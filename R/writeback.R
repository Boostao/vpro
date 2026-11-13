# Guarded Non-Destructive Transactional SQLite WAL Write-Back ------------------

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

.vpro_identity_seq_ddl <- paste(
  'CREATE TABLE IF NOT EXISTS main."__VPRO_IdentitySeq" (',
  '  "TableName" TEXT PRIMARY KEY,',
  '  "LastID" INTEGER NOT NULL',
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
  if (vpro_is_bundled_package_path(db_path) ||
      (!is.null(con) && identical(con$source, "sample") &&
       identical(
         normalizePath(db_path, winslash = "/", mustWork = FALSE),
         normalizePath(vpro_bundled_db("Sample.db"), winslash = "/", mustWork = FALSE)
       ))) {
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
  on.exit({
    if (tx_started && !committed && DBI::dbIsValid(dbc)) {
      tryCatch(DBI::dbExecute(dbc, "ROLLBACK"), error = function(e) NULL)
    }
    if (DBI::dbIsValid(dbc)) {
      DBI::dbDisconnect(dbc)
    }
  }, add = TRUE)

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

  # Hard refusal guards: Master* / master, USys*, BECSiteUnit, core VP08 tables
  if (grepl("master", nm, ignore.case = TRUE) || grepl("master", ft, ignore.case = TRUE)) {
    rlang::abort(paste0(
      "Refusing write-back to Master-protected table `", ft, "` (`Master*` prefixes are read-only)."
    ))
  }
  if (grepl("^usys", nm, ignore.case = TRUE) || grepl("^usys", ft, ignore.case = TRUE)) {
    rlang::abort(paste0(
      "Refusing write-back to system table/view `", ft, "` (`USys*` objects are protected)."
    ))
  }
  if (grepl("^becsiteunit(_su|_lump)?$", nm, ignore.case = TRUE) ||
      grepl("^becsiteunit(_su|_lump)?$", ft, ignore.case = TRUE)) {
    rlang::abort(paste0(
      "Refusing write-back to custodian-locked table `", ft, "` (`BECSiteUnit` is protected)."
    ))
  }

  core_pat <- paste0("_(", paste(.vpro_core_project_suffixes, collapse = "|"), ")$")
  if (grepl(core_pat, nm, ignore.case = TRUE) || grepl(core_pat, ft, ignore.case = TRUE)) {
    rlang::abort(paste0(
      "Refusing write-back targeting core VP08 table `", ft, "`."
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
      "`", arg, "` must be a literal `character` vector (never numeric) to preserve leading zeroes such as '00337'."
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
      "`", arg, "` value '", bad, "' exceeds VPro's 7 UTF-16 code-unit limit."
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
  if (is.na(p_ix)) p_ix <- match("plot", nms_low)
  if (is.na(p_ix)) p_ix <- match("plot_number", nms_low)
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
    rlang::abort("`SiteUnit` values must be valid UTF-8 up to 50 UTF-16 code units.")
  }

  tibble::tibble(
    PlotNumber = raw_plots,
    SiteUnit = units_chr
  )
}

vpro_reserve_next_id_in_tx <- function(dbc, table_name, id_col = "ID") {
  DBI::dbExecute(dbc, .vpro_identity_seq_ddl)
  cur_seq <- DBI::dbGetQuery(
    dbc,
    'SELECT "LastID" FROM main."__VPRO_IdentitySeq" WHERE "TableName" = ?',
    params = list(table_name)
  )
  last_seq <- if (nrow(cur_seq) > 0L && !is.na(cur_seq$LastID[[1L]])) {
    as.numeric(cur_seq$LastID[[1L]])
  } else {
    0
  }
  qt <- vpro_quote_ident(table_name)
  qid <- vpro_quote_ident(id_col)
  max_df <- DBI::dbGetQuery(
    dbc,
    paste0("SELECT COALESCE(MAX(CAST(", qid, " AS INTEGER)), 0) AS max_id FROM main.", qt)
  )
  max_tbl <- if (nrow(max_df) > 0L && !is.na(max_df$max_id[[1L]])) {
    as.numeric(max_df$max_id[[1L]])
  } else {
    0
  }
  next_val <- max(last_seq, max_tbl, 0) + 1
  next_int <- as.integer(min(next_val, .Machine$integer.max))
  DBI::dbExecute(
    dbc,
    'INSERT OR REPLACE INTO main."__VPRO_IdentitySeq" ("TableName", "LastID") VALUES (?, ?)',
    params = list(table_name, next_int)
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
  plot_number = NA_character_
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
    next_id <- vpro_reserve_next_id_in_tx(dbc, actual_audit, id_col = "ID")
    DBI::dbExecute(
      dbc,
      paste0(
        "INSERT INTO main.", q_audit,
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
        next_id
      )
    )
  } else {
    DBI::dbExecute(
      dbc,
      paste0(
        "INSERT INTO main.", q_audit,
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

#' Materialize a staging `*_ClusterCandidate_SU` table atomically
#'
#' Writes cluster or candidate site-unit memberships to
#' `<Prefix>_ClusterCandidate_SU` inside `con$project_path` using a `BEGIN IMMEDIATE`
#' WAL transaction, registers `_table_metadata` (`'VP04'`), appends provenance
#' to `<Project>_Audit` and `__VPRO_RSidecarHistory`, and returns an updated
#' `vpro_workspace` handle pointing at the candidate SU table.
#'
#' @param con A `vpro_workspace` handle referencing a writable user `.db`.
#' @param memberships A `vpro_clusters` object or a `data.frame` containing
#'   literal character `PlotNumber` and `SiteUnit` (or `Cluster`).
#' @param name Candidate table prefix or name (defaults to
#'   `paste0(con$project, "_ClusterCandidate")`).
#' @param overwrite Logical; if `TRUE` (default), replaces an existing
#'   `<Prefix>_ClusterCandidate_SU` staging table.
#' @param actor Username recorded in `<Project>_Audit`.
#' @return Invisibly returns an updated `vpro_workspace` with `con$su` switched
#'   to the newly written `<Prefix>_ClusterCandidate_SU` table.
#' @export
vpro_write_candidate_su <- function(
  con,
  memberships,
  name = paste0(con$project, "_ClusterCandidate"),
  overwrite = TRUE,
  actor = Sys.info()[["user"]]
) {
  vpro_assert_workspace(con)
  vpro_assert_writable_project_db(con$project_path, con = con)

  if (!is.character(name) || length(name) != 1L || is.na(name) || !nzchar(trimws(name))) {
    rlang::abort("`name` must be a single non-empty character string.")
  }
  raw_nm <- trimws(name)
  base <- sub("_SU$", "", raw_nm, ignore.case = TRUE)
  base <- sub("_ClusterCandidate$", "", base, ignore.case = TRUE)

  cand_prefix <- paste0(base, "_ClusterCandidate")
  target_table <- paste0(cand_prefix, "_SU")
  vpro_assert_safe_prefix(raw_nm, target_table, con$project, kind = "candidate_su")

  if (tolower(base) %in% c("none", "filtered")) {
    rlang::abort(paste0("Candidate prefix `", base, "` is reserved by VPro."))
  }
  if (!grepl("^[A-Za-z][A-Za-z0-9_]{0,13}$", base)) {
    rlang::abort(paste0(
      "Candidate prefix `", base,
      "` must start with an ASCII letter, contain only ASCII letters, digits, or underscores, and be at most 14 characters."
    ))
  }

  clean_df <- vpro_extract_su_memberships(memberships)
  actor_clean <- vpro_normalize_actor(actor)

  written_table <- vpro_with_immediate_tx(con$project_path, con = con, fn = function(dbc) {
    existing <- vpro_find_existing_table_ci(dbc, target_table)
    if (!is.null(existing) && !isTRUE(overwrite)) {
      rlang::abort(paste0(
        "Candidate SU table `", existing, "` already exists; set `overwrite = TRUE` to replace it."
      ))
    }

    if (!is.null(existing)) {
      DBI::dbExecute(dbc, paste0("DROP TABLE IF EXISTS main.", vpro_quote_ident(existing)))
    }
    q_tbl <- vpro_quote_ident(target_table)
    q_uidx <- vpro_quote_ident(paste0("uidx_", target_table, "_PlotNumber"))
    q_idx <- vpro_quote_ident(paste0("idx_", target_table, "_SiteUnit"))

    DBI::dbExecute(dbc, paste0("CREATE TABLE main.", q_tbl, ' ("PlotNumber" VARCHAR, "SiteUnit" VARCHAR)'))
    DBI::dbExecute(dbc, paste0("CREATE UNIQUE INDEX main.", q_uidx, " ON ", q_tbl, ' ("PlotNumber")'))
    DBI::dbExecute(dbc, paste0("CREATE INDEX main.", q_idx, " ON ", q_tbl, ' ("SiteUnit")'))
    vpro_upsert_table_metadata_in_tx(dbc, target_table, "VP04")

    DBI::dbExecute(
      dbc,
      paste0("INSERT INTO main.", q_tbl, ' ("PlotNumber", "SiteUnit") VALUES (?, ?)'),
      params = list(clean_df$PlotNumber, clean_df$SiteUnit)
    )

    before_desc <- if (is.null(existing)) "created" else "overwritten"
    vpro_append_project_audit_in_tx(
      dbc = dbc,
      project_name = con$project,
      actor = actor_clean,
      table_name = target_table,
      edit_field = "MaterializeClusterCandidate",
      before_val = before_desc,
      after_val = sprintf("%d plots", nrow(clean_df))
    )
    vpro_append_rsidecar_history_in_tx(
      dbc = dbc,
      action = "MaterializeClusterCandidate",
      details = list(
        tableName = target_table,
        rows = nrow(clean_df),
        overwrote = !is.null(existing),
        actor = actor_clean
      )
    )
    target_table
  })

  con_next <- con
  con_next$su_path <- con$project_path
  invisible(vpro_use(con_next, su = written_table))
}

#' Write or replace a working `*_SU` site-unit table atomically
#'
#' Persists plot-to-SiteUnit assignments to `<su_name>_SU` inside
#' `con$project_path` under `BEGIN IMMEDIATE`, strictly refusing `Master*`,
#' `USys*`, `BECSiteUnit`, and core `VP08` tables. Requires `create = TRUE` when
#' creating a new `*_SU` table and `confirm_overwrite = TRUE` when replacing an
#' existing `*_SU` table.
#'
#' @param con A `vpro_workspace` handle referencing a writable user `.db`.
#' @param memberships A `vpro_clusters` object or `data.frame(PlotNumber, SiteUnit)`.
#' @param su_name Target working site-unit name (with or without `_SU` suffix).
#' @param create Logical; must be `TRUE` to create a table that does not yet exist.
#' @param confirm_overwrite Logical; must be `TRUE` to overwrite an existing `*_SU` table.
#' @param actor Username recorded in `<Project>_Audit`.
#' @return Invisibly returns an updated `vpro_workspace` with `con$su` switched
#'   to the written `*_SU` table.
#' @export
vpro_write_su <- function(
  con,
  memberships,
  su_name,
  create = FALSE,
  confirm_overwrite = FALSE,
  actor = Sys.info()[["user"]]
) {
  vpro_assert_workspace(con)
  vpro_assert_writable_project_db(con$project_path, con = con)

  if (!is.character(su_name) || length(su_name) != 1L || is.na(su_name) || !nzchar(trimws(su_name))) {
    rlang::abort("`su_name` must be a single non-empty character string.")
  }
  raw_nm <- trimws(su_name)
  base <- sub("_SU$", "", raw_nm, ignore.case = TRUE)
  target_table <- paste0(base, "_SU")

  vpro_assert_safe_prefix(raw_nm, target_table, con$project, kind = "su")

  if (tolower(base) %in% c("none", "usyssutabledynamic", "filtered")) {
    rlang::abort(paste0("Target SU name `", base, "` is reserved by VPro."))
  }
  if (grepl("_clustercandidate$", base, ignore.case = TRUE)) {
    rlang::abort(
      "Use `vpro_write_candidate_su()` when writing `*_ClusterCandidate_SU` staging tables."
    )
  }
  if (!grepl("^[A-Za-z][A-Za-z0-9_]{0,30}$", base)) {
    rlang::abort(paste0(
      "Target SU name `", base,
      "` must start with an ASCII letter, contain only ASCII letters, digits, or underscores, and be at most 31 characters."
    ))
  }

  clean_df <- vpro_extract_su_memberships(memberships)
  actor_clean <- vpro_normalize_actor(actor)

  written_table <- vpro_with_immediate_tx(con$project_path, con = con, fn = function(dbc) {
    existing <- vpro_find_existing_table_ci(dbc, target_table)
    if (is.null(existing) && !isTRUE(create)) {
      rlang::abort(paste0(
        "Target SU table `", target_table,
        "` does not exist; set `create = TRUE` to create a new working `*_SU` table."
      ))
    }
    if (!is.null(existing) && !isTRUE(confirm_overwrite)) {
      rlang::abort(paste0(
        "Target SU table `", existing,
        "` already exists; set `confirm_overwrite = TRUE` to confirm replacing it."
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
    vpro_append_project_audit_in_tx(
      dbc = dbc,
      project_name = con$project,
      actor = actor_clean,
      table_name = actual_tbl,
      edit_field = "WriteWorkingSU",
      before_val = before_desc,
      after_val = sprintf("%d plots (%d units)", nrow(clean_df), length(unique(clean_df$SiteUnit)))
    )
    vpro_append_rsidecar_history_in_tx(
      dbc = dbc,
      action = "WriteWorkingSU",
      details = list(
        tableName = actual_tbl,
        overwrote = !is.null(existing),
        rows = nrow(clean_df),
        units = length(unique(clean_df$SiteUnit)),
        actor = actor_clean
      )
    )
    actual_tbl
  })

  con_next <- con
  con_next$su_path <- con$project_path
  invisible(vpro_use(con_next, su = written_table))
}

#' Write or replace a taxonomic lumping (`*_Lump`) table atomically
#'
#' Validates `LumpCode` (`<= 50` UTF-16 code units), `SppCode` (`<= 8` UTF-16
#' code units, unique, distinct from `LumpCode`), and serializes `Use` to Access
#' integer booleans (`-1L` = `TRUE`, `0L` = `FALSE`). Writes `<lump_name>_Lump`
#' + `_table_metadata` (`'VP05'`) + `<Project>_Audit` + `__VPRO_RSidecarHistory`
#' inside a `BEGIN IMMEDIATE` WAL transaction.
#'
#' @param con A `vpro_workspace` handle referencing a writable user `.db`.
#' @param lump_df A `data.frame` containing `LumpCode`, `SppCode`, and optional
#'   `Use` (defaults to `TRUE` when omitted).
#' @param lump_name Target lump table name (with or without `_Lump` suffix).
#' @param create Logical; if `TRUE` (default), allows creating a new `*_Lump` table.
#' @param confirm_overwrite Logical; must be `TRUE` to replace an existing `*_Lump` table.
#' @param actor Username recorded in `<Project>_Audit`.
#' @return Invisibly returns an updated `vpro_workspace` with `con$lump` switched
#'   to the written `*_Lump` table.
#' @export
vpro_write_lump <- function(
  con,
  lump_df,
  lump_name,
  create = TRUE,
  confirm_overwrite = FALSE,
  actor = Sys.info()[["user"]]
) {
  vpro_assert_workspace(con)
  vpro_assert_writable_project_db(con$project_path, con = con)

  if (!is.character(lump_name) || length(lump_name) != 1L || is.na(lump_name) || !nzchar(trimws(lump_name))) {
    rlang::abort("`lump_name` must be a single non-empty character string.")
  }
  raw_nm <- trimws(lump_name)
  base <- sub("_Lump$", "", raw_nm, ignore.case = TRUE)
  target_table <- paste0(base, "_Lump")

  vpro_assert_safe_prefix(raw_nm, target_table, con$project, kind = "lump")

  if (tolower(base) %in% c("none", "combinedspp", "attribute", "filtered")) {
    rlang::abort(paste0("Lump table name `", base, "` is reserved by VPro."))
  }
  if (!grepl("^[A-Za-z][A-Za-z0-9_]{0,30}$", base)) {
    rlang::abort(paste0(
      "Lump table name `", base,
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
      rlang::abort(paste0("`LumpCode` '", bad_l, "' exceeds 50 UTF-16 code units."))
    }
    if (any(u16_spp > 8L)) {
      bad_s <- clean_spp[which(u16_spp > 8L)[[1L]]]
      rlang::abort(paste0("`SppCode` '", bad_s, "' exceeds 8 UTF-16 code units."))
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

  written_table <- vpro_with_immediate_tx(con$project_path, con = con, fn = function(dbc) {
    existing <- vpro_find_existing_table_ci(dbc, target_table)
    if (is.null(existing) && !isTRUE(create)) {
      rlang::abort(paste0(
        "Target lump table `", target_table,
        "` does not exist; set `create = TRUE` to create it."
      ))
    }
    if (!is.null(existing) && !isTRUE(confirm_overwrite)) {
      rlang::abort(paste0(
        "Target lump table `", existing,
        "` already exists; set `confirm_overwrite = TRUE` to confirm replacing it."
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
      project_name = con$project,
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

  con_next <- con
  con_next$lump_path <- con$project_path
  invisible(vpro_use(con_next, lump = written_table))
}
