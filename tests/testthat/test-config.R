test_that("configuration installs and persists values", {
  root <- withr::local_tempdir()
  withr::local_options(vpro.config_dir = file.path(root, "config"))

  path <- vpro_config_install()
  expect_true(file.exists(path))
  expect_identical(vpro_config_get("Current", "CurrProject"), "Sample")

  vpro_config_set("Current", "CurrProject", "Example")
  expect_identical(vpro_config_get("Current", "CurrProject"), "Example")
  expect_identical(yaml::read_yaml(path)$Current$CurrProject, "Example")
})

test_that("configuration refuses unknown keys", {
  root <- withr::local_tempdir()
  withr::local_options(vpro.config_dir = file.path(root, "config"))

  vpro_config_install()
  expect_error(vpro_config_get("Missing"), "Unknown VPRO configuration section")
  expect_error(vpro_config_get("Current", "Missing"), "Unknown VPRO configuration key")
})
