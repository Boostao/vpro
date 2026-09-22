local_other_context <- function(path) {
  con <- tryCatch(vpro_db_connect(), error = identity)
  if (inherits(con, "error")) {
    testthat::skip(conditionMessage(con))
  }
  context <- vpro_project_context(con = con)
  withr::defer(vpro_db_disconnect(context$con), envir = parent.frame())
  vpro_project_attach(context, path, "Sample")
  vpro_project_activate(context, "Sample")
  context
}

local_other_sample_copy <- function() {
  path <- tempfile(fileext = ".db")
  file.copy(system.file("extdata", "projects", "Sample.db", package = "vpro"), path)
  path
}

other_plot_numbers <- function(context) {
  DBI::dbGetQuery(
    context$con,
    'SELECT "PlotNumber" FROM USysEnv ORDER BY "PlotNumber" LIMIT 2'
  )$PlotNumber
}

seed_other_rows <- function(path, rows) {
  con <- DBI::dbConnect(RSQLite::SQLite(), path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  DBI::dbAppendTable(con, "Sample_Other", rows)
}

test_that("Other rows require an active project and existing plot", {
  path <- local_other_sample_copy()
  con <- tryCatch(vpro_db_connect(), error = identity)
  if (inherits(con, "error")) {
    skip(conditionMessage(con))
  }
  context <- vpro_project_context(con = con)
  withr::defer(vpro_db_disconnect(context$con))

  expect_snapshot(error = TRUE, vpro_plot_other_list(context, "1976071"))
  vpro_project_attach(context, path, "Sample")
  vpro_project_activate(context, "Sample")
  plot_number <- other_plot_numbers(context)[[1]]
  expect_identical(nrow(vpro_plot_other_list(context, plot_number)), 0L)
  expect_snapshot(error = TRUE, vpro_plot_other_list(context, "Missing"))
})

test_that("Other rows are filtered and ordered by DataName and ID", {
  path <- local_other_sample_copy()
  context <- local_other_context(path)
  plots <- other_plot_numbers(context)
  rows <- data.frame(
    PlotNumber = c(plots[[1]], plots[[1]], plots[[1]], plots[[2]]),
    DataName = c("Zulu", "Alpha", "Alpha", "Alpha"),
    DataItem = c("z", "second", "first", "other plot"),
    ID = c(9003L, 9002L, 9001L, 9004L),
    stringsAsFactors = FALSE
  )
  seed_other_rows(path, rows)

  result <- vpro_plot_other_list(context, plots[[1]])

  expect_identical(result$ID, c(9001L, 9002L, 9003L))
  expect_true(all(result$PlotNumber == plots[[1]]))
  expect_identical(result$DataItem, c("first", "second", "z"))
})

test_that("Other updates one identified row and writes child audit records", {
  path <- local_other_sample_copy()
  context <- local_other_context(path)
  plot_number <- other_plot_numbers(context)[[1]]
  seed_other_rows(
    path,
    data.frame(
      PlotNumber = c(plot_number, plot_number),
      DataName = c("First", "Sibling"),
      DataItem = c("Before", "Unchanged"),
      ID = c(9101L, 9102L),
      stringsAsFactors = FALSE
    )
  )

  result <- vpro_plot_other_update(
    context,
    plot_number,
    9101L,
    changes = list(DataItem = "After", UserFlag1 = TRUE),
    user = "other-editor",
    audit_strength = 2
  )

  expect_identical(result$other$DataItem, "After")
  expect_identical(result$other$UserFlag1, 1L)
  expect_setequal(result$audit$EditField, c("DataItem", "UserFlag1"))
  expect_true(all(result$audit$Table == "_Other"))
  expect_true(all(result$audit$ID == 9101L))
  expect_true(all(result$audit$User == "other-editor"))
  expect_identical(
    vpro_plot_other_list(context, plot_number)$DataItem,
    c("After", "Unchanged")
  )
  visible <- DBI::dbGetQuery(
    context$con,
    'SELECT "DataItem" FROM USysOther WHERE "ID" = 9101'
  )
  expect_identical(visible$DataItem, "After")
})

test_that("Other update validates identity, keys, fields, and values", {
  path <- local_other_sample_copy()
  context <- local_other_context(path)
  plots <- other_plot_numbers(context)
  seed_other_rows(
    path,
    data.frame(
      PlotNumber = plots[[1]],
      DataName = "Stable",
      DataItem = "Before",
      ID = 9201L,
      stringsAsFactors = FALSE
    )
  )

  expect_snapshot(
    error = TRUE,
    vpro_plot_other_update(context, plots[[2]], 9201L, list(DataItem = "Wrong plot"), user = "tester")
  )
  expect_snapshot(
    error = TRUE,
    vpro_plot_other_update(context, plots[[1]], 9999L, list(DataItem = "Missing"), user = "tester")
  )
  expect_snapshot(
    error = TRUE,
    vpro_plot_other_update(context, plots[[1]], 2147483648, list(DataItem = "Invalid ID"), user = "tester")
  )
  expect_snapshot(
    error = TRUE,
    vpro_plot_other_update(context, plots[[1]], 9201L, list(ID = 9202L), user = "tester")
  )
  expect_snapshot(
    error = TRUE,
    vpro_plot_other_update(context, plots[[1]], 9201L, list(NotAField = "invalid"), user = "tester")
  )
  expect_snapshot(
    error = TRUE,
    vpro_plot_other_update(context, plots[[1]], 9201L, list(UserFlag1 = "yes"), user = "tester")
  )
  expect_identical(vpro_plot_other_list(context, plots[[1]])$DataItem, "Before")
})

test_that("Other creation generates an ID and audits populated defaults", {
  path <- local_other_sample_copy()
  context <- local_other_context(path)
  plot_number <- other_plot_numbers(context)[[1L]]

  result <- vpro_plot_other_create(
    context,
    plot_number,
    list(DataName = "Created", DataItem = "Value"),
    user = "creator",
    audit_strength = 2
  )

  expect_identical(result$other$PlotNumber, plot_number)
  expect_gte(result$other$ID, -2147483648)
  expect_lte(result$other$ID, 2147483647)
  expect_identical(result$other$UserFlag1, 0L)
  expect_setequal(
    result$audit$EditField,
    c("DataName", "DataItem", "UserFlag1", "UserFlag2", "UserFlag3")
  )
  expect_true(all(result$audit$ID == result$other$ID))
})

test_that("Other deletion removes one row without adding audit records", {
  path <- local_other_sample_copy()
  context <- local_other_context(path)
  plot_number <- other_plot_numbers(context)[[1L]]
  created <- vpro_plot_other_create(
    context,
    plot_number,
    list(DataName = "Delete me"),
    user = "creator",
    audit_strength = 0
  )
  before_audit <- nrow(vpro_plot_audit_list(context, plot_number))

  deleted <- vpro_plot_other_delete(context, plot_number, created$other$ID)

  expect_identical(deleted$DataName, "Delete me")
  expect_identical(nrow(vpro_plot_other_list(context, plot_number)), 0L)
  expect_identical(nrow(vpro_plot_audit_list(context, plot_number)), before_audit)
})

test_that("Other audit strength follows field-change semantics", {
  path <- local_other_sample_copy()
  context <- local_other_context(path)
  plot_number <- other_plot_numbers(context)[[1]]
  seed_other_rows(
    path,
    data.frame(
      PlotNumber = plot_number,
      DataName = "Audit strength",
      DataItem = NA_character_,
      ID = 9301L,
      stringsAsFactors = FALSE
    )
  )

  strength_one <- vpro_plot_other_update(
    context,
    plot_number,
    9301L,
    list(DataItem = "Added"),
    user = "tester",
    audit_strength = 1
  )
  expect_identical(nrow(strength_one$audit), 0L)

  strength_three <- vpro_plot_other_update(
    context,
    plot_number,
    9301L,
    list(DataItem = NA_character_),
    user = "tester",
    audit_strength = 3
  )
  expect_identical(strength_three$audit$EditField, "DataItem")
  expect_identical(strength_three$audit$BeforeEdit, "Added")
  expect_true(is.na(strength_three$audit$AfterEdit))
  expect_identical(strength_three$audit$ID, 9301L)
})
