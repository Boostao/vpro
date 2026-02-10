# Authentication and RBAC helpers

auth_init_state <- function(state) {
  shiny::isolate({
    if (is.null(state$AuthAuthenticated)) state$AuthAuthenticated <- FALSE
    if (is.null(state$AuthUser)) state$AuthUser <- NULL
    if (is.null(state$AuthUserId)) state$AuthUserId <- NULL
    if (is.null(state$AuthRoles)) state$AuthRoles <- character(0)
    if (is.null(state$AuthPermissions)) state$AuthPermissions <- character(0)
  })
}

auth_parse_permissions <- function(value) {
  if (is.null(value)) return(character(0))
  if (is.list(value)) value <- unlist(value, use.names = FALSE)
  if (!is.character(value)) return(character(0))

  pieces <- unlist(lapply(value, function(item) {
    cleaned <- gsub("^[\\{\\[]|[\\}\\]]$", "", item)
    parts <- unlist(strsplit(cleaned, "[,[:space:]]+"))
    parts[nzchar(parts)]
  }))

  unique(pieces)
}

auth_fetch_roles_permissions <- function(con, user_id) {
  roles <- DBI::dbGetQuery(
    con,
    "SELECT r.role_name, r.permissions
     FROM master.admin.user_roles ur
     JOIN master.admin.roles r ON r.id = ur.role_id
     WHERE ur.user_id = ?",
    list(user_id)
  )

  role_names <- character(0)
  permissions <- character(0)

  if (nrow(roles) > 0) {
    role_names <- unique(roles$role_name)
    permissions <- unique(unlist(lapply(roles$permissions, auth_parse_permissions)))
  }

  list(roles = role_names, permissions = permissions)
}

auth_verify_password <- function(stored_hash, password) {
  if (!requireNamespace("bcrypt", quietly = TRUE)) {
    return(list(ok = FALSE, reason = "bcrypt package not available"))
  }
  if (is.null(stored_hash) || !nzchar(stored_hash)) {
    return(list(ok = FALSE, reason = "Missing password hash"))
  }
  ok <- bcrypt::checkpw(password, stored_hash)
  list(ok = isTRUE(ok), reason = if (ok) NULL else "Invalid credentials")
}

auth_login <- function(con, state, username, password) {
  auth_init_state(state)
  attached <- tryCatch({
    DBI::dbGetQuery(con, "SELECT database_name FROM duckdb_databases()")$database_name
  }, error = function(e) character(0))
  if (!("master" %in% attached)) {
    sync_require_cloud(con, allow_attach = TRUE)
  }

  user <- DBI::dbGetQuery(
    con,
    "SELECT id, username, password_hash, is_active
     FROM master.admin.users
     WHERE username = ?",
    list(username)
  )

  if (nrow(user) == 0 || !isTRUE(user$is_active[1])) {
    return(list(ok = FALSE, message = "Invalid username or inactive account"))
  }

  verify <- auth_verify_password(user$password_hash[1], password)
  if (!isTRUE(verify$ok)) {
    return(list(ok = FALSE, message = verify$reason %||% "Invalid credentials"))
  }

  roles_info <- auth_fetch_roles_permissions(con, user$id[1])

  state$AuthAuthenticated <- TRUE
  state$AuthUser <- user$username[1]
  state$AuthUserId <- user$id[1]
  state$AuthRoles <- roles_info$roles
  state$AuthPermissions <- roles_info$permissions
  state$User <- user$username[1]

  list(ok = TRUE, message = "Authenticated")
}

auth_logout <- function(state) {
  auth_init_state(state)
  state$AuthAuthenticated <- FALSE
  state$AuthUser <- NULL
  state$AuthUserId <- NULL
  state$AuthRoles <- character(0)
  state$AuthPermissions <- character(0)
}

auth_is_authenticated <- function(state) {
  shiny::isolate(isTRUE(state$AuthAuthenticated))
}

auth_user_has_permission <- function(state, permission) {
  if (!auth_is_authenticated(state)) return(FALSE)
  shiny::isolate({
    perms <- state$AuthPermissions %||% character(0)
    "*" %in% perms || permission %in% perms
  })
}

auth_require_permission <- function(state, permission) {
  if (!auth_user_has_permission(state, permission)) {
    stop(sprintf("Permission required: %s", permission))
  }
}
