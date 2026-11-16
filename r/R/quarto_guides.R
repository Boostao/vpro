# Reproducible B.C. Government Quarto BEC Ecosystem Guides ---------------------

vpro_five_num_stat <- function(vals, label) {
  clean <- as.double(vals[!is.na(vals) & is.finite(vals)])
  if (length(clean) == 0L) {
    return(NULL)
  }
  qs <- as.numeric(stats::quantile(clean, probs = c(0, 0.25, 0.5, 0.75, 1), names = FALSE))
  list(
    metric = as.character(label),
    n = as.integer(length(clean)),
    min = round(qs[[1L]], 1),
    q1 = round(qs[[2L]], 1),
    median = round(qs[[3L]], 1),
    q3 = round(qs[[4L]], 1),
    max = round(qs[[5L]], 1)
  )
}

vpro_aspect_rose_sectors <- function(aspects) {
  labels <- c("N", "NE", "E", "SE", "S", "SW", "W", "NW")
  counts <- integer(8L)
  v <- suppressWarnings(as.double(aspects))
  v <- v[!is.na(v) & is.finite(v) & v >= 0 & v <= 360 & v != 999]
  if (length(v) > 0L) {
    norm <- (v + 360.0) %% 360.0
    idx <- (as.integer(floor((norm + 22.5) / 45.0)) %% 8L) + 1L
    for (k in idx) {
      counts[[k]] <- counts[[k]] + 1L
    }
  }
  lapply(seq_along(labels), function(i) {
    list(sector = labels[[i]], count = as.integer(counts[[i]]))
  })
}

vpro_build_guide_payload <- function(
  ws,
  type = c("single_unit", "bgc_unit", "veg_summary", "qc_audit"),
  unit = NULL,
  bgc = NULL,
  title = NULL,
  concept_notes = NULL,
  ref_period = "1961_1990",
  min_constancy = 20,
  lump = TRUE,
  force_offline = FALSE
) {
  type <- match.arg(type)
  if (identical(type, "qc_audit")) {
    val <- vpro_validate(ws, scope = if (!is.null(ws$su)) "su" else "project")
    env_df <- vpro_env(ws, scope = if (!is.null(ws$su)) "su" else "project")
    iss <- val$issues
    cats <- unique(iss$category)
    cat_list <- lapply(cats, function(ct) {
      sub <- iss[iss$category == ct, , drop = FALSE]
      list(
        category = ct,
        errors = as.integer(sum(sub$severity == "error", na.rm = TRUE)),
        warnings = as.integer(sum(sub$severity != "error", na.rm = TRUE)),
        total = as.integer(nrow(sub))
      )
    })
    iss_sub <- utils::head(iss, 250L)
    iss_list <- lapply(seq_len(nrow(iss_sub)), function(i) {
      list(
        plotNumber = as.character(iss_sub$PlotNumber[[i]]),
        category = as.character(iss_sub$category[[i]]),
        rule = as.character(iss_sub$rule[[i]]),
        severity = as.character(iss_sub$severity[[i]]),
        detail = as.character(iss_sub$detail[[i]])
      )
    })
    return(list(
      guideType = type,
      title = if (!is.null(title) && nzchar(title)) title else paste0("VPro Standards & LMH25 Audit - ", ws$project),
      project = ws$project,
      targetUnit = "",
      bgcLabel = "",
      plotCount = as.integer(nrow(env_df)),
      speciesRowCount = 0L,
      issueCount = as.integer(nrow(iss)),
      categoryCounts = cat_list,
      issues = iss_list,
      vegetationTable = list()
    ))
  }

  env_df <- vpro_env(ws, scope = if (!is.null(ws$su)) "su" else "project", exclude_modifiers = TRUE)
  asmr_df <- vpro_asmr(
    ws,
    scope = if (!is.null(ws$su)) "su" else "project",
    ref_period = ref_period,
    cache = FALSE,
    force_offline = force_offline
  )

  # Optional unit / BGC filtering
  if (!is.null(bgc) && nzchar(trimws(bgc))) {
    bgc_req <- toupper(gsub("[[:space:]]+", "", bgc))
    env_bgc <- toupper(gsub("[[:space:]]+", "", paste0(ifelse(is.na(env_df$Zone), "", env_df$Zone), ifelse(is.na(env_df$SubZone), "", env_df$SubZone))))
    keep_p <- env_df$PlotNumber[env_bgc == bgc_req | toupper(ifelse(is.na(env_df$Zone), "", env_df$Zone)) == bgc_req]
    env_df <- env_df[env_df$PlotNumber %in% keep_p, , drop = FALSE]
  }

  target_unit <- ""
  if (identical(type, "single_unit")) {
    avail_units <- sort(unique(env_df$SiteUnit[!is.na(env_df$SiteUnit) & nzchar(trimws(env_df$SiteUnit))]))
    if (!is.null(unit) && nzchar(trimws(unit))) {
      target_unit <- trimws(as.character(unit))
      env_df <- env_df[!is.na(env_df$SiteUnit) & env_df$SiteUnit == target_unit, , drop = FALSE]
    } else if (length(avail_units) > 0L) {
      target_unit <- avail_units[[1L]]
      env_df <- env_df[!is.na(env_df$SiteUnit) & env_df$SiteUnit == target_unit, , drop = FALSE]
    } else {
      target_unit <- ws$project
    }
  }

  plots_keep <- env_df$PlotNumber
  asmr_sub <- asmr_df[asmr_df$PlotNumber %in% plots_keep, , drop = FALSE]
  n_plots <- nrow(env_df)

  bgc_vals <- gsub("[[:space:]]+", "", paste0(ifelse(is.na(env_df$Zone), "", env_df$Zone), ifelse(is.na(env_df$SubZone), "", env_df$SubZone)))
  bgc_vals <- bgc_vals[nzchar(bgc_vals)]
  bgc_label <- if (!is.null(bgc) && nzchar(trimws(bgc))) {
    trimws(bgc)
  } else if (length(bgc_vals) > 0L) {
    names(sort(table(bgc_vals), decreasing = TRUE))[[1L]]
  } else {
    "All"
  }

  # Relative & Actual edatopic cell counts across kept plots
  make_grid_cells <- function(smr_vec, snr_vec) {
    smr_i <- suppressWarnings(as.integer(round(as.numeric(smr_vec))))
    snr_c <- toupper(substr(trimws(ifelse(is.na(snr_vec), "", as.character(snr_vec))), 1L, 1L))
    ok <- !is.na(smr_i) & smr_i >= 0L & smr_i <= 8L & snr_c %in% c("A", "B", "C", "D", "E")
    if (!any(ok)) {
      return(list())
    }
    tab <- as.data.frame(table(smr = smr_i[ok], snr = snr_c[ok]), stringsAsFactors = FALSE)
    tab <- tab[tab$Freq > 0L, , drop = FALSE]
    lapply(seq_len(nrow(tab)), function(i) {
      list(smr = as.character(tab$smr[[i]]), snr = as.character(tab$snr[[i]]), count = as.integer(tab$Freq[[i]]))
    })
  }
  rel_cells <- make_grid_cells(asmr_sub$rSMR, asmr_sub$rSNR)
  act_cells <- make_grid_cells(asmr_sub$aSMR, asmr_sub$rSNR)

  env_stats <- Filter(
    Negate(is.null),
    list(
      vpro_five_num_stat(env_df$Elevation, "Elevation (m)"),
      vpro_five_num_stat(env_df$SlopeGradient, "Slope Gradient (%)"),
      vpro_five_num_stat(asmr_sub$MAT, "MAT (deg C)"),
      vpro_five_num_stat(asmr_sub$MAP, "MAP (mm)"),
      vpro_five_num_stat(asmr_sub$CMD, "Annual CMD (mm)"),
      vpro_five_num_stat(asmr_sub$aSMR, "Modeled aSMR")
    )
  )

  # Characteristic vegetation summary across kept plots
  veg_abcd <- vpro_veg(
    ws,
    scope = if (!is.null(ws$su)) "su" else "project",
    lump = lump,
    strata = "abcd",
    exclude_modifiers = TRUE
  )
  veg_abcd <- veg_abcd[veg_abcd$PlotNumber %in% plots_keep, , drop = FALSE]
  veg_rows <- list()
  if (nrow(veg_abcd) > 0L && n_plots > 0L) {
    vdt <- data.table::as.data.table(veg_abcd)
    agg <- vdt[,
      list(
        n_pres = length(unique(get("PlotNumber"))),
        sum_cov = sum(get("Cover"), na.rm = TRUE),
        sci = get("ScientificName")[[1L]],
        eng = get("EnglishName")[[1L]]
      ),
      by = c("Strata", "Species")
    ]
    agg$const_pct <- (agg$n_pres / n_plots) * 100.0
    agg$mean_cov <- agg$sum_cov / agg$n_pres
    agg <- agg[agg$const_pct >= min_constancy]
    if (nrow(agg) > 0L) {
      ord <- order(match(agg$Strata, c("A", "B", "C", "D")), -agg$const_pct, -agg$mean_cov)
      agg <- agg[ord]
      p_cls <- vpro_presence_class(pmin(1.0, agg$const_pct / 100.0))
      veg_rows <- lapply(seq_len(nrow(agg)), function(i) {
        list(
          layer = as.character(agg$Strata[[i]]),
          species = as.character(agg$Species[[i]]),
          scientificName = ifelse(is.na(agg$sci[[i]]), "", as.character(agg$sci[[i]])),
          englishName = ifelse(is.na(agg$eng[[i]]), "", as.character(agg$eng[[i]])),
          constancyPct = round(as.numeric(agg$const_pct[[i]]), 1),
          constancyClass = ifelse(is.na(p_cls[[i]]), "I", p_cls[[i]]),
          meanCover = round(as.numeric(agg$mean_cov[[i]]), 1)
        )
      })
    }
  }

  # Per-unit summaries for bgc_unit & veg_summary
  unit_list <- list()
  u_names <- sort(unique(env_df$SiteUnit[!is.na(env_df$SiteUnit) & nzchar(trimws(env_df$SiteUnit))]))
  if (length(u_names) > 0L) {
    modal_chr <- function(x) {
      ok <- x[!is.na(x) & nzchar(trimws(as.character(x)))]
      if (length(ok) == 0L) "-" else names(sort(table(ok), decreasing = TRUE))[[1L]]
    }
    unit_list <- lapply(u_names, function(u) {
      sub <- env_df[!is.na(env_df$SiteUnit) & env_df$SiteUnit == u, , drop = FALSE]
      el <- suppressWarnings(as.numeric(sub$Elevation))
      list(
        siteUnit = u,
        nPlots = as.integer(nrow(sub)),
        meanElev = if (any(!is.na(el))) round(mean(el, na.rm = TRUE), 0) else NA_real_,
        modalSmr = modal_chr(sub$MoistureRegime),
        modalSnr = modal_chr(sub$NutrientRegime)
      )
    })
  }

  default_title <- switch(
    type,
    single_unit = paste0("BEC Site Unit Guide: ", target_unit),
    bgc_unit = paste0("BEC Subzone Synopsis: ", bgc_label),
    veg_summary = paste0("BEC Vegetation Synthesis: ", ws$project)
  )

  list(
    guideType = type,
    title = if (!is.null(title) && nzchar(trimws(title))) trimws(title) else default_title,
    project = ws$project,
    targetUnit = target_unit,
    bgcLabel = bgc_label,
    refPeriod = ref_period,
    conceptNotes = if (is.null(concept_notes)) "" else as.character(concept_notes),
    plotCount = as.integer(n_plots),
    speciesRowCount = as.integer(length(veg_rows)),
    relativeGrid = rel_cells,
    actualGrid = act_cells,
    aspectRose = vpro_aspect_rose_sectors(env_df$Aspect),
    envStats = env_stats,
    unitSummaries = unit_list,
    vegetationTable = veg_rows
  )
}

#' Render a B.C. Government Quarto BEC ecosystem guide or QC audit report
#'
#' Compiles one of the bundled B.C. Government Quarto report templates
#' (`unit_guide.qmd`, `bgc_synopsis.qmd`, `veg_summary_book.qmd`, or
#' `qc_audit.qmd`) styled with self-hosted `BC Sans` `.woff2` typography and
#' `#003366` Navy / `#FCBA19` Gold accents. Automatically falls back to
#' `rmarkdown::render()` for HTML output when the `quarto` CLI is unavailable.
#'
#' @param ws A `vpro_workspace` handle.
#' @param type Guide template: `"single_unit"`, `"bgc_unit"`, `"veg_summary"`,
#'   or `"qc_audit"`.
#' @param unit Optional `SiteUnit` name when `type = "single_unit"`.
#' @param bgc Optional BGC zone/subzone filter (e.g. `"CWHvm1"` or `"SBS"`).
#' @param format Output format: `"html"` (self-contained single file) or `"pdf"`.
#' @param output_file Destination file path. Defaults to a temporary `.html` or
#'   `.pdf` path.
#' @param title Optional custom report title.
#' @param concept_notes Optional ecological concept text block.
#' @param ref_period Climate normal period (`"1961_1990"` or `"1991_2020"`).
#' @param min_constancy Minimum species constancy percentage (`0..100`, default `20`).
#' @param lump Logical; whether to apply active species lumping.
#' @param force_offline Logical; if `TRUE`, uses the offline BGC lapse climate model.
#' @return An S3 object of class `vpro_guide_artifact` containing `path`,
#'   `type`, `format`, `title`, `plot_count`, `species_rows`, `renderer`,
#'   `size_bytes`, `sha256`, and `payload`.
#' @export
vpro_render_guide <- function(
  ws,
  type = c("single_unit", "bgc_unit", "veg_summary", "qc_audit"),
  unit = NULL,
  bgc = NULL,
  format = c("html", "pdf"),
  output_file = NULL,
  title = NULL,
  concept_notes = NULL,
  ref_period = "1961_1990",
  min_constancy = 20,
  lump = TRUE,
  force_offline = FALSE
) {
  vpro_assert_workspace(ws)
  type <- match.arg(type)
  format <- match.arg(format)

  template_file <- switch(
    type,
    single_unit = "unit_guide.qmd",
    bgc_unit = "bgc_synopsis.qmd",
    veg_summary = "veg_summary_book.qmd",
    qc_audit = "qc_audit.qmd"
  )
  template_src <- vpro_bundled_file("quarto", template_file)
  theme_assets <- vpro_bcgov_theme("assets")

  if (is.null(output_file) || !nzchar(trimws(output_file))) {
    output_file <- tempfile(pattern = paste0("vpro-", type, "-"), fileext = paste0(".", format))
  }
  output_file <- vpro_abs_path(output_file)
  out_ext <- tolower(tools::file_ext(output_file))
  protected_dbs <- c(ws$project_path, ws$su_path, ws$vlists_path, ws$vuser_path, ws$vpro64_path, ws$vmetadata_path)
  if (out_ext %in% c("db", "sqlite", "sqlite3", "accdb", "mdb") || output_file %in% protected_dbs) {
    rlang::abort(paste0("Refusing to write rendered guide over a database path: ", output_file))
  }
  dir.create(dirname(output_file), recursive = TRUE, showWarnings = FALSE)

  payload <- vpro_build_guide_payload(
    ws = ws,
    type = type,
    unit = unit,
    bgc = bgc,
    title = title,
    concept_notes = concept_notes,
    ref_period = ref_period,
    min_constancy = min_constancy,
    lump = lump,
    force_offline = force_offline
  )

  work_dir <- tempfile("vpro-quarto-stage-")
  dir.create(file.path(work_dir, "fonts"), recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(work_dir, recursive = TRUE), add = TRUE)

  staged_qmd <- file.path(work_dir, template_file)
  file.copy(template_src, staged_qmd, overwrite = TRUE)
  file.copy(theme_assets$css_path, file.path(work_dir, "bcgov.css"), overwrite = TRUE)
  for (wf in theme_assets$woff2) {
    file.copy(wf, file.path(work_dir, "fonts", basename(wf)), overwrite = TRUE)
  }

  payload_path <- file.path(work_dir, "guide_payload.json")
  jsonlite::write_json(payload, path = payload_path, auto_unbox = TRUE, pretty = FALSE, null = "null")

  rendered_path <- file.path(work_dir, paste0(tools::file_path_sans_ext(template_file), ".", format))
  renderer_used <- "quarto"
  quarto_bin <- Sys.which("quarto")

  rendered_ok <- FALSE
  if (nzchar(quarto_bin)) {
    run_quarto_in_stage <- function() {
      old_wd <- getwd()
      on.exit(setwd(old_wd), add = TRUE)
      setwd(work_dir)
      out <- system2(
        quarto_bin,
        c("render", template_file, "--to", format, "--quiet"),
        stdout = TRUE,
        stderr = TRUE
      )
      attr(out, "status")
    }
    res_status <- tryCatch(run_quarto_in_stage(), error = function(e) 1L)
    if ((is.null(res_status) || identical(res_status, 0L)) && file.exists(rendered_path)) {
      rendered_ok <- TRUE
    }
  }

  if (!rendered_ok) {
    if (identical(format, "pdf")) {
      rlang::abort("PDF rendering requires Quarto + a working LaTeX/Typst engine, which failed or was not found.")
    }
    rlang::check_installed("rmarkdown", reason = "to render BEC HTML guides when Quarto CLI is unavailable.")
    renderer_used <- "rmarkdown_fallback"
    staged_rmd <- file.path(work_dir, "fallback_guide.Rmd")
    qmd_lines <- readLines(staged_qmd, warn = FALSE)
    yaml_ends <- which(trimws(qmd_lines) == "---")
    body_lines <- if (length(yaml_ends) >= 2L) qmd_lines[(yaml_ends[[2L]] + 1L):length(qmd_lines)] else qmd_lines
    yml_str <- yaml::as.yaml(list(
      title = as.character(payload$title),
      output = list(html_document = list(self_contained = TRUE, theme = NULL, css = "bcgov.css")),
      params = list(payload_json = "guide_payload.json")
    ))
    rmd_header <- c("---", sub("\n$", "", yml_str), "---", "")
    writeLines(c(rmd_header, body_lines), staged_rmd, useBytes = TRUE)
    rendered_path <- rmarkdown::render(
      input = staged_rmd,
      output_file = "fallback_guide.html",
      output_dir = work_dir,
      params = list(payload_json = payload_path),
      quiet = TRUE,
      envir = new.env(parent = globalenv())
    )
  }

  tmp_pub <- tempfile("vpro-guide-pub-", tmpdir = dirname(output_file), fileext = paste0(".", format))
  on.exit(unlink(tmp_pub), add = TRUE)
  if (
    !file.copy(rendered_path, tmp_pub, overwrite = TRUE) ||
      (!file.rename(tmp_pub, output_file) && !file.copy(tmp_pub, output_file, overwrite = TRUE))
  ) {
    rlang::abort(paste0("Failed to publish rendered guide to: ", output_file))
  }

  structure(
    list(
      path = output_file,
      type = type,
      format = format,
      title = payload$title,
      target_unit = payload$targetUnit,
      bgc_label = payload$bgcLabel,
      plot_count = payload$plotCount,
      species_rows = payload$speciesRowCount,
      renderer = renderer_used,
      size_bytes = as.numeric(file.info(output_file)$size),
      sha256 = vpro_sha256_file(output_file),
      payload = payload
    ),
    class = "vpro_guide_artifact"
  )
}

#' @export
print.vpro_guide_artifact <- function(x, ...) {
  cli::cli_h3("vpro_guide_artifact: {.val {x$title}}")
  cli::cli_bullets(c(
    "*" = "File: {.path {x$path}} ({round(x$size_bytes / 1024, 1)} KB, renderer: {x$renderer})",
    "*" = "Type: {.val {x$type}} | Plots: {x$plot_count} | Characteristic species rows: {x$species_rows}"
  ))
  invisible(x)
}
