create_hierarchy_fixture <- function(
  path,
  hierarchy = "Tree",
  rows = data.frame(
    ID = c(1L, 2L, 3L, 4L, 5L),
    Name = c("Root", "Child", "", "Cycle A", "Cycle B"),
    Parent = c(NA_integer_, 1L, 99L, 5L, 4L),
    Level = c(1L, 2L, 2L, 3L, 3L),
    Tag = NA_character_,
    MyOrder = sprintf("%05d", 1:5),
    ChildID = NA_integer_,
    StartChild = NA_integer_,
    LastChild = NA_integer_,
    Flag = FALSE,
    stringsAsFactors = FALSE
  )
) {
  con <- DBI::dbConnect(RSQLite::SQLite(), path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  table <- paste0(hierarchy, "_Hierarchy")
  DBI::dbExecute(
    con,
    paste0(
      'CREATE TABLE "', table, '" (',
      '"ID" INTEGER PRIMARY KEY, "Name" TEXT NOT NULL, "Parent" INTEGER, ',
      '"Level" SMALLINT, "Tag" TEXT, "MyOrder" TEXT, "ChildID" SMALLINT, ',
      '"StartChild" SMALLINT, "LastChild" SMALLINT, "Flag" BOOLEAN)'
    )
  )
  DBI::dbWriteTable(con, table, rows, append = TRUE)
  DBI::dbExecute(
    con,
    paste0('CREATE UNIQUE INDEX "uidx_', table, '_Name" ON "', table, '" ("Name")')
  )
  DBI::dbExecute(
    con,
    paste0('CREATE INDEX "idx_', table, '_Parent" ON "', table, '" ("Parent")')
  )
  if (!DBI::dbExistsTable(con, "_table_metadata")) {
    DBI::dbExecute(
      con,
      "CREATE TABLE _table_metadata (table_name TEXT PRIMARY KEY, description TEXT)"
    )
  }
  DBI::dbExecute(
    con,
    "INSERT INTO _table_metadata VALUES (?, ?)",
    params = list(table, "VP04")
  )
  invisible(path)
}

local_hierarchy_context <- function(config = NULL) {
  con <- tryCatch(vpro_db_connect(), error = identity)
  if (inherits(con, "error")) {
    testthat::skip(conditionMessage(con))
  }
  context <- vpro_project_context(con = con, config = config)
  withr::defer(vpro_db_disconnect(context$con), envir = parent.frame())
  context
}

test_that("hierarchy inspection validates structure and reports tree diagnostics", {
  path <- tempfile(fileext = ".db")
  create_hierarchy_fixture(path)

  inspection <- vpro_hierarchy_inspect(path, "Tree")

  expect_identical(inspection$version, "VP04")
  expect_identical(inspection$compatible, TRUE)
  expect_identical(inspection$unique_name_index, TRUE)
  expect_identical(inspection$parent_index, TRUE)
  expect_identical(inspection$diagnostics$total_rows, 5L)
  expect_identical(inspection$diagnostics$root_rows, 1L)
  expect_identical(inspection$diagnostics$blank_name_rows, 1L)
  expect_identical(inspection$diagnostics$orphan_parent_rows, 1L)
  expect_identical(inspection$diagnostics$cycle_rows, 2L)
})

test_that("hierarchy activation persists selection and shared detach is safe", {
  root <- withr::local_tempdir()
  config_path <- file.path(root, "config.yml")
  path <- file.path(root, "tree.db")
  vpro_config_install(config_path)
  accessor <- config_init(config_path)
  create_hierarchy_fixture(path)
  context <- local_hierarchy_context(accessor)

  record <- vpro_hierarchy_attach(context, path, "Tree")
  active <- vpro_hierarchy_activate(context, "Tree")

  expect_identical(active$hierarchy, "Tree")
  expect_identical(DBI::dbGetQuery(context$con, "SELECT COUNT(*) AS n FROM Hierarchy")$n, 5)
  expect_identical(accessor("Current", "CurrHierarchy"), "Tree")
  expect_identical(accessor("Current", "HierarchyPath"), normalizePath(path))
  expect_error(vpro_hierarchy_detach(context, "Tree"), "active VPRO hierarchy")

  expect_identical(vpro_hierarchy_deactivate(context), TRUE)
  expect_null(context$active_hierarchy)
  expect_identical(vpro_hierarchy_detach(context, "Tree"), TRUE)
  expect_identical(record$alias %in% vpro_db_list(context$con), FALSE)
  expect_identical(vpro_hierarchy_detach(context, "Tree"), FALSE)
})

test_that("hierarchy shares a project database attachment", {
  path <- system.file("extdata", "projects", "Sample.db", package = "vpro")
  context <- local_hierarchy_context()
  project <- vpro_project_attach(context, path, "Sample")
  hierarchy <- vpro_hierarchy_attach(context, path, "Sample")

  expect_identical(hierarchy$alias, project$alias)
  expect_identical(length(context$databases), 1L)
  vpro_hierarchy_activate(context, "Sample")
  expect_identical(DBI::dbGetQuery(context$con, "SELECT COUNT(*) AS n FROM Hierarchy")$n, 43)
  vpro_hierarchy_deactivate(context)
  expect_identical(vpro_hierarchy_detach(context, "Sample"), TRUE)
  expect_identical(project$alias %in% vpro_db_list(context$con), TRUE)
})

test_that("hierarchy save-as preserves rows, indexes, and metadata", {
  source_path <- tempfile(fileext = ".db")
  target_path <- tempfile(fileext = ".db")
  unlink(target_path)
  create_hierarchy_fixture(source_path)
  context <- local_hierarchy_context()
  vpro_hierarchy_attach(context, source_path, "Tree")
  vpro_hierarchy_activate(context, "Tree")

  vpro_hierarchy_save_as(context, "Tree", target_path, "Copy")
  inspection <- vpro_hierarchy_inspect(target_path, "Copy")

  expect_identical(inspection$version, "VP04")
  expect_identical(inspection$unique_name_index, TRUE)
  expect_identical(inspection$parent_index, TRUE)
  expect_identical(inspection$diagnostics$total_rows, 5L)
  expect_identical(context$active_hierarchy$hierarchy, "Tree")
  expect_error(
    vpro_hierarchy_save_as(context, "Tree", target_path, "Copy"),
    "already exists"
  )
  expect_error(
    vpro_hierarchy_save_as(context, "Tree", target_path, "Sample"),
    "reserved"
  )
})

test_that("hierarchy recovery restores valid state and clears invalid state", {
  root <- withr::local_tempdir()
  config_path <- file.path(root, "config.yml")
  path <- file.path(root, "tree.db")
  vpro_config_install(config_path)
  accessor <- config_init(config_path)
  create_hierarchy_fixture(path)
  accessor("Current", "CurrHierarchy", "Tree")
  accessor("Current", "HierarchyPath", path)
  context <- local_hierarchy_context(accessor)

  recovered <- vpro_hierarchy_recover(context)
  expect_identical(recovered$recovered, TRUE)
  expect_identical(context$active_hierarchy$hierarchy, "Tree")

  vpro_hierarchy_deactivate(context)
  accessor("Current", "CurrHierarchy", "Missing")
  accessor("Current", "HierarchyPath", file.path(root, "missing.db"))
  failed <- vpro_hierarchy_recover(context)

  expect_identical(failed$recovered, FALSE)
  expect_match(failed$error, "does not exist", fixed = TRUE)
  expect_null(context$active_hierarchy)
  expect_identical(accessor("Current", "CurrHierarchy"), "None")
  expect_identical(accessor("Current", "HierarchyPath"), "")
})

test_that("project recovery restores the default bundled hierarchy", {
  root <- withr::local_tempdir()
  config_path <- file.path(root, "config.yml")
  path <- system.file("extdata", "projects", "Sample.db", package = "vpro")
  vpro_config_install(config_path)
  accessor <- config_init(config_path)
  accessor("Current", "ProjectPath", path)
  context <- local_hierarchy_context(accessor)

  result <- vpro_project_recover(context, sample_path = path)

  expect_identical(result$fallback, FALSE)
  expect_identical(result$hierarchy$recovered, TRUE)
  expect_identical(context$active_hierarchy$hierarchy, "Sample")
  expect_identical(accessor("Current", "HierarchyPath"), normalizePath(path))
  expect_identical(DBI::dbGetQuery(context$con, "SELECT COUNT(*) AS n FROM Hierarchy")$n, 43)
})
