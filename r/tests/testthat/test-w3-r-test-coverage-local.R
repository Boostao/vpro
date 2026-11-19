# Wave 3 (ENG-R-008): Offline unit test coverage for local R SDK exports and helpers

new_w3_cov_scratch_dir <- function(prefix = "w3cov") {
  dir_path <- file.path(
    tempdir(),
    sprintf("vpro-%s-%d-%06d", prefix, Sys.getpid(), sample.int(999999L, 1L))
  )
  dir.create(dir_path, recursive = TRUE, showWarnings = FALSE)
  normalizePath(dir_path, winslash = "/", mustWork = TRUE)
}

test_that("vpro_is_bundled_package_path narrows to extdata/cache and excludes covr vpro-tests", {
  expect_false(vpro:::vpro_is_bundled_package_path(NULL))
  expect_false(vpro:::vpro_is_bundled_package_path(""))
  expect_false(vpro:::vpro_is_bundled_package_path(NA_character_))
  expect_false(vpro:::vpro_is_bundled_package_path(file.path(tempdir(), "user-workspace", "MyProj.db")))

  pkg_dir <- system.file(package = "vpro")
  if (nzchar(pkg_dir)) {
    expect_true(vpro:::vpro_is_bundled_package_path(pkg_dir))
    expect_false(vpro:::vpro_is_bundled_package_path(
      file.path(pkg_dir, "vpro-tests", ".vpro-writeback-covr", "Sample.db")
    ))
    expect_false(vpro:::vpro_is_bundled_package_path(
      file.path(pkg_dir, "tests", "testthat", "scratch.db")
    ))
  }

  ext_dir <- vpro:::vpro_bundled_file("extdata", must_work = FALSE)
  if (nzchar(ext_dir)) {
    expect_true(vpro:::vpro_is_bundled_package_path(ext_dir))
    expect_true(vpro:::vpro_is_bundled_package_path(file.path(ext_dir, "Sample.db.gz")))
  }
  expect_true(vpro:::vpro_is_bundled_package_path(vpro:::vpro_bundled_db("Sample.db")))

  expect_true(vpro:::vpro_is_protected_support_db(""))
  expect_true(vpro:::vpro_is_protected_support_db("/any/dir/VLists.db"))
  expect_true(vpro:::vpro_is_protected_support_db("/any/dir/VUser.db"))
  expect_false(vpro:::vpro_is_protected_support_db("/any/dir/AlphaProj.db"))
})

test_that("Access boolean, percent cap, modifier unit, BEC classes, coordinates, and BC Gov theme exports work", {
  # vpro_access_to_logical & vpro_logical_to_access
  expect_identical(
    vpro_access_to_logical(c(TRUE, FALSE, NA)),
    c(TRUE, FALSE, NA)
  )
  expect_identical(
    vpro_access_to_logical(c(-1, 0, 5, NA_real_, Inf, -Inf)),
    c(TRUE, FALSE, TRUE, NA, NA, NA)
  )
  expect_identical(
    vpro_access_to_logical(c(
      "-1", "0", "+0", "-0", "true", "FALSE",
      "9223372036854775807", "-9223372036854775808",
      "9223372036854775808", "not_a_bool", "", NA_character_
    )),
    c(TRUE, FALSE, FALSE, FALSE, TRUE, FALSE, TRUE, TRUE, NA, NA, NA, NA)
  )

  expect_identical(
    vpro_logical_to_access(c(TRUE, FALSE, NA)),
    c(-1L, 0L, NA_integer_)
  )
  expect_identical(
    vpro_logical_to_access(c("-1", "0", "true", "false", "bad", NA_character_)),
    c(-1L, 0L, -1L, 0L, NA_integer_, NA_integer_)
  )

  # vpro_cap_percent
  expect_equal(vpro_cap_percent(c(-5, 0, 42.5, 99.9, 100, 135.2, NA_real_)), c(-5, 0, 42.5, 99.9, 100, 100, NA_real_))
  expect_error(vpro_cap_percent(character(0L)), "nonempty numeric")
  expect_error(vpro_cap_percent(c(10, Inf)), "finite")

  # vpro_is_modifier_unit
  units <- c("CWHvm1/01", "CWHvm1/01.poor", "SBSdk/04.SUPPORT", "ICHmc2/01.nudum", "$CWHvm1/02", "IDFdk1/03?", NA_character_)
  expect_identical(
    vpro_is_modifier_unit(units, include_tentative = FALSE),
    c(FALSE, TRUE, TRUE, TRUE, FALSE, FALSE, FALSE)
  )
  expect_identical(
    vpro_is_modifier_unit(units, include_tentative = TRUE),
    c(FALSE, TRUE, TRUE, TRUE, TRUE, TRUE, FALSE)
  )

  # Numeric presence classes, prominence/Goldstream recycling & validation, diagnostics ic/c/NA
  expect_identical(
    vpro_presence_class(c(-0.1, 0, 0.2, 0.25, 0.5, 0.75, 0.9, 1.1, NA_real_), format = "numeric"),
    c(NA_integer_, 1L, 1L, 2L, 3L, 4L, 5L, NA_integer_, NA_integer_)
  )
  expect_error(vpro_prominence_class(c(10, 20), c(0.2, 0.4, 0.6)), "common length")
  expect_error(vpro_goldstream_class(10, 0.5, return_score = NA), "TRUE or FALSE")
  expect_identical(
    vpro_classify_diagnostic_codes(c(U1 = NA_character_, U2 = NA_character_)),
    list(unit = NA_character_, diagnosis = NA_character_)
  )
  expect_identical(
    vpro_classify_diagnostic_codes(c(U1 = "5 - 3", U2 = "4 - 2")),
    list(unit = "U1", diagnosis = "c")
  )
  expect_identical(
    vpro_classify_diagnostic_codes(c(U1 = "2 - 2", U2 = NA_character_)),
    list(unit = "U1", diagnosis = "ic")
  )
  expect_error(vpro_classify_diagnostic_codes(c("5 - 5")), "named character")
  expect_error(vpro_classify_diagnostic_codes(c(U1 = "9 - 9")), "1 - \\+")

  # Coordinate conversions with NA minutes/seconds & vector recycling
  dec <- vpro_coordinate_decimal(c(54, 49), minutes = c(30, NA_real_), seconds = c(0, 36))
  expect_equal(dec, c(54.5, 49 + 36 / 3600), tolerance = 1e-10)
  dms <- vpro_coordinate_dms(c(-126.51, 54.25))
  expect_equal(dms$degrees, c(126, 54))
  dm <- vpro_coordinate_dm(c(-126.5, 54.75))
  expect_equal(dm$minutes, c(30, 45), tolerance = 1e-8)

  # vpro_bcgov_theme ("assets" and "ggplot2")
  assets <- vpro_bcgov_theme(type = "assets")
  expect_type(assets, "list")
  expect_equal(assets$navy, "#003366")
  expect_equal(assets$gold, "#FCBA19")
  expect_equal(assets$font_family, "BC Sans")
  expect_true(file.exists(assets$css_path))
  expect_length(assets$woff2, 4L)
  expect_true(all(file.exists(assets$woff2)))

  if (requireNamespace("ggplot2", quietly = TRUE)) {
    th <- vpro_bcgov_theme(type = "ggplot2", base_size = 12)
    expect_s3_class(th, "theme")
  }
})

test_that("workspace discovery, listing exports, vpro_use, vpro_duckdb, vpro_other, and vpro_metadata work", {
  scratch <- new_w3_cov_scratch_dir("workspace")
  on.exit(unlink(scratch, recursive = TRUE, force = TRUE), add = TRUE)

  data_dir <- file.path(scratch, "data")
  cfg_dir <- file.path(scratch, "cfg")
  dir.create(file.path(data_dir, "projects"), recursive = TRUE)
  dir.create(cfg_dir, recursive = TRUE)

  # Empty directory returns 0-row project tibble
  empty_projs <- vpro_list_projects(path = data_dir)
  expect_s3_class(empty_projs, "tbl_df")
  expect_equal(nrow(empty_projs), 0L)

  # Build a writable multi-table project AlphaProj.db cloned from bundled Sample.db
  alpha_db <- file.path(data_dir, "projects", "AlphaProj.db")
  src_sample <- vpro:::vpro_bundled_db("Sample.db")
  file.copy(src_sample, alpha_db, overwrite = TRUE)

  dbc <- DBI::dbConnect(RSQLite::SQLite(), alpha_db)
  on.exit(if (DBI::dbIsValid(dbc)) DBI::dbDisconnect(dbc), add = TRUE)
  for (sfx in c("Env", "Admin", "Veg", "Humus", "Mineral", "Other", "Audit", "Metadata", "SU", "Hierarchy", "Lump")) {
    old_t <- paste0("Sample_", sfx)
    new_t <- paste0("AlphaProj_", sfx)
    if (DBI::dbExistsTable(dbc, old_t)) {
      DBI::dbExecute(dbc, sprintf('ALTER TABLE "%s" RENAME TO "%s"', old_t, new_t))
    }
  }
  DBI::dbExecute(dbc, 'UPDATE "_table_metadata" SET "table_name" = REPLACE("table_name", \'Sample_\', \'AlphaProj_\')')
  # Add alternate SU, Hierarchy, and Lump tables + _Other rows with Access -1/0 flags
  DBI::dbExecute(dbc, 'CREATE TABLE "Alt2026_SU" AS SELECT * FROM "AlphaProj_SU" LIMIT 5')
  DBI::dbExecute(dbc, 'CREATE TABLE "Alt2026_Hierarchy" AS SELECT * FROM "AlphaProj_Hierarchy"')
  DBI::dbExecute(dbc, 'CREATE TABLE "Alt2026_Lump" AS SELECT * FROM "AlphaProj_Lump" LIMIT 3')
  other_cols <- DBI::dbListFields(dbc, "AlphaProj_Other")
  if (all(c("PlotNumber", "DataName", "DataItem", "Flag") %in% other_cols)) {
    DBI::dbExecute(
      dbc,
      'INSERT INTO "AlphaProj_Other" ("PlotNumber", "DataName", "DataItem", "Flag", "ID") VALUES (\'00337\', \'CWD\', \'12.4\', -1, 7001), (\'108050\', \'Epiphyte\', \'Usnea\', 0, 7002)'
    )
  }
  DBI::dbDisconnect(dbc)

  # Place a dummy support DB file in data_dir to verify vpro_list_projects skips support DB basenames
  file.copy(vpro:::vpro_bundled_db("VUser.db"), file.path(data_dir, "VUser.db"), overwrite = TRUE)

  ws <- vpro_connect("AlphaProj", su = "AlphaProj_SU", data_dir = data_dir, config_dir = cfg_dir)
  expect_equal(ws$project, "AlphaProj")
  expect_equal(ws$su, "AlphaProj_SU")
  expect_equal(ws$hierarchy, "AlphaProj_Hierarchy")
  expect_equal(ws$lump, "AlphaProj_Lump")

  # vpro_list_projects (ws, directory path, and direct file path)
  lp_ws <- vpro_list_projects(ws)
  expect_equal(nrow(lp_ws), 1L)
  expect_equal(lp_ws$project[[1L]], "AlphaProj")
  expect_true(lp_ws$complete[[1L]])
  expect_equal(lp_ws$version[[1L]], "VP08")
  expect_equal(lp_ws$n_plots[[1L]], 52L)

  lp_dir <- vpro_list_projects(path = data_dir)
  expect_equal(lp_dir$project, "AlphaProj")
  lp_file <- vpro_list_projects(path = alpha_db)
  expect_equal(lp_file$project, "AlphaProj")

  # vpro_list_su, vpro_list_hierarchies, vpro_list_lumps
  su_list <- vpro_list_su(ws)
  expect_true(all(c("AlphaProj_SU", "Alt2026_SU") %in% su_list$table))
  expect_true(su_list$active[su_list$table == "AlphaProj_SU"])
  expect_false(su_list$active[su_list$table == "Alt2026_SU"])
  expect_equal(su_list$n_plots[su_list$table == "Alt2026_SU"], 5L)

  hier_list <- vpro_list_hierarchies(ws)
  expect_true(all(c("AlphaProj_Hierarchy", "Alt2026_Hierarchy") %in% hier_list$table))
  expect_true(hier_list$active[hier_list$table == "AlphaProj_Hierarchy"])
  expect_gt(hier_list$n_nodes[[1L]], 0L)

  lump_list <- vpro_list_lumps(ws)
  expect_true(all(c("AlphaProj_Lump", "Alt2026_Lump") %in% lump_list$table))
  expect_true(lump_list$active[lump_list$table == "AlphaProj_Lump"])
  expect_equal(lump_list$n_rows[lump_list$table == "Alt2026_Lump"], 3L)

  # summary.vpro_workspace & print.vpro_workspace
  ws_sum <- summary(ws)
  expect_equal(ws_sum$project, "AlphaProj")
  expect_equal(nrow(ws_sum$su_tables), 2L)
  expect_no_error(capture.output(print(ws), type = "message"))

  # vpro_use switches and clears SU, Hierarchy, and Lump without mutating disk
  ws_alt <- vpro_use(ws, su = "Alt2026", hierarchy = "Alt2026_Hierarchy", lump = "Alt2026_Lump")
  expect_equal(ws_alt$su, "Alt2026_SU")
  expect_equal(ws_alt$hierarchy, "Alt2026_Hierarchy")
  expect_equal(ws_alt$lump, "Alt2026_Lump")
  expect_equal(nrow(vpro_site_units(ws_alt)), 5L)

  ws_none <- vpro_use(ws_alt, su = "None", hierarchy = "None", lump = "None")
  expect_null(ws_none[["su"]])
  expect_null(ws_none[["hierarchy"]])
  expect_null(ws_none[["lump"]])
  ws_none_named <- ws_alt
  ws_none_named[c("su", "hierarchy", "lump")] <- list(NULL, NULL, NULL)
  expect_no_error(capture.output(print(ws_none_named), type = "message"))
  expect_error(vpro_use(ws, project = "NoSuchProj"), "not found")
  expect_error(vpro_use(ws, su = "NoSuchSU"), "not found")

  # vpro_other (scope = "project" includes unassigned '00337'; scope = "su" filters to active SU)
  oth_proj <- vpro_other(ws, scope = "project")
  expect_s3_class(oth_proj, "tbl_df")
  expect_true("00337" %in% oth_proj$PlotNumber)
  if ("Flag" %in% names(oth_proj)) {
    expect_type(oth_proj$Flag, "logical")
    expect_true(any(oth_proj$Flag[oth_proj$PlotNumber == "00337"], na.rm = TRUE))
  }
  oth_su <- vpro_other(ws, scope = "su")
  expect_false("00337" %in% oth_su$PlotNumber)

  # vpro_metadata & vpro_soil S3 methods
  meta_tbl <- vpro_metadata(ws)
  expect_s3_class(meta_tbl, "tbl_df")
  expect_gt(nrow(meta_tbl), 0L)
  expect_equal(nrow(vpro_metadata(ws_alt)), nrow(meta_tbl))
  expect_equal(nrow(vpro_list_su(ws_alt)), 2L)
  expect_equal(nrow(vpro_list_hierarchies(ws_alt)), 2L)
  expect_equal(nrow(vpro_list_lumps(ws_alt)), 2L)

  soil_both <- vpro_soil(ws, scope = "project", type = "both")
  expect_no_error(capture.output(print(soil_both), type = "message"))
  soil_flat <- tibble::as_tibble(soil_both)
  expect_true(all(c("Humus", "Mineral") %in% soil_flat$SoilLayer))

  # vpro_duckdb cross-database read-only SQLite attachment
  if (requireNamespace("duckdb", quietly = TRUE)) {
    expect_error(vpro_duckdb(list()), "vpro_workspace")
    dcon <- suppressMessages(vpro_duckdb(ws))
    on.exit(if (DBI::dbIsValid(dcon)) DBI::dbDisconnect(dcon, shutdown = TRUE), add = TRUE)
    joined <- DBI::dbGetQuery(
      dcon,
      paste(
        'SELECT CAST(e."PlotNumber" AS VARCHAR) AS PlotNumber, v."Species", s."ScientificName"',
        'FROM project."AlphaProj_Env" AS e',
        'INNER JOIN project."AlphaProj_Veg" AS v ON e."PlotNumber" = v."PlotNumber"',
        'LEFT JOIN vlists."USysAllSpecs" AS s ON UPPER(v."Species") = UPPER(s."Code")',
        'LIMIT 10'
      )
    )
    expect_equal(nrow(joined), 10L)
    expect_type(joined$PlotNumber, "character")
    # Confirm read-only attachment blocks mutations
    expect_error(DBI::dbExecute(dcon, 'DELETE FROM project."AlphaProj_Env"'))
    DBI::dbDisconnect(dcon, shutdown = TRUE)
  }
})

test_that("vpro_filter_plots and vpro_env quality/column filters enforce DataQuality, BEC_Use, and orphan rules", {
  scratch <- new_w3_cov_scratch_dir("filter")
  on.exit(unlink(scratch, recursive = TRUE, force = TRUE), add = TRUE)

  db_path <- file.path(scratch, "FilterProj.db")
  file.copy(vpro:::vpro_bundled_db("Sample.db"), db_path, overwrite = TRUE)

  dbc <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  on.exit(if (DBI::dbIsValid(dbc)) DBI::dbDisconnect(dbc), add = TRUE)
  # Add plots covering:
  # - F_ORPH: in _Env and _SU but missing _Admin -> failed_criteria == "Project"
  # - F_POOR: Poor Site/Veg/Soil + BEC_Use 'A'
  # - F_GOOD: Good Site/Veg/Soil + BEC_Use 'C'
  # - F_MOD : Excellent quality but .poor modifier unit
  DBI::dbExecute(
    dbc,
    paste(
      'INSERT INTO "Sample_Env" ("PlotNumber", "Zone", "SubZone") VALUES',
      "('F_ORPH', 'CWH', 'vm1'),",
      "('F_POOR', 'CWH', 'vm1'),",
      "('F_GOOD', 'CWH', 'vm1'),",
      "('F_MOD', 'CWH', 'vm1')"
    )
  )
  DBI::dbExecute(
    dbc,
    paste(
      'INSERT INTO "Sample_Admin" ("Plot", "SitePlotQuality", "VegPlotQuality", "SoilPlotQuality", "BEC_Use") VALUES',
      "('F_POOR', 'Poor', 'Poor', 'Poor', 'A'),",
      "('F_GOOD', 'Good', 'Good', 'Good', 'C'),",
      "('F_MOD', 'Excellent', 'Excellent', 'Excellent', 'D')"
    )
  )
  DBI::dbExecute(
    dbc,
    paste(
      'INSERT INTO "Sample_SU" ("PlotNumber", "SiteUnit") VALUES',
      "('F_ORPH', 'CWHvm1/01'),",
      "('F_POOR', 'CWHvm1/01'),",
      "('F_GOOD', 'CWHvm1/01'),",
      "('F_MOD', 'CWHvm1/01.poor')"
    )
  )
  DBI::dbDisconnect(dbc)

  ws <- vpro_connect(db_path, su = "Sample_SU", data_dir = scratch, config_dir = scratch)

  expect_error(vpro_filter_plots(ws, site_min = "NotALevel"), "DataQuality")

  flt <- vpro_filter_plots(
    ws,
    site_min = "Good",
    veg_min = "Good",
    soil_min = "Good",
    include_site_missing = FALSE,
    include_veg_missing = FALSE,
    include_soil_missing = FALSE,
    bec_min = "B",
    include_bec_missing = FALSE,
    exclude_modifiers = TRUE,
    scope = "su"
  )
  expect_true("F_GOOD" %in% flt$selected$PlotNumber)
  expect_false("F_MOD" %in% flt$selected$PlotNumber)
  expect_false("F_POOR" %in% flt$selected$PlotNumber)
  expect_false("F_ORPH" %in% flt$selected$PlotNumber)

  rem_orph <- flt$removed[flt$removed$PlotNumber == "F_ORPH", ]
  expect_equal(rem_orph$failed_criteria, "Project")
  rem_poor <- flt$removed[flt$removed$PlotNumber == "F_POOR", ]
  expect_equal(rem_poor$failed_criteria, "Site,Veg,Soil,BEC")

  flt_proj <- vpro_filter_plots(ws, site_min = "Fair", exclude_modifiers = TRUE, scope = "project")
  expect_true("F_GOOD" %in% flt_proj$selected$PlotNumber)
  expect_false("F_MOD" %in% flt_proj$selected$PlotNumber)

  # Exercise vpro_env(..., filter_quality = TRUE / string / list, columns = ...)
  env_q_true <- vpro_env(ws, filter_quality = TRUE)
  expect_false("F_ORPH" %in% env_q_true$PlotNumber)
  env_q_str <- vpro_env(ws, filter_quality = "Good", columns = c("Zone", "BECSiteUnit"))
  expect_true(all(c("PlotNumber", "SiteUnit", "Zone", "BECSiteUnit") %in% names(env_q_str)))
  env_q_lst <- vpro_env(ws, filter_quality = list(site_min = "Good", bec_min = "C", include_bec_missing = FALSE))
  expect_true("F_GOOD" %in% env_q_lst$PlotNumber)
  expect_false("F_POOR" %in% env_q_lst$PlotNumber)
})

test_that("vpro_hierarchy_to_table, vpro_table_to_hierarchy, and vpro_hierarchy handle ~ breakpoints, empty inputs, and cycles", {
  expect_error(vpro_hierarchy_to_table(data.frame(ID = 1L)), "must contain")
  expect_error(vpro_table_to_hierarchy(data.frame()), "non-empty")

  empty_h <- vpro_hierarchy_to_table(
    data.frame(ID = integer(), Name = character(), Parent = integer(), Level = integer())
  )
  expect_equal(nrow(empty_h), 0L)
  expect_true(all(c("Formation", "Order", "Suborder", "Alliance", "Suball", "Assoc", "Subass", "SiteUnit", "BreakpointUnit") %in% names(empty_h)))

  nodes <- tibble::tibble(
    ID = c(1L, 2L, 3L, 4L, 5L),
    Name = c("Forest", "~TsugaOrder", "ThujaAlliance", "CWHvm1_Assoc", "CWHvm1/01"),
    Parent = c(NA_integer_, 1L, 2L, 3L, 4L),
    Level = c(1L, 4L, 6L, 8L, 11L)
  )

  paths_clean <- vpro_hierarchy_to_table(nodes, preserve_tilde = FALSE)
  expect_equal(nrow(paths_clean), 1L)
  expect_equal(paths_clean$Order, "TsugaOrder")
  # Suborder/Suball/Subass auto-fill from Order/Alliance/Assoc
  expect_equal(paths_clean$Suborder, "TsugaOrder")
  expect_equal(paths_clean$Suball, "ThujaAlliance")
  expect_equal(paths_clean$Subass, "CWHvm1_Assoc")
  expect_equal(paths_clean$SiteUnit, "CWHvm1/01")
  expect_equal(paths_clean$BreakpointUnit, "TsugaOrder")

  paths_tilde <- vpro_hierarchy_to_table(nodes, preserve_tilde = TRUE)
  expect_equal(paths_tilde$Order, "~TsugaOrder")
  roundtrip <- vpro_table_to_hierarchy(paths_tilde[, 1:11])
  expect_true("~TsugaOrder" %in% roundtrip$Name)

  # Parent cycle terminates cleanly without infinite recursion
  cyc_nodes <- tibble::tibble(
    ID = c(10L, 20L, 30L),
    Name = c("NodeA", "NodeB", "LeafC"),
    Parent = c(20L, 10L, 20L),
    Level = c(1L, 4L, 11L)
  )
  cyc_paths <- vpro_hierarchy_to_table(cyc_nodes)
  expect_equal(nrow(cyc_paths), 1L)
  expect_equal(cyc_paths$SiteUnit, "LeafC")

  # Workspace vpro_hierarchy modes & S3 methods (including hierarchy = "None")
  ws <- vpro_connect("Sample")
  h_both <- vpro_hierarchy(ws, as = "both")
  expect_no_error(capture.output(print(h_both), type = "message"))
  expect_s3_class(tibble::as_tibble(h_both), "tbl_df")
  expect_s3_class(vpro_hierarchy(ws, as = "nodes"), "tbl_df")
  expect_s3_class(vpro_hierarchy(ws, as = "paths"), "tbl_df")

  ws_no_h <- ws
  ws_no_h["hierarchy"] <- list(NULL)
  h_empty <- vpro_hierarchy(ws_no_h, as = "both")
  expect_equal(nrow(h_empty$nodes), 0L)
  expect_equal(nrow(vpro_hierarchy(ws_no_h, as = "nodes")), 0L)
  expect_equal(nrow(vpro_hierarchy(ws_no_h, as = "paths")), 0L)
  expect_no_error(capture.output(print(h_empty), type = "message"))
})

test_that("vpro_access_inspect validates inputs and inspects Access tables offline and on local fixtures", {
  expect_error(vpro_access_inspect(tempfile(fileext = ".accdb")), "existing")
  expect_error(vpro_access_inspect(tempdir()), "existing")

  skip_if_not_installed("mdbr")
  dummy_accdb <- tempfile("mock-inspect-", fileext = ".accdb")
  writeBin(as.raw(1:16), dummy_accdb)
  on.exit(unlink(dummy_accdb, force = TRUE), add = TRUE)

  testthat::local_mocked_bindings(
    mdb_tables = function(path, type = "table") {
      if (identical(type, "linkedtable")) {
        c("USysAllSpecs", "USysTableOfLists")
      } else {
        c("Demo_Env", "Demo_Veg", "Legacy_Env", "USysEnv", "Filtered_Env")
      }
    },
    mdb_count = function(path, tbl) {
      switch(tbl, Demo_Env = 24L, Demo_Veg = 310L, Legacy_Env = 8L, 0L)
    },
    mdb_prop = function(path, name) {
      if (identical(name, "Demo_Env")) {
        list(Demo_Env = list(`(none)` = c(Description = "VP08")))
      } else if (identical(name, "Legacy_Env")) {
        list(Legacy_Env = list(`(none)` = c(Description = "VP03")))
      } else {
        NULL
      }
    },
    .package = "mdbr"
  )

  insp <- vpro_access_inspect(dummy_accdb)
  expect_equal(insp$projects$project, c("Demo", "Legacy"))
  expect_equal(insp$projects$version, c("VP08", "VP03"))
  expect_equal(insp$projects$compatible, c(TRUE, FALSE))
  expect_equal(insp$projects$n_plots, c(24L, 8L))
  expect_equal(insp$links, c("USysAllSpecs", "USysTableOfLists"))
})

test_that("climate fallback normals, taxonomy user-conflict detection, and guide payload builders cover edge branches", {
  # BGC lapse-rate model: exact BGC match, Zone-mean fallback, and nearest-neighbor fallback
  pts <- data.frame(
    CoordElevHash = c("h1", "h2", "h3"),
    bgc = c("SBSdk", "CWH_UNKNOWN_SUBZONE", ""),
    zone = c("SBS", "CWH", "UNKNOWN_ZONE"),
    lat = c(54.5, 49.5, 52.1),
    lon = c(-126.5, -125.1, -122.3),
    elev = c(650, 300, 900),
    stringsAsFactors = FALSE
  )
  lapse_6190 <- vpro:::vpro_compute_bgc_lapse_normals(pts, "1961_1990")
  lapse_9120 <- vpro:::vpro_compute_bgc_lapse_normals(pts, "1991_2020")
  expect_equal(nrow(lapse_6190), 3L)
  expect_true(all(is.finite(lapse_6190$MAT)))
  expect_true(all(lapse_9120$MAT > lapse_6190$MAT))

  expect_type(vpro:::vpro_climr_has_local_rasters(), "logical")

  # Taxonomy with conflicting VUser.db species tuple surfaces attr(tax, "conflicts")
  scratch <- new_w3_cov_scratch_dir("tax")
  on.exit(unlink(scratch, recursive = TRUE, force = TRUE), add = TRUE)
  file.copy(vpro:::vpro_bundled_db("Sample.db"), file.path(scratch, "SampleCopy.db"))
  file.copy(vpro:::vpro_bundled_db("VUser.db"), file.path(scratch, "VUser.db"))
  dbu <- DBI::dbConnect(RSQLite::SQLite(), file.path(scratch, "VUser.db"))
  on.exit(if (DBI::dbIsValid(dbu)) DBI::dbDisconnect(dbu), add = TRUE)
  DBI::dbExecute(
    dbu,
    "INSERT OR REPLACE INTO \"USysUserSpp\" (\"Code\", \"ScientificName\", \"LifeForm\", \"EnglishName\", \"Codetype\") VALUES ('PINUCON', 'Pinus contorta custom', 99, 'Custom lodgepole', 'U')"
  )
  DBI::dbDisconnect(dbu)

  ws_tax <- vpro_connect(file.path(scratch, "SampleCopy.db"), data_dir = scratch, config_dir = scratch)
  tax_clean <- vpro_taxonomy(ws_tax, include_synonyms = FALSE, include_user = TRUE)
  conflicts <- attr(tax_clean, "conflicts")
  expect_true("PINUCON" %in% conflicts$Code)
  tax_with_syn <- vpro_taxonomy(ws_tax, include_synonyms = TRUE, include_user = FALSE)
  expect_gt(nrow(tax_with_syn), nrow(tax_clean))

  # Quarto guide payload builders (qc_audit & veg_summary) & vpro_climate empty/guard paths
  ws_sample <- vpro_connect("Sample")
  expect_error(vpro_climate(ws_sample, allow_fallback = FALSE, force_offline = TRUE), "Cannot set both")

  no_coord_db <- file.path(scratch, "NoCoords.db")
  file.copy(vpro:::vpro_bundled_db("Sample.db"), no_coord_db)
  dbnc <- DBI::dbConnect(RSQLite::SQLite(), no_coord_db)
  DBI::dbExecute(dbnc, 'UPDATE "Sample_Env" SET "Latitude" = NULL, "Longitude" = NULL')
  DBI::dbExecute(dbnc, 'CREATE TABLE "Empty_SU" ("PlotNumber" TEXT, "SiteUnit" TEXT)')
  DBI::dbDisconnect(dbnc)
  ws_nc <- vpro_connect(no_coord_db, su = "Sample_SU", data_dir = scratch, config_dir = scratch)
  clim_nc <- vpro_climate(ws_nc, force_offline = TRUE)
  expect_equal(nrow(clim_nc), 0L)
  expect_gt(attr(clim_nc, "skipped_no_coords"), 0L)
  ws_empty_su <- vpro_use(ws_nc, su = "Empty_SU")
  expect_equal(nrow(vpro_climate(ws_empty_su, scope = "su", force_offline = TRUE)), 0L)

  qc_payload <- vpro:::vpro_build_guide_payload(ws_sample, type = "qc_audit", force_offline = TRUE)
  expect_equal(qc_payload$guideType, "qc_audit")
  expect_gt(qc_payload$plotCount, 30L)
  veg_payload <- vpro:::vpro_build_guide_payload(ws_sample, type = "veg_summary", bgc = "SBS", force_offline = TRUE)
  expect_equal(veg_payload$guideType, "veg_summary")
})
