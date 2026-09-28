test_that("app modules use the app configuration adapter and valid schema keys", {
  module_files <- list.files(
    test_path("..", "..", "inst", "app", "modules"),
    pattern = "\\.R$",
    full.names = TRUE
  )
  module_text <- unlist(lapply(module_files, readLines, warn = FALSE), use.names = FALSE)

  expect_false(any(grepl("\\bconfig\\s*\\(", module_text)))
  expect_false(any(grepl("\\b(ProjectIDSource|CurrPlotList|FS1333ProjectIdSource)\\b", module_text)))
  expect_false(any(grepl('"System"\\s*,\\s*"AuditStrength"', module_text)))
})

test_that("app configuration reads fresh file-backed values and builds the UI", {
  root <- withr::local_tempdir()
  withr::local_options(vpro.config_dir = file.path(root, "config"))

  app_dir <- test_path("..", "..", "inst", "app")
  app_env <- new.env(parent = globalenv())
  withr::with_dir(app_dir, {
    sys.source("global.R", envir = app_env)
    sys.source("ui.R", envir = app_env)
  })

  expect_identical(app_env$app_config_get("Current", "CurrProject"), "Sample")
  cfg_path <- file.path(vpro::vpro_config_dir(), "config.yml")
  cfg <- yaml::read_yaml(cfg_path)
  cfg$Current$CurrProject <- "FreshProject"
  yaml::write_yaml(cfg, cfg_path)
  expect_identical(app_env$app_config_get("Current", "CurrProject"), "FreshProject")
  expect_s3_class(app_env$ui, "shiny.tag.list")
})
