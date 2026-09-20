library(shinytest2)

test_that("import tab loads", {
  withr::local_envvar(NOT_CRAN = "true")
  app <- AppDriver$new("../..", name = "import-tab", height = 900, width = 1400)
  on.exit(app$stop(), add = TRUE)
  app$wait_for_idle()

  app$set_inputs(main_tabs = "Import")
  app$wait_for_idle()

  app$get_value(input = "import-import_file")
  app$get_value(input = "import-target_table")
  app$get_value(input = "import-import_analyze")
  app$get_value(input = "import-import_apply")
  app$get_value(input = "import-import_allow_replace")
  app$get_value(input = "import-import_confirm_replace")

  expect_true(TRUE)
})
