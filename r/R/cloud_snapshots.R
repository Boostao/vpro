# BECMaster Snapshot Publication & Portable RDS Project Bundles ----------------

.vpro_snap_s3_state <- new.env(parent = emptyenv())

.vpro_register_snap_s3 <- function() {
  if (isTRUE(.vpro_snap_s3_state$registered)) {
    return(invisible(NULL))
  }
  pkg_env <- environment(.vpro_register_snap_s3)
  reg_one <- function(gen_pkg, gen_name, cls) {
    fn_name <- paste0(gen_name, ".", cls)
    if (!exists(fn_name, envir = pkg_env, mode = "function", inherits = FALSE)) {
      return(invisible(NULL))
    }
    gen_env <- asNamespace(gen_pkg)
    s3_tbl <- gen_env[[".__S3MethodsTable__."]]
    if (is.environment(s3_tbl) && !exists(fn_name, envir = s3_tbl, inherits = FALSE)) {
      base::registerS3method(gen_name, cls, get(fn_name, envir = pkg_env), envir = gen_env)
    }
    invisible(NULL)
  }

  reg_one("base", "print", "vpro_rds_project")
  reg_one("tibble", "as_tibble", "vpro_rds_project")

  .vpro_snap_s3_state$registered <- TRUE
  invisible(NULL)
}

.vpro_default_bec_version <- "BECdb_v13_2026"
.vpro_default_taxonomy_version <- "BCPlantTaxa_v19_2025"
.vpro_valid_snapshot_formats <- c("rds", "sqlite", "gpkg", "csv")

# Internal Validation, Project Naming & Canonicalization Helpers ---------------

vpro_validate_snapshot_tag <- function(snapshot_tag, arg_name = "snapshot_tag") {
  if (!is.character(snapshot_tag) || length(snapshot_tag) != 1L || is.na(snapshot_tag)) {
    cli::cli_abort("{.arg {arg_name}} must be a single non-empty ASCII string.")
  }
  tag <- trimws(snapshot_tag)
  if (!grepl("^[A-Za-z0-9._-]{1,80}$", tag) || tag %in% c(".", "..")) {
    cli::cli_abort(
      "{.arg {arg_name}} must be 1..80 characters containing only ASCII letters, digits, {.val .}, {.val _}, or {.val -}."
    )
  }
  tag
}

vpro_snapshot_project_prefix <- function(raw_name, fallback = "Snap_Project", guard_reserved = TRUE) {
  s <- if (is.character(raw_name) && length(raw_name) >= 1L && !is.na(raw_name[[1L]])) {
    gsub("[^A-Za-z0-9_]", "_", trimws(raw_name[[1L]]))
  } else {
    ""
  }
  s <- gsub("_+", "_", s)
  s <- sub("^_+", "", s)
  s <- sub("_+$", "", s)
  if (!nzchar(s)) {
    s <- fallback
  }
  needs_prefix <- !grepl("^[A-Za-z]", s) || (
    isTRUE(guard_reserved) && (
      tolower(s) %in% c("none", "sample") ||
      grepl("master", s, ignore.case = TRUE)
    )
  )
  if (needs_prefix) {
    s <- paste0("Snap_", s)
  }
  s <- substr(s, 1L, 31L)
  s <- sub("_+$", "", s)
  if (!nzchar(s) || !grepl("^[A-Za-z]", s)) {
    s <- "Snap_Project"
  }
  vpro_project_name(s)
}

vpro_preserve_or_assign_unique_ids <- function(ids_raw, start_id = 100000000L, require_positive = FALSE) {
  n <- length(ids_raw)
  if (n == 0L) {
    return(integer())
  }
  nums <- suppressWarnings(as.double(ids_raw))
  used_env <- new.env(hash = TRUE, parent = emptyenv())
  next_id <- as.double(start_id)
  out <- numeric(n)

  for (i in seq_len(n)) {
    v <- nums[[i]]
    valid <- !is.na(v) && is.finite(v) && v == trunc(v) &&
      v > -2147483648 && v <= 2147483647 &&
      (!isTRUE(require_positive) || v >= 1)
    key <- if (valid) sprintf("%.0f", v) else ""
    if (!valid || exists(key, envir = used_env, inherits = FALSE)) {
      repeat {
        cand_key <- sprintf("%.0f", next_id)
        if (!exists(cand_key, envir = used_env, inherits = FALSE)) {
          v <- next_id
          key <- cand_key
          next_id <- next_id + 1
          break
        }
        next_id <- next_id + 1
      }
    }
    assign(key, TRUE, envir = used_env)
    out[[i]] <- v
  }
  as.integer(out)
}

vpro_is_none_selector <- function(x) {
  identical(x, FALSE) || (
    is.character(x) && length(x) == 1L && !is.na(x) &&
      identical(tolower(trimws(x)), "none")
  )
}

vpro_assert_char_plot_key <- function(df, col_name, table_label) {
  if (is.null(df) || !is.data.frame(df) || nrow(df) == 0L) {
    return(invisible(NULL))
  }
  nms <- names(df)
  idx <- match(tolower(col_name), tolower(nms))
  if (is.na(idx)) {
    return(invisible(NULL))
  }
  v <- df[[idx]]
  if (is.numeric(v) && any(!is.na(v))) {
    cli::cli_abort(
      "Column {.field {col_name}} in RDS table {.val {table_label}} must be {.cls character} (not numeric) to preserve leading-zero PlotNumbers like {.val 00337}."
    )
  }
  invisible(NULL)
}

vpro_derive_su_from_env_admin <- function(env_tbl, admin_tbl) {
  empty_su <- tibble::tibble(PlotNumber = character(), SiteUnit = character())
  if (is.null(env_tbl) || nrow(env_tbl) == 0L || is.null(admin_tbl) || nrow(admin_tbl) == 0L) {
    return(empty_su)
  }
  env_plots <- as.character(env_tbl$PlotNumber)
  env_plots <- env_plots[!is.na(env_plots) & nzchar(trimws(env_plots))]
  if (length(env_plots) == 0L) {
    return(empty_su)
  }
  adm_plots <- as.character(admin_tbl$Plot)
  bec_su <- if ("BECSiteUnit" %in% names(admin_tbl)) {
    trimws(ifelse(is.na(admin_tbl$BECSiteUnit), "", as.character(admin_tbl$BECSiteUnit)))
  } else {
    rep("", nrow(admin_tbl))
  }
  usr_su <- if ("UserSiteUnit" %in% names(admin_tbl)) {
    trimws(ifelse(is.na(admin_tbl$UserSiteUnit), "", as.character(admin_tbl$UserSiteUnit)))
  } else {
    rep("", nrow(admin_tbl))
  }
  coal <- ifelse(nzchar(bec_su), bec_su, ifelse(nzchar(usr_su), usr_su, NA_character_))
  ix <- match(env_plots, adm_plots)
  matched_su <- ifelse(is.na(ix), NA_character_, coal[ix])
  keep <- !is.na(matched_su) & nzchar(matched_su)
  if (!any(keep)) {
    return(empty_su)
  }
  out <- data.frame(
    PlotNumber = env_plots[keep],
    SiteUnit = matched_su[keep],
    stringsAsFactors = FALSE
  )
  out <- unique(out)
  ord <- order(out$PlotNumber, out$SiteUnit, method = "radix")
  tibble::as_tibble(out[ord, , drop = FALSE])
}

vpro_normalize_su_tibble <- function(su_df) {
  empty_su <- tibble::tibble(PlotNumber = character(), SiteUnit = character())
  if (is.null(su_df) || !is.data.frame(su_df) || nrow(su_df) == 0L) {
    return(empty_su)
  }
  vpro_assert_char_plot_key(su_df, "PlotNumber", "su")
  nms <- tolower(names(su_df))
  p_ix <- match("plotnumber", nms)
  s_ix <- match("siteunit", nms)
  if (is.na(p_ix) || is.na(s_ix)) {
    cli::cli_abort(
      "Site-unit table {.arg su} must contain {.field PlotNumber} and {.field SiteUnit} columns."
    )
  }
  plots <- as.character(su_df[[p_ix]])
  units <- trimws(as.character(su_df[[s_ix]]))
  keep <- !is.na(plots) & nzchar(trimws(plots)) & !is.na(units) & nzchar(units)
  if (!any(keep)) {
    return(empty_su)
  }
  out <- unique(data.frame(
    PlotNumber = plots[keep],
    SiteUnit = units[keep],
    stringsAsFactors = FALSE
  ))
  ord <- order(out$PlotNumber, out$SiteUnit, method = "radix")
  tibble::as_tibble(out[ord, , drop = FALSE])
}

vpro_normalize_lump_tibble <- function(lump_df) {
  empty_lump <- tibble::tibble(
    SppCode = character(),
    LumpCode = character(),
    Use = logical()
  )
  if (is.null(lump_df) || !is.data.frame(lump_df) || nrow(lump_df) == 0L) {
    return(empty_lump)
  }
  nms <- tolower(names(lump_df))
  s_ix <- match("sppcode", nms)
  l_ix <- match("lumpcode", nms)
  if (is.na(s_ix) || is.na(l_ix)) {
    cli::cli_abort(
      "Species lump table {.arg lump} must contain {.field SppCode} and {.field LumpCode} columns."
    )
  }
  u_ix <- match("use", nms)
  spp <- toupper(trimws(as.character(lump_df[[s_ix]])))
  lmp <- toupper(trimws(as.character(lump_df[[l_ix]])))
  use_lgl <- if (is.na(u_ix)) {
    rep(TRUE, nrow(lump_df))
  } else {
    u_raw <- vpro_access_to_logical(lump_df[[u_ix]])
    u_raw[is.na(u_raw)] <- FALSE
    u_raw
  }
  keep <- !is.na(spp) & nzchar(spp) & !is.na(lmp) & nzchar(lmp)
  if (!any(keep)) {
    return(empty_lump)
  }
  out <- data.frame(
    SppCode = spp[keep],
    LumpCode = lmp[keep],
    Use = as.logical(use_lgl[keep]),
    stringsAsFactors = FALSE
  )
  ord <- order(ifelse(out$Use, 0L, 1L), out$LumpCode, out$SppCode)
  out <- out[ord, , drop = FALSE]
  out <- out[!duplicated(out$SppCode), , drop = FALSE]
  out <- out[order(out$LumpCode, out$SppCode), , drop = FALSE]
  tibble::as_tibble(out)
}

vpro_compute_local_audit_tail_hash <- function(audit_tbl) {
  if (is.null(audit_tbl) || nrow(audit_tbl) == 0L) {
    return(.vpro_genesis_audit_hash)
  }
  audit_spec <- vpro_pg_vp08_specs("Audit")
  audit_cols <- as.character(audit_spec$name)
  sq_df <- vpro_pg_canonicalize_to_sqlite(audit_tbl, audit_spec)
  prev <- .vpro_genesis_audit_hash
  for (i in seq_len(nrow(sq_df))) {
    row_vals <- lapply(audit_cols, function(cn) sq_df[[cn]][[i]])
    prev <- vpro_compute_audit_row_hash(prev, "", row_vals)
  }
  prev
}

vpro_read_workspace_vp08_table <- function(dbc, project, suffix) {
  spec <- vpro_pg_vp08_specs(suffix)
  tbl_name <- paste0(project, "_", suffix)
  if (!DBI::dbExistsTable(dbc, tbl_name)) {
    return(vpro_pg_canonicalize_to_tidy(data.frame(), spec))
  }
  actual_fields <- DBI::dbListFields(dbc, tbl_name)
  actual_low <- tolower(actual_fields)
  spec_names <- as.character(spec$name)

  sel_exprs <- vapply(spec_names, function(col) {
    ix <- match(tolower(col), actual_low)
    q_alias <- vpro_quote_ident(col)
    if (is.na(ix)) {
      return(paste0("NULL AS ", q_alias))
    }
    q_src <- vpro_quote_ident(actual_fields[[ix]])
    if (col %in% c("PlotNumber", "Plot")) {
      paste0("CASE WHEN ", q_src, " IS NULL THEN NULL ELSE CAST(", q_src, " AS TEXT) END AS ", q_alias)
    } else {
      paste0(q_src, " AS ", q_alias)
    }
  }, character(1L))

  where_sql <- ""
  order_sql <- ""
  if (identical(suffix, "Env")) {
    where_sql <- ' WHERE typeof("PlotNumber") = \'text\' AND TRIM("PlotNumber") <> \'\''
    order_sql <- ' ORDER BY "PlotNumber"'
  } else if (identical(suffix, "Admin")) {
    where_sql <- ' WHERE typeof("Plot") = \'text\' AND TRIM("Plot") <> \'\''
    order_sql <- ' ORDER BY "Plot"'
  } else if (identical(suffix, "Humus")) {
    where_sql <- ' WHERE typeof("PlotNumber") = \'text\' AND TRIM("PlotNumber") <> \'\''
    order_sql <- paste(
      ' ORDER BY "PlotNumber",',
      'CASE WHEN LOWER(TRIM(COALESCE("Horizon", \'\'))) GLOB \'o[fmh]*\' THEN 1 ELSE 0 END ASC,',
      'CASE WHEN LOWER(TRIM(COALESCE("Horizon", \'\'))) GLOB \'o[fmh]*\' THEN "UpperDepth" ELSE -"UpperDepth" END ASC,',
      '"Horizon" DESC, "ID"'
    )
  } else if (identical(suffix, "Mineral")) {
    where_sql <- ' WHERE typeof("PlotNumber") = \'text\' AND TRIM("PlotNumber") <> \'\''
    order_sql <- ' ORDER BY "PlotNumber", "UpperDepth" ASC, "Horizon" ASC, "ID"'
  } else if (suffix %in% c("Veg", "Other")) {
    where_sql <- ' WHERE typeof("PlotNumber") = \'text\' AND TRIM("PlotNumber") <> \'\''
    order_sql <- if ("id" %in% actual_low) ' ORDER BY "PlotNumber", "ID"' else ' ORDER BY "PlotNumber"'
  } else if (suffix %in% c("Metadata", "Audit")) {
    order_sql <- if ("id" %in% actual_low) ' ORDER BY "ID"' else ""
  }

  sql <- paste0(
    "SELECT ", paste(sel_exprs, collapse = ", "),
    " FROM ", vpro_quote_ident(tbl_name),
    where_sql,
    order_sql
  )
  raw_df <- DBI::dbGetQuery(dbc, sql)
  tidy_tbl <- vpro_pg_canonicalize_to_tidy(raw_df, spec)
  if ("PlotNumber" %in% names(tidy_tbl)) {
    tidy_tbl$PlotNumber <- as.character(tidy_tbl$PlotNumber)
  }
  if ("Plot" %in% names(tidy_tbl)) {
    tidy_tbl$Plot <- as.character(tidy_tbl$Plot)
  }
  tidy_tbl
}

vpro_extract_workspace_snapshot_tables <- function(con_ws) {
  vpro_assert_workspace(con_ws)
  dbc <- vpro_sqlite_ro(con_ws$project_path)
  on.exit(DBI::dbDisconnect(dbc), add = TRUE)

  prj <- con_ws$project
  env_tbl <- vpro_read_workspace_vp08_table(dbc, prj, "Env")
  admin_tbl <- vpro_read_workspace_vp08_table(dbc, prj, "Admin")
  veg_tbl <- vpro_read_workspace_vp08_table(dbc, prj, "Veg")
  humus_tbl <- vpro_read_workspace_vp08_table(dbc, prj, "Humus")
  mineral_tbl <- vpro_read_workspace_vp08_table(dbc, prj, "Mineral")
  other_tbl <- vpro_read_workspace_vp08_table(dbc, prj, "Other")
  metadata_tbl <- vpro_read_workspace_vp08_table(dbc, prj, "Metadata")
  audit_tbl <- vpro_read_workspace_vp08_table(dbc, prj, "Audit")

  su_tbl <- if (!is.null(con_ws$su)) {
    vpro_normalize_su_tibble(vpro_site_units(con_ws, exclude_modifiers = FALSE))
  } else {
    vpro_derive_su_from_env_admin(env_tbl, admin_tbl)
  }

  lump_tbl <- vpro_normalize_lump_tibble(NULL)
  if (!is.null(con_ws$lump) && nzchar(con_ws$lump) &&
      !is.null(con_ws$lump_path) && file.exists(con_ws$lump_path)) {
    dbc_lump <- if (identical(con_ws$lump_path, con_ws$project_path)) {
      dbc
    } else {
      vpro_sqlite_ro(con_ws$lump_path)
    }
    if (!identical(con_ws$lump_path, con_ws$project_path)) {
      on.exit(DBI::dbDisconnect(dbc_lump), add = TRUE)
    }
    if (DBI::dbExistsTable(dbc_lump, con_ws$lump)) {
      lump_fields <- tolower(DBI::dbListFields(dbc_lump, con_ws$lump))
      use_expr <- if ("use" %in% lump_fields) '"Use"' else "1 AS \"Use\""
      raw_lump <- DBI::dbGetQuery(
        dbc_lump,
        paste0(
          'SELECT UPPER(TRIM(CAST("SppCode" AS TEXT))) AS "SppCode", ',
          'UPPER(TRIM(CAST("LumpCode" AS TEXT))) AS "LumpCode", ',
          use_expr, " FROM ", vpro_quote_ident(con_ws$lump)
        )
      )
      lump_tbl <- vpro_normalize_lump_tibble(raw_lump)
    }
  }

  list(
    env = env_tbl,
    admin = admin_tbl,
    veg = veg_tbl,
    humus = humus_tbl,
    mineral = mineral_tbl,
    other = other_tbl,
    metadata = metadata_tbl,
    audit = audit_tbl,
    su = su_tbl,
    lump = lump_tbl
  )
}

# Pivot vpro_wails ExportProjectRDS veg_long -> 44-col VP08 Veg ----------------

vpro_pivot_veg_long_to_vp08 <- function(veg_long_df) {
  veg_spec <- vpro_pg_vp08_specs("Veg")
  if (is.null(veg_long_df) || !is.data.frame(veg_long_df) || nrow(veg_long_df) == 0L) {
    return(vpro_pg_canonicalize_to_tidy(data.frame(), veg_spec))
  }
  vpro_assert_char_plot_key(veg_long_df, "PlotNumber", "veg_long")

  plot_raw <- vpro_pg_match_df_col(veg_long_df, "PlotNumber")
  spp_raw <- vpro_pg_match_df_col(veg_long_df, "Species")
  lyr_raw <- vpro_pg_match_df_col(veg_long_df, "Layer")
  cov_raw <- vpro_pg_match_df_col(veg_long_df, "Cover")

  if (is.null(plot_raw) || is.null(spp_raw) || is.null(lyr_raw) || is.null(cov_raw)) {
    cli::cli_abort(
      "RDS {.val veg_long} table must contain {.field PlotNumber}, {.field Species}, {.field Layer}, and {.field Cover} columns."
    )
  }

  n_in <- nrow(veg_long_df)
  plots <- as.character(plot_raw)
  spp <- toupper(trimws(as.character(spp_raw)))
  layers <- tolower(trimws(ifelse(is.na(lyr_raw), "", as.character(lyr_raw))))
  covers <- vpro_narrow_float32(suppressWarnings(as.double(cov_raw)))

  ht_raw <- vpro_pg_match_df_col(veg_long_df, "Height")
  heights <- if (is.null(ht_raw)) rep(NA_real_, n_in) else suppressWarnings(as.double(ht_raw))
  heights[!is.finite(heights)] <- NA_real_

  coll_raw <- vpro_pg_match_df_col(veg_long_df, "Collected")
  collected <- if (is.null(coll_raw)) {
    rep(NA_character_, n_in)
  } else {
    c_chr <- trimws(as.character(coll_raw))
    c_chr[!nzchar(c_chr)] <- NA_character_
    c_chr
  }

  id_raw <- vpro_pg_match_df_col(veg_long_df, "ID")
  ids <- if (is.null(id_raw)) rep(NA_integer_, n_in) else suppressWarnings(as.integer(id_raw))

  flag_raw <- vpro_pg_match_df_col(veg_long_df, "Flag")
  flags <- if (is.null(flag_raw)) rep(FALSE, n_in) else vpro_access_to_logical(flag_raw)
  flags[is.na(flags)] <- FALSE

  valid <- !is.na(plots) & nzchar(trimws(plots)) & !is.na(spp) & nzchar(spp)
  if (!any(valid)) {
    return(vpro_pg_canonicalize_to_tidy(data.frame(), veg_spec))
  }

  plots <- plots[valid]
  spp <- spp[valid]
  layers <- layers[valid]
  covers <- covers[valid]
  heights <- heights[valid]
  collected <- collected[valid]
  ids <- ids[valid]
  flags <- flags[valid]

  cov_map <- c(
    "1" = "Cover1", "a1" = "Cover1", "cover1" = "Cover1",
    "2" = "Cover2", "a2" = "Cover2", "cover2" = "Cover2",
    "3" = "Cover3", "a3" = "Cover3", "cover3" = "Cover3",
    "a" = "TotalA", "totala" = "TotalA",
    "4" = "Cover4", "b1" = "Cover4", "cover4" = "Cover4",
    "5" = "Cover5", "b2" = "Cover5", "cover5" = "Cover5",
    "5a" = "Cover5a", "b2a" = "Cover5a", "cover5a" = "Cover5a",
    "5b" = "Cover5b", "b2b" = "Cover5b", "cover5b" = "Cover5b",
    "5c" = "Cover5c", "b2c" = "Cover5c", "cover5c" = "Cover5c",
    "b" = "TotalB", "totalb" = "TotalB",
    "6" = "Cover6", "c" = "Cover6", "cover6" = "Cover6",
    "7" = "Cover7", "d" = "Cover7", "d1" = "Cover7", "cover7" = "Cover7",
    "8" = "Cover8", "dw" = "Cover8", "d2" = "Cover8", "cover8" = "Cover8",
    "9" = "Cover9", "dr" = "Cover9", "d3" = "Cover9", "cover9" = "Cover9",
    "10" = "Cover10", "ep" = "Cover10", "cover10" = "Cover10"
  )

  ht_map <- c(
    "Cover1" = "Height1",
    "Cover2" = "Height2",
    "Cover3" = "Height3",
    "TotalA" = "HeightA",
    "Cover4" = "Height4",
    "Cover5" = "Height5",
    "Cover5a" = "Height5a",
    "Cover5b" = "Height5b",
    "Cover5c" = "Height5c",
    "TotalB" = "HeightB",
    "Cover6" = "Height6"
  )

  non_empty_lyr <- nzchar(layers)
  mapped_cov_col <- rep(NA_character_, length(layers))
  mapped_cov_col[non_empty_lyr] <- unname(cov_map[layers[non_empty_lyr]])
  unknown_lyr <- unique(layers[non_empty_lyr & is.na(mapped_cov_col)])
  if (length(unknown_lyr) > 0L) {
    cli::cli_abort(
      "Unrecognized vegetation layer code(s) in {.val veg_long}: {.val {unknown_lyr}}."
    )
  }
  mapped_ht_col <- unname(ht_map[mapped_cov_col])

  grp_key <- paste0(plots, "\r", spp)
  u_keys <- unique(grp_key)
  row_idx <- match(grp_key, u_keys)
  n_out <- length(u_keys)
  first_pos <- match(u_keys, grp_key)

  all_cov_cols <- c(
    "Cover1", "Cover2", "Cover3", "TotalA",
    "Cover4", "Cover5", "Cover5a", "Cover5b", "Cover5c", "TotalB",
    "Cover6", "Cover7", "Cover8", "Cover9", "Cover10"
  )
  all_num_ht_cols <- c(
    "Height1", "Height2", "Height3", "HeightA",
    "Height4", "Height5", "Height5a", "Height5b", "Height5c",
    "Height6"
  )

  out_list <- list(
    PlotNumber = plots[first_pos],
    Species = spp[first_pos],
    Layer = rep(NA_character_, n_out)
  )
  for (cc in all_cov_cols) {
    out_list[[cc]] <- rep(NA_real_, n_out)
  }
  for (hc in all_num_ht_cols) {
    out_list[[hc]] <- rep(NA_real_, n_out)
  }
  out_list[["HeightB"]] <- rep(NA_character_, n_out)

  for (cc in all_cov_cols) {
    hit <- which(!is.na(mapped_cov_col) & mapped_cov_col == cc & !is.na(covers) & covers >= 0)
    if (length(hit) > 0L) {
      vec <- out_list[[cc]]
      for (k in hit) {
        r <- row_idx[[k]]
        cv <- covers[[k]]
        if (is.na(vec[[r]]) || cv > vec[[r]]) {
          vec[[r]] <- cv
        }
      }
      out_list[[cc]] <- vpro_narrow_float32(vec)
    }
  }

  for (hc in all_num_ht_cols) {
    hit <- which(!is.na(mapped_ht_col) & mapped_ht_col == hc & !is.na(heights))
    if (length(hit) > 0L) {
      vec <- out_list[[hc]]
      for (k in hit) {
        r <- row_idx[[k]]
        hv <- heights[[k]]
        if (is.na(vec[[r]]) || hv > vec[[r]]) {
          vec[[r]] <- hv
        }
      }
      out_list[[hc]] <- vec
    }
  }

  hit_hb <- which(!is.na(mapped_ht_col) & mapped_ht_col == "HeightB" & !is.na(heights))
  if (length(hit_hb) > 0L) {
    hb_num <- rep(NA_real_, n_out)
    for (k in hit_hb) {
      r <- row_idx[[k]]
      hv <- heights[[k]]
      if (is.na(hb_num[[r]]) || hv > hb_num[[r]]) {
        hb_num[[r]] <- hv
      }
    }
    ok_hb <- !is.na(hb_num)
    out_list[["HeightB"]][ok_hb] <- sub("\\.?0+$", "", sprintf("%.2f", hb_num[ok_hb]))
  }

  coll_out <- rep(NA_character_, n_out)
  hit_coll <- which(!is.na(collected) & nzchar(collected))
  if (length(hit_coll) > 0L) {
    for (k in hit_coll) {
      r <- row_idx[[k]]
      if (is.na(coll_out[[r]])) {
        coll_out[[r]] <- substr(collected[[k]], 1L, 1L)
      }
    }
  }
  out_list[["Collected"]] <- coll_out

  flag_out <- rep(FALSE, n_out)
  hit_flag <- which(flags)
  if (length(hit_flag) > 0L) {
    flag_out[unique(row_idx[hit_flag])] <- TRUE
  }
  out_list[["Flag"]] <- flag_out

  out_list[["ID"]] <- vpro_preserve_or_assign_unique_ids(
    ids[first_pos],
    start_id = 1L,
    require_positive = FALSE
  )

  wide_df <- as.data.frame(out_list, stringsAsFactors = FALSE, check.names = FALSE)
  ord <- order(wide_df$PlotNumber, wide_df$Species, wide_df$ID, method = "radix")
  wide_df <- wide_df[ord, , drop = FALSE]
  vpro_pg_canonicalize_to_tidy(wide_df, veg_spec)
}

# Public Exported Snapshot & Portable RDS Functions ----------------------------

#' Write a compact compressed `VP08` `.rds` snapshot bundle from a workspace
#'
#' Extracts all 8 `VP08` project tables (`env`, `admin`, `veg`, `humus`,
#' `mineral`, `other`, `metadata`, `audit`), site-unit assignments (`su`), and
#' species lump mappings (`lump`) from any `vpro_workspace` (see [vpro_connect()],
#' e.g. `vpro_connect("Sample")`), enforces literal `character` `PlotNumber`/`Plot` keys,
#' normalizes Access `-1/0` booleans to R `logical`, narrows cover columns via
#' [vpro_narrow_float32()], and atomically writes a compressed `"vpro_rds_bundle"`
#' file suitable for zero-database ecological analysis via
#' [vpro_import_rds()].
#'
#' @param ws A `vpro_workspace` handle from [vpro_connect()].
#' @param path Destination `.rds` file path.
#' @param snapshot_tag Optional snapshot identifier tag stored in `provenance`.
#'   Defaults to `provenance$snapshot_tag` when present, or the file stem of
#'   `path`.
#' @param provenance Optional named list of provenance metadata (`snapshot_tag`,
#'   `created_at`, `created_by`, `bec_version`, `taxonomy_version`,
#'   `tail_audit_hash`, `notes`).
#' @param compress Compression codec passed to [base::saveRDS()]: `"xz"`
#'   (default maximum compression) or `"gzip"` (faster write).
#' @param redact_sensitive Logical; if `TRUE`, redacts coordinates (`Latitude`,
#'   `Longitude`, `UTMEasting`, `UTMNorthing`, `UTMZone`) to `NA` on plots
#'   containing sensitive (`USysSppAttributes.RedBlueList`) species. Defaults to
#'   `isTRUE(attr(ws, "cloud_redacted"))`.
#' @return A list with `path`, `sha256`, `bytes`, `plot_count`, and `veg_count`.
#' @seealso [vpro_import_rds()], [vpro_master_publish_snapshot()]
#' @export
vpro_export_rds <- function(
  ws,
  path,
  snapshot_tag = NULL,
  provenance = list(),
  compress = c("xz", "gzip"),
  redact_sensitive = isTRUE(attr(ws, "cloud_redacted"))
) {
  vpro_assert_workspace(ws)
  compress <- match.arg(compress)

  if (!is.character(path) || length(path) != 1L || is.na(path) || !nzchar(trimws(path))) {
    cli::cli_abort("{.arg path} must be a single non-empty {.file .rds} file path.")
  }
  if (is.null(provenance)) {
    provenance <- list()
  }
  if (!is.list(provenance)) {
    cli::cli_abort("{.arg provenance} must be a named {.cls list}.")
  }
  if (!is.null(snapshot_tag) && (!is.character(snapshot_tag) || length(snapshot_tag) != 1L || is.na(snapshot_tag) || !nzchar(trimws(snapshot_tag)))) {
    cli::cli_abort("{.arg snapshot_tag} must be {.code NULL} or a single non-empty character string.")
  }

  dest_clean <- trimws(path)
  if (!nzchar(tools::file_ext(dest_clean))) {
    dest_clean <- paste0(dest_clean, ".rds")
  }
  dest_resolved <- vpro_abs_path(dest_clean)

  if (file.exists(dest_resolved) && dir.exists(dest_resolved)) {
    cli::cli_abort("{.arg path} points to an existing directory: {.path {dest_resolved}}.")
  }
  if (vpro_is_protected_support_db(dest_resolved, con = ws) || vpro_is_bundled_package_path(dest_resolved)) {
    cli::cli_abort(
      "Refusing to write RDS snapshot onto protected or bundled package path: {.path {dest_resolved}}."
    )
  }

  tables <- vpro_extract_workspace_snapshot_tables(ws)
  if (isTRUE(redact_sensitive) && is.data.frame(tables$env) && nrow(tables$env) > 0L &&
      is.data.frame(tables$veg) && nrow(tables$veg) > 0L && "Species" %in% names(tables$veg)) {
    sens_codes <- .vpro_sensitive_species_codes(vlists_path = ws$vlists_path)
    if (length(sens_codes) > 0L) {
      veg_spp <- toupper(trimws(as.character(tables$veg$Species)))
      sens_plots <- unique(as.character(tables$veg$PlotNumber[veg_spp %in% sens_codes]))
      if (length(sens_plots) > 0L) {
        tables$env <- .vpro_redact_coord_df(tables$env, sens_plots)
      }
    }
  }
  plot_count <- as.integer(nrow(tables$env))
  veg_count <- as.integer(nrow(tables$veg))

  pick_chr <- function(val, default_val) {
    if (!is.null(val) && length(val) >= 1L && !is.na(val[[1L]]) && nzchar(trimws(as.character(val[[1L]])))) {
      trimws(as.character(val[[1L]]))
    } else {
      default_val
    }
  }

  resolved_tag <- if (!is.null(snapshot_tag)) {
    trimws(snapshot_tag)
  } else {
    stem <- tools::file_path_sans_ext(basename(dest_resolved))
    pick_chr(provenance$snapshot_tag, if (nzchar(stem)) stem else ws$project)
  }

  sys_user <- tryCatch(Sys.info()[["user"]], error = function(e) "")
  default_actor <- if (is.character(sys_user) && length(sys_user) == 1L && !is.na(sys_user) && nzchar(trimws(sys_user))) {
    trimws(sys_user)
  } else {
    "VProUser"
  }

  notes_val <- if (!is.null(provenance$notes) && length(provenance$notes) >= 1L && !is.na(provenance$notes[[1L]])) {
    as.character(provenance$notes[[1L]])
  } else {
    NA_character_
  }

  tail_hash <- pick_chr(provenance$tail_audit_hash, "")
  if (!nzchar(tail_hash)) {
    tail_hash <- vpro_compute_local_audit_tail_hash(tables$audit)
  }

  prov_clean <- list(
    snapshot_tag = resolved_tag,
    created_at = pick_chr(provenance$created_at, format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")),
    created_by = pick_chr(provenance$created_by, default_actor),
    plot_count = plot_count,
    veg_count = veg_count,
    bec_version = pick_chr(provenance$bec_version, .vpro_default_bec_version),
    taxonomy_version = pick_chr(provenance$taxonomy_version, .vpro_default_taxonomy_version),
    tail_audit_hash = tail_hash,
    notes = notes_val
  )

  bundle <- structure(
    list(
      schema_version = "VP08",
      project = as.character(ws$project),
      provenance = prov_clean,
      tables = tables
    ),
    class = "vpro_rds_bundle"
  )

  parent_dir <- dirname(dest_resolved)
  if (!dir.exists(parent_dir)) {
    dir.create(parent_dir, recursive = TRUE, showWarnings = FALSE)
  }

  tmp_rds <- tempfile(pattern = ".vpro-rds-snap-", tmpdir = parent_dir, fileext = ".rds")
  published <- FALSE
  on.exit(if (!published) unlink(tmp_rds, force = TRUE), add = TRUE)

  saveRDS(bundle, file = tmp_rds, compress = compress)
  if (!file.rename(tmp_rds, dest_resolved)) {
    if (file.exists(dest_resolved)) {
      unlink(dest_resolved, force = TRUE)
    }
    if (!file.rename(tmp_rds, dest_resolved)) {
      if (!file.copy(tmp_rds, dest_resolved, overwrite = TRUE)) {
        cli::cli_abort("Failed to atomically write RDS snapshot to {.path {dest_resolved}}.")
      }
      unlink(tmp_rds, force = TRUE)
    }
  }
  published <- TRUE

  dest_final <- normalizePath(dest_resolved, winslash = "/", mustWork = TRUE)
  list(
    path = dest_final,
    sha256 = tolower(trimws(unname(as.character(vpro_sha256_file(dest_final))))),
    bytes = file.info(dest_final)$size,
    plot_count = plot_count,
    veg_count = veg_count
  )
}

#' Open a portable `.rds` project snapshot as a live `vpro_workspace`
#'
#' Reads either a `"vpro_rds_bundle"` written by [vpro_export_rds()] /
#' [vpro_master_publish_snapshot()] or a named-list `.rds` bundle exported by
#' `VPro` desktop (`ExportProjectRDS` with `env`, `admin`, `veg_long`, `humus`,
#' `mineral`, `su`, `metadata`), automatically pivoting `veg_long` into the
#' canonical 44-column `VP08` `veg` schema when `veg` is absent. Enforces all
#' `VP08` domain invariants, stages a self-cleaning ephemeral SQLite `VP08`
#' database in [base::tempdir()], and returns an S3 object inheriting from
#' `"vpro_workspace"` so [vpro_env()], [vpro_veg()], [vpro_soil()],
#' [vpro_matrix()], [vpro_cluster()], [vpro_diagnostics()], [vpro_climate()],
#' [vpro_asmr()], [vpro_sf()], and [vpro_render_guide()] work out-of-the-box
#' with zero external database setup.
#'
#' @param path Path to an `.rds` project snapshot file.
#' @param su Optional site-unit override: `NULL` (default uses bundle `su`
#'   table), `"None"` / `FALSE` to disable active SU scoping, a custom
#'   `data.frame(PlotNumber, SiteUnit)`, or a target `*_SU` table name.
#' @param lump Optional species lump override: `NULL` (default uses bundle
#'   `lump` table), `"None"` / `FALSE` to disable active lumping, a custom
#'   `data.frame(SppCode, LumpCode, Use)`, or a target `*_Lump` table name.
#' @return An S3 object of class `c("vpro_rds_project", "vpro_workspace")`.
#' @seealso [vpro_export_rds()], [vpro_master_publish_snapshot()], [vpro_env()],
#'   [vpro_diagnostics()]
#' @export
vpro_import_rds <- function(path, su = NULL, lump = NULL) {
  .vpro_register_snap_s3()

  if (!is.character(path) || length(path) != 1L || is.na(path) || !nzchar(trimws(path))) {
    cli::cli_abort("{.arg path} must be a single non-empty {.file .rds} file path.")
  }
  if (!file.exists(path) || dir.exists(path)) {
    cli::cli_abort("RDS snapshot file does not exist: {.path {path}}.")
  }
  rds_norm <- normalizePath(path, winslash = "/", mustWork = TRUE)
  raw_obj <- readRDS(rds_norm)

  is_bundle <- inherits(raw_obj, "vpro_rds_bundle") || (
    is.list(raw_obj) &&
      !is.data.frame(raw_obj) &&
      is.list(raw_obj$tables) &&
      ("env" %in% tolower(names(raw_obj$tables)))
  )
  is_wails_list <- !is_bundle &&
    is.list(raw_obj) &&
    !is.data.frame(raw_obj) &&
    !is.null(names(raw_obj)) &&
    ("env" %in% tolower(names(raw_obj)))

  if (!is_bundle && !is_wails_list) {
    cli::cli_abort(c(
      "Unsupported RDS object in {.path {rds_norm}}.",
      "i" = "Expected a {.cls vpro_rds_bundle} from {.fn vpro_export_rds} or a named list of data frames ({.field env}, {.field admin}, {.field veg}/{.field veg_long}, ...) from {.code VPro}."
    ))
  }

  raw_tables <- if (is_bundle) raw_obj$tables else raw_obj
  tbl_names_low <- tolower(names(raw_tables))
  fetch_tbl <- function(nm) {
    ix <- match(tolower(nm), tbl_names_low)
    if (is.na(ix)) NULL else raw_tables[[ix]]
  }

  file_stem <- tools::file_path_sans_ext(basename(rds_norm))
  raw_proj <- if (is_bundle && is.character(raw_obj$project) && length(raw_obj$project) == 1L &&
                  !is.na(raw_obj$project) && nzchar(trimws(raw_obj$project))) {
    trimws(raw_obj$project)
  } else {
    file_stem
  }
  project_name <- tryCatch(
    vpro_project_name(raw_proj),
    error = function(e) vpro_snapshot_project_prefix(raw_proj, fallback = "RDSProject", guard_reserved = FALSE)
  )

  raw_env <- fetch_tbl("env")
  raw_admin <- fetch_tbl("admin")
  raw_veg <- fetch_tbl("veg")
  raw_veg_long <- fetch_tbl("veg_long")
  raw_humus <- fetch_tbl("humus")
  raw_mineral <- fetch_tbl("mineral")
  raw_other <- fetch_tbl("other")
  raw_metadata <- fetch_tbl("metadata")
  raw_audit <- fetch_tbl("audit")
  raw_su <- fetch_tbl("su")
  raw_lump <- fetch_tbl("lump")

  vpro_assert_char_plot_key(raw_env, "PlotNumber", "env")
  vpro_assert_char_plot_key(raw_admin, "Plot", "admin")
  vpro_assert_char_plot_key(raw_veg, "PlotNumber", "veg")
  vpro_assert_char_plot_key(raw_humus, "PlotNumber", "humus")
  vpro_assert_char_plot_key(raw_mineral, "PlotNumber", "mineral")
  vpro_assert_char_plot_key(raw_other, "PlotNumber", "other")
  vpro_assert_char_plot_key(raw_audit, "PlotNumber", "audit")

  canon_one <- function(df_in, suffix) {
    spec <- vpro_pg_vp08_specs(suffix)
    src <- if (is.null(df_in)) data.frame() else df_in
    out <- vpro_pg_canonicalize_to_tidy(src, spec)
    if ("PlotNumber" %in% names(out)) {
      out$PlotNumber <- as.character(out$PlotNumber)
    }
    if ("Plot" %in% names(out)) {
      out$Plot <- as.character(out$Plot)
    }
    out
  }

  env_tbl <- canon_one(raw_env, "Env")
  if (nrow(env_tbl) > 0L) {
    keep_e <- !is.na(env_tbl$PlotNumber) & nzchar(trimws(env_tbl$PlotNumber))
    env_tbl <- env_tbl[keep_e, , drop = FALSE]
    env_tbl <- env_tbl[!duplicated(env_tbl$PlotNumber), , drop = FALSE]
    env_tbl <- env_tbl[order(env_tbl$PlotNumber, method = "radix"), , drop = FALSE]
  }

  admin_tbl <- canon_one(raw_admin, "Admin")
  if (nrow(admin_tbl) > 0L) {
    keep_a <- !is.na(admin_tbl$Plot) & nzchar(trimws(admin_tbl$Plot))
    admin_tbl <- admin_tbl[keep_a, , drop = FALSE]
    admin_tbl <- admin_tbl[!duplicated(admin_tbl$Plot), , drop = FALSE]
    admin_tbl <- admin_tbl[order(admin_tbl$Plot, method = "radix"), , drop = FALSE]
  }

  veg_tbl <- if (!is.null(raw_veg)) {
    canon_one(raw_veg, "Veg")
  } else if (!is.null(raw_veg_long)) {
    vpro_pivot_veg_long_to_vp08(raw_veg_long)
  } else {
    canon_one(NULL, "Veg")
  }
  if (nrow(veg_tbl) > 0L) {
    keep_v <- !is.na(veg_tbl$PlotNumber) & nzchar(trimws(veg_tbl$PlotNumber))
    veg_tbl <- veg_tbl[keep_v, , drop = FALSE]
    veg_spec <- vpro_pg_vp08_specs("Veg")
    cov_cols <- as.character(veg_spec$name[veg_spec$is_cover])
    for (cc in intersect(cov_cols, names(veg_tbl))) {
      cv <- veg_tbl[[cc]]
      bad_cv <- !is.na(cv) & (!is.finite(cv) | cv < 0 | cv >= 100)
      if (any(bad_cv)) {
        cli::cli_abort(
          "RDS vegetation cover column {.field {cc}} contains value(s) outside [0, 100) in IEEE-754 float32."
        )
      }
    }
  }

  humus_tbl <- canon_one(raw_humus, "Humus")
  if (nrow(humus_tbl) > 0L) {
    humus_tbl <- humus_tbl[!is.na(humus_tbl$PlotNumber) & nzchar(trimws(humus_tbl$PlotNumber)), , drop = FALSE]
  }

  mineral_tbl <- canon_one(raw_mineral, "Mineral")
  if (nrow(mineral_tbl) > 0L) {
    mineral_tbl <- mineral_tbl[!is.na(mineral_tbl$PlotNumber) & nzchar(trimws(mineral_tbl$PlotNumber)), , drop = FALSE]
  }

  other_tbl <- canon_one(raw_other, "Other")
  if (nrow(other_tbl) > 0L) {
    other_tbl <- other_tbl[!is.na(other_tbl$PlotNumber) & nzchar(trimws(other_tbl$PlotNumber)), , drop = FALSE]
  }

  metadata_tbl <- canon_one(raw_metadata, "Metadata")
  audit_tbl <- canon_one(raw_audit, "Audit")

  su_disabled <- vpro_is_none_selector(su)
  su_tbl <- if (is.data.frame(su)) {
    vpro_normalize_su_tibble(su)
  } else if (!is.null(raw_su)) {
    vpro_normalize_su_tibble(raw_su)
  } else {
    vpro_derive_su_from_env_admin(env_tbl, admin_tbl)
  }

  lump_disabled <- vpro_is_none_selector(lump)
  lump_tbl <- if (is.data.frame(lump)) {
    vpro_normalize_lump_tibble(lump)
  } else if (!is.null(raw_lump)) {
    vpro_normalize_lump_tibble(raw_lump)
  } else {
    vpro_normalize_lump_tibble(NULL)
  }

  su_table_name <- if (!su_disabled && nrow(su_tbl) > 0L) {
    if (is.character(su) && length(su) == 1L && !is.na(su) && nzchar(trimws(su))) {
      req_s <- trimws(su)
      if (grepl("_SU$", req_s, ignore.case = TRUE)) req_s else paste0(req_s, "_SU")
    } else {
      paste0(project_name, "_SU")
    }
  } else {
    NULL
  }

  lump_table_name <- if (!lump_disabled && nrow(lump_tbl) > 0L) {
    if (is.character(lump) && length(lump) == 1L && !is.na(lump) && nzchar(trimws(lump))) {
      req_l <- trimws(lump)
      if (grepl("_Lump$", req_l, ignore.case = TRUE)) req_l else paste0(req_l, "_Lump")
    } else {
      paste0(project_name, "_Lump")
    }
  } else {
    NULL
  }

  # Materialize ephemeral self-cleaning VP08 SQLite workspace in tempdir()
  tmp_db <- tempfile(pattern = "vpro-rds-proj-", fileext = ".db")
  staged_ok <- FALSE
  on.exit({
    if (!staged_ok) {
      unlink(c(tmp_db, paste0(tmp_db, "-wal"), paste0(tmp_db, "-shm")), force = TRUE)
    }
  }, add = TRUE)

  sq_con <- DBI::dbConnect(RSQLite::SQLite(), tmp_db)
  on.exit(if (DBI::dbIsValid(sq_con)) DBI::dbDisconnect(sq_con), add = TRUE)
  DBI::dbExecute(sq_con, "PRAGMA foreign_keys = OFF")
  DBI::dbExecute(sq_con, "PRAGMA journal_mode = DELETE")
  DBI::dbExecute(sq_con, "PRAGMA synchronous = NORMAL")

  tables_map <- list(
    Env = env_tbl,
    Admin = admin_tbl,
    Veg = veg_tbl,
    Humus = humus_tbl,
    Mineral = mineral_tbl,
    Other = other_tbl,
    Metadata = metadata_tbl,
    Audit = audit_tbl
  )

  DBI::dbWithTransaction(sq_con, {
    deferred_idx <- vpro_clone_sample_schema(sq_con, project_name)

    DBI::dbExecute(
      sq_con,
      'CREATE TABLE "_table_metadata" ("table_name" TEXT PRIMARY KEY, "description" TEXT)'
    )
    for (sfx in .vpro_core_project_suffixes) {
      DBI::dbExecute(
        sq_con,
        'INSERT INTO "_table_metadata" ("table_name", "description") VALUES (?, \'VP08\')',
        params = list(paste0(project_name, "_", sfx))
      )
    }
    DBI::dbExecute(
      sq_con,
      'CREATE TABLE IF NOT EXISTS "__VPRO_ChildIdentity" ("ChildTable" TEXT NOT NULL, "ID" INTEGER NOT NULL, PRIMARY KEY ("ChildTable", "ID"))'
    )

    for (sfx in names(tables_map)) {
      src_tbl <- tables_map[[sfx]]
      if (nrow(src_tbl) == 0L) {
        next
      }
      spec <- vpro_pg_vp08_specs(sfx)
      dst_tbl <- paste0(project_name, "_", sfx)
      dst_fields <- DBI::dbListFields(sq_con, dst_tbl)
      sq_df <- vpro_pg_canonicalize_to_sqlite(src_tbl, spec)
      if ("PlotNumber" %in% names(sq_df)) {
        sq_df$PlotNumber <- as.character(sq_df$PlotNumber)
      }
      if ("Plot" %in% names(sq_df)) {
        sq_df$Plot <- as.character(sq_df$Plot)
      }
      bool_cols <- as.character(spec$name[!is.na(spec$is_bool) & spec$is_bool])
      for (bc in intersect(bool_cols, names(sq_df))) {
        sq_df[[bc]] <- vpro_logical_to_access(sq_df[[bc]])
      }
      if (identical(sfx, "Veg") && "Species" %in% names(sq_df)) {
        sq_df$Species <- as.character(sq_df$Species)
        sq_df$Species[is.na(sq_df$Species)] <- ""
      }
      if (sfx %in% c("Veg", "Humus", "Mineral", "Other", "Metadata") && "ID" %in% names(sq_df)) {
        sq_df$ID <- vpro_preserve_or_assign_unique_ids(
          sq_df$ID,
          start_id = if (identical(sfx, "Metadata")) 1L else 100000000L,
          require_positive = FALSE
        )
      }
      keep_cols <- intersect(dst_fields, names(sq_df))
      DBI::dbAppendTable(sq_con, dst_tbl, sq_df[, keep_cols, drop = FALSE])
    }

    for (sfx in c("Veg", "Humus", "Mineral", "Other", "Metadata", "Audit")) {
      full_tbl <- paste0(project_name, "_", sfx)
      q_full <- vpro_quote_ident(full_tbl)
      DBI::dbExecute(
        sq_con,
        paste0(
          'INSERT OR IGNORE INTO "__VPRO_ChildIdentity" ("ChildTable", "ID") ',
          'SELECT ?, "ID" FROM ', q_full,
          ' WHERE typeof("ID") = \'integer\' AND "ID" >= 0'
        ),
        params = list(q_full)
      )
    }

    if (!is.null(su_table_name)) {
      q_su <- vpro_quote_ident(su_table_name)
      DBI::dbExecute(sq_con, paste0("CREATE TABLE ", q_su, ' ("PlotNumber" TEXT, "SiteUnit" TEXT)'))
      DBI::dbAppendTable(
        sq_con,
        su_table_name,
        data.frame(
          PlotNumber = as.character(su_tbl$PlotNumber),
          SiteUnit = as.character(su_tbl$SiteUnit),
          stringsAsFactors = FALSE
        )
      )
      idx_kind <- if (anyDuplicated(su_tbl$PlotNumber) > 0L) "CREATE INDEX " else "CREATE UNIQUE INDEX "
      DBI::dbExecute(
        sq_con,
        paste0(idx_kind, vpro_quote_ident(paste0("idx_", su_table_name, "_PlotNumber")), " ON ", q_su, ' ("PlotNumber")')
      )
      DBI::dbExecute(
        sq_con,
        paste0("CREATE INDEX ", vpro_quote_ident(paste0("idx_", su_table_name, "_SiteUnit")), " ON ", q_su, ' ("SiteUnit")')
      )
      DBI::dbExecute(
        sq_con,
        'INSERT OR REPLACE INTO "_table_metadata" ("table_name", "description") VALUES (?, \'VP04\')',
        params = list(su_table_name)
      )
    }

    if (!is.null(lump_table_name)) {
      q_lump <- vpro_quote_ident(lump_table_name)
      DBI::dbExecute(
        sq_con,
        paste0("CREATE TABLE ", q_lump, ' ("LumpCode" VARCHAR(50), "SppCode" VARCHAR(8) UNIQUE, "Use" BOOLEAN)')
      )
      DBI::dbAppendTable(
        sq_con,
        lump_table_name,
        data.frame(
          LumpCode = as.character(lump_tbl$LumpCode),
          SppCode = as.character(lump_tbl$SppCode),
          Use = vpro_logical_to_access(lump_tbl$Use),
          stringsAsFactors = FALSE
        )
      )
      DBI::dbExecute(
        sq_con,
        paste0("CREATE INDEX ", vpro_quote_ident(paste0("idx_", lump_table_name, "_LumpCode")), " ON ", q_lump, ' ("LumpCode")')
      )
      DBI::dbExecute(
        sq_con,
        'INSERT OR REPLACE INTO "_table_metadata" ("table_name", "description") VALUES (?, \'VP08\')',
        params = list(lump_table_name)
      )
    }

    for (idx_sql in deferred_idx) {
      DBI::dbExecute(sq_con, idx_sql)
    }
  })

  DBI::dbExecute(sq_con, "PRAGMA journal_mode = WAL")
  DBI::dbExecute(sq_con, "PRAGMA wal_checkpoint(TRUNCATE)")
  DBI::dbDisconnect(sq_con)
  unlink(c(paste0(tmp_db, "-wal"), paste0(tmp_db, "-shm")), force = TRUE)

  insp <- vpro_project_inspect(tmp_db, project_name)
  if (!isTRUE(insp$compatible)) {
    cli::cli_abort("Staged RDS SQLite workspace failed {.code VP08} compatibility verification.")
  }

  tmp_db_norm <- normalizePath(tmp_db, winslash = "/", mustWork = TRUE)
  # Close a brief RW handle after SQLITE_RO inspection so idle -wal/-shm sidecars are cleaned
  clean_con <- DBI::dbConnect(RSQLite::SQLite(), tmp_db_norm, flags = RSQLite::SQLITE_RW)
  tryCatch({
    DBI::dbGetQuery(clean_con, "SELECT 1 FROM sqlite_master LIMIT 1")
    DBI::dbExecute(clean_con, "PRAGMA wal_checkpoint(TRUNCATE)")
  }, finally = {
    if (DBI::dbIsValid(clean_con)) DBI::dbDisconnect(clean_con)
  })
  staged_ok <- TRUE

  cleanup_env <- new.env(parent = emptyenv())
  cleanup_env$db_path <- tmp_db_norm
  reg.finalizer(
    cleanup_env,
    function(e) {
      p <- e$db_path
      if (is.character(p) && length(p) == 1L && !is.na(p) && nzchar(p)) {
        unlink(c(p, paste0(p, "-wal"), paste0(p, "-shm")), force = TRUE)
      }
    },
    onexit = TRUE
  )

  raw_prov <- if (is_bundle && is.list(raw_obj$provenance)) raw_obj$provenance else list()
  pick_prov <- function(val, def) {
    if (!is.null(val) && length(val) >= 1L && !is.na(val[[1L]]) && nzchar(trimws(as.character(val[[1L]])))) {
      trimws(as.character(val[[1L]]))
    } else {
      def
    }
  }
  prov_out <- list(
    snapshot_tag = pick_prov(raw_prov$snapshot_tag, if (nzchar(file_stem)) file_stem else project_name),
    created_at = pick_prov(
      raw_prov$created_at,
      format(file.info(rds_norm)$mtime, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
    ),
    created_by = pick_prov(raw_prov$created_by, if (is_wails_list) "vpro_wails" else "VProUser"),
    plot_count = as.integer(nrow(env_tbl)),
    veg_count = as.integer(nrow(veg_tbl)),
    bec_version = pick_prov(raw_prov$bec_version, .vpro_default_bec_version),
    taxonomy_version = pick_prov(raw_prov$taxonomy_version, .vpro_default_taxonomy_version),
    tail_audit_hash = pick_prov(raw_prov$tail_audit_hash, vpro_compute_local_audit_tail_hash(audit_tbl)),
    notes = if (!is.null(raw_prov$notes) && length(raw_prov$notes) >= 1L && !is.na(raw_prov$notes[[1L]])) {
      as.character(raw_prov$notes[[1L]])
    } else {
      NA_character_
    }
  )

  tables_out <- list(
    env = env_tbl,
    admin = admin_tbl,
    veg = veg_tbl,
    humus = humus_tbl,
    mineral = mineral_tbl,
    other = other_tbl,
    metadata = metadata_tbl,
    audit = audit_tbl,
    su = su_tbl,
    lump = lump_tbl
  )

  tmp_dir_norm <- normalizePath(tempdir(), winslash = "/", mustWork = FALSE)
  res_obj <- structure(
    list(
      project = project_name,
      project_path = tmp_db_norm,
      su = su_table_name,
      su_path = tmp_db_norm,
      hierarchy = NULL,
      hierarchy_path = tmp_db_norm,
      lump = lump_table_name,
      lump_path = tmp_db_norm,
      vlists_path = vpro_bundled_db("VLists.db"),
      vuser_path = vpro_bundled_db("VUser.db"),
      vpro64_path = vpro_bundled_db("VPro64.db"),
      vmetadata_path = vpro_bundled_db("VMetaData.db"),
      data_dir = tmp_dir_norm,
      config_dir = tmp_dir_norm,
      source = "rds_snapshot",
      rds_path = rds_norm,
      provenance = prov_out,
      tables = tables_out,
      .rds_cleanup = cleanup_env
    ),
    class = c("vpro_rds_project", "vpro_workspace")
  )
  attr(res_obj, "rds_cleanup") <- cleanup_env
  res_obj
}

#' @rdname vpro_import_rds
#' @param x A `vpro_rds_project` object returned by [vpro_import_rds()].
#' @param ... Unused additional arguments.
#' @export
print.vpro_rds_project <- function(x, ...) {
  prov <- if (is.list(x$provenance)) x$provenance else list()
  tag_lbl <- if (!is.null(prov$snapshot_tag) && !is.na(prov$snapshot_tag) && nzchar(prov$snapshot_tag)) {
    as.character(prov$snapshot_tag)
  } else {
    as.character(x$project)
  }
  n_plots <- if (is.list(x$tables) && is.data.frame(x$tables$env)) {
    nrow(x$tables$env)
  } else if (!is.null(prov$plot_count)) {
    as.integer(prov$plot_count)
  } else {
    0L
  }
  n_veg <- if (is.list(x$tables) && is.data.frame(x$tables$veg)) {
    nrow(x$tables$veg)
  } else if (!is.null(prov$veg_count)) {
    as.integer(prov$veg_count)
  } else {
    0L
  }
  bec_lbl <- if (!is.null(prov$bec_version) && !is.na(prov$bec_version) && nzchar(prov$bec_version)) {
    as.character(prov$bec_version)
  } else {
    .vpro_default_bec_version
  }
  tax_lbl <- if (!is.null(prov$taxonomy_version) && !is.na(prov$taxonomy_version) && nzchar(prov$taxonomy_version)) {
    as.character(prov$taxonomy_version)
  } else {
    .vpro_default_taxonomy_version
  }
  su_lbl <- if (!is.null(x$su) && nzchar(x$su)) {
    n_su <- if (is.list(x$tables) && is.data.frame(x$tables$su)) nrow(x$tables$su) else NA_integer_
    paste0(x$su, " (", n_su, " rows)")
  } else {
    "<none>"
  }
  lump_lbl <- if (!is.null(x$lump) && nzchar(x$lump)) {
    n_lmp <- if (is.list(x$tables) && is.data.frame(x$tables$lump)) nrow(x$tables$lump) else NA_integer_
    paste0(x$lump, " (", n_lmp, " rows)")
  } else {
    "<none>"
  }

  cli::cli_h3("vpro_rds_project: {.val {tag_lbl}} (project {.val {x$project}})")
  cli::cli_bullets(c(
    "*" = "RDS snapshot: {.path {x$rds_path}}",
    "*" = "Records: {n_plots} plots, {n_veg} veg rows",
    "*" = "Standards: BEC {bec_lbl} | Taxonomy {tax_lbl}",
    "*" = "Active SU: {su_lbl} | Active Lump: {lump_lbl}"
  ))
  invisible(x)
}

#' @rdname vpro_import_rds
#' @export
as_tibble.vpro_rds_project <- function(x, ...) {
  tibble::as_tibble(x$tables$env)
}

vpro_write_snapshot_csv_bundle <- function(ws, snapshot_tag, out_dir_abs, provenance, overwrite = FALSE, redact_sensitive = FALSE) {
  csv_dir <- file.path(out_dir_abs, paste0(snapshot_tag, "_csv"))
  tar_path <- file.path(out_dir_abs, paste0(snapshot_tag, "_csv.tar.gz"))

  if ((dir.exists(csv_dir) || file.exists(csv_dir) || file.exists(tar_path)) && !isTRUE(overwrite)) {
    cli::cli_abort(
      "Snapshot CSV output already exists (pass {.code overwrite = TRUE} to replace): {.path {tar_path}}."
    )
  }
  if (dir.exists(csv_dir) || file.exists(csv_dir)) {
    unlink(csv_dir, recursive = TRUE, force = TRUE)
  }
  if (file.exists(tar_path)) {
    unlink(tar_path, force = TRUE)
  }

  dir.create(csv_dir, recursive = TRUE, showWarnings = FALSE)
  tables <- vpro_extract_workspace_snapshot_tables(ws)
  if (isTRUE(redact_sensitive) && is.data.frame(tables$env) && nrow(tables$env) > 0L &&
      is.data.frame(tables$veg) && nrow(tables$veg) > 0L && "Species" %in% names(tables$veg)) {
    sens_codes <- .vpro_sensitive_species_codes(vlists_path = ws$vlists_path)
    if (length(sens_codes) > 0L) {
      veg_spp <- toupper(trimws(as.character(tables$veg$Species)))
      sens_plots <- unique(as.character(tables$veg$PlotNumber[veg_spp %in% sens_codes]))
      if (length(sens_plots) > 0L) {
        tables$env <- .vpro_redact_coord_df(tables$env, sens_plots)
      }
    }
  }

  csv_targets <- list(
    env = tables$env,
    admin = tables$admin,
    veg = tables$veg,
    humus = tables$humus,
    mineral = tables$mineral,
    other = tables$other,
    metadata = tables$metadata,
    su = tables$su
  )

  file_entries <- vector("list", length(csv_targets))
  nms <- names(csv_targets)
  for (i in seq_along(nms)) {
    nm <- nms[[i]]
    df <- as.data.frame(csv_targets[[nm]], stringsAsFactors = FALSE, check.names = FALSE)
    fname <- paste0(nm, ".csv")
    fpath <- file.path(csv_dir, fname)
    utils::write.csv(
      df,
      file = fpath,
      row.names = FALSE,
      na = "",
      quote = TRUE,
      fileEncoding = "UTF-8"
    )
    f_norm <- normalizePath(fpath, winslash = "/", mustWork = TRUE)
    file_entries[[i]] <- list(
      file = fname,
      rows = as.integer(nrow(df)),
      columns = as.integer(ncol(df)),
      sha256 = tolower(trimws(unname(as.character(vpro_sha256_file(f_norm))))),
      bytes = as.double(file.info(f_norm)$size)
    )
  }

  manifest_obj <- list(
    schema_version = "VP08",
    snapshot_tag = as.character(snapshot_tag),
    project = as.character(ws$project),
    created_at = as.character(provenance$created_at),
    created_by = as.character(provenance$created_by),
    plot_count = as.integer(provenance$plot_count),
    veg_count = as.integer(provenance$veg_count),
    bec_version = as.character(provenance$bec_version),
    taxonomy_version = as.character(provenance$taxonomy_version),
    tail_audit_hash = as.character(provenance$tail_audit_hash),
    notes = if (is.na(provenance$notes)) NULL else as.character(provenance$notes),
    files = file_entries
  )
  manifest_path <- file.path(csv_dir, "manifest.json")
  jsonlite::write_json(
    manifest_obj,
    path = manifest_path,
    auto_unbox = TRUE,
    pretty = TRUE,
    na = "null"
  )

  tmp_tar <- tempfile(pattern = ".vpro-csv-snap-", tmpdir = out_dir_abs, fileext = ".tar.gz")
  published <- FALSE
  on.exit(if (!published) unlink(tmp_tar, force = TRUE), add = TRUE)

  old_wd <- getwd()
  tar_status <- tryCatch({
    setwd(out_dir_abs)
    utils::tar(
      tarfile = tmp_tar,
      files = basename(csv_dir),
      compression = "gzip"
    )
  }, finally = {
    setwd(old_wd)
  })
  if (!identical(as.integer(tar_status), 0L) || !file.exists(tmp_tar)) {
    cli::cli_abort("Failed to create gzipped CSV snapshot archive {.path {tar_path}}.")
  }

  if (!file.rename(tmp_tar, tar_path)) {
    if (!file.copy(tmp_tar, tar_path, overwrite = TRUE)) {
      cli::cli_abort("Failed to publish CSV snapshot archive {.path {tar_path}}.")
    }
    unlink(tmp_tar, force = TRUE)
  }
  published <- TRUE

  tar_final <- normalizePath(tar_path, winslash = "/", mustWork = TRUE)
  list(
    csv_dir = normalizePath(csv_dir, winslash = "/", mustWork = TRUE),
    path = tar_final,
    sha256 = tolower(trimws(unname(as.character(vpro_sha256_file(tar_final))))),
    bytes = file.info(tar_final)$size
  )
}

#' Publish a custodian `BECMaster` snapshot and multi-format release artifacts
#'
#' Requires a custodian PostgreSQL connection (`pg$role == "custodian"`).
#' Pulls a `REPEATABLE READ` consistent snapshot from `becmaster.*`, writes the
#' requested release artifacts (`"rds"`, `"sqlite"`, `"gpkg"` in `EPSG:3005`,
#' and/or `"csv"` directory + `.tar.gz` bundle) into `out_dir`, computes a
#' deterministic SHA-256 manifest digest across artifact hashes, counts, and
#' active standards versions, and upserts the release record into
#' `becmaster.snapshots` matching `CreateBECMasterSnapshot` in `vpro`.
#'
#' @param pg A custodian `vpro_pg_conn` connection (`role == "custodian"`).
#' @param snapshot_tag Snapshot release identifier (`1..80` ASCII characters
#'   matching `^[A-Za-z0-9._-]{1,80}$`, e.g. `"BECMaster_2026_11"`).
#' @param out_dir Output directory where snapshot artifact files are written
#'   (created recursively if absent).
#' @param formats Non-empty character subset of `c("rds", "sqlite", "gpkg", "csv")`.
#' @param notes Optional release notes recorded in `becmaster.snapshots`.
#' @param zones Optional BEC zone filter passed to the `REPEATABLE READ` pull.
#' @param subzones Optional BEC subzone/variant filter.
#' @param project_ids Optional `ProjectID` filter.
#' @param plots Optional literal character `PlotNumber` filter.
#' @param bbox Optional spatial bounding box (`c(min_lon, min_lat, max_lon, max_lat)`
#'   in `EPSG:4326` or an `sf` `bbox` object).
#' @param compress Compression codec for `.rds` output (`"xz"` or `"gzip"`).
#' @param overwrite Logical; if `TRUE`, replaces existing local artifacts and
#'   updates an existing `snapshot_tag` row in `becmaster.snapshots`.
#' @param redact_sensitive Logical; if `TRUE`, redacts coordinates on plots
#'   containing sensitive (`USysSppAttributes.RedBlueList`) species across
#'   generated artifacts.
#' @return A structured list with `snapshot_tag`, `created_at`, `created_by`,
#'   `plot_count`, `veg_count`, `bec_version`, `taxonomy_version`,
#'   `manifest_sha256`, `notes`, and an `artifacts` tibble (`format`, `path`,
#'   `sha256`, `bytes`).
#' @seealso [vpro_master_list_snapshots()], [vpro_export_rds()],
#'   [vpro_import_rds()], [vpro_export_gpkg()]
#' @export
vpro_master_publish_snapshot <- function(
  pg,
  snapshot_tag,
  out_dir,
  formats = c("rds", "sqlite", "gpkg", "csv"),
  notes = NULL,
  zones = NULL,
  subzones = NULL,
  project_ids = NULL,
  plots = NULL,
  bbox = NULL,
  compress = c("xz", "gzip"),
  overwrite = FALSE,
  redact_sensitive = FALSE
) {
  vpro_assert_pg_conn(pg, require_custodian = TRUE)
  tag <- vpro_validate_snapshot_tag(snapshot_tag, "snapshot_tag")
  overwrite <- vpro_pg_validate_flag(overwrite, "overwrite")
  redact_sensitive <- vpro_pg_validate_flag(redact_sensitive, "redact_sensitive")
  compress <- match.arg(compress)

  if (!is.null(notes) && (!is.character(notes) || length(notes) != 1L)) {
    cli::cli_abort("{.arg notes} must be {.code NULL} or a single character string.")
  }
  notes_clean <- if (is.null(notes) || is.na(notes[[1L]]) || !nzchar(trimws(notes[[1L]]))) {
    NA_character_
  } else {
    trimws(notes[[1L]])
  }

  if (!is.character(formats) || length(formats) == 0L || anyNA(formats)) {
    cli::cli_abort(
      "{.arg formats} must be a non-empty subset of {.or {.val {.vpro_valid_snapshot_formats}}}."
    )
  }
  req_formats <- unique(tolower(trimws(formats)))
  bad_fmt <- setdiff(req_formats, .vpro_valid_snapshot_formats)
  if (length(bad_fmt) > 0L || length(req_formats) == 0L) {
    cli::cli_abort(
      "Unsupported snapshot format(s) {.val {bad_fmt}} (expected subset of {.or {.val {.vpro_valid_snapshot_formats}}})."
    )
  }
  if ("gpkg" %in% req_formats) {
    rlang::check_installed("sf", reason = "to export EPSG:3005 GeoPackage snapshots.")
  }

  if (!is.character(out_dir) || length(out_dir) != 1L || is.na(out_dir) || !nzchar(trimws(out_dir))) {
    cli::cli_abort("{.arg out_dir} must be a single non-empty directory path.")
  }
  out_dir_abs <- vpro_abs_path(trimws(out_dir))
  if (file.exists(out_dir_abs) && !dir.exists(out_dir_abs)) {
    cli::cli_abort("{.arg out_dir} points to an existing file rather than a directory: {.path {out_dir_abs}}.")
  }
  if (vpro_is_bundled_package_path(out_dir_abs)) {
    cli::cli_abort("Refusing to publish snapshots inside installed package path: {.path {out_dir_abs}}.")
  }
  if (!dir.exists(out_dir_abs)) {
    dir.create(out_dir_abs, recursive = TRUE, showWarnings = FALSE)
  }
  out_dir_abs <- normalizePath(out_dir_abs, winslash = "/", mustWork = TRUE)

  rds_dest <- file.path(out_dir_abs, paste0(tag, ".rds"))
  sqlite_dest <- file.path(out_dir_abs, paste0(tag, ".db"))
  gpkg_dest <- file.path(out_dir_abs, paste0(tag, ".gpkg"))
  csv_dir_dest <- file.path(out_dir_abs, paste0(tag, "_csv"))
  csv_tar_dest <- file.path(out_dir_abs, paste0(tag, "_csv.tar.gz"))

  if ("sqlite" %in% req_formats &&
      (file.exists(paste0(sqlite_dest, "-wal")) || file.exists(paste0(sqlite_dest, "-shm")))) {
    cli::cli_abort(
      "Refusing to write {.path {sqlite_dest}} while active SQLite WAL/SHM sidecar files exist."
    )
  }

  if (!isTRUE(overwrite)) {
    planned <- character()
    if ("rds" %in% req_formats) planned <- c(planned, rds_dest)
    if ("sqlite" %in% req_formats) planned <- c(planned, sqlite_dest)
    if ("gpkg" %in% req_formats) planned <- c(planned, gpkg_dest)
    if ("csv" %in% req_formats) planned <- c(planned, csv_tar_dest, csv_dir_dest)
    existing <- planned[file.exists(planned) | dir.exists(planned)]
    if (length(existing) > 0L) {
      cli::cli_abort(
        "Destination snapshot artifact(s) already exist (pass {.code overwrite = TRUE} to replace): {.path {existing}}."
      )
    }
  }

  snap_proj_name <- vpro_snapshot_project_prefix(
    tag,
    fallback = "Snap_BEC",
    guard_reserved = TRUE
  )

  is_full <- length(vpro_pg_clean_tokens(zones, "zones")) == 0L &&
    length(vpro_pg_clean_tokens(subzones, "subzones")) == 0L &&
    length(vpro_pg_clean_tokens(project_ids, "project_ids")) == 0L &&
    length(vpro_pg_clean_tokens(plots, "plots")) == 0L &&
    is.null(bbox)

  want_sqlite <- "sqlite" %in% req_formats
  stage_dir <- NULL
  if (!want_sqlite) {
    stage_dir <- tempfile(pattern = "vpro-snap-stage-")
    dir.create(stage_dir, recursive = TRUE, showWarnings = FALSE)
    on.exit(unlink(stage_dir, recursive = TRUE, force = TRUE), add = TRUE)
    stage_sqlite_path <- file.path(stage_dir, paste0(snap_proj_name, ".db"))
  } else {
    stage_sqlite_path <- sqlite_dest
  }

  pull_res <- vpro_master_pull_impl(
    pg = pg,
    dest_path = stage_sqlite_path,
    project_name = snap_proj_name,
    zones = zones,
    subzones = subzones,
    project_ids = project_ids,
    plots = plots,
    bbox = bbox,
    overwrite = if (want_sqlite) overwrite else TRUE,
    allow_full = is_full,
    log_download = TRUE,
    allow_reserved_name = TRUE,
    redact_sensitive = isTRUE(redact_sensitive)
  )

  ws_snap <- pull_res$workspace
  plot_count <- as.integer(pull_res$plot_count)
  veg_count <- as.integer(pull_res$veg_count)

  bec_version <- if (!is.null(pull_res$snapshot_meta$bec_version)) {
    pull_res$snapshot_meta$bec_version
  } else {
    .vpro_default_bec_version
  }
  taxonomy_version <- if (!is.null(pull_res$snapshot_meta$taxonomy_version)) {
    pull_res$snapshot_meta$taxonomy_version
  } else {
    .vpro_default_taxonomy_version
  }
  tail_audit_hash <- if (!is.null(pull_res$snapshot_meta$tail_audit_hash)) {
    pull_res$snapshot_meta$tail_audit_hash
  } else {
    .vpro_genesis_audit_hash
  }

  usr_df <- tryCatch(
    vpro_pg_query(pg, "SELECT current_user AS usr", params = NULL, action = "read current_user"),
    error = function(e) data.frame()
  )
  pg_actor <- if (nrow(usr_df) >= 1L && !is.na(usr_df$usr[[1L]]) && nzchar(trimws(as.character(usr_df$usr[[1L]])))) {
    trimws(as.character(usr_df$usr[[1L]]))
  } else if (!is.null(pg$user) && nzchar(trimws(as.character(pg$user)))) {
    trimws(as.character(pg$user))
  } else {
    "VProCustodian"
  }
  created_at_iso <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")

  prov_meta <- list(
    snapshot_tag = tag,
    created_at = created_at_iso,
    created_by = pg_actor,
    plot_count = plot_count,
    veg_count = veg_count,
    bec_version = bec_version,
    taxonomy_version = taxonomy_version,
    tail_audit_hash = tail_audit_hash,
    notes = notes_clean
  )

  art_rows <- vector("list", length(req_formats))
  for (i in seq_along(req_formats)) {
    fmt <- req_formats[[i]]
    if (identical(fmt, "sqlite")) {
      art_rows[[i]] <- tibble::tibble(
        format = "sqlite",
        path = pull_res$dest_path,
        sha256 = tolower(trimws(as.character(pull_res$sha256))),
        bytes = as.double(file.info(pull_res$dest_path)$size)
      )
    } else if (identical(fmt, "rds")) {
      rds_res <- vpro_export_rds(
        ws = ws_snap,
        path = rds_dest,
        snapshot_tag = tag,
        provenance = prov_meta,
        compress = compress,
        redact_sensitive = isTRUE(redact_sensitive)
      )
      art_rows[[i]] <- tibble::tibble(
        format = "rds",
        path = rds_res$path,
        sha256 = rds_res$sha256,
        bytes = as.double(rds_res$bytes)
      )
    } else if (identical(fmt, "gpkg")) {
      gpkg_written <- vpro_export_gpkg(
        ws_snap,
        path = gpkg_dest,
        crs = 3005,
        scope = "project",
        overwrite = overwrite
      )
      unlink(c(paste0(gpkg_written, "-wal"), paste0(gpkg_written, "-shm")), force = TRUE)
      gpkg_norm <- normalizePath(gpkg_written, winslash = "/", mustWork = TRUE)
      art_rows[[i]] <- tibble::tibble(
        format = "gpkg",
        path = gpkg_norm,
        sha256 = tolower(trimws(unname(as.character(vpro_sha256_file(gpkg_norm))))),
        bytes = as.double(file.info(gpkg_norm)$size)
      )
    } else if (identical(fmt, "csv")) {
      csv_res <- vpro_write_snapshot_csv_bundle(
        ws = ws_snap,
        snapshot_tag = tag,
        out_dir_abs = out_dir_abs,
        provenance = prov_meta,
        overwrite = overwrite,
        redact_sensitive = isTRUE(redact_sensitive)
      )
      art_rows[[i]] <- tibble::tibble(
        format = "csv",
        path = csv_res$path,
        sha256 = csv_res$sha256,
        bytes = as.double(csv_res$bytes)
      )
    }
  }

  artifacts_tbl <- do.call(rbind, art_rows)
  ord_fmt <- order(artifacts_tbl$format, method = "radix")
  art_sig <- paste(
    paste0(artifacts_tbl$format[ord_fmt], ":", tolower(artifacts_tbl$sha256[ord_fmt])),
    collapse = ","
  )
  manifest_payload <- sprintf(
    "%s|%d|%d|%s|%s|%s|%s",
    tag,
    plot_count,
    veg_count,
    bec_version,
    taxonomy_version,
    tail_audit_hash,
    art_sig
  )
  manifest_sha256 <- tolower(vpro_sha256_utf8(manifest_payload)[[1L]])

  upsert_sql <- paste(
    "INSERT INTO becmaster.snapshots (",
    "  snapshot_tag, created_at, created_by, plot_count, veg_count,",
    "  bec_version, taxonomy_version, manifest_sha256, notes",
    ") VALUES ($1, now(), current_user, $2, $3, $4, $5, $6, $7)",
    "ON CONFLICT (snapshot_tag) DO UPDATE SET",
    "  created_at = EXCLUDED.created_at,",
    "  created_by = EXCLUDED.created_by,",
    "  plot_count = EXCLUDED.plot_count,",
    "  veg_count = EXCLUDED.veg_count,",
    "  bec_version = EXCLUDED.bec_version,",
    "  taxonomy_version = EXCLUDED.taxonomy_version,",
    "  manifest_sha256 = EXCLUDED.manifest_sha256,",
    "  notes = EXCLUDED.notes",
    "RETURNING",
    "  snapshot_tag,",
    "  to_char(created_at AT TIME ZONE 'UTC', 'YYYY-MM-DD\"T\"HH24:MI:SS\"Z\"') AS created_at,",
    "  created_by"
  )

  up_df <- vpro_pg_query(
    pg,
    upsert_sql,
    params = list(
      tag,
      plot_count,
      veg_count,
      bec_version,
      taxonomy_version,
      manifest_sha256,
      notes_clean
    ),
    action = "upsert becmaster.snapshots record"
  )

  final_created_at <- if (nrow(up_df) >= 1L && !is.na(up_df$created_at[[1L]])) {
    as.character(up_df$created_at[[1L]])
  } else {
    created_at_iso
  }
  final_created_by <- if (nrow(up_df) >= 1L && !is.na(up_df$created_by[[1L]])) {
    as.character(up_df$created_by[[1L]])
  } else {
    pg_actor
  }

  list(
    snapshot_tag = tag,
    created_at = final_created_at,
    created_by = final_created_by,
    plot_count = plot_count,
    veg_count = veg_count,
    bec_version = bec_version,
    taxonomy_version = taxonomy_version,
    manifest_sha256 = manifest_sha256,
    notes = notes_clean,
    artifacts = artifacts_tbl
  )
}

#' List published `BECMaster` snapshots from PostgreSQL
#'
#' Queries `becmaster.snapshots` ordered newest-first (`created_at DESC`) and
#' returns a tidy tibble matching `ListBECMasterSnapshots` in `vpro`.
#'
#' @param pg A `vpro_pg_conn` connection handle.
#' @param limit Positive integer maximum number of snapshot rows to return
#'   (defaults to `100L`).
#' @return A tibble with `snapshot_tag`, `created_at`, `created_by`,
#'   `plot_count`, `veg_count`, `bec_version`, `taxonomy_version`,
#'   `manifest_sha256`, and `notes`.
#' @seealso [vpro_master_publish_snapshot()], [vpro_import_rds()]
#' @export
vpro_master_list_snapshots <- function(pg, limit = 100L) {
  vpro_assert_pg_conn(pg, require_custodian = FALSE)
  limit_int <- vpro_pg_validate_limit(limit, allow_null = FALSE)

  sql <- paste(
    "SELECT",
    "  snapshot_tag,",
    "  created_at,",
    "  created_by,",
    "  plot_count,",
    "  veg_count,",
    "  bec_version,",
    "  taxonomy_version,",
    "  manifest_sha256,",
    "  notes",
    "FROM becmaster.snapshots",
    "ORDER BY created_at DESC, snapshot_tag DESC",
    "LIMIT $1"
  )
  df <- vpro_pg_query(
    pg,
    sql,
    params = list(as.integer(limit_int)),
    action = "list becmaster.snapshots"
  )

  if (nrow(df) == 0L) {
    return(tibble::tibble(
      snapshot_tag = character(),
      created_at = as.POSIXct(character(), tz = "UTC"),
      created_by = character(),
      plot_count = integer(),
      veg_count = integer(),
      bec_version = character(),
      taxonomy_version = character(),
      manifest_sha256 = character(),
      notes = character()
    ))
  }

  veg_dbl <- suppressWarnings(as.double(as.character(df$veg_count)))
  veg_col <- if (all(is.na(veg_dbl) | abs(veg_dbl) <= .Machine$integer.max)) {
    as.integer(veg_dbl)
  } else {
    veg_dbl
  }

  ts_col <- if (inherits(df$created_at, "POSIXt")) {
    as.POSIXct(df$created_at, tz = "UTC")
  } else {
    as.POSIXct(as.character(df$created_at), tz = "UTC")
  }

  tibble::tibble(
    snapshot_tag = as.character(df$snapshot_tag),
    created_at = ts_col,
    created_by = as.character(df$created_by),
    plot_count = suppressWarnings(as.integer(as.character(df$plot_count))),
    veg_count = veg_col,
    bec_version = as.character(df$bec_version),
    taxonomy_version = as.character(df$taxonomy_version),
    manifest_sha256 = as.character(df$manifest_sha256),
    notes = as.character(df$notes)
  )
}
