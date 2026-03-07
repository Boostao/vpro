# Plan: Push-Only Sync Rewrite — All Tables

## TL;DR
Rewrite `logic_sync.R` and `mod_sync.R` to support a push-only sync covering **9 field-editable tables**.
Replace the 3-table hardcoded approach with a table-config-driven engine using dynamic column discovery
(no hardcoded column lists, no missed columns). Remove all pull logic. Add comprehensive tests against
the Docker/test Postgres.

---

## Confirmed decisions (from user Q&A)
- **Push tables (9):** Admin, Env, SU, Humus, Mineral, Other, Veg, Herbarium, Metadata
- **Reference tables excluded:** Lump, Theme, Profile, VegProfile, Hierarchy, Audit — admin-curated, not pushed by field users
- **Conflict handling:** show diff — admin picks `keep_staged` / `keep_core` per field
- **MR granularity:** one push = one MR bundling all dirty tables for a project
- **Local DuckDB:** all tables already exist
- **Pull removed entirely:** no watermarks, no local conflict queue

---

## Key findings
- Current push only handles Env, SU, Veg — and only syncs a tiny column subset (9 of 120+ env columns)
- Current push uses snake_case aliases that don't match local PascalCase OR PG lowercase column names
- Pull logic (~1000 lines) must be removed entirely
- Dynamic column discovery (`information_schema.columns`) eliminates hardcoded column lists and the casing mismatch
- `admin.merge_requests` has hardcoded `env_record_count / su_record_count / veg_record_count` — needs to cover 9 tables
- `admin.merge_conflicts` UNIQUE key uses veg-specific columns (`SpeciesCode`, `LayerCode`) — needs a generic `record_id`
- All 9 staging tables are missing `merge_request_id` — can't link staged rows back to a merge request
- Staging PKs are single-column — prevents the same plot appearing in two different MRs
- `admin.*` tables are defined *after* `staging.*` in the SQL file — FK dependency requires reordering

---

## Pre-step — Fix PostgreSQL schema (`scripts/00_schema_becmaster_test.sql`)

### A. Reorder schema creation
Currently: `audit → lists → core → staging → admin`
Required: `audit → lists → **admin** → core → staging`
(Staging FK `merge_request_id → admin.merge_requests(id)` requires admin to exist first)

### B. Add `merge_request_id` + composite PK to all 9 staging tables

Pattern for each staging table:
```sql
-- BEFORE:
plotnumber TEXT PRIMARY KEY,

-- AFTER:
merge_request_id INTEGER NOT NULL REFERENCES admin.merge_requests(id) ON DELETE CASCADE,
plotnumber TEXT NOT NULL,
CONSTRAINT staging_<table>_pk PRIMARY KEY (merge_request_id, plotnumber),
```

Table-by-table PK changes:
| Staging table   | Old PK      | New composite PK              |
|-----------------|-------------|-------------------------------|
| staging.admin   | `plot`      | `(merge_request_id, plot)`    |
| staging.env     | `plotnumber`| `(merge_request_id, plotnumber)` |
| staging.su      | `plotnumber`| `(merge_request_id, plotnumber)` |
| staging.humus   | `id`        | `(merge_request_id, id)`      |
| staging.mineral | `id`        | `(merge_request_id, id)`      |
| staging.other   | `id`        | `(merge_request_id, id)`      |
| staging.veg     | `id`        | `(merge_request_id, id)`      |
| staging.herbarium | `recid`   | `(merge_request_id, recid)`   |
| staging.metadata| `id`        | `(merge_request_id, id)`      |

### C. `admin.merge_requests` — replace hardcoded 3-table counts with JSONB
```sql
-- REMOVE:
env_record_count INTEGER NOT NULL DEFAULT 0,
su_record_count  INTEGER NOT NULL DEFAULT 0,
veg_record_count INTEGER NOT NULL DEFAULT 0,

-- REPLACE WITH:
record_counts JSONB NOT NULL DEFAULT '{}',
```

### D. `admin.merge_conflicts` — generic row identifier
```sql
-- REMOVE: "PlotNumber", "ProjectID", "SpeciesCode", "LayerCode" columns
-- ADD:    record_id TEXT NOT NULL DEFAULT ''
-- UNIQUE: (merge_request_id, table_name, record_id)
```

### E. Docker restart (destroy volume to re-apply init SQL)
```bash
docker-compose down -v
docker-compose up -d
```

---

## Phase 1 — Infrastructure cleanup (`logic_sync.R`)

1. **Remove** all pull functions:
   `sync_pull`, `.pull_env`, `.pull_su`, `.pull_veg`, `.pull_lists`,
   `sync_count_incoming`, `sync_get_local_conflicts`, `sync_count_local_conflicts`,
   `sync_resolve_local_conflict`, `sync_get_watermark`, `sync_set_watermark`

2. **Simplify `sync_ensure_local_tables()`**: add `local_modified_utc TIMESTAMPTZ DEFAULT NULL`
   to each of the 9 data tables if not already present — no watermark table, no conflict_queue creation

3. **Keep:** `sync_cloud_connected()`, `sync_require_cloud()`

---

## Phase 2 — Table config + generic push engine (`logic_sync.R`)

4. **Define `SYNC_TABLE_CONFIG`** — named list, one entry per table:
   ```r
   list(
     local         = "Env",          # DuckDB PascalCase name
     pg            = "env",          # PostgreSQL lowercase name
     pk            = "plotnumber",   # PK column in PostgreSQL (lowercase)
     project_scope = "direct"        # "direct" | "via_env" | "none"
   )
   ```
   - `direct`: table has its own `projectid` column (Env, Metadata)
   - `via_env`: join through `Env.plotnumber` to scope to a project (SU, Admin, Humus, Mineral, Other, Veg, Herbarium)
   - `none`: no project filter applied (not used for the 9 tables but kept as escape hatch)

5. **Implement `.get_shared_columns(con, local_table, pg_schema, pg_table)`**:
   - Local: `SELECT column_name FROM information_schema.columns WHERE table_name = local_table`
   - Remote: `SELECT column_name FROM master.information_schema.columns WHERE table_schema = pg_schema AND table_name = pg_table`
   - Return: intersection after `tolower()`, excluding sync metadata cols:
     `c("merge_request_id", "changetype", "baserowversion", "rowversion", "lastmodifiedutc", "modifiedby", "local_modified_utc", "submitted_utc", "submitted_by")`

6. **Implement `.push_table(con, cfg, mr_id, submitter, project_id)`**:
   - Get shared columns via `.get_shared_columns()`
   - Build project filter subquery based on `cfg$project_scope`
   - Dirty detection: `local_modified_utc IS NOT NULL`
   - Change type: LEFT JOIN local vs `master.core.{pg}` on PK → 'I' if no core match, 'U' if match
   - Capture `base_row_version = core."rowVersion"` (NULL for inserts)
   - INSERT into `master.staging.{pg}` with all shared cols + `merge_request_id`, `changeType`, `baseRowVersion`, `modifiedBy`
   - Return row count (integer)

7. **Implement `sync_push(con, project_id, submitter)`** (public entry point):
   - `sync_require_cloud(con)`
   - `sync_ensure_local_tables(con)`
   - Auto-resolve `project_id` if NULL (single project in Env)
   - Pre-flight: count dirty rows across all 9 tables; stop if 0
   - `mr_id <- .create_merge_request(con, project_id, submitter)`
   - Loop: call `.push_table()` for each config entry; collect counts
   - Update MR: `record_counts = jsonlite::toJSON(counts)`
   - Return: `list(merge_request_id = mr_id, counts = counts)`

8. **Implement `sync_get_local_changes(con, project_id)`** (used by mod_sync UI):
   - For each of the 9 tables: `SELECT * FROM {local} WHERE local_modified_utc IS NOT NULL [+ project filter]`
   - Return named list keyed by `cfg$pg` name

---

## Phase 3 — Admin/merge workflow (`logic_sync.R`)

9. **Generic `.detect_table_conflicts(con, mr_id, cfg)`** replacing 3 separate helpers:
   - For each UPDATE row in `staging.{pg}`: check `core."rowVersion" > staging."baseRowVersion"`
   - Fetch staged vs core values as JSON blobs
   - Upsert into `admin.merge_conflicts(merge_request_id, table_name, record_id, details)`
   - `record_id` = stringified PK value(s) for the row

10. **Generic `.apply_table(con, mr_id, cfg)`** replacing `.apply_env`, `.apply_su`, `.apply_veg`:
    - Build dynamic UPSERT of staging rows into `core.{pg}` (INSERT … ON CONFLICT DO UPDATE)
    - Skip rows where `admin.merge_conflicts.resolution = 'keep_core'`
    - `resolution IN ('keep_staged', 'dismiss', NULL)` → apply to core

11. **Update `.delete_staging(con, mr_id)`** — iterate over all 9 `cfg$pg` names

12. **Keep (update internals only):**
    `merge_request_get()`, `merge_request_list()`, `merge_request_refresh_conflicts()`,
    `merge_request_get_conflicts()`, `merge_request_unresolved_count()`,
    `merge_request_resolve_conflict()`, `merge_approve_request()`, `merge_reject_request()`

---

## Phase 4 — Simplify `mod_sync.R`

13. **Remove:** pull button, incoming count badge, pull handler, local conflict modal,
    `conflict_keep_local` / `conflict_accept_master` buttons,
    all `sync_count_incoming` / `sync_get_local_conflicts` / `sync_resolve_local_conflict` calls

14. **Update Changes tab** — group 9 tables into accordion panels:
    - Site: Admin, Env, SU
    - Soil: Humus, Mineral, Other
    - Vegetation: Veg, Herbarium
    - Project: Metadata

15. **Update push handler** — display per-table counts from `result$counts`

16. **Keep:** MR tab (list + status + detail), sync status message, Refresh button

---

## Phase 5 — Tests (`tests/testthat/test_sync_push.R`)

17. **Setup helpers:** init local DuckDB with dirty test rows per table; attach test Postgres as `master`

18. **Test: push creates MR + staging rows**
    - Insert dirty rows into local Env, SU, Veg, Humus (mark `local_modified_utc`)
    - Call `sync_push()`
    - Assert: MR exists in `admin.merge_requests` with status `pending_review`
    - Assert: `staging.env / staging.veg / staging.su / staging.humus` have rows with correct `merge_request_id`

19. **Test: admin approve merges to core**
    - After push, call `merge_approve_request()`
    - Assert: `core.env / core.veg` etc. have the pushed rows
    - Assert: MR status = `merged`

20. **Test: conflict detection**
    - Push a row, then manually increment `core."rowVersion"` in Postgres
    - Call `merge_request_refresh_conflicts()`
    - Assert: `admin.merge_conflicts` has 1 unresolved row for that table

21. **Test: conflict resolution**
    - `keep_staged` → verify core gets staged value on approve
    - `keep_core`   → verify core value unchanged after approve

---

## Relevant files
- `R/logic_sync.R` — complete rewrite (~500 lines target vs ~1900 current)
- `R/mod_sync.R` — simplify (~250 lines target vs ~500 current)
- `scripts/00_schema_becmaster_test.sql` — schema fixes (pre-step above)
- `tests/testthat/test_sync_push.R` — new test file

---

## Verification checklist
- [ ] `source("R/logic_sync.R")` — no R errors
- [ ] `docker-compose up -d` + `testthat::test_file("tests/testthat/test_sync_push.R")` — all green
- [ ] Manual: log in, dirty a row, Push → admin panel shows MR with per-table counts
- [ ] Manual: admin approves MR → core updated, MR status = merged

---

## Column name normalization note
Dynamic discovery uses `tolower(column_name)` on both sides. DuckDB (case-insensitive identifiers)
and PostgreSQL (lowercase) align correctly after normalization. No hardcoded column lists needed.
