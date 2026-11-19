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
  if (!is.numeric(limit) || length(limit) != 1L || is.na(limit) || !is.finite(limit) || limit < 1 || limit != trunc(limit)) {
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

vpro_pg_postgis_geom_schema <- function(pg) {
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
    vpro_pg_query(pg, sql, params = NULL, action = "inspect becmaster.env PostGIS geometry column"),
    error = function(e) data.frame(postgis_schema = "", has_geom = FALSE)
  )
  if (nrow(res) >= 1L && isTRUE(vpro_access_to_logical(res$has_geom[[1L]])) && !is.na(res$postgis_schema[[1L]]) && nzchar(trimws(as.character(res$postgis_schema[[1L]])))) {
    trimws(as.character(res$postgis_schema[[1L]]))
  } else {
    ""
  }
}

# Internal parameterized WHERE builder for becmaster.env push-down queries
vpro_pg_subset_where <- function(
  pg,
  zones = NULL,
  subzones = NULL,
  project_ids = NULL,
  plots = NULL,
  bbox = NULL,
  table_alias = "e",
  allow_full = FALSE,
  has_limit = FALSE
) {
  vpro_assert_pg_conn(pg, require_custodian = FALSE)
  allow_full <- vpro_pg_validate_flag(allow_full, "allow_full")
  has_limit <- vpro_pg_validate_flag(has_limit, "has_limit")

  zones_clean <- vpro_pg_clean_tokens(zones, "zones")
  subzones_clean <- vpro_pg_clean_tokens(subzones, "subzones")
  project_ids_clean <- vpro_pg_clean_tokens(project_ids, "project_ids")
  plots_clean <- vpro_pg_clean_tokens(plots, "plots")

  bbox_clean <- NULL
  if (!is.null(bbox)) {
    if (
      inherits(bbox, "bbox") ||
        (is.numeric(bbox) && !is.null(names(bbox)) && all(c("xmin", "ymin", "xmax", "ymax") %in% names(bbox)))
    ) {
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
    postgis_schema <- vpro_pg_postgis_geom_schema(pg)
    if (nzchar(postgis_schema)) {
      clauses <- c(
        clauses,
        paste0(
          "(",
          pfx,
          "geom && ",
          vpro_quote_ident(postgis_schema),
          ".ST_MakeEnvelope(",
          p_min_lon,
          ", ",
          p_min_lat,
          ", ",
          p_max_lon,
          ", ",
          p_max_lat,
          ", 4326) AND ",
          pfx,
          '"Longitude" BETWEEN ',
          p_min_lon,
          " AND ",
          p_max_lon,
          " AND ",
          pfx,
          '"Latitude" BETWEEN ',
          p_min_lat,
          " AND ",
          p_max_lat,
          ")"
        )
      )
    } else {
      clauses <- c(
        clauses,
        paste0(
          "(",
          pfx,
          '"Longitude" BETWEEN ',
          p_min_lon,
          " AND ",
          p_max_lon,
          " AND ",
          pfx,
          '"Latitude" BETWEEN ',
          p_min_lat,
          " AND ",
          p_max_lat,
          ")"
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

# Red/Blue-listed accepted taxa only, matching Go IsSensitiveRedBlueList and
# loadSensitiveSpecies*: RedBlueList in R/B/RED/BLUE and Codetype <> 'S'.
.vpro_sensitive_attr_where_sql <- function() {
  paste(
    'WHERE "Code" IS NOT NULL AND TRIM(CAST("Code" AS TEXT)) <> \'\'',
    'AND UPPER(TRIM(COALESCE(CAST("Codetype" AS TEXT), \'\'))) <> \'S\'',
    'AND UPPER(TRIM(COALESCE(CAST("RedBlueList" AS TEXT), \'\'))) IN (\'R\', \'B\', \'RED\', \'BLUE\')'
  )
}

.vpro_sensitive_species_codes <- function(
  pg = NULL,
  vlists_path = getOption("vpro.vlists_path", NULL),
  extra_codes = NULL,
  require_populated = TRUE
) {
  require_populated <- vpro_pg_validate_flag(require_populated, "require_populated")
  codes <- character()
  syn_pairs <- data.frame(Code = character(), OldCode = character(), stringsAsFactors = FALSE)
  checked_sources <- character()
  has_any_attr_table <- FALSE

  if (!is.null(extra_codes)) {
    extra_clean <- unique(toupper(trimws(as.character(extra_codes[!is.na(extra_codes)]))))
    extra_clean <- extra_clean[nzchar(extra_clean)]
    if (length(extra_clean) > 0L) {
      codes <- c(codes, extra_clean)
      has_any_attr_table <- TRUE
    }
  }

  vdb <- ""
  if (!is.null(vlists_path)) {
    if (!is.character(vlists_path) || length(vlists_path) != 1L || is.na(vlists_path) || !nzchar(trimws(vlists_path))) {
      if (is.null(pg) && length(codes) == 0L && isTRUE(require_populated)) {
        cli::cli_abort(
          "{.arg vlists_path} must be a non-empty file path to {.file VLists.db} for rare-plant coordinate redaction."
        )
      }
    } else {
      vdb_cand <- trimws(vlists_path)
      if (!file.exists(vdb_cand)) {
        if (is.null(pg) && length(codes) == 0L && isTRUE(require_populated)) {
          cli::cli_abort(c(
            "Species conservation catalogue {.path {vdb_cand}} was not found.",
            "i" = "Refusing to return or export unredacted plot coordinates when sensitive-species redaction is required."
          ))
        }
      } else {
        vdb <- vdb_cand
      }
    }
  } else {
    vdb <- tryCatch(vpro_find_support_db("VLists.db", vpro_data_dir()), error = function(e) "")
  }

  if (is.character(vdb) && length(vdb) == 1L && nzchar(vdb) && file.exists(vdb)) {
    checked_sources <- c(checked_sources, vdb)
    dbc <- tryCatch(vpro_sqlite_ro(vdb), error = function(e) e)
    if (inherits(dbc, "error")) {
      if (is.null(pg) && length(codes) == 0L && isTRUE(require_populated)) {
        cli::cli_abort(
          "Failed to open species conservation catalogue {.path {vdb}} for rare-plant coordinate redaction: {conditionMessage(dbc)}"
        )
      }
    } else if (!is.null(dbc)) {
      on.exit(if (DBI::dbIsValid(dbc)) DBI::dbDisconnect(dbc), add = TRUE)
      if (isTRUE(DBI::dbExistsTable(dbc, "USysSppAttributes"))) {
        has_any_attr_table <- TRUE
        attr_df <- DBI::dbGetQuery(
          dbc,
          paste(
            'SELECT DISTINCT UPPER(TRIM(CAST("Code" AS TEXT))) AS code FROM "USysSppAttributes"',
            .vpro_sensitive_attr_where_sql()
          )
        )
        if (nrow(attr_df) > 0L) {
          codes <- c(codes, as.character(attr_df$code))
        }
      }
      if (isTRUE(tryCatch(DBI::dbExistsTable(dbc, "USysAllSpecs"), error = function(e) FALSE))) {
        sp_df <- tryCatch(
          DBI::dbGetQuery(
            dbc,
            'SELECT UPPER(TRIM(CAST("Code" AS TEXT))) AS "Code", UPPER(TRIM(CAST("OldCode" AS TEXT))) AS "OldCode" FROM "USysAllSpecs" WHERE "OldCode" IS NOT NULL AND TRIM(CAST("OldCode" AS TEXT)) <> \'\' AND "Code" IS NOT NULL AND TRIM(CAST("Code" AS TEXT)) <> \'\''
          ),
          error = function(e) data.frame()
        )
        if (nrow(sp_df) > 0L) {
          syn_pairs <- rbind(syn_pairs, sp_df)
        }
      }
    }
  }

  if (!is.null(pg)) {
    checked_sources <- c(checked_sources, "standards.usys_spp_attributes")
    chk <- vpro_pg_query(
      pg,
      "SELECT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'standards' AND table_name = 'usys_spp_attributes') AS ok",
      params = NULL,
      action = "check standards.usys_spp_attributes availability"
    )
    has_pg_attr <- nrow(chk) >= 1L && isTRUE(vpro_access_to_logical(chk$ok[[1L]]))
    if (isTRUE(has_pg_attr)) {
      has_any_attr_table <- TRUE
      pg_attr <- vpro_pg_query(
        pg,
        paste(
          'SELECT DISTINCT UPPER(TRIM(CAST("Code" AS TEXT))) AS code FROM standards.usys_spp_attributes',
          .vpro_sensitive_attr_where_sql()
        ),
        params = NULL,
        action = "query sensitive species in standards.usys_spp_attributes"
      )
      if (nrow(pg_attr) > 0L) {
        codes <- c(codes, as.character(pg_attr$code))
      }
    }
  }

  codes <- unique(toupper(trimws(codes[!is.na(codes)])))
  codes <- codes[nzchar(codes)]
  if (length(codes) > 0L && nrow(syn_pairs) > 0L) {
    syn_pairs$Code <- toupper(trimws(as.character(syn_pairs$Code)))
    syn_pairs$OldCode <- toupper(trimws(as.character(syn_pairs$OldCode)))
    old_hits <- syn_pairs$OldCode[syn_pairs$Code %in% codes]
    canon_hits <- syn_pairs$Code[syn_pairs$OldCode %in% codes]
    codes <- unique(c(codes, old_hits, canon_hits))
    codes <- codes[nzchar(codes)]
  }

  if (isTRUE(require_populated) && length(codes) == 0L) {
    src_lbl <- if (length(checked_sources) > 0L) {
      paste(checked_sources, collapse = ", ")
    } else {
      "VLists.db / standards.usys_spp_attributes"
    }
    if (!isTRUE(has_any_attr_table)) {
      cli::cli_abort(c(
        "Cannot redact rare-plant coordinates because species conservation table {.code USysSppAttributes} ({.code standards.usys_spp_attributes}) is missing ({src_lbl}).",
        "i" = "Refusing to return or export unredacted plot coordinates when sensitive-species redaction is required.",
        "i" = "Supply a species catalogue populated with BC Conservation Data Centre (CDC) Red/Blue status codes ({.val R}/{.val B}), or set {.code redact_sensitive = FALSE} only when unredacted coordinates are authorized."
      ))
    }
    cli::cli_abort(c(
      "Cannot redact rare-plant coordinates because {.code USysSppAttributes.RedBlueList} contains 0 Red/Blue-listed species rows ({src_lbl}).",
      "i" = "Refusing to return or export unredacted plot coordinates when sensitive-species redaction is required.",
      "i" = "Populate BC Conservation Data Centre (CDC) Red/Blue status codes ({.val R}/{.val B}) in {.file VLists.db} / {.code standards.usys_spp_attributes}, or set {.code redact_sensitive = FALSE} only when unredacted coordinates are authorized."
    ))
  }

  sort(as.character(codes), method = "radix")
}

.vpro_sensitive_plots_in_pg <- function(pg, plots, sensitive_codes) {
  plots <- unique(as.character(plots[!is.na(plots) & nzchar(trimws(as.character(plots)))]))
  sensitive_codes <- unique(toupper(trimws(as.character(sensitive_codes[!is.na(sensitive_codes)]))))
  sensitive_codes <- sensitive_codes[nzchar(sensitive_codes)]
  if (length(plots) == 0L || length(sensitive_codes) == 0L) {
    return(character(0L))
  }

  tax_bundle <- tryCatch(vpro_pg_load_cloud_taxonomy(pg, resolve_synonyms = TRUE), error = function(e) NULL)
  if (!is.null(tax_bundle) && length(tax_bundle$syn_map) > 0L) {
    syn_map <- tax_bundle$syn_map
    extra_old <- names(syn_map)[unname(syn_map) %in% sensitive_codes]
    extra_canon <- unname(syn_map[names(syn_map) %in% sensitive_codes])
    sensitive_codes <- unique(c(sensitive_codes, extra_old, extra_canon))
    sensitive_codes <- sensitive_codes[nzchar(sensitive_codes)]
  }

  hit_df <- vpro_pg_query(
    pg,
    paste(
      'SELECT DISTINCT CAST("PlotNumber" AS TEXT) AS "PlotNumber"',
      "FROM becmaster.veg",
      'WHERE "PlotNumber" = ANY($1::text[])',
      '  AND UPPER(TRIM(CAST("Species" AS TEXT))) = ANY($2::text[])'
    ),
    params = list(vpro_pg_text_array(plots), vpro_pg_text_array(sensitive_codes)),
    action = "identify plots containing Red/Blue listed sensitive species"
  )
  if (!is.data.frame(hit_df) || nrow(hit_df) == 0L) {
    return(character(0L))
  }
  unique(as.character(hit_df$PlotNumber[!is.na(hit_df$PlotNumber) & nzchar(hit_df$PlotNumber)]))
}

# Truncate coordinates of sensitive plots to a ~10 km grid exactly like Go
# MaskSensitiveEnvRow: Latitude/Longitude to 0.1 degree, UTMEasting/UTMNorthing
# to 10,000 m, and XCoord/YCoord as degrees when |x| <= 180 and |y| <= 90,
# otherwise as metres. UTMZone is preserved. Non-numeric values are cleared.
.vpro_trunc_latlon <- function(x) trunc(x * 10) / 10
.vpro_trunc_utm <- function(x) trunc(x / 10000) * 10000

.vpro_redact_coord_df <- function(df, sensitive_plots) {
  if (!is.data.frame(df) || nrow(df) == 0L || length(sensitive_plots) == 0L || !("PlotNumber" %in% names(df))) {
    return(df)
  }
  mask <- as.character(df$PlotNumber) %in% as.character(sensitive_plots)
  if (!any(mask)) {
    return(df)
  }
  apply_col <- function(df, cc, fn) {
    v <- df[[cc]]
    if (is.numeric(v)) {
      idx <- mask & is.finite(v)
      out <- fn(as.double(v[idx]))
      if (is.integer(v)) out <- as.integer(out)
      v[idx] <- out
    } else {
      v[mask] <- NA
    }
    df[[cc]] <- v
    df
  }
  for (cc in intersect(c("Latitude", "Longitude"), names(df))) {
    df <- apply_col(df, cc, .vpro_trunc_latlon)
  }
  for (cc in intersect(c("UTMEasting", "UTMNorthing"), names(df))) {
    df <- apply_col(df, cc, .vpro_trunc_utm)
  }
  has_x <- "XCoord" %in% names(df)
  has_y <- "YCoord" %in% names(df)
  if (has_x || has_y) {
    num <- function(cc) {
      if (cc %in% names(df) && is.numeric(df[[cc]])) as.double(df[[cc]]) else rep(NA_real_, nrow(df))
    }
    xv <- num("XCoord")
    yv <- num("YCoord")
    is_deg <- (!is.finite(xv) | abs(xv) <= 180) & (!is.finite(yv) | abs(yv) <= 90)
    for (cc in intersect(c("XCoord", "YCoord"), names(df))) {
      v <- df[[cc]]
      if (is.numeric(v)) {
        vals <- as.double(v)
        idx <- mask & is.finite(vals)
        out <- ifelse(is_deg[idx], .vpro_trunc_latlon(vals[idx]), .vpro_trunc_utm(vals[idx]))
        if (is.integer(v)) out <- as.integer(out)
        v[idx] <- out
      } else {
        v[mask] <- NA
      }
      df[[cc]] <- v
    }
  }
  df
}

vpro_same_hash <- function(a, b) {
  if (length(a) != 1L || length(b) != 1L || is.na(a[[1L]]) || is.na(b[[1L]])) {
    return(FALSE)
  }
  tolower(trimws(unname(as.character(a[[1L]])))) == tolower(trimws(unname(as.character(b[[1L]]))))
}

#' Verify the cryptographic SHA-256 hash chain on `becmaster.audit` (internal)
#'
#' Recomputes `row_hash` across the most recent `limit` rows of `becmaster.audit`
#' in ascending `audit_seq` order using `vpro_compute_audit_row_hash()`,
#' matching VPro Desktop. Anchors the window's first row
#' against `.vpro_genesis_audit_hash` when starting at the beginning of the
#' ledger, or against the immediate predecessor row's `row_hash` when verifying
#' a bounded tail window.
#'
#' @param pg A `vpro_pg_conn` handle.
#' @param limit Positive integer number of most-recent audit rows to verify
#'   (defaults to `1000L`).
#' @return A list with `verified_rows` (`integer`), `valid` (`logical`),
#'   `partial_window` (`logical`), `tail_hash` (`character`), and `detail`
#'   (`character`).
#' @keywords internal
.vpro_master_verify_audit <- function(pg, limit = 1000L) {
  vpro_assert_pg_conn(pg, require_custodian = FALSE)
  limit_int <- if (is.null(limit)) 1000L else vpro_pg_validate_limit(limit, allow_null = FALSE)

  audit_spec <- vpro_pg_vp08_specs("Audit")
  audit_cols <- as.character(audit_spec$name)
  quoted_csv <- paste(vapply(audit_cols, vpro_quote_ident, character(1)), collapse = ", ")

  sql <- paste0(
    "SELECT * FROM (",
    "  SELECT audit_seq::text AS audit_seq_txt, audit_seq, ",
    quoted_csv,
    ", ",
    '         "ID"::text AS "__id_txt__", ',
    "         COALESCE(merge_tx_id::text, '') AS merge_tx_id, prev_hash, row_hash",
    "  FROM becmaster.audit",
    "  ORDER BY audit_seq DESC",
    "  LIMIT $1",
    ") AS sub ",
    "ORDER BY audit_seq ASC"
  )

  df <- vpro_pg_query(
    pg,
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
          "Audit hash chain broken at seq=",
          seq_txt,
          ": prev_hash=",
          prev_hash,
          " != expected=",
          expected_prev
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
          "Audit row_hash tampered at seq=",
          seq_txt,
          ": computed=",
          computed,
          " != stored=",
          row_hash
        )
      ))
    }

    expected_prev <- row_hash
    tail_hash <- row_hash
    count <- count + 1L
  }

  pred_df <- vpro_pg_query(
    pg,
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
          "Initial audit row seq=",
          first_seq_txt,
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
          "Audit window boundary broken at seq=",
          first_seq_txt,
          ": prev_hash=",
          first_prev_hash,
          " != predecessor=",
          pred_hash
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

vpro_validate_splinter_project_name <- function(project_name, allow_reserved_name = FALSE) {
  if (
    !is.character(project_name) || length(project_name) != 1L || is.na(project_name) || !validUTF8(project_name) || trimws(project_name) != project_name || !nzchar(project_name)
  ) {
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
  if (length(filters$zones) > 0L) {
    payload$zones <- as.character(filters$zones)
  }
  if (length(filters$subzones) > 0L) {
    payload$subzones <- as.character(filters$subzones)
  }
  if (length(filters$project_ids) > 0L) {
    payload$projectIds <- as.character(filters$project_ids)
  }
  if (length(filters$plots) > 0L) {
    payload$plotNumbers <- as.character(filters$plots)
  }
  if (!is.null(filters$bbox)) {
    payload$bbox <- as.numeric(filters$bbox)
  }
  if (!is.null(limit_int)) {
    payload$limit <- jsonlite::unbox(as.integer(limit_int))
  }
  if (isTRUE(allow_full)) {
    payload$allowFullCheckout <- jsonlite::unbox(TRUE)
  }
  as.character(jsonlite::toJSON(payload, auto_unbox = FALSE))
}
