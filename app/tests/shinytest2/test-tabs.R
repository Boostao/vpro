library(shinytest2)

test_that("secondary tabs load without errors", {
  app <- AppDriver$new("../..", name = "tabs", height = 900, width = 1400)
  on.exit(app$stop(), add = TRUE)
  app$wait_for_idle()

  app$set_inputs(main_tabs = "Reports")
  app$wait_for_idle()
  app$get_value(input = "report-report_template")

  app$set_inputs(main_tabs = "Upload")
  app$wait_for_idle()
  app$get_value(input = "upload-upload_file")

  app$set_inputs(main_tabs = "Merge")
  app$wait_for_idle()
  app$get_value(input = "merge-merge_request")

  app$set_inputs(main_tabs = "Administration")
  app$wait_for_idle()
  app$get_value(input = "admin-sync_project")
})
