# PostgreSQL BECMaster Tidy Ecological Queries (Env, Veg, Soil) --------------

#' Query tidy plot environment and administration records from PostgreSQL `BECMaster`
#'
#' Executes a parameterized push-down query against `becmaster.env` (optionally
#' left-joining `becmaster.admin`), preserving literal leading-zero `PlotNumber`
#' strings, converting Access `-1/0` booleans to R `logical`, narrowing
#' `StrataCover*` columns to IEEE-754 `float32`, and deriving `SiteUnit` so the
#' returned tibble matches [vpro_env()] column names and types. When connecting
#' as a non-custodian role, coordinates (`Latitude`, `Longitude`, `UTMEasting`,
#' `UTMNorthing`, `UTMZone`) are automatically redacted to `NA` on plots
#' containing sensitive (`USysSppAttributes.RedBlueList`) species.
#'
#' @param pg A `vpro_pg_conn` handle created by `vpro_master_connect()`.
#' @param zones Optional character vector of BEC zone codes (e.g. `"CWH"`, `"SBS"`).
#' @param subzones Optional character vector of BEC subzone/variant codes (e.g. `"vm1"`).
#' @param project_ids Optional character vector of `ProjectID` values.
#' @param plots Optional character vector of literal `PlotNumber` values
#'   (preserving leading zeroes such as `"00337"`).
#' @param bbox Optional spatial bounding box as `c(min_lon, min_lat, max_lon, max_lat)`
#'   in EPSG:4326 or an `sf` `bbox` object.
#' @param include_admin Logical; if `TRUE` (default), left-joins `becmaster.admin`
#'   and derives `SiteUnit` from `BECSiteUnit` / `UserSiteUnit`.
#' @param columns Optional character vector of `_Env`/`_Admin` column names to
#'   project (`PlotNumber` and `SiteUnit` are always retained).
#' @param limit Optional positive integer row limit.
#' @param allow_full Logical; set `TRUE` to explicitly authorize an unfiltered
#'   full-table query when no filter or `limit` is supplied.
#' @return A tibble of plot environment records ordered by `PlotNumber`.
#' @export
vpro_master_env <- function(
  pg,
  zones = NULL,
  subzones = NULL,
  project_ids = NULL,
  plots = NULL,
  bbox = NULL,
  include_admin = TRUE,
  columns = NULL,
  limit = NULL,
  allow_full = FALSE
) {
  vpro_assert_pg_conn(pg, require_custodian = FALSE)
  include_admin <- vpro_pg_validate_flag(include_admin, "include_admin")
  allow_full <- vpro_pg_validate_flag(allow_full, "allow_full")
  limit_int <- vpro_pg_validate_limit(limit, allow_null = TRUE)

  sub <- vpro_pg_subset_where(
    pg = pg,
    zones = zones,
    subzones = subzones,
    project_ids = project_ids,
    plots = plots,
    bbox = bbox,
    table_alias = "e",
    allow_full = allow_full,
    has_limit = !is.null(limit_int)
  )

  env_spec <- vpro_pg_vp08_specs("Env")
  adm_spec <- vpro_pg_vp08_specs("Admin")
  env_fields <- as.character(env_spec$name)

  if (!is.null(columns)) {
    if (!is.character(columns)) {
      cli::cli_abort("{.arg columns} must be {.code NULL} or a character vector of column names.")
    }
    req_cols <- unique(c("PlotNumber", as.character(columns)))
    env_fields <- env_fields[tolower(env_fields) %in% tolower(req_cols)]
  }

  env_select <- vapply(env_fields, function(f) {
    qf <- vpro_quote_ident(f)
    if (identical(f, "PlotNumber")) {
      'CAST(e."PlotNumber" AS TEXT) AS "PlotNumber"'
    } else {
      paste0("e.", qf, " AS ", qf)
    }
  }, character(1))

  join_sql <- ""
  adm_select <- character()
  adm_fields <- character()
  su_expr <- 'CAST(NULL AS TEXT) AS "SiteUnit"'

  if (isTRUE(include_admin)) {
    join_sql <- ' LEFT JOIN becmaster.admin AS a ON e."PlotNumber" = a."Plot"'
    su_expr <- 'COALESCE(NULLIF(TRIM(a."BECSiteUnit"), \'\'), NULLIF(TRIM(a."UserSiteUnit"), \'\')) AS "SiteUnit"'
    adm_fields <- setdiff(as.character(adm_spec$name), c("Plot", env_fields))
    if (!is.null(columns)) {
      adm_fields <- adm_fields[tolower(adm_fields) %in% tolower(as.character(columns))]
    }
    if (length(adm_fields) > 0L) {
      adm_select <- vapply(adm_fields, function(f) {
        qf <- vpro_quote_ident(f)
        paste0("a.", qf, " AS ", qf)
      }, character(1))
    }
  }

  select_parts <- c(env_select[[1L]], su_expr, env_select[-1L], adm_select)
  where_part <- if (nzchar(sub$where_sql)) paste0(" ", sub$where_sql) else ""
  limit_part <- if (!is.null(limit_int)) sprintf(" LIMIT %d", limit_int) else ""
  sql <- paste0(
    "SELECT ", paste(select_parts, collapse = ", "),
    " FROM becmaster.env AS e",
    join_sql,
    where_part,
    ' ORDER BY e."PlotNumber"',
    limit_part
  )

  df <- vpro_pg_query(
    pg,
    sql,
    params = if (length(sub$params) > 0L) sub$params else NULL,
    action = "query becmaster.env"
  )

  comb_spec <- rbind(
    env_spec[env_spec$name %in% env_fields, , drop = FALSE],
    adm_spec[adm_spec$name %in% adm_fields, , drop = FALSE]
  )
  if (nrow(comb_spec) > 0L) {
    su_col <- if ("SiteUnit" %in% names(df)) as.character(df$SiteUnit) else rep(NA_character_, nrow(df))
    canon_sub <- vpro_pg_canonicalize_to_tidy(
      df[, intersect(comb_spec$name, names(df)), drop = FALSE],
      comb_spec
    )
    for (nm in names(canon_sub)) {
      df[[nm]] <- canon_sub[[nm]]
    }
    df$SiteUnit <- su_col
  }

  df$PlotNumber <- as.character(df$PlotNumber)
  df$SiteUnit <- if ("SiteUnit" %in% names(df)) as.character(df$SiteUnit) else rep(NA_character_, nrow(df))

  bool_cols <- unique(c(
    "SpeciesListComplete", "Flag", "SV_FloodPlain", "UpdatedFromCards",
    as.character(comb_spec$name[!is.na(comb_spec$is_bool) & comb_spec$is_bool])
  ))
  for (bc in intersect(bool_cols, names(df))) {
    df[[bc]] <- vpro_access_to_logical(df[[bc]])
  }

  cov_cols <- unique(c(
    grep("^StrataCover", names(df), value = TRUE),
    as.character(comb_spec$name[!is.na(comb_spec$is_cover) & comb_spec$is_cover])
  ))
  for (cc in intersect(cov_cols, names(df))) {
    df[[cc]] <- vpro_narrow_float32(as.numeric(df[[cc]]))
  }

  if (!identical(pg$role, "custodian") && nrow(df) > 0L) {
    sens_codes <- .vpro_sensitive_species_codes(pg = pg)
    if (length(sens_codes) > 0L) {
      sens_plots <- .vpro_sensitive_plots_in_pg(pg, df$PlotNumber, sens_codes)
      if (length(sens_plots) > 0L) {
        df <- .vpro_redact_coord_df(df, sens_plots)
      }
    }
  }

  front <- intersect(c("PlotNumber", "SiteUnit"), names(df))
  df <- df[, c(front, setdiff(names(df), front)), drop = FALSE]
  rownames(df) <- NULL
  tibble::as_tibble(df)
}

vpro_pg_load_cloud_taxonomy <- function(pg, resolve_synonyms = TRUE) {
  sql <- paste(
    'SELECT UPPER(TRIM(CAST("Code" AS TEXT))) AS "Code",',
    '       UPPER(TRIM(CAST("OldCode" AS TEXT))) AS "OldCode",',
    '       CAST("ScientificName" AS TEXT) AS "ScientificName",',
    '       CAST("EnglishName" AS TEXT) AS "EnglishName",',
    '       CAST("Lifeform" AS INTEGER) AS "Lifeform",',
    '       CAST("Codetype" AS TEXT) AS "Codetype"',
    "FROM standards.usys_all_specs",
    'WHERE "Code" IS NOT NULL AND TRIM("Code") <> \'\''
  )
  cloud_specs <- tryCatch(
    vpro_pg_query(pg, sql, params = NULL, action = "query standards.usys_all_specs"),
    error = function(e) NULL
  )

  if (!is.null(cloud_specs) && nrow(cloud_specs) > 0L) {
    cloud_specs$Code <- toupper(trimws(as.character(cloud_specs$Code)))
    cloud_specs$OldCode <- toupper(trimws(as.character(cloud_specs$OldCode)))
    cloud_specs$ScientificName <- as.character(cloud_specs$ScientificName)
    cloud_specs$EnglishName <- as.character(cloud_specs$EnglishName)
    cloud_specs$Lifeform <- suppressWarnings(as.integer(as.character(cloud_specs$Lifeform)))
    cloud_specs$Codetype <- as.character(cloud_specs$Codetype)

    syn_map <- character()
    if (isTRUE(resolve_synonyms)) {
      is_s <- !is.na(cloud_specs$Codetype) & tolower(trimws(cloud_specs$Codetype)) == "s"
      syns <- cloud_specs[
        is_s &
          !is.na(cloud_specs$OldCode) & nzchar(cloud_specs$OldCode) &
          !is.na(cloud_specs$Code) & nzchar(cloud_specs$Code) &
          cloud_specs$OldCode != cloud_specs$Code,
        c("OldCode", "Code"),
        drop = FALSE
      ]
      syns <- syns[!duplicated(syns$OldCode), , drop = FALSE]
      syn_map <- stats::setNames(syns$Code, syns$OldCode)
    }

    non_syn <- cloud_specs[
      !(!is.na(cloud_specs$Codetype) & tolower(trimws(cloud_specs$Codetype)) == "s"),
      ,
      drop = FALSE
    ]
    if (nrow(non_syn) > 0L) {
      ord <- order(
        non_syn$Code,
        ifelse(!is.na(non_syn$Codetype) & toupper(trimws(non_syn$Codetype)) == "U", 0L, 1L)
      )
      non_syn <- non_syn[ord, , drop = FALSE]
      non_syn <- non_syn[!duplicated(non_syn$Code), , drop = FALSE]
    }
    return(list(
      syn_map = syn_map,
      tax = non_syn[, c("Code", "ScientificName", "EnglishName", "Lifeform"), drop = FALSE]
    ))
  }

  list(
    syn_map = if (isTRUE(resolve_synonyms)) vpro_synonym_map(NULL) else character(),
    tax = vpro_taxonomy(NULL, include_synonyms = FALSE, include_user = FALSE)
  )
}

#' Query tidy vegetation records from PostgreSQL `BECMaster` with lump and strata synthesis
#'
#' Pushes plot filtering down to PostgreSQL via a `WITH matched AS (...)` CTE on
#' `becmaster.env` + `becmaster.admin`, extracts matching `becmaster.veg` rows,
#' and runs the exact [vpro_veg()] phytosociological pipeline: IEEE-754 `float32`
#' cover narrowing, duplicate `(PlotNumber, Species)` `max` deduplication,
#' pre-lump effective stratum synthesis (`TotalA`/`TotalB` fallback), optional
#' taxonomic lumping with VPro's `99%` per-layer cap (`pmin(sum, 99)`), optional
#' `BCPlantTaxonomy v19` synonym resolution (`standards.usys_all_specs` with
#' bundled `VLists.db` fallback), and `total` / `abcd` / `lifeform` / `raw`
#' aggregation.
#'
#' @inheritParams vpro_master_env
#' @param strata Aggregation level: `"total"` (default), `"abcd"` (`A`, `B`, `C`,
#'   `D`), `"lifeform"`, or `"raw"` (`1..10`, `5a..5c`, `A`, `B`).
#' @param combine Multi-layer combination formula: `"pielou"` (probabilistic
#'   complement \eqn{100 \times (1 - \prod_i (1 - c_i / 100))}) or `"sum"`
#'   (additive sum capped at `99%`).
#' @param lump Optional species lump mapping: `NULL` / `FALSE` (disabled) or a
#'   two-column `data.frame(SppCode, LumpCode)` (with optional `Use` column).
#' @param resolve_synonyms Logical; if `TRUE` (default), resolves `OldCode -> Code`
#'   synonyms from `standards.usys_all_specs` (falling back to bundled `VLists.db`).
#' @return A tibble matching [vpro_veg()] column names and types identically.
#' @export
vpro_master_veg <- function(
  pg,
  zones = NULL,
  subzones = NULL,
  project_ids = NULL,
  plots = NULL,
  bbox = NULL,
  strata = c("total", "abcd", "lifeform", "raw"),
  combine = c("pielou", "sum"),
  lump = NULL,
  resolve_synonyms = TRUE,
  limit = NULL,
  allow_full = FALSE
) {
  vpro_assert_pg_conn(pg, require_custodian = FALSE)
  strata <- match.arg(strata)
  combine <- match.arg(combine)
  resolve_synonyms <- vpro_pg_validate_flag(resolve_synonyms, "resolve_synonyms")
  allow_full <- vpro_pg_validate_flag(allow_full, "allow_full")
  limit_int <- vpro_pg_validate_limit(limit, allow_null = TRUE)

  if (!is.null(lump) && !identical(lump, FALSE) && !is.data.frame(lump)) {
    cli::cli_abort(
      "{.arg lump} in {.fn vpro_master_veg} must be {.code NULL}, {.code FALSE}, or a {.cls data.frame} containing {.field SppCode} and {.field LumpCode}."
    )
  }
  lump_tbl <- vpro_lump_map(ws = NULL, lump = lump)

  sub <- vpro_pg_subset_where(
    pg = pg,
    zones = zones,
    subzones = subzones,
    project_ids = project_ids,
    plots = plots,
    bbox = bbox,
    table_alias = "e",
    allow_full = allow_full,
    has_limit = !is.null(limit_int)
  )

  where_part <- if (nzchar(sub$where_sql)) paste0(" ", sub$where_sql) else ""
  limit_part <- if (!is.null(limit_int)) sprintf(" LIMIT %d", limit_int) else ""
  sql <- paste0(
    "WITH matched AS (",
    'SELECT e."PlotNumber", ',
    'COALESCE(NULLIF(TRIM(a."BECSiteUnit"), \'\'), NULLIF(TRIM(a."UserSiteUnit"), \'\')) AS "SiteUnit" ',
    "FROM becmaster.env AS e ",
    'LEFT JOIN becmaster.admin AS a ON e."PlotNumber" = a."Plot"',
    where_part,
    ' ORDER BY e."PlotNumber"',
    limit_part,
    ") ",
    'SELECT v.*, m."SiteUnit" AS "__SiteUnit" ',
    "FROM becmaster.veg AS v ",
    'INNER JOIN matched AS m ON v."PlotNumber" = m."PlotNumber" ',
    'WHERE v."Species" IS NOT NULL AND TRIM(v."Species") <> \'\''
  )

  raw_df <- vpro_pg_query(
    pg,
    sql,
    params = if (length(sub$params) > 0L) sub$params else NULL,
    action = "query becmaster.veg"
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

  raw_df$PlotNumber <- as.character(raw_df$PlotNumber)
  raw_df$Species <- toupper(trimws(as.character(raw_df$Species)))
  valid_sp <- !is.na(raw_df$Species) & nzchar(raw_df$Species)
  raw_df <- raw_df[valid_sp, , drop = FALSE]
  if (nrow(raw_df) == 0L) {
    return(empty_out())
  }

  su_vals <- if ("__SiteUnit" %in% names(raw_df)) {
    as.character(raw_df[["__SiteUnit"]])
  } else {
    rep(NA_character_, nrow(raw_df))
  }
  su_keep <- !duplicated(raw_df$PlotNumber)
  su_map <- stats::setNames(su_vals[su_keep], raw_df$PlotNumber[su_keep])

  layer_defs <- c(
    "1" = "Cover1", "2" = "Cover2", "3" = "Cover3", "A" = "TotalA",
    "4" = "Cover4", "5" = "Cover5", "5a" = "Cover5a", "5b" = "Cover5b", "5c" = "Cover5c", "B" = "TotalB",
    "6" = "Cover6", "7" = "Cover7", "8" = "Cover8", "9" = "Cover9", "10" = "Cover10"
  )
  present_layers <- layer_defs[layer_defs %in% names(raw_df)]
  cov_cols <- unname(present_layers)

  dt <- data.table::as.data.table(raw_df[, c("PlotNumber", "Species", cov_cols), drop = FALSE])

  # IEEE-754 float32 narrowing and [0, 100] bounds calibration
  for (cc in cov_cols) {
    v <- vpro_narrow_float32(as.numeric(dt[[cc]]))
    v[!is.na(v) & v > 100] <- 100
    v[!is.na(v) & v < 0] <- NA_real_
    data.table::set(dt, j = cc, value = v)
  }

  max_na <- function(x) {
    ok <- x[!is.na(x)]
    if (length(ok) == 0L) NA_real_ else max(ok)
  }
  if (anyDuplicated(dt, by = c("PlotNumber", "Species")) > 0L) {
    dt <- dt[, lapply(.SD, max_na), by = c("PlotNumber", "Species"), .SDcols = cov_cols]
  }

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

  if (strata != "raw") {
    sub_a <- intersect(c("Cover1", "Cover2", "Cover3"), names(dt))
    eff_a <- combine_cols(as.matrix(dt[, sub_a, with = FALSE]))
    if ("TotalA" %in% names(dt)) {
      ta <- dt[["TotalA"]]
      use_ta <- !is.na(ta) & (ta > 0 | is.na(eff_a))
      eff_a[use_ta] <- ta[use_ta]
    }
    sub_b <- intersect(c("Cover4", "Cover5", "Cover5a", "Cover5b", "Cover5c"), names(dt))
    eff_b <- combine_cols(as.matrix(dt[, sub_b, with = FALSE]))
    if ("TotalB" %in% names(dt)) {
      tb <- dt[["TotalB"]]
      use_tb <- !is.na(tb) & (tb > 0 | is.na(eff_b))
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

  tax_bundle <- vpro_pg_load_cloud_taxonomy(pg, resolve_synonyms = resolve_synonyms)
  syn_map <- tax_bundle$syn_map
  tax <- tax_bundle$tax

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

  if (anyDuplicated(dt, by = c("PlotNumber", "Species")) > 0L) {
    sum_cap99 <- function(x) {
      ok <- x[!is.na(x)]
      if (length(ok) == 0L) NA_real_ else if (length(ok) == 1L) ok else min(sum(ok), 99.0)
    }
    dt <- dt[, lapply(.SD, sum_cap99), by = c("PlotNumber", "Species"), .SDcols = cov_cols]
  }

  strata_of_layer <- c(
    "1" = "A", "2" = "A", "3" = "A", "A" = "A",
    "4" = "B", "5" = "B", "5a" = "B", "5b" = "B", "5c" = "B", "B" = "B",
    "6" = "C",
    "7" = "D", "8" = "D", "9" = "D", "10" = "D"
  )

  attach_meta <- function(res_dt) {
    data.table::set(res_dt, j = "SiteUnit", value = unname(su_map[res_dt[["PlotNumber"]]]))
    ix <- match(res_dt$Species, tax$Code)
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
    abcd_list <- list(A = cov_a, B = cov_b, C = cov_c, D = cov_d)
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
    data.table::setorderv(res_dt, c("PlotNumber", "Lifeform", "Species"))
  } else {
    data.table::setorderv(res_dt, c("PlotNumber", "Species"))
  }
  cols <- c("PlotNumber", "SiteUnit", "Species", "Cover", "ScientificName", "EnglishName", "Lifeform")
  tibble::as_tibble(res_dt[, cols, with = FALSE])
}

#' Query tidy `LMH25 (2023)`-ordered soil horizon records from PostgreSQL `BECMaster`
#'
#' Pushes plot filtering down into `becmaster.humus` and/or `becmaster.mineral`
#' via `WITH matched AS (...)`, normalizes literal character `PlotNumber` and
#' logical `Flag` columns, classifies `HorizonRegime`, and orders horizons per
#' `LMH25 (2023)` (`L/F/H` ordered `UpperDepth DESC`; `Of/Om/Oh` and
#' `A/B/C/R/W` ordered `UpperDepth ASC`).
#'
#' @inheritParams vpro_master_env
#' @param type `"both"` (returns an S3 `vpro_soil` object with `$humus` and
#'   `$mineral` tibbles), `"humus"`, or `"mineral"`.
#' @return A `vpro_soil` object (`type = "both"`) or a tibble (`"humus"` / `"mineral"`).
#' @export
vpro_master_soil <- function(
  pg,
  zones = NULL,
  subzones = NULL,
  project_ids = NULL,
  plots = NULL,
  bbox = NULL,
  type = c("both", "humus", "mineral"),
  limit = NULL,
  allow_full = FALSE
) {
  vpro_assert_pg_conn(pg, require_custodian = FALSE)
  type <- match.arg(type)
  allow_full <- vpro_pg_validate_flag(allow_full, "allow_full")
  limit_int <- vpro_pg_validate_limit(limit, allow_null = TRUE)

  sub <- vpro_pg_subset_where(
    pg = pg,
    zones = zones,
    subzones = subzones,
    project_ids = project_ids,
    plots = plots,
    bbox = bbox,
    table_alias = "e",
    allow_full = allow_full,
    has_limit = !is.null(limit_int)
  )

  where_part <- if (nzchar(sub$where_sql)) paste0(" ", sub$where_sql) else ""
  limit_part <- if (!is.null(limit_int)) sprintf(" LIMIT %d", limit_int) else ""
  cte_sql <- paste0(
    "WITH matched AS (",
    'SELECT e."PlotNumber" FROM becmaster.env AS e',
    where_part,
    ' ORDER BY e."PlotNumber"',
    limit_part,
    ") "
  )

  read_one <- function(pg_tbl, suffix) {
    spec <- vpro_pg_vp08_specs(suffix)
    sel <- paste(vapply(as.character(spec$name), function(f) {
      qf <- vpro_quote_ident(f)
      if (identical(f, "PlotNumber")) {
        'CAST(s."PlotNumber" AS TEXT) AS "PlotNumber"'
      } else {
        paste0("s.", qf, " AS ", qf)
      }
    }, character(1)), collapse = ", ")
    sql <- paste0(
      cte_sql,
      "SELECT ", sel,
      " FROM becmaster.", vpro_quote_ident(pg_tbl), " AS s ",
      'INNER JOIN matched AS m ON s."PlotNumber" = m."PlotNumber"'
    )
    raw <- vpro_pg_query(
      pg,
      sql,
      params = if (length(sub$params) > 0L) sub$params else NULL,
      action = paste0("query becmaster.", pg_tbl)
    )
    raw <- vpro_pg_canonicalize_to_tidy(raw, spec)
    raw$PlotNumber <- as.character(raw$PlotNumber)
    if ("Flag" %in% names(raw)) {
      raw$Flag <- vpro_access_to_logical(raw$Flag)
    }
    if (nrow(raw) == 0L) {
      raw$HorizonRegime <- character()
      return(tibble::as_tibble(raw))
    }
    vpro_order_soil_df(raw)
  }

  if (identical(type, "humus")) {
    return(read_one("humus", "Humus"))
  }
  if (identical(type, "mineral")) {
    return(read_one("mineral", "Mineral"))
  }

  structure(
    list(
      humus = read_one("humus", "Humus"),
      mineral = read_one("mineral", "Mineral")
    ),
    class = "vpro_soil"
  )
}
