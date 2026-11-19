# PostgreSQL BECMaster Tidy Ecological Queries (Env, Veg, Soil) --------------

#' Query tidy plot environment and administration records from PostgreSQL `BECMaster`
#'
#' Executes a parameterized push-down query against `becmaster.env` (optionally
#' left-joining `becmaster.admin`), preserving literal leading-zero `PlotNumber`
#' strings, converting VPro yes/no flags to R `logical`, applying VPro
#' single-precision rounding to `StrataCover*` columns, and deriving `SiteUnit`
#' so the returned tibble matches [vpro_env()] column names and types. When connecting
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

  env_select <- vapply(
    env_fields,
    function(f) {
      qf <- vpro_quote_ident(f)
      if (identical(f, "PlotNumber")) {
        'CAST(e."PlotNumber" AS TEXT) AS "PlotNumber"'
      } else {
        paste0("e.", qf, " AS ", qf)
      }
    },
    character(1)
  )

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
      adm_select <- vapply(
        adm_fields,
        function(f) {
          qf <- vpro_quote_ident(f)
          paste0("a.", qf, " AS ", qf)
        },
        character(1)
      )
    }
  }

  select_parts <- c(env_select[[1L]], su_expr, env_select[-1L], adm_select)
  where_part <- if (nzchar(sub$where_sql)) paste0(" ", sub$where_sql) else ""
  limit_part <- if (!is.null(limit_int)) sprintf(" LIMIT %d", limit_int) else ""
  sql <- paste0(
    "SELECT ",
    paste(select_parts, collapse = ", "),
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
    "SpeciesListComplete",
    "Flag",
    "SV_FloodPlain",
    "UpdatedFromCards",
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
          !is.na(cloud_specs$OldCode) &
          nzchar(cloud_specs$OldCode) &
          !is.na(cloud_specs$Code) &
          nzchar(cloud_specs$Code) &
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
        ifelse(!is.na(non_syn$Codetype) & toupper(trimws(non_syn$Codetype)) == "U", 0L, 1L),
        method = "radix"
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
#' Pushes plot filtering down to PostgreSQL on `becmaster.env` +
#' `becmaster.admin`, extracts matching `becmaster.veg` rows, and runs the exact
#' [vpro_veg()] phytosociological pipeline: VPro single-precision cover rounding,
#' duplicate `(PlotNumber, Species)` `max` deduplication, pre-lump effective
#' stratum synthesis (`TotalA`/`TotalB` fallback), optional taxonomic lumping
#' with VPro's `99%` per-layer cap (`pmin(sum, 99)`), optional `BCPlantTaxonomy
#' v19` synonym resolution (`standards.usys_all_specs` with bundled `VLists.db`
#' fallback), and `total` / `abcd` / `lifeform` / `raw` aggregation.
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
#' @param cover_precedence Stratum cover precedence when combining `A`/`B`
#'   sublayers alongside `TotalA`/`TotalB`: `"strata_totals"` (default, where
#'   populated `TotalA`/`TotalB` overrides sublayers) or `"sublayer_sum"`
#'   (matching BEC diagnostics where `TotalA`/`TotalB` is used only when
#'   sublayers are absent).
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
  cover_precedence = c("strata_totals", "sublayer_sum"),
  limit = NULL,
  allow_full = FALSE
) {
  vpro_assert_pg_conn(pg, require_custodian = FALSE)
  strata <- match.arg(strata)
  combine <- match.arg(combine)
  cover_precedence <- match.arg(cover_precedence)
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

  if (nrow(raw_df) == 0L) {
    return(.vpro_empty_veg_tibble(strata))
  }

  raw_df$PlotNumber <- as.character(raw_df$PlotNumber)
  raw_df$Species <- toupper(trimws(as.character(raw_df$Species)))
  valid_sp <- !is.na(raw_df$Species) & nzchar(raw_df$Species)
  raw_df <- raw_df[valid_sp, , drop = FALSE]
  if (nrow(raw_df) == 0L) {
    return(.vpro_empty_veg_tibble(strata))
  }

  su_vals <- if ("__SiteUnit" %in% names(raw_df)) {
    as.character(raw_df[["__SiteUnit"]])
  } else {
    rep(NA_character_, nrow(raw_df))
  }
  su_keep <- !duplicated(raw_df$PlotNumber)
  su_map <- stats::setNames(su_vals[su_keep], raw_df$PlotNumber[su_keep])

  tax_bundle <- vpro_pg_load_cloud_taxonomy(pg, resolve_synonyms = resolve_synonyms)

  .vpro_fold_veg_records(
    raw_df = raw_df,
    strata = strata,
    combine = combine,
    cover_precedence = cover_precedence,
    lump_tbl = lump_tbl,
    syn_map = tax_bundle$syn_map,
    tax = tax_bundle$tax,
    su_df = NULL,
    su_map = su_map
  )
}

#' Query tidy `LMH25 (2023)`-ordered soil horizon records from PostgreSQL `BECMaster`
#'
#' Pushes plot filtering down into `becmaster.humus` and/or `becmaster.mineral`,
#' normalizes literal character `PlotNumber` and logical `Flag` columns,
#' classifies `HorizonRegime`, and orders horizons per `LMH25 (2023)` (`L/F/H`
#' ordered `UpperDepth DESC`; `Of/Om/Oh` and `A/B/C/R/W` ordered `UpperDepth ASC`).
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
    sel <- paste(
      vapply(
        as.character(spec$name),
        function(f) {
          qf <- vpro_quote_ident(f)
          if (identical(f, "PlotNumber")) {
            'CAST(s."PlotNumber" AS TEXT) AS "PlotNumber"'
          } else {
            paste0("s.", qf, " AS ", qf)
          }
        },
        character(1)
      ),
      collapse = ", "
    )
    sql <- paste0(
      cte_sql,
      "SELECT ",
      sel,
      " FROM becmaster.",
      vpro_quote_ident(pg_tbl),
      " AS s ",
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
    vpro_order_soil_df(raw, kind = suffix)
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
