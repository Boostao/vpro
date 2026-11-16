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
#' Matches VPro Desktop quality-control filtering: ranks `SitePlotQuality`,
#' `VegPlotQuality`, and `SoilPlotQuality` via `USysTableOfLists`
#' (`ListName = 'DataQuality'`), applies case-insensitive lexical
#' `BEC_Use >= bec_min` when `bec_min` is supplied, and optionally drops
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
  all_items <- tolower(
    DBI::dbGetQuery(
      dbc_vlists,
      'SELECT DISTINCT "Item" FROM "USysTableOfLists" WHERE "Item" IS NOT NULL'
    )$Item
  )
  lvl_keys <- tolower(levels$Item)
  resolve_thresh <- function(val, arg) {
    ix <- match(tolower(trimws(val)), lvl_keys)
    if (is.na(ix)) {
      rlang::abort(paste0("`", arg, "` is not a configured DataQuality level: ", val))
    }
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
        bec_expr,
        ' AS "BEC_Use", ',
        'CASE WHEN admin."Plot" IS NOT NULL THEN 1 ELSE 0 END AS "has_admin" ',
        'FROM ',
        env_q,
        ' AS env LEFT JOIN ',
        adm_q,
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
        bec_expr,
        ' AS "BEC_Use", ',
        'CASE WHEN admin."Plot" IS NOT NULL THEN 1 ELSE 0 END AS "has_admin" ',
        'FROM ',
        env_q,
        ' AS env LEFT JOIN ',
        adm_q,
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
      cmp[!miss] <- vapply(
        src$BEC_Use[!miss],
        function(val) {
          vl <- tolower(enc2utf8(val))
          identical(vl, thr_low) || sort(c(vl, thr_low), method = "radix")[[1L]] == thr_low
        },
        logical(1)
      )
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
    reasons <- vapply(
      rem_idx,
      function(i) {
        r <- character()
        if (!src$complete_plot[[i]]) {
          r <- c(r, "Project")
        }
        if (src$complete_plot[[i]] && !s_ok[[i]]) {
          r <- c(r, "Site")
        }
        if (src$complete_plot[[i]] && !v_ok[[i]]) {
          r <- c(r, "Veg")
        }
        if (src$complete_plot[[i]] && !so_ok[[i]]) {
          r <- c(r, "Soil")
        }
        if (src$complete_plot[[i]] && !b_ok[[i]]) {
          r <- c(r, "BEC")
        }
        paste(r, collapse = ",")
      },
      character(1)
    )
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
  env_select <- vapply(
    env_fields,
    function(f) {
      qf <- vpro_quote_ident(f)
      if (identical(f, "PlotNumber")) {
        'CAST(env."PlotNumber" AS TEXT) AS "PlotNumber"'
      } else {
        paste0("env.", qf, " AS ", qf)
      }
    },
    character(1)
  )

  join_sql <- ""
  adm_select <- character()
  if (isTRUE(include_admin) && DBI::dbExistsTable(dbc, adm_tbl)) {
    adm_fields <- setdiff(DBI::dbListFields(dbc, adm_tbl), c("Plot", env_fields))
    if (!is.null(columns)) {
      adm_fields <- adm_fields[tolower(adm_fields) %in% tolower(as.character(columns))]
    }
    if (length(adm_fields) > 0L) {
      adm_select <- vapply(
        adm_fields,
        function(f) {
          qf <- vpro_quote_ident(f)
          paste0("admin.", qf, " AS ", qf)
        },
        character(1)
      )
      join_sql <- paste0(
        " LEFT JOIN ",
        vpro_quote_ident(adm_tbl),
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
          "SELECT ",
          paste(c(env_select, adm_select), collapse = ", "),
          " FROM ",
          vpro_quote_ident(env_tbl),
          " AS env",
          join_sql,
          ' WHERE typeof(env."PlotNumber") = \'text\' AND env."PlotNumber" IN (',
          ph_txt,
          ') AND CAST(env."PlotNumber" AS BLOB) IN (',
          ph_blb,
          ')'
        )
        DBI::dbGetQuery(dbc, q, params = as.list(c(ch, ch)))
      })
      df <- do.call(rbind, parts)
    }
  } else {
    sql <- paste0(
      "SELECT ",
      paste(c(env_select, adm_select), collapse = ", "),
      " FROM ",
      vpro_quote_ident(env_tbl),
      " AS env",
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
        ws = ws,
        site_min = filter_quality,
        veg_min = filter_quality,
        soil_min = filter_quality,
        scope = scope,
        exclude_modifiers = exclude_modifiers
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

#' Read tidy vegetation records (`_Veg`) with synonym, lump, and strata synthesis
#'
#' Extracts physical `<Project>_Veg` records, applies VPro single-precision
#' cover rounding, optionally resolves `BCPlantTaxonomy v19` synonyms
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
    if (ncol(mat) == 0L) {
      return(rep(NA_real_, nrow(mat)))
    }
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
      if (length(ok) == 0L) {
        NA_real_
      } else if (length(ok) == 1L) {
        ok
      } else {
        min(sum(ok), 99.0)
      }
    }
    dt <- dt[, lapply(.SD, sum_cap99), by = c("PlotNumber", "Species"), .SDcols = cov_cols]
  }

  # Layer-to-Strata mapping (matching LayerCode.Layer1234567)
  strata_of_layer <- c(
    "1" = "A",
    "2" = "A",
    "3" = "A",
    "A" = "A",
    "4" = "B",
    "5" = "B",
    "5a" = "B",
    "5b" = "B",
    "5c" = "B",
    "B" = "B",
    "6" = "C",
    "7" = "D",
    "8" = "D",
    "9" = "D",
    "10" = "D"
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
      if (!any(ok)) {
        return(NULL)
      }
      data.table::data.table(
        PlotNumber = dt$PlotNumber[ok],
        Species = dt$Species[ok],
        Layer = rep(lyr, sum(ok)),
        Strata = rep(unname(strata_of_layer[[lyr]]), sum(ok)),
        Cover = v[ok]
      )
    })
    long_dt <- data.table::rbindlist(Filter(Negate(is.null), long_parts))
    if (nrow(long_dt) == 0L) {
      return(empty_out())
    }
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
      A = cov_a,
      B = cov_b,
      C = cov_c,
      D = cov_d
    )
    parts <- lapply(names(abcd_list), function(st) {
      v <- abcd_list[[st]]
      ok <- !is.na(v) & v > 0
      if (!any(ok)) {
        return(NULL)
      }
      data.table::data.table(
        PlotNumber = dt$PlotNumber[ok],
        Species = dt$Species[ok],
        Strata = rep(st, sum(ok)),
        Cover = v[ok]
      )
    })
    res_dt <- data.table::rbindlist(Filter(Negate(is.null), parts))
    if (nrow(res_dt) == 0L) {
      return(empty_out())
    }
    res_dt <- attach_meta(res_dt)
    data.table::setorderv(res_dt, c("PlotNumber", "Species", "Strata"))
    cols <- c("PlotNumber", "SiteUnit", "Species", "Strata", "Cover", "ScientificName", "EnglishName", "Lifeform")
    return(tibble::as_tibble(res_dt[, cols, with = FALSE]))
  }

  tot_cov <- combine_cols(cbind(cov_a, cov_b, cov_c, cov_d))
  ok <- !is.na(tot_cov) & tot_cov > 0
  if (!any(ok)) {
    return(empty_out())
  }
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
