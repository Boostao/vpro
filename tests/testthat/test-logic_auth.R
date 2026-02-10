testthat::context("logic_auth")

source(here::here("R", "logic_auth.R"))
source(here::here("R", "logic_sync.R"))

setup_auth_db <- function() {
  con <- DBI::dbConnect(duckdb::duckdb(), ":memory:")
  master_path <- tempfile(pattern = "master_auth_", fileext = ".duckdb")
  DBI::dbExecute(con, sprintf("ATTACH '%s' AS master", gsub("'", "''", master_path)))

  DBI::dbExecute(con, "CREATE SCHEMA master.admin")

  DBI::dbExecute(con, "
    CREATE TABLE master.admin.users (
      id INTEGER,
      username TEXT,
      password_hash TEXT,
      is_active BOOLEAN
    )
  ")

  DBI::dbExecute(con, "
    CREATE TABLE master.admin.roles (
      id INTEGER,
      role_name TEXT,
      permissions TEXT
    )
  ")

  DBI::dbExecute(con, "
    CREATE TABLE master.admin.user_roles (
      user_id INTEGER,
      role_id INTEGER
    )
  ")

  con
}

testthat::test_that("auth_login loads roles and permissions", {
  testthat::skip_if_not_installed("bcrypt")

  con <- setup_auth_db()
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  password_hash <- bcrypt::hashpw("secret")

  DBI::dbExecute(
    con,
    "INSERT INTO master.admin.users (id, username, password_hash, is_active)
     VALUES (1, 'user1', ?, TRUE)",
    list(password_hash)
  )

  DBI::dbExecute(
    con,
    "INSERT INTO master.admin.roles (id, role_name, permissions)
     VALUES (1, 'field_user', 'read:own_projects,create:merge_requests')"
  )

  DBI::dbExecute(
    con,
    "INSERT INTO master.admin.user_roles (user_id, role_id) VALUES (1, 1)"
  )

  state <- shiny::reactiveValues()
  auth_init_state(state)

  result <- auth_login(con, state, "user1", "secret")

  testthat::expect_true(result$ok)
  testthat::expect_true(auth_is_authenticated(state))
  testthat::expect_true("field_user" %in% shiny::isolate(state$AuthRoles))
  testthat::expect_true("create:merge_requests" %in% shiny::isolate(state$AuthPermissions))
})

testthat::test_that("auth_user_has_permission respects wildcard", {
  state <- shiny::reactiveValues()
  auth_init_state(state)
  state$AuthAuthenticated <- TRUE
  state$AuthPermissions <- c("*")

  testthat::expect_true(auth_user_has_permission(state, "publish_rds"))
  testthat::expect_true(auth_user_has_permission(state, "view_download_logs"))
})
