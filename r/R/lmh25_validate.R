# Unified VP08 & LMH25 Project Validation Engine -----------------------------

#' Run comprehensive VPro workspace standards, referential, and `LMH25` QA
#'
#' Combines canonical VPro validation engines into a single read-only
#' quality-assurance bundle, selectable via `checks = c("all", "compliance", "lmh25")`:
#' 1. **`env_codes`**: `USysTableOfLists` picklist validation (`Validate != 0`,
#'    expanding `ValidateLoops` such as `SiteDisturbance1..3`, matching VPro
#'    Desktop environment checks).
#' 2. **`veg_codes`**: `BCPlantTaxonomy v19` (`USysAllSpecs`) + user species
#'    (`USysUserSpp`) check for unlisted codes, local user codes (`"user"`), and
#'    case-insensitive `OldCode -> Code` synonyms.
#' 3. **`orphans`**: referential integrity across `_Env <-> _Admin`, `_Veg`,
#'    `_Humus`, `_Mineral`, `_Other`, and active `*_SU`, plus plots without
#'    vegetation.
#' 4. **`duplicates`**: duplicate physical `(PlotNumber, Species)` rows and
#'    same-layer cover collisions.
#' 5. **`bounds`**: VPro field length limits, `0` to under `100%` cover bounds,
#'    and numeric `_Env` / `_Admin` bounds (`Latitude`, `Longitude`, `Aspect`,
#'    `SlopeGradient`, `StartDate`).
#' 6. **`lmh25`**: `LMH25 (2023)` pedological & edatopic audit (horizon depth
#'    directions, contiguity, substrate sums, von Post ranges, Keys `9.4`/`9.6`).
#'
#' @param ws A `vpro_workspace` handle from [vpro_connect()].
#' @param scope Validation scope: `"su"` (restricts plot-scoped checks to active
#'   `ws$su` when set) or `"project"` (validates the entire `<Project>`).
#' @param checks Which validation engines to execute: `"all"` (default),
#'   `"compliance"` (VP08 standards/bounds/referential checks only), or `"lmh25"`
#'   (pedological & edatopic audit only).
#' @return An S3 object of class `vpro_validation` containing `$issues`,
#'   `$env_codes`, `$veg_codes`, `$orphans`, `$duplicates`, `$bounds`,
#'   `$lmh25`, `$skipped_definitions`, `$checks`, and `$passed`.
#' @export
vpro_validate <- function(
  ws,
  scope = c("su", "project"),
  checks = c("all", "compliance", "lmh25")
) {
  vpro_assert_workspace(ws)
  scope <- match.arg(scope)
  checks <- match.arg(checks)
  use_su <- identical(scope, "su") && !is.null(ws$su)

  run_compliance <- checks %in% c("all", "compliance")
  run_lmh25 <- checks %in% c("all", "lmh25")

  env_codes_tbl <- tibble::tibble(list_name = character(), field = character(), PlotNumber = character(), value = character())
  skipped_tbl <- tibble::tibble(list_name = character(), field = character(), reason = character())
  veg_codes_tbl <- tibble::tibble(PlotNumber = character(), Species = character(), status = character(), suggested_code = character())
  orphans_tbl <- tibble::tibble(table = character(), PlotNumber = character(), issue = character(), n_rows = integer())
  duplicates_tbl <- tibble::tibble(PlotNumber = character(), Species = character(), overlapping_layers = character(), n_rows = integer(), same_layer_conflict = logical())
  bounds_tbl <- tibble::tibble(table = character(), PlotNumber = character(), field = character(), value = character(), rule = character())

  if (run_compliance) {
    dbc <- vpro_sqlite_ro(ws$project_path)
    on.exit(DBI::dbDisconnect(dbc), add = TRUE)

    dbc_vlists <- vpro_sqlite_ro(ws$vlists_path)
    on.exit(DBI::dbDisconnect(dbc_vlists), add = TRUE)

    su_df <- if (!is.null(ws$su)) {
      vpro_site_units(ws, exclude_modifiers = FALSE)
    } else {
      tibble::tibble(PlotNumber = character(), SiteUnit = character())
    }
    su_plots <- unique(as.character(su_df[["PlotNumber"]]))

    env_tbl <- paste0(ws$project, "_Env")
    adm_tbl <- paste0(ws$project, "_Admin")
    veg_tbl <- paste0(ws$project, "_Veg")
    env_q <- vpro_quote_ident(env_tbl)
    adm_q <- vpro_quote_ident(adm_tbl)
    veg_q <- vpro_quote_ident(veg_tbl)

    # 1. USysTableOfLists environment code picklist validation
    env_cols <- DBI::dbListFields(dbc, env_tbl)
    adm_cols <- if (DBI::dbExistsTable(dbc, adm_tbl)) DBI::dbListFields(dbc, adm_tbl) else character()
    env_col_map <- stats::setNames(env_cols, tolower(env_cols))
    adm_col_map <- stats::setNames(adm_cols, tolower(adm_cols))

    defs <- DBI::dbGetQuery(
      dbc_vlists,
      paste(
        'SELECT COALESCE(MIN("ListName"), \'\') AS "ListName",',
        'COALESCE(MIN("FieldUsedIn"), \'\') AS "FieldUsedIn",',
        'COALESCE(CAST("ValidateLoops" AS TEXT), \'\') AS "ValidateLoops"',
        'FROM "USysTableOfLists"',
        'WHERE "Validate" IS NOT NULL AND "Validate" <> 0',
        'GROUP BY "ListName" COLLATE NOCASE, "FieldUsedIn" COLLATE NOCASE, "ValidateLoops"',
        'ORDER BY "ListName" COLLATE NOCASE, "FieldUsedIn" COLLATE NOCASE, "ValidateLoops"'
      )
    )
    all_list_rows <- DBI::dbGetQuery(
      dbc_vlists,
      'SELECT "ListName", "Item" FROM "USysTableOfLists" WHERE "ListName" IS NOT NULL AND "Item" IS NOT NULL'
    )

    # Query Env and Admin separately to avoid column collision in R
    env_valid_plots <- DBI::dbGetQuery(
      dbc,
      paste0(
        "SELECT CAST(env.\"PlotNumber\" AS TEXT) AS \"PlotNumber\" FROM ",
        env_q,
        " AS env INNER JOIN ",
        adm_q,
        " AS admin ON typeof(env.\"PlotNumber\") = 'text' AND typeof(admin.\"Plot\") = 'text' ",
        "AND CAST(env.\"PlotNumber\" AS BLOB) = CAST(admin.\"Plot\" AS BLOB)"
      )
    )[["PlotNumber"]]
    if (use_su) {
      env_valid_plots <- intersect(env_valid_plots, su_plots)
    }

    env_raw <- vpro_query_scoped_plots(dbc, env_q, env_valid_plots)
    env_raw[["PlotNumber"]] <- as.character(env_raw[["PlotNumber"]])
    adm_raw <- if (length(env_valid_plots) > 0L) {
      a_all <- DBI::dbGetQuery(dbc, paste0('SELECT CAST("Plot" AS TEXT) AS "__Plot__", * FROM ', adm_q, ' WHERE typeof("Plot") = \'text\''))
      a_all[a_all[["__Plot__"]] %in% env_valid_plots, , drop = FALSE]
    } else {
      DBI::dbGetQuery(dbc, paste0('SELECT CAST("Plot" AS TEXT) AS "__Plot__", * FROM ', adm_q, ' WHERE 1 = 0'))
    }

    ec_list <- character()
    ec_field <- character()
    ec_plot <- character()
    ec_val <- character()
    sk_list <- character()
    sk_field <- character()
    sk_reason <- character()

    for (di in seq_len(nrow(defs))) {
      ln <- defs[["ListName"]][[di]]
      fu <- defs[["FieldUsedIn"]][[di]]
      lp <- trimws(defs[["ValidateLoops"]][[di]])
      if (!nzchar(trimws(ln))) {
        sk_list <- c(sk_list, ln)
        sk_field <- c(sk_field, fu)
        sk_reason <- c(sk_reason, "ListName is blank")
        next
      }
      if (!nzchar(trimws(fu))) {
        sk_list <- c(sk_list, ln)
        sk_field <- c(sk_field, fu)
        sk_reason <- c(sk_reason, "FieldUsedIn is blank")
        next
      }
      expanded <- fu
      if (nzchar(lp)) {
        if (!grepl("^-?[0-9]+$", lp)) {
          sk_list <- c(sk_list, ln)
          sk_field <- c(sk_field, fu)
          sk_reason <- c(sk_reason, "ValidateLoops is not an integer")
          next
        }
        n_lp <- as.integer(lp)
        if (n_lp > 0L) {
          expanded <- paste0(fu, seq_len(n_lp))
        }
      }

      allowed_low <- tolower(all_list_rows[["Item"]][tolower(all_list_rows[["ListName"]]) == tolower(ln)])

      for (fld in expanded) {
        lf <- tolower(fld)
        in_e <- lf %in% names(env_col_map)
        in_a <- lf %in% names(adm_col_map)
        if (in_e && in_a) {
          sk_list <- c(sk_list, ln)
          sk_field <- c(sk_field, fld)
          sk_reason <- c(sk_reason, "Field is ambiguous across Env and Admin")
          next
        }
        if (!in_e && !in_a) {
          sk_list <- c(sk_list, ln)
          sk_field <- c(sk_field, fld)
          sk_reason <- c(sk_reason, "Field not found in Env/Admin schema")
          next
        }
        if (in_e) {
          actual <- unname(env_col_map[[lf]])
          p_vec <- env_raw[["PlotNumber"]]
          v_vec <- env_raw[[actual]]
        } else {
          actual <- unname(adm_col_map[[lf]])
          p_vec <- adm_raw[["__Plot__"]]
          v_vec <- adm_raw[[actual]]
        }
        v_chr <- ifelse(is.na(v_vec), "", as.character(v_vec))
        bad <- !is.na(v_vec) & nzchar(v_chr) & !(tolower(v_chr) %in% allowed_low)
        if (any(bad)) {
          pairs <- unique(data.frame(p = p_vec[bad], v = v_chr[bad], stringsAsFactors = FALSE))
          pairs <- pairs[order(pairs$p, pairs$v), , drop = FALSE]
          ec_list <- c(ec_list, rep(ln, nrow(pairs)))
          ec_field <- c(ec_field, rep(fld, nrow(pairs)))
          ec_plot <- c(ec_plot, pairs$p)
          ec_val <- c(ec_val, pairs$v)
        }
      }
    }

    env_codes_tbl <- tibble::tibble(
      list_name = ec_list,
      field = ec_field,
      PlotNumber = ec_plot,
      value = ec_val
    )
    skipped_tbl <- tibble::tibble(
      list_name = sk_list,
      field = sk_field,
      reason = sk_reason
    )

    # 2. USysAllSpecs + USysUserSpp species code validation
    specs_all <- DBI::dbGetQuery(
      dbc_vlists,
      'SELECT COALESCE(CAST("Code" AS TEXT), \'\') AS "Code", COALESCE(CAST("OldCode" AS TEXT), \'\') AS "OldCode", COALESCE(LOWER(TRIM(CAST("Codetype" AS TEXT))), \'\') AS "Codetype" FROM "USysAllSpecs"'
    )
    code_trimmed <- trimws(as.character(specs_all[["Code"]]))
    old_trimmed <- trimws(as.character(specs_all[["OldCode"]]))
    accepted_low <- unique(tolower(code_trimmed[nzchar(code_trimmed) & specs_all[["Codetype"]] != "s"]))
    syn_keep <- nzchar(old_trimmed) & nzchar(code_trimmed) & tolower(old_trimmed) != tolower(code_trimmed)
    syn_rows <- specs_all[syn_keep, , drop = FALSE]
    syn_rows[["OldCode"]] <- old_trimmed[syn_keep]
    syn_rows[["Code"]] <- code_trimmed[syn_keep]
    syn_rows <- syn_rows[!duplicated(tolower(syn_rows[["OldCode"]])), , drop = FALSE]
    syn_map <- stats::setNames(syn_rows[["Code"]], tolower(syn_rows[["OldCode"]]))

    user_low <- character()
    if (file.exists(ws$vuser_path)) {
      dbc_vuser <- vpro_sqlite_ro(ws$vuser_path)
      on.exit(DBI::dbDisconnect(dbc_vuser), add = TRUE)
      if (DBI::dbExistsTable(dbc_vuser, "USysUserSpp")) {
        u_df <- DBI::dbGetQuery(dbc_vuser, 'SELECT COALESCE(CAST("Code" AS TEXT), \'\') AS "Code" FROM "USysUserSpp"')
        user_low <- unique(tolower(trimws(u_df[["Code"]][nzchar(trimws(u_df[["Code"]]))])))
      }
    }

    veg_scope_plots <- if (use_su) su_plots else NULL
    veg_codes_raw <- if (use_su) {
      vpro_query_scoped_plots(
        dbc,
        veg_q,
        veg_scope_plots,
        select_cols = 'CAST("PlotNumber" AS TEXT) AS "PlotNumber", CAST("Species" AS TEXT) AS "Species"'
      )
    } else {
      DBI::dbGetQuery(dbc, paste0('SELECT COALESCE(CAST("PlotNumber" AS TEXT), \'\') AS "PlotNumber", CAST("Species" AS TEXT) AS "Species" FROM ', veg_q))
    }

    vc_plot <- character()
    vc_spp <- character()
    vc_status <- character()
    vc_sugg <- character()

    if (nrow(veg_codes_raw) > 0L) {
      uniq_vs <- unique(veg_codes_raw)
      uniq_vs <- uniq_vs[order(uniq_vs[["PlotNumber"]], uniq_vs[["Species"]]), , drop = FALSE]
      for (vi in seq_len(nrow(uniq_vs))) {
        p_v <- as.character(uniq_vs[["PlotNumber"]][[vi]])
        s_v <- uniq_vs[["Species"]][[vi]]
        s_chr <- ifelse(is.na(s_v), "", trimws(as.character(s_v)))
        s_low <- tolower(s_chr)
        if (!nzchar(s_chr)) {
          vc_plot <- c(vc_plot, p_v)
          vc_spp <- c(vc_spp, s_chr)
          vc_status <- c(vc_status, "unlisted")
          vc_sugg <- c(vc_sugg, NA_character_)
        } else if (s_low %in% accepted_low) {
          next
        } else if (s_low %in% names(syn_map)) {
          vc_plot <- c(vc_plot, p_v)
          vc_spp <- c(vc_spp, s_chr)
          vc_status <- c(vc_status, "synonym")
          vc_sugg <- c(vc_sugg, unname(syn_map[[s_low]]))
        } else if (s_low %in% user_low) {
          vc_plot <- c(vc_plot, p_v)
          vc_spp <- c(vc_spp, s_chr)
          vc_status <- c(vc_status, "user")
          vc_sugg <- c(vc_sugg, NA_character_)
        } else {
          vc_plot <- c(vc_plot, p_v)
          vc_spp <- c(vc_spp, s_chr)
          vc_status <- c(vc_status, "unlisted")
          vc_sugg <- c(vc_sugg, NA_character_)
        }
      }
    }
    veg_codes_tbl <- tibble::tibble(
      PlotNumber = vc_plot,
      Species = vc_spp,
      status = vc_status,
      suggested_code = vc_sugg
    )

    # 3. Referential / orphan child check (_Admin, _Veg, _Humus, _Mineral, _Other, *_SU) & plots_without_veg
    or_tbl <- character()
    or_plot <- character()
    or_issue <- character()
    or_n <- integer()

    miss_adm <- DBI::dbGetQuery(
      dbc,
      paste0(
        'SELECT CAST(e."PlotNumber" AS TEXT) AS "PlotNumber" FROM ',
        env_q,
        ' AS e ',
        'WHERE NOT EXISTS (SELECT 1 FROM ',
        adm_q,
        ' AS a WHERE typeof(a."Plot") = \'text\' AND typeof(e."PlotNumber") = \'text\' AND CAST(a."Plot" AS BLOB) = CAST(e."PlotNumber" AS BLOB)) ORDER BY 1'
      )
    )
    if (nrow(miss_adm) > 0L) {
      or_tbl <- c(or_tbl, rep("Admin", nrow(miss_adm)))
      or_plot <- c(or_plot, as.character(miss_adm[["PlotNumber"]]))
      or_issue <- c(or_issue, rep("missing_admin", nrow(miss_adm)))
      or_n <- c(or_n, rep(1L, nrow(miss_adm)))
    }

    orph_adm <- DBI::dbGetQuery(
      dbc,
      paste0(
        'SELECT COALESCE(CAST(a."Plot" AS TEXT), \'<NULL>\') AS "PlotNumber", COUNT(*) AS "n" FROM ',
        adm_q,
        ' AS a ',
        'WHERE a."Plot" IS NULL OR typeof(a."Plot") <> \'text\' OR NOT EXISTS (SELECT 1 FROM ',
        env_q,
        ' AS e WHERE typeof(e."PlotNumber") = \'text\' AND CAST(e."PlotNumber" AS BLOB) = CAST(a."Plot" AS BLOB)) GROUP BY 1 ORDER BY 1'
      )
    )
    if (nrow(orph_adm) > 0L) {
      or_tbl <- c(or_tbl, rep("Admin", nrow(orph_adm)))
      or_plot <- c(or_plot, as.character(orph_adm[["PlotNumber"]]))
      or_issue <- c(or_issue, rep("orphan_admin", nrow(orph_adm)))
      or_n <- c(or_n, as.integer(orph_adm[["n"]]))
    }

    for (sfx in c("Veg", "Humus", "Mineral", "Other")) {
      ctbl <- paste0(ws$project, "_", sfx)
      if (!DBI::dbExistsTable(dbc, ctbl)) {
        next
      }
      cq <- vpro_quote_ident(ctbl)
      ores <- DBI::dbGetQuery(
        dbc,
        paste0(
          'SELECT COALESCE(CAST(c."PlotNumber" AS TEXT), \'<NULL>\') AS "PlotNumber", COUNT(*) AS "n" FROM ',
          cq,
          ' AS c ',
          'WHERE c."PlotNumber" IS NULL OR typeof(c."PlotNumber") <> \'text\' OR NOT EXISTS (SELECT 1 FROM ',
          env_q,
          ' AS e WHERE typeof(e."PlotNumber") = \'text\' AND CAST(e."PlotNumber" AS BLOB) = CAST(c."PlotNumber" AS BLOB)) GROUP BY 1 ORDER BY 1'
        )
      )
      if (nrow(ores) > 0L) {
        or_tbl <- c(or_tbl, rep(sfx, nrow(ores)))
        or_plot <- c(or_plot, as.character(ores[["PlotNumber"]]))
        or_issue <- c(or_issue, rep("orphan_child", nrow(ores)))
        or_n <- c(or_n, as.integer(ores[["n"]]))
      }
    }

    all_env_plots <- DBI::dbGetQuery(
      dbc,
      paste0('SELECT CAST("PlotNumber" AS TEXT) AS "PlotNumber" FROM ', env_q, ' WHERE typeof("PlotNumber") = \'text\' ORDER BY 1')
    )[["PlotNumber"]]

    if (!is.null(ws$su) && nrow(su_df) > 0L) {
      su_orph <- setdiff(su_plots, all_env_plots)
      if (length(su_orph) > 0L) {
        for (sp in sort(su_orph)) {
          cnt <- sum(su_df[["PlotNumber"]] == sp)
          or_tbl <- c(or_tbl, "SU")
          or_plot <- c(or_plot, sp)
          or_issue <- c(or_issue, "orphan_su")
          or_n <- c(or_n, as.integer(cnt))
        }
      }
    }

    plots_with_veg <- DBI::dbGetQuery(
      dbc,
      paste0('SELECT DISTINCT CAST("PlotNumber" AS TEXT) AS "PlotNumber" FROM ', veg_q, ' WHERE typeof("PlotNumber") = \'text\'')
    )[["PlotNumber"]]
    target_env_plots <- if (use_su) intersect(all_env_plots, su_plots) else all_env_plots
    no_veg_plots <- sort(setdiff(target_env_plots, plots_with_veg))
    if (length(no_veg_plots) > 0L) {
      or_tbl <- c(or_tbl, rep("Veg", length(no_veg_plots)))
      or_plot <- c(or_plot, as.character(no_veg_plots))
      or_issue <- c(or_issue, rep("plot_without_veg", length(no_veg_plots)))
      or_n <- c(or_n, rep(0L, length(no_veg_plots)))
    }

    orphans_tbl <- tibble::tibble(
      table = or_tbl,
      PlotNumber = or_plot,
      issue = or_issue,
      n_rows = or_n
    )

    # 4. Duplicate physical (PlotNumber, Species) / same-layer cover check (Check4DuplicatedSpecies)
    veg_flds <- DBI::dbListFields(dbc, veg_tbl)
    layer_map <- c(
      "1" = "Cover1",
      "2" = "Cover2",
      "3" = "Cover3",
      "A" = "TotalA",
      "4" = "Cover4",
      "5" = "Cover5",
      "5a" = "Cover5a",
      "5b" = "Cover5b",
      "5c" = "Cover5c",
      "B" = "TotalB",
      "6" = "Cover6",
      "7" = "Cover7",
      "8" = "Cover8",
      "9" = "Cover9",
      "10" = "Cover10"
    )
    present_lc <- layer_map[layer_map %in% veg_flds]
    flag_exprs <- vapply(
      names(present_lc),
      function(lcode) {
        paste0('CASE WHEN ', vpro_quote_ident(present_lc[[lcode]]), ' IS NOT NULL THEN 1 ELSE 0 END AS ', vpro_quote_ident(paste0("f_", lcode)))
      },
      character(1)
    )
    lyr_col_sql <- if ("Layer" %in% veg_flds) 'COALESCE(TRIM(CAST("Layer" AS TEXT)), \'\') AS "__lyr__", ' else '\'\' AS "__lyr__", '

    dup_sql_cols <- paste0(
      'CAST("PlotNumber" AS TEXT) AS "PlotNumber", CAST("Species" AS TEXT) AS "Species", ',
      lyr_col_sql,
      paste(flag_exprs, collapse = ", ")
    )
    dup_raw <- vpro_query_scoped_plots(
      dbc,
      veg_q,
      veg_scope_plots,
      select_cols = dup_sql_cols,
      where_extra = '"Species" IS NOT NULL AND TRIM(CAST("Species" AS TEXT)) <> \'\''
    )

    duplicates_tbl <- if (nrow(dup_raw) == 0L) {
      tibble::tibble(
        PlotNumber = character(),
        Species = character(),
        overlapping_layers = character(),
        n_rows = integer(),
        same_layer_conflict = logical()
      )
    } else {
      grp_key <- paste0(dup_raw[["PlotNumber"]], "\t", toupper(trimws(as.character(dup_raw[["Species"]]))))
      f_cols <- paste0("f_", names(present_lc))
      f_mat <- as.matrix(dup_raw[, f_cols, drop = FALSE])
      storage.mode(f_mat) <- "integer"
      row_counts <- tabulate(match(grp_key, unique(grp_key)))
      uniq_keys <- unique(grp_key)
      dup_mask <- row_counts > 1L
      if (!any(dup_mask)) {
        tibble::tibble(
          PlotNumber = character(),
          Species = character(),
          overlapping_layers = character(),
          n_rows = integer(),
          same_layer_conflict = logical()
        )
      } else {
        target_keys <- uniq_keys[dup_mask]
        idx_list <- split(seq_len(nrow(dup_raw)), grp_key)[target_keys]
        l_names <- names(present_lc)
        d_plot <- character(length(target_keys))
        d_spp <- character(length(target_keys))
        d_ov <- character(length(target_keys))
        d_n <- integer(length(target_keys))
        d_conf <- logical(length(target_keys))
        for (ki in seq_along(target_keys)) {
          r_ix <- idx_list[[ki]]
          d_plot[[ki]] <- as.character(dup_raw[["PlotNumber"]][[r_ix[[1L]]]])
          d_spp[[ki]] <- as.character(dup_raw[["Species"]][[r_ix[[1L]]]])
          d_n[[ki]] <- length(r_ix)
          cs <- colSums(f_mat[r_ix, , drop = FALSE])
          hits <- l_names[cs > 1L]
          lyrs <- dup_raw[["__lyr__"]][r_ix]
          dup_lcol <- any(duplicated(lyrs[nzchar(lyrs)]))
          d_conf[[ki]] <- length(hits) > 0L || dup_lcol
          d_ov[[ki]] <- paste(hits, collapse = ",")
        }
        ord_d <- order(d_plot, d_spp)
        tibble::tibble(
          PlotNumber = d_plot[ord_d],
          Species = d_spp[ord_d],
          overlapping_layers = d_ov[ord_d],
          n_rows = d_n[ord_d],
          same_layer_conflict = d_conf[ord_d]
        )
      }
    }

    bounds_tbl <- .vpro_check_vp08_bounds(dbc, ws$project, su_plots, use_su)
    proj_name_lbl <- ws$project
  } else {
    proj_name_lbl <- ws$project
  }

  # 6. LMH25 pedological & edatopic validation
  lmh25_res <- if (run_lmh25) {
    .vpro_check_lmh25(ws, scope = scope)
  } else {
    structure(
      list(
        issues = tibble::tibble(PlotNumber = character(), rule = character(), severity = character(), detail = character()),
        summary = tibble::tibble(rule = character(), severity = character(), n_issues = integer(), n_plots = integer()),
        n_plots_checked = 0L
      ),
      class = "vpro_lmh25_audit"
    )
  }

  # Build unified $issues tibble
  parts <- list()
  if (nrow(env_codes_tbl) > 0L) {
    parts[[length(parts) + 1L]] <- tibble::tibble(
      PlotNumber = env_codes_tbl[["PlotNumber"]],
      category = rep("env_codes", nrow(env_codes_tbl)),
      rule = paste0("list:", env_codes_tbl[["list_name"]]),
      severity = rep("error", nrow(env_codes_tbl)),
      detail = sprintf("Field %s has unlisted value '%s' (list %s).", env_codes_tbl[["field"]], env_codes_tbl[["value"]], env_codes_tbl[["list_name"]])
    )
  }
  if (nrow(veg_codes_tbl) > 0L) {
    is_unl <- veg_codes_tbl[["status"]] == "unlisted"
    is_usr <- veg_codes_tbl[["status"]] == "user"
    parts[[length(parts) + 1L]] <- tibble::tibble(
      PlotNumber = veg_codes_tbl[["PlotNumber"]],
      category = rep("veg_codes", nrow(veg_codes_tbl)),
      rule = paste0("species_", veg_codes_tbl[["status"]]),
      severity = ifelse(is_unl, "error", "warning"),
      detail = ifelse(
        is_unl,
        sprintf("Species code '%s' is not in USysAllSpecs or USysUserSpp.", veg_codes_tbl[["Species"]]),
        ifelse(
          is_usr,
          sprintf("Species code '%s' is defined only in local USysUserSpp.", veg_codes_tbl[["Species"]]),
          sprintf("Species code '%s' is a synonym; accepted code is '%s'.", veg_codes_tbl[["Species"]], veg_codes_tbl[["suggested_code"]])
        )
      )
    )
  }
  if (nrow(orphans_tbl) > 0L) {
    is_noveg <- orphans_tbl[["issue"]] == "plot_without_veg"
    parts[[length(parts) + 1L]] <- tibble::tibble(
      PlotNumber = orphans_tbl[["PlotNumber"]],
      category = rep("orphans", nrow(orphans_tbl)),
      rule = orphans_tbl[["issue"]],
      severity = ifelse(is_noveg, "warning", "error"),
      detail = ifelse(
        is_noveg,
        sprintf("Plot %s has no vegetation rows in %s_Veg.", orphans_tbl[["PlotNumber"]], proj_name_lbl),
        sprintf("Table %s has %s (%d row(s)) for PlotNumber %s.", orphans_tbl[["table"]], orphans_tbl[["issue"]], orphans_tbl[["n_rows"]], orphans_tbl[["PlotNumber"]])
      )
    )
  }
  if (nrow(duplicates_tbl) > 0L) {
    parts[[length(parts) + 1L]] <- tibble::tibble(
      PlotNumber = duplicates_tbl[["PlotNumber"]],
      category = rep("duplicates", nrow(duplicates_tbl)),
      rule = ifelse(duplicates_tbl[["same_layer_conflict"]], "duplicate_species_layer", "duplicate_species_rows"),
      severity = ifelse(duplicates_tbl[["same_layer_conflict"]], "error", "warning"),
      detail = ifelse(
        duplicates_tbl[["same_layer_conflict"]],
        sprintf(
          "Species '%s' appears %d times with overlapping cover in layer(s): %s.",
          duplicates_tbl[["Species"]],
          duplicates_tbl[["n_rows"]],
          duplicates_tbl[["overlapping_layers"]]
        ),
        sprintf("Species '%s' is split across %d physical rows without overlapping cover.", duplicates_tbl[["Species"]], duplicates_tbl[["n_rows"]])
      )
    )
  }
  if (nrow(bounds_tbl) > 0L) {
    parts[[length(parts) + 1L]] <- tibble::tibble(
      PlotNumber = bounds_tbl[["PlotNumber"]],
      category = rep("bounds", nrow(bounds_tbl)),
      rule = paste0("bounds:", bounds_tbl[["field"]]),
      severity = rep("error", nrow(bounds_tbl)),
      detail = sprintf("%s.%s value '%s': %s", bounds_tbl[["table"]], bounds_tbl[["field"]], bounds_tbl[["value"]], bounds_tbl[["rule"]])
    )
  }
  if (nrow(lmh25_res$issues) > 0L) {
    parts[[length(parts) + 1L]] <- tibble::tibble(
      PlotNumber = lmh25_res$issues[["PlotNumber"]],
      category = rep("lmh25", nrow(lmh25_res$issues)),
      rule = lmh25_res$issues[["rule"]],
      severity = lmh25_res$issues[["severity"]],
      detail = lmh25_res$issues[["detail"]]
    )
  }

  issues_all <- if (length(parts) == 0L) {
    tibble::tibble(
      PlotNumber = character(),
      category = character(),
      rule = character(),
      severity = character(),
      detail = character()
    )
  } else {
    do.call(rbind, parts)
  }

  passed <- !any(issues_all[["severity"]] == "error")

  structure(
    list(
      passed = passed,
      issues = issues_all,
      env_codes = env_codes_tbl,
      veg_codes = veg_codes_tbl,
      orphans = orphans_tbl,
      duplicates = duplicates_tbl,
      bounds = bounds_tbl,
      lmh25 = lmh25_res,
      skipped_definitions = skipped_tbl,
      checks = checks
    ),
    class = "vpro_validation"
  )
}

#' Print a `vpro_validation` workspace QA summary
#'
#' @param x A `vpro_validation` object from [vpro_validate()].
#' @param ... Unused additional arguments.
#' @return `x`, invisibly.
#' @export
print.vpro_validation <- function(x, ...) {
  n_err <- sum(x$issues[["severity"]] == "error")
  n_wrn <- sum(x$issues[["severity"]] == "warning")
  n_bnd <- if (!is.null(x$bounds)) nrow(x$bounds) else 0L
  b1 <- sprintf("Total issues: %d (%d errors, %d warnings)", nrow(x$issues), n_err, n_wrn)
  b2 <- sprintf("Env picklist errors: %d | Veg code findings: %d", nrow(x$env_codes), nrow(x$veg_codes))
  b3 <- sprintf("Orphans/no-veg: %d | Duplicates: %d | Bounds: %d | LMH25: %d", nrow(x$orphans), nrow(x$duplicates), n_bnd, nrow(x$lmh25$issues))
  cli::cli_h3(sprintf("vpro_validation (%s)", if (x$passed) "PASSED" else "FAILED"))
  cli::cli_bullets(c("*" = b1, "*" = b2, "*" = b3))
  invisible(x)
}

#' Coerce a `vpro_validation` bundle to its unified issues tibble
#'
#' @param x A `vpro_validation` object from [vpro_validate()].
#' @param ... Unused additional arguments.
#' @return The `$issues` tibble (`PlotNumber`, `category`, `rule`, `severity`,
#'   `detail`).
#' @export
as_tibble.vpro_validation <- function(x, ...) {
  x$issues
}
