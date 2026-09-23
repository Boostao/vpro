succession_fixture <- function(path, project = "Alpha", rows = TRUE, state = "unconverted") {
  con <- DBI::dbConnect(RSQLite::SQLite(), path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  DBI::dbExecute(con, "PRAGMA foreign_keys = ON")
  env_field <- if (state %in% c("converted", "inconsistent")) ', "SuccessionPlot" INTEGER DEFAULT 0' else ""
  veg_field <- if (state %in% c("converted", "partial")) ', "SuccessionYear" INTEGER' else ""
  DBI::dbExecute(con, paste0('CREATE TABLE "', project, '_Env" ("PlotNumber" TEXT PRIMARY KEY', env_field, ')'))
  DBI::dbExecute(
    con,
    paste0(
      'CREATE TABLE "',
      project,
      '_Veg" ("PlotNumber" TEXT, "Species" TEXT, "ID" INTEGER',
      veg_field,
      ', FOREIGN KEY ("PlotNumber") REFERENCES "',
      project,
      '_Env"("PlotNumber"))'
    )
  )
  for (suffix in c("Admin", "Audit", "Humus", "Metadata", "Mineral", "Other")) {
    DBI::dbExecute(con, paste0('CREATE TABLE "', project, '_', suffix, '" ("PlotNumber" TEXT)'))
  }
  DBI::dbExecute(con, paste0('CREATE INDEX "idx_', project, '_Veg_ID" ON "', project, '_Veg" ("ID")'))
  DBI::dbExecute(con, 'CREATE TABLE _table_metadata (table_name TEXT, description TEXT)')
  DBI::dbExecute(con, 'INSERT INTO _table_metadata VALUES (?, ?)', params = list(paste0(project, '_Env'), 'VP08'))
  if (rows) {
    DBI::dbExecute(con, paste0('INSERT INTO "', project, '_Env" ("PlotNumber") VALUES ("P1"), ("P2")'))
    if (state %in% c("converted", "partial")) {
      DBI::dbExecute(con, paste0('INSERT INTO "', project, '_Veg" ("PlotNumber", "Species", "ID", "SuccessionYear") VALUES ("P1", "X", 12, 2021), ("P2", "Y", 34, 2021)'))
    } else {
      DBI::dbExecute(con, paste0('INSERT INTO "', project, '_Veg" ("PlotNumber", "Species", "ID") VALUES ("P1", "X", 12), ("P2", "Y", 34)'))
    }
  }
  invisible(path)
}

succession_authorize <- function(permission) {
  function(request, resource) identical(request, permission)
}

test_that("succession conversion preserves rows and produces a restorable WAL-safe backup", {
  path <- tempfile(fileext = '.db')
  backup <- tempfile(fileext = '.db')
  succession_fixture(path)
  con <- DBI::dbConnect(RSQLite::SQLite(), path)
  DBI::dbGetQuery(con, 'PRAGMA journal_mode = WAL')
  DBI::dbExecute(con, 'CREATE TABLE unrelated (value TEXT)')
  DBI::dbExecute(con, "INSERT INTO unrelated VALUES ('retained')")
  DBI::dbDisconnect(con)
  authorize <- succession_authorize('convert_succession')
  receipt <- vpro_project_convert_succession(path, 'Alpha', 2021, backup, authorize)
  expect_identical(receipt$state_before, 'unconverted')
  expect_identical(receipt$state_after, 'converted')
  expect_identical(receipt$year, 2021L)
  expect_identical(receipt$activation, 'not attempted; attach and activate the project in a fresh context')
  expect_identical(receipt$backup_md5, unname(tools::md5sum(backup)))
  expect_identical(vpro_project_succession_status(backup, 'Alpha')$state, 'unconverted')
  status <- vpro_project_succession_status(path, 'Alpha')
  expect_identical(status$years$n, 2L)
  expect_identical(status$years$value, 2021L)
  expect_identical(status$flags$value, 0L)
  con <- DBI::dbConnect(RSQLite::SQLite(), path)
  expect_identical(DBI::dbGetQuery(con, 'SELECT ID FROM Alpha_Veg ORDER BY ID')$ID, c(12L, 34L))
  expect_identical(DBI::dbGetQuery(con, 'SELECT value FROM unrelated')$value, 'retained')
  DBI::dbExecute(con, 'INSERT INTO Alpha_Env (PlotNumber) VALUES ("P3")')
  expect_identical(DBI::dbGetQuery(con, 'SELECT SuccessionPlot FROM Alpha_Env WHERE PlotNumber="P3"')$SuccessionPlot, 0L)
  expect_identical(nrow(DBI::dbGetQuery(con, 'PRAGMA foreign_key_check')), 0L)
  expect_identical(DBI::dbGetQuery(con, "SELECT name FROM sqlite_master WHERE type='index' AND name='idx_Alpha_Veg_ID'")$name, 'idx_Alpha_Veg_ID')
  DBI::dbDisconnect(con)
  expect_identical(vpro_project_succession_status(backup, 'Alpha')$env_rows, 2L)
  expect_snapshot(error = TRUE, vpro_project_convert_succession(path, 'Alpha', 2022, tempfile(fileext = '.db'), authorize))
})

test_that("partial recovery adds only Env flag and refuses unexpected years", {
  path <- tempfile(fileext = '.db')
  succession_fixture(path, state = 'partial')
  authorize <- succession_authorize('recover_succession')
  expect_snapshot(error = TRUE, vpro_project_convert_succession(path, 'Alpha', 2022, tempfile(fileext = '.db'), authorize))
  receipt <- vpro_project_recover_succession(path, 'Alpha', tempfile(fileext = '.db'), authorize)
  expect_identical(receipt$year, 2021L)
  expect_identical(vpro_project_succession_status(path, 'Alpha')$years$value, 2021L)
  expect_identical(vpro_project_succession_status(path, 'Alpha')$flags$value, 0L)

  mixed <- tempfile(fileext = '.db')
  succession_fixture(mixed, state = 'partial')
  con <- DBI::dbConnect(RSQLite::SQLite(), mixed)
  DBI::dbExecute(con, 'UPDATE Alpha_Veg SET SuccessionYear = 2020 WHERE ID = 12')
  DBI::dbDisconnect(con)
  expect_snapshot(error = TRUE, vpro_project_recover_succession(mixed, 'Alpha', tempfile(fileext = '.db'), authorize))
  expect_identical(vpro_project_succession_status(mixed, 'Alpha')$state, 'partial')
  con <- DBI::dbConnect(RSQLite::SQLite(), mixed)
  DBI::dbExecute(con, 'UPDATE Alpha_Veg SET SuccessionYear = NULL WHERE ID = 12')
  DBI::dbDisconnect(con)
  expect_snapshot(error = TRUE, vpro_project_recover_succession(mixed, 'Alpha', tempfile(fileext = '.db'), authorize))
  expect_identical(vpro_project_succession_status(mixed, 'Alpha')$state, 'partial')
})

test_that("transaction failures roll back both SQLite schema changes", {
  for (stage in c('after_ddl', 'after_update', 'after_env')) {
    path <- tempfile(fileext = '.db')
    backup <- tempfile(fileext = '.db')
    succession_fixture(path)
    authorize <- succession_authorize('convert_succession')
    before <- vpro_project_succession_status(path, 'Alpha')
    expect_error(vpro:::vpro_succession_apply(NULL, path, 'Alpha', backup, 'convert_succession', 'unconverted', 2021L, authorize, .fail_at = stage), 'Injected succession failure')
    expect_identical(vpro_project_succession_status(path, 'Alpha'), before)
    expect_identical(vpro_project_succession_status(backup, 'Alpha')$state, 'unconverted')
  }
})

test_that("preflight rejects protected targets and requires explicit authorization", {
  path <- tempfile(fileext = '.db')
  succession_fixture(path)
  authorize <- succession_authorize('recover_succession')
  expect_snapshot(error = TRUE, vpro_project_convert_succession(path, 'Alpha', 2021, tempfile(fileext = '.db'), authorize))
  expect_snapshot(error = TRUE, vpro_project_convert_succession(path, 'Sample', 2021, tempfile(fileext = '.db'), authorize))
  expect_snapshot(error = TRUE, vpro_project_convert_succession(path, 'Alpha', 0, tempfile(fileext = '.db'), authorize))
  authorize <- function(...) TRUE
  expect_snapshot(error = TRUE, vpro_project_convert_succession(path, 'Alpha', 2021, path, authorize))
  expect_identical(vpro_project_succession_status(path, 'Alpha')$state, 'unconverted')
  expect_snapshot(error = TRUE, vpro_project_succession_status(system.file('extdata', 'projects', 'Sample.db', package = 'vpro'), 'Missing'))
})

test_that("a realistic VP08 copy converts, restores, and activates in a fresh coordinator", {
  source <- system.file("extdata", "projects", "Sample.db", package = "vpro")
  skip_if(!nzchar(source), "Bundled Sample database is unavailable")
  root <- withr::local_tempdir()
  path <- file.path(root, "Oracle.db")
  backup <- file.path(root, "Oracle-before.db")
  restored <- file.path(root, "Oracle-restored.db")
  expect_identical(file.copy(source, path), TRUE)
  sqlite <- DBI::dbConnect(RSQLite::SQLite(), path)
  for (suffix in .vpro_core_project_suffixes) {
    DBI::dbExecute(sqlite, paste0('ALTER TABLE "Sample_', suffix, '" RENAME TO "Oracle_', suffix, '"'))
    DBI::dbExecute(sqlite, 'UPDATE _table_metadata SET table_name = ? WHERE table_name = ?', params = list(paste0("Oracle_", suffix), paste0("Sample_", suffix)))
  }
  original <- lapply(c("Oracle_Env", "Oracle_Veg"), function(table) {
    DBI::dbGetQuery(sqlite, paste('SELECT rowid, * FROM', DBI::dbQuoteIdentifier(sqlite, table), 'ORDER BY rowid'))
  })
  original_schema <- DBI::dbGetQuery(
    sqlite,
    "SELECT type, name, tbl_name, sql FROM sqlite_master WHERE tbl_name IN ('Oracle_Env', 'Oracle_Veg') AND type IN ('table', 'index') ORDER BY type, name"
  )
  expect_equal(nrow(DBI::dbGetQuery(sqlite, 'PRAGMA foreign_key_check')), 0L)
  DBI::dbDisconnect(sqlite)

  status <- vpro_project_succession_status(path, "Oracle")
  expect_identical(status$state, "unconverted")
  receipt <- vpro_project_convert_succession(path, "Oracle", 2021L, backup, succession_authorize("convert_succession"))
  expect_identical(receipt$veg_rows, status$veg_rows)
  expect_identical(receipt$env_rows, status$env_rows)
  expect_identical(receipt$activation, "not attempted; attach and activate the project in a fresh context")
  expect_identical(file.copy(backup, restored), TRUE)
  expect_identical(vpro_project_succession_status(restored, "Oracle")$state, "unconverted")
  restored_con <- DBI::dbConnect(RSQLite::SQLite(), restored, flags = RSQLite::SQLITE_RO)
  for (i in seq_along(original)) {
    table <- c("Oracle_Env", "Oracle_Veg")[[i]]
    expect_identical(DBI::dbGetQuery(restored_con, paste('SELECT rowid, * FROM', DBI::dbQuoteIdentifier(restored_con, table), 'ORDER BY rowid')), original[[i]])
  }
  expect_identical(
    DBI::dbGetQuery(
      restored_con,
      "SELECT type, name, tbl_name, sql FROM sqlite_master WHERE tbl_name IN ('Oracle_Env', 'Oracle_Veg') AND type IN ('table', 'index') ORDER BY type, name"
    ),
    original_schema
  )
  expect_identical(DBI::dbGetQuery(restored_con, 'PRAGMA integrity_check')[[1L]][[1L]], "ok")
  expect_equal(nrow(DBI::dbGetQuery(restored_con, 'PRAGMA foreign_key_check')), 0L)
  DBI::dbDisconnect(restored_con)

  config_path <- file.path(root, "config.yml")
  vpro_config_install(config_path)
  accessor <- config_init(config_path)
  coordinator <- tryCatch(vpro_db_connect(), error = identity)
  if (inherits(coordinator, "error")) {
    skip(conditionMessage(coordinator))
  }
  withr::defer(vpro_db_disconnect(coordinator))
  context <- vpro_project_context(con = coordinator, config = accessor)
  vpro_project_attach(context, path, "Oracle")
  expect_error(
    vpro_project_convert_succession(path, "Oracle", 2022L, file.path(root, "refused.db"), succession_authorize("convert_succession"), context = context),
    "Detach this database from the VPRO context"
  )
  vpro_project_activate(context, "Oracle")
  expect_identical(accessor("Current", "CurrProject"), "Oracle")
  expect_identical(accessor("Current", "ProjectPath"), normalizePath(path))
  expect_equal(DBI::dbGetQuery(coordinator, 'SELECT COUNT(*) AS n FROM USysEnv')$n, status$env_rows)
  expect_equal(DBI::dbGetQuery(coordinator, 'SELECT COUNT(*) AS n FROM USysVeg')$n, status$veg_rows)
  expect_equal(DBI::dbGetQuery(coordinator, 'SELECT DISTINCT SuccessionPlot FROM USysEnv')$SuccessionPlot, 0)
  for (view in paste0("USysVeg", LETTERS[1:4])) {
    expect_true("SuccessionYear" %in% DBI::dbListFields(coordinator, view))
    expect_equal(DBI::dbGetQuery(coordinator, paste('SELECT DISTINCT SuccessionYear FROM', view))$SuccessionYear, 2021)
  }
  expect_error(
    vpro_project_recover_succession(path, "Oracle", file.path(root, "attached.db"), succession_authorize("recover_succession"), context = context),
    "Detach this database from the VPRO context"
  )
  vpro_db_disconnect(coordinator)
  expect_identical(file.copy(backup, path, overwrite = TRUE), TRUE)
  expect_identical(unname(tools::md5sum(path)), receipt$backup_md5)
  expect_identical(vpro_project_succession_status(path, "Oracle")$state, "unconverted")
  restored_coordinator <- vpro_db_connect()
  withr::defer(vpro_db_disconnect(restored_coordinator))
  restored_context <- vpro_project_context(con = restored_coordinator)
  vpro_project_attach(restored_context, path, "Oracle")
  vpro_project_activate(restored_context, "Oracle")
  expect_equal(DBI::dbGetQuery(restored_coordinator, 'SELECT COUNT(*) AS n FROM USysVeg')$n, status$veg_rows)
  expect_equal(DBI::dbGetQuery(restored_coordinator, 'SELECT COUNT(*) AS n FROM USysEnv')$n, status$env_rows)
  expect_identical("SuccessionYear" %in% DBI::dbListFields(restored_coordinator, "USysVegA"), FALSE)
})

test_that("WAL readers can remain open during a consistent succession backup", {
  path <- tempfile(fileext = ".db")
  backup <- tempfile(fileext = ".db")
  succession_fixture(path)
  writer <- DBI::dbConnect(RSQLite::SQLite(), path)
  DBI::dbGetQuery(writer, 'PRAGMA journal_mode = WAL')
  reader <- DBI::dbConnect(RSQLite::SQLite(), path, flags = RSQLite::SQLITE_RO)
  withr::defer(DBI::dbDisconnect(reader))
  DBI::dbExecute(reader, 'BEGIN')
  expect_identical(DBI::dbGetQuery(reader, 'SELECT COUNT(*) AS n FROM Alpha_Veg')$n, 2L)
  DBI::dbExecute(writer, 'INSERT INTO Alpha_Env (PlotNumber) VALUES ("P3")')
  DBI::dbDisconnect(writer)
  receipt <- vpro_project_convert_succession(path, "Alpha", 2021L, backup, succession_authorize("convert_succession"))
  expect_identical(receipt$env_rows, 3L)
  expect_identical(vpro_project_succession_status(backup, "Alpha")$env_rows, 3L)
  DBI::dbExecute(reader, 'ROLLBACK')
})

test_that("a competing writer prevents conversion while retaining a consistent backup", {
  path <- tempfile(fileext = ".db")
  backup <- tempfile(fileext = ".db")
  succession_fixture(path)
  writer <- DBI::dbConnect(RSQLite::SQLite(), path)
  withr::defer({
    if (DBI::dbIsValid(writer)) {
      DBI::dbExecute(writer, 'ROLLBACK')
      DBI::dbDisconnect(writer)
    }
  })
  DBI::dbExecute(writer, 'BEGIN IMMEDIATE')
  DBI::dbExecute(writer, 'INSERT INTO Alpha_Env (PlotNumber) VALUES ("uncommitted")')
  before <- vpro_project_succession_status(path, "Alpha")
  # The writer holds the lock until the conversion attempt has returned.
  expect_error(vpro_project_convert_succession(path, "Alpha", 2021L, backup, succession_authorize("convert_succession")), "locked")
  expect_identical(vpro_project_succession_status(backup, "Alpha"), within(before, path <- normalizePath(backup)))
  DBI::dbExecute(writer, 'ROLLBACK')
  DBI::dbDisconnect(writer)
  expect_identical(vpro_project_succession_status(path, "Alpha"), before)
})

test_that("empty Veg and Env families can convert and recover", {
  path <- tempfile(fileext = '.db')
  succession_fixture(path, rows = FALSE)
  authorize <- succession_authorize('convert_succession')
  receipt <- vpro_project_convert_succession(path, 'Alpha', 2021, tempfile(fileext = '.db'), authorize)
  expect_identical(receipt$veg_rows, 0L)
  expect_identical(receipt$env_rows, 0L)
  expect_identical(vpro_project_succession_status(path, 'Alpha')$state, 'converted')
})
