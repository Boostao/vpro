# Test Setup - Initialize test environment and fixtures
# Runs once before all tests

# Set PG connection env vars for test environment (docker-compose)
Sys.setenv(
  PGHOST                 = "localhost",
  PGPORT                 = "5433",
  PGDATABASE             = "becmaster",
  VPRO_PG_GUEST_USER     = "vpro_default",
  VPRO_PG_ADMIN_USER     = "vpro_admin",
  VPRO_PG_ADMIN_PASSWORD = "admin_password"
)

# Load required packages
library(testthat)
library(DBI)
library(duckdb)
library(fs)

# Source connection factory
source(here::here("R", "db_connections.R"))

# Global test fixtures
test_con <- NULL  # Will hold test DuckDB connection
# pg_available will be set by check_postgres_available() via super-assignment

# Initialize test database connection on load
initialize_test_db <- function() {
  message("[test-setup] Initializing test database environment")
  
  # Create local test DuckDB (separate from dev DB)
  test_db_path <- tempfile(pattern = "vpro_test_", fileext = ".duckdb")
  
  # Note: In practice, you'd seed the local test DB with sample data here
  # For now, the real test will happen via postgres
  
  message("[test-setup] Test database initialized")
  return(test_db_path)
}

# Setup postgres connectivity check
check_postgres_available <- function() {
  message("[test-setup] Checking PostgreSQL availability at localhost:5433")
  
  # First check if RPostgres is available
  if (!requireNamespace("RPostgres", quietly = TRUE)) {
    message("[test-setup] RPostgres package not available - skipping postgres tests")
    return(FALSE)
  }
  
  # Try to connect to docker-compose postgres
  tryCatch({
    con_test <- DBI::dbConnect(
      RPostgres::Postgres(),
      host = Sys.getenv("PGHOST", "localhost"),
      port = as.integer(Sys.getenv("PGPORT", "5433")),
      user = "testuser",
      password = "testpass",
      dbname = Sys.getenv("PGDATABASE", "becmaster"),
      check_interrupts = FALSE,
      connect_timeout = 10
    )
    DBI::dbDisconnect(con_test)
    message("[test-setup] PostgreSQL is available!")
    return(TRUE)
  }, error = function(e) {
    message("[test-setup] PostgreSQL not available: ", e$message)
    message("[test-setup] To run cloud attachment tests:")
    message("[test-setup]   cd /Users/nicolas/Documents/GitHub/vpro")
    message("[test-setup]   docker-compose up -d")
    message("[test-setup]   then set PGHOST/PGPORT/PGDATABASE env vars")
    return(FALSE)
  })
}

# Run initialization
test_db_path <- initialize_test_db()
pg_available <<- check_postgres_available()

# Clean up function to reset databases between test sections
teardown_test_db <- function() {
  message("[test-teardown] Cleaning up test databases")
  if (!is.null(test_con) && DBI::dbIsValid(test_con)) {
    DBI::dbDisconnect(test_con)
  }
}
