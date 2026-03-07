# =============================================================================
# logic_sync.R
# Bidirectional sync engine: local DuckDB <-> master PostgreSQL (cloud)
# =============================================================================
#
# Architecture
# ─────────────
#   Local DuckDB  = offline working copy for field users
#   Master PG     = cloud source of truth, attached as catalog alias `master`
#                   via DuckDB's native ATTACH ... (TYPE POSTGRES)
#
# Data flow
# ─────────
#   PULL  master.core.{table}  ──► Env / SU / Veg (local DuckDB)
#         master.lists.{table} ──► local lists attachment (full replace, no conflict)
#   PUSH  Env / SU / Veg       ──► master.staging.{table}
#                                     └─► admin review
#                                           └─► master.core.{table}
#
# Conflict model
# ───────────────
#   PULL conflict  (local, resolved by field user)
#     Occurs when an incoming master row has a higher row_version than
#     `master_row_version` stored in the local row AND the values differ.
#     Logged to sync.conflict_queue. User must resolve before pushing.
#
#   PUSH conflict  (server, resolved by admin)
#     Occurs when at review time master.core.row_version is higher than
#     the staging.base_row_version captured at push time (master was
#     updated after the user's last sync).
#     Logged to master.admin.merge_conflicts. Admin resolves during review.
#
# Naming conventions
# ───────────────────
#   master.core.env      production PostgreSQL data
#   master.staging.env   pending uploads awaiting admin review
#   master.admin.*       governance tables (merge requests, conflicts)
#   Env / SU / Veg       local DuckDB field tables (PascalCase)
# =============================================================================

# NULL-coalescing operator (safe to define; rlang may already export this)
if (!exists("%||%", inherits = FALSE)) {
  `%||%` <- function(x, y) if (!is.null(x)) x else y
}


# =============================================================================
# 1. Cloud connectivity
# =============================================================================

#' Check whether the cloud master database is currently attached.
#'
#' @param con   DuckDB connection.
#' @param alias Character. Catalog alias for the attached master. Default "master".
#' @return Logical.
sync_cloud_connected <- function(con, alias = "master") {
  tryCatch({
    dbs <- DBI::dbGetQuery(con, "SELECT database_name FROM duckdb_databases()")$database_name
    alias %in% dbs
  }, error = function(e) FALSE)
}

#' Ensure the cloud master database is attached.
#'
#' Stops with a clear message if the cloud is not attached.  Sync always
#' requires an authenticated session; auto-attach is not supported.
#'
#' @param con          DuckDB connection.
#' @param allow_attach Logical. Unused; kept for backward compatibility.
#' @param alias        Character. Expected catalog alias.
sync_require_cloud <- function(con, allow_attach = FALSE, alias = "master") {
  if (sync_cloud_connected(con, alias)) return(invisible(TRUE))
  stop("Cloud database '", alias, "' is not attached. Please log in first.")
}


# =============================================================================
# 2. Local sync infrastructure
# =============================================================================

#' Create the sync schema and supporting tables on the local DuckDB.
#'
#' Idempotent. Also adds `master_row_version INTEGER` to Env, SU, Veg if they
#' exist and don't already have this column.
#'
#' @param con DuckDB connection.
sync_ensure_local_tables <- function(con) {
  DBI::dbExecute(con, "CREATE SCHEMA IF NOT EXISTS sync")

  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS sync.watermarks (
      table_name    TEXT NOT NULL PRIMARY KEY,
      last_pull_utc TIMESTAMPTZ,
      last_push_utc TIMESTAMPTZ
    )
  ")

  DBI::dbExecute(con, "CREATE SEQUENCE IF NOT EXISTS sync.cq_seq START 1")

  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS sync.conflict_queue (
      id           INTEGER PRIMARY KEY DEFAULT nextval('sync.cq_seq'),
      table_name   TEXT NOT NULL,
      plot_number  TEXT NOT NULL,
      project_id   TEXT,
      species_code TEXT,
      layer_code   TEXT,
      conflict_at  TIMESTAMPTZ DEFAULT now(),
      local_values  TEXT NOT NULL,
      master_values TEXT NOT NULL,
      resolution   TEXT CHECK (resolution IN ('keep_local', 'accept_master'))
    )
  ")

  # master_row_version = the core.row_version we stored the last time we pulled
  # this row. NULL means the row is new locally (never synced from master).
  # Stays unchanged when the user edits the local row — that's the whole point:
  # it lets us detect that master has moved forward since our last pull.
  for (tbl in c("Env", "SU", "Veg")) {
    if (DBI::dbExistsTable(con, tbl)) {
      tryCatch(
        DBI::dbExecute(con, sprintf(
          "ALTER TABLE %s ADD COLUMN IF NOT EXISTS master_row_version INTEGER", tbl
        )),
        error = function(e) NULL
      )
    }
  }

  # local_modified_utc: set by the app when the user edits a row. NULL = row is
  # clean (matches what was last pulled from master). Reset to NULL on each pull.
  # This lets sync_pull distinguish "user touched this" from "user is just behind
  # master" — the latter is safe to fast-forward without user interaction.
  for (tbl in c("Env", "SU", "Veg")) {
    if (DBI::dbExistsTable(con, tbl)) {
      tryCatch(
        DBI::dbExecute(con, sprintf(
          "ALTER TABLE %s ADD COLUMN IF NOT EXISTS local_modified_utc TIMESTAMPTZ", tbl
        )),
        error = function(e) NULL
      )
    }
  }

  invisible(TRUE)
}

#' Read a pull or push watermark timestamp for a given table.
#'
#' @param con        DuckDB connection.
#' @param table_name Character.
#' @param direction  "pull" or "push".
#' @return POSIXct or NULL.
sync_get_watermark <- function(con, table_name, direction = c("pull", "push")) {
  direction <- match.arg(direction)
  col <- if (direction == "pull") "last_pull_utc" else "last_push_utc"
  if (!DBI::dbExistsTable(con, DBI::Id(schema = "sync", table = "watermarks"))) return(NULL)
  res <- tryCatch(
    DBI::dbGetQuery(
      con,
      sprintf("SELECT %s FROM sync.watermarks WHERE table_name = ?", col),
      list(table_name)
    ),
    error = function(e) data.frame()
  )
  if (nrow(res) == 0 || is.na(res[[col]][1])) return(NULL)
  res[[col]][1]
}

#' Write a pull or push watermark for a given table.
#'
#' @param con        DuckDB connection.
#' @param table_name Character.
#' @param direction  "pull" or "push".
#' @param ts         POSIXct. Defaults to now.
sync_set_watermark <- function(con, table_name, direction = c("pull", "push"),
                                ts = Sys.time()) {
  direction <- match.arg(direction)
  col <- if (direction == "pull") "last_pull_utc" else "last_push_utc"
  ts_str <- format(ts, "%Y-%m-%d %H:%M:%OS3")
  DBI::dbExecute(
    con,
    sprintf(
      "INSERT INTO sync.watermarks (table_name, %s)
       VALUES (?, ?)
       ON CONFLICT (table_name) DO UPDATE SET %s = EXCLUDED.%s",
      col, col, col
    ),
    list(table_name, ts_str)
  )
  invisible(TRUE)
}


# =============================================================================
# 3. PULL: master.core -> local
# =============================================================================

#' Pull updated records from the master database into local DuckDB tables.
#'
#' For each requested data table:
#'   - Fetches rows from master.core.{table} modified since the last pull watermark.
#'   - Fast-forwards rows where local is unchanged (master_row_version matches
#'     or local values already equal the incoming values).
#'   - Queues conflicts where both local and master have diverged since last sync.
#'
#' When "lists" is included, all reference tables in master.lists.* are copied
#' to the local `lists` catalog attachment (full replace, no conflict detection).
#' Reference lists are admin-only — field users never edit them.
#'
#' Veg is pulled using the same watermark + conflict logic as env/su. The
#' composite key is (plot_number, species_code, layer_code, project_id).
#' Useful for reporting workflows where the local DuckDB is used to generate
#' reports against a complete, up-to-date copy of master veg data.
#'
#' @param con          DuckDB connection with master attached.
#' @param project_id   Integer or character. Filters to this project if supplied.
#' @param tables       Character vector. Any of "env", "su", "veg", "lists".
#' @param allow_attach Logical. Auto-attach master if not connected.
#'
#' @return Named list. Data table entries: list(pulled, fast_forwarded, conflicts).
#'   Lists entry: list(synced_tables, skipped).
sync_pull <- function(con,
                      project_id  = NULL,
                      tables      = c("env", "su", "veg", "lists"),
                      allow_attach = TRUE) {
  sync_require_cloud(con, allow_attach = allow_attach)
  sync_ensure_local_tables(con)

  results <- list()
  if ("env"   %in% tables) results$env   <- .pull_env(con, project_id)
  if ("su"    %in% tables) results$su    <- .pull_su(con,  project_id)
  if ("veg"   %in% tables) results$veg   <- .pull_veg(con, project_id)
  if ("lists" %in% tables) results$lists <- .pull_lists(con)
  results
}

# ── internal pull helpers ────────────────────────────────────────────────────

.pull_env <- function(con, project_id) {
  if (!DBI::dbExistsTable(con, "Env")) {
    return(list(pulled = 0L, fast_forwarded = 0L, conflicts = 0L,
                skipped = TRUE, reason = "no_local_table"))
  }

  last_pull <- sync_get_watermark(con, "env", "pull")
  has_mrv   <- "master_row_version" %in% DBI::dbListFields(con, "Env")
  has_lmu   <- "local_modified_utc"  %in% DBI::dbListFields(con, "Env")

  filters <- "1=1"
  params  <- list()
  if (!is.null(project_id) && nzchar(as.character(project_id))) {
    filters <- paste0(filters, " AND \"ProjectID\" = ?")
    params  <- c(params, list(project_id))
  }
  if (!is.null(last_pull)) {
    filters <- paste0(filters, " AND \"lastModifiedUTC\" > ?")
    params  <- c(params, list(last_pull))
  }

  incoming <- tryCatch(
    DBI::dbGetQuery(
      con,
      sprintf(
        "SELECT \"PlotNumber\", \"ProjectID\", \"Latitude\", \"Longitude\", \"Elevation\",
                \"SurveyDate\", \"SurveyorName\", \"PlotNotes\", \"Zone\", \"SubZone\", \"SiteSeries\",
                \"rowVersion\"
         FROM master.core.env WHERE %s",
        filters
      ),
      params
    ),
    error = function(e) { warning("sync_pull env failed: ", e$message); data.frame() }
  )

  if (nrow(incoming) == 0) {
    sync_set_watermark(con, "env", "pull")
    return(list(pulled = 0L, fast_forwarded = 0L, conflicts = 0L))
  }

  fast_forwarded <- 0L
  conflicts      <- 0L
  env_fields     <- list(
    c("Latitude",    "Latitude"),
    c("Longitude",   "Longitude"),
    c("Elevation",   "Elevation"),
    c("Date",        "SurveyDate"),
    c("SiteSurveyor","SurveyorName"),
    c("SiteNotes",   "PlotNotes"),
    c("Zone",        "Zone"),
    c("SubZone",     "SubZone"),
    c("SiteSeries",  "SiteSeries")
  )

  for (i in seq_len(nrow(incoming))) {
    row <- incoming[i, , drop = FALSE]
    pn  <- row$plot_number[1]
    pid <- as.character(row$project_id[1])

    lmu_col   <- if (has_lmu) ", local_modified_utc" else ""
    local_row <- tryCatch(
      DBI::dbGetQuery(
        con,
        sprintf(
          "SELECT PlotNumber, ProjectID, Latitude, Longitude, Elevation, Date,
                  SiteSurveyor, SiteNotes, master_row_version%s
           FROM Env WHERE PlotNumber = ?",
          lmu_col
        ),
        list(pn)
      ),
      error = function(e) data.frame()
    )

    if (nrow(local_row) == 0) {
      # Brand-new master record — insert locally
      .upsert_local_env(con, row, has_mrv, has_lmu)
      fast_forwarded <- fast_forwarded + 1L
      next
    }

    local_mrv <- if (has_mrv) local_row$master_row_version[1] else NA_integer_
    master_rv <- row$row_version[1]

    # Master has not moved since last pull — nothing to do
    if (!is.na(local_mrv) && !is.na(master_rv) &&
        identical(as.integer(local_mrv), as.integer(master_rv))) {
      next
    }

    values_differ <- .values_differ(local_row, row, env_fields)

    if (!values_differ) {
      # Values already converged (e.g. master applied a previous push) — safe update
      .upsert_local_env(con, row, has_mrv, has_lmu)
      fast_forwarded <- fast_forwarded + 1L
    } else if (is.na(local_mrv)) {
      # Local row was created offline (never pulled) — fast-forward, master wins
      .upsert_local_env(con, row, has_mrv, has_lmu)
      fast_forwarded <- fast_forwarded + 1L
    } else {
      # Master moved AND values differ: only a TRUE conflict if user dirtied the row
      local_dirty <- has_lmu && !is.na(local_row$local_modified_utc[1])
      if (!local_dirty) {
        # Row was never modified locally since last pull — safe to fast-forward
        .upsert_local_env(con, row, has_mrv, has_lmu)
        fast_forwarded <- fast_forwarded + 1L
      } else {
        # TRUE conflict: master row_version moved AND user has local edits
        local_vals <- list(
          Latitude     = local_row$Latitude[1],
          Longitude    = local_row$Longitude[1],
          Elevation    = local_row$Elevation[1],
          Date         = as.character(local_row$Date[1]),
          SiteSurveyor = local_row$SiteSurveyor[1],
          SiteNotes    = local_row$SiteNotes[1]
        )
        master_vals <- list(
          Latitude      = row$Latitude[1],
          Longitude     = row$Longitude[1],
          Elevation     = row$Elevation[1],
          SurveyDate    = as.character(row$SurveyDate[1]),
          SurveyorName  = row$SurveyorName[1],
          PlotNotes     = row$PlotNotes[1]
        )
        .queue_conflict(con, "env", pn, pid, NA, NA, local_vals, master_vals)
        conflicts <- conflicts + 1L
      }
    }
  }

  sync_set_watermark(con, "env", "pull")
  list(pulled = nrow(incoming), fast_forwarded = fast_forwarded, conflicts = conflicts)
}

.pull_su <- function(con, project_id) {
  if (!DBI::dbExistsTable(con, "SU")) {
    return(list(pulled = 0L, fast_forwarded = 0L, conflicts = 0L,
                skipped = TRUE, reason = "no_local_table"))
  }

  last_pull <- sync_get_watermark(con, "su", "pull")
  has_mrv   <- "master_row_version" %in% DBI::dbListFields(con, "SU")
  has_lmu   <- "local_modified_utc"  %in% DBI::dbListFields(con, "SU")

  filters <- "1=1"
  params  <- list()
  if (!is.null(project_id) && nzchar(as.character(project_id))) {
    filters <- paste0(filters, " AND \"ProjectID\" = ?")
    params  <- c(params, list(project_id))
  }
  if (!is.null(last_pull)) {
    filters <- paste0(filters, " AND \"lastModifiedUTC\" > ?")
    params  <- c(params, list(last_pull))
  }

  incoming <- tryCatch(
    DBI::dbGetQuery(
      con,
      sprintf("SELECT \"PlotNumber\", \"ProjectID\", \"SiteUnit\", \"rowVersion\"
               FROM master.core.su WHERE %s", filters),
      params
    ),
    error = function(e) { warning("sync_pull su failed: ", e$message); data.frame() }
  )

  if (nrow(incoming) == 0) {
    sync_set_watermark(con, "su", "pull")
    return(list(pulled = 0L, fast_forwarded = 0L, conflicts = 0L))
  }

  fast_forwarded <- 0L
  conflicts      <- 0L
  su_fields      <- list(c("SiteUnit", "SiteUnit"))

  for (i in seq_len(nrow(incoming))) {
    row <- incoming[i, , drop = FALSE]
    pn  <- row$PlotNumber[1]
    pid <- as.character(row$ProjectID[1])

    lmu_col   <- if (has_lmu) ", local_modified_utc" else ""
    local_row <- tryCatch(
      DBI::dbGetQuery(
        con,
        sprintf("SELECT PlotNumber, SiteUnit, master_row_version%s FROM SU WHERE PlotNumber = ?",
                lmu_col),
        list(pn)
      ),
      error = function(e) data.frame()
    )

    if (nrow(local_row) == 0) {
      .upsert_local_su(con, row, has_mrv, has_lmu)
      fast_forwarded <- fast_forwarded + 1L
      next
    }

    local_mrv <- if (has_mrv) local_row$master_row_version[1] else NA_integer_
    master_rv <- row$rowVersion[1]

    if (!is.na(local_mrv) && !is.na(master_rv) &&
        identical(as.integer(local_mrv), as.integer(master_rv))) {
      next
    }

    values_differ <- .values_differ(local_row, row, su_fields)

    if (!values_differ || is.na(local_mrv)) {
      .upsert_local_su(con, row, has_mrv, has_lmu)
      fast_forwarded <- fast_forwarded + 1L
    } else {
      local_dirty <- has_lmu && !is.na(local_row$local_modified_utc[1])
      if (!local_dirty) {
        # Row not locally modified since last pull — safe to fast-forward
        .upsert_local_su(con, row, has_mrv, has_lmu)
        fast_forwarded <- fast_forwarded + 1L
      } else {
        local_vals  <- list(SiteUnit  = local_row$SiteUnit[1])
        master_vals <- list(SiteUnit  = row$SiteUnit[1])
        .queue_conflict(con, "su", pn, pid, NA, NA, local_vals, master_vals)
        conflicts <- conflicts + 1L
      }
    }
  }

  sync_set_watermark(con, "su", "pull")
  list(pulled = nrow(incoming), fast_forwarded = fast_forwarded, conflicts = conflicts)
}

# Compare field pairs between a local row and a master row.
# field_pairs: list of c(local_name, master_name)
.values_differ <- function(local_row, master_row, field_pairs) {
  for (pair in field_pairs) {
    lv    <- if (pair[1] %in% names(local_row))  local_row[[pair[1]]][1]  else NA
    mv    <- if (pair[2] %in% names(master_row)) master_row[[pair[2]]][1] else NA
    na_l  <- is.na(lv) || is.null(lv)
    na_m  <- is.na(mv) || is.null(mv)
    if (na_l && na_m) next
    if (xor(na_l, na_m)) return(TRUE)
    if (as.character(lv) != as.character(mv)) return(TRUE)
  }
  FALSE
}

# Upsert an env row received from master into the local Env table.
.upsert_local_env <- function(con, master_row, has_mrv, has_lmu = FALSE) {
  pn <- master_row$PlotNumber[1]
  exists <- nrow(DBI::dbGetQuery(con, "SELECT 1 FROM Env WHERE PlotNumber = ?", list(pn))) > 0

  mrv_sql    <- if (isTRUE(has_mrv)) ", master_row_version = ?" else ""
  mrv_insert <- if (isTRUE(has_mrv)) ", master_row_version" else ""
  mrv_ph     <- if (isTRUE(has_mrv)) ", ?" else ""
  mrv_val    <- if (isTRUE(has_mrv)) list(as.integer(master_row$rowVersion[1])) else list()

  # On pull, clear the dirty flag so the row is treated as clean until next user edit
  lmu_sql    <- if (isTRUE(has_lmu)) ", local_modified_utc = NULL" else ""
  lmu_insert <- if (isTRUE(has_lmu)) ", local_modified_utc" else ""
  lmu_ph     <- if (isTRUE(has_lmu)) ", NULL" else ""

  base_params <- list(
    master_row$Latitude[1], master_row$Longitude[1], master_row$Elevation[1],
    master_row$SurveyDate[1], master_row$SurveyorName[1], master_row$PlotNotes[1],
    master_row$Zone[1], master_row$SubZone[1], master_row$SiteSeries[1]
  )

  if (exists) {
    DBI::dbExecute(
      con,
      paste0("UPDATE Env SET Latitude = ?, Longitude = ?, Elevation = ?,",
             " Date = ?, SiteSurveyor = ?, SiteNotes = ?,",
             " Zone = ?, SubZone = ?, SiteSeries = ?", mrv_sql, lmu_sql,
             " WHERE PlotNumber = ?"),
      c(base_params, mrv_val, list(pn))
    )
  } else {
    DBI::dbExecute(
      con,
      paste0("INSERT INTO Env (PlotNumber, ProjectID, Latitude, Longitude, Elevation,",
             " Date, SiteSurveyor, SiteNotes, Zone, SubZone, SiteSeries", 
             mrv_insert, lmu_insert, ")",
             " VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?", mrv_ph, lmu_ph, ")"),
      c(list(pn, as.character(master_row$ProjectID[1])), base_params, mrv_val)
    )
  }
}

# Upsert a su row received from master into the local SU table.
.upsert_local_su <- function(con, master_row, has_mrv, has_lmu = FALSE) {
  pn <- master_row$PlotNumber[1]
  exists <- nrow(DBI::dbGetQuery(con, "SELECT 1 FROM SU WHERE PlotNumber = ?", list(pn))) > 0

  mrv_sql    <- if (isTRUE(has_mrv)) ", master_row_version = ?" else ""
  mrv_insert <- if (isTRUE(has_mrv)) ", master_row_version" else ""
  mrv_ph     <- if (isTRUE(has_mrv)) ", ?" else ""
  mrv_val    <- if (isTRUE(has_mrv)) list(as.integer(master_row$rowVersion[1])) else list()

  # On pull, clear the dirty flag so the row is treated as clean until next user edit
  lmu_sql    <- if (isTRUE(has_lmu)) ", local_modified_utc = NULL" else ""
  lmu_insert <- if (isTRUE(has_lmu)) ", local_modified_utc" else ""
  lmu_ph     <- if (isTRUE(has_lmu)) ", NULL" else ""

  if (exists) {
    DBI::dbExecute(
      con,
      paste0("UPDATE SU SET SiteUnit = ?", mrv_sql, lmu_sql, " WHERE PlotNumber = ?"),
      c(list(master_row$SiteUnit[1]), mrv_val, list(pn))
    )
  } else {
    DBI::dbExecute(
      con,
      paste0("INSERT INTO SU (PlotNumber, SiteUnit", mrv_insert, lmu_insert, ")",
             " VALUES (?, ?", mrv_ph, lmu_ph, ")"),
      c(list(pn, master_row$SiteUnit[1]), mrv_val)
    )
  }
}

.pull_veg <- function(con, project_id) {
  if (!DBI::dbExistsTable(con, "Veg") || !DBI::dbExistsTable(con, "Env")) {
    return(list(pulled = 0L, fast_forwarded = 0L, conflicts = 0L,
                skipped = TRUE, reason = "no_local_table"))
  }

  last_pull <- sync_get_watermark(con, "veg", "pull")
  has_mrv   <- "master_row_version" %in% DBI::dbListFields(con, "Veg")
  has_lmu   <- "local_modified_utc"  %in% DBI::dbListFields(con, "Veg")

  filters <- "1=1"
  params  <- list()
  if (!is.null(project_id) && nzchar(as.character(project_id))) {
    filters <- paste0(filters, " AND \"ProjectID\" = ?")
    params  <- c(params, list(as.integer(project_id)))
  }
  if (!is.null(last_pull)) {
    filters <- paste0(filters, " AND \"lastModifiedUTC\" > ?")
    params  <- c(params, list(last_pull))
  }

  incoming <- tryCatch(
    DBI::dbGetQuery(
      con,
      sprintf(
        "SELECT \"PlotNumber\", \"ProjectID\", \"SpeciesCode\", \"LayerCode\",
                \"Cover1\", \"Height1\", \"Cover2\", \"Height2\", \"Cover3\", \"Height3\",
                \"TotalA\", \"HeightA\", \"Cover4\", \"Height4\", \"Cover5\", \"Height5\",
                \"Cover5a\", \"Height5a\", \"Cover5b\", \"Height5b\", \"Cover5c\", \"Height5c\",
                \"TotalB\", \"HeightB\", \"Cover6\", \"Height6\", \"Cover7\", \"Cover8\", \"Cover9\", \"Cover10\",
                collected, flag, ll, af, dc, ut, vi, pv, pg, ffa,
                \"Cultural1\", \"Cultural2\", \"Other1\", \"Other2\", \"rowVersion\"
         FROM master.core.veg WHERE %s",
        filters
      ),
      params
    ),
    error = function(e) { warning("sync_pull veg failed: ", e$message); data.frame() }
  )

  if (nrow(incoming) == 0) {
    sync_set_watermark(con, "veg", "pull")
    return(list(pulled = 0L, fast_forwarded = 0L, conflicts = 0L))
  }

  fast_forwarded <- 0L
  conflicts      <- 0L
  # Compare the primary coverage/measurement fields; cover1 is the most critical
  veg_fields <- list(
    c("Cover1",  "Cover1"),  c("Height1", "Height1"),
    c("Cover2",  "Cover2"),  c("Height2", "Height2"),
    c("Cover3",  "Cover3"),  c("Height3", "Height3"),
    c("TotalA",  "TotalA"),  c("HeightA", "HeightA"),
    c("Cover4",  "Cover4"),  c("Height4", "Height4"),
    c("Cover5",  "Cover5"),  c("Height5", "Height5"),
    c("Cover5a", "Cover5a"), c("Height5a", "Height5a"),
    c("Cover5b", "Cover5b"), c("Height5b", "Height5b"),
    c("Cover5c", "Cover5c"), c("Height5c", "Height5c"),
    c("TotalB",  "TotalB"),  c("HeightB", "HeightB"),
    c("Cover6",  "Cover6"),  c("Height6", "Height6"),
    c("Cover7",  "Cover7"),  c("Cover8",  "Cover8"),
    c("Cover9",  "Cover9"),  c("Cover10", "Cover10"),
    c("Collected", "Collected"), c("Flag", "Flag"),
    c("ID",  "ID"),  c("LL",  "LL"),
    c("AF",  "AF"),  c("DC",  "DC"),
    c("UT",  "UT"),  c("VI",  "VI"),
    c("PV",  "PV"),  c("PG",  "PG"),  c("FFA", "FFA"),
    c("Cultural1", "Cultural1"), c("Cultural2", "Cultural2"),
    c("Other1", "Other1"), c("Other2", "Other2")
  )

  for (i in seq_len(nrow(incoming))) {
    row  <- incoming[i, , drop = FALSE]
    pn   <- row$PlotNumber[1]
    pid  <- as.integer(row$ProjectID[1])
    sc   <- row$SpeciesCode[1]
    lc   <- row$LayerCode[1]

    lmu_col   <- if (has_lmu) ", local_modified_utc" else ""
    local_row <- tryCatch(
      DBI::dbGetQuery(
        con,
        sprintf(
          "SELECT v.PlotNumber, v.Species, v.Layer,
                  v.Cover1, v.Height1, v.Cover2, v.Height2, v.Cover3,
                  v.TotalA, v.Cover4, v.Cover5, v.TotalB, v.Cover6,
                  v.Cover7, v.Cover8, v.Cover9, v.Cover10,
                  v.Collected, v.Flag, v.master_row_version%s
           FROM Veg v
           JOIN Env e ON e.PlotNumber = v.PlotNumber
           WHERE v.PlotNumber = ? AND TRIM(v.Species) = ? AND v.Layer = ?
             AND e.ProjectID = ?",
          lmu_col
        ),
        list(pn, sc, lc %||% "", pid)
      ),
      error = function(e) data.frame()
    )

    if (nrow(local_row) == 0) {
      .upsert_local_veg(con, row, has_mrv, has_lmu)
      fast_forwarded <- fast_forwarded + 1L
      next
    }

    local_mrv <- if (has_mrv) local_row$master_row_version[1] else NA_integer_
    master_rv <- row$rowVersion[1]

    if (!is.na(local_mrv) && !is.na(master_rv) &&
        identical(as.integer(local_mrv), as.integer(master_rv))) {
      next
    }

    values_differ <- .values_differ(local_row, row, veg_fields)

    if (!values_differ || is.na(local_mrv)) {
      .upsert_local_veg(con, row, has_mrv, has_lmu)
      fast_forwarded <- fast_forwarded + 1L
    } else {
      local_dirty <- has_lmu && !is.na(local_row$local_modified_utc[1])
      if (!local_dirty) {
        .upsert_local_veg(con, row, has_mrv, has_lmu)
        fast_forwarded <- fast_forwarded + 1L
      } else {
        local_vals <- list(
          Cover1 = local_row$Cover1[1], Height1 = local_row$Height1[1],
          Cover2 = local_row$Cover2[1], TotalA  = local_row$TotalA[1],
          Cover4 = local_row$Cover4[1], Cover5  = local_row$Cover5[1]
        )
        master_vals <- list(
          cover1 = row$cover1[1], height1 = row$height1[1],
          cover2 = row$cover2[1], totala  = row$totala[1],
          cover4 = row$cover4[1], cover5  = row$cover5[1]
        )
        .queue_conflict(con, "veg", pn, as.character(pid), sc, lc, local_vals, master_vals)
        conflicts <- conflicts + 1L
      }
    }
  }

  sync_set_watermark(con, "veg", "pull")
  list(pulled = nrow(incoming), fast_forwarded = fast_forwarded, conflicts = conflicts)
}

# Upsert a veg row received from master into the local Veg table.
.upsert_local_veg <- function(con, master_row, has_mrv, has_lmu = FALSE) {
  pn <- master_row$PlotNumber[1]
  sc <- master_row$SpeciesCode[1]
  lc <- master_row$LayerCode[1] %||% ""

  exists <- nrow(DBI::dbGetQuery(
    con,
    "SELECT 1 FROM Veg v JOIN Env e ON e.PlotNumber = v.PlotNumber
     WHERE v.PlotNumber = ? AND TRIM(v.Species) = ? AND v.Layer = ?
       AND e.ProjectID = ?",
    list(pn, sc, lc, as.integer(master_row$ProjectID[1]))
  )) > 0

  mrv_val <- if (isTRUE(has_mrv)) list(as.integer(master_row$rowVersion[1])) else list()

  cover_params <- list(
    master_row$Cover1[1],   master_row$Height1[1],
    master_row$Cover2[1],   master_row$Height2[1],
    master_row$Cover3[1],   master_row$Height3[1],
    master_row$TotalA[1],   master_row$HeightA[1],
    master_row$Cover4[1],   master_row$Height4[1],
    master_row$Cover5[1],   master_row$Height5[1],
    master_row$Cover5a[1],  master_row$Height5a[1],
    master_row$Cover5b[1],  master_row$Height5b[1],
    master_row$Cover5c[1],  master_row$Height5c[1],
    master_row$TotalB[1],   master_row$HeightB[1],
    master_row$Cover6[1],   master_row$Height6[1],
    master_row$Cover7[1],   master_row$Cover8[1],
    master_row$Cover9[1],   master_row$Cover10[1],
    master_row$Collected[1], master_row$Flag[1],
    master_row$ll[1],   master_row$af[1],
    master_row$dc[1],        master_row$ut[1],
    master_row$vi[1],        master_row$pv[1],
    master_row$pg[1],        master_row$ffa[1],
    master_row$Cultural1[1],
    master_row$Cultural2[1], master_row$Other1[1],
    master_row$Other2[1]
  )

  mrv_set_sql    <- if (isTRUE(has_mrv)) ", master_row_version = ?" else ""
  lmu_set_sql    <- if (isTRUE(has_lmu)) ", local_modified_utc = NULL" else ""
  mrv_col        <- if (isTRUE(has_mrv)) ", master_row_version" else ""
  lmu_col        <- if (isTRUE(has_lmu)) ", local_modified_utc" else ""
  mrv_ph         <- if (isTRUE(has_mrv)) ", ?" else ""
  lmu_ph         <- if (isTRUE(has_lmu)) ", NULL" else ""

  if (exists) {
    DBI::dbExecute(
      con,
      paste0(
        "UPDATE Veg SET",
        " Cover1=?, Height1=?, Cover2=?, Height2=?, Cover3=?, Height3=?,",
        " TotalA=?, HeightA=?, Cover4=?, Height4=?, Cover5=?, Height5=?,",
        " Cover5a=?, Height5a=?, Cover5b=?, Height5b=?, Cover5c=?, Height5c=?,",
        " TotalB=?, HeightB=?, Cover6=?, Height6=?, Cover7=?, Cover8=?,",
        " Cover9=?, Cover10=?, Collected=?, Flag=?, ID=?, LL=?,",
        " AF=?, DC=?, UT=?, VI=?, PV=?, PG=?, FFA=?,",
        " Cultural1=?, Cultural2=?, Other1=?, Other2=?",
        mrv_set_sql, lmu_set_sql,
        " WHERE PlotNumber = ? AND TRIM(Species) = ? AND Layer = ?"
      ),
      c(cover_params, mrv_val, list(pn, sc, lc))
    )
  } else {
    DBI::dbExecute(
      con,
      paste0(
        "INSERT INTO Veg",
        " (PlotNumber, Species, Layer,",
        "  Cover1, Height1, Cover2, Height2, Cover3, Height3,",
        "  TotalA, HeightA, Cover4, Height4, Cover5, Height5,",
        "  Cover5a, Height5a, Cover5b, Height5b, Cover5c, Height5c,",
        "  TotalB, HeightB, Cover6, Height6, Cover7, Cover8,",
        "  Cover9, Cover10, Collected, Flag, ID, LL,",
        "  AF, DC, UT, VI, PV, PG, FFA,",
        "  Cultural1, Cultural2, Other1, Other2",
        mrv_col, lmu_col, ")",
        " VALUES (?, ?, ?,",
        "  ?, ?, ?, ?, ?, ?,",
        "  ?, ?, ?, ?, ?, ?,",
        "  ?, ?, ?, ?, ?, ?,",
        "  ?, ?, ?, ?, ?, ?,",
        "  ?, ?, ?, ?, ?, ?,",
        "  ?, ?, ?, ?, ?, ?, ?,",
        "  ?, ?, ?, ?",
        mrv_ph, lmu_ph, ")"
      ),
      c(list(pn, sc, lc), cover_params, mrv_val)
    )
  }
}

# =============================================================================
# 3b. PULL: master.lists.* -> local lists.* (full replace, no conflict)
# =============================================================================

#' Sync all reference (lists) tables from master into the local lists attachment.
#'
#' Reference data is admin-only — users never edit it. Every sync_pull does a
#' full replace: DELETE then INSERT for each matching table. No conflict
#' detection or watermark filtering; always take master as authoritative.
#'
#' Only tables that exist in **both** master.lists and the locally attached
#' `lists` catalog are touched. Tables not found in master are skipped with a
#' warning. If no `lists` catalog is attached locally, returns silently with
#' zero synced tables.
#'
#' @param con DuckDB connection (master and local `lists` catalog both attached).
#' @return Named list: synced_tables (integer count), skipped (character vector).
.pull_lists <- function(con) {
  # Discover tables available in master.lists
  master_tbls <- tryCatch(
    DBI::dbGetQuery(
      con,
      "SELECT table_name FROM duckdb_tables() WHERE database_name = 'master' AND schema_name = 'lists'"
    )$table_name,
    error = function(e) character(0)
  )

  if (length(master_tbls) == 0) {
    return(list(synced_tables = 0L, skipped = character(0)))
  }

  # Discover tables in the locally attached `lists` catalog
  local_tbls <- tryCatch(
    DBI::dbGetQuery(
      con,
      "SELECT table_name FROM duckdb_tables() WHERE database_name = 'lists'"
    )$table_name,
    error = function(e) character(0)
  )

  if (length(local_tbls) == 0) {
    return(list(synced_tables = 0L, skipped = character(0)))
  }

  synced  <- 0L
  skipped <- character(0)

  for (tbl in local_tbls) {
    # Exact name match first; fall back to case-insensitive
    master_match <- master_tbls[master_tbls == tbl]
    if (length(master_match) == 0) {
      master_match <- master_tbls[tolower(master_tbls) == tolower(tbl)]
    }
    if (length(master_match) == 0) {
      skipped <- c(skipped, tbl)
      next
    }
    m_tbl <- master_match[1]

    ok <- tryCatch({
      m_cols <- DBI::dbListFields(con, DBI::Id(catalog = "master", schema = "lists", table = m_tbl))
      l_cols <- DBI::dbListFields(con, DBI::Id(catalog = "lists",  table = tbl))

      # Exact-case common columns first; fall back to case-insensitive intersection
      common <- intersect(l_cols, m_cols)
      if (length(common) > 0) {
        col_local  <- paste(sprintf('"%s"', common), collapse = ", ")
        col_master <- col_local
      } else {
        ci_local <- l_cols[tolower(l_cols) %in% tolower(m_cols)]
        if (length(ci_local) == 0) {
          warning("lists pull: no common columns between local '", tbl, "' and master '", m_tbl, "' — skipped")
          return(FALSE)
        }
        ci_master  <- vapply(
          ci_local,
          function(lc) m_cols[tolower(m_cols) == tolower(lc)][1],
          character(1)
        )
        col_local  <- paste(sprintf('"%s"', ci_local),  collapse = ", ")
        col_master <- paste(sprintf('"%s"', ci_master), collapse = ", ")
      }

      DBI::dbExecute(con, sprintf('DELETE FROM lists."%s"', tbl))
      DBI::dbExecute(con, sprintf(
        'INSERT INTO lists."%s" (%s) SELECT %s FROM master.lists."%s"',
        tbl, col_local, col_master, m_tbl
      ))
      TRUE
    }, error = function(e) {
      warning("lists pull: error syncing '", tbl, "': ", conditionMessage(e))
      FALSE
    })

    if (isTRUE(ok)) synced <- synced + 1L else skipped <- c(skipped, tbl)
  }

  sync_set_watermark(con, "lists", "pull")
  list(synced_tables = synced, skipped = skipped)
}

# Append a pull conflict to the local sync.conflict_queue.
.queue_conflict <- function(con, table_name, plot_number, project_id,
                             species_code, layer_code,
                             local_vals, master_vals) {
  to_json <- function(x) {
    tryCatch(
      as.character(jsonlite::toJSON(x, auto_unbox = TRUE, na = "null")),
      error = function(e) "{}"
    )
  }
  DBI::dbExecute(
    con,
    "INSERT INTO sync.conflict_queue
       (table_name, plot_number, project_id, species_code, layer_code,
        local_values, master_values)
     VALUES (?, ?, ?, ?, ?, ?, ?)",
    list(
      table_name,
      as.character(plot_number),
      as.character(project_id %||% ""),
      if (is.na(species_code) || is.null(species_code)) NA_character_ else as.character(species_code),
      if (is.na(layer_code)   || is.null(layer_code))   NA_character_ else as.character(layer_code),
      to_json(local_vals),
      to_json(master_vals)
    )
  )
}


# =============================================================================
# 4. Local conflict queue management
# =============================================================================

#' List pull conflicts from the local conflict_queue.
#'
#' @param con            DuckDB connection.
#' @param project_id     Optional filter.
#' @param table_name     Optional filter ("env", "su", "veg").
#' @param unresolved_only Logical. Default TRUE.
#' @return data.frame.
sync_get_local_conflicts <- function(con, project_id = NULL, table_name = NULL,
                                      unresolved_only = TRUE) {
  if (!DBI::dbExistsTable(con, DBI::Id(schema = "sync", table = "conflict_queue"))) {
    return(data.frame())
  }
  sql    <- "SELECT * FROM sync.conflict_queue WHERE 1=1"
  params <- list()
  if (isTRUE(unresolved_only)) {
    sql <- paste0(sql, " AND resolution IS NULL")
  }
  if (!is.null(project_id) && nzchar(as.character(project_id))) {
    sql    <- paste0(sql, " AND project_id = ?")
    params <- c(params, list(as.character(project_id)))
  }
  if (!is.null(table_name) && nzchar(table_name)) {
    sql    <- paste0(sql, " AND table_name = ?")
    params <- c(params, list(table_name))
  }
  DBI::dbGetQuery(con, paste0(sql, " ORDER BY conflict_at DESC"), params)
}

#' Count unresolved pull conflicts.
#'
#' @param con        DuckDB connection.
#' @param project_id Optional filter.
#' @param table_name Optional filter.
#' @return Integer.
sync_count_local_conflicts <- function(con, project_id = NULL, table_name = NULL) {
  nrow(sync_get_local_conflicts(con, project_id = project_id,
                                table_name = table_name, unresolved_only = TRUE))
}

#' Resolve an entry in the local conflict_queue.
#'
#' @param con         DuckDB connection.
#' @param conflict_id Integer. Row id in sync.conflict_queue.
#' @param resolution  "keep_local" — discard master value, keep local row unchanged.
#'                    "accept_master" — overwrite local row with master values.
sync_resolve_local_conflict <- function(con, conflict_id, resolution) {
  if (!resolution %in% c("keep_local", "accept_master")) {
    stop("resolution must be 'keep_local' or 'accept_master'")
  }

  if (resolution == "accept_master") {
    row <- DBI::dbGetQuery(
      con,
      "SELECT * FROM sync.conflict_queue WHERE id = ?",
      list(as.integer(conflict_id))
    )
    if (nrow(row) > 0) {
      master_vals <- tryCatch(
        jsonlite::fromJSON(row$master_values[1]),
        error = function(e) list()
      )
      if (row$table_name[1] == "env" && length(master_vals) > 0) {
        DBI::dbExecute(
          con,
          "UPDATE Env SET Latitude = ?, Longitude = ?, Elevation = ?,
                          Date = ?, SiteSurveyor = ?, SiteNotes = ?
           WHERE PlotNumber = ?",
          list(
            master_vals$latitude      %||% NA,
            master_vals$longitude     %||% NA,
            master_vals$elevation_m   %||% NA,
            master_vals$survey_date   %||% NA,
            master_vals$surveyor_name %||% NA,
            master_vals$plot_notes    %||% NA,
            row$plot_number[1]
          )
        )
      } else if (row$table_name[1] == "su" && !is.null(master_vals$su_number)) {
        DBI::dbExecute(
          con,
          "UPDATE SU SET SiteUnit = ? WHERE PlotNumber = ?",
          list(master_vals$su_number, row$plot_number[1])
        )
      }
    }
  }

  DBI::dbExecute(
    con,
    "UPDATE sync.conflict_queue SET resolution = ? WHERE id = ?",
    list(resolution, as.integer(conflict_id))
  )
  invisible(TRUE)
}


# =============================================================================
# 5. PUSH: local -> master.staging
# =============================================================================

#' Push local changes to the master staging area, creating a merge request.
#'
#' Computes the delta between each local table and master.core (rows that are
#' new or changed), then inserts them into master.staging with:
#'   - `change_type`       'I' (new) or 'U' (changed)
#'   - `base_row_version`  current master row_version at push time (NULL for new rows)
#'
#' Aborts if unresolved local pull conflicts exist for the project.
#'
#' @param con          DuckDB connection (master must be attached).
#' @param project_id   Integer or character. Project to push.
#' @param submitter    Character. Username / label of the submitter.
#' @param tables       Character vector. Any of "env", "su", "veg".
#' @param allow_attach Logical. Auto-attach master if not connected.
#'
#' @return Named list: merge_request_id, env, su, veg (row counts),
#'         and optionally compliance_failed = TRUE.
sync_push <- function(con,
                      project_id   = NULL,
                      submitter    = Sys.getenv("USER", "unknown"),
                      tables       = c("env", "su", "veg"),
                      allow_attach = TRUE) {
  sync_require_cloud(con, allow_attach = allow_attach)
  sync_ensure_local_tables(con)

  # Resolve project_id if not supplied
  if (is.null(project_id) || !nzchar(as.character(project_id))) {
    if (DBI::dbExistsTable(con, "Env")) {
      pids <- DBI::dbGetQuery(con, "SELECT DISTINCT ProjectID FROM Env WHERE ProjectID IS NOT NULL")$ProjectID
      pids <- pids[!is.na(pids) & nzchar(as.character(pids))]
      if (length(pids) == 1) {
        project_id <- pids[1]
      } else {
        stop("project_id is required for sync_push when multiple projects exist.")
      }
    } else {
      stop("project_id is required for sync_push.")
    }
  }

  # Guard: block push if unresolved pull conflicts exist
  n_conflicts <- sync_count_local_conflicts(con, project_id = as.character(project_id))
  if (n_conflicts > 0) {
    stop(sprintf(
      paste0("Push blocked: %d unresolved pull conflict(s) for project %s. ",
             "Resolve via sync_resolve_local_conflict() before pushing."),
      n_conflicts, project_id
    ))
  }

  mr_id   <- .create_merge_request(con, project_id, submitter)
  results <- list(merge_request_id = mr_id)

  if ("env" %in% tables) results$env <- .push_env(con, project_id, mr_id, submitter)
  if ("su"  %in% tables) results$su  <- .push_su( con, project_id, mr_id, submitter)
  if ("veg" %in% tables) results$veg <- .push_veg(con, project_id, mr_id, submitter)

  env_n <- as.integer(results$env %||% 0L)
  su_n  <- as.integer(results$su  %||% 0L)
  veg_n <- as.integer(results$veg %||% 0L)

  DBI::dbExecute(
    con,
    "UPDATE master.admin.merge_requests
     SET env_record_count = ?, su_record_count = ?, veg_record_count = ?
     WHERE id = ?",
    list(env_n, su_n, veg_n, mr_id)
  )

  # Optional compliance gate (staging_compliance_checks() from logic_compliance.R)
  if (exists("staging_compliance_checks", mode = "function")) {
    compliance    <- tryCatch(
      staging_compliance_checks(con, mr_id, project_id),
      error = function(e) list(passed = TRUE)
    )
    compliance_ok <- isTRUE(compliance$passed)
    report_json   <- tryCatch(
      as.character(jsonlite::toJSON(
        list(summary = compliance$summary_tibble, details = compliance$detail_tibble),
        auto_unbox = TRUE, na = "null"
      )),
      error = function(e) NULL
    )
    DBI::dbExecute(
      con,
      "UPDATE master.admin.merge_requests
       SET compliance_passed = ?, compliance_report = ? WHERE id = ?",
      list(compliance_ok, report_json, mr_id)
    )
    if (!compliance_ok) {
      .delete_staging(con, mr_id)
      DBI::dbExecute(
        con,
        "UPDATE master.admin.merge_requests SET status = 'rejected' WHERE id = ?",
        list(mr_id)
      )
      results$compliance_failed <- TRUE
      return(results)
    }
  }

  for (tbl in tables) sync_set_watermark(con, tbl, "push")
  results
}

# ── internal push helpers ───────────────────────────────────────────────────

.create_merge_request <- function(con, project_id, submitter) {
  # Resolve submitter's user_id — submitter is expected to be the user's email,
  # matching admin.users.email (always present: auth_guest_login upserts on login).
  uid_row <- tryCatch(
    DBI::dbGetQuery(
      con,
      "SELECT id FROM master.admin.users WHERE email = ? LIMIT 1",
      list(as.character(submitter))
    ),
    error = function(e) data.frame(id = integer(0))
  )
  submitter_user_id <- if (nrow(uid_row) > 0) as.integer(uid_row$id[1]) else NA_integer_

  DBI::dbExecute(
    con,
    "INSERT INTO master.admin.merge_requests
       (project_id, submitter_user_id, submitter_name, submitted_utc, status)
     VALUES (?, ?, ?, now(), 'pending_review')",
    list(as.integer(project_id), submitter_user_id, as.character(submitter))
  )
  
  # Fetch the ID of the newly inserted merge request
  res <- DBI::dbGetQuery(
    con,
    "SELECT id FROM master.admin.merge_requests
     WHERE project_id = ? AND submitter_name = ? AND status = 'pending_review'
     ORDER BY submitted_utc DESC LIMIT 1",
    list(as.integer(project_id), as.character(submitter))
  )
  if (nrow(res) == 0) stop("Failed to create merge request.")
  res$id[1]
}

.push_env <- function(con, project_id, mr_id, submitter) {
  if (!DBI::dbExistsTable(con, "Env")) return(0L)

  DBI::dbExecute(con, "DROP TABLE IF EXISTS tmp_push_env_delta")
  DBI::dbExecute(
    con,
    "CREATE TEMP TABLE tmp_push_env_delta AS
     SELECT
       l.PlotNumber::TEXT            AS plot_number,
       l.ProjectID  AS project_id,
       l.Latitude::DOUBLE            AS latitude,
       l.Longitude::DOUBLE           AS longitude,
       l.Elevation::INTEGER          AS elevation_m,
       l.Date::DATE                  AS survey_date,
       l.SiteSurveyor::TEXT          AS surveyor_name,
       l.SiteNotes::TEXT             AS plot_notes,
       l.Zone::TEXT                  AS zone,
       l.SubZone::TEXT               AS subzone,
       l.SiteSeries::TEXT            AS site_series,
       c.row_version                 AS base_row_version,
       CASE WHEN c.plot_number IS NULL THEN 'I' ELSE 'U' END AS change_type
     FROM Env l
     LEFT JOIN master.core.env c
       ON  c.plot_number = l.PlotNumber
       AND c.project_id  = l.ProjectID
     WHERE l.ProjectID = ?
       AND (
         c.plot_number IS NULL
         OR c.latitude      IS DISTINCT FROM l.Latitude::DOUBLE
         OR c.longitude     IS DISTINCT FROM l.Longitude::DOUBLE
         OR c.elevation_m   IS DISTINCT FROM l.Elevation::INTEGER
         OR c.survey_date   IS DISTINCT FROM l.Date::DATE
         OR c.surveyor_name IS DISTINCT FROM l.SiteSurveyor
         OR c.plot_notes    IS DISTINCT FROM l.SiteNotes
         OR c.zone          IS DISTINCT FROM l.Zone
         OR c.subzone       IS DISTINCT FROM l.SubZone
         OR c.site_series   IS DISTINCT FROM l.SiteSeries
       )",
    list(as.character(project_id))
  )

  n <- DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM tmp_push_env_delta")$n[1]
  if (n > 0) {
    DBI::dbExecute(
      con,
      "INSERT INTO master.staging.env
         (merge_request_id, change_type, base_row_version,
          plot_number, project_id, latitude, longitude, elevation_m,
          survey_date, surveyor_name, plot_notes, zone, subzone, site_series,
          modified_by)
       SELECT ?, change_type, base_row_version,
              plot_number, project_id, latitude, longitude, elevation_m,
              survey_date, surveyor_name, plot_notes, zone, subzone, site_series, ?
       FROM tmp_push_env_delta",
      list(mr_id, submitter)
    )
  }

  DBI::dbExecute(con, "DROP TABLE IF EXISTS tmp_push_env_delta")
  as.integer(n)
}

.push_su <- function(con, project_id, mr_id, submitter) {
  if (!DBI::dbExistsTable(con, "SU") || !DBI::dbExistsTable(con, "Env")) return(0L)

  DBI::dbExecute(con, "DROP TABLE IF EXISTS tmp_push_su_delta")
  DBI::dbExecute(
    con,
    "CREATE TEMP TABLE tmp_push_su_delta AS
     SELECT
       su.PlotNumber::TEXT           AS plot_number,
       e.ProjectID  AS project_id,
       su.SiteUnit::TEXT             AS su_number,
       e.Zone::TEXT                  AS bec_zone,
       e.SubZone::TEXT               AS bec_subzone,
       e.SiteSeries::TEXT            AS site_series,
       c.row_version                 AS base_row_version,
       CASE WHEN c.plot_number IS NULL THEN 'I' ELSE 'U' END AS change_type
     FROM SU su
     LEFT JOIN Env e  ON e.PlotNumber = su.PlotNumber
     LEFT JOIN master.core.su c
       ON  c.plot_number = su.PlotNumber
       AND c.project_id  = e.ProjectID
     WHERE e.PlotNumber IS NOT NULL
       AND e.ProjectID = ?
       AND (
         c.plot_number IS NULL
         OR c.su_number   IS DISTINCT FROM su.SiteUnit
         OR c.bec_zone    IS DISTINCT FROM e.Zone
         OR c.bec_subzone IS DISTINCT FROM e.SubZone
         OR c.site_series IS DISTINCT FROM e.SiteSeries
       )",
    list(as.integer(project_id))
  )

  n <- DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM tmp_push_su_delta")$n[1]
  if (n > 0) {
    DBI::dbExecute(
      con,
      "INSERT INTO master.staging.su
         (merge_request_id, change_type, base_row_version,
          plot_number, project_id, su_number, bec_zone, bec_subzone, site_series,
          modified_by)
       SELECT ?, change_type, base_row_version,
              plot_number, project_id, su_number, bec_zone, bec_subzone, site_series, ?
       FROM tmp_push_su_delta",
      list(mr_id, submitter)
    )
  }

  DBI::dbExecute(con, "DROP TABLE IF EXISTS tmp_push_su_delta")
  as.integer(n)
}

.push_veg <- function(con, project_id, mr_id, submitter) {
  if (!DBI::dbExistsTable(con, "Veg") || !DBI::dbExistsTable(con, "Env")) return(0L)

  DBI::dbExecute(con, "DROP TABLE IF EXISTS tmp_push_veg_all")
  DBI::dbExecute(
    con,
    "CREATE TEMP TABLE tmp_push_veg_all AS
     SELECT
       v.PlotNumber::TEXT              AS plot_number,
       e.ProjectID    AS project_id,
       TRIM(v.Species)::TEXT           AS species_code,
       v.Layer::TEXT                   AS layer_code,
       TRY_CAST(v.Cover1   AS REAL)    AS cover1,
       TRY_CAST(v.Height1  AS REAL)    AS height1,
       TRY_CAST(v.Cover2   AS REAL)    AS cover2,
       TRY_CAST(v.Height2  AS REAL)    AS height2,
       TRY_CAST(v.Cover3   AS REAL)    AS cover3,
       TRY_CAST(v.Height3  AS REAL)    AS height3,
       TRY_CAST(v.TotalA   AS REAL)    AS totala,
       TRY_CAST(v.HeightA  AS REAL)    AS heighta,
       TRY_CAST(v.Cover4   AS REAL)    AS cover4,
       TRY_CAST(v.Height4  AS REAL)    AS height4,
       TRY_CAST(v.Cover5   AS REAL)    AS cover5,
       TRY_CAST(v.Height5  AS REAL)    AS height5,
       TRY_CAST(v.Cover5a  AS REAL)    AS cover5a,
       TRY_CAST(v.Height5a AS REAL)    AS height5a,
       TRY_CAST(v.Cover5b  AS REAL)    AS cover5b,
       TRY_CAST(v.Height5b AS REAL)    AS height5b,
       TRY_CAST(v.Cover5c  AS REAL)    AS cover5c,
       TRY_CAST(v.Height5c AS REAL)    AS height5c,
       TRY_CAST(v.TotalB   AS REAL)    AS totalb,
       v.HeightB::TEXT                 AS heightb,
       TRY_CAST(v.Cover6   AS REAL)    AS cover6,
       TRY_CAST(v.Height6  AS REAL)    AS height6,
       TRY_CAST(v.Cover7   AS REAL)    AS cover7,
       TRY_CAST(v.Cover8   AS REAL)    AS cover8,
       TRY_CAST(v.Cover9   AS REAL)    AS cover9,
       TRY_CAST(v.Cover10  AS REAL)    AS cover10,
       v.Collected::TEXT               AS collected,
       TRY_CAST(v.Flag     AS BOOLEAN) AS flag,
       TRY_CAST(v.ID       AS INTEGER) AS veg_id,
       TRY_CAST(v.LL       AS INTEGER) AS ll,
       TRY_CAST(v.AF       AS INTEGER) AS af,
       TRY_CAST(v.DC       AS INTEGER) AS dc,
       TRY_CAST(v.UT       AS INTEGER) AS ut,
       TRY_CAST(v.VI       AS INTEGER) AS vi,
       TRY_CAST(v.PV       AS INTEGER) AS pv,
       TRY_CAST(v.PG       AS INTEGER) AS pg,
       TRY_CAST(v.FFA      AS INTEGER) AS ffa,
       TRY_CAST(v.Cultural1 AS INTEGER) AS cultural1,
       TRY_CAST(v.Cultural2 AS INTEGER) AS cultural2,
       TRY_CAST(v.Other1   AS INTEGER) AS other1,
       TRY_CAST(v.Other2   AS INTEGER) AS other2,
       c.row_version                   AS base_row_version,
       CASE WHEN c.plot_number IS NULL THEN 'I' ELSE 'U' END AS change_type
     FROM Veg v
     LEFT JOIN Env e ON e.PlotNumber = v.PlotNumber
     LEFT JOIN master.core.veg c
       ON  c.plot_number  = v.PlotNumber
       AND c.project_id   = e.ProjectID
       AND c.species_code = TRIM(v.Species)
       AND c.layer_code   = v.Layer
     WHERE e.PlotNumber IS NOT NULL
       AND e.ProjectID = ?",
    list(as.integer(project_id))
  )

  n <- DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM tmp_push_veg_all")$n[1]
  if (n > 0) {
    DBI::dbExecute(
      con,
      "INSERT INTO master.staging.veg
         (merge_request_id, change_type, base_row_version,
          plot_number, project_id, species_code, layer_code,
          cover1, height1, cover2, height2, cover3, height3, totala, heighta,
          cover4, height4, cover5, height5, cover5a, height5a, cover5b, height5b,
          cover5c, height5c, totalb, heightb, cover6, height6,
          cover7, cover8, cover9, cover10,
          collected, flag, veg_id, ll, af, dc, ut, vi, pv, pg, ffa,
          cultural1, cultural2, other1, other2, modified_by)
       SELECT ?, change_type, base_row_version,
              plot_number, project_id, species_code, layer_code,
              cover1, height1, cover2, height2, cover3, height3, totala, heighta,
              cover4, height4, cover5, height5, cover5a, height5a, cover5b, height5b,
              cover5c, height5c, totalb, heightb, cover6, height6,
              cover7, cover8, cover9, cover10,
              collected, flag, veg_id, ll, af, dc, ut, vi, pv, pg, ffa,
              cultural1, cultural2, other1, other2, ?
       FROM tmp_push_veg_all",
      list(mr_id, submitter)
    )
  }

  DBI::dbExecute(con, "DROP TABLE IF EXISTS tmp_push_veg_all")
  as.integer(n)
}

# Delete all staging rows for a merge request (used on rejection or compliance failure).
.delete_staging <- function(con, mr_id) {
  for (tbl in c("master.staging.env", "master.staging.su", "master.staging.veg")) {
    tryCatch(
      DBI::dbExecute(con,
        sprintf("DELETE FROM %s WHERE merge_request_id = ?", tbl), list(mr_id)
      ),
      error = function(e) NULL
    )
  }
}


# =============================================================================
# 6. Server-side merge management (admin workflow)
# =============================================================================

#' Retrieve a single merge request by id.
#'
#' @param con              DuckDB connection (master attached).
#' @param merge_request_id Integer.
#' @return Single-row data.frame or NULL.
merge_request_get <- function(con, merge_request_id) {
  rows <- DBI::dbGetQuery(
    con,
    "SELECT * FROM master.admin.merge_requests WHERE id = ?",
    list(as.integer(merge_request_id))
  )
  if (nrow(rows) == 0) return(NULL)
  rows[1, , drop = FALSE]
}

#' List merge requests, optionally filtered by status.
#'
#' @param con    DuckDB connection.
#' @param status Optional character filter. One of the status CHECK values.
#' @param limit  Integer. Max rows to return.
#' @return data.frame with an extra `unresolved_conflicts` column.
merge_request_list <- function(con, status = NULL, limit = 200L) {
  sql    <- "SELECT id, project_id, submitter_name, submitted_utc, status,
                    env_record_count, su_record_count, veg_record_count, compliance_passed
             FROM master.admin.merge_requests"
  params <- list()
  if (!is.null(status) && nzchar(status)) {
    sql    <- paste0(sql, " WHERE status = ?")
    params <- list(status)
  }
  sql    <- paste0(sql, " ORDER BY submitted_utc DESC LIMIT ?")
  params <- c(params, list(as.integer(limit)))

  out <- DBI::dbGetQuery(con, sql, params)
  if (nrow(out) == 0) return(out)

  unresolved <- tryCatch(
    DBI::dbGetQuery(
      con,
      "SELECT merge_request_id, COUNT(*) AS unresolved_conflicts
       FROM master.admin.merge_conflicts
       WHERE resolution IS NULL
       GROUP BY merge_request_id"
    ),
    error = function(e) data.frame()
  )
  if (nrow(unresolved) > 0) {
    out <- merge(out, unresolved, by.x = "id", by.y = "merge_request_id", all.x = TRUE)
  }
  if (!"unresolved_conflicts" %in% names(out)) out$unresolved_conflicts <- 0L
  out$unresolved_conflicts[is.na(out$unresolved_conflicts)] <- 0L
  out
}

#' Detect and log all conflicts for a merge request.
#'
#' A conflict exists when `core.row_version > staging.base_row_version`, meaning
#' master was updated between the user's last pull and the admin review.
#' Existing unresolved conflicts are refreshed; resolved ones are preserved.
#'
#' @param con              DuckDB connection.
#' @param merge_request_id Integer.
merge_request_refresh_conflicts <- function(con, merge_request_id) {
  mr_id <- as.integer(merge_request_id)
  DBI::dbExecute(
    con,
    "DELETE FROM master.admin.merge_conflicts
     WHERE merge_request_id = ? AND resolution IS NULL",
    list(mr_id)
  )
  .detect_env_conflicts(con, mr_id)
  .detect_su_conflicts( con, mr_id)
  .detect_veg_conflicts(con, mr_id)
  invisible(TRUE)
}

# Insert or refresh a server-side conflict record.
.insert_conflict <- function(con, mr_id, table_name, plot_number, project_id,
                              species_code = NA, layer_code = NA, details_json) {
  sc  <- if (is.na(species_code) || is.null(species_code)) "" else as.character(species_code)
  lc  <- if (is.na(layer_code)   || is.null(layer_code))   "" else as.character(layer_code)
  pid <- as.character(project_id %||% "")
  key_params <- list(mr_id, as.character(table_name), as.character(plot_number), pid, sc, lc)

  existing <- tryCatch(
    DBI::dbGetQuery(
      con,
      "SELECT id, resolution FROM master.admin.merge_conflicts
       WHERE merge_request_id = ? AND table_name = ? AND plot_number = ?
         AND COALESCE(project_id, '') = ? AND species_code = ? AND layer_code = ?",
      key_params
    ),
    error = function(e) data.frame()
  )

  if (nrow(existing) > 0) {
    # Row already exists: update details only if not yet resolved; never clobber decisions.
    if (is.na(existing$resolution[1])) {
      DBI::dbExecute(con,
        "UPDATE master.admin.merge_conflicts SET details = ? WHERE id = ?",
        list(as.character(details_json), as.integer(existing$id[1])))
    }
    return(invisible(NULL))
  }

  # No existing row — plain INSERT (DuckDB forwards to master catalog for seq DEFAULT).
  DBI::dbExecute(
    con,
    "INSERT INTO master.admin.merge_conflicts
       (merge_request_id, table_name, plot_number, project_id,
        species_code, layer_code, details)
     VALUES (?, ?, ?, ?, ?, ?, ?)",
    list(mr_id, as.character(table_name), as.character(plot_number), pid, sc, lc,
         as.character(details_json))
  )
}

.to_json <- function(x) {
  tryCatch(
    as.character(jsonlite::toJSON(x, auto_unbox = TRUE, na = "null")),
    error = function(e) "{}"
  )
}

.detect_env_conflicts <- function(con, mr_id) {
  rows <- tryCatch(
    DBI::dbGetQuery(
      con,
      "SELECT s.plot_number, s.project_id,
              s.base_row_version AS staged_rv, c.row_version AS core_rv,
              s.latitude     AS s_lat,  c.latitude     AS c_lat,
              s.longitude    AS s_lon,  c.longitude    AS c_lon,
              s.elevation_m  AS s_elev, c.elevation_m  AS c_elev,
              s.survey_date  AS s_date, c.survey_date  AS c_date,
              s.surveyor_name AS s_surv, c.surveyor_name AS c_surv,
              s.plot_notes   AS s_notes, c.plot_notes  AS c_notes
       FROM master.staging.env s
       JOIN master.core.env c
         ON  c.plot_number = s.plot_number
         AND c.project_id  = s.project_id
       WHERE s.merge_request_id = ?
         AND s.base_row_version IS NOT NULL
         AND c.row_version > s.base_row_version",
      list(mr_id)
    ),
    error = function(e) data.frame()
  )
  if (nrow(rows) == 0) return(invisible(NULL))

  for (i in seq_len(nrow(rows))) {
    r       <- rows[i, , drop = FALSE]
    changes <- list(row_version = list(staged_base  = r$staged_rv[1],
                                       core_current = r$core_rv[1]))
    for (p in list(c("s_lat","c_lat","latitude"), c("s_lon","c_lon","longitude"),
                   c("s_elev","c_elev","elevation_m"), c("s_date","c_date","survey_date"),
                   c("s_surv","c_surv","surveyor_name"), c("s_notes","c_notes","plot_notes"))) {
      sv <- r[[p[1]]][1]; cv <- r[[p[2]]][1]
      if (is.na(sv) && is.na(cv)) next
      if (!is.na(sv) && !is.na(cv) && as.character(sv) == as.character(cv)) next
      changes[[p[3]]] <- list(staged = sv, core = cv)
    }
    .insert_conflict(con, mr_id, "env", r$plot_number[1], r$project_id[1],
                     NA, NA, .to_json(changes))
  }
}

.detect_su_conflicts <- function(con, mr_id) {
  rows <- tryCatch(
    DBI::dbGetQuery(
      con,
      "SELECT s.plot_number, s.project_id,
              s.base_row_version AS staged_rv, c.row_version AS core_rv,
              s.su_number    AS s_su,   c.su_number   AS c_su,
              s.bec_zone     AS s_zone, c.bec_zone    AS c_zone,
              s.bec_subzone  AS s_sub,  c.bec_subzone AS c_sub,
              s.site_series  AS s_ser,  c.site_series AS c_ser
       FROM master.staging.su s
       JOIN master.core.su c
         ON  c.plot_number = s.plot_number
         AND c.project_id  = s.project_id
       WHERE s.merge_request_id = ?
         AND s.base_row_version IS NOT NULL
         AND c.row_version > s.base_row_version",
      list(mr_id)
    ),
    error = function(e) data.frame()
  )
  if (nrow(rows) == 0) return(invisible(NULL))

  for (i in seq_len(nrow(rows))) {
    r       <- rows[i, , drop = FALSE]
    changes <- list(row_version = list(staged_base  = r$staged_rv[1],
                                       core_current = r$core_rv[1]))
    for (p in list(c("s_su","c_su","su_number"), c("s_zone","c_zone","bec_zone"),
                   c("s_sub","c_sub","bec_subzone"), c("s_ser","c_ser","site_series"))) {
      sv <- r[[p[1]]][1]; cv <- r[[p[2]]][1]
      if (is.na(sv) && is.na(cv)) next
      if (!is.na(sv) && !is.na(cv) && as.character(sv) == as.character(cv)) next
      changes[[p[3]]] <- list(staged = sv, core = cv)
    }
    .insert_conflict(con, mr_id, "su", r$plot_number[1], r$project_id[1],
                     NA, NA, .to_json(changes))
  }
}

.detect_veg_conflicts <- function(con, mr_id) {
  rows <- tryCatch(
    DBI::dbGetQuery(
      con,
      "SELECT s.plot_number, s.project_id, s.species_code, s.layer_code,
              s.base_row_version AS staged_rv, c.row_version AS core_rv,
              s.cover1 AS s_c1, c.cover1 AS c_c1,
              s.cover2 AS s_c2, c.cover2 AS c_c2,
              s.totala AS s_ta, c.totala AS c_ta,
              s.totalb AS s_tb, c.totalb AS c_tb,
              s.flag   AS s_fl, c.flag   AS c_fl
       FROM master.staging.veg s
       JOIN master.core.veg c
         ON  c.plot_number  = s.plot_number
         AND c.project_id   = s.project_id
         AND c.species_code = s.species_code
         AND c.layer_code   = s.layer_code
       WHERE s.merge_request_id = ?
         AND s.base_row_version IS NOT NULL
         AND c.row_version > s.base_row_version",
      list(mr_id)
    ),
    error = function(e) data.frame()
  )
  if (nrow(rows) == 0) return(invisible(NULL))

  for (i in seq_len(nrow(rows))) {
    r       <- rows[i, , drop = FALSE]
    changes <- list(row_version = list(staged_base  = r$staged_rv[1],
                                       core_current = r$core_rv[1]))
    for (p in list(c("s_c1","c_c1","cover1"), c("s_c2","c_c2","cover2"),
                   c("s_ta","c_ta","totala"), c("s_tb","c_tb","totalb"),
                   c("s_fl","c_fl","flag"))) {
      sv <- r[[p[1]]][1]; cv <- r[[p[2]]][1]
      if (is.na(sv) && is.na(cv)) next
      if (!is.na(sv) && !is.na(cv) && as.character(sv) == as.character(cv)) next
      changes[[p[3]]] <- list(staged = sv, core = cv)
    }
    .insert_conflict(con, mr_id, "veg", r$plot_number[1], r$project_id[1],
                     r$species_code[1], r$layer_code[1], .to_json(changes))
  }
}

#' List conflicts for a merge request.
#'
#' @param con              DuckDB connection.
#' @param merge_request_id Integer.
#' @param unresolved_only  Logical. Default TRUE.
#' @param limit            Integer.
#' @return data.frame.
merge_request_get_conflicts <- function(con, merge_request_id,
                                         unresolved_only = TRUE, limit = 500L) {
  sql    <- "SELECT id, table_name, plot_number, project_id, species_code, layer_code,
                    created_utc, resolution, details
             FROM master.admin.merge_conflicts
             WHERE merge_request_id = ?"
  params <- list(as.integer(merge_request_id))
  if (isTRUE(unresolved_only)) sql <- paste0(sql, " AND resolution IS NULL")
  sql    <- paste0(sql, " ORDER BY created_utc DESC LIMIT ?")
  params <- c(params, list(as.integer(limit)))
  DBI::dbGetQuery(con, sql, params)
}

#' Count unresolved conflicts for a merge request.
#'
#' @param con              DuckDB connection.
#' @param merge_request_id Integer.
#' @return Integer.
merge_request_unresolved_count <- function(con, merge_request_id) {
  res <- tryCatch(
    DBI::dbGetQuery(
      con,
      "SELECT COUNT(*) AS n FROM master.admin.merge_conflicts
       WHERE merge_request_id = ? AND resolution IS NULL",
      list(as.integer(merge_request_id))
    ),
    error = function(e) data.frame(n = 0L)
  )
  as.integer(res$n[1])
}

#' Resolve a single conflict entry.
#'
#' @param con         DuckDB connection.
#' @param conflict_id Integer. Row id in master.admin.merge_conflicts.
#' @param resolution  "keep_staged"  — apply the incoming value to core when merging.
#'                    "keep_core"    — discard staged value; core wins.
#'                    "dismiss"      — acknowledge trivial difference; apply staged.
#' @param actor       Character. Reviewer username.
merge_request_resolve_conflict <- function(con, conflict_id, resolution,
                                            actor = Sys.getenv("USER", "unknown")) {
  if (!resolution %in% c("keep_staged", "keep_core", "dismiss")) {
    stop("resolution must be 'keep_staged', 'keep_core', or 'dismiss'")
  }
  DBI::dbExecute(
    con,
    "UPDATE master.admin.merge_conflicts
     SET resolution = ?, resolved_by = ?, resolved_utc = now()
     WHERE id = ?",
    list(resolution, as.character(actor), as.integer(conflict_id))
  )
  invisible(TRUE)
}

#' Approve and apply a merge request to master.core.
#'
#' Before applying, refreshes conflict detection. Blocks if unresolved conflicts
#' remain. Rows with resolution 'keep_core' are skipped; all others are applied.
#'
#' In production PostgreSQL, `row_version` and `last_modified_utc` are updated
#' automatically by the `core.row_version_trigger()` BEFORE UPDATE trigger.
#'
#' @param con              DuckDB connection (master attached).
#' @param merge_request_id Integer.
#' @param reviewer         Character. Reviewer username.
#' @param review_notes     Character. Optional notes.
merge_approve_request <- function(con, merge_request_id, reviewer, review_notes = "") {
  mr_id <- as.integer(merge_request_id)

  merge_request_refresh_conflicts(con, mr_id)

  n_unresolved <- merge_request_unresolved_count(con, mr_id)
  if (n_unresolved > 0) {
    stop(sprintf(
      "Merge blocked: %d unresolved conflict(s). Resolve via merge_request_resolve_conflict().",
      n_unresolved
    ))
  }

  # Resolve reviewer user_id by email — reviewer is always authenticated (admin role).
  uid_row <- tryCatch(
    DBI::dbGetQuery(
      con,
      "SELECT id FROM master.admin.users WHERE email = ? LIMIT 1",
      list(as.character(reviewer))
    ),
    error = function(e) data.frame(id = integer(0))
  )
  approved_by_user_id <- if (nrow(uid_row) > 0) as.integer(uid_row$id[1]) else NA_integer_

  .apply_env(con, mr_id)
  .apply_su( con, mr_id)
  .apply_veg(con, mr_id)

  .delete_staging(con, mr_id)

  DBI::dbExecute(
    con,
    "UPDATE master.admin.merge_requests
     SET status = 'merged', reviewer = ?, reviewer_user_id = ?,
         review_notes = ?, reviewed_utc = now()
     WHERE id = ?",
    list(as.character(reviewer), approved_by_user_id,
         as.character(review_notes), mr_id)
  )

  # Fetch record counts to populate merge_history
  mr_row <- tryCatch(
    DBI::dbGetQuery(
      con,
      "SELECT env_record_count, su_record_count, veg_record_count
       FROM master.admin.merge_requests WHERE id = ?",
      list(mr_id)
    ),
    error = function(e) data.frame(env_record_count = 0L, su_record_count = 0L, veg_record_count = 0L)
  )
  total_records <- as.integer(
    (mr_row$env_record_count[1L] %||% 0L) +
    (mr_row$su_record_count[1L]  %||% 0L) +
    (mr_row$veg_record_count[1L] %||% 0L)
  )

  tryCatch(
    DBI::dbExecute(
      con,
      "INSERT INTO master.admin.merge_history
         (merge_request_id, approved_by_user_id, record_count)
       VALUES (?, ?, ?)",
      list(mr_id, approved_by_user_id, total_records)
    ),
    error = function(e) warning("merge_history INSERT failed: ", e$message)
  )

  invisible(TRUE)
}

#' Reject a merge request, discarding all staged data.
#'
#' @param con              DuckDB connection.
#' @param merge_request_id Integer.
#' @param reviewer         Character. Reviewer username.
#' @param review_notes     Character. Optional notes.
merge_reject_request <- function(con, merge_request_id, reviewer, review_notes = "") {
  mr_id <- as.integer(merge_request_id)

  # Resolve reviewer user_id by email — reviewer is always authenticated (admin role).
  uid_row <- tryCatch(
    DBI::dbGetQuery(
      con,
      "SELECT id FROM master.admin.users WHERE email = ? LIMIT 1",
      list(as.character(reviewer))
    ),
    error = function(e) data.frame(id = integer(0))
  )
  reviewer_user_id <- if (nrow(uid_row) > 0) as.integer(uid_row$id[1]) else NA_integer_

  .delete_staging(con, mr_id)
  DBI::dbExecute(
    con,
    "DELETE FROM master.admin.merge_conflicts WHERE merge_request_id = ?",
    list(mr_id)
  )
  DBI::dbExecute(
    con,
    "UPDATE master.admin.merge_requests
     SET status = 'rejected', reviewer = ?, reviewer_user_id = ?,
         review_notes = ?, reviewed_utc = now()
     WHERE id = ?",
    list(as.character(reviewer), reviewer_user_id,
         as.character(review_notes), mr_id)
  )
  invisible(TRUE)
}

# ── apply helpers ───────────────────────────────────────────────────────────
# The LEFT JOIN + WHERE clause ensures rows with resolution = 'keep_core'
# (or 'dismiss' is treated same as 'keep_staged' — apply the staged value)
# are filtered out of the INSERT. Only non-conflicted rows or keep_staged rows
# reach master.core.

# NOTE: In production PostgreSQL, the BEFORE UPDATE trigger auto-increments
# row_version and last_modified_utc. No manual update is needed here.

.apply_env <- function(con, mr_id) {
  DBI::dbExecute(
    con,
    "INSERT INTO master.core.env
       (plot_number, project_id, latitude, longitude, elevation_m,
        survey_date, surveyor_name, plot_notes, modified_by)
     SELECT s.plot_number, s.project_id, s.latitude, s.longitude, s.elevation_m,
            s.survey_date, s.surveyor_name, s.plot_notes, s.modified_by
     FROM master.staging.env s
     LEFT JOIN master.admin.merge_conflicts mc
       ON  mc.merge_request_id = s.merge_request_id
       AND mc.table_name       = 'env'
       AND mc.plot_number      = s.plot_number
       AND mc.project_id       = s.project_id
       AND (mc.species_code IS NULL OR mc.species_code = '')
       AND (mc.layer_code   IS NULL OR mc.layer_code   = '')
     WHERE s.merge_request_id = ?
       AND (mc.id IS NULL OR mc.resolution IN ('keep_staged', 'dismiss'))
     ON CONFLICT (plot_number) DO UPDATE SET
       latitude      = EXCLUDED.latitude,
       longitude     = EXCLUDED.longitude,
       elevation_m   = EXCLUDED.elevation_m,
       survey_date   = EXCLUDED.survey_date,
       surveyor_name = EXCLUDED.surveyor_name,
       plot_notes    = EXCLUDED.plot_notes,
       modified_by   = EXCLUDED.modified_by",
    list(mr_id)
  )
}

.apply_su <- function(con, mr_id) {
  DBI::dbExecute(
    con,
    "INSERT INTO master.core.su
       (plot_number, project_id, su_number, bec_zone, bec_subzone, site_series, modified_by)
     SELECT s.plot_number, s.project_id, s.su_number,
            s.bec_zone, s.bec_subzone, s.site_series, s.modified_by
     FROM master.staging.su s
     LEFT JOIN master.admin.merge_conflicts mc
       ON  mc.merge_request_id = s.merge_request_id
       AND mc.table_name       = 'su'
       AND mc.plot_number      = s.plot_number
       AND mc.project_id       = s.project_id
       AND (mc.species_code IS NULL OR mc.species_code = '')
       AND (mc.layer_code   IS NULL OR mc.layer_code   = '')
     WHERE s.merge_request_id = ?
       AND (mc.id IS NULL OR mc.resolution IN ('keep_staged', 'dismiss'))
     ON CONFLICT (plot_number) DO UPDATE SET
       su_number   = EXCLUDED.su_number,
       bec_zone    = EXCLUDED.bec_zone,
       bec_subzone = EXCLUDED.bec_subzone,
       site_series = EXCLUDED.site_series,
       modified_by = EXCLUDED.modified_by",
    list(mr_id)
  )
}

.apply_veg <- function(con, mr_id) {
  DBI::dbExecute(
    con,
    "INSERT INTO master.core.veg
       (plot_number, species_code, layer_code,
        cover1, height1, cover2, height2, cover3, height3, totala, heighta,
        cover4, height4, cover5, height5, cover5a, height5a, cover5b, height5b,
        cover5c, height5c, totalb, heightb, cover6, height6,
        cover7, cover8, cover9, cover10,
        collected, flag, veg_id, ll, af, dc, ut, vi, pv, pg, ffa,
        cultural1, cultural2, other1, other2, project_id, modified_by)
     SELECT s.plot_number, s.species_code, s.layer_code,
            s.cover1, s.height1, s.cover2, s.height2, s.cover3, s.height3,
            s.totala, s.heighta, s.cover4, s.height4, s.cover5, s.height5,
            s.cover5a, s.height5a, s.cover5b, s.height5b, s.cover5c, s.height5c,
            s.totalb, s.heightb, s.cover6, s.height6,
            s.cover7, s.cover8, s.cover9, s.cover10,
            s.collected, s.flag, s.veg_id, s.ll, s.af, s.dc, s.ut, s.vi,
            s.pv, s.pg, s.ffa, s.cultural1, s.cultural2, s.other1, s.other2,
            s.project_id, s.modified_by
     FROM master.staging.veg s
     LEFT JOIN master.admin.merge_conflicts mc
       ON  mc.merge_request_id = s.merge_request_id
       AND mc.table_name       = 'veg'
       AND mc.plot_number      = s.plot_number
       AND mc.project_id       = s.project_id
       AND mc.species_code     = s.species_code
       AND mc.layer_code       = s.layer_code
     WHERE s.merge_request_id = ?
       AND (mc.id IS NULL OR mc.resolution IN ('keep_staged', 'dismiss'))
     ON CONFLICT (plot_number, species_code, layer_code, project_id) DO UPDATE SET
       cover1    = EXCLUDED.cover1,    height1   = EXCLUDED.height1,
       cover2    = EXCLUDED.cover2,    height2   = EXCLUDED.height2,
       cover3    = EXCLUDED.cover3,    height3   = EXCLUDED.height3,
       totala    = EXCLUDED.totala,    heighta   = EXCLUDED.heighta,
       cover4    = EXCLUDED.cover4,    height4   = EXCLUDED.height4,
       cover5    = EXCLUDED.cover5,    height5   = EXCLUDED.height5,
       cover5a   = EXCLUDED.cover5a,   height5a  = EXCLUDED.height5a,
       cover5b   = EXCLUDED.cover5b,   height5b  = EXCLUDED.height5b,
       cover5c   = EXCLUDED.cover5c,   height5c  = EXCLUDED.height5c,
       totalb    = EXCLUDED.totalb,    heightb   = EXCLUDED.heightb,
       cover6    = EXCLUDED.cover6,    height6   = EXCLUDED.height6,
       cover7    = EXCLUDED.cover7,    cover8    = EXCLUDED.cover8,
       cover9    = EXCLUDED.cover9,    cover10   = EXCLUDED.cover10,
       collected = EXCLUDED.collected, flag      = EXCLUDED.flag,
       veg_id    = EXCLUDED.veg_id,    ll        = EXCLUDED.ll,
       af        = EXCLUDED.af,        dc        = EXCLUDED.dc,
       ut        = EXCLUDED.ut,        vi        = EXCLUDED.vi,
       pv        = EXCLUDED.pv,        pg        = EXCLUDED.pg,
       ffa       = EXCLUDED.ffa,       cultural1 = EXCLUDED.cultural1,
       cultural2 = EXCLUDED.cultural2, other1    = EXCLUDED.other1,
       other2    = EXCLUDED.other2,    modified_by = EXCLUDED.modified_by",
    list(mr_id)
  )
}


# =============================================================================
# 7. Field-user sync helpers (used by mod_sync)
# =============================================================================

#' Retrieve local dirty rows (insert / update) across Env, SU, Veg.
#'
#' @param con        DuckDB connection.
#' @param project_id Optional character/integer filter.
#' @return Named list: `$env`, `$su`, `$veg` — each a data.frame with a
#'   `change_type` column ("insert" | "update").
sync_get_local_changes <- function(con, project_id = NULL) {
  empty_with_type <- function() data.frame(change_type = character(0))

  .query_table <- function(tbl, key_cols, extra_cols) {
    if (!DBI::dbExistsTable(con, tbl)) return(empty_with_type())
    fields <- tryCatch(DBI::dbListFields(con, tbl), error = function(e) character(0))
    has_lmu <- "local_modified_utc" %in% fields
    has_mrv <- "master_row_version"  %in% fields
    if (!has_lmu) return(empty_with_type())

    pid_filter <- ""
    pid_params <- list()
    if (!is.null(project_id) && nzchar(as.character(project_id))) {
      pid_filter <- " AND ProjectID = ?"
      pid_params <- list(as.character(project_id))
    }

    sql <- sprintf(
      "SELECT %s,
              CASE WHEN master_row_version IS NULL THEN 'insert' ELSE 'update' END AS change_type
       FROM %s
       WHERE local_modified_utc IS NOT NULL%s",
      paste(c(key_cols, extra_cols), collapse = ", "),
      tbl,
      pid_filter
    )
    if (!has_mrv) {
      sql <- sprintf(
        "SELECT %s, 'insert' AS change_type
         FROM %s
         WHERE local_modified_utc IS NOT NULL%s",
        paste(c(key_cols, extra_cols), collapse = ", "),
        tbl,
        pid_filter
      )
    }
    tryCatch(
      DBI::dbGetQuery(con, sql, pid_params),
      error = function(e) empty_with_type()
    )
  }

  env_extra  <- intersect(
    c("Latitude", "Longitude", "Elevation", "Date", "SiteSurveyor", "SiteNotes"),
    tryCatch(DBI::dbListFields(con, "Env"), error = function(e) character(0))
  )
  su_extra   <- intersect(
    c("SiteUnit"),
    tryCatch(DBI::dbListFields(con, "SU"), error = function(e) character(0))
  )
  veg_extra  <- intersect(
    c("Species", "Layer", "Cover1"),
    tryCatch(DBI::dbListFields(con, "Veg"), error = function(e) character(0))
  )

  list(
    env = .query_table("Env", c("PlotNumber", "ProjectID"), env_extra),
    su  = .query_table("SU",  c("PlotNumber"),              su_extra),
    veg = .query_table("Veg", c("PlotNumber"),              veg_extra)
  )
}

#' Count incoming rows available from master since last pull watermark.
#'
#' @param con        DuckDB connection.
#' @param project_id Optional filter.
#' @return Named list: `$env`, `$su`, `$veg` (integer counts), `$available` (logical).
sync_count_incoming <- function(con, project_id = NULL) {
  not_available <- list(env = 0L, su = 0L, veg = 0L, available = FALSE)
  if (!sync_cloud_connected(con)) return(not_available)

  .count_table <- function(master_tbl, watermark_name) {
    last_pull <- sync_get_watermark(con, watermark_name, "pull")
    filters <- "1=1"
    params  <- list()
    if (!is.null(project_id) && nzchar(as.character(project_id))) {
      filters <- paste0(filters, " AND \"ProjectID\" = ?")
      params  <- c(params, list(as.character(project_id)))
    }
    if (!is.null(last_pull)) {
      filters <- paste0(filters, " AND \"lastModifiedUTC\" > ?")
      params  <- c(params, list(last_pull))
    }
    res <- tryCatch(
      DBI::dbGetQuery(
        con,
        sprintf("SELECT COUNT(*) AS n FROM %s WHERE %s", master_tbl, filters),
        params
      ),
      error = function(e) data.frame(n = 0L)
    )
    as.integer(res$n[1] %||% 0L)
  }

  list(
    env       = .count_table("master.core.env", "env"),
    su        = .count_table("master.core.su",  "su"),
    veg       = .count_table("master.core.veg", "veg"),
    available = TRUE
  )
}

#' Retrieve the current user's merge requests from master.
#'
#' @param con             DuckDB connection.
#' @param submitter       Character. Matched against `submitter_name`.
#' @param show_approved   Logical. Include approved/merged rows.
#' @param show_rejected   Logical. Include rejected rows.
#' @return data.frame with columns:
#'   id, project_id, submitted_utc, status, env_record_count, su_record_count,
#'   veg_record_count, review_notes, reviewed_utc.
sync_get_user_merge_requests <- function(con, submitter,
                                          show_approved = TRUE,
                                          show_rejected = TRUE) {
  empty_mr <- data.frame(
    id               = integer(0),
    project_id       = integer(0),
    submitted_utc    = as.POSIXct(character(0)),
    status           = character(0),
    env_record_count = integer(0),
    su_record_count  = integer(0),
    veg_record_count = integer(0),
    review_notes     = character(0),
    reviewed_utc     = as.POSIXct(character(0)),
    stringsAsFactors = FALSE
  )
  if (!sync_cloud_connected(con)) return(empty_mr)

  sql    <- paste0(
    "SELECT id, project_id, submitted_utc, status,",
    " env_record_count, su_record_count, veg_record_count,",
    " review_notes, reviewed_utc",
    " FROM master.admin.merge_requests",
    " WHERE submitter_name = ?",
    " ORDER BY submitted_utc DESC"
  )
  params <- list(as.character(submitter))

  out <- tryCatch(
    DBI::dbGetQuery(con, sql, params),
    error = function(e) empty_mr
  )
  if (nrow(out) == 0) return(empty_mr)

  if (!isTRUE(show_approved)) {
    out <- out[!out$status %in% c("merged", "approved"), , drop = FALSE]
  }
  if (!isTRUE(show_rejected)) {
    out <- out[out$status != "rejected", , drop = FALSE]
  }
  out
}
