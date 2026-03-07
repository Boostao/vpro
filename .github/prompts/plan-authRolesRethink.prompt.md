# Plan: Auth & Roles Rethink

## TL;DR
Replace two PG roles (trust-auth guest + password admin) with one `vpro_app` PG role.
The real auth is R-level (admin.users + bcrypt). A single password-protected PG role is simpler, more secure (removes trust-auth hole), and honest about where permissions actually live.

---

## Core Design

### PostgreSQL side (infrastructure — not R code)
- Single role: `vpro_app` with password
- Permissions: SELECT on core.*/lists.*/audit.*; full CRUD on staging.* and admin.*
- Hard constraint: REVOKE UPDATE, DELETE on audit.logged_actions (append-only)
- Provisioned via scripts (not in runtime R code)
- Env vars: VPRO_PG_APP_USER (default: "vpro_app"), VPRO_PG_APP_PASSWORD

### Application side (in admin.users — unchanged schema)
- `guest` role: identified by email (name optional); app_role = 'guest'; no password hash
- `admin` role: email + bcrypt hash; app_role = 'admin'

### Connection lifecycle
```
App boot       → local DuckDB only (no PG)
Login          → attach_cloud(con) [single call, vpro_app role]
               → verify identity in admin.users (R code)
               → set state
Session        → PG stays attached for whole session
Logout         → detach_db(con, "master") + clear state
onSessionEnded → auto-detach + disconnect
```

---

## Phase 1 — db_connections.R
1. Remove `attach_cloud_as_guest()` and `attach_cloud_as_admin()`
2. Add `attach_cloud(con, alias="master", fail_on_error=TRUE)` reading VPRO_PG_APP_USER + VPRO_PG_APP_PASSWORD
3. Update `global.R` env vars: remove VPRO_PG_GUEST_USER / VPRO_PG_ADMIN_USER / VPRO_PG_ADMIN_PASSWORD; add VPRO_PG_APP_USER / VPRO_PG_APP_PASSWORD

## Phase 2 — logic_auth.R
1. `auth_guest_login(con, state, email, full_name = NULL)` — make full_name optional
   - Email regex validation stays mandatory
   - full_name stored when provided, NULL allowed in DB
   - Admin redirect + inactive check unchanged
2. No other logic changes

## Phase 3 — mod_auth.R
1. Both guest and admin login paths: call `attach_cloud(con)` once (if not already attached), then call the R auth function. Remove the vpro_default bootstrap → re-attach as vpro_admin dance.
2. Guest form: make Full Name field optional (hint: "Optional")
3. Add subtitle "Sign in to enable cloud sync" in the pre-login panel
4. On any auth failure: detach_db(con, "master"); on success: leave attached

## Phase 4 — Delete
1. Delete `R/db_roles.R`
2. Delete `tests/testthat/test-db_roles.R`

## Phase 5 — Tests (test-logic_auth.R + helpers)
1. Update `get_auth_test_con()` and `get_auth_test_con_admin()` in test helpers to both use `attach_cloud()` (no role distinction at connection level)
2. Update `auth_guest_login creates new guest` test: full_name may be NULL
3. Add test: guest login with email only (no name) → succeeds
4. Add test: guest login with email + name → name stored
5. All existing admin tests unchanged (login, change_password, grant_admin)

---

## Relevant Files
- `R/db_connections.R` — replace 2 functions with 1 `attach_cloud()`
- `global.R` — env var update
- `R/logic_auth.R` — `auth_guest_login` full_name optional
- `R/mod_auth.R` — simplify login paths, UI hint
- `R/db_roles.R` — DELETE
- `tests/testthat/test-logic_auth.R` — guest tests + helpers
- `tests/testthat/test-db_roles.R` — DELETE
- `tests/testthat/helpers.R` — `get_auth_test_con*` use attach_cloud

## Out of Scope
- SQL provisioning of vpro_app role (scripts/ concern)
- mod_sync.R auth-gated pull/push UI

---

## Verification
1. Source logic_auth.R, mod_auth.R, db_connections.R — no parse errors
2. App starts, sidebar shows "Sign in to enable cloud sync"
3. Guest login with email only → succeeds
4. Guest login with email + name → succeeds, name stored
5. Admin login unchanged
6. testthat::test_file("tests/testthat/test-logic_auth.R") all pass
