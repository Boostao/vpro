# Tests for diagnostic helpers

source(here::here("R", "logic_diagnostic.R"))

test_that("parse_presence_significance parses codes", {
  parsed <- parse_presence_significance("53")
  expect_equal(parsed$presence, 5)
  expect_equal(parsed$significance, 3)

  parsed_single <- parse_presence_significance("5")
  expect_equal(parsed_single$presence, 5)
  expect_equal(parsed_single$significance, 5)
})

test_that("compute_diagnostic_flags finds differential and constant", {
  codes <- c(UnitA = "53", UnitB = "12")
  result <- compute_diagnostic_flags(codes)
  expect_equal(result$unit, "UnitA")
  expect_true(grepl("d", result$diagnosis))
  expect_true(grepl("c", result$diagnosis))
})

test_that("compute_diagnostic_row returns dd", {
  row <- data.frame(
    Species = "SP1",
    UnitA = "45",
    UnitB = "32",
    stringsAsFactors = FALSE
  )

  result <- compute_diagnostic_row(row)
  expect_equal(result$species, "SP1")
  expect_equal(result$unit, "UnitA")
  expect_equal(result$diagnosis, "dd")
})

test_that("diagnostic_from_matrix returns table", {
  df <- data.frame(
    Species = c("SP1", "SP2"),
    UnitA = c("45", "12"),
    UnitB = c("32", "53"),
    stringsAsFactors = FALSE
  )

  result <- diagnostic_from_matrix(df)
  expect_equal(nrow(result), 2)
  expect_equal(result$Species, c("SP1", "SP2"))
  expect_true(all(nzchar(result$Diagnosis)))
})
