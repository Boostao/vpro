# Plan: mod_sync UI — Badges + GitHub-style Diff Cards

**Goal**: Two improvements to `R/mod_sync.R` + `R/logic_sync.R`:
1. Yellow/green count badges on accordion section headers
2. GitHub-style diff cards showing actual changed field values (before → after for updates)

**User decisions**:
- Layout: Record cards (GitHub commit style)
- Before/after: YES — always fetch from master.core (sync is cloud-only)
- Fields shown: Key + modified fields only (PK always, then only fields that differ)

---

## Phase 1 — Backend: `sync_get_change_detail()`

Add to `R/logic_sync.R` (after section 5):

Function signature:
```
sync_get_change_detail(con, cfg, project_id = NULL, max_rows = 50L)
```

Logic:
1. Check `DBI::dbExistsTable` + `local_modified_utc` column exists (early return list())
2. Build project filter same as `sync_get_local_changes()` (sanitize pid_safe)
3. Fetch dirty local rows: `SELECT * FROM "<Local>" WHERE local_modified_utc IS NOT NULL AND <proj_filter> LIMIT max_rows`
4. Fetch matching master.core rows if `sync_cloud_connected(con)`: `SELECT * FROM master.core.<pg> WHERE CAST("<pk>" AS TEXT) IN (...)`
5. Build core_lookup = named list keyed by pk_value from core rows
6. For each local row:
   - Determine change_type: "insert" if no matching core row, else "update"
   - local_data = as.list(row) minus local_modified_utc
   - core_data = as.list(core_lookup[[pk_val]]) or NULL
7. Return list of records: list(pk_value, change_type, local_data, core_data)

Security: use same `gsub("[^A-Za-z0-9_-]", "", ...)` sanitization for pid

## Phase 2 — UI: Accordion with reactive badge titles in `mod_sync_ui()`

Change each `accordion_panel` title from a static `tagList` to a `div` containing:
- The icon + label text
- `uiOutput(ns("badges_site"))` / `badges_soil` / `badges_veg` / `badges_project`

Replace all 9 `DT::dataTableOutput(ns("tbl_*_changes"))` with `uiOutput(ns("cards_*"))`.

Add `tags$style` block with diff card CSS (green left border for insert, yellow for update).

Remove `tags$p` subtitles (table names visible in cards themselves).

### CSS to add (inline in mod_sync_ui as tags$style)

```css
.sync-diff-card { border-left: 4px solid #ccc; margin-bottom: 10px; border-radius: 4px; background: #fff; }
.sync-diff-card.sync-insert { border-color: #43893e; }
.sync-diff-card.sync-update { border-color: #f9ca54; }
.sync-diff-header { padding: 7px 12px; font-size: 0.82em; font-weight: 600; display: flex; align-items: center; gap: 8px; }
.sync-diff-card.sync-insert .sync-diff-header { background: #edf7ea; }
.sync-diff-card.sync-update .sync-diff-header { background: #fef9ec; }
.sync-diff-body { padding: 4px 0; }
.sync-diff-row { display: grid; grid-template-columns: 160px 1fr; font-size: 0.8em; padding: 2px 12px; }
.sync-diff-row.changed { grid-template-columns: 160px 1fr auto 1fr; }
.sync-diff-field { color: #666; font-family: monospace; }
.sync-val-before { font-family: monospace; background: #fff3cd; padding: 1px 4px; border-radius: 2px; }
.sync-val-after  { font-family: monospace; background: #d4edda; padding: 1px 4px; border-radius: 2px; }
.sync-val-new    { font-family: monospace; background: #d4edda; padding: 1px 4px; border-radius: 2px; }
.sync-diff-arrow { color: #888; padding: 0 6px; }
```

## Phase 3 — Server: Badge count renders

Add helper `.section_counts(pg_names)` → reactive returning `c(insert=N, update=N)` from `reactive_changes()`.
Add helper `.render_badges(counts_rv)` → `renderUI` emitting `span.badge` elements:
- Yellow `#f9ca54 / color:#222` for updates ← bcgov warning color
- Green `#43893e / color:#fff` for inserts ← bcgov success color
- **Only appear when count > 0**

Wire: `output$badges_site <- .render_badges(...)` for each of the 4 sections.

### Badge color reference (bcgov theme variables)
- `warning: #f9ca54` — updates
- `success: #43893e` — inserts

## Phase 4 — Server: Diff card renders

Add `reactive_all_details` — calls `sync_get_change_detail()` for every table with dirty rows, returns named list keyed by `pg_name`.

Add `.build_diff_card(record, pk)` helper:
- **Insert** card: green header (`INSERT` badge + PK value), then `+ field: value` rows for non-null non-PK fields
- **Update** card: yellow header (`UPDATE` badge + PK value), then `field | before → after` rows for only fields that differ between `local_data` and `core_data`

Add `.render_cards_output(pg_name, cfg)` that wires each `output$cards_<pg>` to a `renderUI` producing cards from `reactive_all_details()`.

Replace the old `.render_changes()` helper and its 9 call sites.

---

## Files to modify
- `R/logic_sync.R` — add `sync_get_change_detail()` function (after section 5)
- `R/mod_sync.R` — replace accordion titles, replace DT outputs, add CSS, new badge + card server logic

## Files NOT modified
- `server.R`, `global.R`, `ui.R` — no changes needed
- `dev/app_sync.R` — no changes (sources mod_sync.R automatically)

---

## Verification
1. Run `shiny::runApp("dev/app_sync.R")` from workspace root
2. Scenario 1 (Env inserts) → Site section shows green badge "3 new", cards show green insert cards with PKs
3. Scenario 2 (Env updates) → Site section shows yellow badge "2 updated", cards show update diffs
4. No changes → badges hidden, "No changes" placeholder shown
5. Reset → badges disappear, cards empty
6. MR tab still functional (not changed)

---

## Open questions / further refinements
1. **Max rows guard**: `sync_get_change_detail()` caps at 50 rows per table by default. Should this be configurable or raised?
2. **NULL/NA display**: Empty or NA fields are hidden in cards. If all update fields match core, card shows "no field differences detected" — acceptable?
3. **Field name display**: Raw column names are used (e.g., `plotnumber`, `elev_m`). No label mapping exists yet — acceptable for now?
4. **Accordion open state**: Currently `open = FALSE`. Should any section auto-open when it has changes?
5. **Card count cap UX**: When a table hits 50 rows, show a "… and N more rows not shown" footer on the section?
