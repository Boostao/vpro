# Synthetic unit tests for developer-only parity parsers.
library(testthat)
root <- if (dir.exists(file.path("data-raw", "parity"))) {
  file.path("data-raw", "parity")
} else {
  file.path("..", "..", "data-raw", "parity")
}
skip_if_not(dir.exists(root), "developer-only parity tooling is not shipped")
root <- normalizePath(root, mustWork = TRUE)
source(file.path(root, "R", "io.R"))
source(file.path(root, "R", "access_parser.R"))
source(file.path(root, "R", "target_parser.R"))
source(file.path(root, "R", "inventory.R"))

test_that("VBA declarations include ranges, visibility and simple flags", {
  x <- c("Private Sub LoadData()", " On Error Resume Next", " Set o = CreateObject(\"X\")", "End Sub", "Public Function EmptyThing()", "End Function")
  got <- parity_vba_procedures(x, "frmX", "Forms", "Forms/frmX.txt")
  expect_equal(nrow(got), 2L)
  expect_equal(got$visibility[1], "private")
  expect_equal(got$line_start[1], 1L)
  expect_equal(got$line_end[1], 4L)
  expect_equal(got$error_suppression[1], 1L)
  expect_equal(got$com_or_shell[1], 1L)
  expect_true(got$empty[2])
})

test_that("Access SQL fragments and octal newlines are decoded", {
  x <- c('dbMemo "SQL" ="SELECT *\\015\\012FROM [T]"', '    " WHERE A=1;\\015\\012"', 'dbBoolean "ReturnsRecords" ="-1"')
  expect_equal(parity_query_sql(x), "SELECT *\r\nFROM [T] WHERE A=1;\r\n")
})

test_that("event procedures and macros yield stable expected handlers", {
  ev <- parity_events(c("Begin Form", ' Name ="SaveButton"', ' OnClick ="[Event Procedure]"'), "frmX", "Forms", "Forms/frmX.txt")
  expect_equal(ev$control, "SaveButton")
  expect_equal(ev$expected_handler, "SaveButton_Click")
  mac <- parity_macro_actions(c(' Action ="RunCode"', ' Argument ="=DoThing()"'), "AutoExec", "Macros/AutoExec.txt")
  expect_equal(mac$run_code, "DoThing")
})

test_that("top-level R function assignments are inventoried", {
  path <- tempfile(fileext = ".R")
  writeLines(c("one <- function(x) x", "two <-", "  function(y) {", "    y", "  }"), path)

  got <- parity_r_functions(path, dirname(path))
  expect_equal(got$name, c("one", "two"))
  expect_equal(got$line_start, c(1L, 2L))
  expect_equal(got$line_end, c(1L, 5L))
})

test_that("reviewed overrides replace matching parity rows", {
  parity <- data.frame(
    id = "source::one",
    status = "unmapped",
    target_id = "",
    notes = "initial",
    stringsAsFactors = FALSE
  )
  target <- data.frame(id = "target::one", stringsAsFactors = FALSE)
  overrides <- tempfile(fileext = ".csv")
  write.csv(
    data.frame(
      source_id = "source::one",
      target_id = "target::one",
      status = "reviewed_equivalence",
      notes = "reviewed",
      stringsAsFactors = FALSE
    ),
    overrides,
    row.names = FALSE
  )

  got <- parity_apply_overrides(parity, target, overrides)
  expect_equal(got$status, "reviewed_equivalence")
  expect_equal(got$target_id, "target::one")
})
