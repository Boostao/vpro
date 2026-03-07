# Plan: mod_sync — Field User Sync Module

## TL;DR
Create a new `mod_sync.R` Shiny module with a top-level "Sync" nav tab. It shows local changes (GitHub Desktop-style), pull/push buttons, a full-blocking conflict modal, and a merge-request history panel. Three new helper functions go in `logic_sync.R`. Wire into `ui.R` and `server.R`. Add tests.

---

## Phase 1: Logic Helpers (logic_sync.R)

Add three new exported functions to `R/logic_sync.R`:

### 1a. `sync_get_local_changes(con, project_id = NULL)`
- Returns named list: `$env`, `$su`, `$veg` — each a data.frame with a `change_type` column ("insert" | "update")
- Logic:
  - **insert**: `local_modified_utc IS NOT NULL AND master_row_version IS NULL` (never pulled from master)
  - **update**: `local_modified_utc IS NOT NULL AND master_row_version IS NOT NULL` (pulled before, then edited)
  - Filter by `project_id` if supplied
  - Gracefully returns empty data.frames if tables/columns don't exist
- NOTE: delete display deferred (no delete log in current schema)

### 1b. `sync_count_incoming(con, project_id = NULL)`
- Returns named list: `$env`, `$su`, `$veg` (integer counts each), `$available` (logical)
- Counts rows in `master.core.*` with `last_modified_utc > last pull watermark` for this project
- Returns `available = FALSE` (all counts 0) when cloud not attached — no error thrown
- Uses `sync_cloud_connected()` check before querying

### 1c. `sync_get_user_merge_requests(con, submitter, show_approved = TRUE, show_rejected = TRUE)`
- Returns data.frame of merge requests from `master.admin.merge_requests`
- Filtered by `submitter_name = submitter` (or submitter_user_id via auth join if available)
- Columns: id, project_id, submitted_utc, status, env_record_count, su_record_count, veg_record_count, review_notes, reviewed_utc
- Returns empty df if cloud not attached
- Applies `show_approved`/`show_rejected` filter args

---

## Phase 2: New Module `R/mod_sync.R`

### mod_sync_ui(id)
Layout: `bslib::navset_card_tab()` with two tabs:

**Tab 1: "Changes"** (default)
- Top row: project badge, pull-count badge, Pull button, Push button, Refresh button
- Pull button label: "Pull (N changes)" where N is computed on tab open
- Push button: disabled if no local changes or unresolved conflicts
- Three accordions (bslib::accordion): "Environment", "Site Units", "Vegetation"
  - Each contains a DT table with row background coloring (green = insert, yellow = update)
  - If no changes: shows "No local changes."
- Status text output (pull/push results)

**Tab 2: "Merge Requests"**
- Toggle checkboxes: "Hide approved", "Hide rejected"
- DT table: id, project, submitted date, status badge, record counts, review notes
- Row click → show detail panel below table (env/su/veg counts, reviewer, review notes)
- Refresh button

### mod_sync_server(id, state, con)
Key reactives and observers:

**Conflict modal (global blocking)**:
- `observe()` on startup + `observeEvent(state$SyncVersion, ...)` — checks `sync_count_local_conflicts()`
- If > 0 conflicts: `showModal(conflict_modal_ui(ns))` — `easyClose = FALSE`
- Inside modal: DT of conflicts + keep_local / accept_master buttons
- After each resolution: re-check count; when 0 → `removeModal()`

**Changes panel**:
- `reactive_changes`: invalidated by `SyncVersion` or Refresh — calls `sync_get_local_changes()`
- `reactive_incoming`: invalidated on tab open or Refresh — calls `sync_count_incoming()`
- Update pull button label with incoming count

**Pull handler** (`observeEvent(input$sync_pull, ...)`):
- Call `sync_pull(con, project_id, tables = c("env","su","veg","lists"))`
- Increment `state$SyncVersion`
- If conflicts detected → auto-trigger conflict modal (via the existing conflict observer)
- Show result in status output

**Push handler** (`observeEvent(input$sync_push, ...)`):
- Guard: abort if `sync_count_local_conflicts() > 0`
- Call `sync_push(con, project_id, submitter = state$User)`
- Increment `state$SyncVersion`
- On success: switch to "Merge Requests" tab via `bslib::nav_select(session, "sync_tabs", "merge_requests")`
- Show result in status output

**Merge requests panel**:
- `reactive_mrs`: invalidated by push success + SyncVersion + Refresh
- Calls `sync_get_user_merge_requests(con, state$User, show_approved = !input$hide_approved, show_rejected = !input$hide_rejected)`

---

## Phase 3: Wiring

### ui.R
Add `bslib::nav_panel("Sync", mod_sync_ui("sync"))` to the main `page_navbar()` — after the "Upload" tab, before "Merge"

### server.R
Add `mod_sync_server("sync", state, con)` alongside the other module init calls

---

## Phase 4: Tests

### tests/testthat/test-mod_sync.R (new file)
Test the three new logic helpers using temporary DuckDB (same pattern as test-logic_sync.R):
- `sync_get_local_changes()`: empty tables, insert-only, update-only, mixed, project filter
- `sync_count_incoming()`: no cloud → returns available=FALSE; with mock master → correct counts
- `sync_get_user_merge_requests()`: no cloud → empty df; with mock → filters by submitter, status toggles

---

## Phase 5: Dev Test App (`dev/app_sync.R`)

Minimal Shiny app, no global.R required. Same bootstrap as `dev/app_auth_status.R`.
Sources: `db_connections.R`, `logic_auth.R`, `logic_sync.R`, `logic_state.R`, `mod_auth.R`, `mod_sync.R`
Auto-logs in as guest on startup. Layout: `page_sidebar()` with sidebar (scenarios) + main (`mod_sync_ui("sync")`).

**Scenarios (sidebar buttons)**:

1. `btn_scenario_inserts` — Insert 3 fake `Env` rows (`plot_number` prefix `DEV_TEST_`) with `local_modified_utc = now()`, `master_row_version = NULL` → appear as **green inserts** in Changes panel

2. `btn_scenario_updates` — Set `local_modified_utc = now()` on 2 existing `Env` rows (keep `master_row_version`) → appear as **yellow updates** in Changes panel

3. `btn_scenario_conflict` — Insert a row into `sync.conflict_queue` for an existing (or fake `DEV_TEST_`) plot → **conflict blocking modal fires**

4. `btn_scenario_mrs` — Insert 3 fake `master.admin.merge_requests` rows (pending_review / merged / rejected) with `submitter_name = state$User` — **requires cloud attached**

5. `btn_scenario_reset` — DELETE all rows with `plot_number LIKE 'DEV_TEST_%'` from local tables + `sync.conflict_queue`; also deletes fake MRs if cloud present

Each scenario shows a `showNotification()` toast confirming what was injected (or a "requires cloud" warning for scenario 4).
All scenario server code clearly marked `# DEV ONLY`.

---

## Relevant Files
- `R/logic_sync.R` — add 3 helper functions (append to bottom)
- `R/mod_sync.R` — new file (full module)
- `ui.R` — add nav_panel entry
- `server.R` — add module server call
- `tests/testthat/test-mod_sync.R` — new test file
- `dev/app_sync.R` — new dev test app

## Verification
1. Source smoke: `source("R/logic_sync.R")` + `source("R/mod_sync.R")` — no errors
2. Conflict modal: introduce a row in `sync.conflict_queue`, launch app → modal appears on any tab
3. Changes panel: manually dirty a row (`local_modified_utc = now()`), open Sync tab → row appears with correct color
4. Pull: connect cloud, click Pull → status updates, watermarks updated, `state$SyncVersion` increments
5. Push: click Push → navigates to Merge Requests tab, new MR appears in list
6. Run `testthat::test_file("tests/testthat/test-mod_sync.R")` — all pass

## Decisions
- Delete display deferred (no delete log in schema); only insert and update shown
- Changes display uses `local_modified_utc` dirty flag (works offline and online)
- Conflict modal is `easyClose = FALSE` to truly block the user
- `mod_merge.R` (admin merge review) is NOT changed — separate concern
- Merge request list shows user's own requests only (filtered by `submitter_name`)
- Pull count badge computed on tab open + refresh (not a timer)

## Out of Scope
- Admin-facing merge approval UI (`mod_merge.R`)
- Delete row tracking (no delete log in schema)
- Cloud conflict resolution (admin-only in `mod_merge.R`)
- Snapshot/parquet export
