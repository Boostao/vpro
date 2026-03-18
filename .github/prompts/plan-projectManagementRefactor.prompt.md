# Plan: Project Management Refactor — VPro

## TL;DR
Refactor VPro's project system from a local canonical DuckDB-file mindset to canonical SQLite project files under `data/projects/`, with an in-memory DuckDB session attaching the selected project and the shared companion SQLite databases. The project selector logic moves into a new Shiny module `mod_project.R`. Business logic moves into a new `R/logic_project.R`. `connect_local_db` should manage the in-memory DuckDB session plus attached SQLite shards. Tests are added/updated.

## Architecture Note
This prompt predates the SQLite-shard migration. Read every reference to local project `.duckdb` files or `vpro.duckdb` as superseded by the current local plan:

- Canonical project files are SQLite `.db` files under `data/projects/`
- Shared local companion databases are canonical SQLite `.db` files under `data/`
- DuckDB is the in-memory composition/query layer, not the persisted source of truth

---

## Architecture Decision

**Tables have NO prefix going forward.** The `Sample_` prefix was legacy/old code. Tables in the runtime DuckDB session and in every project SQLite file are named `Env`, `Veg`, `Metadata`, `Humus`, `Mineral`, `SU`, `Admin`, `Audit`, `Herbarium`, `Profile`, `Theme`, `Lump`, `Hierarchy`, `Other`.

`state$CurrProject` is a **filter value** (the `projectid` column inside rows), not a table name prefix.

### Data flow
1. App starts → in-memory DuckDB opens and attaches the canonical shared SQLite databases.
2. User opens `data/projects/MyProject.db` → attach SQLite file → `INSERT INTO Env SELECT * FROM project_alias.Env` (and all other tables) → `state$CurrProject = projectid` → SU dropdown refreshes
3. User works → all writes go directly to `Env`, `Veg`, etc. filtered by `projectid`
4. User saves/closes → `SELECT rows WHERE projectid = ?` written back to project file → `DELETE FROM Env WHERE projectid = ?`

### Prerequisite: Schema Migration (Phase 0)
All existing `Sample_Env`, `Sample_Veg`, `Sample_Metadata` etc. references must be renamed to `Env`, `Veg`, `Metadata` across:
- ~30+ references in `R/logic_*.R` and `R/mod_*.R`
- ~20+ references in `tests/testthat/` test files
- `tests/testthat/helpers.R` schema init
- canonical project SQLite files and any runtime table-creation helpers that still assume `.duckdb`
- `01_build_database.R` if it produces `Sample_*` table names from CSV filenames

This is a large mechanical find-replace task and **must land before** the project management module works. It should be a separate block executed first, but it is listed here as Phase 0 for completeness.

---

## Phases

### Phase 0 — Schema Migration (prerequisite, separate block)
Rename all `Sample_*` table references to unprefixed throughout the codebase:
- In `R/logic_*.R` and `R/mod_*.R`: ~30+ occurrences (`Sample_Env` → `Env`, `Sample_Veg` → `Veg`, `Sample_Metadata` → `Metadata`, etc.)
- In all `tests/testthat/` test files: ~20+ `CREATE TABLE Sample_*` statements
- In `tests/testthat/helpers.R`: update `initialize_test_schema()` to create unprefixed tables
- In `01_build_database.R`: CSV files from Access are named `Sample_Env.csv` etc. — add rename step in build script to strip `Sample_` prefix from table names
- Rename tables in `vpro.duckdb` itself (ALTER TABLE or rebuild)
- In `logic_state.R` > `set_project`: remove `resolve_prefixed_table(con, project_id, "_Metadata")` call; replace with `SELECT * FROM Metadata WHERE projectid = ?`

### Phase 1 — `R/logic_project.R` (new file)
All prefix-based functions from `logic_state.R` become **obsolete and are deleted** (not moved):
- Delete: `discover_prefixes_by_suffix`, `list_project_tables`, `is_valid_project_prefix`, `resolve_prefixed_table`, `list_main_tables`, `create_project_table_set`, `attach_project_table_set`, `unattach_project_table_set`, `create_prefixed_table_from_template`, `attach_prefixed_table`, `unattach_prefixed_table`

New functions in `logic_project.R`:
- `PROJECT_TABLES` — constant: `c("Env", "Veg", "Metadata", "Admin", "Humus", "Mineral", "SU", "Audit", "Herbarium", "Profile", "Theme", "Lump", "Hierarchy", "Other")`
- `list_open_projects(con)` — `SELECT DISTINCT projectid FROM Env ORDER BY projectid`
- `open_project(con, path)` — attach `.duckdb` as alias, detect `projectid` from `Env`, INSERT all rows into main tables, detach, return `projectid`
- `save_project(con, project_id, path)` — create/overwrite project `.duckdb`, create matching schema, INSERT rows `WHERE projectid = ?` from each main table
- `close_project(con, project_id, path = NULL)` — call `save_project` if path given, then `DELETE FROM <table> WHERE projectid = ?` for all `PROJECT_TABLES`
- `new_project(con, project_id, project_title)` — validate uniqueness, `INSERT INTO Metadata (projectid, projecttitle) VALUES (?, ?)`, return `project_id`
- `project_exists(con, project_id)` — `SELECT COUNT(*) FROM Metadata WHERE projectid = ?` > 0

Keep in `logic_state.R`: `set_project` (simplified), `set_su`, state init, all pref helpers.

### Phase 2 — `R/mod_project.R` (new module)
`mod_project_ui(id)` + `mod_project_server(id, state, con)`.

Sidebar UI:
```
[No project open]  OR  [BCGov2025-Alpine]   ← uiOutput reactive label
[Open]  [New]  [Save]                        ← three compact buttons, one row
[Close project]                              ← visible only when project is open
```
- **Open** → modal with textInput for path + Browse button (via `shinyFiles` if available, else plain)
- **New** → modal with Project ID (required, validated) + Project Title (required)
- **Save** → confirm path (defaults to last open path); if unsaved, prompts for path
- **Close** → confirmation dialog; calls `close_project` which saves first

Module stores `current_path` reactiveVal (last opened/saved path) for default in Save.
Module exports `project_changed` reactive that `server.R` observes.

Auto-save on session end: `session$onSessionEnded` triggers `save_project` if project is open + path known.

### Phase 3 — Simplify `connect_local_db`
- Remove `VPRO_MAIN_DB` as a DuckDB-specific concept; if a path override remains, it should point at canonical SQLite files instead.
- Keep auxiliary attachments unchanged
- Add comment: main db starts empty of project data; `open_project` loads rows at runtime

### Phase 4 — Update `server.R`
Remove (~180 lines): all `PROJECT_ACTION_*` constants, `refresh_project_dropdown`, `project_refresh` reactiveVal, all project `observeEvent` handlers.
Add:
- `mod_project_server("project", state, con)`
- `observe({ req(project_mod$project_changed()); refresh_su_dropdown(); refresh_hierarchy_dropdown() })`

### Phase 5 — Update `ui.R`
Replace `selectInput("sel_project", "Project:", choices = NULL)` with `mod_project_ui("project")`.

### Phase 6 — Tests
**New** `tests/testthat/test-logic_project.R`:
- `open_project`: write temp `.duckdb` with `Env` rows → `open_project` → assert rows in main `Env`
- `save_project`: insert rows → `save_project` → reopen file → assert rows in `Env`
- `close_project`: rows in main → `close_project` → rows gone from main `Env`
- `new_project`: call → assert row in main `Metadata`
- `list_open_projects`: insert two projectids → returns both
- Multiple projects open simultaneously (different projectids coexist in main tables)

**Update** `tests/testthat/test-logic_state.R`: remove all tests for deleted prefix functions (they would fail). Keep `set_project`, `set_su`, init tests.

**New** `tests/testthat/test-mod_project.R`: `testServer` tests for open/new/save/close reactive flows.

---

## Files to Create
- `R/logic_project.R`
- `R/mod_project.R`
- `tests/testthat/test-logic_project.R`
- `tests/testthat/test-mod_project.R`

## Files to Modify (Phases 1–6)
- `R/logic_state.R` — delete prefix functions, simplify `set_project`
- `R/db_connections.R` — remove `VPRO_MAIN_DB` env var, add clarifying comment
- `server.R` — remove ~180 lines, add module call
- `ui.R` — swap `selectInput` for `mod_project_ui`
- `tests/testthat/test-logic_state.R` — remove deleted-function tests

## Files to Modify (Phase 0 — schema migration, separate block)
- `R/logic_compliance.R`, `R/logic_excel_export.R`, `R/logic_diagnostic.R`, `R/logic_reports_qc.R`, `R/logic_publish.R`, `R/logic_sync.R`
- `R/mod_site_env.R`, `R/mod_veg_sample.R`, `R/mod_hierarchy.R`, `R/mod_export.R`, `R/mod_import.R`, `R/mod_images.R`, `R/mod_reporting.R`, `R/mod_sync.R`
- `tests/testthat/test-logic_compliance.R`, `test-logic_reports_qc.R`, `test-logic_publish.R`, `test-logic_venus_export.R`, `test-mod_import.R`, others with `Sample_*`
- `tests/testthat/helpers.R`
- `scripts/01_build_database.R`

## Decisions
- Project file format: SQLite `.db`
- Table naming: no prefix, unprefixed (`Env`, `Veg`, `Metadata`, …)
- Access import: deferred stub only
- Required at creation: Project ID + Project Title only
- Auto-save on session end

## Out of Scope
- SU and Hierarchy dropdown refactor (flagged: `sel_su` using `discover_prefixes_by_suffix(con, "_SU")` also becomes broken after Phase 0 — needs its own block to list site units from `SU` table instead)
- `shinyFiles` optional — plain textInput fallback if package unavailable
