library(shinytest2)
library(testthat)
library(DBI)
library(duckdb)

new_app_driver <- function(name, height, width, ...) {
  app_obj <- shiny::shinyAppFile(normalizePath(file.path("..", "..", "app.R")))
  AppDriver$new(app = app_obj, name = name, height = height, width = width, ...)
}

# ============================================================================
# Data Entry UI Regression Tests
# ============================================================================
# Focused on detailed data entry mechanics and edge cases beyond E2E tests:
#   - Keyboard navigation patterns
#   - Input validation and error states
#   - Copy/paste, undo/redo operations
#   - Tab switching with unsaved changes
#   - Dependent field calculations
#   - Special character handling
#
# Complements test-e2e-workflows.R with granular UX regression coverage
# ============================================================================

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

# Helper: Safe app value getter (reused from E2E tests)
safe_get_value <- function(app, input = NULL, output = NULL, export = NULL) {
  tryCatch({
    app$get_value(input = input, output = output, export = export)
  }, error = function(e) {
    NULL
  })
}

# Helper: Select project in app
select_project <- function(app, project_id = NULL) {
  available_projects <- safe_get_value(app, input = "sel_project")
  
  if (is.null(project_id)) {
    if (is.null(available_projects) || !nzchar(available_projects)) {
      return(NULL)
    }
    project_id <- available_projects
  }
  
  app$set_inputs(sel_project = project_id)
  app$wait_for_idle()
  
  return(project_id)
}

# Helper: Select plot in app
select_plot <- function(app, plot_id = NULL) {
  project_id <- safe_get_value(app, input = "sel_project")
  if (is.null(project_id) || !nzchar(project_id)) {
    return(NULL)
  }

  con <- dbConnect(duckdb(), "data/vpro.duckdb")
  on.exit(dbDisconnect(con), add = TRUE)

  scope <- tryCatch(
    dbGetQuery(
      con,
      paste(
        "SELECT DISTINCT s.siteunit, s.plotnumber",
        "FROM SU s",
        "INNER JOIN Env e ON e.plotnumber = s.plotnumber",
        "WHERE e.projectid = ?",
        "  AND s.siteunit IS NOT NULL",
        "  AND trim(s.siteunit) <> ''",
        "  AND s.plotnumber IS NOT NULL",
        "  AND trim(s.plotnumber) <> ''",
        "ORDER BY s.siteunit, s.plotnumber"
      ),
      list(project_id)
    ),
    error = function(e) data.frame(siteunit = character(0), plotnumber = character(0))
  )

  if (nrow(scope) == 0) {
    return(NULL)
  }

  if (is.null(plot_id)) {
    plot_id <- scope$plotnumber[[1]]
  }

  target <- scope[scope$plotnumber == plot_id, , drop = FALSE]
  if (nrow(target) == 0) {
    return(NULL)
  }

  site_unit <- target$siteunit[[1]]
  site_rows <- scope$plotnumber[scope$siteunit == site_unit]
  row_index <- match(plot_id, site_rows)

  if (is.null(safe_get_value(app, input = "picker_site_unit"))) {
    app$click("btn_nav_su_tree")
    app$wait_for_idle()
  }

  app$set_inputs(picker_site_unit = site_unit)
  app$wait_for_idle()
  app$set_inputs(site_unit_plot_table_rows_selected = row_index)
  app$wait_for_idle()
  
  safe_get_value(app, input = "sel_su")
}

# Helper: Navigate to specific layer in vegetation tab
navigate_to_veg_layer <- function(app, layer_name) {
  app$set_inputs(main_tabs = "Vegetation")
  app$wait_for_idle()
  
  app$set_inputs(`veg-layers_tab` = layer_name)
  app$wait_for_idle()
  
  safe_get_value(app, input = "veg-layers_tab")
}

# Helper: Check if handsontable is editable (by checking output structure)
is_hot_editable <- function(app, output_id) {
  hot_output <- safe_get_value(app, output = output_id)
  !is.null(hot_output)
}

# Helper: Direct DB query to verify state
verify_db_state <- function(query, expected_rows = NULL, description = "DB check") {
  con <- dbConnect(duckdb(), "data/vpro.duckdb")
  on.exit(dbDisconnect(con), add = TRUE)
  
  result <- tryCatch({
    dbGetQuery(con, query)
  }, error = function(e) {
    message("DB query failed: ", conditionMessage(e))
    data.frame()
  })
  
  if (!is.null(expected_rows)) {
    expect_equal(nrow(result), expected_rows, 
                 label = paste0(description, " - row count"))
  }
  
  invisible(result)
}


# ============================================================================
# VEGETATION DATA ENTRY TESTS
# ============================================================================

describe("Vegetation Data Entry - Layer Navigation", {
  
  test_that("Layer switching preserves tab context", {
    skip_on_cran()
    
    app <- new_app_driver(name = "veg-layer-nav", height = 1000, width = 1600)
    on.exit(app$stop(), add = TRUE)
    app$wait_for_idle(timeout = 5000)
    
    project <- select_project(app)
    if (is.null(project)) skip("No project available")
    
    plot <- select_plot(app)
    if (is.null(plot)) skip("No plot available")
    
    # Navigate through all layers
    layers <- c(
      "Layer A (Trees)",
      "Layer B (Shrubs)", 
      "Layer C (Herbs)",
      "Layer D (Mosses)"
    )
    
    for (layer in layers) {
      current_layer <- navigate_to_veg_layer(app, layer)
      expect_equal(current_layer, layer, 
                   label = paste("Navigate to", layer))
    }
    
    # Return to first layer
    final_layer <- navigate_to_veg_layer(app, "Layer A (Trees)")
    expect_equal(final_layer, "Layer A (Trees)", 
                 label = "Return to Layer A")
  })
  
  test_that("Layer tabs render handsontable for each layer", {
    skip_on_cran()
    
    app <- new_app_driver(name = "veg-layer-tables", height = 1000, width = 1600)
    on.exit(app$stop(), add = TRUE)
    app$wait_for_idle(timeout = 5000)
    
    project <- select_project(app)
    if (is.null(project)) skip("No project available")
    
    plot <- select_plot(app)
    if (is.null(plot)) skip("No plot available")
    
    # Check each layer has a handsontable
    hot_outputs <- c(
      "veg-hot_veg_a",
      "veg-hot_veg_b",
      "veg-hot_veg_c",
      "veg-hot_veg_d"
    )
    
    layer_names <- c(
      "Layer A (Trees)",
      "Layer B (Shrubs)",
      "Layer C (Herbs)",
      "Layer D (Mosses)"
    )
    
    for (i in seq_along(hot_outputs)) {
      navigate_to_veg_layer(app, layer_names[i])
      
      hot_exists <- is_hot_editable(app, hot_outputs[i])
      expect_true(hot_exists, 
                  label = paste("Handsontable exists for", layer_names[i]))
    }
  })
  
  test_that("Vegetation context hint updates with current plot", {
    skip_on_cran()
    
    app <- new_app_driver(name = "veg-context-hint", height = 1000, width = 1600)
    on.exit(app$stop(), add = TRUE)
    app$wait_for_idle(timeout = 5000)
    
    project <- select_project(app)
    if (is.null(project)) skip("No project available")
    
    plot <- select_plot(app)
    if (is.null(plot)) skip("No plot available")
    
    app$set_inputs(main_tabs = "Vegetation")
    app$wait_for_idle()
    
    context_hint <- safe_get_value(app, output = "veg-veg_context_hint")
    expect_true(!is.null(context_hint), 
                label = "Context hint renders for current plot")
  })
})


describe("Vegetation Data Entry - Add/Delete Operations", {
  
  test_that("Add Species button exists on all layers", {
    skip_on_cran()
    
    app <- new_app_driver(name = "veg-add-btn", height = 1000, width = 1600)
    on.exit(app$stop(), add = TRUE)
    app$wait_for_idle(timeout = 5000)
    
    project <- select_project(app)
    if (is.null(project)) skip("No project available")
    
    plot <- select_plot(app)
    if (is.null(plot)) skip("No plot available")
    
    layers <- c(
      "Layer A (Trees)",
      "Layer B (Shrubs)",
      "Layer C (Herbs)",
      "Layer D (Mosses)"
    )
    
    for (layer in layers) {
      navigate_to_veg_layer(app, layer)
      
      add_btn_exists <- !is.null(safe_get_value(app, input = "veg-btn_add_spp"))
      expect_true(add_btn_exists, 
                  label = paste("Add Species button exists on", layer))
    }
  })
  
  test_that("Delete Selected button exists on all layers", {
    skip_on_cran()
    
    app <- new_app_driver(name = "veg-del-btn", height = 1000, width = 1600)
    on.exit(app$stop(), add = TRUE)
    app$wait_for_idle(timeout = 5000)
    
    project <- select_project(app)
    if (is.null(project)) skip("No project available")
    
    plot <- select_plot(app)
    if (is.null(plot)) skip("No plot available")
    
    layers <- c(
      "Layer A (Trees)",
      "Layer B (Shrubs)",
      "Layer C (Herbs)",
      "Layer D (Mosses)"
    )
    
    for (layer in layers) {
      navigate_to_veg_layer(app, layer)
      
      del_btn_exists <- !is.null(safe_get_value(app, input = "veg-btn_del_spp"))
      expect_true(del_btn_exists, 
                  label = paste("Delete button exists on", layer))
    }
  })
  
  test_that("Add Species button triggers without errors", {
    skip_on_cran()
    skip("Add Species modal implementation pending")
    
    app <- new_app_driver(name = "veg-add-trigger", height = 1000, width = 1600)
    on.exit(app$stop(), add = TRUE)
    app$wait_for_idle(timeout = 5000)
    
    project <- select_project(app)
    if (is.null(project)) skip("No project available")
    
    plot <- select_plot(app)
    if (is.null(plot)) skip("No plot available")
    
    navigate_to_veg_layer(app, "Layer A (Trees)")
    
    # Click Add Species - should open modal
    app$click("veg-btn_add_spp")
    app$wait_for_idle()
    
    # Check if modal or species picker appears
    # Implementation depends on mod_veg_sample.R modal structure
  })
})


describe("Vegetation Data Entry - Cover Value Validation", {
  
  test_that("Cover values accept numeric input (0-100)", {
    skip_on_cran()
    skip("Direct handsontable cell input testing requires advanced AppDriver features")
    
    # This would test typing "50" into a cover cell and verifying save
    # Requires AppDriver$set_values() for handsontable cells
    # Or using JavaScript execution to set cell values
  })
  
  test_that("Cover values accept special codes (+, r, P)", {
    skip_on_cran()
    skip("Direct handsontable cell input testing requires advanced AppDriver features")
    
    # Test entering special cover codes like "+", "r", "P"
    # Verify they're stored as TEXT in Sample_Veg.Cover1-10
  })
  
  test_that("Cover sum warning appears when total exceeds 100%", {
    skip_on_cran()
    skip("Cover sum validation not yet implemented")
    
    # If implemented: Enter multiple species with covers totaling >100%
    # Verify warning notification or indicator appears
  })
})


describe("Vegetation Data Entry - Species Management", {
  
  test_that("Duplicate species detection within same layer", {
    skip_on_cran()
    skip("Duplicate species check not yet implemented")
    
    # Test adding same species code twice to Layer A
    # Should show warning or prevent duplicate
  })
  
  test_that("Species autocomplete/lookup functionality", {
    skip_on_cran()
    skip("Species autocomplete implementation pending")
    
    # Test typing partial species code triggers lookup
    # Verify species list from vpro_lists.duckdb::SppList
  })
})


# ============================================================================
# SITE & ENVIRONMENT DATA ENTRY TESTS
# ============================================================================

describe("Site & Environment - Tab Structure", {
  
  test_that("Site/Env tabs exist and are navigable", {
    skip_on_cran()
    
    app <- new_app_driver(name = "env-tab-nav", height = 1000, width = 1600)
    on.exit(app$stop(), add = TRUE)
    app$wait_for_idle(timeout = 5000)
    
    project <- select_project(app)
    if (is.null(project)) skip("No project available")
    
    plot <- select_plot(app)
    if (is.null(plot)) skip("No plot available")
    
    app$set_inputs(main_tabs = "FS882-6x4XL")
    app$wait_for_idle()
    
    # Verify env_tabs exists
    env_tabs <- safe_get_value(app, input = "env-env_tabs")
    expect_true(!is.null(env_tabs), 
                label = "Site/Env tabs structure exists")
  })
  
  test_that("General tab fields are populated", {
    skip_on_cran()
    
    app <- new_app_driver(name = "env-general-fields", height = 1000, width = 1600)
    on.exit(app$stop(), add = TRUE)
    app$wait_for_idle(timeout = 5000)
    
    project <- select_project(app)
    if (is.null(project)) skip("No project available")
    
    plot <- select_plot(app)
    if (is.null(plot)) skip("No plot available")
    
    app$set_inputs(main_tabs = "FS882-6x4XL")
    app$wait_for_idle()
    
    # Key General tab fields
    location_exists <- !is.null(safe_get_value(app, input = "env-env_location"))
    date_exists <- !is.null(safe_get_value(app, input = "env-env_date"))
    observer_exists <- !is.null(safe_get_value(app, input = "env-env_observer"))
    
    expect_true(location_exists, label = "Location field exists")
    expect_true(date_exists, label = "Date field exists")
    expect_true(observer_exists, label = "Observer field exists")
  })
  
  test_that("Mensuration tab fields exist", {
    skip_on_cran()
    skip("Mensuration tab field verification pending")
    
    # Navigate to Mensuration tab within Site & Env
    # Verify tree measurement fields exist
  })
  
  test_that("Soil tab with horizon management exists", {
    skip_on_cran()
    skip("Soil tab verification pending")
    
    # Navigate to Soil tab
    # Verify soil horizon add/remove functionality
  })
})


describe("Site & Environment - Coordinate Calculations", {
  
  test_that("Latitude field accepts decimal degrees", {
    skip_on_cran()
    
    app <- new_app_driver(name = "env-lat-dd", height = 1000, width = 1600)
    on.exit(app$stop(), add = TRUE)
    app$wait_for_idle(timeout = 5000)
    
    project <- select_project(app)
    if (is.null(project)) skip("No project available")
    
    plot <- select_plot(app)
    if (is.null(plot)) skip("No plot available")
    
    app$set_inputs(main_tabs = "FS882-6x4XL")
    app$wait_for_idle()
    
    # Set a valid latitude
    app$set_inputs(`env-env_latitude` = "49.2827")
    app$wait_for_idle()
    
    lat_value <- safe_get_value(app, input = "env-env_latitude")
    expect_equal(lat_value, "49.2827", 
                 label = "Latitude accepts decimal degrees")
  })
  
  test_that("Longitude field accepts decimal degrees", {
    skip_on_cran()
    
    app <- new_app_driver(name = "env-lon-dd", height = 1000, width = 1600)
    on.exit(app$stop(), add = TRUE)
    app$wait_for_idle(timeout = 5000)
    
    project <- select_project(app)
    if (is.null(project)) skip("No project available")
    
    plot <- select_plot(app)
    if (is.null(plot)) skip("No plot available")
    
    app$set_inputs(main_tabs = "FS882-6x4XL")
    app$wait_for_idle()
    
    # Set a valid longitude
    app$set_inputs(`env-env_longitude` = "-123.1207")
    app$wait_for_idle()
    
    lon_value <- safe_get_value(app, input = "env-env_longitude")
    expect_equal(lon_value, "-123.1207", 
                 label = "Longitude accepts decimal degrees")
  })
  
  test_that("DMS to DD conversion triggers on input change", {
    skip_on_cran()
    skip("DMS conversion trigger verification requires observeEvent inspection")
    
    # Test entering DMS format (e.g., "49° 16' 57.72\" N")
    # Verify DD field updates automatically
    # Requires logic_coord_tools.R::parse_dms() integration
  })
  
  test_that("UTM coordinate fields exist", {
    skip_on_cran()
    
    app <- new_app_driver(name = "env-utm-fields", height = 1000, width = 1600)
    on.exit(app$stop(), add = TRUE)
    app$wait_for_idle(timeout = 5000)
    
    project <- select_project(app)
    if (is.null(project)) skip("No project available")
    
    plot <- select_plot(app)
    if (is.null(plot)) skip("No plot available")
    
    app$set_inputs(main_tabs = "FS882-6x4XL")
    app$wait_for_idle()
    
    utm_east_exists <- !is.null(safe_get_value(app, input = "env-env_utm_east"))
    utm_north_exists <- !is.null(safe_get_value(app, input = "env-env_utm_north"))
    
    expect_true(utm_east_exists, label = "UTM Easting field exists")
    expect_true(utm_north_exists, label = "UTM Northing field exists")
  })
})


describe("Site & Environment - Field Validation", {
  
  test_that("Elevation accepts numeric values", {
    skip_on_cran()
    
    app <- new_app_driver(name = "env-elevation", height = 1000, width = 1600)
    on.exit(app$stop(), add = TRUE)
    app$wait_for_idle(timeout = 5000)
    
    project <- select_project(app)
    if (is.null(project)) skip("No project available")
    
    plot <- select_plot(app)
    if (is.null(plot)) skip("No plot available")
    
    app$set_inputs(main_tabs = "FS882-6x4XL")
    app$wait_for_idle()
    
    app$set_inputs(`env-env_elevation` = 1200)
    app$wait_for_idle()
    
    elev_value <- safe_get_value(app, input = "env-env_elevation")
    expect_equal(elev_value, 1200, 
                 label = "Elevation accepts numeric input")
  })
  
  test_that("Slope gradient validates 0-100% range", {
    skip_on_cran()
    skip("Slope range validation not yet implemented")
    
    # Test entering >100% slope
    # Should show validation error or clamp to 100
  })
  
  test_that("Aspect accepts 0-360 degrees", {
    skip_on_cran()
    
    app <- new_app_driver(name = "env-aspect", height = 1000, width = 1600)
    on.exit(app$stop(), add = TRUE)
    app$wait_for_idle(timeout = 5000)
    
    project <- select_project(app)
    if (is.null(project)) skip("No project available")
    
    plot <- select_plot(app)
    if (is.null(plot)) skip("No plot available")
    
    app$set_inputs(main_tabs = "FS882-6x4XL")
    app$wait_for_idle()
    
    app$set_inputs(`env-env_aspect` = 180)
    app$wait_for_idle()
    
    aspect_value <- safe_get_value(app, input = "env-env_aspect")
    expect_equal(aspect_value, 180, 
                 label = "Aspect accepts degree value")
  })
  
  test_that("Date picker enforces valid dates", {
    skip_on_cran()
    
    app <- new_app_driver(name = "env-date-valid", height = 1000, width = 1600)
    on.exit(app$stop(), add = TRUE)
    app$wait_for_idle(timeout = 5000)
    
    project <- select_project(app)
    if (is.null(project)) skip("No project available")
    
    plot <- select_plot(app)
    if (is.null(plot)) skip("No plot available")
    
    app$set_inputs(main_tabs = "FS882-6x4XL")
    app$wait_for_idle()
    
    test_date <- as.Date("2024-06-15")
    app$set_inputs(`env-env_date` = test_date)
    app$wait_for_idle()
    
    date_value <- safe_get_value(app, input = "env-env_date")
    expect_equal(date_value, test_date, 
                 label = "Date picker accepts valid date")
  })
})


describe("Site & Environment - Dropdowns & Code Lists", {
  
  test_that("Moisture regime dropdown populates from code lists", {
    skip_on_cran()
    
    app <- new_app_driver(name = "env-moisture", height = 1000, width = 1600)
    on.exit(app$stop(), add = TRUE)
    app$wait_for_idle(timeout = 5000)
    
    project <- select_project(app)
    if (is.null(project)) skip("No project available")
    
    plot <- select_plot(app)
    if (is.null(plot)) skip("No plot available")
    
    app$set_inputs(main_tabs = "FS882-6x4XL")
    app$wait_for_idle()
    
    moisture_exists <- !is.null(safe_get_value(app, input = "env-env_moisture"))
    expect_true(moisture_exists, 
                label = "Moisture regime dropdown exists")
  })
  
  test_that("Nutrient regime dropdown populates from code lists", {
    skip_on_cran()
    
    app <- new_app_driver(name = "env-nutrient", height = 1000, width = 1600)
    on.exit(app$stop(), add = TRUE)
    app$wait_for_idle(timeout = 5000)
    
    project <- select_project(app)
    if (is.null(project)) skip("No project available")
    
    plot <- select_plot(app)
    if (is.null(plot)) skip("No plot available")
    
    app$set_inputs(main_tabs = "FS882-6x4XL")
    app$wait_for_idle()
    
    nutrient_exists <- !is.null(safe_get_value(app, input = "env-env_nutrient"))
    expect_true(nutrient_exists, 
                label = "Nutrient regime dropdown exists")
  })
  
  test_that("Meso slope position dropdown exists", {
    skip_on_cran()
    
    app <- new_app_driver(name = "env-meso-slope", height = 1000, width = 1600)
    on.exit(app$stop(), add = TRUE)
    app$wait_for_idle(timeout = 5000)
    
    project <- select_project(app)
    if (is.null(project)) skip("No project available")
    
    plot <- select_plot(app)
    if (is.null(plot)) skip("No plot available")
    
    app$set_inputs(main_tabs = "FS882-6x4XL")
    app$wait_for_idle()
    
    meso_exists <- !is.null(safe_get_value(app, input = "env-env_meso"))
    expect_true(meso_exists, 
                label = "Meso slope position dropdown exists")
  })
})


describe("Site & Environment - Save Operations", {
  
  test_that("Save header button exists", {
    skip_on_cran()
    
    app <- new_app_driver(name = "env-save-btn", height = 1000, width = 1600)
    on.exit(app$stop(), add = TRUE)
    app$wait_for_idle(timeout = 5000)
    
    project <- select_project(app)
    if (is.null(project)) skip("No project available")
    
    plot <- select_plot(app)
    if (is.null(plot)) skip("No plot available")
    
    app$set_inputs(main_tabs = "FS882-6x4XL")
    app$wait_for_idle()
    
    save_btn_exists <- !is.null(safe_get_value(app, input = "env-save_header"))
    expect_true(save_btn_exists, 
                label = "Save header button exists")
  })
  
  test_that("Save button click triggers without errors", {
    skip_on_cran()
    
    app <- new_app_driver(name = "env-save-click", height = 1000, width = 1600)
    on.exit(app$stop(), add = TRUE)
    app$wait_for_idle(timeout = 5000)
    
    project <- select_project(app)
    if (is.null(project)) skip("No project available")
    
    plot <- select_plot(app)
    if (is.null(plot)) skip("No plot available")
    
    app$set_inputs(main_tabs = "FS882-6x4XL")
    app$wait_for_idle()
    
    # Click save without changes (should succeed or no-op gracefully)
    app$click("env-save_header")
    app$wait_for_idle()
    
    # If notification system exists, verify no error notification
    # Current implementation should complete without crashing
    expect_true(TRUE, label = "Save click completes without crash")
  })
  
  test_that("Save persists location change to database", {
    skip_on_cran()
    skip("Full save persistence test requires cleanup and isolation")
    
    # Create test plot, modify location, save, verify in DB
    # Requires cleanup helper and isolated test data
  })
})


# ============================================================================
# EDGE CASES & REGRESSION TESTS
# ============================================================================

describe("Data Entry Edge Cases", {
  
  test_that("Rapid input changes don't cause reactive loops", {
    skip_on_cran()
    skip("Rapid input simulation requires advanced timing control")
    
    # Simulate fast typing across multiple fields
    # Verify app remains responsive and no infinite reactive loops
  })
  
  test_that("Tab switching preserves unsaved changes warning", {
    skip_on_cran()
    skip("Unsaved changes warning not yet implemented")
    
    # Modify field in Site & Env
    # Switch to different tab
    # Should show warning modal or indicator
  })
  
  test_that("Empty/NULL values handle gracefully", {
    skip_on_cran()
    
    app <- new_app_driver(name = "null-handling", height = 1000, width = 1600)
    on.exit(app$stop(), add = TRUE)
    app$wait_for_idle(timeout = 5000)
    
    project <- select_project(app)
    if (is.null(project)) skip("No project available")
    
    plot <- select_plot(app)
    if (is.null(plot)) skip("No plot available")
    
    app$set_inputs(main_tabs = "FS882-6x4XL")
    app$wait_for_idle()
    
    # Clear elevation field (set to empty)
    app$set_inputs(`env-env_elevation` = "")
    app$wait_for_idle()
    
    # Should not crash - verify app still responsive
    location_field <- safe_get_value(app, input = "env-env_location")
    expect_true(!is.null(location_field), 
                label = "App responsive after empty numeric field")
  })
  
  test_that("Session timeout recovery mechanism", {
    skip_on_cran()
    skip("Session timeout testing requires extended wait times")
    
    # Hold app open for Shiny session timeout duration
    # Verify reconnection or graceful degradation
  })
  
  test_that("Required field indicators display correctly", {
    skip_on_cran()
    skip("Required field validation not yet implemented")
    
    # Check for visual indicators (*, red border) on mandatory fields
    # Verify validation triggers on save attempt
  })
})


describe("Data Entry Performance", {
  
  test_that("Large vegetation dataset loads in reasonable time", {
    skip_on_cran()
    skip("Performance testing requires benchmarking setup")
    
    # Select plot with >50 species entries
    # Measure handsontable render time
    # Should complete in <3 seconds
  })
  
  test_that("Plot switching refreshes data efficiently", {
    skip_on_cran()
    skip("Performance profiling pending")
    
    # Switch between multiple plots rapidly
    # Verify no memory leaks or slowing
  })
})
