test_that("vpro_render_guide compiles self-contained BC Gov HTML guides across all 4 templates", {
  ws <- vpro_connect("Sample")

  for (tp in c("single_unit", "bgc_unit", "veg_summary", "qc_audit")) {
    out_html <- tempfile(paste0("guide-", tp, "-"), fileext = ".html")
    on.exit(unlink(out_html), add = TRUE)

    art <- vpro_render_guide(
      ws,
      type = tp,
      output_file = out_html,
      force_offline = TRUE
    )
    expect_s3_class(art, "vpro_guide_artifact")
    expect_true(file.exists(art$path))
    expect_gt(art$size_bytes, 1000)
    expect_equal(nchar(art$sha256), 64L)
    html_txt <- paste(readLines(art$path, warn = FALSE), collapse = "\n")
    expect_match(html_txt, "#003366")
    expect_message(print(art), "vpro_guide_artifact")
  }
})

test_that(".vpro_sidecar_exec preserves 100% JSON schema parity with vpro desktop rsidecar", {
  ws <- vpro_connect("Sample")

  # 1. probe_runtime
  probe_out <- tempfile("probe-", fileext = ".json")
  on.exit(unlink(probe_out), add = TRUE)
  p_res <- vpro:::.vpro_sidecar_exec("probe_runtime", output_json = probe_out)
  expect_true(p_res$ok)
  expect_true(file.exists(probe_out))
  parsed_probe <- jsonlite::fromJSON(probe_out)
  expect_true(all(c("ok", "rVersion", "packages", "climrRastersCached") %in% names(parsed_probe)))

  # 2. compute_climate_asmr
  h1 <- vpro:::.vpro_coord_elev_hash(54.25, -126.75, 650, "1961_1990")
  clim_req <- jsonlite::toJSON(list(
    projectPath = ws$project_path,
    projectName = "Sample",
    refPeriod = "1961_1990",
    forceOfflineModel = TRUE,
    uncachedPoints = list(
      list(coordElevHash = h1, lat = 54.25, lon = -126.75, elev = 650, bgc = "SBSdk", zone = "SBS")
    ),
    plots = list(
      list(plotNumber = "00337", coordElevHash = h1, rsmr = "4", slope = 40, aspect = 210)
    )
  ), auto_unbox = TRUE)
  clim_out <- tempfile("clim-", fileext = ".json")
  on.exit(unlink(clim_out), add = TRUE)
  c_res <- vpro:::.vpro_sidecar_exec("compute_climate_asmr", clim_req, output_json = clim_out)
  expect_true(c_res$ok)
  expect_true(c_res$vproCompatible)
  expect_length(c_res$computedNormals, 1L)
  expect_length(c_res$plotEvaluations, 1L)
  expect_equal(c_res$plotEvaluations[[1L]]$plotNumber, "00337")
  expect_equal(c_res$plotEvaluations[[1L]]$aspectFactor, 1.25)
  expect_true(is.finite(c_res$plotEvaluations[[1L]]$asmr))

  # 3. run_clustering (NC k=4 excluding CL_Noise from silhouette, plus BETA_FLEXIBLE & PAM)
  cl_req <- list(
    projectPath = ws$project_path,
    projectName = "Sample",
    vlistsPath = ws$vlists_path,
    method = "NC",
    distance = "bray",
    linkage = "ward.D2",
    transform = "sqrt",
    k = 4L,
    applyLump = TRUE,
    lumpTable = "Sample_Lump",
    unitPrefix = "CL"
  )
  cl_out <- tempfile("clust-", fileext = ".json")
  on.exit(unlink(cl_out), add = TRUE)
  cl_res <- vpro:::.vpro_sidecar_exec("run_clustering", cl_req, output_json = cl_out)
  expect_true(cl_res$ok)
  expect_equal(cl_res$k, 4L)
  expect_gt(cl_res$plotCount, 40L)
  expect_gt(cl_res$noiseCount, 0L)
  expect_equal(cl_res$meanSilhouette, 0.1464, tolerance = 0.005)
  expect_true("00337" %in% vapply(cl_res$memberships, `[[`, character(1), "plotNumber"))
  expect_true(all(c("maxHeight", "cutHeight", "segments", "leaves", "newick") %in% names(cl_res$dendrogram)))

  bf_res <- vpro:::.vpro_sidecar_exec("run_clustering", list(
    projectPath = ws$project_path,
    projectName = "Sample",
    vlistsPath = ws$vlists_path,
    method = "BETA_FLEXIBLE",
    beta = -0.25,
    distance = "bray",
    transform = "sqrt",
    k = 4L,
    applyLump = TRUE,
    lumpTable = "Sample_Lump"
  ))
  expect_true(bf_res$ok)
  expect_equal(bf_res$method, "BETA_FLEXIBLE")

  pam_res <- vpro:::.vpro_sidecar_exec("run_clustering", list(
    projectPath = ws$project_path,
    projectName = "Sample",
    vlistsPath = ws$vlists_path,
    method = "PAM",
    distance = "bray",
    transform = "sqrt",
    k = 4L,
    applyLump = TRUE,
    lumpTable = "Sample_Lump"
  ))
  expect_true(pam_res$ok)
  expect_equal(pam_res$method, "PAM")

  # 4. render_guide (BC Gov Navy/Gold + BC Sans styling)
  g_html <- tempfile("sidecar-guide-", fileext = ".html")
  on.exit(unlink(g_html), add = TRUE)
  g_res <- vpro:::.vpro_sidecar_exec("render_guide", list(
    projectPath = ws$project_path,
    projectName = "Sample",
    guideType = "single_unit",
    destinationPath = g_html,
    forceOfflineModel = TRUE
  ))
  expect_true(g_res$ok)
  expect_true(file.exists(g_res$htmlPath))
  expect_gt(g_res$speciesRowCount, 0L)
  g_txt <- paste(readLines(g_res$htmlPath, warn = FALSE), collapse = "\n")
  expect_match(g_txt, "#003366")
  expect_match(g_txt, "#FCBA19")
  expect_match(g_txt, "BC Sans")
})
