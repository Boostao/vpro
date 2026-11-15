# Pure In-Memory 3-Way Diff Engine (1:1 with custodian_merge.go) ---------------

vpro_format_float15 <- function(x) {
  out <- rep(NA_character_, length(x))
  ok <- !is.na(x) & is.finite(x)
  if (any(ok)) {
    vals <- as.double(x[ok])
    vals[vals == 0] <- 0.0
    res <- sprintf("%.15g", vals)
    res[vals == 0] <- "0"
    out[ok] <- res
  }
  out
}

vpro_float64_hex_bits <- function(x) {
  n <- length(x)
  out <- rep("", n)
  ok <- !is.na(x) & is.finite(x)
  if (any(ok)) {
    vals <- as.double(x[ok])
    vals[vals == 0] <- 0.0
    raw_b <- writeBin(vals, raw(), size = 8L, endian = "big")
    hex_mat <- matrix(sprintf("%02x", as.integer(raw_b)), nrow = 8L)
    out[ok] <- paste0(
      hex_mat[1L, ], hex_mat[2L, ], hex_mat[3L, ], hex_mat[4L, ],
      hex_mat[5L, ], hex_mat[6L, ], hex_mat[7L, ], hex_mat[8L, ]
    )
  }
  out
}

vpro_match_table_by_suffix <- function(tables_list, suffix) {
  if (is.null(tables_list) || !is.list(tables_list) || length(tables_list) == 0L) {
    return(NULL)
  }
  nms <- names(tables_list)
  if (is.null(nms)) {
    return(NULL)
  }
  if (suffix %in% nms) {
    return(tables_list[[suffix]])
  }
  ci <- match(tolower(suffix), tolower(nms))
  if (!is.na(ci)) {
    return(tables_list[[ci]])
  }
  NULL
}

vpro_build_cloud_snapshot <- function(label, tables_list) {
  if (is.null(tables_list)) {
    return(NULL)
  }

  plots_seen <- character(0L)
  comp_by_suffix <- stats::setNames(vector("list", length(.vpro_merge_table_suffixes)), .vpro_merge_table_suffixes)
  raw_by_suffix <- stats::setNames(vector("list", length(.vpro_merge_table_suffixes)), .vpro_merge_table_suffixes)

  for (suffix in .vpro_merge_table_suffixes) {
    spec <- vpro_pg_vp08_specs(suffix)
    df_in <- vpro_match_table_by_suffix(tables_list, suffix)
    if (is.null(df_in) || nrow(df_in) == 0L) {
      comp_by_suffix[[suffix]] <- list()
      raw_by_suffix[[suffix]] <- list()
      next
    }

    df <- as.data.frame(df_in, stringsAsFactors = FALSE)
    n_rows <- nrow(df)
    n_cols <- nrow(spec)

    raw_cols <- stats::setNames(vector("list", n_cols), spec$name)
    comp_cols <- stats::setNames(vector("list", n_cols), spec$name)
    hash_cols <- stats::setNames(vector("list", n_cols), spec$name)

    for (ci in seq_len(n_cols)) {
      cn <- spec$name[[ci]]
      pg_t <- spec$pg_type[[ci]]
      is_b <- isTRUE(spec$is_bool[[ci]])
      col_v <- vpro_pg_match_df_col(df, cn)

      if (is_b) {
        acc <- if (is.null(col_v)) rep(NA_integer_, n_rows) else vpro_logical_to_access(col_v)
        raw_cols[[ci]] <- acc
        comp_cols[[ci]] <- ifelse(is.na(acc), NA_character_, as.character(acc))
        hash_cols[[ci]] <- ifelse(is.na(acc), "null", paste0("int:", acc))
      } else if (identical(pg_t, "TEXT")) {
        chr <- if (is.null(col_v)) rep(NA_character_, n_rows) else vpro_pg_format_utc_text(col_v, cn)
        non_na <- !is.na(chr)
        if (any(non_na)) chr[non_na] <- enc2utf8(chr[non_na])
        raw_cols[[ci]] <- chr
        comp_cols[[ci]] <- chr
        hash_cols[[ci]] <- ifelse(is.na(chr), "null", paste0("text:", chr))
      } else if (pg_t %in% c("BIGINT", "SMALLINT")) {
        num <- if (is.null(col_v)) {
          rep(NA_real_, n_rows)
        } else if (is.logical(col_v)) {
          ifelse(is.na(col_v), NA_real_, ifelse(col_v, -1.0, 0.0))
        } else if (is.character(col_v)) {
          s <- trimws(col_v)
          s[!nzchar(s)] <- NA_character_
          suppressWarnings(as.double(s))
        } else {
          suppressWarnings(as.double(col_v))
        }
        num[!is.finite(num)] <- NA_real_
        rnd <- round(num)
        raw_cols[[ci]] <- rnd
        int_str <- ifelse(is.na(rnd), NA_character_, sprintf("%.0f", rnd))
        comp_cols[[ci]] <- int_str
        hash_cols[[ci]] <- ifelse(is.na(int_str), "null", paste0("int:", int_str))
      } else if (identical(pg_t, "DOUBLE PRECISION")) {
        num <- if (is.null(col_v)) {
          rep(NA_real_, n_rows)
        } else if (is.character(col_v)) {
          s <- trimws(col_v)
          s[!nzchar(s)] <- NA_character_
          suppressWarnings(as.double(s))
        } else {
          suppressWarnings(as.double(col_v))
        }
        num[!is.finite(num)] <- NA_real_
        raw_cols[[ci]] <- num
        comp_cols[[ci]] <- vpro_format_float15(num)
        hex_b <- vpro_float64_hex_bits(num)
        hash_cols[[ci]] <- ifelse(is.na(num), "null", paste0("float:", hex_b))
      } else {
        chr <- if (is.null(col_v)) rep(NA_character_, n_rows) else as.character(col_v)
        raw_cols[[ci]] <- chr
        comp_cols[[ci]] <- chr
        hash_cols[[ci]] <- ifelse(is.na(chr), "null", paste0("text:", chr))
      }
    }

    plot_col <- if (identical(suffix, "Admin")) "Plot" else "PlotNumber"
    plot_vec <- comp_cols[[plot_col]]
    valid_p <- which(!is.na(plot_vec) & nzchar(plot_vec))
    if (length(valid_p) == 0L) {
      comp_by_suffix[[suffix]] <- list()
      raw_by_suffix[[suffix]] <- list()
      next
    }

    plots_seen <- c(plots_seen, plot_vec[valid_p])

    # Compute logical base keys vectorized across valid rows
    base_keys <- if (suffix %in% c("Env", "Admin")) {
      rep(suffix, length(valid_p))
    } else if (identical(suffix, "Veg")) {
      spp_v <- ifelse(is.na(comp_cols[["Species"]][valid_p]), "", comp_cols[["Species"]][valid_p])
      lyr_raw <- comp_cols[["Layer"]][valid_p]
      lyr_v <- ifelse(is.na(lyr_raw), "", trimws(lyr_raw))
      ifelse(nzchar(lyr_v), paste0("Species=", spp_v, "|Layer=", lyr_v), paste0("Species=", spp_v))
    } else if (suffix %in% c("Humus", "Mineral")) {
      hz_v <- ifelse(is.na(comp_cols[["Horizon"]][valid_p]), "", comp_cols[["Horizon"]][valid_p])
      paste0("Horizon=", hz_v)
    } else if (identical(suffix, "Other")) {
      dn_v <- ifelse(is.na(comp_cols[["DataName"]][valid_p]), "", comp_cols[["DataName"]][valid_p])
      paste0("DataName=", dn_v)
    } else {
      rep(suffix, length(valid_p))
    }

    sig_cols <- setdiff(spec$name, c("ID", "PlotNumber", "Plot"))
    sig_parts <- vector("list", length(sig_cols) + 1L)
    sig_parts[[1L]] <- base_keys
    for (si in seq_along(sig_cols)) {
      cv <- comp_cols[[sig_cols[[si]]]][valid_p]
      sig_parts[[si + 1L]] <- ifelse(is.na(cv), "<NULL>", cv)
    }
    row_sigs <- do.call(paste, c(sig_parts, list(sep = "|")))

    comp_df <- as.data.frame(comp_cols, stringsAsFactors = FALSE, check.names = FALSE)[valid_p, , drop = FALSE]
    raw_df <- as.data.frame(raw_cols, stringsAsFactors = FALSE, check.names = FALSE)[valid_p, , drop = FALSE]
    hash_df <- as.data.frame(hash_cols, stringsAsFactors = FALSE, check.names = FALSE)[valid_p, , drop = FALSE]

    p_valid <- plot_vec[valid_p]
    idx_by_plot <- split(seq_along(valid_p), p_valid)

    suffix_comp_map <- list()
    suffix_raw_map <- list()

    for (p_nm in names(idx_by_plot)) {
      ix <- idx_by_plot[[p_nm]]
      if (length(ix) > 1L) {
        ix <- ix[order(row_sigs[ix], method = "radix")]
      }
      bks <- base_keys[ix]
      rks <- character(length(ix))
      seen_bk <- new.env(hash = TRUE, parent = emptyenv())
      for (k in seq_along(ix)) {
        bk <- bks[[k]]
        cnt <- if (exists(bk, envir = seen_bk, inherits = FALSE)) {
          get(bk, envir = seen_bk, inherits = FALSE) + 1L
        } else {
          1L
        }
        assign(bk, cnt, envir = seen_bk)
        rks[[k]] <- if (cnt > 1L) paste0(bk, "#", cnt) else bk
      }

      p_comp <- comp_df[ix, , drop = FALSE]
      rownames(p_comp) <- rks
      p_raw <- raw_df[ix, , drop = FALSE]
      rownames(p_raw) <- rks
      p_hash <- hash_df[ix, , drop = FALSE]
      rownames(p_hash) <- rks
      attr(p_raw, "hash_df") <- p_hash

      suffix_comp_map[[p_nm]] <- p_comp
      suffix_raw_map[[p_nm]] <- p_raw
    }

    comp_by_suffix[[suffix]] <- suffix_comp_map
    raw_by_suffix[[suffix]] <- suffix_raw_map
  }

  list(
    label = as.character(label),
    plots = sort(unique(plots_seen), method = "radix"),
    comp = comp_by_suffix,
    raw = raw_by_suffix
  )
}

vpro_frame_digest_tokens <- function(tokens) {
  u <- enc2utf8(as.character(tokens))
  paste0(nchar(u, type = "bytes"), ":", u, "|", collapse = "")
}

vpro_hash_cloud_snapshot <- function(snap) {
  if (is.null(snap)) {
    return("")
  }
  chunks <- character(1L + length(.vpro_merge_table_suffixes))
  chunks[[1L]] <- vpro_frame_digest_tokens(snap$label)

  for (si in seq_along(.vpro_merge_table_suffixes)) {
    suffix <- .vpro_merge_table_suffixes[[si]]
    spec <- vpro_pg_vp08_specs(suffix)
    s_raw <- snap$raw[[suffix]]
    p_names <- if (length(s_raw) > 0L) sort(names(s_raw), method = "radix") else character(0L)

    if (length(p_names) == 0L) {
      chunks[[1L + si]] <- vpro_frame_digest_tokens(c(suffix, "0"))
      next
    }

    row_blocks <- vector("list", length(p_names))
    total_rows <- 0L
    for (pi in seq_along(p_names)) {
      p_nm <- p_names[[pi]]
      p_hash_df <- attr(s_raw[[p_nm]], "hash_df")
      rks <- rownames(p_hash_df)
      ord <- order(rks, method = "radix")
      rks <- rks[ord]
      p_hash_df <- p_hash_df[ord, spec$name, drop = FALSE]
      total_rows <- total_rows + length(rks)

      col_framed <- lapply(spec$name, function(cn) {
        u <- enc2utf8(p_hash_df[[cn]])
        paste0(nchar(u, type = "bytes"), ":", u, "|")
      })
      rk_u <- enc2utf8(paste0(p_nm, "::", rks))
      rk_framed <- paste0(nchar(rk_u, type = "bytes"), ":", rk_u, "|")
      row_blocks[[pi]] <- paste0(
        rk_framed,
        do.call(paste0, col_framed),
        collapse = ""
      )
    }

    chunks[[1L + si]] <- paste0(
      vpro_frame_digest_tokens(c(suffix, as.character(total_rows))),
      paste0(unlist(row_blocks, use.names = FALSE), collapse = "")
    )
  }

  vpro_sha256_utf8(paste0(chunks, collapse = ""))[[1L]]
}

vpro_summarize_cloud_row <- function(spec, comp_row_vec) {
  cols <- setdiff(spec$name, c("ID", "PlotNumber", "Plot"))
  vals <- comp_row_vec[cols]
  keep <- !is.na(vals) & nzchar(vals) & !(cols == "Flag" & vals == "0")
  if (!any(keep)) {
    return("")
  }
  paste(paste0(cols[keep], "=", vals[keep]), collapse = ", ")
}

vpro_same_nullable_str <- function(a, b) {
  if (is.na(a) || is.na(b)) {
    return(is.na(a) && is.na(b))
  }
  identical(as.character(a), as.character(b))
}

vpro_compute_3way_diff <- function(
  submission_id,
  source_project,
  src_tables,
  tgt_tables,
  base_tables = NULL,
  base_db = "",
  base_project = ""
) {
  .vpro_register_sync_s3()
  sub_id <- as.character(submission_id[[1L]])
  src_proj <- as.character(source_project[[1L]])

  src_snap <- vpro_build_cloud_snapshot(src_proj, src_tables)
  tgt_snap <- vpro_build_cloud_snapshot("BECMaster", tgt_tables)
  base_snap <- if (!is.null(base_tables)) {
    bp_lbl <- if (!is.null(base_project) && nzchar(base_project)) as.character(base_project) else "Base"
    vpro_build_cloud_snapshot(bp_lbl, base_tables)
  } else {
    NULL
  }

  has_base <- !is.null(base_snap)
  src_hash <- vpro_hash_cloud_snapshot(src_snap)
  tgt_hash <- vpro_hash_cloud_snapshot(tgt_snap)
  base_hash <- vpro_hash_cloud_snapshot(base_snap)
  preview_digest <- vpro_sha256_utf8(
    vpro_frame_digest_tokens(c(sub_id, src_hash, tgt_hash, base_hash))
  )[[1L]]

  overlap_plots <- sort(
    unique(c(
      src_snap$plots,
      tgt_snap$plots,
      if (has_base) base_snap$plots else character(0L)
    )),
    method = "radix"
  )

  src_plot_env <- new.env(hash = TRUE, parent = emptyenv())
  for (p in src_snap$plots) assign(p, TRUE, envir = src_plot_env)
  tgt_plot_env <- new.env(hash = TRUE, parent = emptyenv())
  for (p in tgt_snap$plots) assign(p, TRUE, envir = tgt_plot_env)
  base_plot_env <- new.env(hash = TRUE, parent = emptyenv())
  if (has_base) {
    for (p in base_snap$plots) assign(p, TRUE, envir = base_plot_env)
  }

  spec_cache <- stats::setNames(
    lapply(.vpro_merge_table_suffixes, vpro_pg_vp08_specs),
    .vpro_merge_table_suffixes
  )

  lookup_base <- function(suffix, plot, rk, field) {
    if (!has_base || !exists(plot, envir = base_plot_env, inherits = FALSE)) {
      return(list(val = NA_character_, in_base = FALSE))
    }
    b_df <- base_snap$comp[[suffix]][[plot]]
    if (is.null(b_df) || !(rk %in% rownames(b_df))) {
      return(list(val = NA_character_, in_base = TRUE))
    }
    row_vec <- stats::setNames(as.character(b_df[rk, , drop = TRUE]), names(b_df))
    if (identical(field, "*")) {
      return(list(val = vpro_summarize_cloud_row(spec_cache[[suffix]], row_vec), in_base = TRUE))
    }
    list(val = row_vec[[field]], in_base = TRUE)
  }

  added_count <- 0L
  identical_count <- 0L
  fast_forward_count <- 0L
  conflict_count <- 0L
  target_only_count <- 0L

  plot_cats <- character(length(overlap_plots))
  plot_n_items <- integer(length(overlap_plots))

  it_cid <- character(0L)
  it_plot <- character(0L)
  it_tbl <- character(0L)
  it_key <- character(0L)
  it_fld <- character(0L)
  it_base <- character(0L)
  it_src <- character(0L)
  it_tgt <- character(0L)
  it_kind <- character(0L)
  it_def <- character(0L)
  it_prot <- logical(0L)

  push_item <- function(cid, pl, tbl, key, fld, bv, sv, tv, knd, def_r, prot) {
    idx <- length(it_cid) + 1L
    it_cid[[idx]] <<- cid
    it_plot[[idx]] <<- pl
    it_tbl[[idx]] <<- tbl
    it_key[[idx]] <<- key
    it_fld[[idx]] <<- fld
    it_base[[idx]] <<- if (is.null(bv) || length(bv) == 0L) NA_character_ else as.character(bv[[1L]])
    it_src[[idx]] <<- if (is.null(sv) || length(sv) == 0L) NA_character_ else as.character(sv[[1L]])
    it_tgt[[idx]] <<- if (is.null(tv) || length(tv) == 0L) NA_character_ else as.character(tv[[1L]])
    it_kind[[idx]] <<- knd
    it_def[[idx]] <<- def_r
    it_prot[[idx]] <<- isTRUE(prot)
  }

  for (pi in seq_along(overlap_plots)) {
    plot <- overlap_plots[[pi]]
    in_src <- exists(plot, envir = src_plot_env, inherits = FALSE)
    in_tgt <- exists(plot, envir = tgt_plot_env, inherits = FALSE)

    if (in_src && !in_tgt) {
      if (has_base && exists(plot, envir = base_plot_env, inherits = FALSE)) {
        cid <- paste0(plot, "::Env::Plot")
        push_item(
          cid, plot, "Env", "Plot", "PlotNumber",
          "Present", "Present", NA_character_,
          "Conflict", "keep_target", FALSE
        )
        conflict_count <- conflict_count + 1L
        plot_cats[[pi]] <- "Conflict"
        plot_n_items[[pi]] <- 1L
      } else {
        added_count <- added_count + 1L
        plot_cats[[pi]] <- "Added"
        plot_n_items[[pi]] <- 0L
      }
      next
    }

    if (!in_src && in_tgt) {
      target_only_count <- target_only_count + 1L
      plot_cats[[pi]] <- "TargetOnly"
      plot_n_items[[pi]] <- 0L
      next
    }

    if (!in_src && !in_tgt) {
      plot_cats[[pi]] <- "Identical"
      plot_n_items[[pi]] <- 0L
      next
    }

    before_n <- length(it_cid)
    has_real_conflict <- FALSE
    has_fast_forward <- FALSE

    for (suffix in .vpro_merge_table_suffixes) {
      spec <- spec_cache[[suffix]]
      s_df <- src_snap$comp[[suffix]][[plot]]
      t_df <- tgt_snap$comp[[suffix]][[plot]]
      b_df <- if (has_base) base_snap$comp[[suffix]][[plot]] else NULL
      s_keys <- if (!is.null(s_df)) rownames(s_df) else character(0L)
      t_keys <- if (!is.null(t_df)) rownames(t_df) else character(0L)
      b_keys <- if (!is.null(b_df)) rownames(b_df) else character(0L)
      if (length(s_keys) == 0L && length(t_keys) == 0L) {
        next
      }
      rks <- sort(unique(c(s_keys, t_keys)), method = "radix")

      is_ambiguous <- function(rk) {
        if (suffix %in% c("Env", "Admin")) return(FALSE)
        base_k <- sub("#.*$", "", rk)
        k2 <- paste0(base_k, "#2")
        grepl("#", rk, fixed = TRUE) || (k2 %in% s_keys) || (k2 %in% t_keys) || (k2 %in% b_keys)
      }

      diff_cols <- setdiff(spec$name, c("ID", "PlotNumber", "Plot"))

      for (rk in rks) {
        has_s <- rk %in% s_keys
        has_t <- rk %in% t_keys
        ambig <- is_ambiguous(rk)

        if (has_s && !has_t) {
          s_vec <- stats::setNames(as.character(s_df[rk, , drop = TRUE]), names(s_df))
          s_sum <- vpro_summarize_cloud_row(spec, s_vec)
          lb <- lookup_base(suffix, plot, rk, "*")
          if (!ambig && has_base && lb$in_base && is.na(lb$val)) {
            knd <- "FastForward"
            def_r <- "accept_source"
            has_fast_forward <- TRUE
          } else {
            knd <- "Conflict"
            def_r <- "keep_target"
            has_real_conflict <- TRUE
          }
          push_item(
            paste0(plot, "::", suffix, "::", rk),
            plot, suffix, rk, "*",
            lb$val, s_sum, NA_character_,
            knd, def_r, FALSE
          )
          next
        }

        if (!has_s && has_t) {
          t_vec <- stats::setNames(as.character(t_df[rk, , drop = TRUE]), names(t_df))
          t_sum <- vpro_summarize_cloud_row(spec, t_vec)
          lb <- lookup_base(suffix, plot, rk, "*")
          if (!ambig && has_base && lb$in_base && vpro_same_nullable_str(t_sum, lb$val)) {
            knd <- "FastForward"
            def_r <- "accept_source"
            has_fast_forward <- TRUE
          } else {
            knd <- "Conflict"
            def_r <- "keep_target"
            has_real_conflict <- TRUE
          }
          push_item(
            paste0(plot, "::", suffix, "::", rk),
            plot, suffix, rk, "*",
            lb$val, NA_character_, t_sum,
            knd, def_r, FALSE
          )
          next
        }

        s_vec <- stats::setNames(as.character(s_df[rk, , drop = TRUE]), names(s_df))
        t_vec <- stats::setNames(as.character(t_df[rk, , drop = TRUE]), names(t_df))

        for (col_nm in diff_cols) {
          sv <- s_vec[[col_nm]]
          tv <- t_vec[[col_nm]]
          if (vpro_same_nullable_str(sv, tv)) {
            next
          }
          fld_key <- if (suffix %in% c("Env", "Admin")) col_nm else paste0(rk, ".", col_nm)
          lb <- lookup_base(suffix, plot, rk, col_nm)
          is_prot <- identical(suffix, "Admin") && (col_nm %in% .vpro_custodian_protected_admin_fields)

          knd <- "Conflict"
          def_r <- "keep_target"
          if (!is_prot && !ambig && has_base && lb$in_base) {
            if (vpro_same_nullable_str(tv, lb$val) && !vpro_same_nullable_str(sv, lb$val)) {
              knd <- "FastForward"
              def_r <- "accept_source"
              has_fast_forward <- TRUE
            } else if (vpro_same_nullable_str(sv, lb$val) && !vpro_same_nullable_str(tv, lb$val)) {
              knd <- "TargetModifiedOnly"
              def_r <- "keep_target"
            } else {
              has_real_conflict <- TRUE
            }
          } else {
            has_real_conflict <- TRUE
          }

          push_item(
            paste0(plot, "::", suffix, "::", fld_key),
            plot, suffix, fld_key, col_nm,
            lb$val, sv, tv,
            knd, def_r, is_prot
          )
        }
      }
    }

    n_pl_items <- length(it_cid) - before_n
    plot_n_items[[pi]] <- n_pl_items

    if (n_pl_items == 0L) {
      identical_count <- identical_count + 1L
      plot_cats[[pi]] <- "Identical"
    } else if (!has_real_conflict && has_fast_forward) {
      fast_forward_count <- fast_forward_count + 1L
      plot_cats[[pi]] <- "FastForward"
    } else if (!has_real_conflict) {
      target_only_count <- target_only_count + 1L
      plot_cats[[pi]] <- "TargetOnly"
    } else {
      conflict_count <- conflict_count + 1L
      plot_cats[[pi]] <- "Conflict"
    }
  }

  plots_tbl <- tibble::tibble(
    PlotNumber = overlap_plots,
    category = plot_cats,
    n_items = plot_n_items
  )

  items_tbl <- tibble::tibble(
    conflict_id = it_cid,
    PlotNumber = it_plot,
    table = it_tbl,
    key = it_key,
    field = it_fld,
    base_val = it_base,
    source_val = it_src,
    target_val = it_tgt,
    kind = it_kind,
    default_resolution = it_def,
    custodian_protected = it_prot
  )

  conflicts_tbl <- items_tbl[items_tbl$kind == "Conflict", , drop = FALSE]
  protected_tbl <- items_tbl[items_tbl$custodian_protected, , drop = FALSE]

  out <- structure(
    list(
      submission_id = sub_id,
      source_project = src_proj,
      target_project = "BECMaster",
      base_db = if (is.null(base_db) || is.na(base_db)) "" else as.character(base_db),
      base_project = if (is.null(base_project) || is.na(base_project)) "" else as.character(base_project),
      preview_digest = preview_digest,
      added_count = as.integer(added_count),
      identical_count = as.integer(identical_count),
      fast_forward_count = as.integer(fast_forward_count),
      conflict_count = as.integer(conflict_count),
      target_only_count = as.integer(target_only_count),
      plots = plots_tbl,
      items = items_tbl,
      conflicts = conflicts_tbl,
      custodian_protected_diffs = protected_tbl
    ),
    class = "vpro_merge_preview"
  )
  attr(out, "snapshots") <- list(src = src_snap, tgt = tgt_snap, base = base_snap)
  out
}
