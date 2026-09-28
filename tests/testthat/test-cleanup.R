test_that("cleanup deletes only approved files and keeps skipped files", {
  root <- withr::local_tempdir()
  path <- file.path(root, "data")
  dir.create(file.path(path, "projects"), recursive = TRUE)
  remove <- file.path(path, "projects", "remove.db")
  keep <- file.path(path, "projects", "keep.db")
  writeLines("delete", remove)
  writeLines("keep", keep)
  prompts <- character()
  answer <- function(text) {
    prompts <<- c(prompts, text)
    if (grepl("remove.db", text, fixed = TRUE)) "y" else "n"
  }

  result <- vpro:::vpro_cleanup_dir(path, answer)
  expect_identical(result$deleted, remove)
  expect_identical(result$skipped, keep)
  expect_identical(result$cancelled, FALSE)
  expect_length(prompts, 2L)
  expect_identical(file.exists(remove), FALSE)
  expect_identical(readLines(keep), "keep")
  expect_identical(dir.exists(path), TRUE)
})

test_that("c stops cleanup and empty input fails closed", {
  root <- withr::local_tempdir()
  path <- file.path(root, "data")
  dir.create(path)
  files <- file.path(path, c("a", "b"))
  writeLines("keep", files[[1]])
  writeLines("keep", files[[2]])
  calls <- 0L
  result <- vpro:::vpro_cleanup_dir(path, function(text) {
    calls <<- calls + 1L
    "c"
  })
  expect_identical(result$cancelled, TRUE)
  expect_identical(calls, 1L)
  expect_identical(file.exists(files), c(TRUE, TRUE))
  expect_identical(vpro:::vpro_cleanup_dir(path, function(text) "")$cancelled, TRUE)
  expect_identical(file.exists(files), c(TRUE, TRUE))
})

test_that("approving all files permits a fresh install", {
  root <- withr::local_tempdir()
  withr::local_options(
    vpro.data_dir = file.path(root, "data"),
    vpro.config_dir = file.path(root, "config")
  )
  vpro_install()
  config_path <- vpro_config_dir()
  data_path <- vpro_data_dir()
  vpro_config_set("Current", "CurrProject", "Changed")
  expect_gt(length(vpro:::vpro_cleanup_dir(config_path, function(text) "y")$deleted), 0L)
  expect_identical(dir.exists(config_path), FALSE)
  expect_gt(length(vpro:::vpro_cleanup_dir(data_path, function(text) "y")$deleted), 0L)
  expect_identical(dir.exists(data_path), FALSE)
  expect_identical(vpro:::vpro_cleanup_dir(data_path, function(text) "y")$deleted, character())

  vpro_install()
  expect_identical(config_init(file.path(config_path, "config.yml"))("Current", "CurrProject"), "Sample")
  expect_identical(file.exists(file.path(data_path, "projects", "Sample.db")), TRUE)
})

test_that("cleanup refuses unsafe roots, symlinks and non-directory paths", {
  root <- withr::local_tempdir()
  writeLines("keep", file.path(root, "keep.txt"))
  expect_error(vpro:::vpro_cleanup_dir("/", function(text) "y"), "unsafe")
  expect_identical(readLines(file.path(root, "keep.txt")), "keep")
  file_path <- file.path(root, "file")
  writeLines("keep", file_path)
  expect_error(vpro:::vpro_cleanup_dir(file_path, function(text) "y"), "not a directory")
  link <- file.path(root, "link")
  if (file.symlink(file_path, link)) {
    expect_error(vpro:::vpro_cleanup_dir(link, function(text) "y"), "symbolic-link")
  }
  expect_identical(readLines(file_path), "keep")
})
