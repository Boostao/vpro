# Tidy VP08 Ecological Readers, Quality Filters & Hierarchy Conversions --------

#' Test whether a SiteUnit name carries a BEC modifier suffix
#'
#' Detects `.support`, `.poor`, `.nudum` (case-insensitive) and `$`/`?`
#' tentative/questionable unit prefixes/suffixes when `include_tentative = TRUE`.
#'
#' @param site_unit Character vector of site-unit labels.
#' @param include_tentative Logical; if `TRUE`, also flags `$` and `?` markers.
#' @return Logical vector of the same length as `site_unit`.
#' @export
vpro_is_modifier_unit <- function(site_unit, include_tentative = FALSE) {
  su <- ifelse(is.na(site_unit), "", trimws(as.character(site_unit)))
  is_mod <- grepl("\\.(support|poor|nudum)($|[^A-Za-z0-9])", su, ignore.case = TRUE)
  if (isTRUE(include_tentative)) {
    is_mod <- is_mod | grepl("(\\$|\\?)", su)
  }
  is_mod
}

#' Read plot-to-SiteUnit assignments (`*_SU`)
#'
#' @param ws A `vpro_workspace` handle.
#' @param su Optional `*_SU` table name override. Defaults to `ws$su`.
#' @param exclude_modifiers Logical; if `TRUE`, removes `.support`, `.poor`, and
#'   `.nudum` units.
#' @return A tibble with literal character `PlotNumber` and `SiteUnit`.
#' @export
vpro_site_units <- function(ws, su = NULL, exclude_modifiers = FALSE) {
  vpro_assert_workspace(ws)
  su_tbl <- if (is.null(su)) {
    ws$su
  } else {
    tables <- vpro_sqlite_physical_tables(ws$su_path)
    vpro_resolve_table_suffix(tables, su, "SU", default_prefix = ws$project)
  }
  if (is.null(su_tbl)) {
    return(tibble::tibble(PlotNumber = character(), SiteUnit = character()))
  }
  dbc <- vpro_sqlite_ro(ws$su_path)
  on.exit(DBI::dbDisconnect(dbc), add = TRUE)
  df <- DBI::dbGetQuery(
    dbc,
    paste0(
      'SELECT CAST("PlotNumber" AS TEXT) AS "PlotNumber", ',
      'CAST("SiteUnit" AS TEXT) AS "SiteUnit" FROM ',
      vpro_quote_ident(su_tbl),
      ' WHERE typeof("PlotNumber") = \'text\' AND TRIM("PlotNumber") <> \'\'',
      ' AND "SiteUnit" IS NOT NULL AND TRIM(CAST("SiteUnit" AS TEXT)) <> \'\'',
      ' ORDER BY "PlotNumber", "SiteUnit"'
    )
  )
  df <- unique(df)
  if (isTRUE(exclude_modifiers) && nrow(df) > 0L) {
    df <- df[!vpro_is_modifier_unit(df$SiteUnit), , drop = FALSE]
  }
  tibble::as_tibble(df)
}

#' Filter plots by VPro `DataQuality`, lexical `BEC_Use`, and modifier rules
#'
#' Calibrated to `V7mdlReportsQualityControl.QC` and `QCLV`: ranks
#' `SitePlotQuality`, `VegPlotQuality`, and `SoilPlotQuality` via
#' `USysTableOfLists` (`ListName = 'DataQuality'`), applies case-insensitive
#' lexical `BEC_Use >= bec_min` when `bec_min` is supplied, and optionally drops
#' `.support/.poor/.nudum` units.
#'
#' @param ws A `vpro_workspace` handle.
#' @param site_min,veg_min,soil_min Inclusive minimum `DataQuality` labels
#'   (e.g. `"Poor"`, `"Fair"`, `"Good"`, `"Excellent"`).
#' @param include_site_missing,include_veg_missing,include_soil_missing Whether
#'   missing or unlisted quality values pass each criterion.
#' @param bec_min Optional lexical minimum for `BEC_Use` (`NULL` disables).
#' @param include_bec_missing Whether missing `BEC_Use` values pass when
#'   `bec_min` is supplied.
#' @param exclude_modifiers Logical; if `TRUE`, excludes `.support`, `.poor`,
#'   and `.nudum` units.
#' @param scope Either `"su"` (active SU plots) or `"project"` (all `_Env` plots).
#' @return A list with `selected` tibble, `removed` tibble, and `thresholds`.
#' @export
vpro_filter_plots <- function(
  ws,
  site_min = "Poor",
  veg_min = "Poor",
  soil_min = "Poor",
  include_site_missing = TRUE,
  include_veg_missing = TRUE,
  include_soil_missing = TRUE,
  bec_min = NULL,
  include_bec_missing = TRUE,
  exclude_modifiers = FALSE,
  scope = c("su", "project")
) {
  vpro_assert_workspace(ws)
  scope <- match.arg(scope)

  dbc_vlists <- vpro_sqlite_ro(ws$vlists_path)
  on.exit(DBI::dbDisconnect(dbc_vlists), add = TRUE)
  levels <- DBI::dbGetQuery(
    dbc_vlists,
    paste(
      'SELECT "Item", "ItemOrder" FROM "USysTableOfLists"',
      'WHERE "ListName" = \'DataQuality\' COLLATE NOCASE',
      'AND "Item" IS NOT NULL AND "ItemOrder" IS NOT NULL',
      'ORDER BY "ItemOrder", "Item" COLLATE NOCASE'
    )
  )
  all_items <- tolower(DBI::dbGetQuery(
    dbc_vlists,
    'SELECT DISTINCT "Item" FROM "USysTableOfLists" WHERE "Item" IS NOT NULL'
  )$Item)
  lvl_keys <- tolower(levels$Item)
  resolve_thresh <- function(val, arg) {
    ix <- match(tolower(trimws(val)), lvl_keys)
    if (is.na(ix)) rlang::abort(paste0("`", arg, "` is not a configured DataQuality level: ", val))
    list(label = levels$Item[[ix]], order = as.numeric(levels$ItemOrder[[ix]]))
  }
  t_site <- resolve_thresh(site_min, "site_min")
  t_veg <- resolve_thresh(veg_min, "veg_min")
  t_soil <- resolve_thresh(soil_min, "soil_min")

  dbc <- vpro_sqlite_ro(ws$project_path)
  on.exit(DBI::dbDisconnect(dbc), add = TRUE)
  env_q <- vpro_quote_ident(paste0(ws$project, "_Env"))
  adm_tbl <- paste0(ws$project, "_Admin")
  adm_q <- vpro_quote_ident(adm_tbl)
  adm_fields <- DBI::dbListFields(dbc, adm_tbl)
  bec_expr <- if ("BEC_Use" %in% adm_fields) 'CAST(admin."BEC_Use" AS TEXT)' else 'CAST(NULL AS TEXT)'

  if (identical(scope, "su") && !is.null(ws$su)) {
    su_df <- vpro_site_units(ws, exclude_modifiers = exclude_modifiers)
    env_adm <- DBI::dbGetQuery(
      dbc,
      paste0(
        'SELECT CAST(env."PlotNumber" AS TEXT) AS "PlotNumber", ',
        'CAST(admin."SitePlotQuality" AS TEXT) AS "SitePlotQuality", ',
        'CAST(admin."VegPlotQuality" AS TEXT) AS "VegPlotQuality", ',
        'CAST(admin."SoilPlotQuality" AS TEXT) AS "SoilPlotQuality", ',
        bec_expr, ' AS "BEC_Use", ',
        'CASE WHEN admin."Plot" IS NOT NULL THEN 1 ELSE 0 END AS "has_admin" ',
        'FROM ', env_q, ' AS env LEFT JOIN ', adm_q,
        ' AS admin ON env."PlotNumber" = admin."Plot" AND typeof(admin."Plot") = \'text\' AND CAST(env."PlotNumber" AS BLOB) = CAST(admin."Plot" AS BLOB) ',
        'WHERE typeof(env."PlotNumber") = \'text\''
      )
    )
    m_ix <- match(su_df$PlotNumber, env_adm$PlotNumber)
    src <- data.frame(
      PlotNumber = su_df$PlotNumber,
      SiteUnit = su_df$SiteUnit,
      SitePlotQuality = env_adm$SitePlotQuality[m_ix],
      VegPlotQuality = env_adm$VegPlotQuality[m_ix],
      SoilPlotQuality = env_adm$SoilPlotQuality[m_ix],
      BEC_Use = env_adm$BEC_Use[m_ix],
      complete_plot = !is.na(m_ix) & !is.na(env_adm$has_admin[m_ix]) & env_adm$has_admin[m_ix] == 1L,
      stringsAsFactors = FALSE
    )
  } else {
    su_df <- vpro_site_units(ws, exclude_modifiers = FALSE)
    su_map <- stats::setNames(su_df$SiteUnit, su_df$PlotNumber)
    src <- DBI::dbGetQuery(
      dbc,
      paste0(
        'SELECT CAST(env."PlotNumber" AS TEXT) AS "PlotNumber", ',
        'CAST(admin."SitePlotQuality" AS TEXT) AS "SitePlotQuality", ',
        'CAST(admin."VegPlotQuality" AS TEXT) AS "VegPlotQuality", ',
        'CAST(admin."SoilPlotQuality" AS TEXT) AS "SoilPlotQuality", ',
        bec_expr, ' AS "BEC_Use", ',
        'CASE WHEN admin."Plot" IS NOT NULL THEN 1 ELSE 0 END AS "has_admin" ',
        'FROM ', env_q, ' AS env LEFT JOIN ', adm_q,
        ' AS admin ON env."PlotNumber" = admin."Plot" AND typeof(admin."Plot") = \'text\' AND CAST(env."PlotNumber" AS BLOB) = CAST(admin."Plot" AS BLOB) ',
        'WHERE typeof(env."PlotNumber") = \'text\' ORDER BY env."PlotNumber"'
      )
    )
    src$SiteUnit <- unname(su_map[src$PlotNumber])
    src$complete_plot <- src$has_admin == 1
    if (isTRUE(exclude_modifiers)) {
      src <- src[!vpro_is_modifier_unit(src$SiteUnit), , drop = FALSE]
    }
  }

  qual_pass <- function(vals, thresh_ord, inc_missing) {
    ords <- as.numeric(levels$ItemOrder[match(tolower(vals), lvl_keys)])
    unmatched <- is.na(ords)
    collides <- !is.na(vals) & tolower(vals) %in% all_items
    (!unmatched & ords >= thresh_ord) | (unmatched & !collides & isTRUE(inc_missing))
  }
  s_ok <- qual_pass(src$SitePlotQuality, t_site$order, include_site_missing)
  v_ok <- qual_pass(src$VegPlotQuality, t_veg$order, include_veg_missing)
  so_ok <- qual_pass(src$SoilPlotQuality, t_soil$order, include_soil_missing)
  b_ok <- if (is.null(bec_min)) {
    rep(TRUE, nrow(src))
  } else {
    thr_low <- tolower(enc2utf8(as.character(bec_min)))
    miss <- is.na(src$BEC_Use)
    cmp <- rep(FALSE, nrow(src))
    if (any(!miss)) {
      cmp[!miss] <- vapply(src$BEC_Use[!miss], function(val) {
        vl <- tolower(enc2utf8(val))
        identical(vl, thr_low) || sort(c(vl, thr_low), method = "radix")[[1L]] == thr_low
      }, logical(1))
    }
    cmp | (miss & isTRUE(include_bec_missing))
  }

  keep <- src$complete_plot & s_ok & v_ok & so_ok & b_ok
  selected <- tibble::tibble(
    PlotNumber = as.character(src$PlotNumber[keep]),
    SiteUnit = as.character(src$SiteUnit[keep])
  )

  rem_idx <- which(!keep)
  if (length(rem_idx) == 0L) {
    removed <- tibble::tibble(
      PlotNumber = character(),
      SiteUnit = character(),
      SitePlotQuality = character(),
      VegPlotQuality = character(),
      SoilPlotQuality = character(),
      BEC_Use = character(),
      failed_criteria = character()
    )
  } else {
    reasons <- vapply(rem_idx, function(i) {
      r <- character()
      if (!src$complete_plot[[i]]) r <- c(r, "Project")
      if (src$complete_plot[[i]] && !s_ok[[i]]) r <- c(r, "Site")
      if (src$complete_plot[[i]] && !v_ok[[i]]) r <- c(r, "Veg")
      if (src$complete_plot[[i]] && !so_ok[[i]]) r <- c(r, "Soil")
      if (src$complete_plot[[i]] && !b_ok[[i]]) r <- c(r, "BEC")
      paste(r, collapse = ",")
    }, character(1))
    removed <- tibble::tibble(
      PlotNumber = as.character(src$PlotNumber[rem_idx]),
      SiteUnit = as.character(src$SiteUnit[rem_idx]),
      SitePlotQuality = as.character(src$SitePlotQuality[rem_idx]),
      VegPlotQuality = as.character(src$VegPlotQuality[rem_idx]),
      SoilPlotQuality = as.character(src$SoilPlotQuality[rem_idx]),
      BEC_Use = as.character(src$BEC_Use[rem_idx]),
      failed_criteria = reasons
    )
  }

  list(
    selected = selected,
    removed = removed,
    thresholds = list(site = t_site, veg = t_veg, soil = t_soil, bec = bec_min)
  )
}

#' Read tidy plot environment and administration records (`_Env` + `_Admin`)
#'
#' Preserves literal leading-zero `PlotNumber`s (`typeof("PlotNumber") = 'text'`),
#' joins `_Admin` (`PlotNumber == Plot`) and active `SiteUnit` (`*_SU`), converts
#' Access `-1/0` booleans to R `logical`, and optionally filters by `DataQuality`
#' and modifier suffixes.
#'
#' @param ws A `vpro_workspace` handle.
#' @param scope Either `"su"` (restrict to active `ws$su` when set, else all
#'   project plots) or `"project"` (all `_Env` plots with `SiteUnit` left-joined).
#' @param include_admin Logical; if `TRUE`, joins `_Admin` columns.
#' @param filter_quality Optional quality filter: `NULL`/`FALSE` (none), `TRUE`
#'   (default `"Poor"` thresholds), a single `DataQuality` string (e.g. `"Fair"`),
#'   or a named list of arguments passed to [vpro_filter_plots()].
#' @param exclude_modifiers Logical; if `TRUE`, excludes `.support`, `.poor`, and
#'   `.nudum` site units.
#' @param columns Optional character vector of `_Env`/`_Admin` column names to
#'   project from SQLite (`PlotNumber` is always retained). Defaults to `NULL`
#'   (all columns).
#' @return A tibble of plot environment records.
#' @export
vpro_env <- function(
  ws,
  scope = c("su", "project"),
  include_admin = TRUE,
  filter_quality = NULL,
  exclude_modifiers = FALSE,
  columns = NULL
) {
  vpro_assert_workspace(ws)
  scope <- match.arg(scope)

  dbc <- vpro_sqlite_ro(ws$project_path)
  on.exit(DBI::dbDisconnect(dbc), add = TRUE)

  env_tbl <- paste0(ws$project, "_Env")
  adm_tbl <- paste0(ws$project, "_Admin")
  env_fields <- DBI::dbListFields(dbc, env_tbl)
  if (!is.null(columns)) {
    req_cols <- unique(c("PlotNumber", as.character(columns)))
    env_fields <- env_fields[tolower(env_fields) %in% tolower(req_cols)]
  }
  env_select <- vapply(env_fields, function(f) {
    qf <- vpro_quote_ident(f)
    if (identical(f, "PlotNumber")) {
      'CAST(env."PlotNumber" AS TEXT) AS "PlotNumber"'
    } else {
      paste0("env.", qf, " AS ", qf)
    }
  }, character(1))

  join_sql <- ""
  adm_select <- character()
  if (isTRUE(include_admin) && DBI::dbExistsTable(dbc, adm_tbl)) {
    adm_fields <- setdiff(DBI::dbListFields(dbc, adm_tbl), c("Plot", env_fields))
    if (!is.null(columns)) {
      adm_fields <- adm_fields[tolower(adm_fields) %in% tolower(as.character(columns))]
    }
    if (length(adm_fields) > 0L) {
      adm_select <- vapply(adm_fields, function(f) {
        qf <- vpro_quote_ident(f)
        paste0("admin.", qf, " AS ", qf)
      }, character(1))
      join_sql <- paste0(
        " LEFT JOIN ", vpro_quote_ident(adm_tbl),
        ' AS admin ON env."PlotNumber" = admin."Plot" AND typeof(admin."Plot") = \'text\' AND CAST(env."PlotNumber" AS BLOB) = CAST(admin."Plot" AS BLOB)'
      )
    }
  }

  su_scoped <- identical(scope, "su") && !is.null(ws$su)
  su_df <- vpro_site_units(ws, exclude_modifiers = if (su_scoped) exclude_modifiers else FALSE)

  if (su_scoped) {
    u_plots <- unique(su_df$PlotNumber)
    if (length(u_plots) == 0L) {
      df <- DBI::dbGetQuery(
        dbc,
        paste0("SELECT ", paste(c(env_select, adm_select), collapse = ", "), " FROM ", vpro_quote_ident(env_tbl), " AS env", join_sql, " WHERE 1 = 0")
      )
    } else {
      chunks <- split(u_plots, ceiling(seq_along(u_plots) / 450L))
      parts <- lapply(chunks, function(ch) {
        ph_txt <- paste(rep("?", length(ch)), collapse = ",")
        ph_blb <- paste(rep("CAST(? AS BLOB)", length(ch)), collapse = ",")
        q <- paste0(
          "SELECT ", paste(c(env_select, adm_select), collapse = ", "),
          " FROM ", vpro_quote_ident(env_tbl), " AS env", join_sql,
          ' WHERE typeof(env."PlotNumber") = \'text\' AND env."PlotNumber" IN (', ph_txt,
          ') AND CAST(env."PlotNumber" AS BLOB) IN (', ph_blb, ')'
        )
        DBI::dbGetQuery(dbc, q, params = as.list(c(ch, ch)))
      })
      df <- do.call(rbind, parts)
    }
  } else {
    sql <- paste0(
      "SELECT ", paste(c(env_select, adm_select), collapse = ", "),
      " FROM ", vpro_quote_ident(env_tbl), " AS env",
      join_sql,
      ' WHERE typeof(env."PlotNumber") = \'text\''
    )
    df <- DBI::dbGetQuery(dbc, sql)
    if (nrow(df) > 1L) {
      df <- df[order(as.character(df$PlotNumber), method = "radix"), , drop = FALSE]
    }
  }
  df$PlotNumber <- as.character(df$PlotNumber)

  # Normalize Access booleans -> R logical
  for (bc in intersect(c("SpeciesListComplete", "Flag", "SV_FloodPlain", "UpdatedFromCards"), names(df))) {
    df[[bc]] <- vpro_access_to_logical(df[[bc]])
  }

  # Attach SiteUnit and apply scope
  if (su_scoped) {
    keep_ix <- match(su_df$PlotNumber, df$PlotNumber)
    valid <- !is.na(keep_ix)
    df <- df[keep_ix[valid], , drop = FALSE]
    df$SiteUnit <- su_df$SiteUnit[valid]
  } else {
    su_map <- stats::setNames(su_df$SiteUnit, su_df$PlotNumber)
    df$SiteUnit <- unname(su_map[df$PlotNumber])
    if (isTRUE(exclude_modifiers)) {
      df <- df[!vpro_is_modifier_unit(df$SiteUnit), , drop = FALSE]
    }
  }

  # Apply optional quality filter
  if (!is.null(filter_quality) && !identical(filter_quality, FALSE)) {
    q_args <- if (isTRUE(filter_quality)) {
      list(ws = ws, scope = scope, exclude_modifiers = exclude_modifiers)
    } else if (is.character(filter_quality) && length(filter_quality) == 1L) {
      list(
        ws = ws, site_min = filter_quality, veg_min = filter_quality,
        soil_min = filter_quality, scope = scope, exclude_modifiers = exclude_modifiers
      )
    } else if (is.list(filter_quality)) {
      utils::modifyList(list(ws = ws, scope = scope, exclude_modifiers = exclude_modifiers), filter_quality)
    } else {
      rlang::abort("`filter_quality` must be NULL, logical, a DataQuality label, or a list of arguments.")
    }
    qf_res <- do.call(vpro_filter_plots, q_args)
    df <- df[df$PlotNumber %in% qf_res$selected$PlotNumber, , drop = FALSE]
  }

  # Place PlotNumber, SiteUnit first for scientist ergonomics
  front <- intersect(c("PlotNumber", "SiteUnit"), names(df))
  df <- df[, c(front, setdiff(names(df), front)), drop = FALSE]
  rownames(df) <- NULL
  tibble::as_tibble(df)
}

vpro_query_scoped_plots <- function(dbc, table_sql, plot_vec, select_cols = "*", where_extra = NULL) {
  if (!is.null(plot_vec)) {
    if (length(plot_vec) == 0L) {
      return(DBI::dbGetQuery(dbc, paste0("SELECT ", select_cols, " FROM ", table_sql, " WHERE 1 = 0")))
    }
    chunks <- split(unique(as.character(plot_vec)), ceiling(seq_along(unique(plot_vec)) / 450L))
    parts <- lapply(chunks, function(ch) {
      ph_txt <- paste(rep("?", length(ch)), collapse = ",")
      ph_blb <- paste(rep("CAST(? AS BLOB)", length(ch)), collapse = ",")
      w <- paste0(
        'WHERE typeof("PlotNumber") = \'text\' AND "PlotNumber" IN (', ph_txt,
        ') AND CAST("PlotNumber" AS BLOB) IN (', ph_blb, ")"
      )
      if (!is.null(where_extra) && nzchar(where_extra)) {
        w <- paste(w, "AND", where_extra)
      }
      DBI::dbGetQuery(dbc, paste("SELECT", select_cols, "FROM", table_sql, w), params = as.list(c(ch, ch)))
    })
    return(do.call(rbind, parts))
  }
  w <- 'WHERE typeof("PlotNumber") = \'text\''
  if (!is.null(where_extra) && nzchar(where_extra)) {
    w <- paste(w, "AND", where_extra)
  }
  DBI::dbGetQuery(dbc, paste("SELECT", select_cols, "FROM", table_sql, w))
}

#' Read tidy vegetation records (`_Veg`) with synonym, lump, and strata synthesis
#'
#' Extracts physical `<Project>_Veg` records, narrows cover values to IEEE-754
#' `float32`, optionally resolves `BCPlantTaxonomy v19` synonyms
#' (`OldCode -> Code`), folds `*_Lump` (or a custom two-column `data.frame`)
#' with VPro's exact per-layer `99%` cover cap (`pmin(sum_cover, 99)`), combines
#' cover across `raw`, `abcd` (`A: 1-3`, `B: 4-5c`, `C: 6`, `D: 7-10`),
#' `lifeform`, or `total` strata, and attaches `ScientificName`, `EnglishName`,
#' and `Lifeform`.
#'
#' When `combine = "pielou"` (the default), multi-layer covers within a stratum
#' or plot are combined via probabilistic canopy complement
#' \eqn{100 \times (1 - \prod_i (1 - c_i / 100))}; when `combine = "sum"`,
#' additive sums are capped at `99%` (`abcd`/`lifeform`/`total`).
#'
#' @param ws A `vpro_workspace` handle.
#' @param scope Either `"su"` (restrict to active `ws$su` when set) or `"project"`.
#' @param lump Logical (`TRUE` uses active `ws$lump`), `FALSE`, a `*_Lump` table
#'   name, or a two-column `data.frame(SppCode, LumpCode)`.
#' @param strata Aggregation level: `"raw"` (individual layers `1..10`, `5a..5c`,
#'   `A`, `B`), `"abcd"` (`A`, `B`, `C`, `D`), `"lifeform"`, or `"total"`.
#' @param combine Multi-layer combination formula: `"pielou"` (probabilistic
#'   complement) or `"sum"` (additive sum capped at `99%`).
#' @param resolve_synonyms Logical; if `TRUE`, maps `BCPlantTaxonomy v19`
#'   `OldCode -> Code` synonyms before lumping.
#' @param exclude_modifiers Logical; if `TRUE`, drops `.support/.poor/.nudum` units.
#' @param cover_precedence Stratum cover precedence when combining `A`/`B`
#'   sublayers alongside `TotalA`/`TotalB`: `"strata_totals"` (default, matching
#'   MS Access `vpro_veg` where positive `TotalA`/`TotalB` overrides sublayers)
#'   or `"sublayer_sum"` (matching BEC diagnostics where `TotalA`/`TotalB` is
#'   used only when sublayers are `NA` / absent).
#' @return A tibble of tidy vegetation observations.
#' @export
vpro_veg <- function(
  ws,
  scope = c("su", "project"),
  lump = TRUE,
  strata = c("raw", "abcd", "lifeform", "total"),
  combine = c("pielou", "sum"),
  resolve_synonyms = TRUE,
  exclude_modifiers = FALSE,
  cover_precedence = c("strata_totals", "sublayer_sum")
) {
  vpro_assert_workspace(ws)
  scope <- match.arg(scope)
  strata <- match.arg(strata)
  combine <- match.arg(combine)
  cover_precedence <- match.arg(cover_precedence)

  su_raw <- vpro_site_units(ws, exclude_modifiers = FALSE)
  su_df <- if (isTRUE(exclude_modifiers) && nrow(su_raw) > 0L) {
    su_raw[!vpro_is_modifier_unit(su_raw$SiteUnit), , drop = FALSE]
  } else {
    su_raw
  }
  scoped_plots <- if (identical(scope, "su") && !is.null(ws$su)) su_df$PlotNumber else NULL
  modifier_plots <- if (identical(scope, "project") && isTRUE(exclude_modifiers) && nrow(su_raw) > 0L) {
    setdiff(su_raw$PlotNumber[vpro_is_modifier_unit(su_raw$SiteUnit)], su_df$PlotNumber)
  } else {
    character()
  }

  dbc <- vpro_sqlite_ro(ws$project_path)
  on.exit(DBI::dbDisconnect(dbc), add = TRUE)

  veg_tbl <- paste0(ws$project, "_Veg")
  veg_fields <- DBI::dbListFields(dbc, veg_tbl)
  layer_defs <- c(
    "1" = "Cover1", "2" = "Cover2", "3" = "Cover3", "A" = "TotalA",
    "4" = "Cover4", "5" = "Cover5", "5a" = "Cover5a", "5b" = "Cover5b", "5c" = "Cover5c", "B" = "TotalB",
    "6" = "Cover6", "7" = "Cover7", "8" = "Cover8", "9" = "Cover9", "10" = "Cover10"
  )
  present_layers <- layer_defs[layer_defs %in% veg_fields]
  sel_cols <- paste(
    c(
      'CAST("PlotNumber" AS TEXT) AS "PlotNumber"',
      'UPPER(TRIM(CAST("Species" AS TEXT))) AS "Species"',
      vapply(present_layers, function(col) paste0('CAST(', vpro_quote_ident(col), ' AS REAL) AS ', vpro_quote_ident(col)), character(1))
    ),
    collapse = ", "
  )

  raw_df <- vpro_query_scoped_plots(
    dbc,
    vpro_quote_ident(veg_tbl),
    scoped_plots,
    select_cols = sel_cols,
    where_extra = '"Species" IS NOT NULL AND TRIM(CAST("Species" AS TEXT)) <> \'\''
  )

  empty_out <- function() {
    base <- list(
      PlotNumber = character(),
      SiteUnit = character(),
      Species = character()
    )
    if (strata == "raw") {
      base$Layer <- character()
      base$Strata <- character()
    } else if (strata == "abcd") {
      base$Strata <- character()
    }
    base$Cover <- numeric()
    base$ScientificName <- character()
    base$EnglishName <- character()
    base$Lifeform <- integer()
    tibble::as_tibble(base)
  }

  if (nrow(raw_df) == 0L) {
    return(empty_out())
  }
  if (length(modifier_plots) > 0L) {
    raw_df <- raw_df[!(raw_df$PlotNumber %in% modifier_plots), , drop = FALSE]
    if (nrow(raw_df) == 0L) return(empty_out())
  }

  dt <- data.table::as.data.table(raw_df)
  cov_cols <- unname(present_layers)

  # IEEE-754 float32 narrowing and [0, 100] bounds calibration
  for (cc in cov_cols) {
    v <- vpro_narrow_float32(as.numeric(dt[[cc]]))
    v[!is.na(v) & v > 100] <- 100
    v[!is.na(v) & v < 0] <- NA_real_
    data.table::set(dt, j = cc, value = v)
  }

  # Deduplicate physical repeated (PlotNumber, Species) rows by MAX per cover column
  max_na <- function(x) {
    ok <- x[!is.na(x)]
    if (length(ok) == 0L) NA_real_ else max(ok)
  }
  if (anyDuplicated(dt, by = c("PlotNumber", "Species")) > 0L) {
    dt <- dt[, lapply(.SD, max_na), by = c("PlotNumber", "Species"), .SDcols = cov_cols]
  }

  # Vectorised stratum cover calculation helper
  combine_cols <- function(mat) {
    if (ncol(mat) == 0L) return(rep(NA_real_, nrow(mat)))
    has_any <- rowSums(!is.na(mat)) > 0L
    m0 <- mat
    m0[is.na(m0)] <- 0.0
    res <- rep(NA_real_, nrow(mat))
    if (identical(combine, "pielou")) {
      m_clamped <- pmin(pmax(m0, 0.0), 100.0)
      comp <- 1.0 - (m_clamped / 100.0)
      prod_comp <- exp(rowSums(log(pmax(comp, 1e-15))))
      zero_100 <- rowSums(m_clamped >= 100.0) > 0L
      val <- 100.0 * (1.0 - prod_comp)
      val[zero_100] <- 100.0
      res[has_any] <- val[has_any]
    } else {
      res[has_any] <- pmin(rowSums(m0)[has_any], 99.0)
    }
    res
  }

  # Compute per-species effective stratum covers BEFORE lump folding so a species
  # recorded via TotalA/TotalB and a lumped congener recorded via Cover1..5c both
  # contribute to the folded stratum!
  if (strata != "raw") {
    sub_a <- intersect(c("Cover1", "Cover2", "Cover3"), names(dt))
    eff_a <- combine_cols(as.matrix(dt[, sub_a, with = FALSE]))
    if ("TotalA" %in% names(dt)) {
      ta <- dt[["TotalA"]]
      use_ta <- if (identical(cover_precedence, "sublayer_sum")) {
        !is.na(ta) & is.na(eff_a)
      } else {
        !is.na(ta) & (ta > 0 | is.na(eff_a))
      }
      eff_a[use_ta] <- ta[use_ta]
    }
    sub_b <- intersect(c("Cover4", "Cover5", "Cover5a", "Cover5b", "Cover5c"), names(dt))
    eff_b <- combine_cols(as.matrix(dt[, sub_b, with = FALSE]))
    if ("TotalB" %in% names(dt)) {
      tb <- dt[["TotalB"]]
      use_tb <- if (identical(cover_precedence, "sublayer_sum")) {
        !is.na(tb) & is.na(eff_b)
      } else {
        !is.na(tb) & (tb > 0 | is.na(eff_b))
      }
      eff_b[use_tb] <- tb[use_tb]
    }
    eff_c <- if ("Cover6" %in% names(dt)) dt[["Cover6"]] else rep(NA_real_, nrow(dt))
    sub_d <- intersect(c("Cover7", "Cover8", "Cover9", "Cover10"), names(dt))
    eff_d <- combine_cols(as.matrix(dt[, sub_d, with = FALSE]))
    data.table::set(dt, j = "__eff_A", value = eff_a)
    data.table::set(dt, j = "__eff_B", value = eff_b)
    data.table::set(dt, j = "__eff_C", value = eff_c)
    data.table::set(dt, j = "__eff_D", value = eff_d)
    cov_cols <- c(cov_cols, "__eff_A", "__eff_B", "__eff_C", "__eff_D")
  }

  # Optional lump folding + BCPlantTaxonomy v19 synonym resolution (OldCode -> Code).
  # Apply lump both before and after synonym resolution (and expand lump SppCodes
  # across synonyms) so legacy space-coded *_Lump tables (e.g. 'POA PRA2') fold
  # seamlessly alongside 2026 underscore-coded species ('POA_PRA2').
  lump_tbl <- vpro_lump_map(ws, lump = lump)
  syn_map <- if (isTRUE(resolve_synonyms)) vpro_synonym_map(ws) else character()

  lmap <- if (nrow(lump_tbl) > 0L) stats::setNames(lump_tbl$LumpCode, lump_tbl$SppCode) else character()
  if (length(lmap) > 0L && length(syn_map) > 0L) {
    syn_spp <- unname(syn_map[names(lmap)])
    extra <- !is.na(syn_spp) & !(syn_spp %in% names(lmap))
    if (any(extra)) {
      extra_map <- stats::setNames(unname(lmap[extra]), syn_spp[extra])
      extra_map <- extra_map[!duplicated(names(extra_map))]
      lmap <- c(lmap, extra_map)
    }
  }

  if (length(lmap) > 0L) {
    m_lmp <- lmap[dt$Species]
    hit <- !is.na(m_lmp)
    if (any(hit)) dt$Species[hit] <- unname(m_lmp[hit])
  }
  if (length(syn_map) > 0L) {
    m_syn <- syn_map[dt$Species]
    hit <- !is.na(m_syn)
    if (any(hit)) dt$Species[hit] <- unname(m_syn[hit])
  }
  if (length(lmap) > 0L) {
    m_lmp2 <- lmap[dt$Species]
    hit2 <- !is.na(m_lmp2)
    if (any(hit2)) dt$Species[hit2] <- unname(m_lmp2[hit2])
  }

  # Fold identical (PlotNumber, Species) after synonym/lump mapping with VPro 99% per-layer cap
  if (anyDuplicated(dt, by = c("PlotNumber", "Species")) > 0L) {
    sum_cap99 <- function(x) {
      ok <- x[!is.na(x)]
      if (length(ok) == 0L) NA_real_ else if (length(ok) == 1L) ok else min(sum(ok), 99.0)
    }
    dt <- dt[, lapply(.SD, sum_cap99), by = c("PlotNumber", "Species"), .SDcols = cov_cols]
  }

  # Layer-to-Strata mapping (matching LayerCode.Layer1234567)
  strata_of_layer <- c(
    "1" = "A", "2" = "A", "3" = "A", "A" = "A",
    "4" = "B", "5" = "B", "5a" = "B", "5b" = "B", "5c" = "B", "B" = "B",
    "6" = "C",
    "7" = "D", "8" = "D", "9" = "D", "10" = "D"
  )

  tax <- vpro_taxonomy(ws, include_synonyms = FALSE, include_user = TRUE)
  tax_ix <- function(spp_vec) match(spp_vec, tax$Code)

  su_map <- stats::setNames(su_df$SiteUnit, su_df$PlotNumber)
  attach_meta <- function(res_dt) {
    if (identical(scope, "su") && !is.null(ws$su)) {
      # Preserve many-to-many SU plots cleanly if any exist
      su_dt <- data.table::as.data.table(su_df)
      res_dt <- merge(su_dt, res_dt, by = "PlotNumber", all = FALSE, allow.cartesian = TRUE)
    } else {
      data.table::set(res_dt, j = "SiteUnit", value = unname(su_map[res_dt[["PlotNumber"]]]))
    }
    ix <- tax_ix(res_dt$Species)
    data.table::set(res_dt, j = "ScientificName", value = tax$ScientificName[ix])
    data.table::set(res_dt, j = "EnglishName", value = tax$EnglishName[ix])
    data.table::set(res_dt, j = "Lifeform", value = as.integer(tax$Lifeform[ix]))
    res_dt
  }

  if (strata == "raw") {
    long_parts <- lapply(names(present_layers), function(lyr) {
      cc <- present_layers[[lyr]]
      v <- dt[[cc]]
      ok <- !is.na(v)
      if (!any(ok)) return(NULL)
      data.table::data.table(
        PlotNumber = dt$PlotNumber[ok],
        Species = dt$Species[ok],
        Layer = rep(lyr, sum(ok)),
        Strata = rep(unname(strata_of_layer[[lyr]]), sum(ok)),
        Cover = v[ok]
      )
    })
    long_dt <- data.table::rbindlist(Filter(Negate(is.null), long_parts))
    if (nrow(long_dt) == 0L) return(empty_out())
    long_dt <- attach_meta(long_dt)
    data.table::setorderv(long_dt, c("PlotNumber", "Species", "Layer"))
    cols <- c("PlotNumber", "SiteUnit", "Species", "Layer", "Strata", "Cover", "ScientificName", "EnglishName", "Lifeform")
    return(tibble::as_tibble(long_dt[, cols, with = FALSE]))
  }

  cov_a <- dt[["__eff_A"]]
  cov_b <- dt[["__eff_B"]]
  cov_c <- dt[["__eff_C"]]
  cov_d <- dt[["__eff_D"]]

  if (strata == "abcd") {
    abcd_list <- list(
      A = cov_a, B = cov_b, C = cov_c, D = cov_d
    )
    parts <- lapply(names(abcd_list), function(st) {
      v <- abcd_list[[st]]
      ok <- !is.na(v) & v > 0
      if (!any(ok)) return(NULL)
      data.table::data.table(
        PlotNumber = dt$PlotNumber[ok],
        Species = dt$Species[ok],
        Strata = rep(st, sum(ok)),
        Cover = v[ok]
      )
    })
    res_dt <- data.table::rbindlist(Filter(Negate(is.null), parts))
    if (nrow(res_dt) == 0L) return(empty_out())
    res_dt <- attach_meta(res_dt)
    data.table::setorderv(res_dt, c("PlotNumber", "Species", "Strata"))
    cols <- c("PlotNumber", "SiteUnit", "Species", "Strata", "Cover", "ScientificName", "EnglishName", "Lifeform")
    return(tibble::as_tibble(res_dt[, cols, with = FALSE]))
  }

  tot_cov <- combine_cols(cbind(cov_a, cov_b, cov_c, cov_d))
  ok <- !is.na(tot_cov) & tot_cov > 0
  if (!any(ok)) return(empty_out())
  res_dt <- data.table::data.table(
    PlotNumber = dt$PlotNumber[ok],
    Species = dt$Species[ok],
    Cover = tot_cov[ok]
  )
  res_dt <- attach_meta(res_dt)
  if (strata == "lifeform") {
    # Collapse if requested by lifeform (retaining Species + Lifeform)
    data.table::setorderv(res_dt, c("PlotNumber", "Lifeform", "Species"))
  } else {
    data.table::setorderv(res_dt, c("PlotNumber", "Species"))
  }
  cols <- c("PlotNumber", "SiteUnit", "Species", "Cover", "ScientificName", "EnglishName", "Lifeform")
  tibble::as_tibble(res_dt[, cols, with = FALSE])
}

vpro_classify_horizon <- function(horizon) {
  h <- trimws(ifelse(is.na(horizon), "", as.character(horizon)))
  # Wetland organic (Of, Om, Oh) vs Upland organic (L, F, H) vs Mineral (A, B, C, R, W)
  out <- rep("mineral", length(h))
  is_wet <- grepl("^[0-9]*O[fmhp]?", h, ignore.case = FALSE) | grepl("^o[fmh]", tolower(h))
  is_up <- !is_wet & grepl("^[0-9]*[LFH]", h, ignore.case = TRUE)
  out[is_wet] <- "wetland_organic"
  out[is_up] <- "upland_organic"
  out
}

vpro_order_soil_df <- function(df) {
  if (nrow(df) == 0L) return(tibble::as_tibble(df))
  df$PlotNumber <- as.character(df$PlotNumber)
  if ("Flag" %in% names(df)) {
    df$Flag <- vpro_access_to_logical(df$Flag)
  }
  df$HorizonRegime <- vpro_classify_horizon(df$Horizon)
  # LMH25 (2023): upland organic L/F/H ordered UpperDepth DESC; wetland Of/Om/Oh & mineral A/B/C/R/W ordered UpperDepth ASC
  regime_rank <- match(df$HorizonRegime, c("upland_organic", "wetland_organic", "mineral"))
  depth_key <- ifelse(
    df$HorizonRegime == "upland_organic",
    -suppressWarnings(as.numeric(df$UpperDepth)),
    suppressWarnings(as.numeric(df$UpperDepth))
  )
  ord <- order(df$PlotNumber, regime_rank, depth_key, na.last = TRUE)
  df <- df[ord, , drop = FALSE]
  rownames(df) <- NULL
  tibble::as_tibble(df)
}

#' Read tidy `LMH25 (2023)`-ordered soil humus and mineral horizon records
#'
#' Extracts `<Project>_Humus` and/or `<Project>_Mineral`, preserves literal
#' character `PlotNumber`s, converts `Flag` to R `logical`, annotates
#' `HorizonRegime` (`"upland_organic"`, `"wetland_organic"`, `"mineral"`), and
#' orders horizons per `LMH25 (2023)` (`L/F/H` ordered `UpperDepth DESC`;
#' `Of/Om/Oh` and `A/B/C/R/W` ordered `UpperDepth ASC`).
#'
#' @param ws A `vpro_workspace` handle.
#' @param scope Either `"su"` or `"project"`.
#' @param type `"both"` (returns S3 `vpro_soil` bundle with `$humus` and
#'   `$mineral` tibbles), `"humus"`, or `"mineral"`.
#' @return A tibble (`type = "humus"` or `"mineral"`) or `vpro_soil` list (`type = "both"`).
#' @export
vpro_soil <- function(ws, scope = c("su", "project"), type = c("both", "humus", "mineral")) {
  vpro_assert_workspace(ws)
  scope <- match.arg(scope)
  type <- match.arg(type)

  su_df <- vpro_site_units(ws)
  scoped_plots <- if (identical(scope, "su") && !is.null(ws$su)) su_df$PlotNumber else NULL

  dbc <- vpro_sqlite_ro(ws$project_path)
  on.exit(DBI::dbDisconnect(dbc), add = TRUE)

  read_one <- function(suffix) {
    tbl <- paste0(ws$project, "_", suffix)
    flds <- DBI::dbListFields(dbc, tbl)
    sel <- paste(vapply(flds, function(f) {
      if (identical(f, "PlotNumber")) 'CAST("PlotNumber" AS TEXT) AS "PlotNumber"' else vpro_quote_ident(f)
    }, character(1)), collapse = ", ")
    raw <- vpro_query_scoped_plots(dbc, vpro_quote_ident(tbl), scoped_plots, select_cols = sel)
    vpro_order_soil_df(raw)
  }

  if (type == "humus") return(read_one("Humus"))
  if (type == "mineral") return(read_one("Mineral"))

  structure(
    list(
      humus = read_one("Humus"),
      mineral = read_one("Mineral")
    ),
    class = "vpro_soil"
  )
}

#' @export
print.vpro_soil <- function(x, ...) {
  cli::cli_h3("vpro_soil (LMH25-ordered)")
  cli::cli_bullets(c(
    "*" = "Humus horizons: {nrow(x$humus)} rows ({length(unique(x$humus$PlotNumber))} plots)",
    "*" = "Mineral horizons: {nrow(x$mineral)} rows ({length(unique(x$mineral$PlotNumber))} plots)"
  ))
  invisible(x)
}

#' @export
as_tibble.vpro_soil <- function(x, ...) {
  h <- x$humus[, intersect(c("PlotNumber", "Horizon", "UpperDepth", "LowerDepth", "HorizonRegime"), names(x$humus)), drop = FALSE]
  h$SoilLayer <- rep("Humus", nrow(h))
  m <- x$mineral[, intersect(c("PlotNumber", "Horizon", "UpperDepth", "LowerDepth", "HorizonRegime"), names(x$mineral)), drop = FALSE]
  m$SoilLayer <- rep("Mineral", nrow(m))
  tibble::as_tibble(rbind(h, m))
}

#' Read `<Project>_Other` plot records
#'
#' @param ws A `vpro_workspace` handle.
#' @param scope Either `"su"` or `"project"`.
#' @return A tibble of `_Other` records.
#' @export
vpro_other <- function(ws, scope = c("su", "project")) {
  vpro_assert_workspace(ws)
  scope <- match.arg(scope)
  scoped_plots <- if (identical(scope, "su") && !is.null(ws$su)) vpro_site_units(ws)$PlotNumber else NULL
  dbc <- vpro_sqlite_ro(ws$project_path)
  on.exit(DBI::dbDisconnect(dbc), add = TRUE)
  tbl <- paste0(ws$project, "_Other")
  flds <- DBI::dbListFields(dbc, tbl)
  sel <- paste(vapply(flds, function(f) {
    if (identical(f, "PlotNumber")) 'CAST("PlotNumber" AS TEXT) AS "PlotNumber"' else vpro_quote_ident(f)
  }, character(1)), collapse = ", ")
  df <- vpro_query_scoped_plots(dbc, vpro_quote_ident(tbl), scoped_plots, select_cols = sel)
  df$PlotNumber <- as.character(df$PlotNumber)
  for (bc in intersect(c("UserFlag1", "UserFlag2", "UserFlag3", "Flag"), names(df))) {
    df[[bc]] <- vpro_access_to_logical(df[[bc]])
  }
  tibble::as_tibble(df)
}

#' Read `<Project>_Audit` trail records
#'
#' @param ws A `vpro_workspace` handle.
#' @return A tibble of `_Audit` records with normalized booleans.
#' @export
vpro_audit <- function(ws) {
  vpro_assert_workspace(ws)
  dbc <- vpro_sqlite_ro(ws$project_path)
  on.exit(DBI::dbDisconnect(dbc), add = TRUE)
  tbl <- paste0(ws$project, "_Audit")
  flds <- DBI::dbListFields(dbc, tbl)
  sel <- paste(vapply(flds, function(f) {
    if (identical(f, "PlotNumber")) 'CAST("PlotNumber" AS TEXT) AS "PlotNumber"' else vpro_quote_ident(f)
  }, character(1)), collapse = ", ")
  df <- DBI::dbGetQuery(dbc, paste("SELECT", sel, "FROM", vpro_quote_ident(tbl), "ORDER BY rowid"))
  if ("PlotNumber" %in% names(df)) df$PlotNumber <- as.character(df$PlotNumber)
  for (bc in intersect(c("Restore", "Flag"), names(df))) {
    df[[bc]] <- vpro_access_to_logical(df[[bc]])
  }
  tibble::as_tibble(df)
}

#' Read `<Project>_Metadata` records
#'
#' @param ws A `vpro_workspace` handle.
#' @return A tibble of project metadata rows.
#' @export
vpro_metadata <- function(ws) {
  vpro_assert_workspace(ws)
  dbc <- vpro_sqlite_ro(ws$project_path)
  on.exit(DBI::dbDisconnect(dbc), add = TRUE)
  tbl <- paste0(ws$project, "_Metadata")
  df <- DBI::dbGetQuery(dbc, paste("SELECT * FROM", vpro_quote_ident(tbl)))
  tibble::as_tibble(df)
}

.vpro_hierarchy_level_names <- c(
  "Formation", "Class", "Subclass", "Order", "Suborder",
  "Alliance", "Suball", "Assoc", "Subass", "Facies", "SiteUnit"
)

#' Convert a VPro `*_Hierarchy` node table to a flat 11-level BEC path table
#'
#' Pure `data.table` counterpart to MoF `treeToTable()`, handling `~` tilde
#' breakpoint prefixes, filling missing `Suborder`/`Suball`/`Subass` from their
#' parent level, and reporting `BreakpointUnit` (the lowest `~`-prefixed
#' ancestor along each branch) for dynamic hierarchy rollups.
#'
#' @param nodes_df Data frame containing `ID`, `Name`, `Parent`, and `Level`.
#' @param preserve_tilde Logical; if `TRUE`, retains leading `~` breakpoint
#'   prefixes in the 11 level columns for lossless round-tripping with
#'   [vpro_table_to_hierarchy()].
#' @return A tibble with leaf/terminal branch rows across the 11 BEC levels plus
#'   `LeafName`, `CleanLeafName`, and `BreakpointUnit`.
#' @export
vpro_hierarchy_to_table <- function(nodes_df, preserve_tilde = FALSE) {
  req <- c("ID", "Name", "Parent", "Level")
  if (!is.data.frame(nodes_df) || !all(req %in% names(nodes_df))) {
    rlang::abort("`nodes_df` must contain `ID`, `Name`, `Parent`, and `Level` columns.")
  }
  if (nrow(nodes_df) == 0L) {
    empty <- as.list(rep(list(character()), length(.vpro_hierarchy_level_names)))
    names(empty) <- .vpro_hierarchy_level_names
    empty$LeafName <- character()
    empty$CleanLeafName <- character()
    empty$BreakpointUnit <- character()
    return(tibble::as_tibble(empty))
  }

  id_chr <- as.character(nodes_df$ID)
  parent_chr <- ifelse(is.na(nodes_df$Parent), NA_character_, as.character(nodes_df$Parent))
  raw_name <- trimws(as.character(nodes_df$Name))
  is_brk <- startsWith(raw_name, "~")
  clean_name <- sub("^~+", "", raw_name)
  disp_name <- if (isTRUE(preserve_tilde)) raw_name else clean_name
  lvl <- suppressWarnings(as.integer(nodes_df$Level))
  lvl[is.na(lvl) | lvl < 1L] <- 11L
  lvl[lvl > 11L] <- 11L

  idx_by_id <- stats::setNames(seq_along(id_chr), id_chr)
  has_children <- id_chr %in% parent_chr[!is.na(parent_chr)]
  leaves <- which(!has_children)

  rows <- lapply(leaves, function(leaf_i) {
    chain <- integer()
    cur <- leaf_i
    visited <- integer()
    while (!is.na(cur) && !(cur %in% visited)) {
      chain <- c(cur, chain)
      visited <- c(visited, cur)
      p_id <- parent_chr[[cur]]
      if (is.na(p_id) || !(p_id %in% names(idx_by_id))) break
      nxt <- idx_by_id[[p_id]]
      if (identical(nxt, cur)) break
      cur <- nxt
    }
    vals <- rep(NA_character_, 11L)
    brk_unit <- NA_character_
    for (ci in chain) {
      lv <- lvl[[ci]]
      vals[[lv]] <- disp_name[[ci]]
      if (is_brk[[ci]]) {
        brk_unit <- clean_name[[ci]]
      }
    }
    # MoF HierarchyConversion.R convention: fill missing Suborder/Suball/Subass from parent
    if (is.na(vals[[5L]]) && !is.na(vals[[4L]])) vals[[5L]] <- vals[[4L]]
    if (is.na(vals[[7L]]) && !is.na(vals[[6L]])) vals[[7L]] <- vals[[6L]]
    if (is.na(vals[[9L]]) && !is.na(vals[[8L]])) vals[[9L]] <- vals[[8L]]
    if (is.na(vals[[11L]])) vals[[11L]] <- disp_name[[leaf_i]]

    rec <- as.list(vals)
    names(rec) <- .vpro_hierarchy_level_names
    rec$LeafName <- raw_name[[leaf_i]]
    rec$CleanLeafName <- clean_name[[leaf_i]]
    rec$BreakpointUnit <- brk_unit
    tibble::as_tibble(rec)
  })
  do.call(rbind, rows)
}

#' Convert a wide BEC hierarchy table into a VPro `*_Hierarchy` node table
#'
#' Pure R counterpart to MoF `tableToTree()`, generating deterministic integer
#' `ID`, `Name`, `Parent`, and `Level` rows ready for VPro `*_Hierarchy` storage.
#'
#' @param wide_df Data frame whose columns correspond to ordered hierarchy
#'   levels (defaults to intersecting `.vpro_hierarchy_level_names` or all columns).
#' @param level_names Optional character vector of level column names in
#'   top-to-bottom order.
#' @return A tibble with `ID`, `Name`, `Parent`, and `Level`.
#' @export
vpro_table_to_hierarchy <- function(wide_df, level_names = NULL) {
  if (!is.data.frame(wide_df) || ncol(wide_df) == 0L) {
    rlang::abort("`wide_df` must be a non-empty data frame of hierarchy level columns.")
  }
  if (is.null(level_names)) {
    std <- intersect(.vpro_hierarchy_level_names, names(wide_df))
    level_names <- if (length(std) >= 2L) std else names(wide_df)
  }
  lvl_nums <- match(level_names, .vpro_hierarchy_level_names)
  if (anyNA(lvl_nums)) {
    lvl_nums <- seq_along(level_names)
  }

  node_env <- new.env(hash = TRUE, parent = emptyenv())
  records <- list()
  next_id <- 0L

  for (r in seq_len(nrow(wide_df))) {
    parent_id <- NA_integer_
    path_key <- ""
    for (c_ix in seq_along(level_names)) {
      col <- level_names[[c_ix]]
      val <- wide_df[[col]][[r]]
      if (is.na(val) || !nzchar(trimws(as.character(val)))) next
      nm <- trimws(as.character(val))
      lv <- as.integer(lvl_nums[[c_ix]])
      # Collapse consecutive identical filled sublevels (e.g. Suborder == Order)
      key <- paste0(path_key, "/", lv, ":", nm)
      if (!is.na(parent_id) && length(records) >= parent_id &&
          identical(records[[parent_id]]$Name, nm)) {
        next
      }
      if (exists(key, envir = node_env, inherits = FALSE)) {
        parent_id <- get(key, envir = node_env, inherits = FALSE)
      } else {
        next_id <- next_id + 1L
        records[[next_id]] <- list(
          ID = next_id,
          Name = nm,
          Parent = parent_id,
          Level = lv
        )
        assign(key, next_id, envir = node_env)
        parent_id <- next_id
      }
      path_key <- key
    }
  }
  if (length(records) == 0L) {
    return(tibble::tibble(ID = integer(), Name = character(), Parent = integer(), Level = integer()))
  }
  tibble::tibble(
    ID = vapply(records, `[[`, integer(1), "ID"),
    Name = vapply(records, `[[`, character(1), "Name"),
    Parent = vapply(records, `[[`, integer(1), "Parent"),
    Level = vapply(records, `[[`, integer(1), "Level")
  )
}

#' Read classification hierarchy (`*_Hierarchy`) as nodes and/or flat BEC paths
#'
#' Reads `<Name>_Hierarchy`, identifies `~Name` tilde breakpoints, and builds
#' both the parent-pointer `nodes` tibble (with `CleanName`, `IsBreakpoint`, and
#' `Path`) and the flat 11-level `paths` tibble (`Formation`..`SiteUnit` +
#' `BreakpointUnit`).
#'
#' @param ws A `vpro_workspace` handle.
#' @param hierarchy Optional `*_Hierarchy` table override (defaults to
#'   `ws$hierarchy`).
#' @param as Return shape: `"both"` (S3 `vpro_hierarchy` bundle with `$nodes` and
#'   `$paths`), `"nodes"`, or `"paths"`.
#' @return A `vpro_hierarchy` list (`as = "both"`) or tibble (`"nodes"` / `"paths"`).
#' @export
vpro_hierarchy <- function(ws, hierarchy = NULL, as = c("both", "nodes", "paths")) {
  vpro_assert_workspace(ws)
  as <- match.arg(as)
  h_tbl <- if (is.null(hierarchy)) {
    ws$hierarchy
  } else {
    tables <- vpro_sqlite_physical_tables(ws$hierarchy_path)
    vpro_resolve_table_suffix(tables, hierarchy, "Hierarchy", default_prefix = ws$project)
  }
  if (is.null(h_tbl)) {
    empty_nodes <- tibble::tibble(
      ID = integer(), Name = character(), CleanName = character(),
      Parent = integer(), Level = integer(), LevelName = character(),
      IsBreakpoint = logical(), Path = character()
    )
    empty_paths <- vpro_hierarchy_to_table(empty_nodes)
    if (as == "nodes") return(empty_nodes)
    if (as == "paths") return(empty_paths)
    return(structure(list(table = NA_character_, nodes = empty_nodes, paths = empty_paths), class = "vpro_hierarchy"))
  }

  dbc <- vpro_sqlite_ro(ws$hierarchy_path)
  on.exit(DBI::dbDisconnect(dbc), add = TRUE)
  raw <- DBI::dbGetQuery(dbc, paste("SELECT * FROM", vpro_quote_ident(h_tbl)))
  if ("Flag" %in% names(raw)) raw$Flag <- vpro_access_to_logical(raw$Flag)

  raw_nm <- trimws(ifelse(is.na(raw$Name), "", as.character(raw$Name)))
  raw$IsBreakpoint <- startsWith(raw_nm, "~")
  raw$CleanName <- sub("^~+", "", raw_nm)
  lvl_int <- suppressWarnings(as.integer(raw$Level))
  raw$LevelName <- ifelse(
    !is.na(lvl_int) & lvl_int >= 1L & lvl_int <= 11L,
    .vpro_hierarchy_level_names[lvl_int],
    NA_character_
  )

  # Build root-to-node "/" Path string
  id_chr <- as.character(raw$ID)
  par_chr <- ifelse(is.na(raw$Parent), NA_character_, as.character(raw$Parent))
  idx_map <- stats::setNames(seq_along(id_chr), id_chr)
  raw$Path <- vapply(seq_len(nrow(raw)), function(i) {
    parts <- character()
    cur <- i
    seen <- integer()
    while (!is.na(cur) && !(cur %in% seen)) {
      parts <- c(raw$CleanName[[cur]], parts)
      seen <- c(seen, cur)
      p <- par_chr[[cur]]
      if (is.na(p) || !(p %in% names(idx_map))) break
      nxt <- idx_map[[p]]
      if (identical(nxt, cur)) break
      cur <- nxt
    }
    paste(parts, collapse = " / ")
  }, character(1))

  nodes_tbl <- tibble::as_tibble(raw)
  paths_tbl <- vpro_hierarchy_to_table(nodes_tbl)

  if (as == "nodes") return(nodes_tbl)
  if (as == "paths") return(paths_tbl)
  structure(
    list(
      table = h_tbl,
      nodes = nodes_tbl,
      paths = paths_tbl
    ),
    class = "vpro_hierarchy"
  )
}

#' @export
print.vpro_hierarchy <- function(x, ...) {
  n_brk <- sum(x$nodes$IsBreakpoint, na.rm = TRUE)
  cli::cli_h3("vpro_hierarchy: {.val {if (is.na(x$table)) '<none>' else x$table}}")
  cli::cli_bullets(c(
    "*" = "Nodes: {nrow(x$nodes)} ({n_brk} `~` breakpoint{?s})",
    "*" = "Terminal site-unit paths: {nrow(x$paths)}"
  ))
  invisible(x)
}

#' @export
as_tibble.vpro_hierarchy <- function(x, ...) {
  x$paths
}
