test_that("bundled data installs without overwriting user files", {
  root <- withr::local_tempdir()
  withr::local_options(vpro.data_dir = file.path(root, "data"))

  path <- vpro_data_install()
  expect_true(file.exists(file.path(path, "VPro64.db")))

  marker <- file.path(path, "VPro64.db")
  writeBin(charToRaw("user-owned"), marker)
  vpro_data_install()
  expect_identical(readBin(marker, "raw", n = file.info(marker)$size), charToRaw("user-owned"))
})

test_that("vpro_install initializes both storage roots", {
  root <- withr::local_tempdir()
  withr::local_options(
    vpro.data_dir = file.path(root, "data"),
    vpro.config_dir = file.path(root, "config")
  )

  installed <- vpro_install()
  expect_true(dir.exists(installed$data_dir))
  expect_true(file.exists(installed$config_file))
})
