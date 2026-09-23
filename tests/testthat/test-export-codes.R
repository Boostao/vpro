test_that("missing export codes become periods without changing other text", {
  expect_identical(vpro_export_code(c(NA, "", " ", ".", "BW", " BW ", "a b")), c(".", "", " ", ".", "BW", " BW ", "a b"))
})

test_that("export codes do not silently coerce unknown input types", {
  expect_snapshot(error = TRUE, vpro_export_code(numeric()))
  expect_snapshot(error = TRUE, vpro_export_code(NA))
  expect_snapshot(error = TRUE, vpro_export_code(1))
  expect_snapshot(error = TRUE, vpro_export_code(list("BW", NA)))
})
