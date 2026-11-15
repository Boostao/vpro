# Atomic SERIALIZABLE Custodian 3-Way Merge Execution ------------------------

#' Execute an atomic `SERIALIZABLE` custodian merge from `staging` into `BECMaster`
#'
#' Locks the pending `staging.submissions` record inside a single PostgreSQL
#' `SERIALIZABLE` transaction, re-verifies the 3-way merge preview (enforcing
#' `expected_digest` when supplied), resolves every plot and field/row change
#' using VPro Desktop custodial precedence (`field_resolutions` ->
#' custodian-protected `keep_target` guard -> `plot_resolutions` ->
#' `FastForward`/`TargetModifiedOnly` item defaults -> `default_resolution`),
#' validates UTF-16 bounds, IEEE-754 `float32 < 100` covers, and `LMH25 (2023)`
#' soil horizon depth signs, allocates non-reused child `ID`s via
#' `becmaster.child_identity_watermark` + `becmaster.child_identity`, appends
#' SHA-256 hash-chained rows to `becmaster.audit` (verifiable via
#' `vpro_master_audit(pg, verify_chain = TRUE)`), and records provenance in
#' `becmaster.merge_ledger` and `staging.submissions`.
#'
#' @param pg A custodian `vpro_pg_conn` connection (`role == "custodian"`) from
#'   [vpro_master_connect()].
#' @param submission_id Pending staging submission UUID string.
#' @param default_resolution Fallback resolution for unresolved `Conflict` items:
#'   `"keep_target"` (default) or `"accept_source"`.
#' @param plot_resolutions Optional named character vector (`PlotNumber ->
#'   "keep_target" | "accept_source"`). Note: custodian-protected `Admin` fields
#'   (`BECSiteUnit`, `BEC_Use`, `GIS_BGC`) still default to `"keep_target"`
#'   unless explicitly listed in `field_resolutions`.
#' @param field_resolutions Optional named character vector (`conflict_id ->
#'   "keep_target" | "accept_source"`).
#' @param expected_digest Optional 64-character SHA-256 `preview_digest` from
#'   [vpro_staging_diff()] for optimistic concurrency verification.
#' @param reviewer_notes Optional custodian review note stored on
#'   `staging.submissions`.
#' @param base_db Optional common ancestor `VP08` SQLite `.db` path or
#'   `vpro_workspace` handle matching [vpro_staging_diff()].
#' @param base_project Optional project prefix inside `base_db`.
#' @param actor Optional custodian actor name recorded in `becmaster.audit` and
#'   `becmaster.merge_ledger` (defaults to PostgreSQL `current_user`).
#' @return A named list with `merge_tx_id`, `submission_id`, `source_project`,
#'   `added_plots`, `updated_plots`, `skipped_plots`, `allocated_child_ids`,
#'   `reserved_deleted_ids`, `audit_rows_written`, `tail_audit_hash`, and
#'   `merged_at`.
#' @export
vpro_staging_merge <- function(
  pg,
  submission_id,
  default_resolution = c("keep_target", "accept_source"),
  plot_resolutions = NULL,
  field_resolutions = NULL,
  expected_digest = NULL,
  reviewer_notes = NULL,
  base_db = NULL,
  base_project = NULL,
  actor = NULL
) {
  vpro_assert_pg_conn(pg, require_custodian = TRUE)
  sub_id <- vpro_validate_uuid_arg(submission_id, "submission_id")
  default_resolution <- match.arg(default_resolution)
  plot_res <- vpro_validate_merge_resolution_vec(plot_resolutions, "plot_resolutions")
  field_res <- vpro_validate_merge_resolution_vec(field_resolutions, "field_resolutions")
  expected_clean <- vpro_validate_optional_scalar_chr(expected_digest, "expected_digest")
  rev_notes_clean <- vpro_validate_optional_scalar_chr(reviewer_notes, "reviewer_notes")
  actor_clean <- vpro_validate_optional_scalar_chr(actor, "actor")

  base_info <- vpro_resolve_sqlite_base_db(base_db, base_project)
  preloaded_base <- vpro_load_sqlite_base_tables(base_info)

  resolve_choice <- function(item_row) {
    cid <- item_row$conflict_id[[1L]]
    pnum <- item_row$PlotNumber[[1L]]
    if (cid %in% names(field_res)) {
      return(unname(field_res[[cid]]))
    }
    if (isTRUE(item_row$custodian_protected[[1L]])) {
      return("keep_target")
    }
    if (pnum %in% names(plot_res)) {
      return(unname(plot_res[[pnum]]))
    }
    knd <- item_row$kind[[1L]]
    if (knd %in% c("FastForward", "TargetModifiedOnly")) {
      return(item_row$default_resolution[[1L]])
    }
    default_resolution
  }

  pg_tbl_map <- c(
    Env = "env", Admin = "admin", Veg = "veg",
    Humus = "humus", Mineral = "mineral", Other = "other"
  )
  spec_cache <- stats::setNames(
    lapply(c(.vpro_merge_table_suffixes, "Metadata", "Audit"), vpro_pg_vp08_specs),
    c(.vpro_merge_table_suffixes, "Metadata", "Audit")
  )

  vpro_pg_exec_safe(
    function() {
      tx_committed <- FALSE
      vpro_pg_begin_isolated_tx(pg$conn, "BEGIN ISOLATION LEVEL SERIALIZABLE", "vpro_staging_merge")
      on.exit({
        if (!tx_committed && isTRUE(tryCatch(DBI::dbIsValid(pg$conn), error = function(e) FALSE))) {
          tryCatch(DBI::dbExecute(pg$conn, "ROLLBACK"), error = function(e) NULL)
        }
      }, add = TRUE)

      lock_df <- DBI::dbGetQuery(
        pg$conn,
        paste(
          "SELECT status, current_user AS db_user, source_db_sha256,",
          "       to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD HH24:MI:SS') AS now_edit_str,",
          "       to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD\"T\"HH24:MI:SS\"Z\"') AS now_iso_str",
          "FROM staging.submissions",
          "WHERE submission_id = $1::uuid",
          "FOR UPDATE"
        ),
        params = list(sub_id)
      )
      if (nrow(lock_df) == 0L) {
        cli::cli_abort("Staging submission {.val {sub_id}} was not found.")
      }
      cur_status <- as.character(lock_df$status[[1L]])
      if (!identical(cur_status, "pending")) {
        cli::cli_abort(
          "Staging submission {.val {sub_id}} has status {.val {cur_status}} (only {.val pending} submissions can be merged)."
        )
      }

      actor_eff <- if (!is.na(actor_clean)) actor_clean else as.character(lock_df$db_user[[1L]])
      src_sha <- as.character(lock_df$source_db_sha256[[1L]])
      now_edit_str <- as.character(lock_df$now_edit_str[[1L]])
      now_iso_str <- as.character(lock_df$now_iso_str[[1L]])

      built <- vpro_build_pg_merge_preview_on_conn(
        conn = pg$conn,
        sub_id = sub_id,
        base_info = base_info,
        preloaded_base_tables = preloaded_base
      )
      preview <- built$preview
      snaps <- attr(preview, "snapshots")
      src_snap <- snaps$src
      tgt_snap <- snaps$tgt

      if (!is.na(expected_clean) && !identical(preview$preview_digest, tolower(expected_clean))) {
        cli::cli_abort(
          "Staging or BECMaster plots changed since preview (expected digest {.val {expected_clean}}, got {.val {preview$preview_digest}}); re-run {.fn vpro_staging_diff} before merging."
        )
      }

      merge_tx_id <- vpro_uuid_v4()

      aud_plot <- character(0L)
      aud_tbl <- character(0L)
      aud_fld <- character(0L)
      aud_before <- character(0L)
      aud_after <- character(0L)
      aud_id <- numeric(0L)

      record_audit <- function(plot_s, suffix_s, fld_s, before_v, after_v, child_id = NA_real_) {
        k <- length(aud_plot) + 1L
        aud_plot[[k]] <<- as.character(plot_s)
        aud_tbl[[k]] <<- paste0("_", suffix_s)
        aud_fld[[k]] <<- as.character(fld_s)
        aud_before[[k]] <<- if (is.null(before_v) || length(before_v) == 0L || is.na(before_v[[1L]])) {
          NA_character_
        } else {
          as.character(before_v[[1L]])
        }
        aud_after[[k]] <<- if (is.null(after_v) || length(after_v) == 0L || is.na(after_v[[1L]])) {
          NA_character_
        } else {
          as.character(after_v[[1L]])
        }
        aud_id[[k]] <<- if (is.null(child_id) || length(child_id) == 0L || is.na(child_id[[1L]])) {
          NA_real_
        } else {
          as.double(child_id[[1L]])
        }
      }

      allocated_ids <- numeric(0L)
      reserved_deleted_ids <- numeric(0L)
      added_plots <- 0L
      updated_plots <- 0L
      skipped_plots <- 0L

      insert_parent_row <- function(suffix, plot) {
        spec <- spec_cache[[suffix]]
        key_col <- if (identical(suffix, "Admin")) "Plot" else "PlotNumber"
        p_raw_df <- src_snap$raw[[suffix]][[plot]]
        p_comp_df <- src_snap$comp[[suffix]][[plot]]
        if (is.null(p_raw_df) || !(suffix %in% rownames(p_raw_df))) {
          cli::cli_abort("Staging plot {.val {plot}} is missing required {.val {suffix}} row.")
        }
        raw_row <- p_raw_df[suffix, , drop = FALSE]
        comp_row <- p_comp_df[suffix, , drop = FALSE]

        placeholders <- character(nrow(spec))
        params <- vector("list", nrow(spec))
        for (i in seq_len(nrow(spec))) {
          c_row <- spec[i, , drop = FALSE]
          cn <- c_row$name[[1L]]
          placeholders[[i]] <- paste0("$", i, "::", tolower(c_row$pg_type[[1L]]))
          if (identical(cn, key_col)) {
            vpro_validate_merge_cell_value(suffix, c_row, plot, plot = plot)
            params[[i]] <- plot
          } else {
            rv <- raw_row[[cn]][[1L]]
            vpro_validate_merge_cell_value(suffix, c_row, rv, plot = plot)
            params[[i]] <- vpro_pg_param_for_spec(c_row, rv)
          }
        }

        col_csv <- paste(vapply(spec$name, vpro_quote_ident, character(1L)), collapse = ", ")
        ins_sql <- paste0(
          "INSERT INTO becmaster.", vpro_quote_ident(pg_tbl_map[[suffix]]),
          " (", col_csv, ") VALUES (", paste(placeholders, collapse = ", "), ")"
        )
        DBI::dbExecute(pg$conn, ins_sql, params = params)

        record_audit(plot, suffix, key_col, NA_character_, plot, NA_real_)
        for (i in seq_len(nrow(spec))) {
          cn <- spec$name[[i]]
          if (identical(cn, key_col)) next
          cv <- comp_row[[cn]][[1L]]
          if (!is.na(cv)) {
            record_audit(plot, suffix, cn, NA_character_, cv, NA_real_)
          }
        }
      }

      insert_child_row <- function(suffix, plot, rk) {
        spec <- spec_cache[[suffix]]
        pg_tbl <- pg_tbl_map[[suffix]]
        raw_row <- src_snap$raw[[suffix]][[plot]][rk, , drop = FALSE]
        comp_row <- src_snap$comp[[suffix]][[plot]][rk, , drop = FALSE]

        if (suffix %in% c("Humus", "Mineral")) {
          vpro_validate_lmh25_merge_horizon(
            suffix = suffix,
            horizon = comp_row[["Horizon"]][[1L]],
            upper_depth = raw_row[["UpperDepth"]][[1L]],
            lower_depth = raw_row[["LowerDepth"]][[1L]],
            plot = plot
          )
        }

        new_id <- vpro_allocate_master_child_id(pg$conn, pg_tbl)
        allocated_ids <<- c(allocated_ids, new_id)

        placeholders <- character(nrow(spec))
        params <- vector("list", nrow(spec))
        for (i in seq_len(nrow(spec))) {
          c_row <- spec[i, , drop = FALSE]
          cn <- c_row$name[[1L]]
          placeholders[[i]] <- paste0("$", i, "::", tolower(c_row$pg_type[[1L]]))
          if (identical(cn, "PlotNumber")) {
            params[[i]] <- plot
          } else if (identical(cn, "ID")) {
            params[[i]] <- vpro_pg_param_for_spec(c_row, new_id)
          } else {
            rv <- raw_row[[cn]][[1L]]
            vpro_validate_merge_cell_value(suffix, c_row, rv, plot = plot)
            params[[i]] <- vpro_pg_param_for_spec(c_row, rv)
          }
        }

        col_csv <- paste(vapply(spec$name, vpro_quote_ident, character(1L)), collapse = ", ")
        ins_sql <- paste0(
          "INSERT INTO becmaster.", vpro_quote_ident(pg_tbl),
          " (", col_csv, ") VALUES (", paste(placeholders, collapse = ", "), ")"
        )
        DBI::dbExecute(pg$conn, ins_sql, params = params)

        for (i in seq_len(nrow(spec))) {
          cn <- spec$name[[i]]
          if (cn %in% c("PlotNumber", "ID")) next
          cv <- comp_row[[cn]][[1L]]
          if (is.na(cv) || (identical(cn, "Flag") && identical(cv, "0"))) next
          record_audit(plot, suffix, cn, NA_character_, cv, new_id)
        }
      }

      insert_whole_plot <- function(plot) {
        u16_p <- vpro_utf16_len(plot)
        if (is.na(u16_p) || u16_p > 7L) {
          cli::cli_abort("PlotNumber {.val {plot}} exceeds 7 UTF-16 code units or contains invalid UTF-8.")
        }
        insert_parent_row("Env", plot)
        insert_parent_row("Admin", plot)
        for (suffix in c("Veg", "Humus", "Mineral", "Other")) {
          c_df <- src_snap$raw[[suffix]][[plot]]
          if (is.null(c_df) || nrow(c_df) == 0L) next
          rks <- sort(rownames(c_df), method = "radix")
          for (rk in rks) {
            insert_child_row(suffix, plot, rk)
          }
        }
      }

      items_by_plot <- if (nrow(preview$items) > 0L) {
        split(preview$items, preview$items$PlotNumber)
      } else {
        list()
      }

      for (pi in seq_len(nrow(preview$plots))) {
        plot <- preview$plots$PlotNumber[[pi]]
        cat_p <- preview$plots$category[[pi]]

        if (cat_p %in% c("Identical", "TargetOnly")) {
          skipped_plots <- skipped_plots + 1L
          next
        }

        if (identical(cat_p, "Added")) {
          if ((plot %in% names(plot_res)) && identical(unname(plot_res[[plot]]), "keep_target")) {
            skipped_plots <- skipped_plots + 1L
            next
          }
          insert_whole_plot(plot)
          added_plots <- added_plots + 1L
          next
        }

        p_items <- items_by_plot[[plot]]
        if (is.null(p_items) || nrow(p_items) == 0L) {
          skipped_plots <- skipped_plots + 1L
          next
        }

        if (nrow(p_items) == 1L && identical(p_items$key[[1L]], "Plot") &&
            !(plot %in% tgt_snap$plots) && (plot %in% src_snap$plots)) {
          if (identical(resolve_choice(p_items[1L, , drop = FALSE]), "accept_source")) {
            insert_whole_plot(plot)
            added_plots <- added_plots + 1L
          } else {
            skipped_plots <- skipped_plots + 1L
          }
          next
        }

        plot_modified <- FALSE
        touched_horizons <- list()

        for (ii in seq_len(nrow(p_items))) {
          item <- p_items[ii, , drop = FALSE]
          if (!identical(resolve_choice(item), "accept_source")) {
            next
          }
          suffix <- item$table[[1L]]
          pg_tbl <- pg_tbl_map[[suffix]]
          spec <- spec_cache[[suffix]]
          fld <- item$field[[1L]]

          if (suffix %in% c("Env", "Admin")) {
            key_col <- if (identical(suffix, "Admin")) "Plot" else "PlotNumber"
            if (identical(fld, "*")) {
              if (!is.na(item$source_val[[1L]]) && is.na(item$target_val[[1L]])) {
                insert_parent_row(suffix, plot)
                plot_modified <- TRUE
              }
              next
            }
            c_idx <- match(fld, spec$name)
            if (is.na(c_idx)) {
              cli::cli_abort("Unknown column {suffix}.{fld}.")
            }
            c_row <- spec[c_idx, , drop = FALSE]
            rv <- src_snap$raw[[suffix]][[plot]][suffix, fld, drop = TRUE]
            vpro_validate_merge_cell_value(suffix, c_row, rv, plot = plot)
            param_val <- vpro_pg_param_for_spec(c_row, rv)
            upd_sql <- paste0(
              "UPDATE becmaster.", vpro_quote_ident(pg_tbl),
              " SET ", vpro_quote_ident(fld), " = $1::", tolower(c_row$pg_type[[1L]]),
              " WHERE ", vpro_quote_ident(key_col), " = $2"
            )
            aff <- DBI::dbExecute(pg$conn, upd_sql, params = list(param_val, plot))
            if (!identical(as.integer(aff), 1L)) {
              cli::cli_abort(
                "Merge update on {suffix}.{fld} for plot {.val {plot}} matched {aff} rows (expected 1)."
              )
            }
            record_audit(plot, suffix, fld, item$target_val[[1L]], item$source_val[[1L]], NA_real_)
            plot_modified <- TRUE
            next
          }

          # Child table row insert / delete / field update
          if (identical(fld, "*")) {
            rk <- item$key[[1L]]
            if (!is.na(item$source_val[[1L]]) && is.na(item$target_val[[1L]])) {
              insert_child_row(suffix, plot, rk)
              plot_modified <- TRUE
            } else if (is.na(item$source_val[[1L]]) && !is.na(item$target_val[[1L]])) {
              t_raw_row <- tgt_snap$raw[[suffix]][[plot]][rk, , drop = FALSE]
              t_comp_row <- tgt_snap$comp[[suffix]][[plot]][rk, , drop = FALSE]
              tgt_id <- t_raw_row[["ID"]][[1L]]
              if (is.na(tgt_id)) {
                cli::cli_abort("Target {suffix} row in plot {.val {plot}} lacks an integer ID.")
              }
              vpro_reserve_master_child_id(pg$conn, pg_tbl, tgt_id)
              reserved_deleted_ids <- c(reserved_deleted_ids, as.double(tgt_id))

              del_sql <- paste0(
                "DELETE FROM becmaster.", vpro_quote_ident(pg_tbl),
                ' WHERE "PlotNumber" = $1 AND "ID" = $2::bigint'
              )
              aff <- DBI::dbExecute(pg$conn, del_sql, params = list(plot, sprintf("%.0f", tgt_id)))
              if (!identical(as.integer(aff), 1L)) {
                cli::cli_abort(
                  "Child delete on {suffix} (plot {.val {plot}}, ID {sprintf('%.0f', tgt_id)}) matched {aff} rows."
                )
              }
              for (ci in seq_len(nrow(spec))) {
                cn <- spec$name[[ci]]
                if (cn %in% c("PlotNumber", "ID")) next
                old_v <- t_comp_row[[cn]][[1L]]
                if (is.na(old_v) || (identical(cn, "Flag") && identical(old_v, "0"))) next
                record_audit(plot, suffix, cn, old_v, NA_character_, tgt_id)
              }
              plot_modified <- TRUE
            }
            next
          }

          full_key <- item$key[[1L]]
          suffix_dot <- paste0(".", fld)
          if (!endsWith(full_key, suffix_dot) || nchar(full_key) <= nchar(suffix_dot)) {
            cli::cli_abort("Malformed child conflict key {.val {full_key}}.")
          }
          rk <- substr(full_key, 1L, nchar(full_key) - nchar(suffix_dot))

          c_idx <- match(fld, spec$name)
          if (is.na(c_idx)) {
            cli::cli_abort("Unknown child column {suffix}.{fld}.")
          }
          c_row <- spec[c_idx, , drop = FALSE]
          rv <- src_snap$raw[[suffix]][[plot]][rk, fld, drop = TRUE]
          vpro_validate_merge_cell_value(suffix, c_row, rv, plot = plot)
          param_val <- vpro_pg_param_for_spec(c_row, rv)

          tgt_id <- tgt_snap$raw[[suffix]][[plot]][rk, "ID", drop = TRUE]
          if (is.na(tgt_id)) {
            cli::cli_abort("Target {suffix} row in plot {.val {plot}} lacks an integer ID.")
          }

          upd_sql <- paste0(
            "UPDATE becmaster.", vpro_quote_ident(pg_tbl),
            " SET ", vpro_quote_ident(fld), " = $1::", tolower(c_row$pg_type[[1L]]),
            ' WHERE "PlotNumber" = $2 AND "ID" = $3::bigint'
          )
          aff <- DBI::dbExecute(pg$conn, upd_sql, params = list(param_val, plot, sprintf("%.0f", tgt_id)))
          if (!identical(as.integer(aff), 1L)) {
            cli::cli_abort(
              "Child update on {suffix}.{fld} (plot {.val {plot}}, ID {sprintf('%.0f', tgt_id)}) matched {aff} rows."
            )
          }
          record_audit(plot, suffix, fld, item$target_val[[1L]], item$source_val[[1L]], tgt_id)

          if (suffix %in% c("Humus", "Mineral")) {
            th_key <- paste0(suffix, "::", plot, "::", sprintf("%.0f", tgt_id))
            touched_horizons[[th_key]] <- list(suffix = suffix, plot = plot, id = tgt_id)
          }
          plot_modified <- TRUE
        }

        if (length(touched_horizons) > 0L) {
          for (th in touched_horizons) {
            hz_df <- DBI::dbGetQuery(
              pg$conn,
              paste0(
                'SELECT "Horizon", "UpperDepth", "LowerDepth" FROM becmaster.',
                vpro_quote_ident(pg_tbl_map[[th$suffix]]),
                ' WHERE "PlotNumber" = $1 AND "ID" = $2::bigint'
              ),
              params = list(th$plot, sprintf("%.0f", th$id))
            )
            if (nrow(hz_df) >= 1L) {
              vpro_validate_lmh25_merge_horizon(
                suffix = th$suffix,
                horizon = hz_df$Horizon[[1L]],
                upper_depth = hz_df$UpperDepth[[1L]],
                lower_depth = hz_df$LowerDepth[[1L]],
                plot = th$plot
              )
            }
          }
        }

        if (plot_modified) {
          updated_plots <- updated_plots + 1L
        } else {
          skipped_plots <- skipped_plots + 1L
        }
      }

      # Insert genuinely new ProjectID metadata rows into becmaster.metadata
      if (added_plots > 0L || updated_plots > 0L) {
        meta_spec <- spec_cache$Metadata
        meta_csv <- paste(vapply(meta_spec$name, vpro_quote_ident, character(1L)), collapse = ", ")
        new_meta <- DBI::dbGetQuery(
          pg$conn,
          paste0(
            "SELECT ", meta_csv, " FROM staging.metadata AS s ",
            "WHERE s.submission_id = $1::uuid ",
            '  AND s."ProjectID" IS NOT NULL AND s."ProjectID" <> \'\' ',
            '  AND NOT EXISTS (SELECT 1 FROM becmaster.metadata AS m WHERE m."ProjectID" = s."ProjectID")'
          ),
          params = list(sub_id)
        )
        if (nrow(new_meta) > 0L) {
          m_placeholders <- paste0("$", seq_len(nrow(meta_spec)), "::", tolower(meta_spec$pg_type))
          ins_meta_sql <- paste0(
            "INSERT INTO becmaster.metadata (", meta_csv, ") VALUES (",
            paste(m_placeholders, collapse = ", "),
            ') ON CONFLICT ("ProjectID") DO NOTHING'
          )
          for (mi in seq_len(nrow(new_meta))) {
            new_m_id <- vpro_allocate_master_child_id(pg$conn, "metadata")
            m_params <- vector("list", nrow(meta_spec))
            for (ci in seq_len(nrow(meta_spec))) {
              c_row <- meta_spec[ci, , drop = FALSE]
              cn <- c_row$name[[1L]]
              if (identical(cn, "ID")) {
                m_params[[ci]] <- vpro_pg_param_for_spec(c_row, new_m_id)
              } else {
                m_params[[ci]] <- vpro_pg_param_for_spec(c_row, new_meta[[cn]][[mi]])
              }
            }
            m_aff <- DBI::dbExecute(pg$conn, ins_meta_sql, params = m_params)
            if (identical(as.integer(m_aff), 1L)) {
              record_audit("", "Metadata", "ProjectID", NA_character_, as.character(new_meta$ProjectID[[mi]]), new_m_id)
            }
          }
        }
      }

      # Append hash-chained audit rows into becmaster.audit
      tail_df <- DBI::dbGetQuery(
        pg$conn,
        "SELECT row_hash FROM becmaster.audit ORDER BY audit_seq DESC LIMIT 1"
      )
      prev_hash <- if (nrow(tail_df) >= 1L && !is.na(tail_df$row_hash[[1L]]) && nzchar(trimws(tail_df$row_hash[[1L]]))) {
        tolower(trimws(as.character(tail_df$row_hash[[1L]])))
      } else {
        .vpro_genesis_audit_hash
      }

      n_aud <- length(aud_plot)
      if (n_aud > 0L) {
        prev_vec <- character(n_aud)
        hash_vec <- character(n_aud)
        for (ai in seq_len(n_aud)) {
          id_cell <- if (is.na(aud_id[[ai]])) {
            NA_integer_
          } else if (abs(aud_id[[ai]]) <= .Machine$integer.max) {
            as.integer(aud_id[[ai]])
          } else {
            sprintf("%.0f", aud_id[[ai]])
          }
          vp08_vals <- list(
            "BECMaster",
            actor_eff,
            aud_plot[[ai]],
            aud_tbl[[ai]],
            aud_fld[[ai]],
            now_edit_str,
            aud_before[[ai]],
            aud_after[[ai]],
            0L,
            0L,
            id_cell
          )
          r_hash <- vpro_compute_audit_row_hash(prev_hash, merge_tx_id, vp08_vals)
          prev_vec[[ai]] <- prev_hash
          hash_vec[[ai]] <- r_hash
          prev_hash <- r_hash
        }

        id_col_out <- if (all(is.na(aud_id) | abs(aud_id) <= .Machine$integer.max)) {
          out_i <- rep(NA_integer_, n_aud)
          ok_i <- !is.na(aud_id)
          if (any(ok_i)) out_i[ok_i] <- as.integer(aud_id[ok_i])
          out_i
        } else {
          out_c <- rep(NA_character_, n_aud)
          ok_c <- !is.na(aud_id)
          if (any(ok_c)) out_c[ok_c] <- sprintf("%.0f", aud_id[ok_c])
          out_c
        }

        audit_df <- data.frame(
          Project = rep("BECMaster", n_aud),
          User = rep(actor_eff, n_aud),
          PlotNumber = aud_plot,
          Table = aud_tbl,
          EditField = aud_fld,
          EditWhen = rep(now_edit_str, n_aud),
          BeforeEdit = aud_before,
          AfterEdit = aud_after,
          Restore = rep(0L, n_aud),
          Flag = rep(0L, n_aud),
          ID = id_col_out,
          merge_tx_id = rep(merge_tx_id, n_aud),
          prev_hash = prev_vec,
          row_hash = hash_vec,
          stringsAsFactors = FALSE
        )
        rownames(audit_df) <- NULL
        DBI::dbAppendTable(
          pg$conn,
          DBI::Id(schema = "becmaster", table = "audit"),
          audit_df
        )
      }

      summary_json <- as.character(jsonlite::toJSON(
        list(
          sourceProject = preview$source_project,
          previewDigest = preview$preview_digest,
          addedPlots = as.integer(added_plots),
          updatedPlots = as.integer(updated_plots),
          skippedPlots = as.integer(skipped_plots),
          auditRowsWritten = as.integer(n_aud),
          allocatedChildIds = as.integer(length(allocated_ids)),
          reservedDeletedIds = as.integer(length(reserved_deleted_ids)),
          tailAuditHash = prev_hash
        ),
        auto_unbox = TRUE
      ))

      DBI::dbExecute(
        pg$conn,
        paste(
          "INSERT INTO becmaster.merge_ledger (",
          "  merge_tx_id, submission_id, actor, merged_at, source_sha256,",
          "  added_plots, updated_plots, summary_json",
          ") VALUES (",
          "  $1::uuid, $2::uuid, $3, $4::timestamptz, $5,",
          "  $6::int, $7::int, $8::jsonb",
          ")"
        ),
        params = list(
          merge_tx_id,
          sub_id,
          actor_eff,
          now_iso_str,
          src_sha,
          as.integer(added_plots),
          as.integer(updated_plots),
          summary_json
        )
      )

      DBI::dbExecute(
        pg$conn,
        paste(
          "UPDATE staging.submissions",
          "SET status = 'merged',",
          "    reviewed_by = $2,",
          "    reviewed_at = $3::timestamptz,",
          "    reviewer_notes = COALESCE($4::text, reviewer_notes),",
          "    merged_tx_id = $5::uuid",
          "WHERE submission_id = $1::uuid"
        ),
        params = list(sub_id, actor_eff, now_iso_str, rev_notes_clean, merge_tx_id)
      )

      DBI::dbExecute(pg$conn, "COMMIT")
      tx_committed <- TRUE

      norm_id_vec <- function(v) {
        if (length(v) == 0L) return(integer(0L))
        v <- sort(v)
        if (all(abs(v) <= .Machine$integer.max)) as.integer(v) else v
      }

      list(
        merge_tx_id = merge_tx_id,
        submission_id = sub_id,
        source_project = preview$source_project,
        added_plots = as.integer(added_plots),
        updated_plots = as.integer(updated_plots),
        skipped_plots = as.integer(skipped_plots),
        allocated_child_ids = norm_id_vec(allocated_ids),
        reserved_deleted_ids = norm_id_vec(unique(reserved_deleted_ids)),
        audit_rows_written = as.integer(n_aud),
        tail_audit_hash = prev_hash,
        merged_at = now_iso_str
      )
    },
    action = "execute SERIALIZABLE staging-to-BECMaster merge"
  )
}
