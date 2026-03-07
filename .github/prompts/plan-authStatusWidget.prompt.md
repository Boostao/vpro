# Plan: `mod_auth_status` — Auth State Widget

## TL;DR
Reactive navbar widget (no polling) that reflects live auth + sync state.
Driven purely by reactive state variables — no `reactiveTimer`.
Two strictly different sync info modes depending on cloud availability.

---

## Files
- `R/mod_auth_status.R` — create (new module)
- `dev/app_auth_status.R` — create (new `dev/` folder, standalone test app)
- `R/logic_auth.R` — add `state$SyncVersion <- 0L` to `auth_init_state()`
- `ui.R` / `server.R` — wiring deferred to a separate block

---

## Phase 0 — State addition (`R/logic_auth.R`)

Add `state$SyncVersion <- 0L` to `auth_init_state()`.

This is an integer invalidation counter. Any sync operation (push complete, pull complete) increments it to force the widget to re-render. No polling needed — the widget reacts to this like any other reactive value.

---

## Phase 1 — Module (`R/mod_auth_status.R`)

### Signature
```r
mod_auth_status_ui(id)
mod_auth_status_server(id, state, con)
# returns: reactive() signalling "auth" | "sync" | NULL on button clicks
```
The returned reactive is a navigation signal. The parent app observes it and calls `nav_select()`. Keeps the module decoupled from routing.

### Reactive triggers (no polling)
Reacts automatically when any of these change:
- `state$AuthAuthenticated`
- `state$AuthRole`
- `state$AuthUser`
- `state$SyncVersion`

### Badge — 3 visual states
| State | Style | Icon | Label |
|-------|-------|------|-------|
| Offline | `badge rounded-pill bg-secondary` (muted grey) | wifi-slash | "Offline" + `actionLink("Sign In")` → nav to Auth tab |
| Online — Guest | `badge rounded-pill bg-success` (green) | cloud | email |
| Online — Admin | `badge rounded-pill bg-primary` (blue) | user-shield | email |

Online/offline is determined by `is_cloud_connected(con)` checked inside `renderUI` (reactive, not polled — re-runs whenever `state$AuthAuthenticated` changes, which is exactly when the cloud attach/detach happens).

### Sync line — always visible, content differs by online state

**Offline** (local DuckDB only — cannot query master):
- Show: `"Last pull: X ago"` from `sync_get_watermark(con, "env", "pull")` (NULL → "never")
- No count — we have no way to know what master has without connecting
- Show: `"Sync →"` `actionLink` → nav to Sync tab

**Online** (cloud PG attached as `master`):
- Show: `"↓ N behind · Last pull: X ago"`
  - N = rows in `master.core.{Env, SU, Veg}` with a modified timestamp > `last_pull_utc` watermark
  - Last pull time from `sync_get_watermark(con, "env", "pull")`
- Show: `"Sync →"` `actionLink` → nav to Sync tab

**Behind-count query** (online only, inside `renderUI`, wrapped in `tryCatch` — falls back to omitting the count):
```sql
-- Run once per table, sum the counts
-- Exact timestamp column TBD at coding time (read master schema)
SELECT COUNT(*) FROM master.core."Env" WHERE <modified_col> > ?
-- + SU + Veg
```
> **Open item**: confirm the exact timestamp column on `master.core.Env/SU/Veg` that tracks last modification (e.g. `updated_at`, `modified_utc`, derived from `row_version` sequence). Read master schema at coding time.

---

## Phase 2 — Standalone test app (`dev/app_auth_status.R`)

### Minimal dependencies — no `global.R`
Sources only:
- `R/logic_auth.R`
- `R/logic_sync.R`
- `R/db_connections.R`
- `R/mod_auth.R`
- `R/mod_auth_status.R`

### Layout
```r
page_navbar(
  id = "main_nav",
  nav_panel("Auth",  mod_auth_ui("auth")),
  nav_panel("Sync",  p("Sync page — coming soon")),
  navbar_options = navbar_options(
    collapsible = FALSE,
    ...   # widget placed here
  )
)
```

### Wiring
```r
nav_trigger <- mod_auth_status_server("auth_status", state, con)
observe({
  dest <- nav_trigger()
  req(!is.null(dest))
  nav_select("main_nav", selected = dest)
})
```

### Sync schema init
`sync_init(con)` called at startup so `sync.watermarks` exists and the offline last-pull path can be tested without a cloud connection.

---

## Verification steps

1. `shiny::runApp("dev/app_auth_status.R")` — loads without errors
2. Offline (no env vars / no cloud):
   - Grey badge, "Sign In" link visible
   - `"Last pull: never"` (first run, no watermark)
3. Set a watermark in console: `sync_set_watermark(con, "env", "pull")` → `"Last pull: just now"` updates without reload
4. Sign in online as guest → green badge, `"↓ N behind"` count appears (N can be 0)
5. Sign in online as admin → blue badge + shield icon
6. Click `"Sync →"` → switches to Sync placeholder tab
7. Click `"Sign In"` (offline state) → switches to Auth tab
8. Increment `state$SyncVersion` in console → widget re-renders (pending count / behind count refreshes)

---

## Decisions

| Decision | Choice |
|----------|--------|
| Polling | None — fully reactive via `state$AuthAuthenticated`, `state$AuthRole`, `state$AuthUser`, `state$SyncVersion` |
| Offline sync info | Last pull timestamp only (can't query master) |
| Online sync info | `"↓ N behind"` from `master.core.*` query + last pull time |
| `state$SyncVersion` | Added to `auth_init_state()` in `logic_auth.R` |
| Navigation pattern | Module returns `reactive()` signal; parent calls `nav_select()` |
| Test app location | `dev/app_auth_status.R` (new `dev/` folder — no prior standard in repo) |
| Main app wiring | Deferred — separate block |
| Bootstrap version | Bootstrap 5 / bslib (`bs_theme(version = 5)`) |
