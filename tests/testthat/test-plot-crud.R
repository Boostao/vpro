local_plot_context <- function(path, project = "Sample", config = NULL) {
  con <- tryCatch(vpro_db_connect(), error = identity)
  if (inherits(con, "error")) {
    testthat::skip(conditionMessage(con))
  }
  context <- vpro_project_context(con = con, config = config)
  withr::defer(vpro_db_disconnect(context$con), envir = parent.frame())
  vpro_project_attach(context, path, project)
  vpro_project_activate(context, project)
  context
}

local_sample_copy <- function() {
  path <- tempfile(fileext = ".db")
  file.copy(system.file("extdata", "projects", "Sample.db", package = "vpro"), path)
  path
}

sample_plot_number <- function(context) {
  DBI::dbGetQuery(context$con, 'SELECT "PlotNumber" FROM USysEnv ORDER BY "PlotNumber" LIMIT 1')$PlotNumber[[1]]
}

test_that("plot reads require an active project and exact Env/Admin rows", {
  path <- local_sample_copy()
  con <- tryCatch(vpro_db_connect(), error = identity)
  if (inherits(con, "error")) {
    skip(conditionMessage(con))
  }
  context <- vpro_project_context(con = con)
  withr::defer(vpro_db_disconnect(context$con))

  expect_snapshot(error = TRUE, vpro_plot_get(context, "1976071"))

  vpro_project_attach(context, path, "Sample")
  vpro_project_activate(context, "Sample")
  plot_number <- sample_plot_number(context)
  result <- vpro_plot_get(context, plot_number)

  expect_identical(nrow(result$env), 1L)
  expect_identical(nrow(result$admin), 1L)
  expect_identical(result$env$PlotNumber, plot_number)
  expect_identical(result$admin$Plot, plot_number)
  expect_snapshot(error = TRUE, vpro_plot_get(context, "Missing"))
})

test_that("plot updates Env and Admin atomically and audit populated changes", {
  path <- local_sample_copy()
  context <- local_plot_context(path)
  plot_number <- sample_plot_number(context)

  vpro_plot_update(
    context,
    plot_number,
    env = list(Location = "First value"),
    admin = list(OfficeNotes = "First note"),
    user = "tester",
    audit_strength = 1
  )
  result <- vpro_plot_update(
    context,
    plot_number,
    env = list(Location = "Second value"),
    admin = list(OfficeNotes = "Second note"),
    user = "tester",
    audit_strength = 1
  )

  expect_identical(result$plot$env$Location, "Second value")
  expect_identical(result$plot$admin$OfficeNotes, "Second note")
  expect_setequal(result$audit$EditField, c("Location", "OfficeNotes"))
  expect_true(all(result$audit$Table == "_Env"))
  expect_true(all(result$audit$User == "tester"))
  expect_true(all(result$audit$BeforeEdit %in% c("First value", "First note")))
  expect_true(all(result$audit$AfterEdit %in% c("Second value", "Second note")))

  visible <- DBI::dbGetQuery(
    context$con,
    paste0(
      'SELECT "Location", "OfficeNotes" FROM USysEnv WHERE "PlotNumber" = ',
      DBI::dbQuoteLiteral(context$con, plot_number)
    )
  )
  expect_identical(visible$Location, "Second value")
  expect_identical(visible$OfficeNotes, "Second note")
})

test_that("plot audit strength follows Access field-change semantics", {
  path <- local_sample_copy()
  context <- local_plot_context(path)
  plot_number <- sample_plot_number(context)

  strength_one <- vpro_plot_update(
    context,
    plot_number,
    env = list(Location = "Added"),
    user = "tester",
    audit_strength = 1
  )
  expect_identical(nrow(strength_one$audit), 0L)

  vpro_plot_update(
    context,
    plot_number,
    env = list(Location = NA_character_),
    user = "tester",
    audit_strength = 1
  )
  strength_two <- vpro_plot_update(
    context,
    plot_number,
    env = list(Location = "Added again"),
    user = "tester",
    audit_strength = 2
  )
  expect_identical(strength_two$audit$EditField, "Location")
  expect_true(is.na(strength_two$audit$BeforeEdit))
  expect_identical(strength_two$audit$AfterEdit, "Added again")

  strength_three <- vpro_plot_update(
    context,
    plot_number,
    env = list(Location = NA_character_),
    user = "tester",
    audit_strength = 3
  )
  expect_identical(strength_three$audit$EditField, "Location")
  expect_identical(strength_three$audit$BeforeEdit, "Added again")
  expect_true(is.na(strength_three$audit$AfterEdit))
})

test_that("plot update validates fields and rolls back the entire request", {
  path <- local_sample_copy()
  context <- local_plot_context(path)
  plot_number <- sample_plot_number(context)
  before <- vpro_plot_get(context, plot_number)

  expect_snapshot(
    error = TRUE,
    vpro_plot_update(
      context,
      plot_number,
      env = list(Location = "Must roll back"),
      admin = list(NotAField = "invalid"),
      user = "tester"
    )
  )
  expect_identical(vpro_plot_get(context, plot_number), before)
  expect_snapshot(
    error = TRUE,
    vpro_plot_update(context, plot_number, env = list(PlotNumber = "NEW"), user = "tester")
  )
  expect_snapshot(
    error = TRUE,
    vpro_plot_update(context, plot_number, admin = list(BECSiteUnit = "restricted"), user = "tester")
  )
  expect_snapshot(
    error = TRUE,
    vpro_plot_update(context, plot_number, admin = list(StartDate = 1800L), user = "tester")
  )
  expect_snapshot(
    error = TRUE,
    vpro_plot_update(context, plot_number, env = list(Elevation = "not numeric"), user = "tester")
  )
})

test_that("protected plot fields require explicit context authorization", {
  path <- local_sample_copy()
  con <- tryCatch(vpro_db_connect(), error = identity)
  if (inherits(con, "error")) {
    skip(conditionMessage(con))
  }
  context <- vpro_project_context(
    con = con,
    authorize = function(permission, resource) {
      identical(permission, "update_protected_plot_field") && identical(resource$field, "BECSiteUnit")
    }
  )
  withr::defer(vpro_db_disconnect(context$con))
  vpro_project_attach(context, path, "Sample")
  vpro_project_activate(context, "Sample")
  plot_number <- sample_plot_number(context)

  result <- vpro_plot_update(
    context,
    plot_number,
    admin = list(BECSiteUnit = "authorized"),
    user = "steward",
    audit_strength = 2
  )

  expect_identical(result$plot$admin$BECSiteUnit, "authorized")
  expect_identical(result$audit$EditField, "BECSiteUnit")
})

test_that("plot update uses configured user and audit strength", {
  root <- withr::local_tempdir()
  path <- file.path(root, "Sample.db")
  file.copy(system.file("extdata", "projects", "Sample.db", package = "vpro"), path)
  config_path <- file.path(root, "config.yml")
  vpro_config_install(config_path)
  accessor <- config_init(config_path)
  accessor("Current", "User", "configured-user")
  accessor("Audit", "AuditStrength", 2)
  context <- local_plot_context(path, config = accessor)
  plot_number <- sample_plot_number(context)

  result <- vpro_plot_update(context, plot_number, env = list(Location = "Configured audit"))

  expect_identical(result$audit$User, "configured-user")
  expect_identical(result$audit$EditField, "Location")
})
