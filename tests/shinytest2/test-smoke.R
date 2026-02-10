library(shinytest2)

test_that("app loads and context inputs exist", {
  app <- AppDriver$new("../..", name = "smoke", height = 900, width = 1400)
  app$wait_for_idle()

  app$get_value(input = "sel_project")
  app$get_value(input = "sel_su")

  app$stop()
})
