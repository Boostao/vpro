test_that("decimal coordinates follow Access component composition", {
  expect_equal(vpro_coordinate_decimal(49, 30, 30), 49.5083333333333)
  expect_equal(
    vpro_coordinate_decimal(c(49, 50), NA_real_, c(30, NA_real_)),
    c(49.0083333333333, 50)
  )
  expect_equal(vpro_coordinate_decimal(-123, 30), -122.5)
  expect_identical(vpro_coordinate_decimal(NA_real_, 30, 30), NA_real_)
})

test_that("DMS decomposition removes signs and preserves missing values", {
  result <- vpro_coordinate_dms(c(-123.5083333333333, 49.5, NA_real_))

  expect_equal(result$degrees, c(123, 49, NA_real_))
  expect_equal(result$minutes, c(30, 30, NA_real_))
  expect_equal(result$seconds, c(30, 0, NA_real_), tolerance = 1e-9)
})

test_that("decimal-minute decomposition removes signs", {
  result <- vpro_coordinate_dm(c(-123.5083333333333, 49, NA_real_))

  expect_equal(result$degrees, c(123, 49, NA_real_))
  expect_equal(result$minutes, c(30.5, 0, NA_real_), tolerance = 1e-9)
})

test_that("coordinate APIs reject invalid numeric inputs", {
  expect_snapshot(error = TRUE, vpro_coordinate_decimal(character()))
  expect_snapshot(error = TRUE, vpro_coordinate_decimal(1:2, 1:3))
  expect_snapshot(error = TRUE, vpro_coordinate_dms(Inf))
  expect_snapshot(error = TRUE, vpro_coordinate_dm("49.5"))
})
