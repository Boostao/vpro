create_lifecycle_fixture <- function(
  path,
  project = "Alpha",
  version = "VP08",
  complete = TRUE,
  succession = FALSE
) {
  con <- DBI::dbConnect(RSQLite::SQLite(), path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  DBI::dbExecute(con, "PRAGMA foreign_keys = ON")

  env <- paste0(project, "_Env")
  admin <- paste0(project, "_Admin")
  DBI::dbExecute(
    con,
    paste0('CREATE TABLE "', env, '" ("PlotNumber" TEXT PRIMARY KEY)')
  )
  DBI::dbExecute(
    con,
    paste0(
      'CREATE TABLE "',
      admin,
      '" ("Plot" TEXT PRIMARY KEY, FOREIGN KEY ("Plot") REFERENCES "',
      env,
      '" ("PlotNumber") ON UPDATE CASCADE ON DELETE CASCADE)'
    )
  )
  DBI::dbExecute(
    con,
    paste0('CREATE TABLE "', project, '_Audit" ("EditWhen" TEXT)')
  )
  for (suffix in c("Humus", "Metadata", "Mineral", "Other")) {
    DBI::dbExecute(
      con,
      paste0('CREATE TABLE "', project, "_", suffix, '" ("PlotNumber" TEXT)')
    )
  }
  if (complete) {
    succession_field <- if (succession) '"SuccessionYear" INTEGER, ' else ""
    DBI::dbExecute(
      con,
      paste0(
        'CREATE TABLE "',
        project,
        '_Veg" (',
        '"ID" INTEGER, "PlotNumber" TEXT, ',
        succession_field,
        '"Species" TEXT, "Cover1" REAL, "Cover2" REAL, "Cover3" REAL, ',
        '"TotalA" REAL, "HeightA" REAL, "Cover4" REAL, "Cover5" REAL, ',
        '"Cover5a" REAL, "Cover5b" REAL, "Cover5c" REAL, "TotalB" REAL, ',
        '"HeightB" TEXT, "Cover6" REAL, "Height6" REAL, "Cover7" REAL, ',
        '"Cover8" REAL, "Cover9" REAL, "Collected" TEXT, ',
        'FOREIGN KEY ("PlotNumber") REFERENCES "',
        env,
        '" ("PlotNumber") ON UPDATE CASCADE ON DELETE CASCADE)'
      )
    )
  }

  DBI::dbExecute(
    con,
    "CREATE TABLE _table_metadata (table_name TEXT PRIMARY KEY, description TEXT)"
  )
  DBI::dbExecute(
    con,
    "INSERT INTO _table_metadata VALUES (?, ?)",
    params = list(env, version)
  )
  DBI::dbExecute(con, paste0('INSERT INTO "', env, '" VALUES (\'P1\')'))
  DBI::dbExecute(con, paste0('INSERT INTO "', admin, '" VALUES (\'P1\')'))
  invisible(path)
}

local_project_context <- function(config = NULL) {
  con <- tryCatch(vpro_db_connect(), error = identity)
  if (inherits(con, "error")) {
    testthat::skip(conditionMessage(con))
  }
  context <- vpro_project_context(con = con, config = config)
  withr::defer(vpro_db_disconnect(context$con), envir = parent.frame())
  context
}

test_that("project inspection reads VP08 table metadata", {
  path <- tempfile(fileext = ".db")
  create_lifecycle_fixture(path)

  inspection <- vpro_project_inspect(path, "Alpha")
  expect_identical(inspection$version, "VP08")
  expect_identical(inspection$compatible, TRUE)
})

test_that("attachment enforces version and complete-family gates", {
  context <- local_project_context()
  old_path <- tempfile(fileext = ".db")
  partial_path <- tempfile(fileext = ".db")
  create_lifecycle_fixture(old_path, version = "VP07")
  create_lifecycle_fixture(partial_path, project = "Partial", complete = FALSE)

  expect_snapshot(error = TRUE, vpro_project_attach(context, old_path, "Alpha"))
  expect_snapshot(error = TRUE, vpro_project_attach(context, partial_path, "Partial"))
})

test_that("activation creates scoped views and persists current state", {
  root <- withr::local_tempdir()
  config_path <- file.path(root, "config.yml")
  vpro_config_install(config_path)
  accessor <- config_init(config_path)
  context <- local_project_context(config = accessor)
  path <- file.path(root, "alpha.db")
  create_lifecycle_fixture(path)

  vpro_project_attach(context, path, "Alpha")
  vpro_project_activate(context, "Alpha")

  expect_identical(DBI::dbGetQuery(context$con, "SELECT PlotNumber FROM USysEnv")$PlotNumber, "P1")
  expect_identical(accessor("Current", "CurrProject"), "Alpha")
  expect_identical(accessor("Current", "CurrPlotlist"), "None")
  expect_identical(accessor("Current", "ProjectPath"), normalizePath(path))
  expect_snapshot(error = TRUE, vpro_project_detach(context, "Alpha"))
  expect_identical(file.exists(path), TRUE)
})

test_that("bundled Sample is a complete VP08 project", {
  path <- system.file("extdata", "projects", "Sample.db", package = "vpro")
  inspection <- vpro_project_inspect(path, "Sample")

  expect_identical(inspection$version, "VP08")
  expect_identical(inspection$compatible, TRUE)
  expect_identical(sum(inspection$validation$present), 8L)
})

test_that("bundled Sample creates active compatibility views", {
  path <- system.file("extdata", "projects", "Sample.db", package = "vpro")
  sqlite <- DBI::dbConnect(RSQLite::SQLite(), path)
  withr::defer(DBI::dbDisconnect(sqlite))
  expected_env <- DBI::dbGetQuery(
    sqlite,
    paste(
      'SELECT COUNT(*) AS n FROM (SELECT DISTINCT env.*, admin.* FROM "Sample_Env" AS env',
      'INNER JOIN "Sample_Admin" AS admin ON env."PlotNumber" = admin."Plot")'
    )
  )$n
  expected_veg <- DBI::dbGetQuery(sqlite, 'SELECT COUNT(*) AS n FROM "Sample_Veg"')$n
  context <- local_project_context()
  vpro_project_attach(context, path, "Sample")
  vpro_project_activate(context, "Sample")

  required_views <- c(
    "USysEnv",
    "USysVeg",
    "USysHumus",
    "USysMineral",
    "USysAuditTrail",
    "USysOther",
    "USysMetadata",
    paste0("USysVeg", LETTERS[1:4])
  )
  expect_setequal(intersect(DBI::dbListTables(context$con), required_views), required_views)
  expect_equal(DBI::dbGetQuery(context$con, "SELECT COUNT(*) AS n FROM USysEnv")$n, expected_env)
  expect_equal(DBI::dbGetQuery(context$con, "SELECT COUNT(*) AS n FROM USysVeg")$n, expected_veg)
})

test_that("startup recovery activates persisted projects", {
  root <- withr::local_tempdir()
  config_path <- file.path(root, "config.yml")
  project_path <- file.path(root, "alpha.db")
  vpro_config_install(config_path)
  accessor <- config_init(config_path)
  accessor("Current", "CurrProject", "Alpha")
  accessor("Current", "ProjectPath", project_path)
  create_lifecycle_fixture(project_path)
  context <- local_project_context(config = accessor)

  result <- vpro_project_recover(
    context,
    sample_path = file.path(root, "unused-sample.db")
  )

  expect_identical(result$active$project, "Alpha")
  expect_identical(result$fallback, FALSE)
  expect_null(result$primary_error)
  expect_identical(DBI::dbGetQuery(context$con, "SELECT COUNT(*) AS n FROM USysEnv")$n, 1)
})

test_that("startup recovery falls back to Sample and persists recovery", {
  root <- withr::local_tempdir()
  config_path <- file.path(root, "config.yml")
  sample_path <- file.path(root, "Sample.db")
  vpro_config_install(config_path)
  accessor <- config_init(config_path)
  accessor("Current", "CurrProject", "Missing")
  accessor("Current", "ProjectPath", file.path(root, "missing.db"))
  create_lifecycle_fixture(sample_path, project = "Sample")
  context <- local_project_context(config = accessor)

  result <- vpro_project_recover(context, sample_path = sample_path)

  expect_identical(result$active$project, "Sample")
  expect_identical(result$fallback, TRUE)
  expect_match(result$primary_error, "does not exist", fixed = TRUE)
  expect_identical(accessor("Current", "CurrProject"), "Sample")
  expect_identical(accessor("Current", "CurrPlotlist"), "None")
  expect_identical(accessor("Current", "ProjectPath"), normalizePath(sample_path))
})

test_that("activation selects succession vegetation columns", {
  context <- local_project_context()
  path <- tempfile(fileext = ".db")
  create_lifecycle_fixture(path, succession = TRUE)

  vpro_project_attach(context, path, "Alpha")
  vpro_project_activate(context, "Alpha")

  expect_true("SuccessionYear" %in% DBI::dbListFields(context$con, "USysVegA"))
  expect_false("Cover5a" %in% DBI::dbListFields(context$con, "USysVegA"))
})

test_that("save-as clones the core family and rejects collisions", {
  context <- local_project_context()
  source_path <- tempfile(fileext = ".db")
  target_path <- tempfile(fileext = ".db")
  unlink(target_path)
  create_lifecycle_fixture(source_path)
  vpro_project_attach(context, source_path, "Alpha")

  vpro_project_save_as(context, "Alpha", target_path, "Beta")
  inspection <- vpro_project_inspect(target_path, "Beta")
  expect_identical(inspection$compatible, TRUE)

  target <- DBI::dbConnect(RSQLite::SQLite(), target_path)
  withr::defer(DBI::dbDisconnect(target))
  expect_identical(DBI::dbGetQuery(target, 'SELECT PlotNumber FROM "Beta_Env"')$PlotNumber, "P1")
  foreign_keys <- DBI::dbGetQuery(target, 'PRAGMA foreign_key_list("Beta_Admin")')
  expect_identical(foreign_keys$table, "Beta_Env")
  expect_identical(foreign_keys$on_delete, "CASCADE")

  expect_snapshot(error = TRUE, vpro_project_save_as(context, "Alpha", target_path, "Beta"))
})

test_that("detaching a non-current project preserves its database", {
  context <- local_project_context()
  path <- tempfile(fileext = ".db")
  create_lifecycle_fixture(path)
  vpro_project_attach(context, path, "Alpha")

  expect_identical(vpro_project_detach(context, "Alpha"), TRUE)
  expect_identical(file.exists(path), TRUE)
  expect_identical(vpro_project_detach(context, "Alpha"), FALSE)
})
