#' PostgreSQL Role Management for VPro
#'
#' This module provides functions to create and manage PostgreSQL roles
#' with appropriate permissions for the VPro application.

#' Create VPro Default Role
#'
#' Creates the vpro_default role with:
#' - Read access to core, lists, and audit schemas
#' - Write access to staging schema
#' - LOGIN capability (authentication via pg_hba.conf trust method, no password required)
#'
#' @param con A DBI connection to PostgreSQL with superuser privileges
#' @return A list with status information
#' @export
create_vpro_default_role <- function(con) {
  
  # Validate connection
  if (!inherits(con, "PqConnection")) {
    stop("Connection must be a PostgreSQL connection (PqConnection)")
  }
  
  if (!DBI::dbIsValid(con)) {
    stop("Database connection is not valid")
  }
  
  message("Creating vpro_default role...")
  
  tryCatch({
    # Create role with LOGIN capability
    # Authentication is handled by pg_hba.conf (trust method for this role)
    DBI::dbExecute(con, "CREATE ROLE vpro_default WITH LOGIN")
    
    # Grant USAGE on schemas
    DBI::dbExecute(con, "GRANT USAGE ON SCHEMA core TO vpro_default")
    DBI::dbExecute(con, "GRANT USAGE ON SCHEMA lists TO vpro_default")
    DBI::dbExecute(con, "GRANT USAGE ON SCHEMA staging TO vpro_default")
    DBI::dbExecute(con, "GRANT USAGE ON SCHEMA audit TO vpro_default")
    
    # Grant SELECT on all tables in core and lists
    DBI::dbExecute(con, "GRANT SELECT ON ALL TABLES IN SCHEMA core TO vpro_default")
    DBI::dbExecute(con, "GRANT SELECT ON ALL TABLES IN SCHEMA lists TO vpro_default")
    DBI::dbExecute(con, "GRANT SELECT ON ALL TABLES IN SCHEMA audit TO vpro_default")
    
    # Grant SELECT on future tables in core and lists
    DBI::dbExecute(con, "ALTER DEFAULT PRIVILEGES IN SCHEMA core GRANT SELECT ON TABLES TO vpro_default")
    DBI::dbExecute(con, "ALTER DEFAULT PRIVILEGES IN SCHEMA lists GRANT SELECT ON TABLES TO vpro_default")
    DBI::dbExecute(con, "ALTER DEFAULT PRIVILEGES IN SCHEMA audit GRANT SELECT ON TABLES TO vpro_default")
    
    # Grant INSERT and UPDATE on staging tables
    DBI::dbExecute(con, "GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA staging TO vpro_default")
    DBI::dbExecute(con, "ALTER DEFAULT PRIVILEGES IN SCHEMA staging GRANT SELECT, INSERT, UPDATE ON TABLES TO vpro_default")
    
    # Grant USAGE on sequences (for serial/identity columns)
    DBI::dbExecute(con, "GRANT USAGE ON ALL SEQUENCES IN SCHEMA staging TO vpro_default")
    DBI::dbExecute(con, "ALTER DEFAULT PRIVILEGES IN SCHEMA staging GRANT USAGE ON SEQUENCES TO vpro_default")
    
    # Ensure no write access to core tables (only via staging workflow)
    DBI::dbExecute(con, "REVOKE INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA core FROM vpro_default")
    DBI::dbExecute(con, "REVOKE INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA lists FROM vpro_default")
    
    # Explicitly revoke write permissions on audit.logged_actions
    DBI::dbExecute(con, "REVOKE INSERT, UPDATE, DELETE ON audit.logged_actions FROM vpro_default")
    
    message("  ✓ vpro_default created successfully")
    
    return(list(
      status = "success",
      message = "Default role created with read access to core/lists and write to staging (trust auth required in pg_hba.conf)"
    ))
    
  }, error = function(e) {
    warning(sprintf("Failed to create vpro_default: %s", e$message))
    return(list(
      status = "error",
      message = e$message
    ))
  })
}


#' Create VPro Admin Role
#'
#' Creates the vpro_admin role with:
#' - Full administrative access to all schemas
#' - Ability to create roles
#' - Cannot modify audit.logged_actions (append-only constraint)
#' - Requires password for LOGIN
#'
#' @param con A DBI connection to PostgreSQL with superuser privileges
#' @param password Character string for the admin role password (default: "admin_password")
#' @return A list with status information
#' @export
create_vpro_admin_role <- function(con, password = "admin_password") {
  
  # Validate connection
  if (!inherits(con, "PqConnection")) {
    stop("Connection must be a PostgreSQL connection (PqConnection)")
  }
  
  if (!DBI::dbIsValid(con)) {
    stop("Database connection is not valid")
  }
  
  # Validate password
  if (!is.character(password) || nchar(password) == 0) {
    stop("Password must be a non-empty character string")
  }
  
  message("Creating vpro_admin role...")
  
  tryCatch({
    # Create role with elevated privileges
    DBI::dbExecute(con, sprintf(
      "CREATE ROLE vpro_admin WITH LOGIN PASSWORD %s CREATEROLE",
      DBI::dbQuoteString(con, password)
    ))
    
    # Grant all privileges on all schemas
    DBI::dbExecute(con, "GRANT ALL PRIVILEGES ON SCHEMA core TO vpro_admin")
    DBI::dbExecute(con, "GRANT ALL PRIVILEGES ON SCHEMA lists TO vpro_admin")
    DBI::dbExecute(con, "GRANT ALL PRIVILEGES ON SCHEMA staging TO vpro_admin")
    DBI::dbExecute(con, "GRANT ALL PRIVILEGES ON SCHEMA admin TO vpro_admin")
    DBI::dbExecute(con, "GRANT ALL PRIVILEGES ON SCHEMA audit TO vpro_admin")
    
    # Grant all on all tables
    DBI::dbExecute(con, "GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA core TO vpro_admin")
    DBI::dbExecute(con, "GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA lists TO vpro_admin")
    DBI::dbExecute(con, "GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA staging TO vpro_admin")
    DBI::dbExecute(con, "GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA admin TO vpro_admin")
    DBI::dbExecute(con, "GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA audit TO vpro_admin")
    
    # Grant all on sequences
    DBI::dbExecute(con, "GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA core TO vpro_admin")
    DBI::dbExecute(con, "GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA lists TO vpro_admin")
    DBI::dbExecute(con, "GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA staging TO vpro_admin")
    DBI::dbExecute(con, "GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA admin TO vpro_admin")
    DBI::dbExecute(con, "GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA audit TO vpro_admin")
    
    # Grant on future objects
    DBI::dbExecute(con, "ALTER DEFAULT PRIVILEGES IN SCHEMA core GRANT ALL ON TABLES TO vpro_admin")
    DBI::dbExecute(con, "ALTER DEFAULT PRIVILEGES IN SCHEMA lists GRANT ALL ON TABLES TO vpro_admin")
    DBI::dbExecute(con, "ALTER DEFAULT PRIVILEGES IN SCHEMA staging GRANT ALL ON TABLES TO vpro_admin")
    DBI::dbExecute(con, "ALTER DEFAULT PRIVILEGES IN SCHEMA admin GRANT ALL ON TABLES TO vpro_admin")
    DBI::dbExecute(con, "ALTER DEFAULT PRIVILEGES IN SCHEMA audit GRANT ALL ON TABLES TO vpro_admin")
    
    # Explicitly revoke DELETE and UPDATE on audit.logged_actions
    # (append-only constraint - even admins cannot modify history)
    DBI::dbExecute(con, "REVOKE UPDATE, DELETE ON audit.logged_actions FROM vpro_admin")
    
    message("  ✓ vpro_admin created successfully")
    
    return(list(
      status = "success",
      message = "Role created with full administrative access (audit log is append-only)"
    ))
    
  }, error = function(e) {
    warning(sprintf("Failed to create vpro_admin: %s", e$message))
    return(list(
      status = "error",
      message = e$message
    ))
  })
}


#' Create PostgreSQL Roles (Master Function)
#'
#' Creates both PostgreSQL roles with appropriate permissions:
#' - vpro_default: Read access to core/lists + write to staging (no password)
#' - vpro_admin: Full administrative access (except audit log modification)
#'
#' @param con A DBI connection to PostgreSQL with superuser privileges
#' @param admin_password Character string for the admin role password (default: "admin_password")
#' @param recreate If TRUE, drops existing roles before creating them (default: FALSE)
#' @return A list with status information for each role created
#' @export
#' @examples
#' \dontrun{
#' con <- DBI::dbConnect(RPostgres::Postgres(),
#'                       host = "localhost",
#'                       port = 5433,
#'                       dbname = "becmaster",
#'                       user = "testuser",
#'                       password = "testpass")
#' result <- create_pg_roles(con, admin_password = "secure_password")
#' 
#' # Now vpro_default can connect without a password (requires trust auth in pg_hba.conf):
#' # R: DBI::dbConnect(RPostgres::Postgres(), user="vpro_default", host="localhost", ...)
#' # psql: psql -U vpro_default -d becmaster (no password prompt)
#' # And vpro_admin can connect with the admin password set above
#' 
#' DBI::dbDisconnect(con)
#' }
create_pg_roles <- function(con, admin_password = "admin_password", recreate = FALSE) {
  
  # Validate connection
  if (!inherits(con, "PqConnection")) {
    stop("Connection must be a PostgreSQL connection (PqConnection)")
  }
  
  # Check if connected
  if (!DBI::dbIsValid(con)) {
    stop("Database connection is not valid")
  }
  
  results <- list()
  
  # Role definitions
  roles <- c("vpro_default", "vpro_admin")
  
  # Drop roles if recreate is TRUE
  if (recreate) {
    message("Dropping existing roles if they exist...")
    for (role_name in roles) {
      tryCatch({
        # Reassign owned objects and revoke privileges first
        DBI::dbExecute(con, sprintf("REASSIGN OWNED BY %s TO CURRENT_USER", role_name))
        DBI::dbExecute(con, sprintf("DROP OWNED BY %s", role_name))
        DBI::dbExecute(con, sprintf("DROP ROLE IF EXISTS %s", role_name))
        message(sprintf("  Dropped role: %s", role_name))
      }, error = function(e) {
        warning(sprintf("Could not drop role %s: %s", role_name, e$message))
      })
    }
  }
  
  # Create vpro_default role
  results$vpro_default <- create_vpro_default_role(con)
  
  # Create vpro_admin role
  results$vpro_admin <- create_vpro_admin_role(con, password = admin_password)
  
  # Summary
  success_count <- sum(sapply(results, function(r) r$status == "success"))
  message(sprintf("\nRole creation complete: %d/%d successful", success_count, length(roles)))
  
  invisible(results)
}


#' List PostgreSQL Roles and Their Permissions
#'
#' Queries the database for existing VPro roles and their permissions.
#'
#' @param con A DBI connection to PostgreSQL
#' @return A data frame with role information
#' @export
list_vpro_roles <- function(con) {
  
  query <- "
    SELECT 
      r.rolname as role_name,
      r.rolcanlogin as can_login,
      r.rolcreaterole as can_create_role,
      r.rolsuper as is_superuser,
      ARRAY_AGG(m.rolname) FILTER (WHERE m.rolname IS NOT NULL) as member_of
    FROM pg_roles r
    LEFT JOIN pg_auth_members am ON r.oid = am.member
    LEFT JOIN pg_roles m ON am.roleid = m.oid
    WHERE r.rolname LIKE 'vpro_%'
    GROUP BY r.rolname, r.rolcanlogin, r.rolcreaterole, r.rolsuper
    ORDER BY r.rolname
  "
  
  DBI::dbGetQuery(con, query)
}


#' Drop VPro Roles
#'
#' Drops all VPro-related roles from the database.
#' Use with caution in production environments.
#'
#' @param con A DBI connection to PostgreSQL with superuser privileges
#' @param force If TRUE, revokes all privileges before dropping (default: FALSE)
#' @return A list with status information for each role dropped
#' @export
drop_vpro_roles <- function(con, force = FALSE) {
  
  roles <- c("vpro_admin", "vpro_default")
  results <- list()
  
  message("Dropping VPro roles...")
  
  for (role in roles) {
    tryCatch({
      if (force) {
        # Reassign owned objects and drop privileges
        DBI::dbExecute(con, sprintf("REASSIGN OWNED BY %s TO CURRENT_USER", role))
        DBI::dbExecute(con, sprintf("DROP OWNED BY %s", role))
      }
      
      DBI::dbExecute(con, sprintf("DROP ROLE IF EXISTS %s", role))
      results[[role]] <- list(status = "success", message = "Role dropped")
      message(sprintf("  ✓ Dropped role: %s", role))
      
    }, error = function(e) {
      results[[role]] <<- list(status = "error", message = e$message)
      warning(sprintf("Could not drop role %s: %s", role, e$message))
    })
  }
  
  invisible(results)
}
