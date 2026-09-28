test_that("bundled bcgov theme compiles without modifying bslib", {
  theme <- vpro_bcgov_theme()
  expect_true(bslib::is_bs_theme(theme))
  expect_invisible(vpro:::vpro_validate_bcgov_theme())

  css <- sass::sass(theme)
  expect_match(css, "BCSans", fixed = TRUE)
  attachments <- theme$layers[[length(theme$layers)]]$file_attachments
  expect_true(all(c("font.css", "fonts") %in% names(attachments)))
  expect_true(file.exists(file.path(attachments[["fonts"]], "BCSans-Regular.woff2")))
  expect_match(css, "#036", fixed = TRUE)
})
