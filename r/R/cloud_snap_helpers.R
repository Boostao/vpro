# BECMaster Snapshot Publication & Portable RDS Project Bundles ----------------

.vpro_snap_s3_state <- new.env(parent = emptyenv())

.vpro_register_snap_s3 <- function() {
  .vpro_register_s3_methods(.vpro_snap_s3_state, list(
    c("base", "print", "vpro_rds_project"),
    c("tibble", "as_tibble", "vpro_rds_project")
  ))
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

# Pivot VPro Desktop ExportProjectRDS veg_long -> 44-col VP08 Veg ------------

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
