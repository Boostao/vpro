new_w2_writeback_scratch <- function(prefix = "w2wb") {
  dir_path <- file.path(
    tempdir(),
    sprintf("vpro-%s-%d-%06d", prefix, Sys.getpid(), sample.int(999999L, 1L))
  )
  dir.create(dir_path, recursive = TRUE, showWarnings = FALSE)
  normalizePath(dir_path, winslash = "/", mustWork = TRUE)
}

clone_project_from_sample <- function(scratch_dir, target_project = "Sample") {
  db_path <- file.path(scratch_dir, paste0(target_project, ".db"))
  src_ws <- vpro_connect("Sample")
  if (identical(target_project, "Sample")) {
    file.copy(src_ws$project_path, db_path, overwrite = TRUE)
    rw <- DBI::dbConnect(RSQLite::SQLite(), db_path, flags = RSQLite::SQLITE_RW)
    on.exit(if (DBI::dbIsValid(rw)) DBI::dbDisconnect(rw), add = TRUE)
    DBI::dbExecute(rw, "PRAGMA journal_mode = WAL")
    DBI::dbExecute(rw, "PRAGMA busy_timeout = 5000")
    DBI::dbDisconnect(rw)
    return(vpro_connect(
      project = db_path,
      su = "Sample_SU",
      hierarchy = "Sample_Hierarchy",
      lump = "Sample_Lump",
      data_dir = scratch_dir,
      config_dir = scratch_dir
    ))
  }

  rw <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  on.exit(if (DBI::dbIsValid(rw)) DBI::dbDisconnect(rw), add = TRUE)
  ro <- vpro:::vpro_sqlite_ro(src_ws$project_path)
  on.exit(if (DBI::dbIsValid(ro)) DBI::dbDisconnect(ro), add = TRUE)

  deferred_idx <- vpro:::vpro_clone_sample_schema(rw, target_project)
  DBI::dbExecute(rw, 'CREATE TABLE "_table_metadata" ("table_name" TEXT PRIMARY KEY, "description" TEXT)')
  for (sfx in vpro:::.vpro_core_project_suffixes) {
    src_tbl <- paste0("Sample_", sfx)
    dst_tbl <- paste0(target_project, "_", sfx)
    df <- DBI::dbGetQuery(ro, paste0("SELECT * FROM ", vpro:::vpro_quote_ident(src_tbl)))
    if (identical(sfx, "Audit") && "Project" %in% names(df) && nrow(df) > 0L) {
      df$Project <- rep(target_project, nrow(df))
    }
    if (nrow(df) > 0L) {
      DBI::dbAppendTable(rw, dst_tbl, df)
    }
    DBI::dbExecute(
      rw,
      'INSERT INTO "_table_metadata" ("table_name", "description") VALUES (?, \'VP08\')',
      params = list(dst_tbl)
    )
  }
  for (idx_sql in deferred_idx) {
    tryCatch(DBI::dbExecute(rw, idx_sql), error = function(e) NULL)
  }
  vpro:::vpro_seed_imported_child_identities(rw, "Sample", target_project)
  DBI::dbExecute(rw, "PRAGMA journal_mode = WAL")
  DBI::dbDisconnect(ro)
  DBI::dbDisconnect(rw)

  vpro_connect(
    project = db_path,
    data_dir = scratch_dir,
    config_dir = scratch_dir
  )
}

test_that("vpro_write_su and vpro_write_lump write SQL NULL Audit.ID, omit __VPRO_IdentitySeq, and never reuse retired IDs", {
  scratch <- new_w2_writeback_scratch("auditnull")
  on.exit(unlink(scratch, recursive = TRUE, force = TRUE), add = TRUE)
  ws <- clone_project_from_sample(scratch, "Sample")

  rw <- DBI::dbConnect(RSQLite::SQLite(), ws$project_path, flags = RSQLite::SQLITE_RW)
  on.exit(if (DBI::dbIsValid(rw)) DBI::dbDisconnect(rw), add = TRUE)
  mx <- as.integer(DBI::dbGetQuery(rw, 'SELECT COALESCE(MAX("ID"), 0) AS mx FROM "Sample_Audit"')$mx[[1L]])
  reserved_audit <- mx + 1L
  DBI::dbExecute(
    rw,
    'CREATE TABLE IF NOT EXISTS "__VPRO_ChildIdentity" ("ChildTable" TEXT NOT NULL, "ID" INTEGER NOT NULL, PRIMARY KEY ("ChildTable", "ID"))'
  )
  DBI::dbExecute(
    rw,
    'INSERT INTO "__VPRO_ChildIdentity" ("ChildTable", "ID") VALUES (?, ?)',
    params = list("Sample_Audit", reserved_audit)
  )
  DBI::dbDisconnect(rw)

  cand <- tibble::tibble(
    PlotNumber = vpro_env(ws, scope = "project")$PlotNumber[1:2],
    Cluster = c("A", "B")
  )
  ws_cand <- vpro_write_su(ws, cand, candidate = TRUE, actor = "qa_actor")
  expect_equal(ws_cand$su, "Sample_ClusterCandidate_SU")
  expect_equal(ws_cand$table, "Sample_ClusterCandidate_SU")

  ws_work <- vpro_write_su(ws, cand, su = "Rev2026", create = TRUE, actor = "qa_actor")
  expect_equal(ws_work$su, "Rev2026_SU")
  expect_equal(ws_work$table, "Rev2026_SU")

  lump_df <- tibble::tibble(LumpCode = "ABIESPP", SppCode = "ABIELAS", Use = TRUE)
  ws_lump <- vpro_write_lump(ws, lump_df, lump = "Rev2026", create = TRUE, actor = "qa_actor")
  expect_equal(ws_lump$lump, "Rev2026_Lump")
  expect_equal(ws_lump$table, "Rev2026_Lump")

  ro <- vpro:::vpro_sqlite_ro(ws$project_path)
  on.exit(if (DBI::dbIsValid(ro)) DBI::dbDisconnect(ro), add = TRUE)

  vpro_tables <- DBI::dbGetQuery(
    ro,
    "SELECT name FROM sqlite_master WHERE type = 'table' AND name LIKE '__VPRO_%' ORDER BY name"
  )$name
  expect_false("__VPRO_IdentitySeq" %in% vpro_tables)
  expect_true("__VPRO_RSidecarHistory" %in% vpro_tables)

  qa_audits <- DBI::dbGetQuery(
    ro,
    'SELECT "ID", typeof("ID") AS id_type, "Table", "EditField" FROM "Sample_Audit" WHERE "User" = \'qa_actor\' ORDER BY rowid ASC'
  )
  expect_equal(nrow(qa_audits), 3L)
  expect_true(all(is.na(qa_audits$ID)))
  expect_equal(qa_audits$id_type, rep("null", 3L))
  expect_equal(
    qa_audits$EditField,
    c("MaterializeClusterCandidate", "WriteWorkingSU", "WriteLumpTable")
  )

  all_audit_ids <- DBI::dbGetQuery(ro, 'SELECT "ID" FROM "Sample_Audit" WHERE "ID" IS NOT NULL')$ID
  expect_false(reserved_audit %in% all_audit_ids)
})

test_that("vpro_reserve_next_id_in_tx honors __VPRO_ChildIdentity and _Audit monotonically without bare-prefix bug", {
  scratch <- new_w2_writeback_scratch("childid")
  on.exit(unlink(scratch, recursive = TRUE, force = TRUE), add = TRUE)
  ws <- clone_project_from_sample(scratch, "Sample")

  rw <- DBI::dbConnect(RSQLite::SQLite(), ws$project_path, flags = RSQLite::SQLITE_RW)
  on.exit(if (DBI::dbIsValid(rw)) DBI::dbDisconnect(rw), add = TRUE)
  mx_veg <- as.integer(DBI::dbGetQuery(
    rw,
    'SELECT COALESCE(MAX("ID"), 0) AS mx FROM "Sample_Veg" WHERE typeof("ID") = \'integer\' AND "ID" > 0 AND "ID" <= 2147483647'
  )$mx[[1L]])
  DBI::dbExecute(rw, vpro:::.vpro_child_identity_ddl)
  # Reserve mx_veg + 1 (unquoted), mx_veg + 2 (quoted), and mx_veg + 3 (deleted row in Sample_Audit)
  DBI::dbExecute(
    rw,
    'INSERT INTO "__VPRO_ChildIdentity" ("ChildTable", "ID") VALUES (?, ?), (?, ?)',
    params = list("Sample_Veg", mx_veg + 1L, '"Sample_Veg"', mx_veg + 2L)
  )
  DBI::dbExecute(
    rw,
    paste(
      'INSERT INTO "Sample_Audit" ("Project", "User", "PlotNumber", "Table", "EditField", "EditWhen", "Restore", "Flag", "ID")',
      "VALUES ('Sample', 'tester', '00337', '_Veg', 'Delete record', '2026-01-01 00:00:00', 0, 0, ?)"
    ),
    params = list(mx_veg + 3L)
  )
  mx_aud <- as.integer(DBI::dbGetQuery(rw, 'SELECT COALESCE(MAX("ID"), 0) AS mx FROM "Sample_Audit"')$mx[[1L]])
  DBI::dbExecute(
    rw,
    'INSERT INTO "__VPRO_ChildIdentity" ("ChildTable", "ID") VALUES (?, ?)',
    params = list("Sample_Audit", mx_aud + 1L)
  )
  DBI::dbDisconnect(rw)

  alloc1 <- vpro:::vpro_with_immediate_tx(ws$project_path, con = ws, fn = function(dbc) {
    id1 <- vpro:::vpro_reserve_next_id_in_tx(dbc, "Sample_Veg")
    vpro:::vpro_append_project_audit_in_tx(
      dbc = dbc,
      project_name = "Sample",
      actor = "child_writer",
      table_name = "_Veg",
      edit_field = "Species",
      before_val = "",
      after_val = "PSEUMEN",
      plot_number = "00337",
      child_id = id1
    )
    id1
  })
  expect_equal(alloc1, mx_veg + 4L)

  # Even without inserting into Sample_Veg, alloc1 is reserved in __VPRO_ChildIdentity and never reused
  alloc2 <- vpro:::vpro_with_immediate_tx(ws$project_path, con = ws, fn = function(dbc) {
    vpro:::vpro_reserve_next_id_in_tx(dbc, '"Sample_Veg"')
  })
  expect_equal(alloc2, mx_veg + 5L)

  # Passing Sample_Audit directly never queries nonexistent bare table "Sample" and skips reserved mx_aud + 1L
  alloc_aud <- vpro:::vpro_with_immediate_tx(ws$project_path, con = ws, fn = function(dbc) {
    vpro:::vpro_reserve_next_id_in_tx(dbc, "Sample_Audit")
  })
  expect_true(alloc_aud > mx_aud + 1L)

  # MaxInt32 outlier in child table falls back cleanly to smallest unused positive INT32
  alloc_gap <- vpro:::vpro_with_immediate_tx(ws$project_path, con = ws, fn = function(dbc) {
    DBI::dbExecute(dbc, 'CREATE TABLE "GapTest_Other" ("ID" INTEGER, "PlotNumber" TEXT)')
    DBI::dbExecute(dbc, 'INSERT INTO "GapTest_Other" ("ID", "PlotNumber") VALUES (1, \'P1\'), (2147483647, \'P1\')')
    vpro:::vpro_reserve_next_id_in_tx(dbc, "GapTest_Other")
  })
  expect_equal(alloc_gap, 2L)

  ro <- vpro:::vpro_sqlite_ro(ws$project_path)
  on.exit(if (DBI::dbIsValid(ro)) DBI::dbDisconnect(ro), add = TRUE)
  child_aud <- DBI::dbGetQuery(
    ro,
    'SELECT "ID", typeof("ID") AS tp FROM "Sample_Audit" WHERE "User" = \'child_writer\''
  )
  expect_equal(nrow(child_aud), 1L)
  expect_equal(child_aud$ID[[1L]], alloc1)
  expect_equal(child_aud$tp[[1L]], "integer")
})

test_that("candidate SU names truncate base to <= 14 chars (<= 31 prefix) across 20-char projects and match Go ProjectNamePattern", {
  scratch <- new_w2_writeback_scratch("cand14")
  on.exit(unlink(scratch, recursive = TRUE, force = TRUE), add = TRUE)

  # 1. Explicit su = 'Haida_Gwaii_2019' (16 chars) on Sample truncates base to 'Haida_Gwaii_20' (31-char prefix)
  ws_sample <- clone_project_from_sample(scratch, "Sample")
  cand <- tibble::tibble(
    PlotNumber = c("00337", "108050"),
    SiteUnit = c("01", "02")
  )
  res_hg <- vpro_write_su(
    ws_sample,
    cand,
    su = "Haida_Gwaii_2019",
    candidate = TRUE,
    create = TRUE,
    overwrite = TRUE,
    actor = "ecologist"
  )
  expect_equal(res_hg$su, "Haida_Gwaii_20_ClusterCandidate_SU")
  expect_equal(res_hg$table, "Haida_Gwaii_20_ClusterCandidate_SU")
  hg_prefix <- sub("_SU$", "", res_hg$table)
  expect_equal(nchar(hg_prefix), 31L)
  expect_true(grepl("^[A-Za-z][A-Za-z0-9_]{0,30}$", hg_prefix))

  # 2. 20-char project name 'TwentyCharProjectNam' with default su = NULL writes 'TwentyCharProj_ClusterCandidate_SU'
  proj20 <- "TwentyCharProjectNam"
  expect_equal(nchar(proj20), 20L)
  ws20 <- clone_project_from_sample(scratch, proj20)
  res20 <- vpro_write_su(ws20, cand, candidate = TRUE, actor = "ecologist")
  expect_equal(res20$table, "TwentyCharProj_ClusterCandidate_SU")
  pfx20 <- sub("_SU$", "", res20$table)
  expect_equal(nchar(pfx20), 31L)
  expect_true(grepl("^[A-Za-z][A-Za-z0-9_]{0,30}$", pfx20))
  expect_equal(nrow(vpro_site_units(res20)), 2L)

  # 3. Default su = NULL when ws$project contains 'master' maps to 'Proj_ClusterCandidate_SU' matching Go rsidecar,
  #    whereas explicit su = 'Master' is unconditionally refused
  ws_mst <- ws_sample
  ws_mst$project <- "Sample"
  expect_error(vpro_write_su(ws_mst, cand, su = "Master", candidate = TRUE), "Master")
  expect_error(vpro_write_su(ws_mst, cand, su = "GoodPrefix12345$bad", candidate = TRUE), "ASCII letter")

  ws_submst <- clone_project_from_sample(scratch, "LocalMasterSubset")
  res_mst_def <- vpro_write_su(ws_submst, cand, candidate = TRUE, actor = "ecologist")
  expect_equal(res_mst_def$table, "Proj_ClusterCandidate_SU")
})

test_that("vpro_seed_imported_child_identities and vpro_import_access seed __VPRO_ChildIdentity identically to Go", {
  scratch <- new_w2_writeback_scratch("impseed")
  on.exit(unlink(scratch, recursive = TRUE, force = TRUE), add = TRUE)
  ws <- clone_project_from_sample(scratch, "ImpProj")

  rw <- DBI::dbConnect(RSQLite::SQLite(), ws$project_path, flags = RSQLite::SQLITE_RW)
  on.exit(if (DBI::dbIsValid(rw)) DBI::dbDisconnect(rw), add = TRUE)
  DBI::dbExecute(rw, 'DELETE FROM "__VPRO_ChildIdentity"')
  DBI::dbExecute(rw, 'DELETE FROM "ImpProj_Veg"')
  DBI::dbExecute(
    rw,
    paste(
      'INSERT INTO "ImpProj_Veg" ("PlotNumber", "Species", "ID", "Cover1", "Flag")',
      "VALUES ('00337', 'PSEUMEN', 2, 25.0, 0), ('00337', 'TSUGHET', 0, 10.0, 0), ('00337', 'ABIEAMA', -5, 5.0, 0)"
    )
  )
  # Historical deleted ID = 99 recorded only in ImpProj_Audit under source table 'OldSrc_Veg'
  DBI::dbExecute(
    rw,
    paste(
      'INSERT INTO "ImpProj_Audit" ("Project", "User", "PlotNumber", "Table", "EditField", "EditWhen", "Restore", "Flag", "ID")',
      "VALUES ('ImpProj', 'VPro', '00337', 'OldSrc_Veg', 'Delete record', '2024-01-01 00:00:00', 0, 0, 99)"
    )
  )
  vpro:::vpro_seed_imported_child_identities(rw, "OldSrc", "ImpProj")

  seeded_veg <- DBI::dbGetQuery(
    rw,
    'SELECT "ID" FROM "__VPRO_ChildIdentity" WHERE "ChildTable" = \'"ImpProj_Veg"\' ORDER BY "ID"'
  )$ID
  # Positive ID 2 (from ImpProj_Veg) and 99 (from OldSrc_Veg in ImpProj_Audit) seeded; 0 and -5 excluded!
  expect_true(all(c(2L, 99L) %in% seeded_veg))
  expect_false(any(c(0L, -5L) %in% seeded_veg))
  DBI::dbDisconnect(rw)

  next_veg_id <- vpro:::vpro_with_immediate_tx(ws$project_path, con = ws, fn = function(dbc) {
    vpro:::vpro_reserve_next_id_in_tx(dbc, "ImpProj_Veg")
  })
  expect_gt(next_veg_id, 99L)

  # Also exercise real vpro_import_access() when local sibling Haida_Gwaii_2019.accdb and mdbr are available
  accdb_path <- "/home/bruno/Work/VPRO_ACCESS_1/VPro64/Haida_Gwaii_2019.accdb"
  if (file.exists(accdb_path) && requireNamespace("mdbr", quietly = TRUE)) {
    imp_db <- file.path(scratch, "HGImported.db")
    imp_res <- vpro_import_access(accdb_path, imp_db, dest_project = "HGImp", overwrite = TRUE)
    expect_gt(imp_res$plot_count, 0L)
    ro_imp <- vpro:::vpro_sqlite_ro(imp_db)
    on.exit(if (DBI::dbIsValid(ro_imp)) DBI::dbDisconnect(ro_imp), add = TRUE)
    has_ci <- DBI::dbGetQuery(
      ro_imp,
      "SELECT COUNT(*) AS n FROM sqlite_master WHERE type = 'table' AND name = '__VPRO_ChildIdentity'"
    )$n[[1L]]
    expect_equal(has_ci, 1L)
    ci_rows <- DBI::dbGetQuery(
      ro_imp,
      'SELECT "ChildTable", MIN("ID") AS min_id, COUNT(*) AS n FROM "__VPRO_ChildIdentity" GROUP BY "ChildTable"'
    )
    expect_gt(nrow(ci_rows), 0L)
    expect_true(all(ci_rows$min_id > 0L))
    expect_true('"HGImp_Veg"' %in% ci_rows$ChildTable)
  }
})
