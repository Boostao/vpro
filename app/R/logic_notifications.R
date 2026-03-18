# Minimal in-app notifications via vpro_messages (DuckDB attached as schema 'messages').

notifications_messages_available <- function(con) {
  attached <- tryCatch({
    DBI::dbGetQuery(con, "SELECT database_name FROM duckdb_databases()")$database_name
  }, error = function(e) character(0))
  if (!"messages" %in% attached) return(FALSE)
  tryCatch({
    DBI::dbExistsTable(con, "messages.tblMessageBoard")
  }, error = function(e) FALSE)
}

notifications_post_message <- function(con,
                                      title,
                                      message,
                                      topictype = "system",
                                      audience = "all",
                                      from = Sys.getenv("USER", "unknown"),
                                      topicdate = Sys.Date()) {
  if (is.null(con)) return(invisible(FALSE))
  if (!notifications_messages_available(con)) return(invisible(FALSE))
  DBI::dbExecute(
    con,
    "INSERT INTO messages.tblMessageBoard (topictype, topicdate, audience, _from, title, message)
     VALUES (?, ?, ?, ?, ?, ?)",
    list(as.character(topictype), as.Date(topicdate), as.character(audience), as.character(from), as.character(title), as.character(message))
  )
  invisible(TRUE)
}

notifications_post_merge_event <- function(con,
                                          merge_request_id,
                                          project_id,
                                          event,
                                          actor = Sys.getenv("USER", "unknown"),
                                          audience = "all") {
  title <- sprintf("Merge request %s: %s", merge_request_id, event)
  project_text <- if (is.null(project_id) || !nzchar(as.character(project_id))) "" else as.character(project_id)
  body <- sprintf("Project: %s\nActor: %s", project_text, actor)
  notifications_post_message(con, title = title, message = body, topictype = "merge", audience = audience, from = actor)
}
