test_that("startup creates local support and saved-query reference views without mutation", {
  con_check <- tryCatch(vpro_db_connect(install_extensions = FALSE), error = identity)
  if (inherits(con_check, "error")) {
    skip(conditionMessage(con_check))
  }
  vpro_db_disconnect(con_check)
  root <- withr::local_tempdir()
  withr::local_options(
    vpro.data_dir = file.path(root, "data"),
    vpro.config_dir = file.path(root, "config")
  )
  vpro_install()
  lists <- vpro_db_path("VLists")
  before <- unname(tools::md5sum(lists))
  startup <- vpro_startup(config = config_init(file.path(vpro_config_dir(), "config.yml")))
  withr::defer(vpro_project_close(startup$context))

  con <- startup$context$con
  expect_true(all(c("USysMasterSiteUnitList", "USysUserSiteUnitList", "MasterSiteUnitList", "MasterUnitList_Hierarchy") %in% DBI::dbListTables(con)))
  union_count <- DBI::dbGetQuery(
    con,
    paste(
      "SELECT COUNT(*) AS n FROM (SELECT * FROM VLists.MasterSiteUnitList",
      "UNION SELECT * FROM VUser.UserSiteUnitList)"
    )
  )$n
  expect_identical(DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM MasterSiteUnitList")$n, union_count)
  expect_identical(DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM MasterUnitList_Hierarchy")$n, union_count)
  expect_identical(startup$reference_descriptions$Table, c("USysAllSpecs", "USysTableOfLists"))
  expect_false(any(grepl("hash", startup$reference_descriptions$Description, ignore.case = TRUE)))
  expect_identical(unname(tools::md5sum(lists)), before)
})

test_that("legacy JustEnglishName is diagnosed without rename recovery", {
  con_check <- tryCatch(vpro_db_connect(install_extensions = FALSE), error = identity)
  if (inherits(con_check, "error")) {
    skip(conditionMessage(con_check))
  }
  vpro_db_disconnect(con_check)
  root <- withr::local_tempdir()
  lists <- file.path(root, "VLists.db")
  user <- file.path(root, "VUser.db")
  file.copy(system.file("extdata", "VLists.db", package = "vpro"), lists)
  file.copy(system.file("extdata", "VUser.db", package = "vpro"), user)
  sqlite <- DBI::dbConnect(RSQLite::SQLite(), lists)
  withr::defer(DBI::dbDisconnect(sqlite))
  DBI::dbExecute(sqlite, 'ALTER TABLE "USysAllSpecs" ADD COLUMN "JustEnglishName" TEXT')
  before <- unname(tools::md5sum(lists))
  con <- vpro_db_connect()
  withr::defer(vpro_db_disconnect(con))
  context <- vpro_project_context(con = con)
  vpro_db_attach(con, c(lists, user))

  diagnostics <- vpro:::vpro_startup_reference_views(context)
  expect_identical(diagnostics$Code, "legacy_just_english_name")
  expect_true(all(c("EnglishName", "CombinedEnglishName", "JustEnglishName") %in% DBI::dbListFields(con, DBI::Id(schema = "VLists", table = "USysAllSpecs"))))
  expect_identical(unname(tools::md5sum(lists)), before)
})
