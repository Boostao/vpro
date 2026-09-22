local_plot_create_context <- function(path, authorize = NULL) {
  con <- tryCatch(vpro_db_connect(), error = identity)
  if (inherits(con, "error")) {
    testthat::skip(conditionMessage(con))
  }
  context <- vpro_project_context(con = con, authorize = authorize)
  withr::defer(vpro_db_disconnect(context$con), envir = parent.frame())
  vpro_project_attach(context, path, "Sample")
  vpro_project_activate(context, "Sample")
  context
}

local_plot_create_copy <- function() {
  path <- tempfile(fileext = ".db")
  file.copy(system.file("extdata", "projects", "Sample.db", package = "vpro"), path)
  path
}

plot_create_counts <- function(path, plot_number) {
  con <- DBI::dbConnect(RSQLite::SQLite(), path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  c(
    env = DBI::dbGetQuery(
      con,
      "SELECT COUNT(*) AS n FROM Sample_Env WHERE PlotNumber = ?",
      params = list(plot_number)
    )$n[[1L]],
    admin = DBI::dbGetQuery(
      con,
      "SELECT COUNT(*) AS n FROM Sample_Admin WHERE Plot = ?",
      params = list(plot_number)
    )$n[[1L]],
    audit = DBI::dbGetQuery(
      con,
      "SELECT COUNT(*) AS n FROM Sample_Audit WHERE PlotNumber = ?",
      params = list(plot_number)
    )$n[[1L]],
    children = sum(vapply(
      c("Veg", "Humus", "Mineral", "Other"),
      function(suffix) {
        DBI::dbGetQuery(
          con,
          paste0("SELECT COUNT(*) AS n FROM Sample_", suffix, " WHERE PlotNumber = ?"),
          params = list(plot_number)
        )$n[[1L]]
      },
      integer(1)
    ))
  )
}

test_that("plot creation atomically creates the Env and Admin pair", {
  path <- local_plot_create_copy()
  context <- local_plot_create_context(path)

  result <- vpro_plot_create(
    context,
    "NEW1001",
    env = list(Location = "Created location", Elevation = 100L),
    admin = list(PlotType = "4", OfficeNotes = "Created note")
  )

  expect_identical(result$env$PlotNumber, "NEW1001")
  expect_identical(result$admin$Plot, "NEW1001")
  expect_identical(result$env$Location, "Created location")
  expect_identical(result$env$Elevation, 100L)
  expect_identical(result$admin$PlotType, "4")
  expect_identical(result$admin$OfficeNotes, "Created note")
  expect_false(as.logical(result$env$SV_FloodPlain))
  expect_identical(vpro_plot_get(context, "NEW1001"), result)
  expect_identical(plot_create_counts(path, "NEW1001"), c(env = 1L, admin = 1L, audit = 0L, children = 0L))

  visible <- DBI::dbGetQuery(
    context$con,
    'SELECT "Location", "OfficeNotes" FROM USysEnv WHERE "PlotNumber" = \'NEW1001\''
  )
  expect_identical(visible$Location, "Created location")
  expect_identical(visible$OfficeNotes, "Created note")
})

test_that("plot creation preserves defaults with empty or one-sided values", {
  path <- local_plot_create_copy()
  context <- local_plot_create_context(path)

  empty <- vpro_plot_create(context, "NEW1002")
  env_only <- vpro_plot_create(context, "NEW1003", env = list(Location = "Env only"))
  admin_only <- vpro_plot_create(context, "NEW1004", admin = list(OfficeNotes = "Admin only"))

  expect_false(as.logical(empty$env$SV_FloodPlain))
  expect_true(is.na(empty$env$ProjectID))
  expect_true(is.na(empty$admin$StartDate))
  expect_identical(env_only$env$Location, "Env only")
  expect_true(is.na(env_only$admin$OfficeNotes))
  expect_true(is.na(admin_only$env$Location))
  expect_identical(admin_only$admin$OfficeNotes, "Admin only")
  expect_identical(plot_create_counts(path, "NEW1002")[["audit"]], 0L)
  expect_identical(plot_create_counts(path, "NEW1003")[["children"]], 0L)
  expect_identical(plot_create_counts(path, "NEW1004")[["children"]], 0L)
})

test_that("plot creation rejects collisions and invalid requests without mutation", {
  path <- local_plot_create_copy()
  context <- local_plot_create_context(path)
  existing <- DBI::dbGetQuery(
    context$con,
    'SELECT "PlotNumber" FROM USysEnv ORDER BY "PlotNumber" LIMIT 1'
  )$PlotNumber[[1L]]

  expect_snapshot(error = TRUE, vpro_plot_create(context, existing))
  expect_snapshot(
    error = TRUE,
    vpro_plot_create(context, "NEW1005", env = list(PlotNumber = "OTHER"))
  )
  expect_snapshot(
    error = TRUE,
    vpro_plot_create(context, "NEW1005", admin = list(Plot = "OTHER"))
  )
  expect_snapshot(
    error = TRUE,
    vpro_plot_create(context, "NEW1005", env = list(NotAField = "invalid"))
  )
  expect_snapshot(
    error = TRUE,
    vpro_plot_create(context, "NEW1005", admin = list(StartDate = 1800L))
  )
  expect_snapshot(
    error = TRUE,
    vpro_plot_create(context, "NEW1005", env = list(Elevation = "high"))
  )
  expect_identical(plot_create_counts(path, "NEW1005"), c(env = 0L, admin = 0L, audit = 0L, children = 0L))
})

test_that("legacy incomplete pairs are diagnosed and left untouched", {
  path <- local_plot_create_copy()
  context <- local_plot_create_context(path)
  con <- DBI::dbConnect(RSQLite::SQLite(), path)
  withr::defer(DBI::dbDisconnect(con))
  DBI::dbExecute(con, "INSERT INTO Sample_Env (PlotNumber) VALUES ('ORPHENV')")
  DBI::dbExecute(con, "INSERT INTO Sample_Admin (Plot) VALUES ('ORPHADM')")

  expect_snapshot(error = TRUE, vpro_plot_create(context, "ORPHENV"))
  expect_snapshot(error = TRUE, vpro_plot_create(context, "ORPHADM"))
  expect_identical(plot_create_counts(path, "ORPHENV")[["env"]], 1L)
  expect_identical(plot_create_counts(path, "ORPHENV")[["admin"]], 0L)
  expect_identical(plot_create_counts(path, "ORPHADM")[["env"]], 0L)
  expect_identical(plot_create_counts(path, "ORPHADM")[["admin"]], 1L)
})

test_that("Admin insertion failure rolls back the Env row", {
  path <- local_plot_create_copy()
  context <- local_plot_create_context(path)
  con <- DBI::dbConnect(RSQLite::SQLite(), path)
  withr::defer(DBI::dbDisconnect(con))
  DBI::dbExecute(
    con,
    "CREATE TRIGGER prevent_admin_create BEFORE INSERT ON Sample_Admin BEGIN SELECT RAISE(ABORT, 'admin insert blocked'); END"
  )

  expect_error(
    vpro_plot_create(context, "NEW1006", env = list(Location = "Must roll back")),
    "admin insert blocked",
    fixed = TRUE
  )
  expect_identical(plot_create_counts(path, "NEW1006"), c(env = 0L, admin = 0L, audit = 0L, children = 0L))
})

test_that("protected Admin values require explicit authorization", {
  path <- local_plot_create_copy()
  denied <- local_plot_create_context(path)

  expect_snapshot(
    error = TRUE,
    vpro_plot_create(denied, "NEW1007", admin = list(BECSiteUnit = "restricted"))
  )
  expect_identical(plot_create_counts(path, "NEW1007")[["env"]], 0L)

  allowed <- local_plot_create_context(
    path,
    authorize = function(permission, resource) {
      identical(permission, "update_protected_plot_field") && identical(resource$field, "BECSiteUnit")
    }
  )
  result <- vpro_plot_create(
    allowed,
    "NEW1007",
    admin = list(BECSiteUnit = "authorized")
  )
  expect_identical(result$admin$BECSiteUnit, "authorized")
})

test_that("plot creation does not change active SU state", {
  path <- local_plot_create_copy()
  context <- local_plot_create_context(path)
  vpro_su_attach(context, path, "Sample")
  vpro_su_activate(context, "Sample")
  active_su <- context$active_su
  sqlite <- DBI::dbConnect(RSQLite::SQLite(), path)
  withr::defer(DBI::dbDisconnect(sqlite))
  before_su_rows <- DBI::dbGetQuery(
    sqlite,
    'SELECT COUNT(*) AS n FROM "Sample_SU"'
  )$n[[1L]]

  result <- vpro_plot_create(context, "NEW1008", env = list(Location = "Outside SU"))

  expect_identical(result$env$Location, "Outside SU")
  expect_identical(context$active_su$su, active_su$su)
  expect_identical(
    DBI::dbGetQuery(sqlite, 'SELECT COUNT(*) AS n FROM "Sample_SU"')$n[[1L]],
    before_su_rows
  )
  expect_equal(
    DBI::dbGetQuery(context$con, 'SELECT COUNT(*) AS n FROM USysEnv WHERE "PlotNumber" = \'NEW1008\'')$n[[1L]],
    0
  )
  expect_identical(vpro_plot_get(context, "NEW1008")$env$PlotNumber, "NEW1008")
})
