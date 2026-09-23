test_that("standalone long environment QMD renders units and visible diagnostics", {
  skip_if_not_installed("quarto")
  skip_if_not_installed("rmarkdown")
  if (!nzchar(Sys.which("quarto"))) {
    skip("Quarto CLI unavailable")
  }
  installed_vpro <- tryCatch(
    getNamespaceExports(loadNamespace("vpro", lib.loc = .libPaths())),
    error = function(e) character()
  )
  if (!"vpro_report_long_environment" %in% installed_vpro) {
    skip("Installed vpro lacks the long-environment API required by the Quarto subprocess")
  }

  template <- system.file("reports", "long_environment.qmd", package = "vpro")
  source_path <- system.file("extdata", "projects", "Sample.db", package = "vpro")
  expect_true(file.exists(template))
  root <- withr::local_tempdir()
  project_path <- file.path(root, "sample.db")
  su_path <- file.path(root, "subset.db")
  reference_path <- file.path(root, "lists.db")
  expect_true(file.copy(source_path, project_path))

  project <- DBI::dbConnect(RSQLite::SQLite(), project_path)
  DBI::dbExecute(project, "DELETE FROM Sample_Admin WHERE Plot = '108050x'")
  DBI::dbDisconnect(project)

  su <- DBI::dbConnect(RSQLite::SQLite(), su_path)
  DBI::dbExecute(su, 'CREATE TABLE "Subset_SU" ("PlotNumber" TEXT, "SiteUnit" TEXT)')
  for (plot in c("00337", "00337", "108050x", "ORPHAN")) {
    DBI::dbExecute(su, 'INSERT INTO "Subset_SU" VALUES (?, ?)', params = list(plot, "U"))
  }
  DBI::dbExecute(su, 'INSERT INTO "Subset_SU" VALUES (?, ?)', params = list("108050", "V"))
  DBI::dbDisconnect(su)

  reference <- DBI::dbConnect(RSQLite::SQLite(), reference_path)
  DBI::dbExecute(reference, 'CREATE TABLE "MasterSiteUnitList" ("SiteSeries" TEXT, "SiteSeriesLongName" TEXT, "Level" INTEGER)')
  for (name in c("First title", "Second title")) {
    DBI::dbExecute(reference, 'INSERT INTO "MasterSiteUnitList" VALUES (?, ?, ?)', params = list("U", name, 11L))
  }
  DBI::dbDisconnect(reference)

  input <- file.path(root, "long_environment.qmd")
  expect_true(file.copy(template, input))
  before <- unname(tools::md5sum(c(source_path, project_path, su_path, reference_path)))
  tryCatch(
    quarto::quarto_render(
      input,
      execute_params = list(
        project_path = project_path,
        project = "Sample",
        su_path = su_path,
        su = "Subset",
        reference_path = reference_path
      ),
      output_file = "long_environment.html",
      quiet = TRUE
    ),
    error = function(e) {
      if (grepl("sqlite_scanner extension is not installed", conditionMessage(e), fixed = TRUE)) {
        skip("DuckDB sqlite_scanner unavailable for a separate Quarto R process")
      }
      stop(e)
    }
  )
  output <- file.path(root, "long_environment.html")
  expect_true(file.exists(output))
  html <- paste(readLines(output, warn = FALSE), collapse = "\n")
  expect_match(html, "Project: Sample. Site-unit table: Subset.", fixed = TRUE)
  expect_match(html, "Site unit: U", fixed = TRUE)
  expect_match(html, "Site unit: V", fixed = TRUE)
  wrappers <- gregexpr('class="table-responsive"', html, fixed = TRUE)[[1L]]
  expect_length(wrappers[wrappers > 0L], 2L)
  expect_match(html, 'aria-label="Environmental fields by plot"', fixed = TRUE)
  expect_match(html, "Conflicting unit names", fixed = TRUE)
  expect_match(html, "First title; Second title", fixed = TRUE)
  expect_match(html, "Missing unit name", fixed = TRUE)
  expect_match(html, "Missing Env", fixed = TRUE)
  expect_match(html, "Missing Admin", fixed = TRUE)
  expect_match(html, "ORPHAN", fixed = TRUE)
  expect_match(html, "Membership rows", fixed = TRUE)
  expect_match(html, "GENERAL LOCATION", fixed = TRUE)
  expect_match(html, "Assigned Site Unit", fixed = TRUE)
  expect_identical(unname(tools::md5sum(c(source_path, project_path, su_path, reference_path))), before)
})
