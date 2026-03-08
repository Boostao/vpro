testthat::context("mod_admin_publishing")

source(here::here("R", "db_connections.R"), local = TRUE)
source(here::here("R", "logic_auth.R"),     local = TRUE)
source(here::here("R", "logic_publish.R"),  local = TRUE)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

make_state <- function(authenticated = TRUE,
                       permissions  = character(0)) {
  e <- new.env(parent = emptyenv())
  e$AuthAuthenticated <- authenticated
  e$AuthRole          <- if (authenticated && "*" %in% permissions) "admin" else "user"
  e$AuthPermissions   <- permissions
  # shiny::isolate won't error in non-Shiny context but state is plain env, so
  # override isolate() to be a plain identity in this test context.
  e
}

make_minimal_db <- function() {
  con <- DBI::dbConnect(duckdb::duckdb(), ":memory:")

  DBI::dbExecute(con, "CREATE TABLE USysProjectMetadata (
    projectid TEXT, projecttitle TEXT, ispublic TEXT,
    beczone TEXT, description TEXT)")
  DBI::dbExecute(con, "CREATE TABLE Env (
    plotnumber TEXT, projectid TEXT, date_sampled DATE,
    latitude DOUBLE, longitude DOUBLE,
    bec_zone TEXT, bec_subzone TEXT, bec_site_series TEXT, _location TEXT)")
  DBI::dbExecute(con, "CREATE TABLE SU (
    plotnumber TEXT, dataquality TEXT)")
  DBI::dbExecute(con, "CREATE TABLE vw_USysAllVeg (
    plotnumber TEXT, projectid TEXT, code TEXT, layer TEXT, cover TEXT)")
  DBI::dbExecute(con, "CREATE TABLE Lump (
    sppcode TEXT, lumpcode TEXT, _use INTEGER)")

  con
}

# ---------------------------------------------------------------------------
# publish_project_dataset
# ---------------------------------------------------------------------------

testthat::test_that("publish_rds creates output files for a project", {
  skip_if_not_installed("duckdb")

  con <- make_minimal_db()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  DBI::dbExecute(con,
    "INSERT INTO USysProjectMetadata VALUES
       ('P1', 'Project One', 'True', 'IDF', 'Test')")
  DBI::dbExecute(con,
    "INSERT INTO Env VALUES
       ('PLOT-001', 'P1', DATE '2024-06-01', 49.123, -120.765,
        'IDF', 'xh', '01', 'Test area')")
  DBI::dbExecute(con,
    "INSERT INTO SU VALUES ('PLOT-001', 'Good')")
  DBI::dbExecute(con,
    "INSERT INTO vw_USysAllVeg VALUES ('PLOT-001', 'P1', 'FD', 'A', '50')")

  out_dir <- tempfile("pub_rds_")
  dir.create(out_dir, recursive = TRUE)
  on.exit(unlink(out_dir, recursive = TRUE), add = TRUE)

  res <- publish_project_dataset(
    project_id  = "P1",
    output_dir  = out_dir,
    formats     = c("rds"),
    con         = con,
    overwrite   = TRUE,
    is_public   = TRUE
  )

  testthat::expect_equal(res$project_id, "P1")
  testthat::expect_true(file.exists(file.path(out_dir, "P1_environment.rds")))
  testthat::expect_true(file.exists(file.path(out_dir, "P1_vegetation.rds")))
  testthat::expect_true(file.exists(file.path(out_dir, "P1_metadata.rds")))
})

testthat::test_that("publish_project_dataset errors when no formats requested", {
  skip_if_not_installed("duckdb")

  con <- make_minimal_db()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  DBI::dbExecute(con,
    "INSERT INTO USysProjectMetadata VALUES
       ('P2', 'Project Two', 'True', 'IDF', 'Test')")
  DBI::dbExecute(con,
    "INSERT INTO Env VALUES
       ('PLOT-002', 'P2', DATE '2024-06-01', 49.5, -120.5,
        'IDF', 'xh', '01', 'Area')")
  DBI::dbExecute(con,
    "INSERT INTO SU VALUES ('PLOT-002', 'Good')")

  out_dir <- tempfile("pub_empty_")
  dir.create(out_dir, recursive = TRUE)
  on.exit(unlink(out_dir, recursive = TRUE), add = TRUE)

  testthat::expect_error(
    publish_project_dataset(
      project_id = "P2",
      output_dir = out_dir,
      formats    = character(0),
      con        = con,
      overwrite  = TRUE,
      is_public  = TRUE
    )
  )
})

testthat::test_that("registry CSV is created and readable after publish", {
  skip_if_not_installed("duckdb")

  con <- make_minimal_db()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  DBI::dbExecute(con,
    "INSERT INTO USysProjectMetadata VALUES
       ('P3', 'Project Three', 'True', 'IDF', 'Test')")
  DBI::dbExecute(con,
    "INSERT INTO Env VALUES
       ('PLOT-003', 'P3', DATE '2024-07-01', 50.0, -121.0,
        'IDF', 'xh', '01', 'Area')")
  DBI::dbExecute(con,
    "INSERT INTO SU VALUES ('PLOT-003', 'Good')")

  out_dir <- tempfile("pub_reg_")
  dir.create(out_dir, recursive = TRUE)
  on.exit(unlink(out_dir, recursive = TRUE), add = TRUE)

  publish_project_dataset(
    project_id = "P3",
    output_dir = out_dir,
    formats    = c("rds", "csv"),
    con        = con,
    overwrite  = TRUE,
    is_public  = TRUE
  )

  reg_path <- file.path(out_dir, "publication_registry.csv")
  testthat::expect_true(file.exists(reg_path))

  reg <- read.csv(reg_path, stringsAsFactors = FALSE)
  testthat::expect_true(nrow(reg) >= 1)
  testthat::expect_true("project_id" %in% names(reg))
  testthat::expect_equal(tail(reg$project_id, 1), "P3")
})

# ---------------------------------------------------------------------------
# Permission guard (logic_auth.R)
# ---------------------------------------------------------------------------

testthat::test_that("auth_user_has_permission returns FALSE for unauthenticated state", {
  # Shiny not running — patch isolate so plain env reads work
  local({
    local_isolate <- function(x) x
    environment(auth_is_authenticated)$`shiny::isolate` <- local_isolate
  })

  state <- make_state(authenticated = FALSE)
  testthat::expect_false(auth_user_has_permission(state, "publish_rds"))
})

testthat::test_that("auth_user_has_permission returns TRUE when permission present", {
  state <- make_state(authenticated = TRUE, permissions = c("publish_rds"))
  # Need shiny::isolate to work with plain env — it does in non-reactive context
  # when the value is not a reactive; just call directly.
  with_mocked_bindings(
    isolate = function(x) x,
    .package = "shiny",
    {
      testthat::expect_true(auth_user_has_permission(state, "publish_rds"))
      testthat::expect_false(auth_user_has_permission(state, "view_download_logs"))
    }
  )
})

testthat::test_that("auth_user_has_permission returns TRUE for wildcard admin", {
  state <- make_state(authenticated = TRUE, permissions = c("*"))
  with_mocked_bindings(
    isolate = function(x) x,
    .package = "shiny",
    {
      testthat::expect_true(auth_user_has_permission(state, "publish_rds"))
      testthat::expect_true(auth_user_has_permission(state, "view_download_logs"))
    }
  )
})

# ---------------------------------------------------------------------------
# build_download_log_query  (already tested in test-logic_publish.R, but
#   re-verify the basic contract from the publishing sub-module context)
# ---------------------------------------------------------------------------

testthat::test_that("build_download_log_query returns sql + params list", {
  q <- build_download_log_query(list())
  testthat::expect_type(q, "list")
  testthat::expect_named(q, c("sql", "params"))
  testthat::expect_true(grepl("download_log", q$sql))
  testthat::expect_length(q$params, 0)
})
