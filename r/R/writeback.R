# Guarded Non-Destructive Project Write-Back ---------------------------------

.vpro_protected_db_basenames <- c(
  "vlists.db",
  "vpro64.db",
  "vuser.db",
  "vmetadata.db",
  "vmessageboard.db",
  "vpics.db",
  "vlists.db.gz",
  "vpro64.db.gz",
  "bec.db",
  "working-unit.db",
  "site-codes.db",
  "soil-codes.db",
  "parent-codes.db"
)

.vpro_rsidecar_history_ddl <- paste(
  'CREATE TABLE IF NOT EXISTS main."__VPRO_RSidecarHistory" (',
  '  "ID" INTEGER PRIMARY KEY AUTOINCREMENT,',
  '  "CreatedAt" TEXT NOT NULL,',
  '  "Action" TEXT NOT NULL,',
  '  "DetailsJSON" TEXT NOT NULL',
  ')'
)

.vpro_child_identity_ddl <- paste(
  'CREATE TABLE IF NOT EXISTS main."__VPRO_ChildIdentity" (',
  '  "ChildTable" TEXT NOT NULL,',
  '  "ID" INTEGER NOT NULL,',
  '  PRIMARY KEY ("ChildTable", "ID")',
  ')'
)

vpro_is_protected_support_db <- function(path, con = NULL) {
  if (!is.character(path) || length(path) != 1L || is.na(path) || !nzchar(path)) {
    return(TRUE)
  }
  bname <- tolower(basename(path))
  if (bname %in% .vpro_protected_db_basenames) {
    return(TRUE)
  }
  if (!is.null(con) && is.list(con)) {
    norm_p <- normalizePath(path, winslash = "/", mustWork = FALSE)
    sup_paths <- c(con$vlists_path, con$vpro64_path, con$vuser_path, con$vmetadata_path)
    sup_paths <- sup_paths[!is.na(sup_paths) & nzchar(sup_paths)]
    if (length(sup_paths) > 0L) {
      norm_sup <- normalizePath(sup_paths, winslash = "/", mustWork = FALSE)
      if (norm_p %in% norm_sup) {
        return(TRUE)
      }
    }
  }
  FALSE
}

vpro_is_bundled_package_path <- function(path) {
  if (!is.character(path) || length(path) != 1L || is.na(path) || !nzchar(path)) {
    return(FALSE)
  }
  norm_target <- normalizePath(path, winslash = "/", mustWork = FALSE)
  roots <- character()
  pkg_dir <- system.file(package = "vpro")
  if (nzchar(pkg_dir)) {
    roots <- c(roots, normalizePath(pkg_dir, winslash = "/", mustWork = FALSE))
  }
  ext_dir <- vpro_bundled_file("extdata", must_work = FALSE)
  if (nzchar(ext_dir)) {
    roots <- c(roots, normalizePath(ext_dir, winslash = "/", mustWork = FALSE))
  }
  roots <- unique(roots[nzchar(roots)])
  for (rt in roots) {
    if (identical(norm_target, rt) || startsWith(norm_target, paste0(rt, "/"))) {
      return(TRUE)
    }
  }
  FALSE
}

vpro_assert_writable_project_db <- function(db_path, con = NULL) {
  if (!is.character(db_path) || length(db_path) != 1L || is.na(db_path) || !nzchar(trimws(db_path))) {
    rlang::abort("Target SQLite database path must be a single non-empty string.")
  }
  if (!file.exists(db_path) || dir.exists(db_path)) {
    rlang::abort(paste0("Target SQLite database does not exist: ", db_path))
  }
  if (vpro_is_protected_support_db(db_path, con = con)) {
    rlang::abort(paste0(
      "Refusing write-back to protected VPro system/reference database: ",
      basename(db_path)
    ))
  }
  if (
    vpro_is_bundled_package_path(db_path) ||
      (!is.null(con) &&
        identical(con$source, "sample") &&
        identical(
          normalizePath(db_path, winslash = "/", mustWork = FALSE),
          normalizePath(vpro_bundled_db("Sample.db"), winslash = "/", mustWork = FALSE)
        ))
  ) {
    rlang::abort(paste0(
      "Refusing write-back to read-only installed `vpro` package database: ",
      db_path,
      ". Copy the database to a user workspace before writing."
    ))
  }
  normalizePath(db_path, winslash = "/", mustWork = TRUE)
}

vpro_with_immediate_tx <- function(db_path, fn, con = NULL) {
  resolved <- vpro_assert_writable_project_db(db_path, con = con)
  dbc <- vpro_sqlite_rw_immediate(resolved)
  tx_started <- FALSE
  committed <- FALSE
  on.exit(
    {
      if (tx_started && !committed && DBI::dbIsValid(dbc)) {
        tryCatch(DBI::dbExecute(dbc, "ROLLBACK"), error = function(e) NULL)
      }
      if (DBI::dbIsValid(dbc)) {
        DBI::dbDisconnect(dbc)
      }
    },
    add = TRUE
  )

  DBI::dbExecute(dbc, "BEGIN IMMEDIATE")
  tx_started <- TRUE
  out <- fn(dbc)
  DBI::dbExecute(dbc, "COMMIT")
  committed <- TRUE
  out
}

vpro_normalize_actor <- function(actor) {
  if (is.character(actor) && length(actor) >= 1L && !is.na(actor[[1L]]) && nzchar(trimws(actor[[1L]]))) {
    val <- trimws(enc2utf8(actor[[1L]]))
    if (validUTF8(val)) {
      return(val)
    }
  }
  "VProUser"
}

vpro_assert_safe_prefix <- function(raw_name, full_table, project_name, kind = c("candidate_su", "su", "lump")) {
  kind <- match.arg(kind)
  if (!is.character(raw_name) || length(raw_name) != 1L || is.na(raw_name) || !nzchar(trimws(raw_name))) {
    rlang::abort("Target table name must be a single non-empty character string.")
  }
  nm <- trimws(enc2utf8(raw_name))
  ft <- trimws(enc2utf8(full_table))
  if (!validUTF8(nm) || !validUTF8(ft) || grepl("[\r\n]", nm) || grepl("[\r\n]", ft)) {
    rlang::abort("Target table name must be valid UTF-8 without control characters.")
  }

  # Hard refusal guards: Master* / *Master*, USys*, BECSiteUnit, core VP08 tables
  if (grepl("master", nm, ignore.case = TRUE) || grepl("master", ft, ignore.case = TRUE)) {
    rlang::abort(paste0(
      "Refusing write-back to Master-protected table `",
      ft,
      "` (`Master*` prefixes are read-only)."
    ))
  }
  if (grepl("^usys", nm, ignore.case = TRUE) || grepl("^usys", ft, ignore.case = TRUE)) {
    rlang::abort(paste0(
      "Refusing write-back to system table/view `",
      ft,
      "` (`USys*` objects are protected)."
    ))
  }
  if (
    grepl("^becsiteunit(_su|_lump)?$", nm, ignore.case = TRUE) ||
      grepl("^becsiteunit(_su|_lump)?$", ft, ignore.case = TRUE)
  ) {
    rlang::abort(paste0(
      "Refusing write-back to custodian-locked table `",
      ft,
      "` (`BECSiteUnit` is protected)."
    ))
  }

  core_pat <- paste0("_(", paste(.vpro_core_project_suffixes, collapse = "|"), ")$")
  if (grepl(core_pat, nm, ignore.case = TRUE) || grepl(core_pat, ft, ignore.case = TRUE)) {
    rlang::abort(paste0(
      "Refusing write-back targeting core VP08 table `",
      ft,
      "`."
    ))
  }
  if (!is.null(project_name) && nzchar(project_name)) {
    core_exact <- tolower(paste0(project_name, "_", .vpro_core_project_suffixes))
    if (tolower(nm) %in% core_exact || tolower(ft) %in% core_exact) {
      rlang::abort(paste0("Refusing write-back targeting core VP08 table `", ft, "`."))
    }
  }

  invisible(TRUE)
}

vpro_validate_plot_numbers_strict <- function(plot_vec, arg = "PlotNumber") {
  if (!is.character(plot_vec)) {
    rlang::abort(paste0(
      "`",
      arg,
      "` must be a literal `character` vector (never numeric) to preserve leading zeroes such as '00337'."
    ))
  }
  if (length(plot_vec) == 0L) {
    rlang::abort(paste0("`", arg, "` must contain at least one plot."))
  }
  if (anyNA(plot_vec) || any(!nzchar(trimws(plot_vec)))) {
    rlang::abort(paste0("`", arg, "` must not contain `NA` or blank values."))
  }
  u16 <- vpro_utf16_len(plot_vec)
  if (anyNA(u16)) {
    rlang::abort(paste0("`", arg, "` contains malformed UTF-8 or unpaired surrogates."))
  }
  if (any(u16 > 7L)) {
    bad <- plot_vec[which(u16 > 7L)[[1L]]]
    rlang::abort(paste0(
      "`",
      arg,
      "` value '",
      bad,
      "' exceeds VPro's 7-character limit."
    ))
  }
  if (anyDuplicated(plot_vec) > 0L) {
    dup <- plot_vec[duplicated(plot_vec)][[1L]]
    rlang::abort(paste0("`", arg, "` must be unique; duplicate plot '", dup, "' found."))
  }
  plot_vec
}

vpro_extract_su_memberships <- function(memberships) {
  df <- NULL
  if (is.data.frame(memberships)) {
    df <- memberships
  } else if (inherits(memberships, "vpro_clusters") || is.list(memberships)) {
    for (cand in c("memberships", "assignments", "plots", "data")) {
      if (!is.null(memberships[[cand]]) && is.data.frame(memberships[[cand]])) {
        df <- memberships[[cand]]
        break
      }
    }
    if (is.null(df) && !is.null(memberships$cluster) && !is.null(names(memberships$cluster))) {
      df <- data.frame(
        PlotNumber = as.character(names(memberships$cluster)),
        SiteUnit = as.character(unname(memberships$cluster)),
        stringsAsFactors = FALSE
      )
    }
    if (is.null(df)) {
      df <- tryCatch(as.data.frame(tibble::as_tibble(memberships)), error = function(e) NULL)
    }
  }
  if (is.null(df) || !is.data.frame(df)) {
    rlang::abort(
      "`memberships` must be a `vpro_clusters` object or a `data.frame` containing `PlotNumber` and `SiteUnit` (or `Cluster`)."
    )
  }

  nms_low <- tolower(names(df))
  p_ix <- match("plotnumber", nms_low)
  if (is.na(p_ix)) {
    p_ix <- match("plot", nms_low)
  }
  if (is.na(p_ix)) {
    p_ix <- match("plot_number", nms_low)
  }
  u_ix <- NA_integer_
  for (col_cand in c("siteunit", "cluster", "clusterunit", "site_unit", "cluster_unit", "unit")) {
    m <- match(col_cand, nms_low)
    if (!is.na(m)) {
      u_ix <- m
      break
    }
  }
  if (is.na(p_ix) || is.na(u_ix)) {
    rlang::abort(
      "`memberships` must contain `PlotNumber` and `SiteUnit` (or `Cluster` / `ClusterUnit`) columns."
    )
  }

  raw_plots <- df[[p_ix]]
  vpro_validate_plot_numbers_strict(raw_plots, "PlotNumber")

  raw_units <- df[[u_ix]]
  if (anyNA(raw_units)) {
    rlang::abort("`SiteUnit` / `Cluster` must not contain `NA` values.")
  }
  units_chr <- trimws(as.character(raw_units))
  if (any(!nzchar(units_chr))) {
    rlang::abort("`SiteUnit` / `Cluster` must not contain blank strings.")
  }
  u16_units <- vpro_utf16_len(units_chr)
  if (anyNA(u16_units) || any(u16_units > 50L)) {
    rlang::abort("`SiteUnit` values must be valid text up to 50 characters.")
  }

  tibble::tibble(
    PlotNumber = raw_plots,
    SiteUnit = units_chr
  )
}

vpro_reserve_next_id_in_tx <- function(dbc, table_name, id_col = "ID") {
  if (!is.character(table_name) || length(table_name) != 1L || is.na(table_name) || !nzchar(trimws(table_name))) {
    rlang::abort("`table_name` must be a single non-empty table name.")
  }
  raw_unquoted <- gsub('""', '"', sub('^"(.*)"$', "\\1", trimws(enc2utf8(table_name))))
  found_tbl <- DBI::dbGetQuery(
    dbc,
    "SELECT name FROM main.sqlite_master WHERE type = 'table' AND name = ? COLLATE NOCASE",
    params = list(raw_unquoted)
  )
  if (nrow(found_tbl) == 0L) {
    rlang::abort(paste0("Target child table `", raw_unquoted, "` does not exist in SQLite database."))
  }
  unquoted <- as.character(found_tbl$name[[1L]])
  qt <- vpro_quote_ident(unquoted)
  qid <- vpro_quote_ident(id_col)

  DBI::dbExecute(dbc, .vpro_child_identity_ddl)

  sql_parts <- c(
    paste0(
      "SELECT CAST(", qid, " AS INTEGER) AS id_val FROM main.", qt,
      " WHERE typeof(", qid, ") = 'integer' AND ", qid, " > 0 AND ", qid, " <= 2147483647"
    ),
    paste(
      'SELECT "ID" AS id_val FROM main."__VPRO_ChildIdentity"',
      'WHERE "ChildTable" COLLATE NOCASE IN (?, ?) AND typeof("ID") = \'integer\' AND "ID" > 0 AND "ID" <= 2147483647'
    )
  )
  sql_params <- list(qt, unquoted)

  last_sep <- regexpr("_[^_]+$", unquoted)
  if (last_sep > 1L) {
    project_pfx <- substr(unquoted, 1L, last_sep - 1L)
    suffix_part <- substr(unquoted, last_sep, nchar(unquoted))
    if (tolower(suffix_part) != "_audit") {
      audit_cand <- paste0(project_pfx, "_Audit")
      audit_found <- DBI::dbGetQuery(
        dbc,
        "SELECT name FROM main.sqlite_master WHERE type = 'table' AND name = ? COLLATE NOCASE",
        params = list(audit_cand)
      )
      if (nrow(audit_found) > 0L) {
        q_audit <- vpro_quote_ident(as.character(audit_found$name[[1L]]))
        plain_sfx <- substring(suffix_part, 2L)
        sql_parts <- c(
          sql_parts,
          paste0(
            'SELECT "ID" AS id_val FROM main.', q_audit,
            ' WHERE "Table" COLLATE NOCASE IN (?, ?, ?) AND typeof("ID") = \'integer\' AND "ID" > 0 AND "ID" <= 2147483647'
          )
        )
        sql_params <- c(sql_params, list(suffix_part, unquoted, plain_sfx))
      }
    }
  }

  used_df <- DBI::dbGetQuery(
    dbc,
    paste0(paste(sql_parts, collapse = " UNION "), " ORDER BY id_val ASC"),
    params = sql_params
  )
  used_num <- if (nrow(used_df) > 0L) as.numeric(used_df$id_val[!is.na(used_df$id_val)]) else numeric()
  used_num <- sort(unique(used_num[is.finite(used_num) & used_num >= 1 & used_num <= .Machine$integer.max]))

  if (length(used_num) == 0L) {
    next_int <- 1L
  } else {
    max_used <- used_num[[length(used_num)]]
    if (max_used < .Machine$integer.max) {
      next_int <- as.integer(max_used + 1)
    } else {
      candidate <- 1
      for (u in used_num) {
        if (u > candidate) {
          break
        }
        if (candidate >= .Machine$integer.max) {
          rlang::abort(paste0("Child ID space exhausted for table `", unquoted, "`."))
        }
        candidate <- candidate + 1
      }
      next_int <- as.integer(candidate)
    }
  }

  DBI::dbExecute(
    dbc,
    paste(
      'INSERT OR IGNORE INTO main."__VPRO_ChildIdentity" ("ChildTable", "ID")',
      "SELECT ?, ? WHERE NOT EXISTS (",
      '  SELECT 1 FROM main."__VPRO_ChildIdentity"',
      '  WHERE "ChildTable" COLLATE NOCASE IN (?, ?) AND "ID" = ?',
      ")"
    ),
    params = list(qt, next_int, qt, unquoted, next_int)
  )
  next_int
}

vpro_append_rsidecar_history_in_tx <- function(dbc, action, details) {
  DBI::dbExecute(dbc, .vpro_rsidecar_history_ddl)
  now_iso <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  payload <- as.character(jsonlite::toJSON(details, auto_unbox = TRUE, null = "null"))
  DBI::dbExecute(
    dbc,
    'INSERT INTO main."__VPRO_RSidecarHistory" ("CreatedAt", "Action", "DetailsJSON") VALUES (?, ?, ?)',
    params = list(now_iso, as.character(action), payload)
  )
  invisible(TRUE)
}

vpro_append_project_audit_in_tx <- function(
  dbc,
  project_name,
  actor,
  table_name,
  edit_field,
  before_val,
  after_val,
  plot_number = NA_character_,
  child_id = NA_integer_
) {
  audit_cand <- paste0(project_name, "_Audit")
  found <- DBI::dbGetQuery(
    dbc,
    "SELECT name FROM main.sqlite_master WHERE type = 'table' AND name = ? COLLATE NOCASE",
    params = list(audit_cand)
  )
  if (nrow(found) == 0L) {
    rlang::abort(paste0("Required project audit table `", audit_cand, "` does not exist; aborting write-back."))
  }
  actual_audit <- as.character(found$name[[1L]])
  q_audit <- vpro_quote_ident(actual_audit)
  flds <- DBI::dbListFields(dbc, actual_audit)

  now_ts <- format(Sys.time(), "%Y-%m-%d %H:%M:%S", tz = "UTC")
  plot_param <- if (is.na(plot_number) || !nzchar(trimws(plot_number))) NA_character_ else as.character(plot_number)

  if ("ID" %in% flds) {
    id_param <- if (is.null(child_id) || length(child_id) == 0L || is.na(child_id[[1L]])) {
      NA_integer_
    } else {
      as.integer(child_id[[1L]])
    }
    DBI::dbExecute(
      dbc,
      paste0(
        "INSERT INTO main.",
        q_audit,
        ' ("Project", "User", "PlotNumber", "Table", "EditField", "EditWhen", "BeforeEdit", "AfterEdit", "Restore", "Flag", "ID") ',
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, 0, ?)"
      ),
      params = list(
        as.character(project_name),
        vpro_normalize_actor(actor),
        plot_param,
        as.character(table_name),
        as.character(edit_field),
        now_ts,
        as.character(before_val),
        as.character(after_val),
        id_param
      )
    )
  } else {
    DBI::dbExecute(
      dbc,
      paste0(
        "INSERT INTO main.",
        q_audit,
        ' ("Project", "User", "PlotNumber", "Table", "EditField", "EditWhen", "BeforeEdit", "AfterEdit", "Restore", "Flag") ',
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, 0)"
      ),
      params = list(
        as.character(project_name),
        vpro_normalize_actor(actor),
        plot_param,
        as.character(table_name),
        as.character(edit_field),
        now_ts,
        as.character(before_val),
        as.character(after_val)
      )
    )
  }
  invisible(TRUE)
}

vpro_find_existing_table_ci <- function(dbc, table_name) {
  res <- DBI::dbGetQuery(
    dbc,
    "SELECT name, type FROM main.sqlite_master WHERE name = ? COLLATE NOCASE",
    params = list(table_name)
  )
  if (nrow(res) == 0L) {
    return(NULL)
  }
  if (any(tolower(res$type) == "view")) {
    rlang::abort(paste0("Refusing write-back targeting SQLite view `", res$name[[1L]], "`."))
  }
  as.character(res$name[[1L]])
}

vpro_upsert_table_metadata_in_tx <- function(dbc, table_name, version_tag) {
  DBI::dbExecute(
    dbc,
    'CREATE TABLE IF NOT EXISTS main."_table_metadata" ("table_name" TEXT PRIMARY KEY, "description" TEXT)'
  )
  DBI::dbExecute(
    dbc,
    'DELETE FROM main."_table_metadata" WHERE "table_name" = ? COLLATE NOCASE',
    params = list(table_name)
  )
  DBI::dbExecute(
    dbc,
    'INSERT INTO main."_table_metadata" ("table_name", "description") VALUES (?, ?)',
    params = list(table_name, version_tag)
  )
  invisible(TRUE)
}

#' Write or replace a working `*_SU` or candidate Site Unit table
#'
#' Saves plot-to-SiteUnit assignments to `<su>_SU` (or, when
#' `candidate = TRUE`, `<Prefix>_ClusterCandidate_SU`) inside `ws$project_path`
#' in one safe transaction, strictly refusing `Master*`, `USys*`, `BECSiteUnit`,
#' and core `VP08` tables. Requires `create = TRUE` when creating a new table
#' (default `TRUE` when `candidate = TRUE`) and `overwrite = TRUE` when replacing
#' an existing table.
#'
#' @param ws A `vpro_workspace` handle referencing a writable user `.db`.
#' @param memberships A `vpro_clusters` object or a `data.frame` containing
#'   literal character `PlotNumber` and `SiteUnit` (or `Cluster`).
#' @param su Target working site-unit name (with or without `_SU` suffix). When
#'   `candidate = TRUE` and `su = NULL`, defaults to
#'   `paste0(ws$project, "_ClusterCandidate")`.
#' @param create Logical; must be `TRUE` to create a table that does not yet
#'   exist (defaults to `FALSE` for working `*_SU` tables and `TRUE` when
#'   `candidate = TRUE`).
#' @param overwrite Logical; must be `TRUE` to replace an existing `*_SU` table.
#' @param candidate Logical; if `TRUE`, writes a staging
#'   `<Prefix>_ClusterCandidate_SU` table (`MaterializeClusterCandidate` audit)
#'   instead of a working `*_SU` table.
#' @param actor Username recorded in `<Project>_Audit`.
#' @return Invisibly returns an updated `vpro_workspace` with `ws$su` switched
#'   to the written `*_SU` table.
#' @export
vpro_write_su <- function(
  ws,
  memberships,
  su = NULL,
  create = FALSE,
  overwrite = FALSE,
  candidate = FALSE,
  actor = Sys.info()[["user"]]
) {
  vpro_assert_workspace(ws)
  vpro_assert_writable_project_db(ws$project_path, con = ws)

  is_candidate <- isTRUE(candidate)
  if (missing(create) && is_candidate) {
    create <- TRUE
  }
  if (is_candidate) {
    if (is.null(su)) {
      base <- if (grepl("master", ws$project, ignore.case = TRUE)) "Proj" else trimws(enc2utf8(as.character(ws$project)))
      raw_nm <- paste0(substr(base, 1L, 14L), "_ClusterCandidate")
    } else {
      if (!is.character(su) || length(su) != 1L || is.na(su) || !nzchar(trimws(su))) {
        rlang::abort("`su` must be a single non-empty character string.")
      }
      raw_nm <- trimws(enc2utf8(su))
      vpro_assert_safe_prefix(raw_nm, raw_nm, ws$project, kind = "candidate_su")
      base <- sub("_SU$", "", raw_nm, ignore.case = TRUE)
      base <- sub("_ClusterCandidate$", "", base, ignore.case = TRUE)
      if (!nzchar(base)) {
        base <- if (grepl("master", ws$project, ignore.case = TRUE)) "Proj" else trimws(enc2utf8(as.character(ws$project)))
      }
    }
    if (!validUTF8(base) || !grepl("^[A-Za-z][A-Za-z0-9_]*$", base)) {
      rlang::abort(paste0(
        "Candidate prefix `",
        base,
        "` must start with an ASCII letter and contain only ASCII letters, digits, or underscores (max 14 characters)."
      ))
    }
    if (tolower(base) %in% c("none", "filtered", "usyssutabledynamic") || grepl("^usys", base, ignore.case = TRUE)) {
      rlang::abort(paste0("Candidate prefix `", base, "` is reserved by VPro."))
    }
    if (nchar(base) > 14L) {
      base <- substr(base, 1L, 14L)
    }
    if (tolower(base) %in% c("none", "filtered") || !grepl("^[A-Za-z][A-Za-z0-9_]{0,13}$", base)) {
      rlang::abort(paste0(
        "Candidate prefix `",
        base,
        "` must start with an ASCII letter and contain only ASCII letters, digits, or underscores (max 14 characters)."
      ))
    }
    cand_prefix <- paste0(base, "_ClusterCandidate")
    target_table <- paste0(cand_prefix, "_SU")
    vpro_assert_safe_prefix(cand_prefix, target_table, ws$project, kind = "candidate_su")
  } else {
    if (is.null(su)) {
      rlang::abort("`su` must be a single non-empty character string when `candidate = FALSE`.")
    }
    if (!is.character(su) || length(su) != 1L || is.na(su) || !nzchar(trimws(su))) {
      rlang::abort("`su` must be a single non-empty character string.")
    }
    raw_nm <- trimws(enc2utf8(su))
    base <- sub("_SU$", "", raw_nm, ignore.case = TRUE)
    target_table <- paste0(base, "_SU")
    vpro_assert_safe_prefix(raw_nm, target_table, ws$project, kind = "su")
    if (tolower(base) %in% c("none", "usyssutabledynamic", "filtered")) {
      rlang::abort(paste0("Target SU name `", base, "` is reserved by VPro."))
    }
    if (grepl("_clustercandidate$", base, ignore.case = TRUE)) {
      rlang::abort(
        "Pass `candidate = TRUE` to `vpro_write_su()` when writing `*_ClusterCandidate_SU` staging tables."
      )
    }
    if (!grepl("^[A-Za-z][A-Za-z0-9_]{0,30}$", base)) {
      rlang::abort(paste0(
        "Target SU name `",
        base,
        "` must start with an ASCII letter, contain only ASCII letters, digits, or underscores, and be at most 31 characters."
      ))
    }
  }

  clean_df <- vpro_extract_su_memberships(memberships)
  actor_clean <- vpro_normalize_actor(actor)

  written_table <- vpro_with_immediate_tx(ws$project_path, con = ws, fn = function(dbc) {
    existing <- vpro_find_existing_table_ci(dbc, target_table)
    if (is.null(existing) && !isTRUE(create)) {
      rlang::abort(paste0(
        "Target SU table `",
        target_table,
        "` does not exist; set `create = TRUE` to create a new working `*_SU` table."
      ))
    }
    if (!is.null(existing) && !isTRUE(overwrite)) {
      rlang::abort(paste0(
        "Target SU table `",
        existing,
        "` already exists; set `overwrite = TRUE` to replace it."
      ))
    }

    actual_tbl <- if (is.null(existing)) target_table else existing
    q_tbl <- vpro_quote_ident(actual_tbl)
    q_uidx <- vpro_quote_ident(paste0("uidx_", actual_tbl, "_PlotNumber"))
    q_idx <- vpro_quote_ident(paste0("idx_", actual_tbl, "_SiteUnit"))

    if (!is.null(existing)) {
      DBI::dbExecute(dbc, paste0("DROP TABLE IF EXISTS main.", q_tbl))
    }
    DBI::dbExecute(dbc, paste0("CREATE TABLE main.", q_tbl, ' ("PlotNumber" VARCHAR, "SiteUnit" VARCHAR)'))
    DBI::dbExecute(dbc, paste0("CREATE UNIQUE INDEX IF NOT EXISTS main.", q_uidx, " ON ", q_tbl, ' ("PlotNumber")'))
    DBI::dbExecute(dbc, paste0("CREATE INDEX IF NOT EXISTS main.", q_idx, " ON ", q_tbl, ' ("SiteUnit")'))
    vpro_upsert_table_metadata_in_tx(dbc, actual_tbl, "VP04")

    DBI::dbExecute(
      dbc,
      paste0("INSERT INTO main.", q_tbl, ' ("PlotNumber", "SiteUnit") VALUES (?, ?)'),
      params = list(clean_df$PlotNumber, clean_df$SiteUnit)
    )

    before_desc <- if (is.null(existing)) "created" else "overwritten (confirmed)"
    action_nm <- if (is_candidate) "MaterializeClusterCandidate" else "WriteWorkingSU"
    after_desc <- if (is_candidate) {
      sprintf("%d plots", nrow(clean_df))
    } else {
      sprintf("%d plots (%d units)", nrow(clean_df), length(unique(clean_df$SiteUnit)))
    }
    vpro_append_project_audit_in_tx(
      dbc = dbc,
      project_name = ws$project,
      actor = actor_clean,
      table_name = actual_tbl,
      edit_field = action_nm,
      before_val = before_desc,
      after_val = after_desc
    )
    details_list <- if (is_candidate) {
      list(
        tableName = actual_tbl,
        rows = nrow(clean_df),
        overwrote = !is.null(existing),
        actor = actor_clean
      )
    } else {
      list(
        tableName = actual_tbl,
        overwrote = !is.null(existing),
        rows = nrow(clean_df),
        units = length(unique(clean_df$SiteUnit)),
        actor = actor_clean
      )
    }
    vpro_append_rsidecar_history_in_tx(
      dbc = dbc,
      action = action_nm,
      details = details_list
    )
    actual_tbl
  })

  ws_next <- ws
  ws_next$su_path <- ws$project_path
  ws_out <- vpro_use(ws_next, su = written_table)
  ws_out$table <- written_table
  invisible(ws_out)
}

#' Write or replace a taxonomic lumping (`*_Lump`) table
#'
#' Validates `LumpCode` (up to 50 characters), `SppCode` (up to 8 characters,
#' unique, and distinct from `LumpCode`), normalizes `Use` to VPro's boolean
#' format, and saves `<lump>_Lump` alongside project metadata and audit history
#' in one safe transaction.
#'
#' @param ws A `vpro_workspace` handle referencing a writable user `.db`.
#' @param lump_df A `data.frame` containing `LumpCode`, `SppCode`, and optional
#'   `Use` (defaults to `TRUE` when omitted).
#' @param lump Target lump table name (with or without `_Lump` suffix).
#' @param create Logical; if `TRUE` (default), allows creating a new `*_Lump` table.
#' @param overwrite Logical; must be `TRUE` to replace an existing `*_Lump` table.
#' @param actor Username recorded in `<Project>_Audit`.
#' @return Invisibly returns an updated `vpro_workspace` with `ws$lump` switched
#'   to the written `*_Lump` table.
#' @export
vpro_write_lump <- function(
  ws,
  lump_df,
  lump,
  create = TRUE,
  overwrite = FALSE,
  actor = Sys.info()[["user"]]
) {
  vpro_assert_workspace(ws)
  vpro_assert_writable_project_db(ws$project_path, con = ws)

  if (!is.character(lump) || length(lump) != 1L || is.na(lump) || !nzchar(trimws(lump))) {
    rlang::abort("`lump` must be a single non-empty character string.")
  }
  raw_nm <- trimws(lump)
  base <- sub("_Lump$", "", raw_nm, ignore.case = TRUE)
  target_table <- paste0(base, "_Lump")

  vpro_assert_safe_prefix(raw_nm, target_table, ws$project, kind = "lump")

  if (tolower(base) %in% c("none", "combinedspp", "attribute", "filtered")) {
    rlang::abort(paste0("Lump table name `", base, "` is reserved by VPro."))
  }
  if (!grepl("^[A-Za-z][A-Za-z0-9_]{0,30}$", base)) {
    rlang::abort(paste0(
      "Lump table name `",
      base,
      "` must start with an ASCII letter, contain only ASCII letters, digits, or underscores, and be at most 31 characters."
    ))
  }

  if (!is.data.frame(lump_df)) {
    rlang::abort("`lump_df` must be a `data.frame` containing `LumpCode` and `SppCode` columns.")
  }
  nms_low <- tolower(names(lump_df))
  l_ix <- match("lumpcode", nms_low)
  s_ix <- match("sppcode", nms_low)
  u_ix <- match("use", nms_low)
  if (is.na(l_ix) || is.na(s_ix)) {
    rlang::abort("`lump_df` must contain `LumpCode` and `SppCode` columns.")
  }

  n_rows <- nrow(lump_df)
  if (n_rows > 0L) {
    raw_lump <- lump_df[[l_ix]]
    raw_spp <- lump_df[[s_ix]]
    if (anyNA(raw_lump) || anyNA(raw_spp)) {
      rlang::abort("`LumpCode` and `SppCode` must not contain `NA` values.")
    }
    clean_lump <- toupper(trimws(as.character(raw_lump)))
    clean_spp <- toupper(trimws(as.character(raw_spp)))
    if (any(!nzchar(clean_lump)) || any(!nzchar(clean_spp))) {
      rlang::abort("`LumpCode` and `SppCode` must not be blank.")
    }
    u16_lump <- vpro_utf16_len(clean_lump)
    u16_spp <- vpro_utf16_len(clean_spp)
    if (anyNA(u16_lump) || anyNA(u16_spp)) {
      rlang::abort("`LumpCode` and `SppCode` must be valid UTF-8 without unpaired surrogates.")
    }
    if (any(u16_lump > 50L)) {
      bad_l <- clean_lump[which(u16_lump > 50L)[[1L]]]
      rlang::abort(paste0("`LumpCode` '", bad_l, "' exceeds the 50-character limit."))
    }
    if (any(u16_spp > 8L)) {
      bad_s <- clean_spp[which(u16_spp > 8L)[[1L]]]
      rlang::abort(paste0("`SppCode` '", bad_s, "' exceeds the 8-character limit (8 UTF-16 code units)."))
    }
    if (any(clean_lump == clean_spp)) {
      same_c <- clean_spp[which(clean_lump == clean_spp)[[1L]]]
      rlang::abort(paste0("`LumpCode` and `SppCode` cannot be identical ('", same_c, "')."))
    }
    if (anyDuplicated(clean_spp) > 0L) {
      dup_s <- clean_spp[duplicated(clean_spp)][[1L]]
      rlang::abort(paste0("`SppCode` must be unique in `*_Lump`; duplicate '", dup_s, "' found."))
    }
    use_int <- if (is.na(u_ix)) {
      rep(-1L, n_rows)
    } else {
      conv <- vpro_logical_to_access(lump_df[[u_ix]])
      conv[is.na(conv)] <- 0L
      as.integer(conv)
    }
  } else {
    clean_lump <- character()
    clean_spp <- character()
    use_int <- integer()
  }

  actor_clean <- vpro_normalize_actor(actor)

  written_table <- vpro_with_immediate_tx(ws$project_path, con = ws, fn = function(dbc) {
    existing <- vpro_find_existing_table_ci(dbc, target_table)
    if (is.null(existing) && !isTRUE(create)) {
      rlang::abort(paste0(
        "Target lump table `",
        target_table,
        "` does not exist; set `create = TRUE` to create it."
      ))
    }
    if (!is.null(existing) && !isTRUE(overwrite)) {
      rlang::abort(paste0(
        "Target lump table `",
        existing,
        "` already exists; set `overwrite = TRUE` to confirm replacing it."
      ))
    }

    actual_tbl <- if (is.null(existing)) target_table else existing
    actual_base <- sub("_Lump$", "", actual_tbl, ignore.case = TRUE)
    q_tbl <- vpro_quote_ident(actual_tbl)
    q_idx <- vpro_quote_ident(paste0("idx_", actual_base, "_Lump_LumpCode"))
    q_uidx <- vpro_quote_ident(paste0("uidx_", actual_base, "_Lump_SppCode"))

    if (!is.null(existing)) {
      DBI::dbExecute(dbc, paste0("DROP TABLE IF EXISTS main.", q_tbl))
    }
    DBI::dbExecute(
      dbc,
      paste0("CREATE TABLE main.", q_tbl, ' ("LumpCode" VARCHAR(50), "SppCode" VARCHAR(8) UNIQUE, "Use" BOOLEAN)')
    )
    DBI::dbExecute(dbc, paste0("CREATE INDEX IF NOT EXISTS main.", q_idx, " ON ", q_tbl, ' ("LumpCode")'))
    DBI::dbExecute(dbc, paste0("CREATE UNIQUE INDEX IF NOT EXISTS main.", q_uidx, " ON ", q_tbl, ' ("SppCode")'))
    vpro_upsert_table_metadata_in_tx(dbc, actual_tbl, "VP05")

    if (n_rows > 0L) {
      DBI::dbExecute(
        dbc,
        paste0("INSERT INTO main.", q_tbl, ' ("LumpCode", "SppCode", "Use") VALUES (?, ?, ?)'),
        params = list(clean_lump, clean_spp, use_int)
      )
    }

    n_active <- sum(use_int == -1L)
    before_desc <- if (is.null(existing)) "created" else "overwritten (confirmed)"
    vpro_append_project_audit_in_tx(
      dbc = dbc,
      project_name = ws$project,
      actor = actor_clean,
      table_name = actual_tbl,
      edit_field = "WriteLumpTable",
      before_val = before_desc,
      after_val = sprintf("%d mappings (%d active)", n_rows, n_active)
    )
    vpro_append_rsidecar_history_in_tx(
      dbc = dbc,
      action = "WriteLumpTable",
      details = list(
        tableName = actual_tbl,
        overwrote = !is.null(existing),
        rows = n_rows,
        activeRows = n_active,
        distinctLumpCodes = length(unique(clean_lump)),
        actor = actor_clean
      )
    )
    actual_tbl
  })

  ws_next <- ws
  ws_next$lump_path <- ws$project_path
  ws_out <- vpro_use(ws_next, lump = written_table)
  ws_out$table <- written_table
  invisible(ws_out)
}
