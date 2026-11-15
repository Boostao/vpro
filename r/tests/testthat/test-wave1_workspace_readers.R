test_that("DESCRIPTION enforces zero Shiny/widget bloat and R >= 4.4.0", {
  desc_path <- system.file("DESCRIPTION", package = "vpro")
  if (!nzchar(desc_path) && file.exists("../../DESCRIPTION")) {
    desc_path <- "../../DESCRIPTION"
  }
  skip_if_not(nzchar(desc_path) && file.exists(desc_path))
  dcf <- read.dcf(desc_path)
  forbidden <- c("shiny", "bslib", "DT", "rhandsontable", "shinyTree", "shinyjs", "sass", "leaflet", "rappdirs")
  imports_raw <- paste(dcf[, intersect(c("Depends", "Imports"), colnames(dcf))], collapse = ",")
  for (pkg in forbidden) {
    expect_false(grepl(paste0("\\b", pkg, "\\b"), imports_raw), info = pkg)
  }
  expect_match(dcf[, "Depends"], "R \\(>= 4\\.4\\.0\\)")
})

test_that("vpro_data_dir and vpro_config_dir match Go app sqlutil_foundation.go across OSes", {
  # Explicit option / env overrides take precedence
  withr::with_options(list(vpro.data_dir = "/tmp/custom-vpro-data", vpro.config_dir = "/tmp/custom-vpro-cfg"), {
    expect_equal(vpro_data_dir(), "/tmp/custom-vpro-data")
    expect_equal(vpro_config_dir(), "/tmp/custom-vpro-cfg")
  })
  withr::with_options(list(vpro.data_dir = NULL, vpro.config_dir = NULL), {
    withr::with_envvar(c(VPRO_DATA_DIR = "/tmp/env-vpro-data", VPRO_CONFIG_DIR = "/tmp/env-vpro-cfg"), {
      expect_equal(vpro_data_dir(), "/tmp/env-vpro-data")
      expect_equal(vpro_config_dir(), "/tmp/env-vpro-cfg")
    })
  })

  # Windows: LOCALAPPDATA/vpro (never rappdirs's doubled vpro/vpro!) + USERPROFILE fallback
  expect_equal(
    vpro:::vpro_resolve_data_dir(os = "Windows", opt = NULL, env_data = "", localappdata = "C:/Users/ecologist/AppData/Local", userprofile = "C:/Users/ecologist"),
    "C:/Users/ecologist/AppData/Local/vpro"
  )
  expect_equal(
    vpro:::vpro_resolve_data_dir(os = "Windows", opt = NULL, env_data = "", localappdata = "", userprofile = "C:/Users/ecologist"),
    "C:/Users/ecologist/AppData/Local/vpro"
  )
  expect_equal(
    vpro:::vpro_resolve_config_dir(os = "Windows", opt = NULL, env_cfg = "", appdata = "C:/Users/ecologist/AppData/Roaming"),
    "C:/Users/ecologist/AppData/Roaming/vpro"
  )

  # macOS (Darwin): ~/Library/Application Support/vpro for both
  expect_equal(
    vpro:::vpro_resolve_data_dir(os = "Darwin", opt = NULL, env_data = "", home = "/Users/ecologist"),
    "/Users/ecologist/Library/Application Support/vpro"
  )
  expect_equal(
    vpro:::vpro_resolve_config_dir(os = "Darwin", opt = NULL, env_cfg = "", home = "/Users/ecologist"),
    "/Users/ecologist/Library/Application Support/vpro"
  )

  # Linux: XDG_DATA_HOME / XDG_CONFIG_HOME with ~/.local/share and ~/.config fallbacks
  expect_equal(
    vpro:::vpro_resolve_data_dir(os = "Linux", opt = NULL, env_data = "", xdg_data = "", home = "/home/ecologist"),
    "/home/ecologist/.local/share/vpro"
  )
  expect_equal(
    vpro:::vpro_resolve_data_dir(os = "Linux", opt = NULL, env_data = "", xdg_data = "/var/xdg-data", home = "/home/ecologist"),
    "/var/xdg-data/vpro"
  )
  expect_equal(
    vpro:::vpro_resolve_config_dir(os = "Linux", opt = NULL, env_cfg = "", xdg_cfg = "", home = "/home/ecologist"),
    "/home/ecologist/.config/vpro"
  )
})

test_that("2026 standards SHA-256 verification and vpro_status succeed", {
  std <- vpro_standards()
  expect_true(std$verified)
  expect_equal(std$vlists_sha256, "81e259244106b14d6dd3c65f0a7e7e87bdb06f60e6c54947c0506e2039379441")
  expect_equal(nrow(std$sources), 2L)
  expect_true(any(grepl("BECdb_v13_2026", std$sources$version)))
  expect_true(any(grepl("BCPlantTaxa_v19_2025", std$sources$version)))

  st <- vpro_status(data_dir = tempdir(), config_dir = tempdir())
  expect_s3_class(st, "vpro_status")
  expect_s3_class(tibble::as_tibble(st), "tbl_df")
  expect_message(print(st), "vpro 2.0")
})

test_that("calibrated float32 narrowing, ACE 15-digit rounding, and BEC classes match oracles", {
  expect_lt(vpro_narrow_float32(99.999996), 100)
  expect_equal(vpro_narrow_float32(99.999999), 100)
  expect_equal(vpro_round_ace(c(1.005, -1.005, 2.5, NA), digits = 2L), c(1.01, -1.01, 2.5, NA))

  expect_equal(vpro_presence_class(c(0, 0.2, 0.2001, 0.4, 0.6, 0.8, 0.8001, 1)), c("I", "I", "II", "II", "III", "IV", "V", "V"))
  expect_equal(vpro_significance_class(c(0.1, 0.3, 0.31, 1.0, 2.2, 5.0, 10.0, 20.0, 33.0, 50.0, 75.0, 80.0)), c("+", "+", "1", "1", "2", "3", "4", "5", "6", "7", "8", "9"))
  expect_equal(vpro_prominence_class(20, 0.25, return_score = TRUE), 100)
  expect_equal(vpro_prominence_class(20, 0.25, return_score = FALSE), 3L)
  expect_equal(vpro_goldstream_class(25, 0.5, return_score = TRUE), 250)
  expect_equal(vpro_goldstream_class(25, 0.5, return_score = FALSE), 4L)

  expect_equal(
    vpro_classify_diagnostic_codes(c(UnitB = "5 - 6", UnitA = "2 - 1", UnitC = "1 - +")),
    list(unit = "UnitB", diagnosis = "d, cd")
  )
  expect_equal(
    vpro_classify_diagnostic_codes(c(UnitB = "4 - 6", UnitA = "4 - 2", UnitC = "2 - 1")),
    list(unit = "UnitB", diagnosis = "dd")
  )

  expect_equal(vpro_coordinate_decimal(-126, -30, -36), -126.51)
  expect_equal(vpro_coordinate_dms(-126.51)$minutes, 30)
  expect_equal(round(vpro_coordinate_dm(-126.5)$minutes, 4), 30)
})

test_that("vpro_connect('Sample') and tidy readers work with leading-zero PlotNumber, booleans, lump 99% cap, and LMH25 order", {
  ws <- vpro_connect("Sample")
  expect_s3_class(ws, "vpro_workspace")
  expect_equal(ws$project, "Sample")
  expect_equal(ws$su, "Sample_SU")
  expect_true(vpro_project_inspect(ws$project_path, "Sample")$compatible)

  env <- vpro_env(ws)
  expect_s3_class(env, "tbl_df")
  expect_type(env$PlotNumber, "character")
  expect_type(env$Flag, "logical")
  expect_equal(nrow(env), 51L)

  env_all <- vpro_env(ws, scope = "project")
  expect_equal(nrow(env_all), 52L)

  veg_tot <- vpro_veg(ws, strata = "total", lump = TRUE)
  expect_s3_class(veg_tot, "tbl_df")
  expect_true(all(c("PlotNumber", "SiteUnit", "Species", "Cover", "ScientificName", "Lifeform") %in% names(veg_tot)))
  expect_gt(nrow(veg_tot), 500L)

  veg_abcd <- vpro_veg(ws, strata = "abcd", lump = FALSE)
  expect_true(all(veg_abcd$Strata %in% c("A", "B", "C", "D")))

  soil <- vpro_soil(ws)
  expect_s3_class(soil, "vpro_soil")
  expect_gt(nrow(soil$humus), 0L)
  expect_gt(nrow(soil$mineral), 0L)

  hier <- vpro_hierarchy(ws)
  expect_s3_class(hier, "vpro_hierarchy")
  expect_gt(nrow(hier$nodes), 10L)
  expect_gt(nrow(hier$paths), 3L)
  roundtrip_nodes <- vpro_table_to_hierarchy(hier$paths[, 1:11])
  expect_gt(nrow(roundtrip_nodes), 5L)

  tax <- vpro_taxonomy(ws)
  expect_gt(nrow(tax), 10000L)
  expect_type(tax$Lifeform, "integer")

  bec <- vpro_bec_units(ws, zone = "CWH")
  expect_gt(nrow(bec), 100L)
  expect_true(all(toupper(bec$BGC_Zone) == "CWH"))
})

test_that("live simulated VPro desktop WAL workspace coexists with active writer and enforces invariants", {
  sim_root <- tempfile("vpro-desktop-sim-")
  sim_data <- file.path(sim_root, "data")
  sim_cfg <- file.path(sim_root, "config")
  dir.create(file.path(sim_data, "projects"), recursive = TRUE)
  dir.create(sim_cfg, recursive = TRUE)
  on.exit(unlink(sim_root, recursive = TRUE), add = TRUE)

  # Clone Sample.db -> LiveProj.db in WAL mode with leading-zero PlotNumber '00337',
  # synonym THUIABI -> ABIEABI, lumped species exceeding 99% in layer, and upland/wetland horizons
  db_path <- file.path(sim_data, "projects", "Sample.db")
  file.copy(vpro_connect("Sample")$project_path, db_path)

  wcon <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  on.exit(if (DBI::dbIsValid(wcon)) DBI::dbDisconnect(wcon), add = TRUE)
  DBI::dbExecute(wcon, "PRAGMA journal_mode = WAL")
  DBI::dbExecute(
    wcon,
    'INSERT INTO "Sample_Env" ("PlotNumber", "Zone", "SubZone", "Flag", "SpeciesListComplete") VALUES (\'00999\', \'CWH\', \'vm\', -1, 0)'
  )
  DBI::dbExecute(
    wcon,
    'INSERT INTO "Sample_Admin" ("Plot", "SitePlotQuality", "VegPlotQuality", "SoilPlotQuality", "UpdatedFromCards") VALUES (\'00999\', \'Good\', \'Good\', \'Good\', -1)'
  )
  # Sample_SU has uidx_Sample_SU_PlotNumber; test both a normal plot and a .poor modifier plot
  DBI::dbExecute(
    wcon,
    'INSERT INTO "Sample_Env" ("PlotNumber", "Zone", "SubZone", "Flag", "SpeciesListComplete") VALUES (\'00998\', \'CWH\', \'vm\', 0, -1)'
  )
  DBI::dbExecute(
    wcon,
    'INSERT INTO "Sample_Admin" ("Plot", "SitePlotQuality", "VegPlotQuality", "SoilPlotQuality", "UpdatedFromCards") VALUES (\'00998\', \'Poor\', \'Poor\', \'Poor\', 0)'
  )
  DBI::dbExecute(
    wcon,
    'INSERT INTO "Sample_SU" ("PlotNumber", "SiteUnit") VALUES (\'00999\', \'CWHvm1/01\'), (\'00998\', \'CWHvm1/01.poor\')'
  )
  # Add two species that lump into POASPP with Cover6 = 65 + 55 = 120 -> must cap at 99%
  # Plus synonym THUIABI -> ABIEABI
  DBI::dbExecute(
    wcon,
    'INSERT INTO "Sample_Veg" ("PlotNumber", "Species", "Cover6") VALUES (\'00999\', \'POA PRA2\', 65.0), (\'00999\', \'POA SEC\', 55.0), (\'00999\', \'THUIABI\', 12.0)'
  )
  # Add upland L/F/H (UpperDepth > LowerDepth) and wetland Of/Om (UpperDepth < LowerDepth)
  DBI::dbExecute(
    wcon,
    paste(
      'INSERT INTO "Sample_Humus" ("PlotNumber", "Horizon", "UpperDepth", "LowerDepth", "Flag") VALUES',
      '(\'00999\', \'H\', 2, 0, 0), (\'00999\', \'L\', 8, 6, -1), (\'00999\', \'F\', 6, 2, 0),',
      '(\'00999\', \'Om\', 15, 40, 0), (\'00999\', \'Of\', 0, 15, 0)'
    )
  )

  # Write live config.yml matching VPro desktop
  yaml::write_yaml(
    list(
      Current = list(
        CurrProject = "Sample",
        CurrPlotlist = "Sample_SU",
        CurrHierarchy = "Sample_Hierarchy"
      )
    ),
    file.path(sim_cfg, "config.yml")
  )

  # Keep wcon open (simulating live VPro desktop WAL connection!) while R connects with 0 args
  withr::with_options(list(vpro.data_dir = sim_data, vpro.config_dir = sim_cfg), {
    ws <- vpro_connect()
    expect_equal(ws$project, "Sample")
    expect_equal(ws$su, "Sample_SU")

    # Exclude .poor modifier unit; verify both Sample's '00337' (project scope) and '00999' (SU scope) leading zeroes
    env_proj <- vpro_env(ws, scope = "project")
    expect_true("00337" %in% env_proj$PlotNumber)
    env_clean <- vpro_env(ws, exclude_modifiers = TRUE)
    expect_false("00998" %in% env_clean$PlotNumber)
    p00999 <- env_clean[env_clean$PlotNumber == "00999", ]
    expect_equal(nrow(p00999), 1L)
    expect_equal(p00999$PlotNumber, "00999")
    expect_identical(p00999$Flag, TRUE)
    expect_identical(p00999$SpeciesListComplete, FALSE)
    expect_identical(p00999$UpdatedFromCards, TRUE)

    veg <- vpro_veg(ws, strata = "raw", lump = TRUE, resolve_synonyms = TRUE, exclude_modifiers = TRUE)
    v999 <- veg[veg$PlotNumber == "00999", ]
    # POA PRA2 (65) + POA SEC (55) -> POASPP capped at 99%!
    expect_equal(v999$Cover[v999$Species == "POASPP" & v999$Layer == "6"], 99.0)
    # THUIABI -> ABIEABI synonym resolved!
    expect_true("ABIEABI" %in% v999$Species)
    expect_false("THUIABI" %in% v999$Species)

    # LMH25 horizon ordering: upland L (8) -> F (6) -> H (2) DESC, then wetland Of (0) -> Om (15) ASC!
    hum999 <- vpro_soil(ws, type = "humus")
    hum999 <- hum999[hum999$PlotNumber == "00999", ]
    expect_equal(hum999$Horizon, c("L", "F", "H", "Of", "Om"))
  })
})

test_that("vpro_import_access streams real Access .accdb into VP08 SQLite with quarantine table", {
  accdb_orig <- "/home/bruno/Work/VPRO_ACCESS_1/VPro64/Manning_TEM_Vpro19.accdb"
  skip_if_not(file.exists(accdb_orig))
  skip_if_not_installed("mdbr")

  tmp_accdb <- tempfile("manning-", fileext = ".accdb")
  tmp_db <- tempfile("manning-", fileext = ".db")
  on.exit(unlink(c(tmp_accdb, tmp_db, paste0(tmp_db, "-wal"), paste0(tmp_db, "-shm"))), add = TRUE)
  file.copy(accdb_orig, tmp_accdb)
  sha_before <- vpro:::vpro_sha256_file(tmp_accdb)

  res <- vpro_import_access(tmp_accdb, dest_db = tmp_db)
  sha_after <- vpro:::vpro_sha256_file(tmp_accdb)
  expect_equal(sha_before, sha_after)
  expect_gt(res$plot_count, 0L)
  expect_true(vpro_project_inspect(tmp_db, res$target_project)$compatible)

  ws <- vpro_connect(tmp_db)
  env <- vpro_env(ws, scope = "project")
  expect_equal(nrow(env), res$plot_count)
})
