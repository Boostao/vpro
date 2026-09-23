test_that("profile maximum retains the zero baseline and ten-cover ordering", {
  expect_equal(vpro_profile_max_cover(1, 3, 4, 5, 9, 10, 11, NA, 7, 2), 11)
  expect_equal(vpro_profile_max_cover(-1, -2, -3, -4, -5, -6, -7, -8, -9, -10), 0)
  expect_equal(vpro_profile_max_cover(0, 0, 0, 0, 0, 0, 0, 0, 0, 0), 0)
  expect_equal(vpro_profile_max_cover(NA, NA, NA, NA, NA, NA, NA, NA, NA, NA), 0)
  expect_equal(
    vpro_profile_max_cover(c(1, NA, -1), 0, 0, 0, 0, 0, 0, 0, 0, c(2, 3, NA)),
    c(2, 3, 0)
  )
})

test_that("profile maximum rejects ambiguous or invalid cover inputs", {
  expect_snapshot(error = TRUE, vpro_profile_max_cover("1", 0, 0, 0, 0, 0, 0, 0, 0, 0))
  expect_snapshot(error = TRUE, vpro_profile_max_cover(numeric(), 0, 0, 0, 0, 0, 0, 0, 0, 0))
  expect_snapshot(error = TRUE, vpro_profile_max_cover(Inf, 0, 0, 0, 0, 0, 0, 0, 0, 0))
  expect_snapshot(error = TRUE, vpro_profile_max_cover(1:2, 1:3, 0, 0, 0, 0, 0, 0, 0, 0))
})
