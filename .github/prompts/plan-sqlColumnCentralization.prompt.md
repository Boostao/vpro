# Plan: Centralize SQL Column Definitions & Query Helpers

## TL;DR
Create a centralized metadata registry (`R/schema_columns.R`) defining standard column sets for each table group (env, site, veg, lists, soils, metadata), then add lightweight query helpers (`R/query_helpers.R`) that eliminate duplication and make column maintenance a single point of reference. Refactor the top 5 duplicated query patterns across 5 files. No major breaking changes, backward compatible where possible.

## Steps

### Phase 1: Foundation (Metadata & Helpers)

1. Create `R/schema_columns.R` with centralized column metadata:
   - Organize by table group: `env_cols`, `site_cols`, `veg_cols`, `lists_cols`, `soils_cols`, `metadata_cols`
   - For each table: define both "base" columns (minimal essential) and "full" columns (all typical selects)
   - Use R lists or data structure that's easy to reference: `list(table_name = list(base = c(...), full = c(...), insert = c(...)))`
   - Include special column sets: veg layers, species attributes, site hierarchies, metadata fields
   - Document the source of truth — what each column represents and why it's included

2. Create `R/query_helpers.R` with utility functions:
   - `sql_select()` — builds SELECT clause from column set name (param: table_group, column_set)
   - `sql_columns()` — returns raw column vector (used in paste/sprintf)
   - `sql_where()` — simple WHERE clause builder for common patterns (PlotNumber IN, ProjectID =, etc.)
   - `sql_insert_scaffold()` — generates (col_list) VALUES (?) / INSERT INTO scaffold
   - Mark all functions with clear comments explaining which file(s) they'll replace

### Phase 2: Refactor High-Impact Duplicates (5 Files)

3. Refactor repeated "veg layer" query pattern (appears in 5 files):
   - `logic_reports_veg.R` (lines 159, 201)
   - `logic_venus_export.R` (line 484)
   - `logic_excel_export.R` (line 201)
   - `logic_report_export.R` (line 488)
   - Replace with: `sql_select("veg", "veg_base")` inside sprintf/paste0 call

4. Refactor repeated "site unit lookup" pattern (appears in 3 files):
   - `logic_report_export.R` (lines 495, 590, 500, 595)
   - `logic_compliance.R` (similar SiteUnit/SiteSeries patterns)
   - Replace with: `sql_select("site", "site_series")` helper

5. Refactor repeated "species list" query pattern (appears in 3 files):
   - `logic_reports_veg.R` (line 204)
   - `logic_excel_export.R` (line 263)
   - `logic_venus_export.R` (similar patterns)
   - Replace with: `sql_select("lists", "species_full")` helper

6. Refactor "SELECT * FROM Sample_Env WHERE PlotNumber IN" pattern (appears 4 times):
   - `logic_report_export.R` (lines 319, 422, 488, 583)
   - Choice: either keep `SELECT *` (for simplicity) OR use `sql_select("env", "full")`, document tradeoff in comments

7. Refactor `logic_sync.R` list table sync (lines 842, 855-856):
   - Replace existing sprintf column-building logic with `sql_columns()` helper for consistency
   - Already uses dynamic column pattern — simplify by centralizing column list reference

### Phase 3: Testing & Validation

8. Smoke test after each refactor:
   - Reload `R/` (source modified files)
   - Verify no syntax errors in generated queries
   - Spot-check 2 refactored queries by printing `sprintf(...)` output manually
   - Run targeted app test (e.g., open a project, trigger a report export, check data matches baseline)

9. Update documentation:
   - Add comment block in `schema_columns.R` explaining the metadata structure
   - Add comment in `query_helpers.R` mapping each helper to the files/line numbers it replaces
   - Update `R/` directory README (if exists) or add a brief note in `global.R` about the new layer

### Phase 4: Cleanup & Future Guidance

10. (Optional) Create a brief "Column Naming & Maintenance" guide in `/memories/repo/` documenting:
    - How to add a new column to a table (update `schema_columns.R`, then refactored code auto-picks it up)
    - How to use `sql_select()` in new queries
    - Why SELECT * was kept/deprecated and when to override

## Relevant Files

- **New files to create:**
  - `R/schema_columns.R` — metadata registry for all table columns
  - `R/query_helpers.R` — lightweight query builder functions

- **Files to refactor (high priority):**
  - `logic_reports_veg.R` — 2 veg queries (lines 159, 201 + 204 for species)
  - `logic_report_export.R` — 4 env queries (lines 319, 422, 488, 583), 4 site queries (lines 495, 590, 500, 595)
  - `logic_venus_export.R` — veg + metadata patterns (lines 416, 484)
  - `logic_excel_export.R` — veg + species patterns (lines 201, 206, 263)
  - `logic_sync.R` — list table sync column building (lines 842, 855-856)

## Verification

1. All existing `sprintf()` calls with SELECT clause still produce the same SQL (test with `cat(sprintf(...))`)
2. No null/NA values appear in exported data that weren't there before (spot-check one report export)
3. No lint/compile errors after sourcing `R/schema_columns.R` and `R/query_helpers.R`
4. Refactored functions produce identical query output to the original (diff the SQL string)
5. Performance: no observable slowdown in query execution (manual test: export a project, measure time)

## Decisions

- **Metadata structure:** R list (not data.frame or DBML) — simpler to maintain inline, no external dependency
- **SELECT * strategy:** Keep SELECT * where already used (Sample_Env, Sample_Humus/Mineral), refactor explicit hardcoded columns to use helpers. Rationale: sample data tables are schema-stable, lists/veg are frequently added to, so explicit columns on lists/veg reduce headaches.
- **Backward compatibility:** Helpers are additive; old code continues to work. Refactored code uses new helpers but doesn't change query semantics.
- **Scope:** Does NOT include parameterized columns (that's a later enhancement). Does NOT touch WHERE/ORDER BY clauses (helpers are SELECT-focused for now).

## Further Considerations

1. **Schema evolution:** If a column is added to Sample_Veg tomorrow, the process is: (a) update `schema_columns.R`, (b) any code using `sql_select("veg", "full")` auto-picks it up. Document this in the guide.
2. **DuckDB vs Postgres:** Column lists are identical (you confirmed parity), so helpers work for both. No DB-specific branching needed.
3. **Future: parameterized columns** — once this layer is stable, consider moving to a query builder (e.g., `dbplyr` style) for even safer column handling. This is out of scope for now.
