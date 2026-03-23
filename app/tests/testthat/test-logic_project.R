# Tests for logic_project.R under the SQLite-per-project runtime.

source(here::here("app", "R", "logic", "00.db.R"))
source(here::here("app", "R", "logic", "db_connections.R"))
source(here::here("app", "R", "logic", "01.state.R"))
source(here::here("app", "R", "logic", "logic_state.R"))
source(here::here("app", "R", "logic", "logic_project.R"))

make_runtime_root <- function() {
  root <- tempfile("vpro_runtime_")
  dir.create(root, recursive = TRUE)
  dir.create(file.path(root, "data", "projects"), recursive = TRUE)
  file.copy(
    here::here("app", "data", "projects", "Sample.db"),
    file.path(root, "data", "projects", "Sample.db"),
    overwrite = TRUE
  )

  yaml::write_yaml(
    list(
      Current = list(CurrProject = "Sample", CurrVegProfile = "Sample"),
      System = list(Location = root)
    ),
    file.path(root, "config.yml")
  )

  root
}

make_project_file <- function(root, project_id, plots = c("P1", "P2")) {
  path <- file.path(root, "imports", paste0(project_id, ".db"))
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)

  con <- db_con()
  on.exit(try(DBI::dbDisconnect(con, shutdown = TRUE), silent = TRUE), add = TRUE)

  DBI::dbExecute(
    con,
    paste0("ATTACH ", DBI::dbQuoteString(con, path), " AS ", DBI::dbQuoteIdentifier(con, project_id), " (TYPE sqlite)")
  )

  quoted <- function(table_name) {
    DBI::dbQuoteIdentifier(con, DBI::Id(project_id, paste0(project_id, "_", table_name)))
  }

  DBI::dbExecute(con, paste0("CREATE TABLE ", quoted("Metadata"), " (ProjectID TEXT, ProjectTitle TEXT)"))
  DBI::dbExecute(con, paste0("CREATE TABLE ", quoted("Env"), " (PlotNumber TEXT, ProjectID TEXT)"))
  DBI::dbExecute(con, paste0("CREATE TABLE ", quoted("Veg"), " (PlotNumber TEXT, Species TEXT, Layer TEXT)"))
  DBI::dbExecute(con, paste0("CREATE TABLE ", quoted("Audit"), " (Project TEXT, User TEXT, \"Table\" TEXT, EditWhen TIMESTAMP)"))
  DBI::dbExecute(con, paste0("CREATE TABLE ", quoted("SU"), " (PlotNumber TEXT, SiteUnit TEXT)"))
  DBI::dbExecute(con, paste0("CREATE TABLE ", quoted("Hierarchy"), " (ID INTEGER, Parent INTEGER, Name TEXT, Level TEXT, MyOrder INTEGER)"))

  DBI::dbExecute(
    con,
    paste0("INSERT INTO ", quoted("Metadata"), " (ProjectID, ProjectTitle) VALUES (?, ?)"),
    list(project_id, paste0(project_id, " Title"))
  )
  for (i in seq_along(plots)) {
    DBI::dbExecute(
      con,
      paste0("INSERT INTO ", quoted("Env"), " (PlotNumber, ProjectID) VALUES (?, ?)"),
      list(plots[[i]], project_id)
    )
    DBI::dbExecute(
      con,
      paste0("INSERT INTO ", quoted("SU"), " (PlotNumber, SiteUnit) VALUES (?, ?)"),
      list(plots[[i]], paste0("SU-", i))
    )
    DBI::dbExecute(
      con,
      paste0("INSERT INTO ", quoted("Veg"), " (PlotNumber, Species, Layer) VALUES (?, ?, ? )"),
      list(plots[[i]], paste0("SPP", i), "A")
    )
  }
  DBI::dbExecute(
    con,
    paste0("INSERT INTO ", quoted("Hierarchy"), " (ID, Parent, Name, Level, MyOrder) VALUES (1, NULL, ?, 'site', 1)"),
    list(project_id)
  )

  path
}

test_that("list_open_projects returns attached project aliases", {
  root <- make_runtime_root()
  old_wd <- setwd(root)
  on.exit(setwd(old_wd), add = TRUE)

  path_a <- make_project_file(root, "ProjA")
  path_b <- make_project_file(root, "ProjB")
  con <- db_con()
  on.exit(try(db_close(con), silent = TRUE), add = TRUE)

  open_project(con, path_a)
  open_project(con, path_b)

  expect_setequal(list_open_projects(con), c("ProjA", "ProjB"))
})

test_that("list_projects_in_file discovers project prefixes from sqlite files", {
  root <- make_runtime_root()
  path <- make_project_file(root, "AlpineBC", plots = c("AP1", "AP2"))

  expect_equal(list_projects_in_file(path), "AlpineBC")
})

test_that("open_project attaches project sqlite database", {
  root <- make_runtime_root()
  old_wd <- setwd(root)
  on.exit(setwd(old_wd), add = TRUE)

  path <- make_project_file(root, "AttachMe", plots = c("AP1", "AP2"))
  con <- db_con()
  on.exit(try(db_close(con), silent = TRUE), add = TRUE)

  pid <- open_project(con, path)
  expect_equal(pid, "AttachMe")
  expect_true(DBI::dbExistsTable(con, db_id("Metadata", "AttachMe", prj = TRUE)))
  expect_true(DBI::dbExistsTable(con, db_id("Env", "AttachMe", prj = TRUE)))
})

test_that("save_project copies the canonical project database", {
  root <- make_runtime_root()
  old_wd <- setwd(root)
  on.exit(setwd(old_wd), add = TRUE)

  path <- make_project_file(root, "SavedProj")
  file.copy(path, project_db_path("SavedProj"), overwrite = TRUE)

  con <- db_con()
  on.exit(try(db_close(con), silent = TRUE), add = TRUE)
  open_project(con, project_db_path("SavedProj"))

  dest <- tempfile(fileext = ".db")
  save_project(con, "SavedProj", dest)

  expect_equal(list_projects_in_file(dest), "SavedProj")
})

test_that("close_project detaches the project database", {
  root <- make_runtime_root()
  old_wd <- setwd(root)
  on.exit(setwd(old_wd), add = TRUE)

  path <- make_project_file(root, "CloseMe")
  con <- db_con()
  on.exit(try(db_close(con), silent = TRUE), add = TRUE)
  open_project(con, path)

  expect_true("CloseMe" %in% list_open_projects(con))
  close_project(con, "CloseMe")
  expect_false("CloseMe" %in% list_open_projects(con))
})

test_that("new_project creates a canonical project sqlite db and metadata row", {
  root <- make_runtime_root()
  old_wd <- setwd(root)
  on.exit(setwd(old_wd), add = TRUE)

  con <- db_con()
  on.exit(try(db_close(con), silent = TRUE), add = TRUE)

  new_project(con, "BCGov2025", "BCGov 2025 Alpine")

  expect_true(file.exists(project_db_path("BCGov2025")))
  expect_true("BCGov2025" %in% list_open_projects(con))

  meta <- DBI::dbGetQuery(
    con,
    paste0("SELECT ProjectID, ProjectTitle FROM ", DBI::dbQuoteIdentifier(con, db_id("Metadata", "BCGov2025", prj = TRUE)))
  )
  expect_equal(meta$ProjectID[[1]], "BCGov2025")
  expect_equal(meta$ProjectTitle[[1]], "BCGov 2025 Alpine")
})

test_that("project_capture_baseline stores a canonical .db baseline copy", {
  root <- make_runtime_root()
  old_wd <- setwd(root)
  on.exit(setwd(old_wd), add = TRUE)

  path <- make_project_file(root, "BaseProj", plots = c("BP1"))
  file.copy(path, project_db_path("BaseProj"), overwrite = TRUE)

  con <- db_con()
  on.exit(try(db_close(con), silent = TRUE), add = TRUE)
  open_project(con, project_db_path("BaseProj"))

  baseline <- project_capture_baseline(con, "BaseProj", source_kind = "test")

  expect_equal(tools::file_ext(baseline$baseline_path[[1]]), "db")
  expect_true(file.exists(baseline$baseline_path[[1]]))
  expect_true(project_baseline_has_tables(con, "BaseProj"))
})

test_that("project_read_baseline_rows reads prefixed tables from .db baselines", {
  root <- make_runtime_root()
  old_wd <- setwd(root)
  on.exit(setwd(old_wd), add = TRUE)

  path <- make_project_file(root, "ReadBase", plots = c("RB1"))
  file.copy(path, project_db_path("ReadBase"), overwrite = TRUE)

  con <- db_con()
  on.exit(try(db_close(con), silent = TRUE), add = TRUE)
  open_project(con, project_db_path("ReadBase"))
  project_capture_baseline(con, "ReadBase", source_kind = "test")

  rows <- project_read_baseline_rows(con, "ReadBase", "Env", "PlotNumber", "RB1")
  expect_equal(rows$PlotNumber[[1]], "RB1")
  expect_equal(rows$ProjectID[[1]], "ReadBase")
})

test_that("project_replace_baseline_from_file accepts canonical .db backups", {
  root <- make_runtime_root()
  old_wd <- setwd(root)
  on.exit(setwd(old_wd), add = TRUE)

  backup_path <- make_project_file(root, "ReplaceMe", plots = c("RP1"))
  con <- db_con()
  on.exit(try(db_close(con), silent = TRUE), add = TRUE)

  baseline <- project_replace_baseline_from_file(con, "ReplaceMe", backup_path, source_kind = "sync_backup_upload")
  expect_true(file.exists(baseline$baseline_path[[1]]))
  expect_true(project_baseline_has_tables(con, "ReplaceMe"))
})

test_that("set_project updates config-backed current project and refreshes context views", {
  root <- make_runtime_root()
  old_wd <- setwd(root)
  on.exit(setwd(old_wd), add = TRUE)

  path <- make_project_file(root, "SwitchMe", plots = c("SW1"))
  con <- db_con()
  on.exit(try(db_close(con), silent = TRUE), add = TRUE)
  open_project(con, path)

  state <- init_sys_state()
  set_project(state, "SwitchMe", con)

  expect_equal((config("Current", "CurrProject") %||% NULL), "SwitchMe")
  expect_equal(shiny::isolate(state$CurrProject), "SwitchMe")

  env_rows <- DBI::dbGetQuery(con, "SELECT ProjectID, PlotNumber FROM Env")
  expect_equal(env_rows$ProjectID[[1]], "SwitchMe")
  expect_equal(env_rows$PlotNumber[[1]], "SW1")
})
