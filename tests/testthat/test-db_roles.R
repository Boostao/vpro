# Test PostgreSQL Role Management
# 
# Tests verify that PostgreSQL roles are created correctly with appropriate
# permissions as specified in the BEC Data Management plan (Step 2).
# 
# Two roles:
# - vpro_default: Read core/lists + write staging (no password)
# - vpro_admin: Full administrative access

test_that("create_vpro_default_role creates role successfully", {
  skip_if_not(pg_available(), "PostgreSQL not available")
  
  con <- get_test_pg_connection()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  
  # Drop if exists
  tryCatch({
    DBI::dbExecute(con, "REASSIGN OWNED BY vpro_default TO CURRENT_USER")
    DBI::dbExecute(con, "DROP OWNED BY vpro_default")
    DBI::dbExecute(con, "DROP ROLE IF EXISTS vpro_default")
  }, error = function(e) {
    # Role might not exist, that's OK
  })
  
  # Create default role
  result <- create_vpro_default_role(con)
  
  expect_type(result, "list")
  expect_equal(result$status, "success")
  
  # Verify role exists
  roles <- DBI::dbGetQuery(con, "
    SELECT rolname, rolcanlogin 
    FROM pg_roles 
    WHERE rolname = 'vpro_default'
  ")
  
  expect_equal(nrow(roles), 1)
  expect_equal(roles$rolname, "vpro_default")
  expect_true(roles$rolcanlogin)  # Can login without password
})


test_that("create_vpro_admin_role creates role with custom password", {
  skip_if_not(pg_available(), "PostgreSQL not available")
  
  con <- get_test_pg_connection()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  
  # Drop if exists
  tryCatch({
    DBI::dbExecute(con, "REASSIGN OWNED BY vpro_admin TO CURRENT_USER")
    DBI::dbExecute(con, "DROP OWNED BY vpro_admin")
    DBI::dbExecute(con, "DROP ROLE IF EXISTS vpro_admin")
  }, error = function(e) {
    # Role might not exist, that's OK
  })
  
  # Create admin role with custom password
  result <- create_vpro_admin_role(con, password = "custom_secure_pass")
  
  expect_type(result, "list")
  expect_equal(result$status, "success")
  
  # Verify role exists
  roles <- DBI::dbGetQuery(con, "
    SELECT rolname, rolcanlogin, rolcreaterole
    FROM pg_roles 
    WHERE rolname = 'vpro_admin'
  ")
  
  expect_equal(nrow(roles), 1)
  expect_equal(roles$rolname, "vpro_admin")
  expect_true(roles$rolcanlogin)
  expect_true(roles$rolcreaterole)
})


test_that("create_pg_roles creates both roles successfully", {
  skip_if_not(pg_available(), "PostgreSQL not available")
  
  con <- get_test_pg_connection()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  
  # Clean up any existing roles first
  drop_vpro_roles(con, force = TRUE)
  
  # Create roles with custom admin password
  result <- create_pg_roles(con, admin_password = "test_admin_pass")
  
  # Check that both roles were created
  expect_type(result, "list")
  expect_named(result, c("vpro_default", "vpro_admin"))
  
  # Both should have status "success"
  expect_equal(result$vpro_default$status, "success")
  expect_equal(result$vpro_admin$status, "success")
  
  # Verify roles exist in database
  roles <- DBI::dbGetQuery(con, "
    SELECT rolname 
    FROM pg_roles 
    WHERE rolname IN ('vpro_default', 'vpro_admin')
    ORDER BY rolname
  ")
  
  expect_equal(nrow(roles), 2)
  expect_equal(roles$rolname, c("vpro_admin", "vpro_default"))
})


test_that("vpro_default role has correct permissions", {
  skip_if_not(pg_available(), "PostgreSQL not available")
  
  # Set up roles
  admin_con <- get_test_pg_connection()
  on.exit(DBI::dbDisconnect(admin_con), add = TRUE)
  
  drop_vpro_roles(admin_con, force = TRUE)
  create_pg_roles(admin_con)
  
  # Connect directly as vpro_default (no password required)
  default_con <- DBI::dbConnect(
    RPostgres::Postgres(),
    host = "localhost",
    port = 5433,
    dbname = "becmaster",
    user = "vpro_default"
    # No password parameter - can login without authentication
  )
  on.exit(DBI::dbDisconnect(default_con), add = TRUE, after = FALSE)
  
  # Should be able to SELECT from core tables
  expect_no_error({
    result <- DBI::dbGetQuery(default_con, "SELECT * FROM core.sample_veg LIMIT 1")
  })
  
  # Should be able to SELECT from lists tables
  expect_no_error({
    result <- DBI::dbGetQuery(default_con, "SELECT * FROM lists.spplist LIMIT 1")
  })
  
  # Should be able to SELECT from audit tables
  expect_no_error({
    result <- DBI::dbGetQuery(default_con, "SELECT * FROM audit.logged_actions LIMIT 1")
  })
  
  # Should be able to SELECT from staging
  expect_no_error({
    result <- DBI::dbGetQuery(default_con, "SELECT * FROM staging.sample_veg LIMIT 1")
  })
  
  # Should be able to INSERT into staging tables
  expect_no_error({
    # First create a merge request
    merge_id <- DBI::dbGetQuery(admin_con, "
      INSERT INTO staging.merge_requests 
      (project_id, submitter_name, submitter_email, status)
      VALUES (1, 'Test User', 'test@example.com', 'pending_review')
      RETURNING id
    ")$id
    
    DBI::dbExecute(default_con, sprintf("
      INSERT INTO staging.sample_veg 
      (plot_number, species_code, layer_code, cover_percent, project_id, merge_request_id, change_type)
      VALUES ('TEST_DEFAULT_PLOT', 'PICO', 'T1', 50, 1, %d, 'I')
    ", merge_id))
  })
  
  # Should be able to UPDATE staging tables
  expect_no_error({
    DBI::dbExecute(default_con, "
      UPDATE staging.sample_veg 
      SET cover_percent = 60 
      WHERE plot_number = 'TEST_DEFAULT_PLOT'
    ")
  })
  
  # Should NOT be able to INSERT into core tables
  expect_error({
    DBI::dbExecute(default_con, "
      INSERT INTO core.sample_veg 
      (plot_number, species_code, layer_code, cover_percent, project_id)
      VALUES ('TEST_PLOT', 'PICO', 'T1', 50, 1)
    ")
  }, "permission denied")
  
  # Should NOT be able to UPDATE core tables
  expect_error({
    DBI::dbExecute(default_con, "
      UPDATE core.sample_veg 
      SET cover_percent = 75 
      WHERE plot_number = 'PLOT_001'
    ")
  }, "permission denied")
  
  # Should NOT be able to DELETE from core tables
  expect_error({
    DBI::dbExecute(default_con, "
      DELETE FROM core.sample_veg 
      WHERE plot_number = 'PLOT_001'
    ")
  }, "permission denied")
  
  # Should NOT be able to modify audit.logged_actions
  expect_error({
    DBI::dbExecute(default_con, "
      INSERT INTO audit.logged_actions 
      (schema_name, table_name, action, new_data)
      VALUES ('core', 'sample_veg', 'I', '{\"test\": \"data\"}'::jsonb)
    ")
  }, "permission denied")
  
  expect_error({
    DBI::dbExecute(default_con, "
      UPDATE audit.logged_actions 
      SET action = 'X' 
      WHERE id = 1
    ")
  }, "permission denied")
  
  expect_error({
    DBI::dbExecute(default_con, "
      DELETE FROM audit.logged_actions 
      WHERE id = 1
    ")
  }, "permission denied")
})


test_that("vpro_admin role has correct permissions", {
  skip_if_not(pg_available(), "PostgreSQL not available")
  
  # Set up roles
  superuser_con <- get_test_pg_connection()
  on.exit(DBI::dbDisconnect(superuser_con), add = TRUE)
  
  drop_vpro_roles(superuser_con, force = TRUE)
  create_pg_roles(superuser_con, admin_password = "test_admin_password")
  
  # Grant the role to the test user
  DBI::dbExecute(superuser_con, "GRANT vpro_admin TO testuser")
  
  # Connect as testuser with admin role
  admin_con <- DBI::dbConnect(
    RPostgres::Postgres(),
    host = "localhost",
    port = 5433,
    dbname = "becmaster",
    user = "testuser",
    password = "testpass"
  )
  on.exit(DBI::dbDisconnect(admin_con), add = TRUE, after = FALSE)
  
  # Set role to vpro_admin
  DBI::dbExecute(admin_con, "SET ROLE vpro_admin")
  
  # Should be able to SELECT from all schemas
  expect_no_error({
    DBI::dbGetQuery(admin_con, "SELECT * FROM core.sample_veg LIMIT 1")
    DBI::dbGetQuery(admin_con, "SELECT * FROM lists.spplist LIMIT 1")
    DBI::dbGetQuery(admin_con, "SELECT * FROM staging.sample_veg LIMIT 1")
    DBI::dbGetQuery(admin_con, "SELECT * FROM admin.users LIMIT 1")
    DBI::dbGetQuery(admin_con, "SELECT * FROM audit.logged_actions LIMIT 1")
  })
  
  # Should be able to INSERT into core tables
  expect_no_error({
    DBI::dbExecute(admin_con, "
      INSERT INTO core.sample_veg 
      (plot_number, species_code, layer_code, cover_percent, project_id)
      VALUES ('ADMIN_TEST_PLOT', 'PICO', 'T1', 50, 1)
    ")
  })
  
  # Should be able to UPDATE core tables
  expect_no_error({
    DBI::dbExecute(admin_con, "
      UPDATE core.sample_veg 
      SET cover_percent = 75 
      WHERE plot_number = 'ADMIN_TEST_PLOT'
    ")
  })
  
  # Should be able to DELETE from core tables
  expect_no_error({
    DBI::dbExecute(admin_con, "
      DELETE FROM core.sample_veg 
      WHERE plot_number = 'ADMIN_TEST_PLOT'
    ")
  })
  
  # Should be able to INSERT into staging
  expect_no_error({
    merge_id <- DBI::dbGetQuery(admin_con, "
      INSERT INTO staging.merge_requests 
      (project_id, submitter_name, submitter_email, status)
      VALUES (1, 'Admin User', 'admin@example.com', 'pending_review')
      RETURNING id
    ")$id
    
    DBI::dbExecute(admin_con, sprintf("
      INSERT INTO staging.sample_veg 
      (plot_number, species_code, layer_code, cover_percent, project_id, merge_request_id, change_type)
      VALUES ('ADMIN_STAGING_PLOT', 'PICO', 'T1', 50, 1, %d, 'I')
    ", merge_id))
  })
  
  # Should be able to INSERT into lists
  expect_no_error({
    # Clean up any existing test data first
    DBI::dbExecute(admin_con, "DELETE FROM lists.spplist WHERE spp_code = 'TEST_SPP'")
    DBI::dbExecute(admin_con, "
      INSERT INTO lists.spplist 
      (spp_code, spp_name, spp_scientific, is_active)
      VALUES ('TEST_SPP', 'Test Species', 'Testus speciesus', TRUE)
    ")
  })
  
  # Should be able to UPDATE lists
  expect_no_error({
    DBI::dbExecute(admin_con, "
      UPDATE lists.spplist 
      SET spp_name = 'Updated Test Species' 
      WHERE spp_code = 'TEST_SPP'
    ")
  })
  
  # Should be able to manage admin tables
  expect_no_error({
    # Clean up any existing test data first
    DBI::dbExecute(admin_con, "DELETE FROM admin.users WHERE username = 'testadminuser'")
    DBI::dbExecute(admin_con, "
      INSERT INTO admin.users 
      (username, email, full_name, role, is_active)
      VALUES ('testadminuser', 'testadmin@example.com', 'Test Admin User', 'writer', TRUE)
    ")
  })
  
  # Should be able to INSERT into audit.logged_actions (append-only)
  expect_no_error({
    DBI::dbExecute(admin_con, "
      INSERT INTO audit.logged_actions 
      (schema_name, table_name, action, new_data)
      VALUES ('core', 'sample_veg', 'I', '{\"test\": \"data\"}'::jsonb)
    ")
  })
  
  # Should NOT be able to UPDATE audit.logged_actions (append-only constraint)
  expect_error({
    DBI::dbExecute(admin_con, "
      UPDATE audit.logged_actions 
      SET action = 'X' 
      WHERE id = 1
    ")
  }, "permission denied")
  
  # Should NOT be able to DELETE from audit.logged_actions (append-only constraint)
  expect_error({
    DBI::dbExecute(admin_con, "
      DELETE FROM audit.logged_actions 
      WHERE id = 1
    ")
  }, "permission denied")
})


test_that("list_vpro_roles returns correct information", {
  skip_if_not(pg_available(), "PostgreSQL not available")
  
  con <- get_test_pg_connection()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  
  drop_vpro_roles(con, force = TRUE)
  create_pg_roles(con)
  
  # List roles
  roles_info <- list_vpro_roles(con)
  
  expect_s3_class(roles_info, "data.frame")
  expect_equal(nrow(roles_info), 2)
  expect_true(all(c("vpro_default", "vpro_admin") %in% roles_info$role_name))
  
  # Check that vpro_admin can create roles
  admin_row <- roles_info[roles_info$role_name == "vpro_admin", ]
  expect_true(admin_row$can_create_role)
  
  # Check that vpro_default CAN login (no password required)
  default_row <- roles_info[roles_info$role_name == "vpro_default", ]
  expect_true(default_row$can_login)
})


test_that("drop_vpro_roles removes all roles", {
  skip_if_not(pg_available(), "PostgreSQL not available")
  
  con <- get_test_pg_connection()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  
  # Clean up any existing roles first
  suppressMessages(drop_vpro_roles(con, force = TRUE))
  
  # Create roles
  create_pg_roles(con)
  
  # Verify they exist
  roles_before <- list_vpro_roles(con)
  expect_equal(nrow(roles_before), 2)
  
  # Drop roles
  result <- drop_vpro_roles(con, force = TRUE)
  
  expect_type(result, "list")
  expect_named(result, c("vpro_admin", "vpro_default"))
  
  # Verify they're gone
  roles_after <- list_vpro_roles(con)
  expect_equal(nrow(roles_after), 0)
})


test_that("create_pg_roles with recreate=TRUE drops and recreates roles", {
  skip_if_not(pg_available(), "PostgreSQL not available")
  
  con <- get_test_pg_connection()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  
  # Create roles first time
  create_pg_roles(con)
  
  # Verify they exist
  roles_v1 <- list_vpro_roles(con)
  expect_equal(nrow(roles_v1), 2)
  
  # Create again with recreate=TRUE (should not error)
  expect_no_error({
    result <- create_pg_roles(con, recreate = TRUE)
  })
  
  # Verify they still exist
  roles_v2 <- list_vpro_roles(con)
  expect_equal(nrow(roles_v2), 2)
})


test_that("create_vpro_admin_role validates password", {
  skip_if_not(pg_available(), "PostgreSQL not available")
  
  con <- get_test_pg_connection()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  
  # Test with empty password
  expect_error(
    create_vpro_admin_role(con, password = ""),
    "Password must be a non-empty character string"
  )
  
  # Test with non-character password
  expect_error(
    create_vpro_admin_role(con, password = 123),
    "Password must be a non-empty character string"
  )
})


test_that("create_pg_roles validates connection", {
  # Test with invalid connection type
  expect_error(
    create_pg_roles("not_a_connection"),
    "Connection must be a PostgreSQL connection"
  )
  
  # Test with disconnected connection
  con <- get_test_pg_connection()
  DBI::dbDisconnect(con)
  
  expect_error(
    create_pg_roles(con),
    "Database connection is not valid"
  )
})


test_that("vpro_default role can be granted to users", {
  skip_if_not(pg_available(), "PostgreSQL not available")
  
  admin_con <- get_test_pg_connection()
  on.exit(DBI::dbDisconnect(admin_con), add = TRUE)
  
  drop_vpro_roles(admin_con, force = TRUE)
  create_pg_roles(admin_con)
  
  # Connect directly as vpro_default (no password)
  expect_no_error({
    default_con <- DBI::dbConnect(
      RPostgres::Postgres(),
      host = "localhost",
      port = 5433,
      dbname = "becmaster",
      user = "vpro_default"
    )
  })
  
  on.exit(DBI::dbDisconnect(default_con), add = TRUE, after = FALSE)
  
  # Verify they can read from core
  expect_no_error({
    DBI::dbGetQuery(default_con, "SELECT * FROM core.sample_veg LIMIT 1")
  })
})
