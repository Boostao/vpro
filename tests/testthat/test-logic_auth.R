testthat::context("logic_auth")
source(here::here("tests", "testthat", "setup.R"))
source(here::here("tests", "testthat", "helpers.R"))

# Make test_connect_duckdb visible
if (!exists("test_connect_duckdb")) {
  test_connect_duckdb <- get("test_connect_duckdb", envir = .GlobalEnv)
}

source(here::here("R", "logic_auth.R"))

# Ensure docker-compose PG env vars are set when running this file in isolation
# (setup.R sets these when running via devtools::test(), but not test_file())
if (!nzchar(Sys.getenv("PGPORT")))              Sys.setenv(PGPORT              = "5433")
if (!nzchar(Sys.getenv("PGHOST")))              Sys.setenv(PGHOST              = "localhost")
if (!nzchar(Sys.getenv("PGDATABASE")))          Sys.setenv(PGDATABASE          = "becmaster")
if (!nzchar(Sys.getenv("VPRO_PG_APP_PASSWORD"))) Sys.setenv(VPRO_PG_APP_PASSWORD = "testpass")
if (!nzchar(Sys.getenv("VPRO_PG_APP_USER")))    Sys.setenv(VPRO_PG_APP_USER    = "vpro_app")

# Both guest and admin test connections use the single vpro_app role.
get_auth_test_con <- function() {
  con <- test_connect_duckdb()
  attach_cloud(con, fail_on_error = TRUE)
  con
}

# Alias kept for test clarity; both functions are identical at connection level.
get_auth_test_con_admin <- function() {
  con <- test_connect_duckdb()
  attach_cloud(con, fail_on_error = TRUE)
  con
}

# ---- auth_login (admin) --------------------------------------------------------

testthat::test_that("auth_login authenticates admin by email and password", {
  testthat::skip_if_not_installed("bcrypt")
  con_admin <- get_auth_test_con_admin()
  on.exit(DBI::dbDisconnect(con_admin), add = TRUE)
  DBI::dbExecute(con_admin, "DELETE FROM master.admin.users WHERE email = 'admin@test.local'")
  DBI::dbExecute(con_admin,
    "INSERT INTO master.admin.users (email, full_name, app_role, password_hash, is_active)
     VALUES ('admin@test.local', 'Test Admin', 'admin', ?, TRUE)",
    list(bcrypt::hashpw("secret"))
  )
  con <- get_auth_test_con()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  state <- shiny::reactiveValues()
  auth_init_state(state)
  result <- auth_login(con, state, "admin@test.local", "secret")

  testthat::expect_true(result$ok)
  testthat::expect_true(auth_is_authenticated(state))
  testthat::expect_true(auth_is_admin(state))
  testthat::expect_equal(shiny::isolate(state$AuthUser), "admin@test.local")
  testthat::expect_true("*" %in% shiny::isolate(state$AuthPermissions))
})

testthat::test_that("auth_login rejects wrong password", {
  testthat::skip_if_not_installed("bcrypt")
  con_admin <- get_auth_test_con_admin()
  on.exit(DBI::dbDisconnect(con_admin), add = TRUE)
  DBI::dbExecute(con_admin, "DELETE FROM master.admin.users WHERE email = 'admin@test.local'")
  DBI::dbExecute(con_admin,
    "INSERT INTO master.admin.users (email, full_name, app_role, password_hash, is_active)
     VALUES ('admin@test.local', 'Test Admin', 'admin', ?, TRUE)",
    list(bcrypt::hashpw("correct"))
  )
  con <- get_auth_test_con()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  state <- shiny::reactiveValues()
  result <- auth_login(con, state, "admin@test.local", "wrong")

  testthat::expect_false(result$ok)
  testthat::expect_false(auth_is_authenticated(state))
})

testthat::test_that("auth_login rejects guest accounts", {
  con_admin <- get_auth_test_con_admin()
  on.exit(DBI::dbDisconnect(con_admin), add = TRUE)
  DBI::dbExecute(con_admin, "DELETE FROM master.admin.users WHERE email = 'guest@test.local'")
  DBI::dbExecute(con_admin,
    "INSERT INTO master.admin.users (email, full_name, app_role, is_active)
     VALUES ('guest@test.local', 'A Guest', 'guest', TRUE)"
  )
  con <- get_auth_test_con()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  state <- shiny::reactiveValues()
  result <- auth_login(con, state, "guest@test.local", "anything")

  testthat::expect_false(result$ok)
  testthat::expect_false(auth_is_authenticated(state))
})

# ---- auth_guest_login ----------------------------------------------------------

testthat::test_that("auth_guest_login creates new guest on first visit", {
  con_admin <- get_auth_test_con_admin()
  on.exit(DBI::dbDisconnect(con_admin), add = TRUE)
  DBI::dbExecute(con_admin, "DELETE FROM master.admin.users WHERE email = 'new@guest.com'")
  state <- shiny::reactiveValues()
  auth_init_state(state)
  result <- auth_guest_login(con_admin, state, "new@guest.com", "Alice Smith")
  row <- DBI::dbGetQuery(con_admin, "SELECT * FROM master.admin.users WHERE email = 'new@guest.com'")
  testthat::expect_equal(nrow(row), 1)
  testthat::expect_equal(row$full_name, "Alice Smith")
})

testthat::test_that("auth_guest_login succeeds with email only (no name)", {
  con_admin <- get_auth_test_con_admin()
  on.exit(DBI::dbDisconnect(con_admin), add = TRUE)
  DBI::dbExecute(con_admin, "DELETE FROM master.admin.users WHERE email = 'noname@guest.com'")
  state <- shiny::reactiveValues()
  auth_init_state(state)
  result <- auth_guest_login(con_admin, state, "noname@guest.com")
  testthat::expect_true(result$ok)
  testthat::expect_true(auth_is_authenticated(state))
  row <- DBI::dbGetQuery(con_admin, "SELECT full_name FROM master.admin.users WHERE email = 'noname@guest.com'")
  testthat::expect_equal(nrow(row), 1)
  testthat::expect_true(is.na(row$full_name[1]) || is.null(row$full_name[1]))
})

testthat::test_that("auth_guest_login with email + name stores name", {
  con_admin <- get_auth_test_con_admin()
  on.exit(DBI::dbDisconnect(con_admin), add = TRUE)
  DBI::dbExecute(con_admin, "DELETE FROM master.admin.users WHERE email = 'named@guest.com'")
  state <- shiny::reactiveValues()
  auth_init_state(state)
  result <- auth_guest_login(con_admin, state, "named@guest.com", "Carol White")
  testthat::expect_true(result$ok)
  row <- DBI::dbGetQuery(con_admin, "SELECT full_name FROM master.admin.users WHERE email = 'named@guest.com'")
  testthat::expect_equal(row$full_name[1], "Carol White")
})

testthat::test_that("auth_guest_login finds and logs in existing guest", {
  con_admin <- get_auth_test_con_admin()
  on.exit(DBI::dbDisconnect(con_admin), add = TRUE)
  DBI::dbExecute(con_admin, "DELETE FROM master.admin.users WHERE email = 'returning@guest.com'")
  DBI::dbExecute(con_admin,
    "INSERT INTO master.admin.users (id, email, full_name, app_role, is_active)
     VALUES (10, 'returning@guest.com', 'Bob Jones', 'guest', TRUE)"
  )
  con <- get_auth_test_con()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  state <- shiny::reactiveValues()
  result <- auth_guest_login(con, state, "returning@guest.com", "Bob Jones")
  testthat::expect_true(result$ok)
  testthat::expect_true(auth_is_authenticated(state))
  testthat::expect_equal(shiny::isolate(state$AuthUserId), 10)
})

testthat::test_that("auth_guest_login rejects invalid email", {
  con <- get_auth_test_con()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  state <- shiny::reactiveValues()
  result <- auth_guest_login(con, state, "not-an-email", "Alice")
  testthat::expect_false(result$ok)
  testthat::expect_false(auth_is_authenticated(state))
})

testthat::test_that("auth_guest_login treats whitespace-only name as no name", {
  con_admin <- get_auth_test_con_admin()
  on.exit(DBI::dbDisconnect(con_admin), add = TRUE)
  DBI::dbExecute(con_admin, "DELETE FROM master.admin.users WHERE email = 'wsname@guest.com'")
  state <- shiny::reactiveValues()
  result <- auth_guest_login(con_admin, state, "wsname@guest.com", "   ")
  # whitespace-only → treated as NULL name, login still succeeds
  testthat::expect_true(result$ok)
})

testthat::test_that("auth_guest_login redirects admin email to admin sign-in", {
  testthat::skip_if_not_installed("bcrypt")
  con_admin <- get_auth_test_con_admin()
  on.exit(DBI::dbDisconnect(con_admin), add = TRUE)
  DBI::dbExecute(con_admin, "DELETE FROM master.admin.users WHERE email = 'admin@test.local'")
  DBI::dbExecute(con_admin,
    "INSERT INTO master.admin.users (email, full_name, app_role, password_hash, is_active)
     VALUES ('admin@test.local', 'An Admin', 'admin', ?, TRUE)",
    list(bcrypt::hashpw("pw"))
  )
  con <- get_auth_test_con()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  state <- shiny::reactiveValues()
  result <- auth_guest_login(con, state, "admin@test.local", "An Admin")
  testthat::expect_false(result$ok)
  testthat::expect_match(result$message, "Admin Sign In", ignore.case = TRUE)
})

# ---- auth_change_password ------------------------------------------------------

testthat::test_that("auth_change_password updates password for admin", {
  testthat::skip_if_not_installed("bcrypt")
  con_admin <- get_auth_test_con_admin()
  on.exit(DBI::dbDisconnect(con_admin), add = TRUE)
  DBI::dbExecute(con_admin, "DELETE FROM master.admin.users WHERE email = 'admin@test.local'")
  DBI::dbExecute(con_admin,
    "INSERT INTO master.admin.users (email, full_name, app_role, password_hash, is_active)
     VALUES ('admin@test.local', 'Admin', 'admin', ?, TRUE)",
    list(bcrypt::hashpw("oldpass1"))
  )
  state <- shiny::reactiveValues()
  auth_login(con_admin, state, "admin@test.local", "oldpass1")
  result <- auth_change_password(con_admin, state, "oldpass1", "newpass999")
  testthat::expect_true(result$ok)
  new_row <- DBI::dbGetQuery(con_admin, "SELECT password_hash FROM master.admin.users WHERE email = 'admin@test.local'")
  testthat::expect_true(bcrypt::checkpw("newpass999", new_row$password_hash[1]))
})

testthat::test_that("auth_change_password fails with wrong current password", {
  testthat::skip_if_not_installed("bcrypt")
  con_admin <- get_auth_test_con_admin()
  on.exit(DBI::dbDisconnect(con_admin), add = TRUE)
  DBI::dbExecute(con_admin, "DELETE FROM master.admin.users WHERE email = 'admin@test.local'")
  DBI::dbExecute(con_admin,
    "INSERT INTO master.admin.users (email, full_name, app_role, password_hash, is_active)
     VALUES ('admin@test.local', 'Admin', 'admin', ?, TRUE)",
    list(bcrypt::hashpw("correct123"))
  )
  state <- shiny::reactiveValues()
  auth_login(con_admin, state, "admin@test.local", "correct123")
  result <- auth_change_password(con_admin, state, "wrongpass", "newpass999")
  testthat::expect_false(result$ok)
})

testthat::test_that("auth_change_password rejects short new password", {
  testthat::skip_if_not_installed("bcrypt")
  con_admin <- get_auth_test_con_admin()
  on.exit(DBI::dbDisconnect(con_admin), add = TRUE)
  DBI::dbExecute(con_admin, "DELETE FROM master.admin.users WHERE email = 'admin@test.local'")
  DBI::dbExecute(con_admin,
    "INSERT INTO master.admin.users (email, full_name, app_role, password_hash, is_active)
     VALUES ('admin@test.local', 'Admin', 'admin', ?, TRUE)",
    list(bcrypt::hashpw("correct123"))
  )
  state <- shiny::reactiveValues()
  auth_login(con_admin, state, "admin@test.local", "correct123")
  result <- auth_change_password(con_admin, state, "correct123", "short")
  testthat::expect_false(result$ok)
})

testthat::test_that("auth_change_password fails for non-admin", {
  con_admin <- get_auth_test_con_admin()
  on.exit(DBI::dbDisconnect(con_admin), add = TRUE)
  DBI::dbExecute(con_admin, "DELETE FROM master.admin.users WHERE email = 'guest@test.com'")
  DBI::dbExecute(con_admin,
    "INSERT INTO master.admin.users (email, full_name, app_role, is_active)
     VALUES ('guest@test.com', 'Guest', 'guest', TRUE)"
  )
  con <- get_auth_test_con()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  state <- shiny::reactiveValues()
  auth_guest_login(con, state, "guest@test.com", "Guest")
  result <- auth_change_password(con, state, "x", "newpass999")
  testthat::expect_false(result$ok)
})

# ---- auth_grant_admin ----------------------------------------------------------

testthat::test_that("auth_grant_admin promotes guest to admin", {
  testthat::skip_if_not_installed("bcrypt")
  con_admin <- get_auth_test_con_admin()
  on.exit(DBI::dbDisconnect(con_admin), add = TRUE)
  DBI::dbExecute(con_admin, "DELETE FROM master.admin.users WHERE email IN ('superadmin@test.local', 'newadmin@test.local')")
  DBI::dbExecute(con_admin,
    "INSERT INTO master.admin.users (email, full_name, app_role, password_hash, is_active)
     VALUES ('superadmin@test.local', 'Super', 'admin', ?, TRUE)",
    list(bcrypt::hashpw("adminpass1"))
  )
  DBI::dbExecute(con_admin,
    "INSERT INTO master.admin.users (email, full_name, app_role, is_active)
     VALUES ('newadmin@test.local', 'New Admin', 'guest', TRUE)"
  )
  state <- shiny::reactiveValues()
  auth_login(con_admin, state, "superadmin@test.local", "adminpass1")
  result <- auth_grant_admin(con_admin, state, "newadmin@test.local", "initpass1")
  row <- DBI::dbGetQuery(con_admin, "SELECT app_role, password_hash FROM master.admin.users WHERE email = 'newadmin@test.local'")
  testthat::expect_true(result$ok)
  testthat::expect_equal(row$app_role, "admin")
  testthat::expect_true(bcrypt::checkpw("initpass1", row$password_hash))
})

testthat::test_that("auth_grant_admin fails for non-admin caller", {
  con_admin <- get_auth_test_con_admin()
  on.exit(DBI::dbDisconnect(con_admin), add = TRUE)
  DBI::dbExecute(con_admin, "DELETE FROM master.admin.users WHERE email = 'guest@test.com'")
  DBI::dbExecute(con_admin,
    "INSERT INTO master.admin.users (email, full_name, app_role, is_active)
     VALUES ('guest@test.com', 'Guest', 'guest', TRUE)"
  )
  con <- get_auth_test_con()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  state <- shiny::reactiveValues()
  auth_guest_login(con, state, "guest@test.com", "Guest")
  result <- auth_grant_admin(con, state, "anyone@test.com", "password99")
  testthat::expect_false(result$ok)
})

testthat::test_that("auth_grant_admin fails if target not found", {
  testthat::skip_if_not_installed("bcrypt")
  con_admin <- get_auth_test_con_admin()
  on.exit(DBI::dbDisconnect(con_admin), add = TRUE)
  DBI::dbExecute(con_admin, "DELETE FROM master.admin.users WHERE email = 'admin@test.local'")
  DBI::dbExecute(con_admin,
    "INSERT INTO master.admin.users (email, full_name, app_role, password_hash, is_active)
     VALUES ('admin@test.local', 'Admin', 'admin', ?, TRUE)",
    list(bcrypt::hashpw("adminpass1"))
  )
  state <- shiny::reactiveValues()
  auth_login(con_admin, state, "admin@test.local", "adminpass1")
  result <- auth_grant_admin(con_admin, state, "nobody@test.com", "password99")
  testthat::expect_false(result$ok)
  testthat::expect_match(result$message, "not found", ignore.case = TRUE)
})

testthat::test_that("auth_grant_admin fails if target is already admin", {
  testthat::skip_if_not_installed("bcrypt")
  con_admin <- get_auth_test_con_admin()
  on.exit(DBI::dbDisconnect(con_admin), add = TRUE)
  DBI::dbExecute(con_admin, "DELETE FROM master.admin.users WHERE email IN ('admin@test.local', 'other@test.local')")
  DBI::dbExecute(con_admin,
    "INSERT INTO master.admin.users (email, full_name, app_role, password_hash, is_active)
     VALUES ('admin@test.local', 'Admin', 'admin', ?, TRUE)",
    list(bcrypt::hashpw("adminpass1"))
  )
  DBI::dbExecute(con_admin,
    "INSERT INTO master.admin.users (email, full_name, app_role, password_hash, is_active)
     VALUES ('other@test.local', 'Other', 'admin', ?, TRUE)",
    list(bcrypt::hashpw("other123"))
  )
  state <- shiny::reactiveValues()
  auth_login(con_admin, state, "admin@test.local", "adminpass1")
  result <- auth_grant_admin(con_admin, state, "other@test.local", "password99")
  testthat::expect_false(result$ok)
  testthat::expect_match(result$message, "already", ignore.case = TRUE)
})

# ---- auth_logout ---------------------------------------------------------------

testthat::test_that("auth_logout clears all state", {
  state <- shiny::reactiveValues()
  auth_init_state(state)
  state$AuthAuthenticated <- TRUE
  state$AuthUser          <- "someone@test.com"
  state$AuthRole          <- "admin"
  state$AuthRoles         <- "admin"
  state$AuthPermissions   <- c("*")

  auth_logout(state)

  testthat::expect_false(auth_is_authenticated(state))
  testthat::expect_null(shiny::isolate(state$AuthUser))
  testthat::expect_null(shiny::isolate(state$AuthRole))
  testthat::expect_equal(shiny::isolate(state$AuthPermissions), character(0))
})

# ---- auth_user_has_permission --------------------------------------------------

testthat::test_that("auth_user_has_permission respects wildcard for admin", {
  state <- shiny::reactiveValues()
  auth_init_state(state)
  state$AuthAuthenticated <- TRUE
  state$AuthPermissions   <- c("*")

  testthat::expect_true(auth_user_has_permission(state, "publish_rds"))
  testthat::expect_true(auth_user_has_permission(state, "view_download_logs"))
})

testthat::test_that("auth_user_has_permission restricts guest to scoped permissions", {
  state <- shiny::reactiveValues()
  auth_init_state(state)
  state$AuthAuthenticated <- TRUE
  state$AuthRole          <- "guest"
  state$AuthPermissions   <- c("write:staging", "read:core")

  testthat::expect_true(auth_user_has_permission(state, "write:staging"))
  testthat::expect_true(auth_user_has_permission(state, "read:core"))
  testthat::expect_false(auth_user_has_permission(state, "publish_rds"))
  testthat::expect_false(auth_user_has_permission(state, "*"))
})

testthat::test_that("auth_user_has_permission returns FALSE when not authenticated", {
  state <- shiny::reactiveValues()
  auth_init_state(state)

  testthat::expect_false(auth_user_has_permission(state, "read:core"))
})

# ---- auth_init_state: SyncVersion --------------------------------------------

testthat::test_that("auth_init_state initialises SyncVersion to 0L", {
  state <- shiny::reactiveValues()
  shiny::isolate(auth_init_state(state))
  testthat::expect_equal(shiny::isolate(state$SyncVersion), 0L)
})

testthat::test_that("auth_init_state does not overwrite existing SyncVersion", {
  state <- shiny::reactiveValues(SyncVersion = 5L)
  shiny::isolate(auth_init_state(state))
  testthat::expect_equal(shiny::isolate(state$SyncVersion), 5L)
})

