# Test Logic - Hierarchy Formatting
#
# Tests for logic_reports_hierarchy.R
# Ported from V7mdlReportsHierarchyDiagram.txt and V7mdlReportsShortVegHierarchy.txt

library(testthat)
library(here)
library(duckdb)

source(here("R", "logic_reports_hierarchy.R"))

# Test database setup
setup_hierarchy_db <- function() {
  con <- dbConnect(duckdb(), dbdir = ":memory:")
  
  dbExecute(con, "
    CREATE TABLE Hierarchy (
      ID INTEGER,
      Name VARCHAR,
      Parent INTEGER,
      Level INTEGER,
      Tag VARCHAR
    )
  ")
  
  # Create a simple hierarchy:
  # Root (1)
  #   ├── Branch1 (2)
  #   │   ├── Leaf1A (4)
  #   │   └── Leaf1B (5)
  #   └── Branch2 (3)
  #       └── Leaf2A (6)
  
  dbExecute(con, "
    INSERT INTO Hierarchy VALUES
    (1, 'Root', NULL, 1, NULL),
    (2, 'Branch1', 1, 2, NULL),
    (3, 'Branch2', 1, 2, NULL),
    (4, 'Leaf1A', 2, 3, NULL),
    (5, 'Leaf1B', 2, 3, NULL),
    (6, 'Leaf2A', 3, 3, NULL)
  ")
  
  con
}

test_that("build_hierarchy_path constructs correct paths", {
  con <- setup_hierarchy_db()
  on.exit(dbDisconnect(con, shutdown = TRUE))
  
  # VBA source: BuildListInXl() logic in V7mdlReportsHierarchyDiagram.txt
  
  # Test leaf node path
  path <- build_hierarchy_path(con, 4)
  expect_equal(path, "Root / Branch1 / Leaf1A")
  
  # Test branch node path
  path <- build_hierarchy_path(con, 2)
  expect_equal(path, "Root / Branch1")
  
  # Test root node path
  path <- build_hierarchy_path(con, 1)
  expect_equal(path, "Root")
  
  # Test with custom separator
  path <- build_hierarchy_path(con, 4, separator = " > ")
  expect_equal(path, "Root > Branch1 > Leaf1A")
})

test_that("walk_hierarchy_down returns all descendants", {
  con <- setup_hierarchy_db()
  on.exit(dbDisconnect(con, shutdown = TRUE))
  
  # VBA source: WalkTheTreeDown() in V7mdlReportsHierarchyDiagram.txt
  
  # Walk from Branch1 - should get Branch1, Leaf1A, Leaf1B
  descendants <- walk_hierarchy_down(con, parent_id = 2)
  
  expect_true(nrow(descendants) >= 2) # At least the 2 leaves
  expect_true(all(c("Leaf1A", "Leaf1B") %in% descendants$Name))
  
  # Walk from root - should get entire tree
  all_nodes <- walk_hierarchy_down(con, parent_id = 1)
  expect_true(nrow(all_nodes) >= 5) # At least 5 descendants
})

test_that("walk_hierarchy_down respects max_level", {
  con <- setup_hierarchy_db()
  on.exit(dbDisconnect(con, shutdown = TRUE))
  
  # Walk with max_level = 1 - should only get immediate children
  descendants <- walk_hierarchy_down(con, parent_id = 1, max_level = 1)
  
  expect_true(all(c("Branch1", "Branch2") %in% descendants$Name))
  expect_false("Leaf1A" %in% descendants$Name)
})

test_that("format_hierarchy_indented adds correct indentation", {
  # VBA source: AddShape() indentation logic in V7mdlReportsHierarchyDiagram.txt
  
  hier_df <- data.frame(
    ID = 1:4,
    Name = c("Root", "Branch", "Leaf", "DeepLeaf"),
    Level = c(1, 2, 3, 4),
    stringsAsFactors = FALSE
  )
  
  result <- format_hierarchy_indented(hier_df)
  
  expect_equal(result$FormattedName[1], "Root")
  expect_equal(result$FormattedName[2], "  Branch")
  expect_equal(result$FormattedName[3], "    Leaf")
  expect_equal(result$FormattedName[4], "      DeepLeaf")
})

test_that("format_hierarchy_indented with level prefix", {
  hier_df <- data.frame(
    ID = 1:3,
    Name = c("Root", "Branch", "Leaf"),
    Level = c(1, 2, 3),
    stringsAsFactors = FALSE
  )
  
  result <- format_hierarchy_indented(hier_df, add_level_prefix = TRUE)
  
  expect_true(grepl("\\[1\\]", result$FormattedName[1]))
  expect_true(grepl("\\[2\\]", result$FormattedName[2]))
  expect_true(grepl("\\[3\\]", result$FormattedName[3]))
})

test_that("order_hierarchy_tree returns tree order", {
  con <- setup_hierarchy_db()
  on.exit(dbDisconnect(con, shutdown = TRUE))
  
  # VBA source: ControlHierarchyOrder() in V7mdlReportsShortVegHierarchy.txt
  
  ordered <- order_hierarchy_tree(con)
  
  # Should be in depth-first order:
  # Root, Branch1, Leaf1A, Leaf1B, Branch2, Leaf2A
  expect_equal(nrow(ordered), 6)
  
  # Root should be first
  expect_equal(ordered$Name[1], "Root")
  
  # Branch1 before Branch2
  branch1_idx <- which(ordered$Name == "Branch1")
  branch2_idx <- which(ordered$Name == "Branch2")
  expect_true(branch1_idx < branch2_idx)
  
  # Leaf1A and Leaf1B should be after Branch1 but before Branch2
  leaf1a_idx <- which(ordered$Name == "Leaf1A")
  expect_true(leaf1a_idx > branch1_idx && leaf1a_idx < branch2_idx)
})

test_that("order_hierarchy_tree respects cutoff_level", {
  con <- setup_hierarchy_db()
  on.exit(dbDisconnect(con, shutdown = TRUE))
  
  # Only include levels 1 and 2
  ordered <- order_hierarchy_tree(con, cutoff_level = 2)
  
  expect_true(nrow(ordered) <= 3) # Root + 2 branches
  expect_false("Leaf1A" %in% ordered$Name)
  expect_false("Leaf1B" %in% ordered$Name)
})

test_that("add_hierarchy_order_columns sets correct min/max", {
  # VBA source: SetMinMax() in V7mdlReportsShortVegHierarchy.txt
  
  hier_df <- data.frame(
    ID = c(1, 2, 3, 4),
    Name = c("Root", "Branch", "Leaf1", "Leaf2"),
    Parent = c(NA, 1, 2, 2),
    stringsAsFactors = FALSE
  )
  
  result <- add_hierarchy_order_columns(hier_df)
  
  expect_true("MinOrder" %in% names(result))
  expect_true("MaxOrder" %in% names(result))
  
  # Root should have min/max spanning all
  expect_equal(result$MinOrder[1], 1)
  expect_true(result$MaxOrder[1] >= 4)
})

test_that("get_hierarchy_level_stats returns correct counts", {
  con <- setup_hierarchy_db()
  on.exit(dbDisconnect(con, shutdown = TRUE))
  
  stats <- get_hierarchy_level_stats(con)
  
  expect_equal(nrow(stats), 3) # 3 levels
  expect_equal(stats$Count[stats$Level == 1], 1) # 1 root
  expect_equal(stats$Count[stats$Level == 2], 2) # 2 branches
  expect_equal(stats$Count[stats$Level == 3], 3) # 3 leaves
})

test_that("build_flat_hierarchy creates complete flat list", {
  con <- setup_hierarchy_db()
  on.exit(dbDisconnect(con, shutdown = TRUE))
  
  # Create lists schema and MasterSiteUnitList
  dbExecute(con, "CREATE SCHEMA lists")
  dbExecute(con, "
    CREATE TABLE lists.MasterSiteUnitList (
      SiteSeries VARCHAR,
      SiteSeriesLongName VARCHAR
    )
  ")
  dbExecute(con, "
    INSERT INTO lists.MasterSiteUnitList VALUES
    ('Root', 'Root Long Name'),
    ('Branch1', 'Branch 1 Long Name')
  ")
  
  flat <- build_flat_hierarchy(con, include_long_names = TRUE)
  
  expect_true("Path" %in% names(flat))
  expect_true("LongName" %in% names(flat))
  
  # Check that paths are built
  leaf1a <- flat[flat$Name == "Leaf1A", ]
  expect_equal(leaf1a$Path, "Root / Branch1 / Leaf1A")
  
  # Check long names were joined
  root_row <- flat[flat$Name == "Root", ]
  expect_equal(root_row$LongName, "Root Long Name")
})

test_that("check_hierarchy_circular_refs detects cycles", {
  con <- dbConnect(duckdb(), dbdir = ":memory:")
  on.exit(dbDisconnect(con, shutdown = TRUE))
  
  # Create hierarchy with circular reference
  dbExecute(con, "
    CREATE TABLE Hierarchy (
      ID INTEGER,
      Name VARCHAR,
      Parent INTEGER,
      Level INTEGER
    )
  ")
  
  dbExecute(con, "
    INSERT INTO Hierarchy VALUES
    (1, 'A', 3, 1),
    (2, 'B', 1, 2),
    (3, 'C', 2, 3)
  ")
  
  circular <- check_hierarchy_circular_refs(con)
  
  # Should detect the cycle
  expect_true(nrow(circular) > 0)
})

test_that("check_hierarchy_circular_refs handles valid hierarchy", {
  con <- setup_hierarchy_db()
  on.exit(dbDisconnect(con, shutdown = TRUE))
  
  circular <- check_hierarchy_circular_refs(con)
  
  # Should find no cycles
  expect_equal(nrow(circular), 0)
})
