test_that("presence classes preserve Access threshold boundaries", {
  boundaries <- c(0, 0.2, 0.4, 0.6, 0.8, 1)
  expect_identical(
    vpro_presence_class(boundaries),
    c("I", "I", "II", "III", "IV", "V")
  )
  expect_identical(
    vpro_presence_class(boundaries + c(0, rep(1e-10, 5))),
    c("I", "II", "III", "IV", "V", NA_character_)
  )
  expect_identical(
    vpro_presence_class(c(-0.1, NA_real_, 1.1)),
    rep(NA_character_, 3)
  )
})

test_that("numeric-label presence classes retain an unbounded fifth class", {
  expect_identical(
    vpro_presence_class_numeric(c(-0.1, 0, 0.2, 0.4, 0.6, 0.8, 2, NA)),
    c(NA, "1", "1", "2", "3", "4", "5", NA)
  )
})

test_that("prominence classes use the unrounded Access score", {
  scores <- c(0, 15, 50, 100, 200, 201)
  expect_identical(
    vpro_prominence_class(scores / 10, 1),
    c(1L, 1L, 2L, 3L, 4L, 5L)
  )
  expect_equal(
    vpro_prominence_class(c(2, 8), 0.25, return_score = TRUE),
    c(10, 40)
  )
  expect_identical(
    vpro_prominence_class(c(-1, 1, NA), c(1, -1, 1)),
    rep(NA_integer_, 3)
  )
  expect_equal(vpro_prominence_class(-1, 1, return_score = TRUE), -10)
})

test_that("Goldstream classes use the unrounded Access score", {
  scores <- c(0, 5, 25, 75, 150, 300, 500, 501)
  expect_identical(
    vpro_goldstream_class(1, scores / 100),
    c(0L, 0:6)
  )
  expect_equal(
    vpro_goldstream_class(c(1, 4), 0.5, return_score = TRUE),
    c(50, 100)
  )
  expect_identical(
    vpro_goldstream_class(c(-1, 1, NA), c(1, -1, 1)),
    rep(NA_integer_, 3)
  )
  expect_equal(vpro_goldstream_class(1, -1, return_score = TRUE), -100)
})

test_that("significance classes preserve mixed Access labels as text", {
  boundaries <- c(-1, -0.5, 0.3, 1, 2.2, 5, 10, 20, 33, 50, 75, 76, NA)
  expect_identical(
    vpro_significance_class(boundaries),
    c(NA, "+", "+", "1", "2", "3", "4", "5", "6", "7", "8", "9", NA)
  )
})

test_that("rounding and capping return stable numeric values", {
  expect_equal(
    vpro_round_minimum(c(-1, 0, 0.004, 0.006, 1.234, NA)),
    c(0.01, 0.01, 0.01, 0.01, 1.23, NA)
  )
  expect_equal(vpro_round_minimum(c(0.14, 0.15), digits = 1, minimum = 0.1), c(0.1, 0.1))
  expect_equal(vpro_cap_percent(c(-1, 50, 100, 101, NA)), c(-1, 50, 100, 100, NA))
})

test_that("value conversion APIs validate inputs", {
  expect_snapshot(error = TRUE, vpro_presence_class("0.5"))
  expect_snapshot(error = TRUE, vpro_prominence_class(1:2, 1:3))
  expect_snapshot(error = TRUE, vpro_prominence_class(1, 1, return_score = NA))
  expect_snapshot(error = TRUE, vpro_significance_class(Inf))
  expect_snapshot(error = TRUE, vpro_round_minimum(1, digits = 1.5))
  expect_snapshot(error = TRUE, vpro_round_minimum(1, minimum = Inf))
})
