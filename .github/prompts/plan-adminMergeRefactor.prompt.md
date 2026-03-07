# Plan: Refactor Admin + Merge into Unified Admin Section

## Summary
Break the monolithic `mod_admin.R` + standalone `mod_merge.R` into a thin parent wrapper + 6 focused sub-modules, each in its own file. The standalone Merge nav tab is removed. The missing `merge_ensure_tables` is implemented in `logic_sync.R`. testthat unit tests cover project CRUD, merge tables, and publishing.

---

## Decisions (confirmed)
- Admin replaces the commented-out `Administration` tab (value = "Administration") in `ui.R`
- Merge tab absorbed into Admin (standalone Merge `nav_panel` removed from `ui.R` + `server.R`)
- Sync tab dropped from Admin (already has standalone Sync tab)
- Download Logs tab included
- 6 sub-modules + 1 parent wrapper, each in its own file
- `merge_ensure_tables` implemented in `logic_sync.R` (fits existing sync infrastructure)
- Tests: testthat unit tests only (no shinytest2)

---

## Phase 1 — Implement `merge_ensure_tables` in `logic_sync.R`

Add `merge_ensure_tables(con)` to `R/logic_sync.R`. It must:
- Ensure `master` database is attached (or already is)
- CREATE SCHEMA IF NOT EXISTS: `master.admin`, `master.staging`, `master.core`
- CREATE TABLE IF NOT EXISTS: `master.admin.merge_requests`
- CREATE TABLE IF NOT EXISTS: `master.admin.merge_conflicts`
- CREATE TABLE IF NOT EXISTS: `master.staging.sample_env`, `sample_su`, `sample_veg`
- CREATE TABLE IF NOT EXISTS: `master.core.sample_env`, `sample_su`, `sample_veg`

Schema mirrors what `setup_merge_db()` already uses in `tests/testthat/test-mod_merge.R`, with full columns including `su_record_count` and `compliance_report` on `merge_requests`.

---

## Phase 2 — Create 6 sub-module files

### 2a. `R/mod_admin_projects.R`
- `mod_admin_projects_ui(id)`: `layout_sidebar` with `proj_select` dropdown + New Project button + project form (id, title, coord agency, start/end dates, notes, Save/Delete)
- `mod_admin_projects_server(id, state, con)`: `update_proj_list()`, `observeEvent(proj_select/new/save/del)`
- Extracted from `mod_admin.R` § 1 (Project Metadata Logic)
- Permission guards: `write:all` or `manage:projects`

### 2b. `R/mod_admin_codes.R`
- `mod_admin_codes_ui(id)`: `layout_sidebar` with `code_list_select` + inline DT editor + Add Row + Save All
- `mod_admin_codes_server(id, state, con)`: `observe` list names from `lists.USysTableOfLists`, DT cell edit, add row, transactional save (DELETE + INSERT per list)
- Extracted from `mod_admin.R` § 2 (Code Maintenance)
- Permission guards: `manage:codes` or `write:all`

### 2c. `R/mod_admin_master.R`
- `mod_admin_master_ui(id)`: internal `navset_card_tab` with:
  - "Master Site Units" — `layout_sidebar` with level filter, DT, Add Row, Save
  - "Master Audit" — `layout_sidebar` with filters, DT, pagination, export
- `mod_admin_master_server(id, state, con)`: all `master_*` and `master_audit_*` handlers
- Extracted from `mod_admin.R` § 3 + Master Audit section
- Calls: `fetch_master_audit_entries`, `get_master_table`

### 2d. `R/mod_admin_audit.R`
- `mod_admin_audit_ui(id)`: `layout_sidebar` with project/plot/table/date filters, DT, pagination, export
- `mod_admin_audit_server(id, state, con)`: `observe` for table choices, `renderDT`, pagination, CSV export
- Extracted from `mod_admin.R` § 4 (Audit Log)
- Calls: `fetch_audit_entries`, `audit_table_exists`, `audit_table_name_col`

### 2e. `R/mod_admin_merge.R`
- `mod_admin_merge_ui(id)`: identical layout to current `mod_merge_ui` (card with request selector, compliance, conflicts, diffs)
- `mod_admin_merge_server(id, state, con)`: identical logic to `mod_merge_server` — `refresh_requests()`, compliance gating, conflict resolution, approve/reject
- Depends on `merge_ensure_tables(con)` (Phase 1)
- Permission gates: `approve:merge_requests`
- `mod_merge.R` is kept but **unwired** (not sourced in main boot path after this change)

### 2f. `R/mod_admin_publishing.R`
- `mod_admin_publishing_ui(id)`: internal `navset_card_tab` with:
  - "Publishing" — `layout_sidebar` with out dir, project multi-select, formats, lumping/public flags, Publish + Refresh buttons; registry table
  - "Download Logs" — `layout_sidebar` with user/dataset/format/status/date filters, Refresh, Export CSV; DT
- `mod_admin_publishing_server(id, state, con)`: all `publish_*` + `download_*` handlers
- `publish_panel_ui` and `download_panel_ui` helper functions move here
- Permission gates: `publish_rds`, `view_download_logs`

---

## Phase 3 — Rewrite `mod_admin.R` as thin wrapper

`mod_admin_ui(id)`:
```r
page_fillable(
  card(
    full_screen = TRUE,
    navset_card_tab(
      nav_panel("Project Management", mod_admin_projects_ui(ns("projects"))),
      nav_panel("Code Maintenance",   mod_admin_codes_ui(ns("codes"))),
      nav_panel("Master Site Units",  mod_admin_master_ui(ns("master"))),
      nav_panel("Audit Log",          mod_admin_audit_ui(ns("audit"))),
      nav_panel("Merge Review",       mod_admin_merge_ui(ns("merge"))),
      nav_panel("Publishing",         mod_admin_publishing_ui(ns("publishing")))
    )
  )
)
```

`mod_admin_server(id, state, con)`:
```r
mod_admin_projects_server("projects", state, con)
mod_admin_codes_server("codes",       state, con)
mod_admin_master_server("master",     state, con)
mod_admin_audit_server("audit",       state, con)
mod_admin_merge_server("merge",       state, con)
mod_admin_publishing_server("publishing", state, con)
```

No logic of its own.

---

## Phase 4 — Wire `ui.R` and `server.R`

### `ui.R`
- Remove lines 98–100 (standalone Merge `nav_panel`)
- Uncomment lines 103–105 (Administration `nav_panel`)

### `server.R`
- Comment out line 711: `mod_merge_server("merge", state, con)`
- Uncomment line 682: `mod_admin_server("admin", state, con)`

### `global.R`
Add `source()` calls for all 6 new files (before `mod_admin.R`):
```r
source("R/mod_admin_projects.R")
source("R/mod_admin_codes.R")
source("R/mod_admin_master.R")
source("R/mod_admin_audit.R")
source("R/mod_admin_merge.R")
source("R/mod_admin_publishing.R")
```

---

## Phase 5 — Tests (testthat unit)

### `tests/testthat/test-mod_admin_projects.R`
- Setup: in-memory DuckDB with `USysProjectMetadata` table
- Test: insert new project → row exists
- Test: update project title → reflected in query
- Test: delete project → row gone
- Test: duplicate project ID → error handled gracefully

### `tests/testthat/test-mod_admin_merge.R`
- Setup: `setup_merge_db()` (reuse pattern from `test-mod_merge.R`)
- Test: `merge_ensure_tables(con)` — all required tables exist after call
- Test: `merge_ensure_tables(con)` — idempotent (call twice, no error)
- Test: `merge_request_unresolved_conflict_count` returns 0 for fresh request
- Test: `merge_request_resolve_conflict` sets resolution correctly
- Test: approve blocked when unresolved conflicts > 0

### `tests/testthat/test-mod_admin_publishing.R`
- Setup: temp output dir + minimal `USysProjectMetadata`
- Test: `publish_rds` creates output file for a project
- Test: empty project list → early return (no crash)
- Test: empty formats list → early return (no crash)
- Test: registry CSV is created and readable after publish
- Test: permission guard returns FALSE for unauthenticated state

---

## Files to modify / create

| File | Action |
|------|--------|
| `R/mod_admin.R` | Rewrite as thin nav wrapper |
| `R/mod_merge.R` | Keep, unwire (not sourced in boot) |
| `R/logic_sync.R` | Add `merge_ensure_tables(con)` |
| `ui.R` | Remove Merge tab, uncomment Administration tab |
| `server.R` | Swap module calls |
| `global.R` | Source all 6 new sub-module files |
| NEW `R/mod_admin_projects.R` | Create |
| NEW `R/mod_admin_codes.R` | Create |
| NEW `R/mod_admin_master.R` | Create |
| NEW `R/mod_admin_audit.R` | Create |
| NEW `R/mod_admin_merge.R` | Create |
| NEW `R/mod_admin_publishing.R` | Create |
| NEW `tests/testthat/test-mod_admin_projects.R` | Create |
| NEW `tests/testthat/test-mod_admin_merge.R` | Create |
| NEW `tests/testthat/test-mod_admin_publishing.R` | Create |

---

## Verification checklist
- [ ] `source("R/mod_admin.R")` — no errors
- [ ] `devtools::test(filter = "mod_admin")` — all new tests pass
- [ ] Existing `test-mod_merge.R` still passes (logic_sync.R not broken)
- [ ] App loads → Administration tab opens with all 6 sub-tabs
- [ ] Merge tab no longer appears in main nav
- [ ] Merge Review sub-tab loads pending requests (with cloud attached)
- [ ] Approve/reject a merge request in Merge Review sub-tab

---

## Scope boundaries
- No new features beyond what currently exists
- Sync tab intentionally excluded from Admin (standalone tab covers it)
- `mod_merge.R` is not deleted — only unwired
- Master Audit and Audit Log remain in Admin
