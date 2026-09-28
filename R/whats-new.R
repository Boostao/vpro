# What's New messages -------------------------------------------------------

vpro_whats_new_path <- function(context) {
  vpro_project_assert_context(context)
  paths <- DBI::dbGetQuery(
    context$con,
    "SELECT path FROM duckdb_databases() WHERE database_name = ?",
    params = list("VPro64")
  )$path
  if (length(paths) != 1L || is.na(paths[[1L]]) || !file.exists(paths[[1L]])) {
    stop("What's New requires an attached VPro64 SQLite database.", call. = FALSE)
  }
  paths[[1L]]
}

#' List What's New messages
#'
#' Reads the `tblWhatsNew` table of the VPro64 database attached to a VPRO
#' session context. SQLite row IDs identify messages for viewed-state updates.
#'
#' @param context A VPRO project context with VPro64 attached.
#' @return A data frame with `row_id`, `Date`, `Change`, and `Viewed`, newest first.
#' @export
vpro_whats_new_list <- function(context) {
  con <- DBI::dbConnect(RSQLite::SQLite(), vpro_whats_new_path(context), flags = RSQLite::SQLITE_RO)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  rows <- DBI::dbGetQuery(
    con,
    'SELECT rowid AS row_id, "Date", "Change", "Viewed" FROM "tblWhatsNew" ORDER BY "Date" DESC, rowid DESC'
  )
  rows$Viewed <- !is.na(rows$Viewed) & rows$Viewed != 0L
  rows
}

vpro_whats_new_row_id <- function(row_id) {
  if (!is.numeric(row_id) || length(row_id) != 1L || is.na(row_id) || !is.finite(row_id) || row_id < 1 || row_id != floor(row_id)) {
    stop("`row_id` must be a positive whole number.", call. = FALSE)
  }
  row_id
}

#' Mark a What's New message as viewed or unviewed
#'
#' @param context A VPRO project context with VPro64 attached.
#' @param row_id SQLite row ID returned by `vpro_whats_new_list()`.
#' @param viewed One non-missing logical value.
#' @return `TRUE`, invisibly. An unknown message is an error.
#' @export
vpro_whats_new_set_viewed <- function(context, row_id, viewed) {
  row_id <- vpro_whats_new_row_id(row_id)
  if (!is.logical(viewed) || length(viewed) != 1L || is.na(viewed)) {
    stop("`viewed` must be TRUE or FALSE.", call. = FALSE)
  }
  con <- DBI::dbConnect(RSQLite::SQLite(), vpro_whats_new_path(context))
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  count <- DBI::dbExecute(
    con,
    'UPDATE "tblWhatsNew" SET "Viewed" = ? WHERE rowid = ?',
    params = list(as.integer(viewed), row_id)
  )
  if (count != 1L) {
    stop("What's New message does not exist.", call. = FALSE)
  }
  invisible(TRUE)
}

#' Mark all What's New messages as viewed
#'
#' @param context A VPRO project context with VPro64 attached.
#' @return Number of updated messages, invisibly.
#' @export
vpro_whats_new_mark_all_viewed <- function(context) {
  con <- DBI::dbConnect(RSQLite::SQLite(), vpro_whats_new_path(context))
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  invisible(DBI::dbExecute(con, 'UPDATE "tblWhatsNew" SET "Viewed" = 1 WHERE "Viewed" IS NULL OR "Viewed" = 0'))
}
