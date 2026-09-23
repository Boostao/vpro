local_soil_context <- function(path) {
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

local_soil_sample_copy <- function() {
  path <- tempfile(fileext = ".db")
  file.copy(system.file("extdata", "projects", "Sample.db", package = "vpro"), path)
  path
}

soil_plot_numbers <- function(context) {
  DBI::dbGetQuery(
    context$con,
    'SELECT "PlotNumber" FROM USysEnv ORDER BY "PlotNumber" LIMIT 2'
  )$PlotNumber
}

seed_soil_rows <- function(path, table, rows) {
  con <- DBI::dbConnect(RSQLite::SQLite(), path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  DBI::dbAppendTable(con, table, rows)
}

test_that("soil reads require an active project and existing plot", {
  path <- local_soil_sample_copy()
  con <- tryCatch(vpro_db_connect(), error = identity)
  if (inherits(con, "error")) {
    skip(conditionMessage(con))
  }
  context <- vpro_project_context(con = con)
  withr::defer(vpro_db_disconnect(context$con))

  expect_snapshot(error = TRUE, vpro_plot_humus_list(context, "1976071"))
  vpro_project_attach(context, path, "Sample")
  vpro_project_activate(context, "Sample")
  plot_number <- soil_plot_numbers(context)[[1L]]
  expect_s3_class(vpro_plot_humus_list(context, plot_number), "data.frame")
  expect_s3_class(vpro_plot_mineral_list(context, plot_number), "data.frame")
  expect_snapshot(error = TRUE, vpro_plot_mineral_list(context, "Missing"))
})

test_that("Humus and Mineral rows preserve their Access order", {
  path <- local_soil_sample_copy()
  context <- local_soil_context(path)
  plots <- soil_plot_numbers(context)
  seed_soil_rows(
    path,
    "Sample_Humus",
    data.frame(
      PlotNumber = c(plots[[1L]], plots[[1L]], plots[[1L]], plots[[2L]]),
      Horizon = c("A", "B", "A", "Z"),
      UpperDepth = c(5, 10, 10, 20),
      ID = c(9003L, 9002L, 9001L, 9004L),
      stringsAsFactors = FALSE
    )
  )
  seed_soil_rows(
    path,
    "Sample_Mineral",
    data.frame(
      PlotNumber = c(plots[[1L]], plots[[1L]], plots[[1L]], plots[[2L]]),
      Horizon = c("B", "A", "A", "Z"),
      UpperDepth = c(10, 5, 5, 1),
      ID = c(9103L, 9102L, 9101L, 9104L),
      stringsAsFactors = FALSE
    )
  )

  humus <- vpro_plot_humus_list(context, plots[[1L]])
  mineral <- vpro_plot_mineral_list(context, plots[[1L]])

  expect_identical(humus$ID, c(9002L, 9001L, 9003L))
  expect_identical(mineral$ID, c(9101L, 9102L, 9103L))
  expect_true(all(humus$PlotNumber == plots[[1L]]))
  expect_true(all(mineral$PlotNumber == plots[[1L]]))
})

test_that("soil get uses compound plot and child identity", {
  path <- local_soil_sample_copy()
  context <- local_soil_context(path)
  plots <- soil_plot_numbers(context)
  seed_soil_rows(
    path,
    "Sample_Humus",
    data.frame(
      PlotNumber = plots[[1L]],
      Horizon = "H",
      ID = -9201L,
      stringsAsFactors = FALSE
    )
  )

  result <- vpro_plot_humus_get(context, plots[[1L]], -9201L)

  expect_identical(result$Horizon, "H")
  expect_identical(result$ID, -9201L)
  expect_snapshot(
    error = TRUE,
    vpro_plot_humus_get(context, plots[[2L]], -9201L)
  )
  expect_snapshot(
    error = TRUE,
    vpro_plot_humus_get(context, plots[[1L]], 2147483648)
  )
})

test_that("soil creation and deletion follow Access child contracts", {
  path <- local_soil_sample_copy()
  context <- local_soil_context(path)
  plot_number <- soil_plot_numbers(context)[[1L]]

  humus <- vpro_plot_humus_create(
    context,
    plot_number,
    list(Horizon = "H", Comment = "created"),
    user = "creator",
    audit_strength = 2
  )
  mineral <- vpro_plot_mineral_create(
    context,
    plot_number,
    list(Horizon = "A", Comments = "created"),
    user = "creator",
    audit_strength = 2
  )

  expect_setequal(humus$audit$EditField, c("Horizon", "Comment"))
  expect_setequal(mineral$audit$EditField, c("Horizon", "Comments"))
  expect_true(all(humus$audit$ID == humus$humus$ID))
  expect_true(all(mineral$audit$ID == mineral$mineral$ID))
  before_audit <- nrow(vpro_plot_audit_list(context, plot_number))
  vpro_plot_humus_delete(context, plot_number, humus$humus$ID)
  vpro_plot_mineral_delete(context, plot_number, mineral$mineral$ID)
  expect_identical(nrow(vpro_plot_humus_list(context, plot_number)), 0L)
  expect_identical(nrow(vpro_plot_mineral_list(context, plot_number)), 0L)
  expect_identical(nrow(vpro_plot_audit_list(context, plot_number)), before_audit)
})

test_that("soil updates identified rows and writes child audit records", {
  path <- local_soil_sample_copy()
  context <- local_soil_context(path)
  plot_number <- soil_plot_numbers(context)[[1L]]
  seed_soil_rows(
    path,
    "Sample_Humus",
    data.frame(
      PlotNumber = c(plot_number, plot_number),
      Horizon = c("H", "Sibling"),
      Comment = c("Before", "Unchanged"),
      ID = c(9301L, 9302L),
      stringsAsFactors = FALSE
    )
  )
  seed_soil_rows(
    path,
    "Sample_Mineral",
    data.frame(
      PlotNumber = plot_number,
      Horizon = "A",
      Comments = "Before",
      ID = 9401L,
      stringsAsFactors = FALSE
    )
  )

  humus <- vpro_plot_humus_update(
    context,
    plot_number,
    9301L,
    list(Comment = "After", Flag = TRUE),
    user = "soil-editor",
    audit_strength = 2
  )
  mineral <- vpro_plot_mineral_update(
    context,
    plot_number,
    9401L,
    list(Comments = "After", UpperDepth = 2.5),
    user = "soil-editor",
    audit_strength = 2
  )

  expect_identical(humus$humus$Comment, "After")
  expect_identical(humus$humus$Flag, 1L)
  expect_setequal(humus$audit$EditField, c("Comment", "Flag"))
  expect_true(all(humus$audit$Table == "_Humus"))
  expect_true(all(humus$audit$ID == 9301L))
  expect_identical(mineral$mineral$Comments, "After")
  expect_identical(mineral$mineral$UpperDepth, 2.5)
  expect_true(all(mineral$audit$Table == "_Mineral"))
  expect_true(all(mineral$audit$ID == 9401L))
  expect_identical(
    vpro_plot_humus_get(context, plot_number, 9302L)$Comment,
    "Unchanged"
  )
  visible <- DBI::dbGetQuery(
    context$con,
    'SELECT "Comments" FROM USysMineral WHERE "ID" = 9401'
  )
  expect_identical(visible$Comments, "After")
})

test_that("soil updates validate keys, fields, values, and audit strength", {
  path <- local_soil_sample_copy()
  context <- local_soil_context(path)
  plots <- soil_plot_numbers(context)
  seed_soil_rows(
    path,
    "Sample_Mineral",
    data.frame(
      PlotNumber = plots[[1L]],
      Horizon = "A",
      Comments = NA_character_,
      ID = 9501L,
      stringsAsFactors = FALSE
    )
  )

  expect_snapshot(
    error = TRUE,
    vpro_plot_mineral_update(
      context,
      plots[[1L]],
      9501L,
      list(ID = 9502L),
      user = "tester"
    )
  )
  expect_snapshot(
    error = TRUE,
    vpro_plot_mineral_update(
      context,
      plots[[1L]],
      9501L,
      list(NotAField = "invalid"),
      user = "tester"
    )
  )
  expect_snapshot(
    error = TRUE,
    vpro_plot_mineral_update(
      context,
      plots[[1L]],
      9501L,
      list(UpperDepth = "deep"),
      user = "tester"
    )
  )
  expect_snapshot(
    error = TRUE,
    vpro_plot_mineral_update(
      context,
      plots[[2L]],
      9501L,
      list(Comments = "wrong plot"),
      user = "tester"
    )
  )

  strength_one <- vpro_plot_mineral_update(
    context,
    plots[[1L]],
    9501L,
    list(Comments = "Added"),
    user = "tester",
    audit_strength = 1
  )
  expect_identical(nrow(strength_one$audit), 0L)
  strength_three <- vpro_plot_mineral_update(
    context,
    plots[[1L]],
    9501L,
    list(Comments = NA_character_),
    user = "tester",
    audit_strength = 3
  )
  expect_identical(strength_three$audit$BeforeEdit, "Added")
  expect_true(is.na(strength_three$audit$AfterEdit))
  expect_identical(strength_three$audit$ID, 9501L)
})

test_that("soil row and audit writes roll back together", {
  path <- local_soil_sample_copy()
  context <- local_soil_context(path)
  plot_number <- soil_plot_numbers(context)[[1L]]
  seed_soil_rows(
    path,
    "Sample_Humus",
    data.frame(
      PlotNumber = plot_number,
      Comment = "Before",
      ID = 9601L,
      stringsAsFactors = FALSE
    )
  )
  con <- DBI::dbConnect(RSQLite::SQLite(), path)
  DBI::dbExecute(con, "DROP TABLE Sample_Audit")
  DBI::dbDisconnect(con)

  expect_snapshot(
    error = TRUE,
    vpro_plot_humus_update(
      context,
      plot_number,
      9601L,
      list(Comment = "After"),
      user = "tester",
      audit_strength = 1
    )
  )
  expect_identical(
    vpro_plot_humus_get(context, plot_number, 9601L)$Comment,
    "Before"
  )
})
