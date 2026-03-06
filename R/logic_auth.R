# Authentication helpers
# Two user types:
#   guest  — email + full name only; read core/lists, write staging
#   admin  — email + bcrypt password; full access, can grant admin to others

auth_init_state <- function(state) {
  shiny::isolate({
    if (is.null(state$AuthAuthenticated)) state$AuthAuthenticated <- FALSE
    if (is.null(state$AuthUser))          state$AuthUser          <- NULL
    if (is.null(state$AuthUserId))        state$AuthUserId        <- NULL
    if (is.null(state$AuthRole))          state$AuthRole          <- NULL
    if (is.null(state$AuthRoles))         state$AuthRoles         <- character(0)
    if (is.null(state$AuthPermissions))   state$AuthPermissions   <- character(0)
  })
}

# Derive permissions from app_role (admin gets wildcard, guest gets scoped set)
.auth_permissions <- function(app_role) {
  if (identical(app_role, "admin")) c("*") else c("write:staging", "read:core")
}

# Populate reactive state from a user data.frame row
.auth_set_state <- function(state, user) {
  role <- user$app_role[1]
  state$AuthAuthenticated <- TRUE
  state$AuthUser          <- user$email[1]
  state$AuthUserId        <- user$id[1]
  state$AuthRole          <- role
  state$AuthRoles         <- role
  state$AuthPermissions   <- .auth_permissions(role)
  state$User              <- user$email[1]
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

#' Admin login by email + password
#' Requires master (cloud PG) to be attached to con before calling.
auth_login <- function(con, state, email, password) {
  auth_init_state(state)

  user <- DBI::dbGetQuery(
    con,
    "SELECT id, email, full_name, app_role, password_hash, is_active
     FROM master.admin.users
     WHERE email = ? AND app_role = 'admin'",
    list(email)
  )

  if (nrow(user) == 0 || !isTRUE(user$is_active[1])) {
    return(list(ok = FALSE, message = "Invalid credentials or inactive account"))
  }

  verify <- auth_verify_password(user$password_hash[1], password)
  if (!isTRUE(verify$ok)) {
    return(list(ok = FALSE, message = "Invalid credentials"))
  }

  .auth_set_state(state, user)
  list(ok = TRUE, message = "Authenticated")
}

#' Guest login by email + full name (creates user record on first visit)
#' Requires master (cloud PG) to be attached to con before calling.
auth_guest_login <- function(con, state, email, full_name) {
  auth_init_state(state)
  email     <- trimws(email)
  full_name <- trimws(full_name)

  if (!grepl("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", email, perl = TRUE)) {
    return(list(ok = FALSE, message = "Please enter a valid email address"))
  }
  if (!nzchar(full_name)) {
    return(list(ok = FALSE, message = "Please enter your full name"))
  }

  existing <- DBI::dbGetQuery(
    con,
    "SELECT id, email, full_name, app_role, is_active
     FROM master.admin.users WHERE email = ?",
    list(email)
  )

  if (nrow(existing) > 0) {
    if (existing$app_role[1] == "admin") {
      return(list(ok = FALSE, message = "Please use Admin Sign In for this account"))
    }
    if (!isTRUE(existing$is_active[1])) {
      return(list(ok = FALSE, message = "Account is inactive"))
    }
    .auth_set_state(state, existing)
  } else {
    DBI::dbExecute(
      con,
      "INSERT INTO master.admin.users (email, full_name, app_role) VALUES (?, ?, 'guest')",
      list(email, full_name)
    )
    user <- DBI::dbGetQuery(
      con,
      "SELECT id, email, full_name, app_role, is_active
       FROM master.admin.users WHERE email = ?",
      list(email)
    )
    .auth_set_state(state, user)
  }

  list(ok = TRUE, message = "Signed in as guest")
}

#' Change password — admin accounts only
auth_change_password <- function(con, state, old_password, new_password) {
  if (!auth_is_admin(state)) {
    return(list(ok = FALSE, message = "Admin account required"))
  }
  if (nchar(new_password) < 8) {
    return(list(ok = FALSE, message = "Password must be at least 8 characters"))
  }

  user_id <- shiny::isolate(state$AuthUserId)
  user <- DBI::dbGetQuery(
    con,
    "SELECT password_hash FROM master.admin.users WHERE id = ?",
    list(user_id)
  )

  verify <- auth_verify_password(user$password_hash[1], old_password)
  if (!isTRUE(verify$ok)) {
    return(list(ok = FALSE, message = "Current password is incorrect"))
  }

  new_hash <- bcrypt::hashpw(new_password)
  DBI::dbExecute(
    con,
    "UPDATE master.admin.users SET password_hash = ? WHERE id = ?",
    list(new_hash, user_id)
  )
  list(ok = TRUE, message = "Password updated successfully")
}

#' Grant admin role to an existing user — admin-only operation
auth_grant_admin <- function(con, state, target_email, initial_password) {
  if (!auth_is_admin(state)) {
    return(list(ok = FALSE, message = "Admin permission required"))
  }
  if (nchar(initial_password) < 8) {
    return(list(ok = FALSE, message = "Initial password must be at least 8 characters"))
  }

  target <- DBI::dbGetQuery(
    con,
    "SELECT id, app_role FROM master.admin.users WHERE email = ?",
    list(target_email)
  )

  if (nrow(target) == 0) {
    return(list(ok = FALSE, message = "User not found"))
  }
  if (target$app_role[1] == "admin") {
    return(list(ok = FALSE, message = "User already has admin access"))
  }

  new_hash <- bcrypt::hashpw(initial_password)
  DBI::dbExecute(
    con,
    "UPDATE master.admin.users SET app_role = 'admin', password_hash = ? WHERE id = ?",
    list(new_hash, target$id[1])
  )
  list(ok = TRUE, message = sprintf("Admin access granted to %s", target_email))
}

auth_logout <- function(state) {
  auth_init_state(state)
  state$AuthAuthenticated <- FALSE
  state$AuthUser          <- NULL
  state$AuthUserId        <- NULL
  state$AuthRole          <- NULL
  state$AuthRoles         <- character(0)
  state$AuthPermissions   <- character(0)
}

auth_is_authenticated <- function(state) {
  shiny::isolate(isTRUE(state$AuthAuthenticated))
}

auth_is_admin <- function(state) {
  auth_is_authenticated(state) && identical(shiny::isolate(state$AuthRole), "admin")
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
