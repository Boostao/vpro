test_that("FS882 plot-wide field mapping and changes fail closed", {
  env <- new.env(parent = baseenv())
  sys.source(test_path("..", "..", "inst", "app", "modules", "mod_fs882_6x4.R"), envir = env)
  plot <- list(env = data.frame(Date = "2024-01-01", Latitude = 49, UpdatedFromCards = 0L,
                                UserSiteUnit = "old"), admin = data.frame(BECSiteUnit = "A"))
  map <- env$fs882_field_map(plot)
  types <- list(env = c(Date = "DATE", Latitude = "REAL", UpdatedFromCards = "INTEGER", UserSiteUnit = "TEXT"),
                admin = c(BECSiteUnit = "TEXT"))
  expect_identical(map$UserSiteUnit$table, "env")
  expect_null(map$FieldNumber)
  expect_error(env$fs882_field_changes(list(FieldNumber = "test"), plot, map, types), "mapping")
  expect_error(env$fs882_field_changes(list(Latitude = "not a number", UserSiteUnit = "new"), plot, map, types), "Invalid numeric")
  expect_identical(env$fs882_field_changes(list(UpdatedFromCards = TRUE), plot, map, types)$env$UpdatedFromCards, TRUE)
  expect_length(env$fs882_field_changes(list(UpdatedFromCards = FALSE), plot, map, types)$env, 0)
  expect_identical(env$fs882_field_changes(list(UserSiteUnit = "new"), plot, map, types)$env$UserSiteUnit, "new")
  draft <- list(UserSiteUnit = "new", UpdatedFromCards = TRUE, FieldNumber = "unmapped")
  latest <- plot
  latest$env$UserSiteUnit <- "new"
  expect_identical(env$fs882_saved_fields(names(draft), draft, latest, map, types), "UserSiteUnit")
  expect_length(env$fs882_field_changes(list(Date = as.Date("2024-01-01")), plot, map, types)$env, 0)
  expect_error(env$fs882_field_value("2024-02-31", "DATE", "Date"), "Invalid date")
})

test_that("FS882 coordinates retain errors rather than converting bad components to NA", {
  env <- new.env(parent = baseenv())
  sys.source(test_path("..", "..", "inst", "app", "modules", "mod_fs882_6x4.R"), envir = env)
  bad <- env$fs882_coord_result(list("49", "70"))
  expect_null(bad$value)
  expect_match(bad$error, "Invalid coordinate")
  expect_match(env$fs882_coord_result(list("49", "oops"))$error, "Invalid coordinate")
  expect_equal(env$fs882_coord_result(list("-0", "30"))$value, -0.5)
  expect_true(is.na(env$fs882_coord_result(list("", ""))$value))
})

test_that("FS882 draft identity rejects stale project and path", {
  env <- new.env(parent = baseenv())
  sys.source(test_path("..", "..", "inst", "app", "modules", "mod_fs882_6x4.R"), envir = env)
  context <- list(active = list(project = "A", path = "/a"))
  expect_true(env$fs882_project_matches(context, "A", "/a", "A"))
  expect_false(env$fs882_project_matches(context, "A", "/a", "B"))
  context$active <- list(project = "B", path = "/b")
  expect_false(env$fs882_project_matches(context, "A", "/a", "B"))
  expect_false(env$fs882_project_matches(context, "B", "/a", "B"))
})
