make_wave2a_scratch_dir <- function(prefix = "wave2a") {
  dir_path <- file.path(
    getwd(),
    sprintf(".vpro-test-scratch-%s-%d-%06d", prefix, Sys.getpid(), sample.int(999999L, 1L))
  )
  dir.create(dir_path, recursive = TRUE, showWarnings = FALSE)
  dir_path
}

test_that("vpro_matrix preserves '00337', aligns env 1-to-1, supports dense/sparse transforms, and feeds vegan in 1 line", {
  ws <- vpro_connect("Sample")

  m_proj <- vpro_matrix(ws, scope = "project", value = "cover", strata = "total", lump = TRUE, transform = "none")
  expect_true(is.matrix(m_proj))
  expect_type(rownames(m_proj), "character")
  expect_true("00337" %in% rownames(m_proj))
  env_proj <- attr(m_proj, "env")
  expect_s3_class(env_proj, "tbl_df")
  expect_identical(rownames(m_proj), env_proj$PlotNumber)
  expect_true(all(rowSums(m_proj) > 0))

  # Value modes: presence (0/1) and goldstream (sqrt(cover))
  m_pres <- vpro_matrix(ws, scope = "su", value = "presence", transform = "none")
  expect_true(all(m_pres %in% c(0, 1)))
  m_gold <- vpro_matrix(ws, scope = "su", value = "goldstream", transform = "none")
  m_cov <- vpro_matrix(ws, scope = "su", value = "cover", transform = "none")
  expect_equal(m_gold, sqrt(m_cov), ignore_attr = TRUE)

  # Strata column naming: abcd and raw
  m_abcd <- vpro_matrix(ws, scope = "su", strata = "abcd")
  expect_true(all(grepl("_(A|B|C|D)$", colnames(m_abcd))))
  m_raw <- vpro_matrix(ws, scope = "su", strata = "raw")
  expect_true(all(grepl("_(1|2|3|4|5|5a|5b|5c|6|7|8|9|10|A|B)$", colnames(m_raw))))

  # Rare-species filtering (proportion and plot count) preserves 1-to-1 env alignment
  m_prop <- vpro_matrix(ws, scope = "su", drop_rare = 0.10)
  expect_lt(ncol(m_prop), ncol(m_cov))
  expect_identical(rownames(m_prop), attr(m_prop, "env")$PlotNumber)

  m_cnt <- vpro_matrix(ws, scope = "su", drop_rare = 5)
  expect_true(all(colSums(m_cnt > 0) >= 5))
  expect_identical(rownames(m_cnt), attr(m_cnt, "env")$PlotNumber)

  # Dense vs Sparse (Matrix::dgCMatrix) parity across all 6 transforms
  skip_if_not_installed("Matrix")
  skip_if_not_installed("vegan")
  for (tr in c("none", "sqrt", "log1p", "hellinger", "chord", "wisconsin")) {
    md <- vpro_matrix(ws, scope = "su", transform = tr, sparse = FALSE)
    ms <- vpro_matrix(ws, scope = "su", transform = tr, sparse = TRUE)
    expect_s4_class(ms, "dgCMatrix")
    expect_identical(rownames(ms), attr(ms, "env")$PlotNumber)
    expect_equal(as.matrix(ms), md, tolerance = 1e-10, ignore_attr = TRUE, info = tr)
  }

  # Hellinger row sum of squares == 1; Chord Euclidean row norm == 1
  m_hel <- vpro_matrix(ws, scope = "su", transform = "hellinger")
  expect_equal(unname(rowSums(m_hel^2)), rep(1, nrow(m_hel)), tolerance = 1e-10)
  m_chd <- vpro_matrix(ws, scope = "su", transform = "chord")
  expect_equal(unname(sqrt(rowSums(m_chd^2))), rep(1, nrow(m_chd)), tolerance = 1e-10)

  # 1-line vegan::metaMDS and vegan::adonis2 integration
  m_su <- vpro_matrix(ws, scope = "su", transform = "sqrt", drop_rare = 2)
  nmds <- suppressWarnings(vegan::metaMDS(m_su, distance = "bray", k = 2, trymax = 3, trace = 0))
  expect_s3_class(nmds, "metaMDS")
  perm <- vegan::adonis2(m_su ~ SiteUnit, data = attr(m_su, "env"), permutations = 19, by = "margin")
  expect_s3_class(perm, "anova")
})

test_that("vpro_cluster supports hierarchical, flexible-beta, PAM, FCM, and NC with S3 methods and vpro_indicators", {
  skip_if_not_installed("vegan")
  skip_if_not_installed("cluster")
  skip_if_not_installed("vegclust")
  skip_if_not_installed("indicspecies")

  ws <- vpro_connect("Sample")
  scratch <- make_wave2a_scratch_dir("cluster")
  on.exit(unlink(scratch, recursive = TRUE), add = TRUE)

  # Hierarchical methods: ward.D2, average, beta_flexible
  cl_ward <- vpro_cluster(ws, method = "ward.D2", k = 3L, scope = "project", exclude_modifiers = FALSE)
  expect_s3_class(cl_ward, "vpro_clusters")
  expect_s3_class(cl_ward$dendrogram, "hclust")
  expect_null(cl_ward$fuzzy_weights)
  expect_true(is.finite(cl_ward$cophenetic))
  expect_true("00337" %in% cl_ward$memberships$PlotNumber)
  expect_equal(
    names(cl_ward$memberships),
    c("PlotNumber", "SiteUnit", "Cluster", "Silhouette", "MaxMembership", "IsNoise")
  )
  expect_false(any(cl_ward$memberships$IsNoise))

  cl_flex <- vpro_cluster(ws, method = "beta_flexible", beta = -0.25, k = 3L)
  expect_s3_class(cl_flex$dendrogram, "hclust")
  expect_equal(nrow(summary.vpro_clusters(cl_flex)), 3L)

  cl_avg <- vpro_cluster(ws, method = "average", k = 3L)
  expect_s3_class(cl_avg$dendrogram, "hclust")

  # Medoid clustering: PAM
  cl_pam <- vpro_cluster(ws, method = "pam", k = 3L, unit_prefix = "PM")
  expect_null(cl_pam$dendrogram)
  expect_true(all(grepl("^PM_0[1-3]$", cl_pam$memberships$SiteUnit)))
  expect_true(all(cl_pam$clusters$medoid_plot %in% cl_pam$memberships$PlotNumber))

  # Fuzzy C-Means & Noise Clustering (vegclust)
  cl_fcm <- vpro_cluster(ws, method = "vegclust_fcm", k = 3L, m = 1.25)
  expect_s3_class(cl_fcm$fuzzy_weights, "data.frame")
  memb_cols_fcm <- setdiff(names(cl_fcm$fuzzy_weights), "PlotNumber")
  expect_equal(unname(rowSums(cl_fcm$fuzzy_weights[, memb_cols_fcm, drop = FALSE])), rep(1, nrow(cl_fcm$fuzzy_weights)), tolerance = 1e-6)

  cl_nc <- vpro_cluster(ws, method = "vegclust_nc", k = 3L, m = 1.25, dnoise = 0.65, unit_prefix = "NC")
  expect_s3_class(cl_nc$fuzzy_weights, "data.frame")
  expect_true("N" %in% names(cl_nc$fuzzy_weights))
  expect_true(any(cl_nc$memberships$IsNoise))
  expect_true(any(cl_nc$memberships$SiteUnit == "NC_Noise"))

  # S3 methods: print, summary, as_tibble, plot
  expect_message(print.vpro_clusters(cl_ward), "vpro_clusters")
  expect_identical(as_tibble.vpro_clusters(cl_ward), cl_ward$memberships)
  expect_true(all(c("SiteUnit", "n_plots", "mean_silhouette", "medoid_plot") %in% names(summary.vpro_clusters(cl_ward))))

  pdf_path <- file.path(scratch, "clusters.pdf")
  grDevices::pdf(pdf_path)
  plot.vpro_clusters(cl_ward, type = "dendrogram")
  plot.vpro_clusters(cl_nc, type = "ordination")
  grDevices::dev.off()
  expect_true(file.exists(pdf_path))

  # Indicator species synthesis (vpro_indicators)
  ind_cl <- vpro_indicators(ws, clusters = cl_ward, max_order = 1L, permutations = 49L, scope = "project")
  expect_s3_class(ind_cl, "tbl_df")
  expect_equal(names(ind_cl), c("Species", "Group", "IndVal", "p_value", "ScientificName"))
  expect_gt(nrow(ind_cl), 10L)
  expect_true(any(!is.na(ind_cl$ScientificName) & nzchar(ind_cl$ScientificName)))

  ind_su <- vpro_indicators(ws, clusters = NULL, max_order = 2L, permutations = 29L)
  expect_s3_class(ind_su, "tbl_df")
  expect_gt(nrow(ind_su), 10L)
})

test_that("vpro_sf repairs positive BC longitudes, backfills UTM->DD, flags >250m divergence, computes BCGS 1:20k, and exports GPKG", {
  skip_if_not_installed("sf")

  scratch <- make_wave2a_scratch_dir("spatial")
  on.exit(unlink(scratch, recursive = TRUE), add = TRUE)

  db_path <- file.path(scratch, "Sample.db")
  file.copy(vpro_connect("Sample")$project_path, db_path)

  wcon <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  on.exit(if (DBI::dbIsValid(wcon)) DBI::dbDisconnect(wcon), add = TRUE)

  # 1. Plot '00401': UTM-only in NAD83 Zone 9 near 54.55N, -127.30W -> mapsheet '093L.054'
  pts_src <- sf::st_as_sf(
    data.frame(lon = -127.30, lat = 54.55),
    coords = c("lon", "lat"),
    crs = 4269L
  )
  utm9_xy <- sf::st_coordinates(sf::st_transform(pts_src, 26909L))

  DBI::dbExecute(
    wcon,
    sprintf(
      paste(
        'INSERT INTO "Sample_Env" ("PlotNumber", "Latitude", "Longitude", "UTMZone", "UTMEasting", "UTMNorthing") VALUES',
        "('00401', NULL, NULL, '09', %.3f, %.3f),",
        "('00402', 54.55, -127.30, '9', %.3f, %.3f),",
        "('00403', 54.55, 127.30, '9', %.3f, %.3f)"
      ),
      utm9_xy[1, 1], utm9_xy[1, 2],
      utm9_xy[1, 1] + 20.0, utm9_xy[1, 2] + 15.0,
      utm9_xy[1, 1] + 900.0, utm9_xy[1, 2]
    )
  )
  DBI::dbExecute(
    wcon,
    'INSERT INTO "Sample_Admin" ("Plot", "SitePlotQuality") VALUES (\'00401\', \'Good\'), (\'00402\', \'Good\'), (\'00403\', \'Good\')'
  )
  DBI::dbDisconnect(wcon)

  ws <- vpro_connect(db_path)
  pts <- vpro_sf(ws, scope = "project", crs = 3005, audit_geodesy = TRUE)

  expect_s3_class(pts, "sf")
  expect_equal(sf::st_crs(pts)$epsg, 3005L)
  expect_type(pts$PlotNumber, "character")
  expect_true("00337" %in% pts$PlotNumber)
  expect_gt(length(attr(pts, "missing_coords")), 5L)
  expect_true("1976022" %in% attr(pts, "missing_coords"))

  # '00337' had positive Longitude ~ 124 -> flipped to negative!
  p00337 <- pts[pts$PlotNumber == "00337", ]
  expect_true(p00337$sign_flipped)
  expect_lt(p00337$Longitude, -120)
  expect_match(p00337$geodesy_flag, "sign_flipped")

  # '00401' had missing DD -> backfilled from NAD83 UTM Zone 9 and assigned BCGS '093L.054'!
  p401 <- pts[pts$PlotNumber == "00401", ]
  expect_true(p401$utm_backfilled)
  expect_equal(p401$Latitude, 54.55, tolerance = 1e-4)
  expect_equal(p401$Longitude, -127.30, tolerance = 1e-4)
  expect_equal(p401$bcgs_mapsheet_20k, "093L.054")

  # '00402' has <250m divergence (~25m) -> not divergent
  p402 <- pts[pts$PlotNumber == "00402", ]
  expect_false(p402$utm_dd_divergent)
  expect_lt(p402$utm_dd_divergence_m, 250)
  expect_equal(p402$geodesy_flag, "ok")

  # '00403' has positive longitude (flipped) AND ~900m UTM offset (>250m -> divergent)
  p403 <- pts[pts$PlotNumber == "00403", ]
  expect_true(p403$sign_flipped)
  expect_true(p403$utm_dd_divergent)
  expect_gt(p403$utm_dd_divergence_m, 800)
  expect_match(p403$geodesy_flag, "sign_flipped")
  expect_match(p403$geodesy_flag, "utm_dd_divergent")

  # Multi-layer GeoPackage export & roundtrip
  gpkg_path <- file.path(scratch, "bec_export.gpkg")
  ret_path <- vpro_export_gpkg(ws, gpkg_path, crs = 3005, scope = "project", overwrite = TRUE)
  expect_true(file.exists(ret_path))

  layers <- sf::st_layers(gpkg_path)
  expect_setequal(layers$name, c("plots", "veg", "soil_humus", "soil_mineral", "site_units"))

  gpkg_plots <- sf::st_read(gpkg_path, layer = "plots", quiet = TRUE)
  expect_true("00337" %in% gpkg_plots$PlotNumber)
  expect_equal(sf::st_crs(gpkg_plots)$epsg, 3005L)

  gpkg_veg <- sf::st_read(gpkg_path, layer = "veg", quiet = TRUE)
  expect_true("00337" %in% gpkg_veg$PlotNumber)

  expect_error(vpro_export_gpkg(ws, gpkg_path, overwrite = FALSE), "overwrite = FALSE")
})

test_that("vpro_validate(checks = 'lmh25') and vpro_validate detect all 7 pedological rule families and 5 workspace QA checks", {
  scratch <- make_wave2a_scratch_dir("lmh25")
  on.exit(unlink(scratch, recursive = TRUE), add = TRUE)

  db_path <- file.path(scratch, "Sample.db")
  file.copy(vpro_connect("Sample")$project_path, db_path)

  wcon <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  on.exit(if (DBI::dbIsValid(wcon)) DBI::dbDisconnect(wcon), add = TRUE)

  # Plot '00501': substrate_sum (130% != 100%), upland_depth_sign (L 2..8), horizon_contiguity (F 8..5, H 2..0),
  # humus_thickness (header 20 vs max 8), downward_depth_sign (Bm 30..10), invalid SiteDisturbance2 picklist,
  # unlisted species 'NOTASPP', synonym 'THUIABI', and same-layer duplicate ('PSEUMEN' Cover6 twice)
  DBI::dbExecute(
    wcon,
    paste(
      'INSERT INTO "Sample_Env" ("PlotNumber", "SubstrateDecWood", "SubstrateRocks", "SiteDisturbance2", "MoistureRegime", "NutrientRegime", "SoilDrainage", "MesoSlopePosition") VALUES',
      "('00501', 70.0, 60.0, 'BAD_DIST_CODE', '7', 'C', 'r', 'UP'),",
      "('00502', 50.0, 50.0, NULL, '2', 'Z', 'v', 'DP'),",
      "('00503', NULL, NULL, NULL, '4', 'C', 'w', 'MD')"
    )
  )
  # Note: '00503' intentionally has NO Admin row (missing_admin) and NO Veg rows (plot_without_veg),
  # plus an orphan Admin row '00599' and orphan Veg/SU rows
  DBI::dbExecute(
    wcon,
    paste(
      'INSERT INTO "Sample_Admin" ("Plot", "HumusThickness") VALUES',
      "('00501', 20.0), ('00502', NULL), ('00599', 5.0)"
    )
  )
  DBI::dbExecute(
    wcon,
    paste(
      'INSERT INTO "Sample_Humus" ("PlotNumber", "Horizon", "UpperDepth", "LowerDepth", "vonPost") VALUES',
      "('00501', 'L', 2.0, 8.0, NULL),",
      "('00501', 'F', 8.0, 5.0, NULL),",
      "('00501', 'H', 2.0, 0.0, NULL),",
      "('00502', 'Of', 0.0, 20.0, 8),",
      "('00502', 'Om', 25.0, 50.0, 2)"
    )
  )
  DBI::dbExecute(
    wcon,
    paste(
      'INSERT INTO "Sample_Mineral" ("PlotNumber", "Horizon", "UpperDepth", "LowerDepth") VALUES',
      "('00501', 'Bm1', 30.0, 10.0),",
      "('00501', 'Bm2', 0.0, 10.0),",
      "('00501', 'BC', 15.0, 40.0)"
    )
  )
  DBI::dbExecute(
    wcon,
    paste(
      'INSERT INTO "Sample_Veg" ("PlotNumber", "Species", "Cover6") VALUES',
      "('00501', 'NOTASPP', 5.0),",
      "('00501', 'THUIABI', 10.0),",
      "('00501', 'PSEUMEN', 15.0),",
      "('00501', 'PSEUMEN', 25.0),",
      "('00502', 'SPHAGNUM', 40.0),",
      "('ORPH99', 'TSUGHET', 12.0)"
    )
  )
  DBI::dbExecute(
    wcon,
    'INSERT INTO "Sample_SU" ("PlotNumber", "SiteUnit") VALUES (\'00501\', \'CWHvm1/01\'), (\'00502\', \'CWHvm1/11\'), (\'SUORPH\', \'CWHvm1/01\')'
  )
  DBI::dbDisconnect(wcon)

  ws <- vpro_connect(db_path)

  # 1. Test vpro_validate(checks = "lmh25") across all 7 rule families
  val_lmh <- vpro_validate(ws, scope = "project", checks = "lmh25")
  expect_s3_class(val_lmh, "vpro_validation")
  expect_identical(val_lmh$checks, "lmh25")
  aud <- val_lmh$lmh25
  expect_s3_class(aud, "vpro_lmh25_audit")
  expect_message(print.vpro_lmh25_audit(aud), "vpro_lmh25_audit")
  iss <- as_tibble.vpro_lmh25_audit(aud)
  expect_equal(names(iss), c("PlotNumber", "rule", "severity", "detail"))

  all_7_rules <- c(
    "substrate_sum",
    "upland_depth_sign",
    "downward_depth_sign",
    "horizon_contiguity",
    "humus_thickness",
    "von_post",
    "smr_snr_keys"
  )
  for (rl in all_7_rules) {
    expect_true(rl %in% iss$rule, info = paste("Missing LMH25 rule:", rl))
  }

  p501_rules <- iss$rule[iss$PlotNumber == "00501"]
  expect_true(all(c("substrate_sum", "upland_depth_sign", "downward_depth_sign", "horizon_contiguity", "humus_thickness", "smr_snr_keys") %in% p501_rules))
  p502_rules <- iss$rule[iss$PlotNumber == "00502"]
  expect_true(all(c("von_post", "horizon_contiguity", "smr_snr_keys") %in% p502_rules))

  # 2. Test comprehensive vpro_validate()
  val <- vpro_validate(ws, scope = "project")
  expect_s3_class(val, "vpro_validation")
  expect_false(val$passed)
  expect_message(print.vpro_validation(val), "vpro_validation")
  expect_identical(as_tibble.vpro_validation(val), val$issues)

  # Picklist loop expansion caught SiteDisturbance2 = 'BAD_DIST_CODE'
  expect_true(any(val$env_codes$PlotNumber == "00501" & val$env_codes$field == "SiteDisturbance2" & val$env_codes$value == "BAD_DIST_CODE"))

  # Unlisted + synonym vegetation species caught
  expect_true(any(val$veg_codes$PlotNumber == "00501" & val$veg_codes$Species == "NOTASPP" & val$veg_codes$status == "unlisted"))
  expect_true(any(val$veg_codes$PlotNumber == "00501" & val$veg_codes$Species == "THUIABI" & val$veg_codes$status == "synonym" & val$veg_codes$suggested_code == "ABIEABI"))

  # Orphans & missing admin & plots without veg caught
  expect_true(any(val$orphans$PlotNumber == "00503" & val$orphans$issue == "missing_admin"))
  expect_true(any(val$orphans$PlotNumber == "00599" & val$orphans$issue == "orphan_admin"))
  expect_true(any(val$orphans$PlotNumber == "ORPH99" & val$orphans$table == "Veg" & val$orphans$issue == "orphan_child"))
  expect_true(any(val$orphans$PlotNumber == "SUORPH" & val$orphans$table == "SU" & val$orphans$issue == "orphan_su"))
  expect_true(any(val$orphans$PlotNumber == "00503" & val$orphans$issue == "plot_without_veg"))

  # Duplicate physical (PlotNumber, Species, Layer) caught
  expect_true(any(val$duplicates$PlotNumber == "00501" & val$duplicates$Species == "PSEUMEN" & val$duplicates$same_layer_conflict & val$duplicates$overlapping_layers == "6"))
})
