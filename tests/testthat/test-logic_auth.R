testthat::context("logic_auth")

source(here::here("R", "logic_auth.R"))

# In-memory DuckDB with an attached master DB that mirrors production schema
setup_auth_db <- function() {
  con         <- DBI::dbConnect(duckdb::duckdb(), ":memory:")
  master_path <- tempfile(pattern = "master_auth_", fileext = ".duckdb")
  DBI::dbExecute(con, sprintf("ATTACH '%s' AS master", gsub("'", "''", master_path)))
  DBI::dbExecute(con, "CREATE SCHEMA master.admin")
  DBI::dbExecute(con, "
    CREATE TABLE master.admin.users (
      id            INTEGER,
      email         TEXT UNIQUE NOT NULL,
      full_name     TEXT NOT NULL DEFAULT '',
      app_role      TEXT NOT NULL DEFAULT 'guest',
      password_hash TEXT,
      is_active     BOOLEAN DEFAULT TRUE
    )
  ")
  con
}

# ---- auth_login (admin) --------------------------------------------------------

testthat::test_that("auth_login authenticates admin by email and password", {
  testthat::skip_if_not_installed("bcrypt")
  con <- setup_auth_db()
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  DBI::dbExecute(con,
    "INSERT INTO master.admin.users (id, email, full_name, app_role, password_hash, is_active)
     VALUES (1, 'admin@test.local', 'Test Admin', 'admin', ?, TRUE)",
    list(bcrypt::hashpw("secret"))
  )

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
  con <- setup_auth_db()
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  DBI::dbExecute(con,
    "INSERT INTO master.admin.users (id, email, full_name, app_role, password_hash, is_active)
     VALUES (1, 'admin@test.local', 'Test Admin', 'admin', ?, TRUE)",
    list(bcrypt::hashpw("correct"))
  )

  state <- shiny::reactiveValues()
  result <- auth_login(con, state, "admin@test.local", "wrong")

  testthat::expect_false(result$ok)
  testthat::expect_false(auth_is_authenticated(state))
})

testthat::test_that("auth_login rejects guest accounts", {
  con <- setup_auth_db()
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  DBI::dbExecute(con,
    "INSERT INTO master.admin.users (id, email, full_name, app_role, is_active)
     VALUES (1, 'guest@test.local', 'A Guest', 'guest', TRUE)"
  )

  state <- shiny::reactiveValues()
  result <- auth_login(con, state, "guest@test.local", "anything")

  testthat::expect_false(result$ok)
  testthat::expect_false(auth_is_authenticated(state))
})

# ---- auth_guest_login ----------------------------------------------------------

testthat::test_that("auth_guest_login creates new guest on first visit", {
  con <- setup_auth_db()
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  state <- shiny::reactiveValues()
  auth_init_state(state)
  result <- auth_guest_login(con, state, "new@guest.com", "Alice Smith")

  testthat::expect_true(result$ok)
  testthat::expect_true(auth_is_authenticated(state))
  testthat::expect_false(auth_is_admin(state))
  testthat::expect_equal(shiny::isolate(state$AuthUser), "new@guest.com")
  testthat::expect_equal(shiny::isolate(state$AuthRole), "guest")
  testthat::expect_true("write:staging" %in% shiny::isolate(state$AuthPermissions))
  testthat::expect_false("*" %in% shiny::isolate(state$AuthPermissions))

  row <- DBI::dbGetQuery(con, "SELECT * FROM master.admin.users WHERE email = 'new@guest.com'")
  testthat::expect_equal(nrow(row), 1)
  testthat::expect_equal(row$full_name, "Alice Smith")
})

testthat::test_that("auth_guest_login finds and logs in existing guest", {
  con <- setup_auth_db()
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  DBI::dbExecute(con,
    "INSERT INTO master.admin.users (id, email, full_name, app_role, is_active)
     VALUES (10, 'returning@guest.com', 'Bob Jones', 'guest', TRUE)"
  )

  state <- shiny::reactiveValues()
  result <- auth_guest_login(con, state, "returning@guest.com", "Bob Jones")

  testthat::expect_true(result$ok)
  testthat::expect_true(auth_is_authenticated(state))
  testthat::expect_equal(shiny::isolate(state$AuthUserId), 10)
})

testthat::test_that("auth_guest_login rejects invalid email", {
  con <- setup_auth_db()
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  state <- shiny::reactiveValues()
  result <- auth_guest_login(con, state, "not-an-email", "Alice")

  testthat::expect_false(result$ok)
  testthat::expect_false(auth_is_authenticated(state))
})

testthat::test_that("auth_guest_login rejects blank full name", {
  con <- setup_auth_db()
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  state <- shiny::reactiveValues()
  result <- auth_guest_login(con, state, "a@b.com", "   ")

  testthat::expect_false(result$ok)
})

testthat::test_that("auth_guest_login redirects admin email to admin sign-in", {
  testthat::skip_if_not_installed("bcrypt")
  con <- setup_auth_db()
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  DBI::dbExecute(con,
    "INSERT INTO master.admin.users (id, email, full_name, app_role, password_hash, is_active)
     VALUES (1, 'admin@test.local', 'An Admin', 'admin', ?, TRUE)",
    list(bcrypt::hashpw("pw"))
  )

  state <- shiny::reactiveValues()
  result <- auth_guest_login(con, state, "admin@test.local", "An Admin")

  testthat::expect_false(result$ok)
  testthat::expect_match(result$message, "Admin Sign In", ignore.case = TRUE)
})

# ---- auth_change_password ------------------------------------------------------

testthat::test_that("auth_change_password updates password for admin", {
  testthat::skip_if_not_installed("bcrypt")
  con <- setup_auth_db()
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  DBI::dbExecute(con,
    "INSERT INTO master.admin.users (id, email, full_name, app_role, password_hash, is_active)
     VALUES (1, 'admin@test.local', 'Admin', 'admin', ?, TRUE)",
    list(bcrypt::hashpw("oldpass1"))
  )

  state <- shiny::reactiveValues()
  auth_login(con, state, "admin@test.local", "oldpass1")
  result <- auth_change_password(con, state, "oldpass1", "newpass999")

  testthat::expect_true(result$ok)
  new_row <- DBI::dbGetQuery(con, "SELECT password_hash FROM master.admin.users WHERE id = 1")
  testthat::expect_true(bcrypt::checkpw("newpass999", new_row$password_hash[1]))
})

testthat::test_that("auth_change_password fails with wrong current password", {
  testthat::skip_if_not_installed("bcrypt")
  con <- setup_auth_db()
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  DBI::dbExecute(con,
    "INSERT INTO master.admin.users (id, email, full_name, app_role, password_hash, is_active)
     VALUES (1, 'admin@test.local', 'Admin', 'admin', ?, TRUE)",
    list(bcrypt::hashpw("correct123"))
  )

  state <- shiny::reactiveValues()
  auth_login(con, state, "admin@test.local", "correct123")
  result <- auth_change_password(con, state, "wrongpass", "newpass999")

  testthat::expect_false(result$ok)
})

testthat::test_that("auth_change_password rejects short new password", {
  testthat::skip_if_not_installed("bcrypt")
  con <- setup_auth_db()
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  DBI::dbExecute(con,
    "INSERT INTO master.admin.users (id, email, full_name, app_role, password_hash, is_active)
     VALUES (1, 'admin@test.local', 'Admin', 'admin', ?, TRUE)",
    list(bcrypt::hashpw("correct123"))
  )

  state <- shiny::reactiveValues()
  auth_login(con, state, "admin@test.local", "correct123")
  result <- auth_change_password(con, state, "correct123", "short")

  testthat::expect_false(result$ok)
})

testthat::test_that("auth_change_password fails for non-admin", {
  con <- setup_auth_db()
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  DBI::dbExecute(con,
    "INSERT INTO master.admin.users (id, email, full_name, app_role, is_active)
     VALUES (99, 'guest@test.com', 'Guest', 'guest', TRUE)"
  )

  state <- shiny::reactiveValues()
  auth_guest_login(con, state, "guest@test.com", "Guest")
  result <- auth_change_password(con, state, "x", "newpass999")

  testthat::expect_false(result$ok)
})

# ---- auth_grant_admin ----------------------------------------------------------

testthat::test_that("auth_grant_admin promotes guest to admin", {
  testthat::skip_if_not_installed("bcrypt")
  con <- setup_auth_db()
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  DBI::dbExecute(con,
    "INSERT INTO master.admin.users (id, email, full_name, app_role, password_hash, is_active)
     VALUES (1, 'superadmin@test.local', 'Super', 'admin', ?, TRUE)",
    list(bcrypt::hashpw("adminpass1"))
  )
  DBI::dbExecute(con,
    "INSERT INTO master.admin.users (id, email, full_name, app_role, is_active)
     VALUES (2, 'newadmin@test.local', 'New Admin', 'guest', TRUE)"
  )

  state <- shiny::reactiveValues()
  auth_login(con, state, "superadmin@test.local", "adminpass1")
  result <- auth_grant_admin(con, state, "newadmin@test.local", "initpass1")

  testthat::expect_true(result$ok)
  row <- DBI::dbGetQuery(con, "SELECT app_role, password_hash FROM master.admin.users WHERE id = 2")
  testthat::expect_equal(row$app_role, "admin")
  testthat::expect_true(bcrypt::checkpw("initpass1", row$password_hash))
})

testthat::test_that("auth_grant_admin fails for non-admin caller", {
  con <- setup_auth_db()
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  DBI::dbExecute(con,
    "INSERT INTO master.admin.users (id, email, full_name, app_role, is_active)
     VALUES (1, 'guest@test.com', 'Guest', 'guest', TRUE)"
  )

  state <- shiny::reactiveValues()
  auth_guest_login(con, state, "guest@test.com", "Guest")
  result <- auth_grant_admin(con, state, "anyone@test.com", "password99")

  testthat::expect_false(result$ok)
})

testthat::test_that("auth_grant_admin fails if target not found", {
  testthat::skip_if_not_installed("bcrypt")
  con <- setup_auth_db()
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  DBI::dbExecute(con,
    "INSERT INTO master.admin.users (id, email, full_name, app_role, password_hash, is_active)
     VALUES (1, 'admin@test.local', 'Admin', 'admin', ?, TRUE)",
    list(bcrypt::hashpw("adminpass1"))
  )

  state <- shiny::reactiveValues()
  auth_login(con, state, "admin@test.local", "adminpass1")
  result <- auth_grant_admin(con, state, "nobody@test.com", "password99")

  testthat::expect_false(result$ok)
  testthat::expect_match(result$message, "not found", ignore.case = TRUE)
})

testthat::test_that("auth_grant_admin fails if target is already admin", {
  testthat::skip_if_not_installed("bcrypt")
  con <- setup_auth_db()
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  DBI::dbExecute(con,
    "INSERT INTO master.admin.users (id, email, full_name, app_role, password_hash, is_active)
     VALUES (1, 'admin@test.local', 'Admin', 'admin', ?, TRUE)",
    list(bcrypt::hashpw("adminpass1"))
  )
  DBI::dbExecute(con,
    "INSERT INTO master.admin.users (id, email, full_name, app_role, password_hash, is_active)
     VALUES (2, 'other@test.local', 'Other', 'admin', ?, TRUE)",
    list(bcrypt::hashpw("other123"))
  )

  state <- shiny::reactiveValues()
  auth_login(con, state, "admin@test.local", "adminpass1")
  result <- auth_grant_admin(con, state, "other@test.local", "password99")

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

