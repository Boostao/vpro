# W2 case-insensitive VLists.db vs vlists.db collision & support DB precedence
# (ENG-XCUT-001 + folded duplicate UX-SHELL-002).

.w2_create_readmodel_vlists <- function(path) {
  con <- DBI::dbConnect(RSQLite::SQLite(), path)
  on.exit(if (DBI::dbIsValid(con)) DBI::dbDisconnect(con), add = TRUE)
  DBI::dbExecute(
    con,
    'CREATE TABLE "Lists" ("ListName" TEXT, "Item" TEXT, "ItemDescription" TEXT, "ItemOrder" REAL, "FieldUsedIn" TEXT)'
  )
  DBI::dbExecute(
    con,
    'CREATE TABLE "Species" ("Code" TEXT, "ScientificName" TEXT, "EnglishName" TEXT, "Lifeform" INTEGER, "FamilyCode" TEXT, "Authority" TEXT)'
  )
  DBI::dbExecute(
    con,
    "INSERT INTO \"Species\" VALUES ('ABIELAS', 'Abies lasiocarpa', 'subalpine fir', 1, 'PINACEA', '(Hook.) Nutt.')"
  )
  invisible(path)
}

.w2_alias_case_insensitive <- function(dir_path, lower_name, pascal_name) {
  lower_path <- file.path(dir_path, lower_name)
  pascal_path <- file.path(dir_path, pascal_name)
  if (!file.exists(pascal_path)) {
    ok <- file.symlink(lower_path, pascal_path)
    if (!isTRUE(ok)) {
      file.copy(lower_path, pascal_path, overwrite = TRUE)
    }
  }
  list(lower = lower_path, pascal = pascal_path)
}

.w2_gzip_file_raw <- function(path) {
  raw_bytes <- readBin(path, what = "raw", n = file.info(path)$size)
  memCompress(raw_bytes, type = "gzip")
}

test_that("ENG-XCUT-001: case-insensitive <dataDir>/vlists.db never shadows database-family/VLists.db in vpro_connect()", {
  td <- tempfile("vpro-w2-ci-")
  cfg <- tempfile("vpro-w2-cfg-")
  dir.create(file.path(td, "database-family"), recursive = TRUE)
  dir.create(file.path(td, "projects"), recursive = TRUE)
  dir.create(cfg, recursive = TRUE)
  on.exit(unlink(c(td, cfg), recursive = TRUE, force = TRUE), add = TRUE)

  sample_ws <- vpro_connect("Sample")
  bundled_vlists <- vpro:::vpro_bundled_db("VLists.db")
  bundled_vuser <- vpro:::vpro_bundled_db("VUser.db")

  fam_vlists <- file.path(td, "database-family", "VLists.db")
  fam_vuser <- file.path(td, "database-family", "VUser.db")
  file.copy(bundled_vlists, fam_vlists)
  file.copy(bundled_vuser, fam_vuser)
  file.copy(sample_ws$project_path, file.path(td, "projects", "Sample.db"))

  # Simulate NTFS/APFS where <dataDir>/vlists.db (2-table read-model) and
  # <dataDir>/VLists.db resolve to the exact same inode.
  .w2_create_readmodel_vlists(file.path(td, "vlists.db"))
  .w2_alias_case_insensitive(td, "vlists.db", "VLists.db")
  expect_true(file.exists(file.path(td, "VLists.db")))

  ws <- vpro_connect("Sample", data_dir = td, config_dir = cfg)
  expect_identical(
    normalizePath(ws$vlists_path, winslash = "/", mustWork = TRUE),
    normalizePath(fam_vlists, winslash = "/", mustWork = TRUE)
  )
  expect_identical(
    normalizePath(ws$vuser_path, winslash = "/", mustWork = TRUE),
    normalizePath(fam_vuser, winslash = "/", mustWork = TRUE)
  )

  tax <- vpro_taxonomy(ws)
  expect_s3_class(tax, "tbl_df")
  expect_gt(nrow(tax), 10000L)

  bec <- vpro_bec_units(ws)
  expect_s3_class(bec, "tbl_df")
  expect_gt(nrow(bec), 1000L)

  # Even when a project database sits directly inside <dataDir> (proj_dir == data_dir),
  # database-family/VLists.db still takes precedence over top-level <dataDir>/VLists.db.
  top_proj <- file.path(td, "TopSample.db")
  file.copy(sample_ws$project_path, top_proj)
  ws_top <- vpro_connect(top_proj, data_dir = td, config_dir = cfg)
  expect_identical(
    normalizePath(ws_top$vlists_path, winslash = "/", mustWork = TRUE),
    normalizePath(fam_vlists, winslash = "/", mustWork = TRUE)
  )

  # Even if database-family/ does not exist yet and only a case-folded 2-table vlists.db
  # read-model exists in <dataDir>, vpro_find_support_db rejects the non-VP08 file and
  # falls back cleanly to bundled VLists.db.
  td_nofam <- tempfile("vpro-w2-nofam-")
  dir.create(file.path(td_nofam, "projects"), recursive = TRUE)
  on.exit(unlink(td_nofam, recursive = TRUE, force = TRUE), add = TRUE)
  file.copy(sample_ws$project_path, file.path(td_nofam, "projects", "Sample.db"))
  .w2_create_readmodel_vlists(file.path(td_nofam, "vlists.db"))
  .w2_alias_case_insensitive(td_nofam, "vlists.db", "VLists.db")

  ws_nofam <- vpro_connect("Sample", data_dir = td_nofam, config_dir = cfg)
  expect_true("USysAllSpecs" %in% vpro:::vpro_sqlite_physical_tables(ws_nofam$vlists_path))
  expect_gt(nrow(vpro_taxonomy(ws_nofam)), 10000L)
  expect_gt(nrow(vpro_bec_units(ws_nofam)), 1000L)
})

test_that("UX-SHELL-002: workspace.R and cloud_master_helpers.R prefer database-family/VLists.db over stale top-level VLists.db", {
  td <- tempfile("vpro-w2-stale-")
  cfg <- tempfile("vpro-w2-stalecfg-")
  dir.create(file.path(td, "database-family"), recursive = TRUE)
  dir.create(file.path(td, "projects"), recursive = TRUE)
  dir.create(cfg, recursive = TRUE)
  on.exit(unlink(c(td, cfg), recursive = TRUE, force = TRUE), add = TRUE)

  sample_ws <- vpro_connect("Sample")
  bundled_vlists <- vpro:::vpro_bundled_db("VLists.db")
  file.copy(sample_ws$project_path, file.path(td, "projects", "Sample.db"))

  # Top-level VLists.db: stale copy with 0 Red/Blue rows and sentinel species STALESPP
  stale_top <- file.path(td, "VLists.db")
  file.copy(bundled_vlists, stale_top)
  con_top <- DBI::dbConnect(RSQLite::SQLite(), stale_top)
  DBI::dbExecute(
    con_top,
    "INSERT INTO \"USysAllSpecs\" (\"Code\", \"ScientificName\", \"Lifeform\", \"Codetype\") VALUES ('STALESPP', 'Staleus topensis', 1, 'V')"
  )
  DBI::dbDisconnect(con_top)

  # Canonical database-family/VLists.db: active copy with ABIELAS Red-listed and sentinel FAMSPP
  active_fam <- file.path(td, "database-family", "VLists.db")
  file.copy(bundled_vlists, active_fam)
  con_fam <- DBI::dbConnect(RSQLite::SQLite(), active_fam)
  DBI::dbExecute(
    con_fam,
    "INSERT INTO \"USysAllSpecs\" (\"Code\", \"ScientificName\", \"Lifeform\", \"Codetype\") VALUES ('FAMSPP', 'Familius canonicus', 1, 'V')"
  )
  DBI::dbExecute(
    con_fam,
    "UPDATE \"USysSppAttributes\" SET \"RedBlueList\" = 'R' WHERE UPPER(TRIM(\"Code\")) = 'ABIELAS'"
  )
  DBI::dbDisconnect(con_fam)

  ws <- vpro_connect("Sample", data_dir = td, config_dir = cfg)
  expect_identical(
    normalizePath(ws$vlists_path, winslash = "/", mustWork = TRUE),
    normalizePath(active_fam, winslash = "/", mustWork = TRUE)
  )
  tax <- vpro_taxonomy(ws)
  expect_true("FAMSPP" %in% tax$Code)
  expect_false("STALESPP" %in% tax$Code)

  withr::with_options(list(vpro.data_dir = td, vpro.vlists_path = NULL), {
    sens_codes <- vpro:::.vpro_sensitive_species_codes(pg = NULL)
    expect_true("ABIELAS" %in% sens_codes)
  })
})

test_that("ENG-XCUT-001 + UX-SHELL-002: vpro_master_standards_sync() targets database-family/VLists.db, ignores 2-table vlists.db, and validates staged VP08 tables", {
  bundled_vlists <- vpro:::vpro_bundled_db("VLists.db")

  # Prepare a cloud release snapshot (bundled VLists.db with a synthetic release stamp)
  cloud_src <- tempfile("vpro-w2-cloud-vlists-", fileext = ".db")
  on.exit(unlink(cloud_src, force = TRUE), add = TRUE)
  file.copy(bundled_vlists, cloud_src)
  con_c <- DBI::dbConnect(RSQLite::SQLite(), cloud_src)
  DBI::dbExecute(
    con_c,
    "UPDATE \"_table_metadata\" SET \"description\" = 'BECdb_v13_2026_r2' WHERE \"table_name\" = 'USysTableOfLists'"
  )
  DBI::dbDisconnect(con_c)
  cloud_sha <- tolower(vpro:::vpro_sha256_file(cloud_src))
  cloud_gz <- .w2_gzip_file_raw(cloud_src)

  fake_pg <- structure(list(role = "contributor"), class = "vpro_pg_conn")

  # 1. Fresh data_dir with case-insensitive 2-table vlists.db <-> VLists.db simulation:
  # sync must write to <data_dir>/database-family/VLists.db without clobbering <data_dir>/vlists.db.
  td_ci <- tempfile("vpro-w2-sync-ci-")
  dir.create(td_ci, recursive = TRUE)
  on.exit(unlink(td_ci, recursive = TRUE, force = TRUE), add = TRUE)
  .w2_create_readmodel_vlists(file.path(td_ci, "vlists.db"))
  .w2_alias_case_insensitive(td_ci, "vlists.db", "VLists.db")
  rm_sha_before <- vpro:::vpro_sha256_file(file.path(td_ci, "vlists.db"))

  local_mocked_bindings(
    vpro_assert_pg_conn = function(pg, require_custodian = FALSE) invisible(TRUE),
    vpro_pg_query = function(pg, sql, params = NULL, action = "") {
      data.frame(
        release_id = "rel-2026-r2",
        bec_version = "BECdb_v13_2026_r2",
        taxonomy_version = "BCPlantTaxa_v19_2025",
        vlists_sha256 = cloud_sha,
        published_at = "2026-11-19T00:00:00Z",
        vlists_gzip = I(list(cloud_gz)),
        stringsAsFactors = FALSE
      )
    },
    .package = "vpro"
  )

  res1 <- vpro_master_standards_sync(fake_pg, data_dir = td_ci)
  expect_true(res1$updated)
  expect_false(res1$already_current)
  expect_identical(
    normalizePath(res1$vlists_path, winslash = "/", mustWork = TRUE),
    normalizePath(file.path(td_ci, "database-family", "VLists.db"), winslash = "/", mustWork = TRUE)
  )
  expect_identical(res1$local_sha256, cloud_sha)
  expect_identical(vpro:::vpro_sha256_file(file.path(td_ci, "vlists.db")), rm_sha_before)

  res2 <- vpro_master_standards_sync(fake_pg, data_dir = td_ci)
  expect_false(res2$updated)
  expect_true(res2$already_current)

  # 2. Shared data_dir with BOTH stale top-level VLists.db AND database-family/VLists.db:
  # sync must update database-family/VLists.db and leave top-level VLists.db untouched.
  td_dual <- tempfile("vpro-w2-sync-dual-")
  dir.create(file.path(td_dual, "database-family"), recursive = TRUE)
  on.exit(unlink(td_dual, recursive = TRUE, force = TRUE), add = TRUE)
  top_vl <- file.path(td_dual, "VLists.db")
  fam_vl <- file.path(td_dual, "database-family", "VLists.db")
  file.copy(bundled_vlists, top_vl)
  file.copy(bundled_vlists, fam_vl)
  top_sha_before <- vpro:::vpro_sha256_file(top_vl)

  res_dual <- vpro_master_standards_sync(fake_pg, data_dir = td_dual)
  expect_true(res_dual$updated)
  expect_identical(
    normalizePath(res_dual$vlists_path, winslash = "/", mustWork = TRUE),
    normalizePath(fam_vl, winslash = "/", mustWork = TRUE)
  )
  expect_identical(tolower(vpro:::vpro_sha256_file(fam_vl)), cloud_sha)
  expect_identical(vpro:::vpro_sha256_file(top_vl), top_sha_before)

  # 3. Staged gzip containing a 2-table read-model (missing USysAllSpecs etc.) is rejected before swap.
  bad_rm <- tempfile("vpro-w2-bad-rm-", fileext = ".db")
  on.exit(unlink(bad_rm, force = TRUE), add = TRUE)
  .w2_create_readmodel_vlists(bad_rm)
  bad_sha <- tolower(vpro:::vpro_sha256_file(bad_rm))
  bad_gz <- .w2_gzip_file_raw(bad_rm)

  local_mocked_bindings(
    vpro_pg_query = function(pg, sql, params = NULL, action = "") {
      data.frame(
        release_id = "rel-bad",
        bec_version = "BECdb_bad",
        taxonomy_version = "Tax_bad",
        vlists_sha256 = bad_sha,
        published_at = "2026-11-19T00:00:00Z",
        vlists_gzip = I(list(bad_gz)),
        stringsAsFactors = FALSE
      )
    },
    .package = "vpro"
  )

  expect_error(
    vpro_master_standards_sync(fake_pg, data_dir = td_dual),
    "missing required catalogue table"
  )
  expect_identical(tolower(vpro:::vpro_sha256_file(fam_vl)), cloud_sha)
})
