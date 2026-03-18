# Plan: Remove config.yml — env vars + auth-driven PG attach

## TL;DR
Replace all `config::get()`/`R_CONFIG_ACTIVE` usage with env vars. `connect_local_db()` should target the canonical SQLite file paths and build the in-memory DuckDB attachment layer from them. `attach_cloud_db()` reads PG host/port/db from env vars; explicit user/pass as arguments. Auth-driven attach/detach (mod_auth.R) stays the same but no longer needs the config package.

---

## Phase 1 — Rewrite `R/db_connections.R`

**Remove:**
- `environment` param from all four public functions
- All `config::get()` calls
- `read_only` param from `attach_cloud_db` (was never used in ATTACH SQL)

**Add internal helpers:**
```
.pg_host()     → Sys.getenv("PGHOST",        "localhost")
.pg_port()     → as.integer(Sys.getenv("PGPORT", "5432"))
.pg_database() → Sys.getenv("PGDATABASE",    "becmaster")
```

**`connect_local_db()`** — no params; reads canonical SQLite paths from env vars with hardcoded defaults:
- `VPRO_MAIN_DB`     → `data/VPro64.db`
- `VPRO_LISTS_DB`    → `data/VLists.db`
- `VPRO_METADATA_DB` → `data/VMetaData.db`
- `VPRO_USER_DB`     → `data/VUser.db`
- `VPRO_MESSAGES_DB` → `data/VMessageBoard.db`
- `VPRO_PICS_DB`     → `data/pics/VPics.db`

**`attach_cloud_db(con, pg_user, pg_password = NULL, alias = "master", fail_on_error = TRUE)`**
— takes explicit credentials; reads host/port/db from env via helpers above.

**`attach_cloud_as_guest(con, alias = "master", fail_on_error = TRUE)`**
— no env/config; reads `VPRO_PG_GUEST_USER` (default `vpro_default`), calls `attach_cloud_db()`.

**`attach_cloud_as_admin(con, alias = "master", fail_on_error = TRUE)`**
— reads `VPRO_PG_ADMIN_USER` (default `vpro_admin`) and `VPRO_PG_ADMIN_PASSWORD`; stops if password missing.

---

## Phase 2 — Update `server.R`

Remove lines ~38-44 (config load block):
```r
# DELETE:
environment <- Sys.getenv("R_CONFIG_ACTIVE", unset = "default")
cfg <- tryCatch({ config::get(config = environment) }, ...)
```

Change to:
```r
con <- connect_local_db()
```
`environment` variable no longer exists; any downstream reference removed.

---

## Phase 3 — Update `R/logic_publish.R`

`publish_project_dataset()` line ~429:
- Remove `environment = NULL` param
- Change `connect_local_db(environment = environment)` → `connect_local_db()`

---

## Phase 4 — Update `R/logic_sync.R`

`sync_require_cloud()`:
- Remove `allow_attach = TRUE` default → change to `allow_attach = FALSE`
- Remove the `attach_cloud_db(con, alias = alias)` auto-attach path (or guard with a clear error message "Cloud not attached; please log in first.")
- This enforces: sync requires authenticated session, not an implicit attach.

---

## Phase 5 — Update test infrastructure

### `tests/testthat/setup.R`
Replace:
```r
Sys.setenv(R_CONFIG_ACTIVE = "test")
```
With:
```r
Sys.setenv(
  PGHOST                 = "localhost",
  PGPORT                 = "5433",          # docker-compose maps 5433:5432
  PGDATABASE             = "becmaster",
  VPRO_PG_GUEST_USER     = "vpro_default",
  VPRO_PG_ADMIN_USER     = "vpro_admin",
  VPRO_PG_ADMIN_PASSWORD = "admin_password"
)
```

Also update `check_postgres_available()` to use env vars (PGHOST/PGPORT) instead of hardcoded localhost:5433 — they now match anyway, but it's consistent.

### `tests/testthat/helpers.R`
`pg_available()` and `get_test_pg_connection()` / `test_connect_postgres()`:
- Replace hardcoded `host="localhost", port=5433, user="vpro_app", password="testpass"` with env var reads:
  ```r
  Sys.getenv("PGHOST", "localhost")
  as.integer(Sys.getenv("PGPORT", "5433"))
  Sys.getenv("PGDATABASE", "becmaster")
  # vpro_app/testpass still hardcoded — these are docker-compose superuser credentials
  # used only in integration test helpers, not app code
  ```
  Keep `vpro_app:testpass` hardcoded for the test superuser connection (that's intentional and specific to docker-compose, not the app).

### `tests/testthat/test-db_connections.R`
Three calls to `attach_cloud_db(con, environment = "test", ...)` → change to explicit credentials:
```r
attach_cloud_db(con, pg_user = "vpro_app", pg_password = "testpass", alias = "master")
```
(These directly test the raw attach mechanism with the docker superuser.)

Also remove `environment` from `connect_local_db()` calls (there are none in this file, but verify.)

### `tests/testthat/test-logic_publish.R` (line 138)
```r
# BEFORE:
con <- connect_local_db(environment = Sys.getenv("R_CONFIG_ACTIVE", "default"))
# AFTER:
con <- connect_local_db()
```

---

## Phase 6 — Delete `config.yml`

Delete the file. Remove `config` from `renv.lock` via `renv::remove("config")` (or note as follow-up).

---

## Phase 7 — Update deployment/env files

### `.env.example`
Replace `R_CONFIG_ACTIVE=production` section with:
```
PGHOST=db
PGPORT=5432
PGDATABASE=becmaster
VPRO_PG_GUEST_USER=vpro_default
VPRO_PG_ADMIN_USER=vpro_admin
VPRO_PG_ADMIN_PASSWORD=<your-admin-pg-password>
# Optional SQLite path overrides
# VPRO_MAIN_DB=data/VPro64.db
```

### `docker-compose.deploy.yml`
Replace `R_CONFIG_ACTIVE=${R_CONFIG_ACTIVE:-production}` with proper PG env vars.

---

## Files NOT changing
- `R/mod_auth.R` — already calls `attach_cloud_as_guest(con, fail_on_error=TRUE)` and `attach_cloud_as_admin(con, fail_on_error=TRUE)` with no `environment` param → no change needed.
- `R/logic_auth.R` — no config usage at all.
- All other test files — no config references.

---

## Verification
1. `source("R/db_connections.R")` without config package — no errors
2. `connect_local_db()` opens the runtime DuckDB layer in dev with canonical SQLite files present under `data/`, `data/pics/`, and `data/projects/`
3. `server.R` loads and session starts without config::get error
4. In test environment: `docker-compose up -d`, set env vars, run `testthat::test_dir("tests/testthat")` — all tests that were passing before still pass
5. Auth flow: guest login attaches cloud, logout detaches — verify in running app

---

## Decisions
- Keep `PGHOST/PGPORT/PGDATABASE` as standard PG env vars (widely recognised)
- Use `VPRO_PG_*` prefix for app-specific role credentials to avoid collision
- `connect_local_db` takes NO environment argument — DuckDB paths are stable and don't vary by environment, only PG does
- `sync_require_cloud` will NOT auto-attach — this was always wrong design (sync shouldn't implicitly authenticate)
- `renv::remove("config")` is a follow-up step after the code changes are implemented and tested
- `config.yml` is deleted entirely; `tests/README.md` references left for now (docs only, not functional)

---

## Open question
The `vpro_app:testpass` docker-compose superuser credentials are hardcoded in test helpers. Want them as env vars too (`VPRO_TEST_PG_USER` / `VPRO_TEST_PG_PASSWORD`), or keep hardcoded since they're test-infra-only?
