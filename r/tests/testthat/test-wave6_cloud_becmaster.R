test_that("ignore files guard secrets and DESCRIPTION keeps RPostgres in Suggests only", {
  root <- normalizePath("../..", winslash = "/", mustWork = FALSE)
  if (file.exists(file.path(root, ".gitignore"))) {
    gi <- readLines(file.path(root, ".gitignore"), warn = FALSE)
    expect_true(any(trimws(gi) == ".env"))
    expect_true(any(trimws(gi) == ".env.*"))
    expect_true(any(trimws(gi) == "!.env.example"))
    expect_true(any(trimws(gi) == ".Renviron"))
  }
  if (file.exists(file.path(root, ".Rbuildignore"))) {
    rbi <- readLines(file.path(root, ".Rbuildignore"), warn = FALSE)
    expect_true(any(grepl("\\^\\\\\\.env", rbi)))
    expect_true(any(grepl("\\^\\\\\\.Renviron\\$", rbi)))
  }

  desc_path <- system.file("DESCRIPTION", package = "vpro")
  if (!nzchar(desc_path) && file.exists(file.path(root, "DESCRIPTION"))) {
    desc_path <- file.path(root, "DESCRIPTION")
  }
  skip_if_not(nzchar(desc_path) && file.exists(desc_path))
  dcf <- read.dcf(desc_path)
  imports_raw <- paste(dcf[, intersect(c("Depends", "Imports"), colnames(dcf))], collapse = ",")
  suggests_raw <- paste(dcf[, intersect("Suggests", colnames(dcf))], collapse = ",")
  expect_false(grepl("\\bRPostgres\\b", imports_raw))
  expect_true(grepl("\\bRPostgres\\b", suggests_raw))
})

test_that("credential resolution follows args > env > becmaster.env and strictly redacts secrets", {
  pg_env_vars <- c(
    VPRO_PG_HOST = "",
    VPRO_PG_PORT = "",
    VPRO_PG_DBNAME = "",
    VPRO_PG_SSLMODE = "",
    VPRO_PG_USER = "",
    VPRO_PG_PASSWORD = "",
    VPRO_PG_URL = "",
    VPRO_PG_ADMIN_USER = "",
    VPRO_PG_ADMIN_PASSWORD = "",
    VPRO_PG_ADMIN_URL = ""
  )

  empty_cfg <- tempfile("vpro-empty-cfg-")
  dir.create(empty_cfg)
  on.exit(unlink(empty_cfg, recursive = TRUE), add = TRUE)

  withr::with_envvar(pg_env_vars, {
    expect_false(vpro_has_pg_credentials("contributor", config_dir = empty_cfg))
    expect_false(vpro_has_pg_credentials("custodian", config_dir = empty_cfg))

    # Write becmaster.env with export prefix, single/double quotes, and inline comments
    dotenv_lines <- c(
      "# Provincial BECMaster test config (synthetic test values)",
      "export VPRO_PG_HOST=pg-file.internal.gov.bc.ca # inline comment",
      "VPRO_PG_PORT=5433",
      "VPRO_PG_DBNAME=becmaster_file",
      "VPRO_PG_SSLMODE=verify-ca",
      "VPRO_PG_USER=contrib_from_file",
      'VPRO_PG_PASSWORD="File$ecret#User99!"',
      "VPRO_PG_ADMIN_USER='custodian_from_file'",
      "VPRO_PG_ADMIN_PASSWORD='File$ecret#Admin88!'"
    )
    writeLines(dotenv_lines, file.path(empty_cfg, "becmaster.env"))

    expect_true(vpro_has_pg_credentials("contributor", config_dir = empty_cfg))
    expect_true(vpro_has_pg_credentials("custodian", config_dir = empty_cfg))

    c_file <- vpro:::vpro_resolve_pg_credentials("contributor", config_dir = empty_cfg)
    expect_equal(c_file$source, "becmaster.env")
    expect_equal(c_file$host, "pg-file.internal.gov.bc.ca")
    expect_equal(c_file$port, 5433L)
    expect_equal(c_file$dbname, "becmaster_file")
    expect_equal(c_file$sslmode, "verify-ca")
    expect_equal(c_file$user, "contrib_from_file")
    expect_equal(c_file$password, "File$ecret#User99!")

    a_file <- vpro:::vpro_resolve_pg_credentials("custodian", config_dir = empty_cfg)
    expect_equal(a_file$user, "custodian_from_file")
    expect_equal(a_file$password, "File$ecret#Admin88!")

    # Process env vars override becmaster.env
    withr::with_envvar(
      c(
        VPRO_PG_HOST = "pg-env.internal.gov.bc.ca",
        VPRO_PG_USER = "contrib_from_env",
        VPRO_PG_PASSWORD = "Env$ecretPassword77"
      ),
      {
        c_env <- vpro:::vpro_resolve_pg_credentials("contributor", config_dir = empty_cfg)
        expect_equal(c_env$source, "env")
        expect_equal(c_env$host, "pg-env.internal.gov.bc.ca")
        expect_equal(c_env$user, "contrib_from_env")
        expect_equal(c_env$password, "Env$ecretPassword77")
        # Port falls back to becmaster.env when VPRO_PG_PORT is empty
        expect_equal(c_env$port, 5433L)

        # Explicit function args override both process env and becmaster.env
        c_args <- vpro:::vpro_resolve_pg_credentials(
          "contributor",
          host = "pg-args.internal.gov.bc.ca",
          port = 6432L,
          user = "contrib_from_args",
          password = "Arg$ecretPassword66",
          config_dir = empty_cfg
        )
        expect_equal(c_args$source, "args")
        expect_equal(c_args$host, "pg-args.internal.gov.bc.ca")
        expect_equal(c_args$port, 6432L)
        expect_equal(c_args$user, "contrib_from_args")
        expect_equal(c_args$password, "Arg$ecretPassword66")
      }
    )

    # URL parsing with percent-encoded password and sslmode query parameter
    parsed_u <- vpro:::vpro_parse_pg_url(
      "postgresql://idir_user:My%40Pass%23123@pg-uri.gov.bc.ca:5434/bec_uri?sslmode=verify-full"
    )
    expect_equal(parsed_u$host, "pg-uri.gov.bc.ca")
    expect_equal(parsed_u$port, 5434L)
    expect_equal(parsed_u$dbname, "bec_uri")
    expect_equal(parsed_u$user, "idir_user")
    expect_equal(parsed_u$password, "My@Pass#123")
    expect_equal(parsed_u$sslmode, "verify-full")

    # Secret redaction scrubs DSNs, password=kv pairs, raw secrets, and URL-encoded secrets
    raw_diag <- paste(
      "FATAL: auth failed for postgres://idir_user:My%40Pass%23123@pg-uri.gov.bc.ca:5434/bec_uri",
      "password='File$ecret#User99!' raw=My@Pass#123"
    )
    scrubbed <- vpro:::vpro_redact_pg_secrets(
      raw_diag,
      secrets = c("My@Pass#123", "File$ecret#User99!")
    )
    expect_false(grepl("My@Pass#123", scrubbed, fixed = TRUE))
    expect_false(grepl("My%40Pass%23123", scrubbed, fixed = TRUE))
    expect_false(grepl("File$ecret#User99!", scrubbed, fixed = TRUE))

    # Failed connection attempt never leaks password in cli_abort error condition
    if (requireNamespace("RPostgres", quietly = TRUE)) {
      err_cond <- tryCatch(
        vpro_master_connect(
          role = "contributor",
          host = "127.0.0.1",
          port = 1L,
          dbname = "becmaster",
          user = "nobody",
          password = "UltraSecretNeverLeak42!",
          sslmode = "disable",
          config_dir = empty_cfg
        ),
        error = function(e) e
      )
      expect_s3_class(err_cond, "error")
      full_err_txt <- paste(
        c(conditionMessage(err_cond), format(err_cond)),
        collapse = "\n"
      )
      expect_false(grepl("UltraSecretNeverLeak42!", full_err_txt, fixed = TRUE))
    }
  })
})

test_that("compact .rds snapshots preserve '00337', Access booleans, float32 covers, and analytical parity", {
  tmp_dir <- tempfile("vpro-rds-roundtrip-")
  dir.create(tmp_dir)
  on.exit(unlink(tmp_dir, recursive = TRUE), add = TRUE)

  src_db <- file.path(tmp_dir, "SampleCopy.db")
  file.copy(vpro:::vpro_bundled_db("Sample.db"), src_db)

  # Sample.db already contains '00337'; also inject '00338' with Access -1/0 booleans, float32 boundary cover, and LMH25 horizons
  dbc <- DBI::dbConnect(RSQLite::SQLite(), src_db)
  DBI::dbExecute(
    dbc,
    paste(
      'INSERT INTO "Sample_Env" ("PlotNumber", "ProjectID", "Zone", "SubZone", "SiteSeries",',
      '"MoistureRegime", "NutrientRegime", "Elevation", "Latitude", "Longitude",',
      '"SpeciesListComplete", "Flag", "SV_FloodPlain")',
      "VALUES ('00338', 'RDS_QA', 'SBS', 'dk', '01', '4', 'C', 320, 54.5, -126.2, -1, 0, NULL)"
    )
  )
  DBI::dbExecute(
    dbc,
    paste(
      'INSERT INTO "Sample_Admin" ("Plot", "PlotType", "SitePlotQuality", "VegPlotQuality",',
      '"SoilPlotQuality", "UpdatedFromCards", "BECSiteUnit", "UserSiteUnit")',
      "VALUES ('00338', 'FS882', 'Good', 'Good', 'Good', -1, 'SBSdk/01', 'SBSdk/01')"
    )
  )
  DBI::dbExecute(
    dbc,
    paste(
      'INSERT INTO "Sample_Veg" ("PlotNumber", "Species", "Layer", "Cover1", "Cover4", "Cover6", "Flag", "ID")',
      "VALUES ('00338', 'PINUCON', '1', 99.999996, 12.5, NULL, -1, 999001)"
    )
  )
  DBI::dbExecute(
    dbc,
    'INSERT INTO "Sample_Humus" ("PlotNumber", "Horizon", "UpperDepth", "LowerDepth", "vonPost", "Flag", "ID") VALUES (\'00338\', \'Fm\', 6.0, 0.0, NULL, 0, 999002)'
  )
  DBI::dbExecute(
    dbc,
    'INSERT INTO "Sample_Mineral" ("PlotNumber", "Horizon", "UpperDepth", "LowerDepth", "Texture", "PercentCoarseFragsTotal", "Flag", "ID") VALUES (\'00338\', \'Bm1\', 0.0, 25.0, \'SL\', 20, -1, 999003)'
  )
  DBI::dbExecute(
    dbc,
    'INSERT INTO "Sample_SU" ("PlotNumber", "SiteUnit") VALUES (\'00338\', \'SBSdk/01\')'
  )
  DBI::dbDisconnect(dbc)

  ws_sql <- vpro_connect(src_db, su = "Sample_SU", lump = "Sample_Lump", data_dir = tmp_dir, config_dir = tmp_dir)
  rds_file <- file.path(tmp_dir, "BECMaster_TestSnap.rds")
  written <- vpro_export_rds(
    ws_sql,
    path = rds_file,
    snapshot_tag = "BECMaster_TestSnap_2026",
    provenance = list(bec_version = "BECdb_v13_2026", taxonomy_version = "BCPlantTaxa_v19_2025"),
    compress = "xz"
  )
  expect_true(file.exists(written$path))
  expect_equal(nchar(written$sha256), 64L)
  expect_equal(written$plot_count, 53L)

  # Read back via both vpro_import_rds() and vpro_connect("...rds")
  ws_rds <- vpro_import_rds(rds_file)
  ws_rds_via_connect <- vpro_connect(rds_file)
  expect_s3_class(ws_rds, "vpro_rds_project")
  expect_s3_class(ws_rds, "vpro_workspace")
  expect_s3_class(ws_rds_via_connect, "vpro_rds_project")
  expect_s3_class(tibble::as_tibble(ws_rds), "tbl_df")
  expect_no_error(capture.output(print(ws_rds), type = "message"))

  env_sql <- vpro_env(ws_sql, scope = "project")
  env_rds <- vpro_env(ws_rds, scope = "project")
  expect_equal(env_rds$PlotNumber, env_sql$PlotNumber)
  expect_true(all(c("00337", "00338") %in% env_rds$PlotNumber))

  row_00338 <- env_rds[env_rds$PlotNumber == "00338", , drop = FALSE]
  expect_true(isTRUE(row_00338$SpeciesListComplete[[1L]]))
  expect_false(isTRUE(row_00338$Flag[[1L]]))
  expect_false(is.na(row_00338$Flag[[1L]]))
  expect_true(is.na(row_00338$SV_FloodPlain[[1L]]))
  expect_true(isTRUE(row_00338$UpdatedFromCards[[1L]]))

  veg_raw <- vpro_veg(ws_rds, scope = "project", strata = "raw", lump = FALSE)
  cov_00338_l1 <- veg_raw$Cover[veg_raw$PlotNumber == "00338" & veg_raw$Layer == "1"]
  expect_length(cov_00338_l1, 1L)
  expect_lt(cov_00338_l1, 100)
  expect_equal(cov_00338_l1, vpro_narrow_float32(99.999996))

  # Exact community matrix and BEC diagnostics parity without external DB
  mat_sql <- vpro_matrix(ws_sql, transform = "sqrt")
  mat_rds <- vpro_matrix(ws_rds, transform = "sqrt")
  expect_equal(dim(mat_rds), dim(mat_sql))
  expect_equal(rownames(mat_rds), rownames(mat_sql))
  expect_equal(colnames(mat_rds), colnames(mat_sql))
  expect_equal(as.numeric(mat_rds), as.numeric(mat_sql), tolerance = 1e-6)

  diag_sql <- vpro_diagnostics(ws_sql)
  diag_rds <- vpro_diagnostics(ws_rds)
  expect_equal(diag_rds$units, diag_sql$units)
  expect_equal(nrow(diag_rds$matrix), nrow(diag_sql$matrix))

  # Verify VPro Desktop ExportProjectRDS `veg_long` bundle format also loads cleanly
  wails_rds <- file.path(tmp_dir, "WailsVegLong.rds")
  saveRDS(
    list(
      env = data.frame(PlotNumber = c("00337", "00338"), Zone = c("CWH", "CWH"), SubZone = c("vm1", "vm1"), stringsAsFactors = FALSE),
      admin = data.frame(Plot = c("00337", "00338"), BECSiteUnit = c("CWHvm1/01", "CWHvm1/01"), stringsAsFactors = FALSE),
      veg_long = data.frame(
        PlotNumber = c("00337", "00338"),
        SiteUnit = c("CWHvm1/01", "CWHvm1/01"),
        ID = c(1L, 2L),
        Species = c("TSUGHET", "THUJPLI"),
        ScientificName = c("Tsuga heterophylla", "Thuja plicata"),
        Lifeform = c(1L, 1L),
        Layer = c("1", "4"),
        Cover = c(45.0, 20.0),
        Height = c(28.0, 4.5),
        Collected = c("", ""),
        stringsAsFactors = FALSE
      ),
      humus = data.frame(PlotNumber = character(), Horizon = character(), UpperDepth = numeric(), LowerDepth = numeric(), ID = integer(), stringsAsFactors = FALSE),
      mineral = data.frame(PlotNumber = character(), Horizon = character(), UpperDepth = numeric(), LowerDepth = numeric(), ID = integer(), stringsAsFactors = FALSE),
      su = data.frame(PlotNumber = c("00337", "00338"), SiteUnit = c("CWHvm1/01", "CWHvm1/01"), stringsAsFactors = FALSE),
      metadata = data.frame(ProjectID = "WAILS_EXP", ProjectTitle = "Wails Export", ID = 1L, stringsAsFactors = FALSE)
    ),
    wails_rds
  )
  ws_wails <- vpro_import_rds(wails_rds)
  expect_equal(vpro_env(ws_wails)$PlotNumber, c("00337", "00338"))
  expect_equal(nrow(vpro_veg(ws_wails, strata = "total")), 2L)
})

test_that("offline 3-way diff algebra and SHA-256 audit hash chain detect conflicts, protected fields, and tampering", {
  mk_empty_tables <- function() {
    out <- list()
    for (sfx in c("Env", "Admin", "Veg", "Humus", "Mineral", "Other")) {
      spec <- vpro:::vpro_pg_vp08_specs(sfx)
      cols <- lapply(seq_len(nrow(spec)), function(i) {
        tp <- spec$pg_type[[i]]
        if (tp == "TEXT") character() else if (tp == "DOUBLE PRECISION") numeric() else integer()
      })
      names(cols) <- spec$name
      out[[sfx]] <- as.data.frame(cols, stringsAsFactors = FALSE)
    }
    out
  }

  add_plot_rows <- function(tbls, plot_num, site_notes, bec_unit, cover1) {
    e_row <- tbls$Env[1L, , drop = FALSE]
    e_row[1L, ] <- NA
    e_row$PlotNumber <- plot_num
    e_row$Zone <- "CWH"
    e_row$SiteNotes <- site_notes
    e_row$Flag <- 0L
    tbls$Env <- rbind(tbls$Env, e_row)

    a_row <- tbls$Admin[1L, , drop = FALSE]
    a_row[1L, ] <- NA
    a_row$Plot <- plot_num
    a_row$BECSiteUnit <- bec_unit
    a_row$UpdatedFromCards <- 0L
    tbls$Admin <- rbind(tbls$Admin, a_row)

    v_row <- tbls$Veg[1L, , drop = FALSE]
    v_row[1L, ] <- NA
    v_row$PlotNumber <- plot_num
    v_row$Species <- "TSUGHET"
    v_row$Layer <- "1"
    v_row$Cover1 <- cover1
    v_row$Flag <- 0L
    v_row$ID <- nrow(tbls$Veg) + 1L
    tbls$Veg <- rbind(tbls$Veg, v_row)
    tbls
  }

  # Base has plots: 00101 (Identical), 00102 (FastForward), 00103 (Conflict), 00104 (CustodianProtected BECSiteUnit)
  base_t <- mk_empty_tables()
  base_t <- add_plot_rows(base_t, "00101", "unchanged", "CWHvm1/01", 30.0)
  base_t <- add_plot_rows(base_t, "00102", "base note", "CWHvm1/01", 30.0)
  base_t <- add_plot_rows(base_t, "00103", "base note", "CWHvm1/01", 30.0)
  base_t <- add_plot_rows(base_t, "00104", "unchanged", "CWHvm1/01", 30.0)

  # Target (BECMaster) modifies 00103 + adds TargetOnly 00105
  tgt_t <- base_t
  tgt_t$Env$SiteNotes[tgt_t$Env$PlotNumber == "00103"] <- "custodian master edit"
  tgt_t <- add_plot_rows(tgt_t, "00105", "master only", "CWHvm1/05", 15.0)

  # Source (Staging) fast-forwards 00102, conflicts on 00103, edits protected BECSiteUnit on 00104, and adds 00337
  src_t <- base_t
  src_t$Env$SiteNotes[src_t$Env$PlotNumber == "00102"] <- "field crew update"
  src_t$Env$SiteNotes[src_t$Env$PlotNumber == "00103"] <- "competing crew edit"
  src_t$Admin$BECSiteUnit[src_t$Admin$Plot == "00104"] <- "CWHvm1/06"
  src_t <- add_plot_rows(src_t, "00337", "brand new plot", "CWHvm1/01", 45.0)

  sub_uuid <- "11111111-2222-4333-8444-555555555555"
  prev <- vpro:::vpro_compute_3way_diff(
    submission_id = sub_uuid,
    source_project = "Crew_2026",
    src_tables = src_t,
    tgt_tables = tgt_t,
    base_tables = base_t
  )
  expect_s3_class(prev, "vpro_merge_preview")
  expect_equal(nchar(prev$preview_digest), 64L)
  expect_equal(prev$added_count, 1L)
  expect_equal(prev$identical_count, 1L)
  expect_equal(prev$fast_forward_count, 1L)
  expect_equal(prev$conflict_count, 2L) # 00103 real conflict + 00104 custodian-protected BECSiteUnit
  expect_equal(prev$target_only_count, 1L)

  cats <- stats::setNames(prev$plots$category, prev$plots$PlotNumber)
  expect_equal(unname(cats[["00337"]]), "Added")
  expect_equal(unname(cats[["00101"]]), "Identical")
  expect_equal(unname(cats[["00102"]]), "FastForward")
  expect_equal(unname(cats[["00103"]]), "Conflict")
  expect_equal(unname(cats[["00104"]]), "Conflict")
  expect_equal(unname(cats[["00105"]]), "TargetOnly")

  # Custodian-protected BECSiteUnit must default to keep_target even though target == base
  prot <- prev$custodian_protected_diffs
  expect_equal(nrow(prot), 1L)
  expect_equal(prot$PlotNumber[[1L]], "00104")
  expect_equal(prot$field[[1L]], "BECSiteUnit")
  expect_equal(prot$default_resolution[[1L]], "keep_target")

  expect_s3_class(tibble::as_tibble(prev), "tbl_df")
  expect_no_error(capture.output(print(prev), type = "message"))

  # Audit SHA-256 chain determinism & tamper sensitivity
  r1 <- list("BECMaster", "Will MacKenzie", "00337", "_Env", "Zone", "2026-11-14 08:00:00", "IDF", "CWH", 0L, 0L, NA_integer_)
  r2 <- list("BECMaster", "Will MacKenzie", "00337", "_Veg", "Cover1", "2026-11-14 08:00:01", NA_character_, "45", 0L, 0L, 42L)
  h1 <- vpro:::vpro_compute_audit_row_hash(vpro:::.vpro_genesis_audit_hash, sub_uuid, r1)
  h1_dup <- vpro:::vpro_compute_audit_row_hash(vpro:::.vpro_genesis_audit_hash, sub_uuid, r1)
  expect_equal(h1, h1_dup)
  expect_equal(nchar(h1), 64L)
  h2 <- vpro:::vpro_compute_audit_row_hash(h1, sub_uuid, r2)
  r1_tampered <- r1
  r1_tampered[[8L]] <- "ICH"
  h1_bad <- vpro:::vpro_compute_audit_row_hash(vpro:::.vpro_genesis_audit_hash, sub_uuid, r1_tampered)
  h2_bad <- vpro:::vpro_compute_audit_row_hash(h1_bad, sub_uuid, r2)
  expect_false(identical(h1, h1_bad))
  expect_false(identical(h2, h2_bad))
})

test_that("live PostgreSQL Contributor read/pull/sync, RBAC write denial, Custodian 3-way merge, audit chain, and snapshots succeed with zero drift", {
  # Opt-in gate (ENG-R-001): this test writes to the configured BECMaster as Custodian, so it never
  # runs just because credentials exist in becmaster.env. Same variables as the Go live tests.
  skip_if_not(
    tolower(Sys.getenv("VPRO_RUN_LIVE_PG_TESTS")) %in% c("1", "true"),
    "live PostgreSQL test skipped: set VPRO_RUN_LIVE_PG_TESTS=1 to run against the configured server"
  )
  skip_if_not_installed("RPostgres")
  skip_if_not(
    vpro_has_pg_credentials("contributor") && vpro_has_pg_credentials("custodian"),
    "Live PostgreSQL Contributor + Custodian credentials not configured"
  )
  skip_if_not(
    nzchar(Sys.getenv("VPRO_LIVE_PG_DESTRUCTIVE_DB")) &&
      identical(Sys.getenv("VPRO_LIVE_PG_DESTRUCTIVE_DB"), vpro_resolve_pg_credentials("custodian")$dbname),
    "destructive live test skipped: set VPRO_LIVE_PG_DESTRUCTIVE_DB to the configured database name to confirm it is disposable"
  )

  admin_con <- vpro_master_connect("custodian")
  on.exit(vpro_master_disconnect(admin_con), add = TRUE)
  contrib_con <- vpro_master_connect("contributor")
  on.exit(vpro_master_disconnect(contrib_con), add = TRUE)

  # Verify print() emits zero passwords or DSNs
  p_out <- paste(
    c(
      capture.output(print(contrib_con)),
      capture.output(print(contrib_con), type = "message")
    ),
    collapse = "\n"
  )
  expect_false(grepl("password", p_out, ignore.case = TRUE))
  expect_false(grepl("postgres://", p_out, ignore.case = TRUE))

  st_contrib <- vpro_master_status(contrib_con)
  st_admin <- vpro_master_status(admin_con)
  expect_true(st_contrib$schemas_bootstrapped)
  expect_true(st_contrib$can_read_master)
  expect_true(st_contrib$can_submit_staging)
  expect_false(st_contrib$can_merge_master)
  expect_true(st_admin$can_merge_master)
  expect_s3_class(tibble::as_tibble(st_contrib), "tbl_df")

  # Record strict baseline watermarks before any test activity
  base_counts <- DBI::dbGetQuery(
    admin_con$conn,
    paste(
      "SELECT",
      "  (SELECT COUNT(*)::int FROM becmaster.env) AS plot_n,",
      "  (SELECT COUNT(*)::bigint FROM becmaster.veg) AS veg_n,",
      "  COALESCE((SELECT MAX(audit_seq) FROM becmaster.audit), 0) AS max_audit_seq,",
      "  COALESCE((SELECT MAX(id) FROM becmaster.download_log), 0) AS max_dl_id"
    )
  )
  baseline_plots <- as.integer(base_counts$plot_n[[1L]])
  baseline_veg <- base_counts$veg_n[[1L]]
  baseline_max_audit <- base_counts$max_audit_seq[[1L]]
  baseline_max_dl <- base_counts$max_dl_id[[1L]]

  # Select a clean compliant BECMaster plot ('0112931' in SBSdk, or fallback search with valid bounds) and an unused leading-zero test PlotNumber
  cand_df <- DBI::dbGetQuery(
    admin_con$conn,
    paste(
      'SELECT e."PlotNumber", e."Zone", e."SubZone", e."SiteNotes", a."BECSiteUnit"',
      'FROM becmaster.env e',
      'JOIN becmaster.admin a ON a."Plot" = e."PlotNumber"',
      'WHERE e."PlotNumber" = \'0112931\'',
      '  AND (a."StrataCoverTotal" IS NULL OR (a."StrataCoverTotal" >= 0 AND a."StrataCoverTotal" < 100))',
      'LIMIT 1'
    )
  )
  if (nrow(cand_df) == 0L) {
    cand_df <- DBI::dbGetQuery(
      admin_con$conn,
      paste(
        'SELECT e."PlotNumber", e."Zone", e."SubZone", e."SiteNotes", a."BECSiteUnit"',
        'FROM becmaster.env e JOIN becmaster.admin a ON a."Plot" = e."PlotNumber"',
        'WHERE length(e."PlotNumber") <= 7',
        '  AND (a."StrataCoverTotal" IS NULL OR (a."StrataCoverTotal" >= 0 AND a."StrataCoverTotal" < 100))',
        'ORDER BY e."PlotNumber" LIMIT 1'
      )
    )
  }
  expect_equal(nrow(cand_df), 1L)
  target_plot <- as.character(cand_df$PlotNumber[[1L]])
  target_zone <- as.character(cand_df$Zone[[1L]])
  target_subzone <- as.character(cand_df$SubZone[[1L]])
  orig_site_notes <- cand_df$SiteNotes[[1L]]
  orig_bec_unit <- cand_df$BECSiteUnit[[1L]]

  leading_zero_plot <- NULL
  for (zp in c("00338", "00339", "00038", "00938", "00088")) {
    ex <- DBI::dbGetQuery(
      admin_con$conn,
      'SELECT EXISTS (SELECT 1 FROM becmaster.env WHERE "PlotNumber" = $1) AS ex',
      params = list(zp)
    )$ex[[1L]]
    if (!isTRUE(ex)) {
      leading_zero_plot <- zp
      break
    }
  }
  expect_false(is.null(leading_zero_plot))

  created_sub_ids <- character()
  created_merge_tx_ids <- character()
  allocated_child_ids <- integer()
  test_proj_id <- "RSDK_QA_2026_PROJ"
  test_snap_tag <- "RSDK_QA_Wave6_Snap"
  red_snap_tag <- "RSDK_QA_Wave6_RedSnap"

  # Unconditional Custodian cleanup restoring exact production BECMaster state
  on.exit({
    tryCatch({
      clean_con <- if (DBI::dbIsValid(admin_con$conn)) admin_con else vpro_master_connect("custodian")
      if (!identical(clean_con, admin_con)) {
        on.exit(vpro_master_disconnect(clean_con), add = TRUE)
      }
      if (!is.null(leading_zero_plot)) {
        DBI::dbExecute(clean_con$conn, 'DELETE FROM becmaster.env WHERE "PlotNumber" = $1', params = list(leading_zero_plot))
      }
      DBI::dbExecute(
        clean_con$conn,
        'UPDATE becmaster.env SET "SiteNotes" = $1 WHERE "PlotNumber" = $2',
        params = list(if (is.na(orig_site_notes)) NA_character_ else as.character(orig_site_notes), target_plot)
      )
      DBI::dbExecute(
        clean_con$conn,
        'UPDATE becmaster.admin SET "BECSiteUnit" = $1 WHERE "Plot" = $2',
        params = list(if (is.na(orig_bec_unit)) NA_character_ else as.character(orig_bec_unit), target_plot)
      )
      DBI::dbExecute(
        clean_con$conn,
        'DELETE FROM becmaster.veg WHERE "PlotNumber" = $1 AND "Species" = \'RQASPP1\'',
        params = list(target_plot)
      )
      DBI::dbExecute(
        clean_con$conn,
        'DELETE FROM becmaster.metadata WHERE "ProjectID" = $1',
        params = list(test_proj_id)
      )
      if (length(allocated_child_ids) > 0L) {
        arr_lit <- paste0("{", paste(as.integer(allocated_child_ids), collapse = ","), "}")
        DBI::dbExecute(
          clean_con$conn,
          "DELETE FROM becmaster.child_identity WHERE id = ANY($1::bigint[])",
          params = list(arr_lit)
        )
      }
      for (mtx in unique(created_merge_tx_ids)) {
        DBI::dbExecute(
          clean_con$conn,
          "DELETE FROM becmaster.audit WHERE merge_tx_id = $1::uuid",
          params = list(mtx)
        )
        DBI::dbExecute(
          clean_con$conn,
          "DELETE FROM becmaster.merge_ledger WHERE merge_tx_id = $1::uuid",
          params = list(mtx)
        )
      }
      for (sid in unique(created_sub_ids)) {
        DBI::dbExecute(
          clean_con$conn,
          "DELETE FROM staging.submissions WHERE submission_id = $1::uuid",
          params = list(sid)
        )
      }
      DBI::dbExecute(
        clean_con$conn,
        "DELETE FROM becmaster.snapshots WHERE snapshot_tag = ANY($1::text[])",
        params = list(vpro:::vpro_pg_text_array(c(test_snap_tag, red_snap_tag)))
      )
      DBI::dbExecute(
        clean_con$conn,
        "DELETE FROM becmaster.download_log WHERE id > $1 AND actor = ANY($2::text[])",
        params = list(baseline_max_dl, vpro:::vpro_pg_text_array(c(contrib_con$user, admin_con$user)))
      )
    }, error = function(e) {
      warning("PostgreSQL test cleanup warning: ", conditionMessage(e), call. = FALSE)
    })
  }, add = TRUE)

  # 1. Verify PostgreSQL engine-level RBAC write denial on Contributor connection
  expect_error(
    vpro:::vpro_pg_execute(
      contrib_con,
      'UPDATE becmaster.env SET "SiteNotes" = \'unauthorized\' WHERE "PlotNumber" = $1',
      params = list(target_plot)
    )
  )
  expect_error(
    vpro:::vpro_pg_execute(
      contrib_con,
      'DELETE FROM becmaster.env WHERE "PlotNumber" = $1',
      params = list(target_plot)
    )
  )
  expect_error(
    vpro_staging_merge(contrib_con, "11111111-2222-4333-8444-555555555555"),
    "custodian"
  )

  # 2. Direct Cloud Readers, Standards Sync, and Seamless Diagnostics Integration
  env_sub <- vpro_master_env(contrib_con, zones = target_zone, plots = target_plot)
  expect_equal(nrow(env_sub), 1L)
  expect_type(env_sub$PlotNumber, "character")
  expect_type(env_sub$Flag, "logical")

  veg_sub <- vpro_master_veg(contrib_con, plots = target_plot, strata = "total")
  expect_s3_class(veg_sub, "tbl_df")
  soil_sub <- vpro_master_soil(contrib_con, plots = target_plot)
  expect_s3_class(soil_sub, "vpro_soil")

  aud_check <- attr(vpro_master_audit(contrib_con, limit = 100L, verify_chain = TRUE), "chain_verification")
  expect_true(aud_check$valid)

  tmp_work <- tempfile("vpro-live-pg-")
  dir.create(tmp_work)
  on.exit(unlink(tmp_work, recursive = TRUE), add = TRUE)

  sync_dir <- file.path(tmp_work, "std_data")
  sync_res1 <- vpro_master_standards_sync(contrib_con, data_dir = sync_dir)
  sync_res2 <- vpro_master_standards_sync(contrib_con, data_dir = sync_dir)
  expect_true(file.exists(sync_res1$vlists_path))
  expect_true(sync_res2$already_current)
  expect_false(sync_res2$updated)

  # 3. Contributor subset pull -> local VP08 SQLite .db + download_log entry
  base_db_path <- file.path(tmp_work, "BaseCWH.db")
  pulled <- vpro_master_pull(
    contrib_con,
    dest_db = base_db_path,
    project = "BaseCWH",
    zones = target_zone,
    plots = target_plot
  )
  expect_equal(pulled$plot_count, 1L)
  expect_gt(pulled$download_log_id, 0L)
  expect_true(vpro_project_inspect(pulled$dest_path, "BaseCWH")$compatible)

  # Prepare Contributor working copy with custom VUser.db containing provisional species 'RQASPP1'
  work_dir <- file.path(tmp_work, "work")
  dir.create(work_dir)
  work_db <- file.path(work_dir, "CrewCWH.db")
  file.copy(base_db_path, work_db)
  file.copy(vpro:::vpro_bundled_db("VUser.db"), file.path(work_dir, "VUser.db"))

  dbc_u <- DBI::dbConnect(RSQLite::SQLite(), file.path(work_dir, "VUser.db"))
  DBI::dbExecute(
    dbc_u,
    "INSERT OR REPLACE INTO \"USysUserSpp\" (\"Code\", \"ScientificName\", \"LifeForm\", \"EnglishName\", \"Codetype\") VALUES ('RQASPP1', 'Carex rsdkiana', 6, 'R SDK test sedge', 'U')"
  )
  DBI::dbDisconnect(dbc_u)

  # Rename tables inside work_db from BaseCWH_* -> CrewCWH_* so source project has distinct name
  dbc_w <- DBI::dbConnect(RSQLite::SQLite(), work_db)
  for (sfx in c("Env", "Admin", "Veg", "Humus", "Mineral", "Other", "Audit", "Metadata", "SU")) {
    old_t <- paste0("BaseCWH_", sfx)
    new_t <- paste0("CrewCWH_", sfx)
    if (DBI::dbExistsTable(dbc_w, old_t)) {
      DBI::dbExecute(dbc_w, sprintf('ALTER TABLE "%s" RENAME TO "%s"', old_t, new_t))
    }
  }
  DBI::dbExecute(dbc_w, 'UPDATE "_table_metadata" SET "table_name" = REPLACE("table_name", \'BaseCWH_\', \'CrewCWH_\')')

  # Verify pre-flight compliance gate blocks float32 >= 100 cover (99.999999 -> 100.0 in float32)
  DBI::dbExecute(
    dbc_w,
    sprintf(
      'INSERT INTO "CrewCWH_Veg" ("PlotNumber", "Species", "Layer", "Cover1", "Flag", "ID") VALUES (\'%s\', \'RQASPP1\', \'6\', 99.999999, 0, 888001)',
      target_plot
    )
  )
  DBI::dbDisconnect(dbc_w)

  ws_crew <- vpro_connect(work_db, data_dir = work_dir, config_dir = tmp_work)
  expect_error(
    vpro_staging_submit(contrib_con, ws_crew, submitter = "Field Crew QA")
  )

  # Fix cover to valid 14.5%, update SiteNotes (FastForward), attempt BECSiteUnit edit (CustodianProtected),
  # and add leading-zero plot (`leading_zero_plot`) + new ProjectID metadata
  dbc_w <- DBI::dbConnect(RSQLite::SQLite(), work_db)
  DBI::dbExecute(dbc_w, 'UPDATE "CrewCWH_Veg" SET "Cover1" = NULL, "Cover6" = 14.5 WHERE "ID" = 888001')
  DBI::dbExecute(
    dbc_w,
    'UPDATE "CrewCWH_Env" SET "SiteNotes" = \'R SDK FastForward QA Note\' WHERE "PlotNumber" = ?',
    params = list(target_plot)
  )
  DBI::dbExecute(
    dbc_w,
    'UPDATE "CrewCWH_Admin" SET "BECSiteUnit" = \'CWHvm1/99\' WHERE "Plot" = ?',
    params = list(target_plot)
  )
  DBI::dbExecute(
    dbc_w,
    sprintf(
      'INSERT INTO "CrewCWH_Env" ("PlotNumber", "ProjectID", "Zone", "SubZone", "SiteSeries", "MoistureRegime", "NutrientRegime", "Elevation", "Latitude", "Longitude", "SpeciesListComplete", "Flag") VALUES (\'%s\', \'%s\', \'%s\', \'%s\', \'01\', \'4\', \'C\', 710, 54.65, -127.05, -1, 0)',
      leading_zero_plot, test_proj_id, target_zone, target_subzone
    )
  )
  DBI::dbExecute(
    dbc_w,
    sprintf(
      'INSERT INTO "CrewCWH_Admin" ("Plot", "PlotType", "SitePlotQuality", "VegPlotQuality", "SoilPlotQuality", "UpdatedFromCards", "BECSiteUnit", "UserSiteUnit") VALUES (\'%s\', \'FS882\', \'Good\', \'Good\', \'Good\', -1, \'SBSdk/01\', \'SBSdk/01\')',
      leading_zero_plot
    )
  )
  DBI::dbExecute(
    dbc_w,
    sprintf(
      'INSERT INTO "CrewCWH_Veg" ("PlotNumber", "Species", "Layer", "Cover1", "Flag", "ID") VALUES (\'%s\', \'PINUCON\', \'1\', 35.0, 0, 888002)',
      leading_zero_plot
    )
  )
  DBI::dbExecute(
    dbc_w,
    sprintf(
      'INSERT INTO "CrewCWH_Humus" ("PlotNumber", "Horizon", "UpperDepth", "LowerDepth", "Flag", "ID") VALUES (\'%s\', \'Fm\', 5.0, 0.0, 0, 888003)',
      leading_zero_plot
    )
  )
  DBI::dbExecute(
    dbc_w,
    sprintf(
      'INSERT INTO "CrewCWH_Metadata" ("ProjectID", "ProjectTitle", "ID") VALUES (\'%s\', \'R SDK QA Metadata\', 888004)',
      test_proj_id
    )
  )
  DBI::dbExecute(
    dbc_w,
    sprintf('INSERT INTO "CrewCWH_SU" ("PlotNumber", "SiteUnit") VALUES (\'%s\', \'CWHvm1/01\')', leading_zero_plot)
  )
  DBI::dbDisconnect(dbc_w)

  # 4. Submit validated staging bundle as Contributor
  sub_res <- vpro_staging_submit(
    contrib_con,
    ws_crew,
    submitter = "R SDK Contributor",
    notes = "Automated Wave 6 qualification upload"
  )
  created_sub_ids <- c(created_sub_ids, sub_res$submission_id)
  expect_equal(sub_res$status, "pending")
  expect_equal(sub_res$plot_count, 2L)
  expect_equal(sub_res$user_species_count, 1L)
  expect_true(sub_res$compliance_passed)

  q_tbl <- vpro_staging_list(contrib_con, status = "pending")
  expect_s3_class(q_tbl, "vpro_staging_queue")
  expect_true(sub_res$submission_id %in% q_tbl$submission_id)

  insp <- vpro_staging_inspect(admin_con, sub_res$submission_id)
  expect_equal(nrow(insp$user_species), 1L)
  expect_equal(insp$user_species$Code[[1L]], "RQASPP1")
  expect_equal(insp$provisional_diffs$status[[1L]], "new_provisional")

  # 5. Custodian 3-way diff, optimistic digest lock rollback check, and SERIALIZABLE merge
  diff_prev <- vpro_staging_diff(
    admin_con,
    sub_res$submission_id,
    base_db = base_db_path,
    base_project = "BaseCWH"
  )
  expect_s3_class(diff_prev, "vpro_merge_preview")
  expect_equal(diff_prev$added_count, 1L)
  expect_true(any(diff_prev$custodian_protected_diffs$field == "BECSiteUnit"))

  # Mismatched expected_digest MUST abort cleanly and leave becmaster untouched (rollback)
  expect_error(
    vpro_staging_merge(
      admin_con,
      sub_res$submission_id,
      expected_digest = strrep("f", 64L),
      base_db = base_db_path,
      base_project = "BaseCWH"
    )
  )
  still_absent <- DBI::dbGetQuery(
    admin_con$conn,
    'SELECT EXISTS (SELECT 1 FROM becmaster.env WHERE "PlotNumber" = $1) AS ex',
    params = list(leading_zero_plot)
  )$ex[[1L]]
  expect_false(still_absent)

  # Execute atomic SERIALIZABLE merge (without overriding custodian-protected BECSiteUnit)
  m_res <- vpro_staging_merge(
    admin_con,
    sub_res$submission_id,
    default_resolution = "keep_target",
    expected_digest = diff_prev$preview_digest,
    reviewer_notes = "Approved FastForward + Added plot; held BECSiteUnit",
    base_db = base_db_path,
    base_project = "BaseCWH",
    actor = "R SDK Custodian"
  )
  created_merge_tx_ids <- c(created_merge_tx_ids, m_res$merge_tx_id)
  allocated_child_ids <- c(allocated_child_ids, as.integer(m_res$allocated_child_ids))
  expect_equal(m_res$added_plots, 1L)
  expect_equal(m_res$updated_plots, 1L)
  expect_gt(m_res$audit_rows_written, 0L)

  # Verify leading-zero plot, FastForward SiteNotes, protected BECSiteUnit hold, and SHA-256 audit chain!
  merged_zero <- vpro_master_env(contrib_con, plots = leading_zero_plot)
  expect_equal(nrow(merged_zero), 1L)
  expect_identical(merged_zero$PlotNumber[[1L]], leading_zero_plot)

  merged_target <- vpro_master_env(contrib_con, plots = target_plot)
  expect_equal(merged_target$SiteNotes[[1L]], "R SDK FastForward QA Note")
  expect_equal(
    if (is.na(merged_target$BECSiteUnit[[1L]])) NA_character_ else merged_target$BECSiteUnit[[1L]],
    if (is.na(orig_bec_unit)) NA_character_ else as.character(orig_bec_unit)
  )

  chain_after <- attr(
    vpro_master_audit(admin_con, limit = as.integer(m_res$audit_rows_written + 25L), verify_chain = TRUE),
    "chain_verification"
  )
  expect_true(chain_after$valid)
  expect_equal(chain_after$tail_hash, m_res$tail_audit_hash)

  # 6. Verify Custodian rejection workflow on a second submission
  sub_rej <- vpro_staging_submit(
    contrib_con,
    ws_crew,
    submitter = "R SDK Contributor",
    notes = "Submission for rejection test"
  )
  created_sub_ids <- c(created_sub_ids, sub_rej$submission_id)
  rej_row <- vpro_staging_reject(
    admin_con,
    sub_rej$submission_id,
    reviewer_notes = "Duplicate test upload; rejecting cleanly."
  )
  expect_equal(rej_row$status[[1L]], "rejected")

  # 7. Verify Custodian multi-format snapshot publisher (.rds, .db, .gpkg, .csv) & .rds reader
  snap_dir <- file.path(tmp_work, "published_snap")
  snap_fmts <- if (requireNamespace("sf", quietly = TRUE)) {
    c("rds", "sqlite", "gpkg", "csv")
  } else {
    c("rds", "sqlite", "csv")
  }
  pub <- vpro_master_publish_snapshot(
    admin_con,
    snapshot_tag = test_snap_tag,
    out_dir = snap_dir,
    formats = snap_fmts,
    plots = c(target_plot, leading_zero_plot),
    notes = "Wave 6 automated multi-format snapshot test",
    compress = "gzip"
  )
  expect_equal(pub$snapshot_tag, test_snap_tag)
  expect_equal(pub$plot_count, 2L)
  expect_equal(nrow(pub$artifacts), length(snap_fmts))
  expect_true(all(file.exists(pub$artifacts$path)))

  snaps_tbl <- vpro_master_list_snapshots(contrib_con)
  expect_true(test_snap_tag %in% snaps_tbl$snapshot_tag)

  rds_art_path <- pub$artifacts$path[pub$artifacts$format == "rds"][[1L]]
  rds_proj <- vpro_import_rds(rds_art_path)
  rds_env <- vpro_env(rds_proj, scope = "project")
  expect_true(all(c(target_plot, leading_zero_plot) %in% rds_env$PlotNumber))

  # 7b. Verify S6.6 redact_sensitive = TRUE redacts sensitive plots across ALL 4 snapshot formats (sqlite, gpkg, rds, csv)
  red_vlists_dir <- file.path(tmp_work, "redacted_vlists")
  dir.create(red_vlists_dir)
  file.copy(vpro:::vpro_bundled_db("VLists.db"), file.path(red_vlists_dir, "VLists.db"))
  vred_con <- DBI::dbConnect(RSQLite::SQLite(), file.path(red_vlists_dir, "VLists.db"))
  DBI::dbExecute(
    vred_con,
    "INSERT OR REPLACE INTO \"USysSppAttributes\" (\"Code\", \"RedBlueList\") VALUES ('RQASPP1', 'Red')"
  )
  DBI::dbDisconnect(vred_con)

  red_snap_dir <- file.path(tmp_work, "published_redacted_snap")
  pub_red <- withr::with_options(list(vpro.data_dir = red_vlists_dir), {
    vpro_master_publish_snapshot(
      admin_con,
      snapshot_tag = red_snap_tag,
      out_dir = red_snap_dir,
      formats = snap_fmts,
      plots = c(target_plot, leading_zero_plot),
      notes = "Wave 6 S6.6 redacted multi-format snapshot test",
      compress = "gzip",
      redact_sensitive = TRUE
    )
  })
  expect_equal(pub_red$snapshot_tag, red_snap_tag)

  sqlite_red_ws <- vpro_connect(pub_red$artifacts$path[pub_red$artifacts$format == "sqlite"][[1L]])
  sqlite_red_env <- vpro_env(sqlite_red_ws, scope = "project")
  sq_hit <- sqlite_red_env[sqlite_red_env$PlotNumber == target_plot, , drop = FALSE]
  expect_true(all(is.na(c(sq_hit$Latitude, sq_hit$Longitude, sq_hit$UTMEasting, sq_hit$UTMNorthing))))
  expect_true(is.na(sq_hit$UTMZone))

  rds_red_env <- vpro_env(vpro_import_rds(pub_red$artifacts$path[pub_red$artifacts$format == "rds"][[1L]]), scope = "project")
  rds_hit <- rds_red_env[rds_red_env$PlotNumber == target_plot, , drop = FALSE]
  expect_true(all(is.na(c(rds_hit$Latitude, rds_hit$Longitude, rds_hit$UTMEasting, rds_hit$UTMNorthing))))
  expect_true(is.na(rds_hit$UTMZone))

  if ("gpkg" %in% snap_fmts) {
    gpkg_red_path <- pub_red$artifacts$path[pub_red$artifacts$format == "gpkg"][[1L]]
    gpkg_plots_sf <- sf::st_read(gpkg_red_path, layer = "plots", quiet = TRUE)
    expect_false(target_plot %in% as.character(gpkg_plots_sf$PlotNumber))
  }

  csv_untar_dir <- file.path(tmp_work, "csv_red_untar")
  dir.create(csv_untar_dir)
  utils::untar(pub_red$artifacts$path[pub_red$artifacts$format == "csv"][[1L]], exdir = csv_untar_dir)
  csv_env_file <- list.files(csv_untar_dir, pattern = "^env\\.csv$", recursive = TRUE, full.names = TRUE)[[1L]]
  csv_env <- utils::read.csv(csv_env_file, colClasses = c(PlotNumber = "character"), na.strings = c("NA", ""), stringsAsFactors = FALSE)
  csv_hit <- csv_env[csv_env$PlotNumber == target_plot, , drop = FALSE]
  expect_true(all(is.na(c(csv_hit$Latitude, csv_hit$Longitude, csv_hit$UTMEasting, csv_hit$UTMNorthing))))
  expect_true(is.na(csv_hit$UTMZone))

  # Run cleanup explicitly inside the test body too and assert exact 71,567-plot zero-drift restoration!
  DBI::dbExecute(admin_con$conn, 'DELETE FROM becmaster.env WHERE "PlotNumber" = $1', params = list(leading_zero_plot))
  DBI::dbExecute(
    admin_con$conn,
    'UPDATE becmaster.env SET "SiteNotes" = $1 WHERE "PlotNumber" = $2',
    params = list(if (is.na(orig_site_notes)) NA_character_ else as.character(orig_site_notes), target_plot)
  )
  DBI::dbExecute(
    admin_con$conn,
    'DELETE FROM becmaster.veg WHERE "PlotNumber" = $1 AND "Species" = \'RQASPP1\'',
    params = list(target_plot)
  )
  DBI::dbExecute(
    admin_con$conn,
    'DELETE FROM becmaster.metadata WHERE "ProjectID" = $1',
    params = list(test_proj_id)
  )
  if (length(allocated_child_ids) > 0L) {
    arr_lit <- paste0("{", paste(as.integer(allocated_child_ids), collapse = ","), "}")
    DBI::dbExecute(
      admin_con$conn,
      "DELETE FROM becmaster.child_identity WHERE id = ANY($1::bigint[])",
      params = list(arr_lit)
    )
    allocated_child_ids <- integer()
  }
  for (mtx in unique(created_merge_tx_ids)) {
    DBI::dbExecute(admin_con$conn, "DELETE FROM becmaster.audit WHERE merge_tx_id = $1::uuid", params = list(mtx))
    DBI::dbExecute(admin_con$conn, "DELETE FROM becmaster.merge_ledger WHERE merge_tx_id = $1::uuid", params = list(mtx))
  }
  created_merge_tx_ids <- character()
  for (sid in unique(created_sub_ids)) {
    DBI::dbExecute(admin_con$conn, "DELETE FROM staging.submissions WHERE submission_id = $1::uuid", params = list(sid))
  }
  created_sub_ids <- character()
  DBI::dbExecute(
    admin_con$conn,
    "DELETE FROM becmaster.snapshots WHERE snapshot_tag = ANY($1::text[])",
    params = list(vpro:::vpro_pg_text_array(c(test_snap_tag, red_snap_tag)))
  )
  DBI::dbExecute(
    admin_con$conn,
    "DELETE FROM becmaster.download_log WHERE id > $1 AND actor = ANY($2::text[])",
    params = list(baseline_max_dl, vpro:::vpro_pg_text_array(c(contrib_con$user, admin_con$user)))
  )
  leading_zero_plot <- NULL

  after_counts <- DBI::dbGetQuery(
    admin_con$conn,
    "SELECT (SELECT COUNT(*)::int FROM becmaster.env) AS plot_n, (SELECT COUNT(*)::bigint FROM becmaster.veg) AS veg_n"
  )
  expect_equal(as.integer(after_counts$plot_n[[1L]]), baseline_plots)
  expect_equal(after_counts$veg_n[[1L]], baseline_veg)
  expect_true(attr(vpro_master_audit(admin_con, limit = 100L, verify_chain = TRUE), "chain_verification")$valid)
})
