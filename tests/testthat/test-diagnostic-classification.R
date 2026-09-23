test_that("diagnostic categories follow Access order and overlap", {
  expect_identical(
    vpro_diagnostic_classify(c(A = "5 - 5", B = "1 - 1")),
    list(unit = "A", diagnosis = "d, cd")
  )
  expect_identical(
    vpro_diagnostic_classify(c(A = "5 - 4", B = "4 - 4")),
    list(unit = "A", diagnosis = "c")
  )
  expect_identical(
    vpro_diagnostic_classify(c(A = "2 - 7", B = "2 - 1")),
    list(unit = "A", diagnosis = "dd")
  )
  expect_identical(
    vpro_diagnostic_classify(c(A = "2 - +", B = "1 - +", C = "1 - +")),
    list(unit = NA_character_, diagnosis = NA_character_)
  )
  expect_identical(
    vpro_diagnostic_classify(c(A = "3 - 4", B = "1 - 1")),
    list(unit = "A", diagnosis = "d")
  )
  expect_identical(
    vpro_diagnostic_classify(c(A = "1 - 9")),
    list(unit = "A", diagnosis = "dd")
  )
  expect_identical(
    vpro_diagnostic_classify(c(A = "5 - 9", B = "3 - 8")),
    list(unit = "A", diagnosis = "d, cd")
  )
})

test_that("diagnostic calculation uses first maximum field and skips null cells", {
  expect_identical(
    vpro_diagnostic_classify(c(Z = NA_character_, B = "5 - 8", A = "5 - 1")),
    list(unit = "B", diagnosis = "dd")
  )
  expect_identical(
    vpro_diagnostic_classify(c(A = "5 - 1", B = "5 - 8")),
    list(unit = NA_character_, diagnosis = NA_character_)
  )
  expect_identical(
    vpro_diagnostic_classify(c(A = NA_character_, B = NA_character_)),
    list(unit = NA_character_, diagnosis = NA_character_)
  )
  expect_identical(
    vpro_diagnostic_classify(c(A = "1 - +", B = "1 - 1")),
    list(unit = NA_character_, diagnosis = NA_character_)
  )
  expect_identical(
    vpro_diagnostic_classify(c(A = "5 - +", B = "1 - +")),
    list(unit = "A", diagnosis = "d, c")
  )
})

test_that("classification matches the disposable Access Diagnostic oracle", {
  # See data-raw/oracle/diagnostic-classification-oracle.tsv for input field order.
  cases <- list(
    D_CD = c(UnitB = "5 - 5", UnitA = "1 - 1", UnitC = NA_character_),
    D_C = c(UnitB = "5 - +", UnitA = "1 - +", UnitC = NA_character_),
    DD_TIE = c(UnitB = "5 - 8", UnitA = "5 - 1", UnitC = NA_character_),
    CONSTANT = c(UnitB = "5 - 4", UnitA = "4 - 4", UnitC = NA_character_),
    DD = c(UnitB = "2 - 7", UnitA = "2 - 1", UnitC = NA_character_),
    D = c(UnitB = "3 - 4", UnitA = "1 - 1", UnitC = NA_character_),
    NONE = c(UnitB = "1 - +", UnitA = "1 - 1", UnitC = NA_character_),
    ALL_NULL = c(UnitB = NA_character_, UnitA = NA_character_, UnitC = NA_character_),
    NULL_FIRST = c(UnitB = NA_character_, UnitA = "5 - 9", UnitC = "3 - 8"),
    IC_CHECK = c(UnitB = "2 - +", UnitA = "1 - +", UnitC = "1 - +")
  )
  expected_unit <- c("UnitB", "UnitB", "UnitB", "UnitB", "UnitB", "UnitB", NA, NA, "UnitA", NA)
  expected_diagnosis <- c("d, cd", "d, c", "dd", "c", "dd", "d", NA, NA, "d, cd", NA)
  actual <- lapply(cases, vpro_diagnostic_classify)
  expect_identical(unname(vapply(actual, `[[`, character(1), "unit")), expected_unit)
  expect_identical(unname(vapply(actual, `[[`, character(1), "diagnosis")), expected_diagnosis)
})

test_that("diagnostic input must contain ordered named crosstab codes", {
  expect_snapshot(error = TRUE, vpro_diagnostic_classify(character()))
  expect_snapshot(error = TRUE, vpro_diagnostic_classify("3 - 5"))
  expect_snapshot(error = TRUE, vpro_diagnostic_classify(c(A = "3 - 5", A = "2 - 3")))
  expect_snapshot(error = TRUE, vpro_diagnostic_classify(c(A = "3 - 5", "2 - 3")))
  expect_snapshot(error = TRUE, vpro_diagnostic_classify(c(A = "3-5")))
  expect_snapshot(error = TRUE, vpro_diagnostic_classify(c(A = "0 - 5")))
  expect_snapshot(error = TRUE, vpro_diagnostic_classify(c(A = "3 - 0")))
  expect_snapshot(error = TRUE, vpro_diagnostic_classify(c(A = "3 - X")))
  expect_snapshot(error = TRUE, vpro_diagnostic_classify(c(A = 3)))
})
