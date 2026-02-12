#!/usr/bin/env Rscript
# Quick smoke test for report parity
# Runs only the template existence and basic render tests (fast)

library(testthat)
library(here)

cat("=== VPRO Report Parity Smoke Tests ===\n\n")

cat("Testing template files exist...\n")
test_res <- test_file(
  here("tests", "testthat", "test-reports-parity.R"),
  filter = "all report templates exist",
  reporter = "summary"
)

cat("\nTesting one report renders...\n")
test_res <- test_file(
  here("tests", "testthat", "test-reports-parity.R"),
  filter = "short_veg.qmd renders without errors",
  reporter = "summary"
)

cat("\n=== Smoke tests complete ===\n")
cat("For full test suite: Rscript -e \"testthat::test_file('tests/testthat/test-reports-parity.R')\"\n")
