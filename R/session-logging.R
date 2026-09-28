# Session and project audit logging -----------------------------------------

vpro_log_timestamp <- function(time) {
  format(time, "%Y-%m-%d %H:%M:%OS6", tz = "UTC")
}

vpro_log_scalar <- function(value, name) {
  if (!is.character(value) || length(value) != 1L || is.na(value) || !nzchar(value)) {
    stop("`", name, "` must be one non-empty character string.", call. = FALSE)
  }
  value
}

vpro_log_context_project <- function(context) {
  vpro_project_assert_context(context)
  if (is.null(context$active)) {
    stop("Project audit logging requires an active VPRO project.", call. = FALSE)
  }
  context$active
}

#' Record a VPRO user login
#'
#' Inserts one row in `VPro64.USysUserLog` and returns that SQLite rowid.  The
#' rowid is the session token required by `vpro_session_logout()`, so concurrent
#' sessions for the same user and machine cannot close one another.
#'
#' @param context A VPRO project context whose coordinator has `VPro64`
#'   attached.
#' @param user Explicit user name.
#' @param machine Explicit local-machine name.
#' @param time Login time.
#'
#' @return A list with `rowid`, `user`, `machine`, and `in_time`.
#' @export
vpro_session_login <- function(context, user, machine = Sys.info()[["nodename"]], time = Sys.time()) {
  vpro_project_assert_context(context)
  user <- vpro_log_scalar(user, "user")
  machine <- vpro_log_scalar(machine, "machine")
  if (!("VPro64" %in% vpro_db_list(context$con))) {
    stop("Session logging database is not attached: VPro64", call. = FALSE)
  }
  paths <- DBI::dbGetQuery(context$con, "SELECT path FROM duckdb_databases() WHERE database_name = ?", params = list("VPro64"))$path
  if (length(paths) != 1L || is.na(paths[[1L]]) || !file.exists(paths[[1L]])) {
    stop("Session logging database path is unavailable: VPro64", call. = FALSE)
  }
  con <- DBI::dbConnect(RSQLite::SQLite(), paths[[1L]])
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  DBI::dbExecute(
    con,
    'INSERT INTO "USysUserLog" ("User", "InTime", "OutTime", "LocalMachine") VALUES (?, ?, NULL, ?)',
    params = list(user, vpro_log_timestamp(time), machine)
  )
  list(rowid = DBI::dbGetQuery(con, "SELECT last_insert_rowid() AS rowid")$rowid[[1L]], user = user, machine = machine, in_time = vpro_log_timestamp(time))
}

#' Close one VPRO user-login row
#'
#' @param context A VPRO project context.
#' @param login A token returned by `vpro_session_login()`.
#' @param time Logout time.
#'
#' @return `TRUE` if this open session was closed; `FALSE` if it was already
#'   closed. An unknown rowid is an error.
#' @export
vpro_session_logout <- function(context, login, time = Sys.time()) {
  vpro_project_assert_context(context)
  if (!is.list(login) || is.null(login$rowid) || length(login$rowid) != 1L || is.na(login$rowid)) {
    stop("`login` must be a token returned by `vpro_session_login()`.", call. = FALSE)
  }
  paths <- DBI::dbGetQuery(context$con, "SELECT path FROM duckdb_databases() WHERE database_name = ?", params = list("VPro64"))$path
  if (length(paths) != 1L || is.na(paths[[1L]]) || !file.exists(paths[[1L]])) {
    stop("Session logging database path is unavailable: VPro64", call. = FALSE)
  }
  con <- DBI::dbConnect(RSQLite::SQLite(), paths[[1L]])
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  found <- DBI::dbGetQuery(con, 'SELECT "OutTime" FROM "USysUserLog" WHERE rowid = ?', params = list(login$rowid))
  if (nrow(found) != 1L) {
    stop("VPRO login row does not exist.", call. = FALSE)
  }
  if (!is.na(found$OutTime[[1L]])) {
    return(invisible(FALSE))
  }
  updated <- DBI::dbExecute(con, 'UPDATE "USysUserLog" SET "OutTime" = ? WHERE rowid = ? AND "OutTime" IS NULL', params = list(vpro_log_timestamp(time), login$rowid))
  invisible(updated == 1L)
}

#' List currently open VPRO sessions
#'
#' @param context A VPRO project context.
#'
#' @return A data frame of open session rows, including their SQLite `rowid`.
#' @export
vpro_session_open <- function(context) {
  vpro_project_assert_context(context)
  paths <- DBI::dbGetQuery(context$con, "SELECT path FROM duckdb_databases() WHERE database_name = ?", params = list("VPro64"))$path
  if (length(paths) != 1L || is.na(paths[[1L]]) || !file.exists(paths[[1L]])) {
    stop("Session logging database path is unavailable: VPro64", call. = FALSE)
  }
  con <- DBI::dbConnect(RSQLite::SQLite(), paths[[1L]])
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  DBI::dbGetQuery(con, 'SELECT rowid, "User", "InTime", "OutTime", "LocalMachine" FROM "USysUserLog" WHERE "OutTime" IS NULL ORDER BY "User", "InTime", rowid')
}

#' Write project lifecycle audit events
#'
#' Adds `On`/`Off` and `Open`/`Close` events to the explicit active project.
#' An `Open` event also records changed reference descriptions from the attached
#' `VLists` metadata. All rows for one call are committed in one SQLite
#' transaction. This is headless and does not infer a user from Shiny or global
#' configuration state.
#'
#' @param context A VPRO project context with an active project and attached
#'   `VLists` database.
#' @param user Explicit audit user.
#' @param event One of `"On"`, `"Off"`, `"Open"`, or `"Close"`.
#' @param time Event time.
#'
#' @return A data frame of changed reference descriptions for `"Open"`; empty
#'   otherwise.
#' @export
vpro_project_log_lifecycle <- function(context, user, event = c("On", "Off", "Open", "Close"), time = Sys.time()) {
  project <- vpro_log_context_project(context)
  user <- vpro_log_scalar(user, "user")
  event <- match.arg(event)
  descriptions <- if (identical(event, "Open")) vpro_reference_descriptions(context) else NULL
  con <- DBI::dbConnect(RSQLite::SQLite(), project$path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  audit <- DBI::dbQuoteIdentifier(con, vpro_project_table(project$project, "Audit"))
  changed <- DBI::dbWithTransaction(con, {
    changed <- data.frame(Table = character(), Before = character(), After = character(), stringsAsFactors = FALSE)
    DBI::dbExecute(
      con,
      paste("INSERT INTO", audit, '("Project", "User", "Table", "EditWhen") VALUES (?, ?, ?, ?)'),
      params = list(project$project, user, event, vpro_log_timestamp(time))
    )
    if (!is.null(descriptions)) {
      for (index in seq_len(nrow(descriptions))) {
        table <- descriptions$Table[[index]]
        old <- DBI::dbGetQuery(con, paste("SELECT \"AfterEdit\" FROM", audit, 'WHERE "Table" = ? ORDER BY "EditWhen" DESC, rowid DESC LIMIT 1'), params = list(table))$AfterEdit
        old <- if (length(old) != 1L || is.na(old[[1L]]) || !nzchar(old[[1L]])) "Unknown" else old[[1L]]
        current <- descriptions$Description[[index]]
        if (!identical(old, current)) {
          DBI::dbExecute(
            con,
            paste("INSERT INTO", audit, '("Project", "User", "Table", "EditWhen", "BeforeEdit", "AfterEdit") VALUES (?, ?, ?, ?, ?, ?)'),
            params = list(project$project, user, table, vpro_log_timestamp(time), old, current)
          )
          changed <- rbind(changed, data.frame(Table = table, Before = old, After = current, stringsAsFactors = FALSE))
        }
      }
    }
    changed
  })
  changed
}
