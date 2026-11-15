# PostgreSQL BECMaster Read, Subset Checkout & Cloud Standards Sync ------------

vpro_pg_clean_tokens <- function(x, arg_name = "filter") {
  if (is.null(x) || length(x) == 0L) {
    return(character())
  }
  if (is.numeric(x) && identical(arg_name, "plots")) {
    cli::cli_abort(
      "{.arg plots} must be a character vector so leading-zero PlotNumbers (e.g. {.val 00337}) are preserved."
    )
  }
  chr <- trimws(as.character(x))
  chr <- chr[!is.na(chr) & nzchar(chr)]
  unique(chr)
}

vpro_pg_validate_limit <- function(limit, allow_null = TRUE) {
  if (is.null(limit)) {
    if (isTRUE(allow_null)) {
      return(NULL)
    }
    cli::cli_abort("{.arg limit} must be a positive integer.")
  }
  if (!is.numeric(limit) || length(limit) != 1L || is.na(limit) ||
      !is.finite(limit) || limit < 1 || limit != trunc(limit)) {
    cli::cli_abort("{.arg limit} must be a single positive integer (>= 1).")
  }
  as.integer(limit)
}

vpro_pg_validate_flag <- function(x, arg_name) {
  if (!is.logical(x) || length(x) != 1L || is.na(x)) {
    cli::cli_abort("{.arg {arg_name}} must be {.code TRUE} or {.code FALSE}.")
  }
  x
}

vpro_pg_postgis_geom_schema <- function(con) {
  sql <- paste(
    "SELECT COALESCE((",
    "  SELECT n.nspname",
    "  FROM pg_extension e",
    "  JOIN pg_namespace n ON n.oid = e.extnamespace",
    "  WHERE e.extname = 'postgis'",
    "  LIMIT 1",
    "), '') AS postgis_schema,",
    "EXISTS (",
    "  SELECT 1 FROM information_schema.columns",
    "  WHERE table_schema = 'becmaster'",
    "    AND table_name = 'env'",
    "    AND column_name = 'geom'",
    ") AS has_geom"
  )
  res <- tryCatch(
    vpro_pg_query(con, sql, params = NULL, action = "inspect becmaster.env PostGIS geometry column"),
    error = function(e) data.frame(postgis_schema = "", has_geom = FALSE)
  )
  if (nrow(res) >= 1L && isTRUE(vpro_access_to_logical(res$has_geom[[1L]])) &&
      !is.na(res$postgis_schema[[1L]]) && nzchar(trimws(as.character(res$postgis_schema[[1L]])))) {
    trimws(as.character(res$postgis_schema[[1L]]))
  } else {
    ""
  }
}

# Internal parameterized WHERE builder for becmaster.env push-down queries
vpro_pg_subset_where <- function(
  con,
  zones = NULL,
  subzones = NULL,
  project_ids = NULL,
  plots = NULL,
  bbox = NULL,
  table_alias = "e",
  allow_full = FALSE,
  has_limit = FALSE
) {
  vpro_assert_pg_conn(con, require_custodian = FALSE)
  allow_full <- vpro_pg_validate_flag(allow_full, "allow_full")
  has_limit <- vpro_pg_validate_flag(has_limit, "has_limit")

  zones_clean <- vpro_pg_clean_tokens(zones, "zones")
  subzones_clean <- vpro_pg_clean_tokens(subzones, "subzones")
  project_ids_clean <- vpro_pg_clean_tokens(project_ids, "project_ids")
  plots_clean <- vpro_pg_clean_tokens(plots, "plots")

  bbox_clean <- NULL
  if (!is.null(bbox)) {
    if (inherits(bbox, "bbox") ||
        (is.numeric(bbox) && !is.null(names(bbox)) &&
         all(c("xmin", "ymin", "xmax", "ymax") %in% names(bbox)))) {
      bbox_clean <- as.double(c(
        bbox[["xmin"]],
        bbox[["ymin"]],
        bbox[["xmax"]],
        bbox[["ymax"]]
      ))
    } else if (is.numeric(bbox) && length(bbox) == 4L) {
      bbox_clean <- as.double(bbox)
    } else {
      cli::cli_abort(
        "{.arg bbox} must be a numeric vector of length 4 {.code c(min_lon, min_lat, max_lon, max_lat)} or an {.cls sf} {.cls bbox} object."
      )
    }
    if (anyNA(bbox_clean) || any(!is.finite(bbox_clean))) {
      cli::cli_abort("{.arg bbox} coordinates must be finite numbers.")
    }
    if (bbox_clean[[1L]] > bbox_clean[[3L]] || bbox_clean[[2L]] > bbox_clean[[4L]]) {
      cli::cli_abort(
        "{.arg bbox} requires {.code min_lon <= max_lon} and {.code min_lat <= max_lat}."
      )
    }
  }

  pfx <- if (!is.null(table_alias) && nzchar(trimws(as.character(table_alias)))) {
    paste0(trimws(as.character(table_alias)), ".")
  } else {
    ""
  }

  clauses <- character()
  params <- list()
  next_param <- function(val) {
    params[[length(params) + 1L]] <<- val
    paste0("$", length(params))
  }

  if (length(zones_clean) > 0L) {
    p <- next_param(vpro_pg_text_array(zones_clean))
    clauses <- c(clauses, paste0(pfx, '"Zone" = ANY(', p, "::text[])"))
  }
  if (length(subzones_clean) > 0L) {
    p <- next_param(vpro_pg_text_array(subzones_clean))
    clauses <- c(clauses, paste0(pfx, '"SubZone" = ANY(', p, "::text[])"))
  }
  if (length(project_ids_clean) > 0L) {
    p <- next_param(vpro_pg_text_array(project_ids_clean))
    clauses <- c(clauses, paste0(pfx, '"ProjectID" = ANY(', p, "::text[])"))
  }
  if (length(plots_clean) > 0L) {
    p <- next_param(vpro_pg_text_array(plots_clean))
    clauses <- c(clauses, paste0(pfx, '"PlotNumber" = ANY(', p, "::text[])"))
  }
  if (!is.null(bbox_clean)) {
    p_min_lon <- next_param(bbox_clean[[1L]])
    p_min_lat <- next_param(bbox_clean[[2L]])
    p_max_lon <- next_param(bbox_clean[[3L]])
    p_max_lat <- next_param(bbox_clean[[4L]])
    postgis_schema <- vpro_pg_postgis_geom_schema(con)
    if (nzchar(postgis_schema)) {
      clauses <- c(
        clauses,
        paste0(
          "(", pfx, "geom && ", vpro_quote_ident(postgis_schema), ".ST_MakeEnvelope(",
          p_min_lon, ", ", p_min_lat, ", ", p_max_lon, ", ", p_max_lat,
          ", 4326) AND ", pfx, '"Longitude" BETWEEN ', p_min_lon, " AND ", p_max_lon,
          " AND ", pfx, '"Latitude" BETWEEN ', p_min_lat, " AND ", p_max_lat, ")"
        )
      )
    } else {
      clauses <- c(
        clauses,
        paste0(
          "(", pfx, '"Longitude" BETWEEN ', p_min_lon, " AND ", p_max_lon,
          " AND ", pfx, '"Latitude" BETWEEN ', p_min_lat, " AND ", p_max_lat, ")"
        )
      )
    }
  }

  if (length(clauses) == 0L && !isTRUE(has_limit) && !isTRUE(allow_full)) {
    cli::cli_abort(c(
      "At least one subset filter is required before querying {.code becmaster}.",
      "i" = "Supply {.arg zones}, {.arg subzones}, {.arg project_ids}, {.arg plots}, {.arg bbox}, a positive {.arg limit}, or set {.code allow_full = TRUE}."
    ))
  }

  list(
    where_sql = if (length(clauses) > 0L) paste0("WHERE ", paste(clauses, collapse = " AND ")) else "",
    clauses = clauses,
    params = params,
    filters = list(
      zones = zones_clean,
      subzones = subzones_clean,
      project_ids = project_ids_clean,
      plots = plots_clean,
      bbox = bbox_clean
    )
  )
}

#' Query tidy plot environment and administration records from PostgreSQL `BECMaster`
#'
#' Executes a parameterized push-down query against `becmaster.env` (optionally
#' left-joining `becmaster.admin`), preserving literal leading-zero `PlotNumber`
#' strings, converting Access `-1/0` booleans to R `logical`, narrowing
#' `StrataCover*` columns to IEEE-754 `float32`, and deriving `SiteUnit` so the
#' returned tibble matches [vpro_env()] column names and types.
#'
#' @param con A `vpro_pg_conn` handle created by `vpro_master_connect()`.
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
  con,
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
  vpro_assert_pg_conn(con, require_custodian = FALSE)
  include_admin <- vpro_pg_validate_flag(include_admin, "include_admin")
  allow_full <- vpro_pg_validate_flag(allow_full, "allow_full")
  limit_int <- vpro_pg_validate_limit(limit, allow_null = TRUE)

  sub <- vpro_pg_subset_where(
    con = con,
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
    con,
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

  front <- intersect(c("PlotNumber", "SiteUnit"), names(df))
  df <- df[, c(front, setdiff(names(df), front)), drop = FALSE]
  rownames(df) <- NULL
  tibble::as_tibble(df)
}

vpro_pg_load_cloud_taxonomy <- function(con, resolve_synonyms = TRUE) {
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
    vpro_pg_query(con, sql, params = NULL, action = "query standards.usys_all_specs"),
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
  con,
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
  vpro_assert_pg_conn(con, require_custodian = FALSE)
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
  lump_tbl <- vpro_lump_map(con = NULL, lump = lump)

  sub <- vpro_pg_subset_where(
    con = con,
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
    con,
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

  tax_bundle <- vpro_pg_load_cloud_taxonomy(con, resolve_synonyms = resolve_synonyms)
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
  con,
  zones = NULL,
  subzones = NULL,
  project_ids = NULL,
  plots = NULL,
  bbox = NULL,
  type = c("both", "humus", "mineral"),
  limit = NULL,
  allow_full = FALSE
) {
  vpro_assert_pg_conn(con, require_custodian = FALSE)
  type <- match.arg(type)
  allow_full <- vpro_pg_validate_flag(allow_full, "allow_full")
  limit_int <- vpro_pg_validate_limit(limit, allow_null = TRUE)

  sub <- vpro_pg_subset_where(
    con = con,
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
      con,
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

#' Query hash-chained audit records from PostgreSQL `becmaster.audit`
#'
#' Retrieves audit trail entries filtered by `plots`, `zones` / `subzones` /
#' `project_ids` (via `becmaster.env`), and/or `merge_tx_id`, ordered by
#' `audit_seq DESC`. Optionally verifies the cryptographic SHA-256 hash chain
#' via [vpro_master_verify_audit()] and attaches the result as
#' `attr(result, "chain_verification")`.
#'
#' @param con A `vpro_pg_conn` handle.
#' @param plots Optional character vector of `PlotNumber` values.
#' @param zones Optional character vector of BEC zone codes.
#' @param subzones Optional character vector of BEC subzone/variant codes.
#' @param project_ids Optional character vector of `ProjectID` values.
#' @param merge_tx_id Optional merge transaction UUID(s).
#' @param limit Optional positive integer row limit (defaults to `1000L`, or
#'   `NULL` for all matching rows).
#' @param verify_chain Logical; if `TRUE`, runs [vpro_master_verify_audit()] and
#'   attaches its report to `attr(result, "chain_verification")`.
#' @return A tibble of `becmaster.audit` records.
#' @export
vpro_master_audit <- function(
  con,
  plots = NULL,
  zones = NULL,
  subzones = NULL,
  project_ids = NULL,
  merge_tx_id = NULL,
  limit = 1000L,
  verify_chain = FALSE
) {
  vpro_assert_pg_conn(con, require_custodian = FALSE)
  verify_chain <- vpro_pg_validate_flag(verify_chain, "verify_chain")
  limit_int <- vpro_pg_validate_limit(limit, allow_null = TRUE)

  plots_clean <- vpro_pg_clean_tokens(plots, "plots")
  zones_clean <- vpro_pg_clean_tokens(zones, "zones")
  subzones_clean <- vpro_pg_clean_tokens(subzones, "subzones")
  project_ids_clean <- vpro_pg_clean_tokens(project_ids, "project_ids")
  merge_tx_clean <- vpro_pg_clean_tokens(merge_tx_id, "merge_tx_id")

  clauses <- character()
  params <- list()
  next_param <- function(val) {
    params[[length(params) + 1L]] <<- val
    paste0("$", length(params))
  }

  if (length(plots_clean) > 0L) {
    p <- next_param(vpro_pg_text_array(plots_clean))
    clauses <- c(clauses, paste0('a."PlotNumber" = ANY(', p, "::text[])"))
  }

  env_sub <- character()
  if (length(zones_clean) > 0L) {
    p <- next_param(vpro_pg_text_array(zones_clean))
    env_sub <- c(env_sub, paste0('e."Zone" = ANY(', p, "::text[])"))
  }
  if (length(subzones_clean) > 0L) {
    p <- next_param(vpro_pg_text_array(subzones_clean))
    env_sub <- c(env_sub, paste0('e."SubZone" = ANY(', p, "::text[])"))
  }
  if (length(project_ids_clean) > 0L) {
    p <- next_param(vpro_pg_text_array(project_ids_clean))
    env_sub <- c(env_sub, paste0('e."ProjectID" = ANY(', p, "::text[])"))
  }
  if (length(env_sub) > 0L) {
    clauses <- c(
      clauses,
      paste0(
        'EXISTS (SELECT 1 FROM becmaster.env AS e WHERE e."PlotNumber" = a."PlotNumber" AND ',
        paste(env_sub, collapse = " AND "),
        ")"
      )
    )
  }

  if (length(merge_tx_clean) > 0L) {
    p <- next_param(vpro_pg_text_array(merge_tx_clean))
    clauses <- c(clauses, paste0("a.merge_tx_id::text = ANY(", p, "::text[])"))
  }

  audit_spec <- vpro_pg_vp08_specs("Audit")
  vp08_sel <- paste(vapply(as.character(audit_spec$name), function(f) {
    qf <- vpro_quote_ident(f)
    if (identical(f, "PlotNumber")) {
      'CAST(a."PlotNumber" AS TEXT) AS "PlotNumber"'
    } else {
      paste0("a.", qf, " AS ", qf)
    }
  }, character(1)), collapse = ", ")

  where_part <- if (length(clauses) > 0L) paste0(" WHERE ", paste(clauses, collapse = " AND ")) else ""
  limit_part <- if (!is.null(limit_int)) sprintf(" LIMIT %d", limit_int) else ""
  sql <- paste0(
    "SELECT a.audit_seq, ", vp08_sel,
    ", CAST(a.merge_tx_id AS TEXT) AS merge_tx_id, a.prev_hash, a.row_hash",
    " FROM becmaster.audit AS a",
    where_part,
    " ORDER BY a.audit_seq DESC",
    limit_part
  )

  df <- vpro_pg_query(
    con,
    sql,
    params = if (length(params) > 0L) params else NULL,
    action = "query becmaster.audit"
  )

  canon <- vpro_pg_canonicalize_to_tidy(
    df[, intersect(audit_spec$name, names(df)), drop = FALSE],
    audit_spec
  )
  for (nm in names(canon)) {
    df[[nm]] <- canon[[nm]]
  }
  df$PlotNumber <- as.character(df$PlotNumber)
  for (bc in intersect(c("Restore", "Flag"), names(df))) {
    df[[bc]] <- vpro_access_to_logical(df[[bc]])
  }
  if ("merge_tx_id" %in% names(df)) df$merge_tx_id <- as.character(df$merge_tx_id)
  if ("prev_hash" %in% names(df)) df$prev_hash <- as.character(df$prev_hash)
  if ("row_hash" %in% names(df)) df$row_hash <- as.character(df$row_hash)

  tbl <- tibble::as_tibble(df)
  if (isTRUE(verify_chain)) {
    v_lim <- if (is.null(limit_int)) 1000L else limit_int
    attr(tbl, "chain_verification") <- vpro_master_verify_audit(con, limit = v_lim)
  }
  tbl
}

vpro_same_hash <- function(a, b) {
  if (length(a) != 1L || length(b) != 1L || is.na(a[[1L]]) || is.na(b[[1L]])) {
    return(FALSE)
  }
  tolower(trimws(unname(as.character(a[[1L]])))) ==
    tolower(trimws(unname(as.character(b[[1L]]))))
}

#' Verify the cryptographic SHA-256 hash chain on `becmaster.audit`
#'
#' Recomputes `row_hash` across the most recent `limit` rows of `becmaster.audit`
#' in ascending `audit_seq` order using `vpro_compute_audit_row_hash()`,
#' matching `VerifyBECMasterAuditChain` in `vpro_wails`
#' (`internal/cloudsync/custodian_merge.go`). Anchors the window's first row
#' against `.vpro_genesis_audit_hash` when starting at the beginning of the
#' ledger, or against the immediate predecessor row's `row_hash` when verifying
#' a bounded tail window.
#'
#' @param con A `vpro_pg_conn` handle.
#' @param limit Positive integer number of most-recent audit rows to verify
#'   (defaults to `1000L`).
#' @return A list with `verified_rows` (`integer`), `valid` (`logical`),
#'   `partial_window` (`logical`), `tail_hash` (`character`), and `detail`
#'   (`character`).
#' @export
vpro_master_verify_audit <- function(con, limit = 1000L) {
  vpro_assert_pg_conn(con, require_custodian = FALSE)
  limit_int <- if (is.null(limit)) 1000L else vpro_pg_validate_limit(limit, allow_null = FALSE)

  audit_spec <- vpro_pg_vp08_specs("Audit")
  audit_cols <- as.character(audit_spec$name)
  quoted_csv <- paste(vapply(audit_cols, vpro_quote_ident, character(1)), collapse = ", ")

  sql <- paste0(
    "SELECT * FROM (",
    "  SELECT audit_seq::text AS audit_seq_txt, audit_seq, ", quoted_csv, ", ",
    '         "ID"::text AS "__id_txt__", ',
    "         COALESCE(merge_tx_id::text, '') AS merge_tx_id, prev_hash, row_hash",
    "  FROM becmaster.audit",
    "  ORDER BY audit_seq DESC",
    "  LIMIT $1",
    ") AS sub ",
    "ORDER BY audit_seq ASC"
  )

  df <- vpro_pg_query(
    con,
    sql,
    params = list(as.integer(limit_int)),
    action = "verify becmaster.audit hash chain"
  )

  if (nrow(df) == 0L) {
    return(list(
      verified_rows = 0L,
      valid = TRUE,
      partial_window = FALSE,
      tail_hash = .vpro_genesis_audit_hash,
      detail = "becmaster.audit is empty (anchored at genesis hash)."
    ))
  }

  canon <- vpro_pg_canonicalize_to_sqlite(df[, audit_cols, drop = FALSE], audit_spec)
  for (col in setdiff(audit_cols, c("Restore", "Flag", "ID"))) {
    canon[[col]] <- as.character(canon[[col]])
  }
  for (bc in intersect(c("Restore", "Flag"), names(canon))) {
    canon[[bc]] <- vpro_logical_to_access(canon[[bc]])
  }
  if ("ID" %in% names(canon) && "__id_txt__" %in% names(df)) {
    id_chr <- as.character(df[["__id_txt__"]])
    id_dbl <- suppressWarnings(as.double(id_chr))
    if (all(is.na(id_dbl) | abs(id_dbl) <= .Machine$integer.max)) {
      canon$ID <- suppressWarnings(as.integer(id_chr))
    } else {
      canon$ID <- id_dbl
    }
  }

  count <- 0L
  first_seq_txt <- unname(as.character(df$audit_seq_txt[[1L]]))
  first_prev_hash <- tolower(trimws(unname(as.character(df$prev_hash[[1L]]))))
  expected_prev <- ""
  tail_hash <- tolower(trimws(unname(as.character(.vpro_genesis_audit_hash))))

  for (i in seq_len(nrow(df))) {
    seq_txt <- unname(as.character(df$audit_seq_txt[[i]]))
    merge_tx <- ifelse(is.na(df$merge_tx_id[[i]]), "", unname(as.character(df$merge_tx_id[[i]])))
    prev_hash <- ifelse(is.na(df$prev_hash[[i]]), "", tolower(trimws(unname(as.character(df$prev_hash[[i]])))))
    row_hash <- ifelse(is.na(df$row_hash[[i]]), "", tolower(trimws(unname(as.character(df$row_hash[[i]])))))

    if (i > 1L && !vpro_same_hash(prev_hash, expected_prev)) {
      return(list(
        verified_rows = as.integer(count),
        valid = FALSE,
        partial_window = FALSE,
        tail_hash = tail_hash,
        detail = paste0(
          "Audit hash chain broken at seq=", seq_txt,
          ": prev_hash=", prev_hash, " != expected=", expected_prev
        )
      ))
    }

    vp08_vals <- lapply(audit_cols, function(cn) canon[[cn]][[i]])
    computed <- tolower(trimws(unname(as.character(
      vpro_compute_audit_row_hash(prev_hash, merge_tx, vp08_vals)
    ))))
    if (!vpro_same_hash(computed, row_hash)) {
      return(list(
        verified_rows = as.integer(count),
        valid = FALSE,
        partial_window = FALSE,
        tail_hash = tail_hash,
        detail = paste0(
          "Audit row_hash tampered at seq=", seq_txt,
          ": computed=", computed, " != stored=", row_hash
        )
      ))
    }

    expected_prev <- row_hash
    tail_hash <- row_hash
    count <- count + 1L
  }

  pred_df <- vpro_pg_query(
    con,
    "SELECT row_hash FROM becmaster.audit WHERE audit_seq < $1::bigint ORDER BY audit_seq DESC LIMIT 1",
    params = list(first_seq_txt),
    action = "verify becmaster.audit predecessor anchor"
  )

  partial_window <- FALSE
  if (nrow(pred_df) == 0L) {
    if (!vpro_same_hash(first_prev_hash, .vpro_genesis_audit_hash)) {
      return(list(
        verified_rows = as.integer(count),
        valid = FALSE,
        partial_window = FALSE,
        tail_hash = tail_hash,
        detail = paste0(
          "Initial audit row seq=", first_seq_txt,
          " does not anchor to genesis hash (deleted prefix detected)."
        )
      ))
    }
  } else {
    partial_window <- TRUE
    pred_hash <- tolower(trimws(unname(as.character(pred_df$row_hash[[1L]]))))
    if (!vpro_same_hash(first_prev_hash, pred_hash)) {
      return(list(
        verified_rows = as.integer(count),
        valid = FALSE,
        partial_window = TRUE,
        tail_hash = tail_hash,
        detail = paste0(
          "Audit window boundary broken at seq=", first_seq_txt,
          ": prev_hash=", first_prev_hash, " != predecessor=", pred_hash
        )
      ))
    }
  }

  list(
    verified_rows = as.integer(count),
    valid = TRUE,
    partial_window = partial_window,
    tail_hash = tail_hash,
    detail = sprintf(
      "Verified %d audit row(s)%s.",
      count,
      if (partial_window) " (partial window anchored to predecessor)" else " from genesis"
    )
  )
}

#' Read provincial BEC and taxonomy standards tables from PostgreSQL `standards.*`
#'
#' Queries either release metadata (`table = "releases"`, omitting the binary
#' `vlists_gzip` payload and reporting `vlists_gzip_bytes`) or one of the six
#' relational standards catalogues (`usys_all_specs`, `usys_table_of_lists`,
#' `bec_site_series`, `master_site_unit_list`, `usys_zone_list`,
#' `project_metadata`) ordered by `row_seq`.
#'
#' @param con A `vpro_pg_conn` handle.
#' @param table Standards table to read: `"releases"`, `"usys_all_specs"`,
#'   `"usys_table_of_lists"`, `"bec_site_series"`, `"master_site_unit_list"`,
#'   `"usys_zone_list"`, or `"project_metadata"`.
#' @return A tibble of standards release metadata or catalogue records.
#' @export
vpro_master_standards <- function(
  con,
  table = c(
    "releases",
    "usys_all_specs",
    "usys_table_of_lists",
    "bec_site_series",
    "master_site_unit_list",
    "usys_zone_list",
    "project_metadata"
  )
) {
  vpro_assert_pg_conn(con, require_custodian = FALSE)
  table <- match.arg(table)

  if (identical(table, "releases")) {
    sql <- paste(
      "SELECT release_id, published_at, published_by, bec_version, taxonomy_version,",
      "       vlists_sha256, bec_db_sha256, vmetadata_sha256, notes, is_current,",
      "       octet_length(vlists_gzip) AS vlists_gzip_bytes",
      "FROM standards.library_releases",
      "ORDER BY published_at DESC, release_id DESC"
    )
    df <- vpro_pg_query(con, sql, params = NULL, action = "query standards.library_releases")
    for (tc in intersect(c(
      "release_id", "published_by", "bec_version", "taxonomy_version",
      "vlists_sha256", "bec_db_sha256", "vmetadata_sha256", "notes"
    ), names(df))) {
      df[[tc]] <- as.character(df[[tc]])
    }
    if ("is_current" %in% names(df)) {
      df$is_current <- vpro_access_to_logical(df$is_current)
    }
    if ("vlists_gzip_bytes" %in% names(df)) {
      df$vlists_gzip_bytes <- suppressWarnings(as.integer(as.character(df$vlists_gzip_bytes)))
    }
    return(tibble::as_tibble(df))
  }

  spec <- vpro_pg_standards_specs(table)
  col_names <- as.character(spec$name)
  quoted_cols <- paste(vapply(col_names, vpro_quote_ident, character(1)), collapse = ", ")
  sql <- paste0(
    "SELECT ", quoted_cols,
    " FROM standards.", vpro_quote_ident(table),
    " ORDER BY row_seq"
  )
  df <- vpro_pg_query(con, sql, params = NULL, action = paste0("query standards.", table))
  df <- vpro_pg_canonicalize_to_tidy(df, spec)

  text_cols <- as.character(spec$name[!is.na(spec$pg_type) & toupper(spec$pg_type) == "TEXT"])
  for (tc in intersect(text_cols, names(df))) {
    df[[tc]] <- as.character(df[[tc]])
  }
  bool_cols <- as.character(spec$name[
    (!is.na(spec$is_bool) & spec$is_bool) |
      (!is.na(spec$sqlite_type) & toupper(spec$sqlite_type) == "BOOLEAN")
  ])
  for (bc in intersect(bool_cols, names(df))) {
    df[[bc]] <- vpro_access_to_logical(df[[bc]])
  }
  if ("Lifeform" %in% names(df)) {
    df$Lifeform <- suppressWarnings(as.integer(as.character(df$Lifeform)))
  }

  tibble::as_tibble(df)
}

vpro_validate_splinter_project_name <- function(project_name, allow_reserved_name = FALSE) {
  if (!is.character(project_name) || length(project_name) != 1L || is.na(project_name) ||
      !validUTF8(project_name) || trimws(project_name) != project_name || !nzchar(project_name)) {
    cli::cli_abort(
      "{.arg project_name} must be a non-empty string without leading or trailing whitespace."
    )
  }
  project_name <- tryCatch(
    vpro_project_name(project_name),
    error = function(e) {
      cli::cli_abort(
        "{.arg project_name} must start with an ASCII letter and contain only ASCII letters, digits, or underscores (max 31 chars).",
        parent = e
      )
    }
  )
  if (!isTRUE(allow_reserved_name)) {
    low <- tolower(project_name)
    if (low %in% c("none", "sample") || grepl("master", low, fixed = TRUE)) {
      cli::cli_abort(
        "Target {.arg project_name} {.val {project_name}} is reserved ({.val None}, {.val Sample}, and names containing {.val master} are not permitted)."
      )
    }
  }
  project_name
}

vpro_assign_unique_ids <- function(ids_raw, used_env, start_id = 100000000, require_positive = FALSE) {
  n <- length(ids_raw)
  if (n == 0L) {
    return(integer())
  }
  chr <- as.character(ids_raw)
  nums <- suppressWarnings(as.double(chr))
  min_allowed <- if (isTRUE(require_positive)) 1 else 0
  next_id <- as.double(start_id)
  out <- numeric(n)

  for (i in seq_len(n)) {
    v <- nums[[i]]
    valid <- !is.na(v) && is.finite(v) && v == trunc(v) && v >= min_allowed
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

  if (all(abs(out) <= .Machine$integer.max)) {
    as.integer(out)
  } else {
    out
  }
}

vpro_serialize_subset_filter_json <- function(filters, limit_int = NULL, allow_full = FALSE) {
  payload <- stats::setNames(list(), character())
  if (length(filters$zones) > 0L) payload$zones <- as.character(filters$zones)
  if (length(filters$subzones) > 0L) payload$subzones <- as.character(filters$subzones)
  if (length(filters$project_ids) > 0L) payload$projectIds <- as.character(filters$project_ids)
  if (length(filters$plots) > 0L) payload$plotNumbers <- as.character(filters$plots)
  if (!is.null(filters$bbox)) payload$bbox <- as.numeric(filters$bbox)
  if (!is.null(limit_int)) payload$limit <- jsonlite::unbox(as.integer(limit_int))
  if (isTRUE(allow_full)) payload$allowFullCheckout <- jsonlite::unbox(TRUE)
  as.character(jsonlite::toJSON(payload, auto_unbox = FALSE))
}

vpro_master_pull_impl <- function(
  con,
  dest_path,
  project_name,
  zones = NULL,
  subzones = NULL,
  project_ids = NULL,
  plots = NULL,
  bbox = NULL,
  overwrite = FALSE,
  limit = NULL,
  allow_full = FALSE,
  log_download = TRUE,
  allow_reserved_name = FALSE,
  unit_col = NULL,
  unit_col_fallback = TRUE
) {
  vpro_assert_pg_conn(con, require_custodian = FALSE)
  overwrite <- vpro_pg_validate_flag(overwrite, "overwrite")
  allow_full <- vpro_pg_validate_flag(allow_full, "allow_full")
  log_download <- vpro_pg_validate_flag(log_download, "log_download")
  limit_int <- vpro_pg_validate_limit(limit, allow_null = TRUE)

  project_name <- vpro_validate_splinter_project_name(
    project_name,
    allow_reserved_name = allow_reserved_name
  )

  if (!is.character(dest_path) || length(dest_path) != 1L || is.na(dest_path) || !nzchar(trimws(dest_path))) {
    cli::cli_abort("{.arg dest_path} must be a single non-empty file path.")
  }
  dest_clean <- trimws(dest_path)
  if (!nzchar(tools::file_ext(dest_clean))) {
    dest_clean <- paste0(dest_clean, ".db")
  }
  dest_resolved <- vpro_abs_path(dest_clean)

  if (vpro_is_protected_support_db(dest_resolved) || vpro_is_bundled_package_path(dest_resolved)) {
    cli::cli_abort(
      "Refusing to write subset database onto protected system or bundled path: {.path {dest_resolved}}."
    )
  }
  if (file.exists(paste0(dest_resolved, "-wal")) || file.exists(paste0(dest_resolved, "-shm"))) {
    cli::cli_abort(
      "Refusing to write to {.path {dest_resolved}} while active SQLite WAL/SHM sidecar files exist."
    )
  }
  if (file.exists(dest_resolved)) {
    if (dir.exists(dest_resolved)) {
      cli::cli_abort("{.arg dest_path} points to an existing directory: {.path {dest_resolved}}.")
    }
    if (!isTRUE(overwrite)) {
      cli::cli_abort(
        "Destination SQLite file already exists (pass {.code overwrite = TRUE} to replace): {.path {dest_resolved}}."
      )
    }
  }

  sub <- vpro_pg_subset_where(
    con = con,
    zones = zones,
    subzones = subzones,
    project_ids = project_ids,
    plots = plots,
    bbox = bbox,
    table_alias = "e",
    allow_full = allow_full,
    has_limit = !is.null(limit_int)
  )

  tx_open <- FALSE
  on.exit({
    if (tx_open) {
      tryCatch(
        vpro_pg_execute(con, "ROLLBACK", params = NULL, action = "rollback subset snapshot transaction"),
        error = function(e) NULL
      )
    }
  }, add = TRUE)

  vpro_pg_exec_safe(
    function() vpro_pg_begin_isolated_tx(con$conn, "BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY", "vpro_master_pull"),
    action = "begin subset snapshot transaction"
  )
  tx_open <- TRUE

  where_part <- if (nzchar(sub$where_sql)) paste0(" ", sub$where_sql) else ""
  limit_part <- if (!is.null(limit_int)) sprintf(" LIMIT %d", limit_int) else ""
  plot_sql <- paste0(
    'SELECT CAST(e."PlotNumber" AS TEXT) AS "PlotNumber" FROM becmaster.env AS e',
    where_part,
    ' ORDER BY e."PlotNumber"',
    limit_part
  )
  matched_df <- vpro_pg_query(
    con,
    plot_sql,
    params = if (length(sub$params) > 0L) sub$params else NULL,
    action = "query matching BECMaster plots"
  )
  plot_list <- as.character(matched_df$PlotNumber)
  plot_list <- plot_list[!is.na(plot_list) & nzchar(plot_list)]
  if (length(plot_list) == 0L) {
    cli::cli_abort("Subset filter matched 0 plots in {.code becmaster.env}.")
  }

  dir.create(dirname(dest_resolved), recursive = TRUE, showWarnings = FALSE)
  tmp_db <- tempfile(pattern = ".vpro-pgsubset-", tmpdir = dirname(dest_resolved), fileext = ".db")
  published <- FALSE
  on.exit({
    if (!published) {
      unlink(tmp_db, force = TRUE)
    }
    unlink(c(paste0(tmp_db, "-wal"), paste0(tmp_db, "-shm")), force = TRUE)
  }, add = TRUE)

  sq_con <- DBI::dbConnect(RSQLite::SQLite(), tmp_db)
  on.exit(if (DBI::dbIsValid(sq_con)) DBI::dbDisconnect(sq_con), add = TRUE)
  DBI::dbExecute(sq_con, "PRAGMA foreign_keys = OFF")
  DBI::dbExecute(sq_con, "PRAGMA journal_mode = DELETE")
  DBI::dbExecute(sq_con, "PRAGMA synchronous = NORMAL")

  veg_n <- 0L
  humus_n <- 0L
  mineral_n <- 0L
  other_n <- 0L
  meta_n <- 0L
  su_n <- 0L

  plot_chunks <- split(plot_list, ceiling(seq_along(plot_list) / 20000L))

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

    stream_plot_table <- function(pg_tbl, plot_col, suffix) {
      spec <- vpro_pg_vp08_specs(suffix)
      col_names <- as.character(spec$name)
      quoted_cols <- paste(vapply(col_names, vpro_quote_ident, character(1)), collapse = ", ")
      dst_tbl <- paste0(project_name, "_", suffix)
      dst_fields <- DBI::dbListFields(sq_con, dst_tbl)
      enforce_unique_id <- suffix %in% c("Veg", "Humus", "Mineral", "Other")
      used_ids <- new.env(hash = TRUE, parent = emptyenv())
      total_rows <- 0L

      ord_clause <- if (identical(suffix, "Audit")) {
        " ORDER BY audit_seq ASC"
      } else if ("ID" %in% col_names) {
        paste0(" ORDER BY ", vpro_quote_ident(plot_col), ', "ID"')
      } else {
        paste0(" ORDER BY ", vpro_quote_ident(plot_col))
      }

      for (ch in plot_chunks) {
        q <- paste0(
          "SELECT ", quoted_cols,
          " FROM becmaster.", vpro_quote_ident(pg_tbl),
          " WHERE ", vpro_quote_ident(plot_col), " = ANY($1::text[])",
          ord_clause
        )
        part <- vpro_pg_query(
          con,
          q,
          params = list(vpro_pg_text_array(ch)),
          action = paste0("stream becmaster.", pg_tbl)
        )
        if (nrow(part) == 0L) {
          next
        }
        part <- vpro_pg_canonicalize_to_sqlite(part, spec)
        if (plot_col %in% names(part)) {
          part[[plot_col]] <- as.character(part[[plot_col]])
        }
        bool_cols <- as.character(spec$name[!is.na(spec$is_bool) & spec$is_bool])
        for (bc in intersect(bool_cols, names(part))) {
          part[[bc]] <- vpro_logical_to_access(part[[bc]])
        }
        if (identical(suffix, "Veg") && "Species" %in% names(part)) {
          part$Species <- as.character(part$Species)
          part$Species[is.na(part$Species)] <- ""
        }
        if (identical(suffix, "Audit") && "Project" %in% names(part)) {
          part$Project <- rep(project_name, nrow(part))
        }
        if (enforce_unique_id && "ID" %in% names(part)) {
          part$ID <- vpro_assign_unique_ids(
            part$ID,
            used_env = used_ids,
            start_id = 100000000,
            require_positive = FALSE
          )
        }
        keep_cols <- intersect(dst_fields, names(part))
        DBI::dbAppendTable(sq_con, dst_tbl, part[, keep_cols, drop = FALSE])
        total_rows <- total_rows + nrow(part)
      }
      total_rows
    }

    stream_plot_table("env", "PlotNumber", "Env")
    stream_plot_table("admin", "Plot", "Admin")
    veg_n <- stream_plot_table("veg", "PlotNumber", "Veg")
    humus_n <- stream_plot_table("humus", "PlotNumber", "Humus")
    mineral_n <- stream_plot_table("mineral", "PlotNumber", "Mineral")
    other_n <- stream_plot_table("other", "PlotNumber", "Other")
    stream_plot_table("audit", "PlotNumber", "Audit")

    DBI::dbExecute(
      sq_con,
      paste0("UPDATE ", vpro_quote_ident(paste0(project_name, "_Audit")), ' SET "Project" = ?'),
      params = list(project_name)
    )

    # Populate <Project>_Metadata for referenced ProjectIDs (with 1-row fallback)
    ref_pids <- DBI::dbGetQuery(
      sq_con,
      paste0(
        'SELECT DISTINCT "ProjectID" FROM ',
        vpro_quote_ident(paste0(project_name, "_Env")),
        ' WHERE typeof("ProjectID") = \'text\' AND TRIM("ProjectID") <> \'\''
      )
    )$ProjectID
    ref_pids <- vpro_pg_clean_tokens(ref_pids, "project_ids")

    meta_dst <- paste0(project_name, "_Metadata")
    if (length(ref_pids) > 0L) {
      meta_spec <- vpro_pg_vp08_specs("Metadata")
      meta_cols <- as.character(meta_spec$name)
      meta_csv <- paste(vapply(meta_cols, vpro_quote_ident, character(1)), collapse = ", ")
      meta_df <- vpro_pg_query(
        con,
        paste0(
          "SELECT ", meta_csv,
          ' FROM becmaster.metadata WHERE "ProjectID" = ANY($1::text[]) ORDER BY "ProjectID"'
        ),
        params = list(vpro_pg_text_array(ref_pids)),
        action = "stream becmaster.metadata"
      )
      if (nrow(meta_df) > 0L) {
        meta_df <- vpro_pg_canonicalize_to_sqlite(meta_df, meta_spec)
        if ("ID" %in% names(meta_df)) {
          used_meta_ids <- new.env(hash = TRUE, parent = emptyenv())
          meta_df$ID <- vpro_assign_unique_ids(
            meta_df$ID,
            used_env = used_meta_ids,
            start_id = 1,
            require_positive = TRUE
          )
        }
        meta_fields <- DBI::dbListFields(sq_con, meta_dst)
        keep_m <- intersect(meta_fields, names(meta_df))
        DBI::dbAppendTable(sq_con, meta_dst, meta_df[, keep_m, drop = FALSE])
        meta_n <- nrow(meta_df)
      }
    }

    if (meta_n == 0L) {
      DBI::dbExecute(
        sq_con,
        paste0(
          "INSERT INTO ", vpro_quote_ident(meta_dst),
          ' ("ProjectID", "ProjectTitle", "ID") VALUES (?, ?, 1)'
        ),
        params = list(project_name, paste0(project_name, " BECMaster Subset"))
      )
      meta_n <- 1L
    }

    # Seed __VPRO_ChildIdentity for all child tables
    for (sfx in c("Veg", "Humus", "Mineral", "Other", "Metadata", "Audit")) {
      full_tbl <- paste0(project_name, "_", sfx)
      q_full <- vpro_quote_ident(full_tbl)
      DBI::dbExecute(
        sq_con,
        paste0(
          'INSERT OR IGNORE INTO "__VPRO_ChildIdentity" ("ChildTable", "ID") ',
          "SELECT ?, \"ID\" FROM ", q_full,
          ' WHERE typeof("ID") = \'integer\' AND "ID" >= 0'
        ),
        params = list(q_full)
      )
    }

    # Build <Project>_SU so classification, matrix, and diagnostics work immediately
    su_tbl <- paste0(project_name, "_SU")
    q_su <- vpro_quote_ident(su_tbl)
    q_env <- vpro_quote_ident(paste0(project_name, "_Env"))
    q_adm <- vpro_quote_ident(paste0(project_name, "_Admin"))

    DBI::dbExecute(
      sq_con,
      paste0("CREATE TABLE ", q_su, ' ("PlotNumber" TEXT, "SiteUnit" TEXT)')
    )

    coalesced_su_expr <- paste(
      "COALESCE(",
      "  NULLIF(TRIM(CAST(a.\"BECSiteUnit\" AS TEXT)), ''),",
      "  NULLIF(TRIM(CAST(a.\"UserSiteUnit\" AS TEXT)), ''),",
      "  CASE",
      "    WHEN e.\"Zone\" IS NOT NULL AND TRIM(CAST(e.\"Zone\" AS TEXT)) <> ''",
      "     AND e.\"SiteSeries\" IS NOT NULL AND TRIM(CAST(e.\"SiteSeries\" AS TEXT)) <> ''",
      "    THEN TRIM(CAST(e.\"Zone\" AS TEXT)) || COALESCE(TRIM(CAST(e.\"SubZone\" AS TEXT)), '') || '/' || TRIM(CAST(e.\"SiteSeries\" AS TEXT))",
      "    ELSE NULL",
      "  END",
      ")"
    )

    su_expr <- if (is.null(unit_col)) {
      coalesced_su_expr
    } else if (identical(unit_col, "BECSiteUnit")) {
      'NULLIF(TRIM(CAST(a."BECSiteUnit" AS TEXT)), \'\')'
    } else if (identical(unit_col, "UserSiteUnit")) {
      'NULLIF(TRIM(CAST(a."UserSiteUnit" AS TEXT)), \'\')'
    } else if (identical(unit_col, "SiteSeries")) {
      paste(
        "CASE",
        "  WHEN e.\"Zone\" IS NOT NULL AND TRIM(CAST(e.\"Zone\" AS TEXT)) <> ''",
        "   AND e.\"SiteSeries\" IS NOT NULL AND TRIM(CAST(e.\"SiteSeries\" AS TEXT)) <> ''",
        "  THEN TRIM(CAST(e.\"Zone\" AS TEXT)) || COALESCE(TRIM(CAST(e.\"SubZone\" AS TEXT)), '') || '/' || TRIM(CAST(e.\"SiteSeries\" AS TEXT))",
        "  WHEN e.\"SiteSeries\" IS NOT NULL AND TRIM(CAST(e.\"SiteSeries\" AS TEXT)) <> ''",
        "  THEN TRIM(CAST(e.\"SiteSeries\" AS TEXT))",
        "  ELSE NULL",
        "END"
      )
    } else {
      coalesced_su_expr
    }

    insert_su_with_expr <- function(expr_sql) {
      DBI::dbExecute(
        sq_con,
        paste0(
          "INSERT INTO ", q_su, ' ("PlotNumber", "SiteUnit") ',
          "SELECT PlotNumber, SiteUnit FROM (",
          '  SELECT CAST(e."PlotNumber" AS TEXT) AS PlotNumber, ',
          expr_sql, " AS SiteUnit ",
          "  FROM ", q_env, " AS e ",
          "  LEFT JOIN ", q_adm, ' AS a ON e."PlotNumber" = a."Plot" ',
          '  WHERE typeof(e."PlotNumber") = \'text\' AND TRIM(e."PlotNumber") <> \'\' ',
          '  ORDER BY e."PlotNumber"',
          ") WHERE SiteUnit IS NOT NULL AND TRIM(SiteUnit) <> ''"
        )
      )
      as.integer(DBI::dbGetQuery(sq_con, paste0("SELECT COUNT(*) AS n FROM ", q_su))$n[[1L]])
    }

    su_n <- insert_su_with_expr(su_expr)
    if (su_n == 0L && !is.null(unit_col) && isTRUE(unit_col_fallback)) {
      su_n <- insert_su_with_expr(coalesced_su_expr)
    }

    DBI::dbExecute(
      sq_con,
      paste0(
        "CREATE UNIQUE INDEX ",
        vpro_quote_ident(paste0("uidx_", su_tbl, "_PlotNumber")),
        " ON ", q_su, ' ("PlotNumber")'
      )
    )
    DBI::dbExecute(
      sq_con,
      paste0(
        "CREATE INDEX ",
        vpro_quote_ident(paste0("idx_", su_tbl, "_SiteUnit")),
        " ON ", q_su, ' ("SiteUnit")'
      )
    )
    DBI::dbExecute(
      sq_con,
      'INSERT OR REPLACE INTO "_table_metadata" ("table_name", "description") VALUES (?, \'VP04\')',
      params = list(su_tbl)
    )

    for (idx_sql in deferred_idx) {
      DBI::dbExecute(sq_con, idx_sql)
    }
  })

  # Capture snapshot-consistent standards release & audit tail inside the same REPEATABLE READ transaction
  snap_bec_ver <- "BECdb_v13_2026"
  snap_tax_ver <- "BCPlantTaxa_v19_2025"
  rel_in_tx <- tryCatch(
    vpro_pg_query(
      con,
      "SELECT bec_version, taxonomy_version FROM standards.library_releases WHERE is_current = TRUE ORDER BY published_at DESC, release_id DESC LIMIT 1",
      params = NULL,
      action = "query active standards release inside snapshot"
    ),
    error = function(e) data.frame()
  )
  if (nrow(rel_in_tx) >= 1L) {
    if (!is.na(rel_in_tx$bec_version[[1L]]) && nzchar(trimws(as.character(rel_in_tx$bec_version[[1L]])))) {
      snap_bec_ver <- trimws(as.character(rel_in_tx$bec_version[[1L]]))
    }
    if (!is.na(rel_in_tx$taxonomy_version[[1L]]) && nzchar(trimws(as.character(rel_in_tx$taxonomy_version[[1L]])))) {
      snap_tax_ver <- trimws(as.character(rel_in_tx$taxonomy_version[[1L]]))
    }
  }
  tail_in_tx <- tryCatch(
    vpro_pg_query(
      con,
      "SELECT COALESCE((SELECT row_hash FROM becmaster.audit ORDER BY audit_seq DESC LIMIT 1), $1) AS tail_hash",
      params = list(.vpro_genesis_audit_hash),
      action = "query audit tail row_hash inside snapshot"
    ),
    error = function(e) data.frame(tail_hash = .vpro_genesis_audit_hash)
  )
  snap_tail_hash <- if (nrow(tail_in_tx) >= 1L && !is.na(tail_in_tx$tail_hash[[1L]]) && nzchar(trimws(as.character(tail_in_tx$tail_hash[[1L]])))) {
    tolower(trimws(as.character(tail_in_tx$tail_hash[[1L]])))
  } else {
    .vpro_genesis_audit_hash
  }

  # Close read-only PostgreSQL snapshot transaction cleanly before WAL finalization & download_log write
  vpro_pg_execute(con, "ROLLBACK", params = NULL, action = "close subset snapshot transaction")
  tx_open <- FALSE

  DBI::dbDisconnect(sq_con)

  insp <- vpro_project_inspect(tmp_db, project_name)
  if (!isTRUE(insp$compatible)) {
    cli::cli_abort("Staged subset SQLite database did not pass {.code VP08} compatibility verification.")
  }

  wal_con <- DBI::dbConnect(RSQLite::SQLite(), tmp_db, flags = RSQLite::SQLITE_RW)
  tryCatch({
    DBI::dbExecute(wal_con, "PRAGMA journal_mode = WAL")
    DBI::dbExecute(wal_con, "PRAGMA wal_checkpoint(TRUNCATE)")
  }, finally = {
    if (DBI::dbIsValid(wal_con)) DBI::dbDisconnect(wal_con)
  })
  unlink(c(paste0(tmp_db, "-wal"), paste0(tmp_db, "-shm")), force = TRUE)

  if (file.exists(paste0(dest_resolved, "-wal")) || file.exists(paste0(dest_resolved, "-shm"))) {
    cli::cli_abort(
      "Refusing to overwrite {.path {dest_resolved}} while active SQLite WAL/SHM sidecar files exist."
    )
  }

  if (!file.rename(tmp_db, dest_resolved)) {
    if (isTRUE(overwrite) && file.exists(dest_resolved)) {
      unlink(dest_resolved)
    }
    if (!file.rename(tmp_db, dest_resolved)) {
      if (!file.copy(tmp_db, dest_resolved, overwrite = isTRUE(overwrite))) {
        cli::cli_abort("Failed to atomically publish subset SQLite database to {.path {dest_resolved}}.")
      }
      unlink(tmp_db, force = TRUE)
    }
  }
  published <- TRUE

  dest_final <- normalizePath(dest_resolved, winslash = "/", mustWork = TRUE)
  ws <- vpro_connect(dest_final)

  # Cleanly close a RW handle after SQLITE_RO inspection inside vpro_connect() so
  # SQLite removes idle -shm/-wal sidecars while preserving journal_mode = WAL
  clean_con <- DBI::dbConnect(RSQLite::SQLite(), dest_final, flags = RSQLite::SQLITE_RW)
  tryCatch({
    DBI::dbGetQuery(clean_con, "SELECT 1 FROM sqlite_master LIMIT 1")
    DBI::dbExecute(clean_con, "PRAGMA wal_checkpoint(TRUNCATE)")
  }, finally = {
    if (DBI::dbIsValid(clean_con)) DBI::dbDisconnect(clean_con)
  })
  sha256 <- tolower(trimws(unname(as.character(vpro_sha256_file(dest_final)))))

  download_log_id <- NA_integer_
  if (isTRUE(log_download)) {
    actor <- if (!is.null(con$user) && length(con$user) >= 1L &&
                 !is.na(con$user[[1L]]) && nzchar(trimws(as.character(con$user[[1L]])))) {
      trimws(as.character(con$user[[1L]]))
    } else {
      "VProUser"
    }
    role_tier <- if (!is.null(con$role) && length(con$role) >= 1L &&
                     !is.na(con$role[[1L]]) && nzchar(trimws(as.character(con$role[[1L]])))) {
      trimws(as.character(con$role[[1L]]))
    } else {
      "contributor"
    }
    filter_json <- vpro_serialize_subset_filter_json(
      sub$filters,
      limit_int = limit_int,
      allow_full = allow_full
    )
    log_df <- vpro_pg_query(
      con,
      paste(
        "INSERT INTO becmaster.download_log (actor, role_tier, filter_json, format, plot_count)",
        "VALUES ($1, $2, $3::jsonb, 'VP08_SQLite', $4)",
        "RETURNING id"
      ),
      params = list(actor, role_tier, filter_json, as.integer(length(plot_list))),
      action = "record becmaster.download_log entry"
    )
    if (nrow(log_df) >= 1L && "id" %in% names(log_df)) {
      id_chr <- as.character(log_df$id[[1L]])
      id_dbl <- suppressWarnings(as.double(id_chr))
      download_log_id <- if (!is.na(id_dbl) && abs(id_dbl) <= .Machine$integer.max) {
        as.integer(id_chr)
      } else {
        id_dbl
      }
    }
  }

  list(
    dest_path = dest_final,
    project_name = project_name,
    sha256 = sha256,
    plot_count = as.integer(length(plot_list)),
    veg_count = as.integer(veg_n),
    humus_count = as.integer(humus_n),
    mineral_count = as.integer(mineral_n),
    other_count = as.integer(other_n),
    metadata_count = as.integer(meta_n),
    su_count = as.integer(su_n),
    download_log_id = download_log_id,
    snapshot_meta = list(
      bec_version = snap_bec_ver,
      taxonomy_version = snap_tax_ver,
      tail_audit_hash = snap_tail_hash
    ),
    workspace = ws
  )
}

#' Pull a snapshot-consistent PostgreSQL `BECMaster` subset into a local `VP08` SQLite `.db`
#'
#' Streams a filtered regional or project checkout from PostgreSQL `becmaster.*`
#' inside a `REPEATABLE READ READ ONLY` transaction into an atomic `VP08` SQLite
#' WAL database (`_Env`, `_Admin`, `_Veg`, `_Humus`, `_Mineral`, `_Other`,
#' `_Audit`, `_Metadata`, `_SU`, `_table_metadata`, and `__VPRO_ChildIdentity`),
#' verifies `VP08` compatibility via [vpro_project_inspect()], and records a
#' provenance receipt in `becmaster.download_log`.
#'
#' @inheritParams vpro_master_env
#' @param dest_path Destination SQLite `.db` file path (`.db` is appended if no
#'   file extension is present).
#' @param project_name Target `VP08` project prefix (must start with an ASCII
#'   letter, contain only letters, digits, or underscores up to 31 characters,
#'   and cannot be `"None"`, `"Sample"`, or contain `"master"`).
#' @param overwrite Logical; if `TRUE`, replaces an existing `dest_path` when no
#'   active `-wal`/`-shm` sidecar files exist.
#' @return A list containing `dest_path`, `project_name`, `sha256`, `plot_count`,
#'   `veg_count`, `humus_count`, `mineral_count`, `other_count`,
#'   `metadata_count`, `download_log_id`, and `workspace` (`vpro_workspace`).
#' @export
vpro_master_pull <- function(
  con,
  dest_path,
  project_name,
  zones = NULL,
  subzones = NULL,
  project_ids = NULL,
  plots = NULL,
  bbox = NULL,
  overwrite = FALSE,
  limit = NULL,
  allow_full = FALSE
) {
  res <- vpro_master_pull_impl(
    con = con,
    dest_path = dest_path,
    project_name = project_name,
    zones = zones,
    subzones = subzones,
    project_ids = project_ids,
    plots = plots,
    bbox = bbox,
    overwrite = overwrite,
    limit = limit,
    allow_full = allow_full,
    log_download = TRUE,
    allow_reserved_name = FALSE,
    unit_col = NULL,
    unit_col_fallback = TRUE
  )
  res$su_count <- NULL
  res
}

#' Materialize a temporary local `vpro_workspace` from a PostgreSQL `BECMaster` subset
#'
#' Pulls a snapshot-consistent cloud subset into a session-temporary `VP08`
#' SQLite database (`log_download = FALSE`), populates `<Project>_SU` from
#' `unit_col`, attaches a garbage-collector / session-exit finalizer to remove
#' the temporary database automatically, and returns a `vpro_workspace` handle
#' ready for [vpro_matrix()], [vpro_cluster()], [vpro_diagnostics()],
#' [vpro_climate()], and [vpro_render_guide()].
#'
#' @inheritParams vpro_master_env
#' @param unit_col Classification column used to populate `<Project>_SU`:
#'   `"BECSiteUnit"` (default), `"UserSiteUnit"`, or `"SiteSeries"`.
#' @param project_name Project prefix inside the temporary workspace database
#'   (defaults to `"CloudSubset"`).
#' @return An S3 `vpro_workspace` object with `ws$source == "cloud_workspace"`.
#' @export
vpro_master_workspace <- function(
  con,
  zones = NULL,
  subzones = NULL,
  project_ids = NULL,
  plots = NULL,
  bbox = NULL,
  unit_col = c("BECSiteUnit", "UserSiteUnit", "SiteSeries"),
  project_name = "CloudSubset",
  limit = NULL
) {
  unit_col_explicit <- !missing(unit_col)
  unit_col <- match.arg(unit_col)

  tmp_ws_db <- tempfile(pattern = "vpro-cloud-ws-", fileext = ".db")
  res <- vpro_master_pull_impl(
    con = con,
    dest_path = tmp_ws_db,
    project_name = project_name,
    zones = zones,
    subzones = subzones,
    project_ids = project_ids,
    plots = plots,
    bbox = bbox,
    overwrite = TRUE,
    limit = limit,
    allow_full = FALSE,
    log_download = FALSE,
    allow_reserved_name = FALSE,
    unit_col = unit_col,
    unit_col_fallback = !unit_col_explicit
  )

  ws <- res$workspace
  ws$source <- "cloud_workspace"
  if (identical(res$su_count, 0L)) {
    ws$su <- NULL
  }

  cleanup_env <- new.env(parent = emptyenv())
  cleanup_env$db_path <- res$dest_path
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
  ws$.cloud_cleanup <- cleanup_env
  attr(ws, "cloud_cleanup") <- cleanup_env
  ws
}

vpro_rebuild_vlists_from_standards <- function(con, base_vlists_path, out_path, bec_version, taxonomy_version) {
  if (!file.copy(base_vlists_path, out_path, overwrite = TRUE)) {
    cli::cli_abort("Failed to stage baseline {.file VLists.db} for relational standards rebuild.")
  }

  sq_con <- DBI::dbConnect(RSQLite::SQLite(), out_path)
  on.exit(if (DBI::dbIsValid(sq_con)) DBI::dbDisconnect(sq_con), add = TRUE)
  DBI::dbExecute(sq_con, "PRAGMA journal_mode = DELETE")
  DBI::dbExecute(sq_con, "PRAGMA synchronous = FULL")

  table_map <- list(
    list(pg = "usys_all_specs", sqlite = "USysAllSpecs"),
    list(pg = "usys_table_of_lists", sqlite = "USysTableOfLists"),
    list(pg = "master_site_unit_list", sqlite = "MasterSiteUnitList"),
    list(pg = "usys_zone_list", sqlite = "USysZoneList")
  )

  DBI::dbWithTransaction(sq_con, {
    for (item in table_map) {
      spec <- vpro_pg_standards_specs(item$pg)
      col_names <- as.character(spec$name)
      quoted_cols <- paste(vapply(col_names, vpro_quote_ident, character(1)), collapse = ", ")
      df <- vpro_pg_query(
        con,
        paste0("SELECT ", quoted_cols, " FROM standards.", vpro_quote_ident(item$pg), " ORDER BY row_seq"),
        params = NULL,
        action = paste0("sync standards.", item$pg)
      )
      df <- vpro_pg_canonicalize_to_sqlite(df, spec)
      bool_cols <- as.character(spec$name[
        (!is.na(spec$is_bool) & spec$is_bool) |
          (!is.na(spec$sqlite_type) & toupper(spec$sqlite_type) == "BOOLEAN")
      ])
      for (bc in intersect(bool_cols, names(df))) {
        df[[bc]] <- vpro_logical_to_access(df[[bc]])
      }
      DBI::dbExecute(sq_con, paste0("DELETE FROM ", vpro_quote_ident(item$sqlite)))
      if (nrow(df) > 0L) {
        sq_fields <- DBI::dbListFields(sq_con, item$sqlite)
        keep_c <- intersect(sq_fields, names(df))
        DBI::dbAppendTable(sq_con, item$sqlite, df[, keep_c, drop = FALSE])
      }
    }

    if (DBI::dbExistsTable(sq_con, "_table_metadata")) {
      DBI::dbExecute(
        sq_con,
        'UPDATE "_table_metadata" SET "description" = ? WHERE "table_name" = \'USysAllSpecs\'',
        params = list(as.character(taxonomy_version))
      )
      DBI::dbExecute(
        sq_con,
        'UPDATE "_table_metadata" SET "description" = ? WHERE "table_name" = \'USysTableOfLists\'',
        params = list(as.character(bec_version))
      )
    }
  })

  DBI::dbDisconnect(sq_con)
  invisible(out_path)
}

#' Synchronize local `VLists.db` with the active PostgreSQL `standards.library_releases` snapshot
#'
#' Compares the SHA-256 digest of the workspace `VLists.db` against the active
#' (`is_current = TRUE`) release in `standards.library_releases`. When absent or
#' outdated, refuses to clobber any live WAL session (`-wal`/`-shm` guard),
#' decompresses `vlists_gzip` (unwrapping `RPostgres` `BYTEA` `blob` payloads,
#' with relational `standards.*` table rebuild fallback if `vlists_gzip` is
#' `NULL`), verifies `PRAGMA integrity_check` and SHA-256 integrity, and
#' atomically swaps the staged database onto `VLists.db`.
#'
#' @param con A `vpro_pg_conn` handle.
#' @param data_dir Target VPro workspace data directory (defaults to
#'   [vpro_data_dir()]).
#' @return A list with `updated`, `already_current`, `release_id`,
#'   `bec_version`, `taxonomy_version`, `local_sha256`, `cloud_sha256`,
#'   `vlists_path`, and `published_at`.
#' @export
vpro_standards_sync <- function(con, data_dir = vpro_data_dir()) {
  vpro_assert_pg_conn(con, require_custodian = FALSE)
  if (!is.character(data_dir) || length(data_dir) != 1L || is.na(data_dir) || !nzchar(trimws(data_dir))) {
    cli::cli_abort("{.arg data_dir} must be a single non-empty directory path.")
  }
  data_dir <- vpro_abs_path(trimws(data_dir))
  if (vpro_is_bundled_package_path(data_dir)) {
    cli::cli_abort("Refusing to write {.file VLists.db} inside the installed {.pkg vpro} package directory.")
  }

  rel_df <- vpro_pg_query(
    con,
    paste(
      "SELECT release_id, bec_version, taxonomy_version, vlists_sha256, published_at, vlists_gzip",
      "FROM standards.library_releases",
      "WHERE is_current = TRUE",
      "ORDER BY published_at DESC",
      "LIMIT 1"
    ),
    params = NULL,
    action = "query active standards.library_releases"
  )
  if (nrow(rel_df) == 0L) {
    cli::cli_abort(
      "No active provincial standards release ({.code is_current = TRUE}) has been published in {.code standards.library_releases}."
    )
  }

  release_id <- as.character(rel_df$release_id[[1L]])
  bec_version <- as.character(rel_df$bec_version[[1L]])
  taxonomy_version <- as.character(rel_df$taxonomy_version[[1L]])
  cloud_sha256 <- tolower(trimws(as.character(rel_df$vlists_sha256[[1L]])))
  pub_raw <- rel_df$published_at[[1L]]
  published_at <- if (inherits(pub_raw, "POSIXt")) {
    format(pub_raw, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  } else {
    as.character(pub_raw)
  }

  cand_top <- file.path(data_dir, "VLists.db")
  cand_fam <- file.path(data_dir, "database-family", "VLists.db")
  if (file.exists(cand_top)) {
    target_path <- normalizePath(cand_top, winslash = "/", mustWork = FALSE)
    target_exists <- TRUE
  } else if (file.exists(cand_fam)) {
    target_path <- normalizePath(cand_fam, winslash = "/", mustWork = FALSE)
    target_exists <- TRUE
  } else {
    dir.create(data_dir, recursive = TRUE, showWarnings = FALSE)
    target_path <- normalizePath(cand_top, winslash = "/", mustWork = FALSE)
    target_exists <- FALSE
  }

  if (target_exists) {
    local_sha256 <- tolower(trimws(unname(as.character(vpro_sha256_file(target_path)))))
    if (vpro_same_hash(local_sha256, cloud_sha256)) {
      return(list(
        updated = FALSE,
        already_current = TRUE,
        release_id = release_id,
        bec_version = bec_version,
        taxonomy_version = taxonomy_version,
        local_sha256 = local_sha256,
        cloud_sha256 = cloud_sha256,
        vlists_path = target_path,
        published_at = published_at
      ))
    }
  } else {
    bundled_vlists <- vpro_bundled_db("VLists.db")
    local_sha256 <- tolower(trimws(unname(as.character(vpro_sha256_file(bundled_vlists)))))
  }

  wal_path <- paste0(target_path, "-wal")
  shm_path <- paste0(target_path, "-shm")
  has_wal_activity <- (file.exists(wal_path) && !is.na(file.info(wal_path)$size)) ||
    (file.exists(shm_path) && !is.na(file.info(shm_path)$size))
  if (has_wal_activity) {
    cli::cli_abort(
      "Refusing to overwrite {.path {target_path}} while active SQLite WAL/SHM sidecar files exist."
    )
  }

  gz_col <- rel_df$vlists_gzip
  raw_vec <- if (is.raw(gz_col)) {
    gz_col
  } else if (is.list(gz_col) && length(gz_col) >= 1L) {
    gz_col[[1L]]
  } else {
    NULL
  }

  dir.create(dirname(target_path), recursive = TRUE, showWarnings = FALSE)
  tmp_vlists <- tempfile(pattern = ".vpro-vlists-sync-", tmpdir = dirname(target_path), fileext = ".db")
  published <- FALSE
  on.exit({
    if (!published) {
      unlink(tmp_vlists, force = TRUE)
    }
    unlink(c(paste0(tmp_vlists, "-wal"), paste0(tmp_vlists, "-shm")), force = TRUE)
  }, add = TRUE)

  if (!is.null(raw_vec) && is.raw(raw_vec) && length(raw_vec) > 0L) {
    db_bytes <- tryCatch(
      memDecompress(raw_vec, type = "gzip"),
      error = function(e) {
        cli::cli_abort(
          paste0("Failed to decompress cloud {.file VLists.db} gzip snapshot: ", conditionMessage(e)),
          parent = e
        )
      }
    )
    writeBin(db_bytes, tmp_vlists)
    staged_sha <- tolower(trimws(unname(as.character(vpro_sha256_file(tmp_vlists)))))
    if (!is.na(cloud_sha256) && nzchar(cloud_sha256) && !vpro_same_hash(staged_sha, cloud_sha256)) {
      cli::cli_abort(
        "Cloud {.file VLists.db} SHA-256 mismatch (expected {.val {cloud_sha256}}, got {.val {staged_sha}})."
      )
    }
  } else {
    base_vlists <- if (target_exists) target_path else vpro_bundled_db("VLists.db")
    vpro_rebuild_vlists_from_standards(
      con = con,
      base_vlists_path = base_vlists,
      out_path = tmp_vlists,
      bec_version = bec_version,
      taxonomy_version = taxonomy_version
    )
  }

  chk_con <- vpro_sqlite_ro(tmp_vlists)
  ic_df <- tryCatch(
    DBI::dbGetQuery(chk_con, "PRAGMA integrity_check"),
    finally = if (DBI::dbIsValid(chk_con)) DBI::dbDisconnect(chk_con)
  )
  if (nrow(ic_df) == 0L || !identical(tolower(trimws(as.character(ic_df[[1L]][[1L]]))), "ok")) {
    cli::cli_abort("Staged {.file VLists.db} failed SQLite {.code PRAGMA integrity_check}.")
  }

  if (file.exists(wal_path) || file.exists(shm_path)) {
    cli::cli_abort(
      "Refusing to overwrite {.path {target_path}} while active SQLite WAL/SHM sidecar files exist."
    )
  }

  if (!file.rename(tmp_vlists, target_path)) {
    if (file.exists(target_path)) {
      unlink(target_path)
    }
    if (!file.rename(tmp_vlists, target_path)) {
      if (!file.copy(tmp_vlists, target_path, overwrite = TRUE)) {
        cli::cli_abort("Failed to atomically install updated {.file VLists.db} at {.path {target_path}}.")
      }
      unlink(tmp_vlists, force = TRUE)
    }
  }
  published <- TRUE

  final_path <- normalizePath(target_path, winslash = "/", mustWork = TRUE)
  final_sha <- tolower(trimws(unname(as.character(vpro_sha256_file(final_path)))))

  list(
    updated = TRUE,
    already_current = FALSE,
    release_id = release_id,
    bec_version = bec_version,
    taxonomy_version = taxonomy_version,
    local_sha256 = final_sha,
    cloud_sha256 = cloud_sha256,
    vlists_path = final_path,
    published_at = published_at
  )
}
