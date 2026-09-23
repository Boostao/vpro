source(here::here("R", "mod_hierarchy.R"))

test_that("hierarchy label helpers work", {
  label <- hierarchy_label("Forest", 12)
  expect_equal(label, "Forest [12]")
  expect_equal(parse_hierarchy_id(label), 12L)
  expect_true(is.na(parse_hierarchy_id("Forest")))
  expect_true(is.na(parse_hierarchy_id(NULL)))
})

test_that("build_hierarchy_tree nests children", {
  df <- data.frame(
    ID = c(1, 2, 3, 4),
    Name = c("Root", "ChildA", "ChildB", "Grand"),
    Parent = c(NA, 1, 1, 2)
  )

  tree <- build_hierarchy_tree(df)
  expect_true("Root [1]" %in% names(tree))
  expect_true("ChildA [2]" %in% names(tree[["Root [1]"]]))
  expect_true("Grand [4]" %in% names(tree[["Root [1]"]][["ChildA [2]"]]))
})

test_that("build_hierarchy_tree respects MyOrder", {
  df <- data.frame(
    ID = c(1, 2, 3),
    Name = c("Beta", "Alpha", "Gamma"),
    Parent = c(NA, NA, NA),
    MyOrder = c(2, 1, 3)
  )

  tree <- build_hierarchy_tree(df)
  expect_equal(names(tree), c("Alpha [2]", "Beta [1]", "Gamma [3]"))
})

test_that("descendants and subtree selection", {
  df <- data.frame(
    ID = c(1, 2, 3, 4),
    Name = c("Root", "ChildA", "ChildB", "Grand"),
    Parent = c(NA, 1, 1, 2)
  )

  expect_equal(sort(get_descendants(df, 1)), c(2, 3, 4))
  subtree <- get_subtree(df, 2)
  expect_equal(sort(subtree$ID), c(2, 4))
})

test_that("insert_subtree remaps ids and parents", {
  con <- DBI::dbConnect(duckdb::duckdb(), ":memory:")
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  DBI::dbExecute(con, "CREATE TABLE Hierarchy (ID INTEGER, Name TEXT, Parent INTEGER, Level INTEGER)")
  DBI::dbExecute(con, "INSERT INTO Hierarchy (ID, Name, Parent) VALUES (1, 'Root', NULL)")

  subtree <- data.frame(
    ID = c(10, 11),
    Name = c("A", "B"),
    Parent = c(NA, 10)
  )

  count <- insert_subtree(con, subtree, 1L, 0L)
  expect_equal(count, 2)

  rows <- DBI::dbGetQuery(con, "SELECT ID, Name, Parent FROM Hierarchy WHERE Name IN ('A','B')")
  expect_equal(nrow(rows), 2)

  a_id <- rows$ID[rows$Name == "A"][1]
  b_parent <- rows$Parent[rows$Name == "B"][1]
  expect_equal(rows$Parent[rows$Name == "A"][1], 1)
  expect_equal(b_parent, a_id)

  levels <- DBI::dbGetQuery(con, "SELECT Name, Level FROM Hierarchy WHERE Name IN ('A','B')")
  level_a <- levels$Level[levels$Name == "A"][1]
  level_b <- levels$Level[levels$Name == "B"][1]
  expect_equal(level_a, 1)
  expect_equal(level_b, 2)
})

test_that("insert_subtree preserves tag when available", {
  con <- DBI::dbConnect(duckdb::duckdb(), ":memory:")
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  DBI::dbExecute(con, "CREATE TABLE Hierarchy (ID INTEGER, Name TEXT, Parent INTEGER, Level INTEGER, Tag TEXT)")
  DBI::dbExecute(con, "INSERT INTO Hierarchy (ID, Name, Parent) VALUES (1, 'Root', NULL)")

  subtree <- data.frame(
    ID = c(10),
    Name = c("Tagged"),
    Parent = c(NA),
    Tag = c("yellow")
  )

  insert_subtree(con, subtree, 1L, 0L)
  rows <- DBI::dbGetQuery(con, "SELECT Tag FROM Hierarchy WHERE Name = 'Tagged'")
  expect_equal(rows$Tag[1], "yellow")
})

test_that("compute_subtree_levels assigns depth", {
  df <- data.frame(
    ID = c(1, 2, 3, 4),
    Name = c("Root", "ChildA", "ChildB", "Grand"),
    Parent = c(NA, 1, 1, 2)
  )

  levels <- compute_subtree_levels(df, parent_level = -1L)
  expect_equal(levels[["1"]], 0L)
  expect_equal(levels[["2"]], 1L)
  expect_equal(levels[["4"]], 2L)
})

test_that("get_sibling_order respects MyOrder", {
  df <- data.frame(
    ID = c(1, 2, 3),
    Name = c("B", "A", "C"),
    Parent = c(NA, NA, NA),
    MyOrder = c(2, 1, 3)
  )

  ordered <- get_sibling_order(df, NA_integer_)
  expect_equal(ordered$ID, c(2, 1, 3))
})

test_that("get_node_path returns breadcrumb", {
  df <- data.frame(
    ID = c(1, 2, 3, 4),
    Name = c("Root", "ChildA", "ChildB", "Grand"),
    Parent = c(NA, 1, 1, 2)
  )

  path <- get_node_path(df, 4)
  expect_equal(path, c("Root", "ChildA", "Grand"))
})

test_that("get_node_path_ids returns id breadcrumb", {
  df <- data.frame(
    ID = c(1, 2, 3, 4),
    Name = c("Root", "ChildA", "ChildB", "Grand"),
    Parent = c(NA, 1, 1, 2)
  )

  ids <- get_node_path_ids(df, 4)
  expect_equal(ids, c(1, 2, 4))
})

test_that("get_subtree_names returns unique names", {
  df <- data.frame(
    ID = c(1, 2, 3, 4),
    Name = c("Root", "ChildA", "ChildB", "Grand"),
    Parent = c(NA, 1, 1, 2)
  )

  names <- get_subtree_names(df, 1)
  expect_true(all(c("Root", "ChildA", "ChildB", "Grand") %in% names))
})

test_that("get_plots_for_site_unit returns plots", {
  con <- DBI::dbConnect(duckdb::duckdb(), ":memory:")
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  DBI::dbExecute(con, "CREATE TABLE SU (PlotNumber TEXT, SiteUnit TEXT)")
  DBI::dbExecute(con, "INSERT INTO SU VALUES ('P1', 'SU1')")
  DBI::dbExecute(con, "INSERT INTO SU VALUES ('P2', 'SU1')")

  plots <- get_plots_for_site_unit(con, "SU1")
  expect_true(all(c("P1", "P2") %in% plots))
})

test_that("filter_duplicate_names drops existing names", {
  source <- data.frame(
    ID = c(1, 2, 3),
    Name = c("A", "B", "C"),
    Parent = c(NA, NA, NA)
  )

  filtered <- filter_duplicate_names(source, c("B", "Z"))
  expect_equal(filtered$dropped, 1)
  expect_equal(filtered$data$Name, c("A", "C"))
})

test_that("resolve_duplicate_names can prefix duplicates", {
  source <- data.frame(
    ID = c(1, 2, 3),
    Name = c("A", "B", "C"),
    Parent = c(NA, NA, NA)
  )

  resolved <- resolve_duplicate_names(source, c("B"), mode = "prefix", prefix = "Merged - ")
  expect_equal(resolved$renamed, 1)
  expect_true(any(grepl("^Merged - ", resolved$data$Name)))
  expect_false(any(resolved$data$Name == "B"))
})

test_that("filter_duplicate_subtrees drops duplicate parents and descendants", {
  source <- data.frame(
    ID = c(1, 2, 3, 4),
    Name = c("Dup", "Child", "Other", "Leaf"),
    Parent = c(NA, 1, NA, 3)
  )

  filtered <- filter_duplicate_subtrees(source, c("Dup"))
  expect_false(1 %in% filtered$data$ID)
  expect_false(2 %in% filtered$data$ID)
  expect_true(all(c(3, 4) %in% filtered$data$ID))
})

test_that("insert_rekeyed_hierarchy remaps parents", {
  con <- DBI::dbConnect(duckdb::duckdb(), ":memory:")
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  DBI::dbExecute(con, "CREATE TABLE Hierarchy (ID INTEGER, Name TEXT, Parent INTEGER)")
  DBI::dbExecute(con, "INSERT INTO Hierarchy VALUES (1, 'Root', NULL)")

  source <- data.frame(
    ID = c(10, 11),
    Name = c("A", "B"),
    Parent = c(NA, 10)
  )

  result <- insert_rekeyed_hierarchy(con, source)
  expect_equal(result$count, 2)

  rows <- DBI::dbGetQuery(con, "SELECT Name, Parent FROM Hierarchy WHERE Name IN ('A', 'B')")
  a_id <- rows$Parent[rows$Name == "A"][1]
  b_parent <- rows$Parent[rows$Name == "B"][1]
  expect_true(is.na(a_id))
  expect_false(is.na(b_parent))
})

test_that("insert_rekeyed_hierarchy preserves tag when available", {
  con <- DBI::dbConnect(duckdb::duckdb(), ":memory:")
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  DBI::dbExecute(con, "CREATE TABLE Hierarchy (ID INTEGER, Name TEXT, Parent INTEGER, Tag TEXT)")
  DBI::dbExecute(con, "INSERT INTO Hierarchy VALUES (1, 'Root', NULL, NULL)")

  source <- data.frame(
    ID = c(10),
    Name = c("Tagged"),
    Parent = c(NA),
    Tag = c("green")
  )

  insert_rekeyed_hierarchy(con, source)
  rows <- DBI::dbGetQuery(con, "SELECT Tag FROM Hierarchy WHERE Name = 'Tagged'")
  expect_equal(rows$Tag[1], "green")
})

test_that("clip_hierarchy_ids removes non-tilde branches", {
  df <- data.frame(
    ID = c(1, 2, 3, 4, 5, 6),
    Name = c("Root", "~Clip", "ChildA", "ChildB", "~Keep", "~KeepChild"),
    Parent = c(NA, 1, 2, 2, 1, 5)
  )

  delete_ids <- clip_hierarchy_ids(df)
  expect_false(2 %in% delete_ids)
  expect_true(3 %in% delete_ids)
  expect_true(4 %in% delete_ids)
  expect_false(6 %in% delete_ids)
})

test_that("get_lowest_tilde_ids identifies lowest tilde nodes", {
  df <- data.frame(
    ID = c(1, 2, 3, 4, 5, 6),
    Name = c("Root", "~Clip", "ChildA", "ChildB", "~Keep", "~KeepChild"),
    Parent = c(NA, 1, 2, 2, 1, 5)
  )

  lowest <- get_lowest_tilde_ids(df)
  expect_true(2 %in% lowest)
  expect_true(6 %in% lowest)
  expect_false(5 %in% lowest)
})

test_that("set_lowest_tilde_levels sets level to 11", {
  con <- DBI::dbConnect(duckdb::duckdb(), ":memory:")
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  DBI::dbExecute(con, "CREATE TABLE USysLowestBreakpoints_Hierarchy (ID INTEGER, Level INTEGER)")
  DBI::dbExecute(con, "INSERT INTO USysLowestBreakpoints_Hierarchy VALUES (1, 2)")
  DBI::dbExecute(con, "INSERT INTO USysLowestBreakpoints_Hierarchy VALUES (2, 3)")

  updated <- set_lowest_tilde_levels(con, "USysLowestBreakpoints_Hierarchy", c(1, 2))
  expect_equal(updated, 2)

  levels <- DBI::dbGetQuery(con, "SELECT Level FROM USysLowestBreakpoints_Hierarchy ORDER BY ID")$Level
  expect_equal(levels, c(11, 11))
})

test_that("create_lowest_breakpoints_table builds lowest tilde subtrees", {
  con <- DBI::dbConnect(duckdb::duckdb(), ":memory:")
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  DBI::dbExecute(con, "CREATE TABLE Hierarchy (ID INTEGER, Name TEXT, Parent INTEGER, Level INTEGER)")
  DBI::dbExecute(con, "INSERT INTO Hierarchy VALUES (1, 'Root', NULL, 1)")
  DBI::dbExecute(con, "INSERT INTO Hierarchy VALUES (2, '~Clip', 1, 2)")
  DBI::dbExecute(con, "INSERT INTO Hierarchy VALUES (3, 'ChildA', 2, 3)")
  DBI::dbExecute(con, "INSERT INTO Hierarchy VALUES (4, '~Keep', 1, 2)")
  DBI::dbExecute(con, "INSERT INTO Hierarchy VALUES (5, '~KeepChild', 4, 3)")

  result <- create_lowest_breakpoints_table(con)
  expect_equal(result$roots, 2)
  expect_true(DBI::dbExistsTable(con, "USysLowestBreakpoints_Hierarchy"))

  rows <- DBI::dbGetQuery(con, "SELECT ID, Parent, Level FROM USysLowestBreakpoints_Hierarchy ORDER BY ID")
  expect_equal(rows$ID, c(2, 3, 5))
  expect_true(all(is.na(rows$Parent[rows$ID %in% c(2, 5)])))
  expect_true(all(rows$Level == c(1, 2, 1)))
})

test_that("sync helpers copy values between env and su", {
  con <- DBI::dbConnect(duckdb::duckdb(), ":memory:")
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  DBI::dbExecute(con, "CREATE TABLE Env (PlotNumber TEXT, UserSiteUnit TEXT, BECSiteUnit TEXT)")
  DBI::dbExecute(con, "CREATE TABLE SU (PlotNumber TEXT, SiteUnit TEXT)")
  DBI::dbExecute(con, "INSERT INTO Env VALUES ('P1', 'SU_A', 'BEC1')")
  DBI::dbExecute(con, "INSERT INTO Env VALUES ('P2', NULL, 'BEC2')")
  DBI::dbExecute(con, "INSERT INTO SU VALUES ('P1', 'OLD')")
  DBI::dbExecute(con, "INSERT INTO SU VALUES ('P2', 'OLD2')")

  updated_env_to_su <- sync_env_to_su(con)
  expect_true(updated_env_to_su >= 0)
  su_vals <- DBI::dbGetQuery(con, "SELECT SiteUnit FROM SU ORDER BY PlotNumber")$SiteUnit
  expect_equal(su_vals, c("SU_A", NA))

  updated_bec <- copy_bec_to_su(con)
  expect_true(updated_bec >= 0)
  su_vals_bec <- DBI::dbGetQuery(con, "SELECT SiteUnit FROM SU ORDER BY PlotNumber")$SiteUnit
  expect_equal(su_vals_bec, c("BEC1", "BEC2"))

  DBI::dbExecute(con, "UPDATE SU SET SiteUnit = 'SU_NEW' WHERE PlotNumber = 'P1'")
  updated_su_to_env <- sync_su_to_env(con)
  expect_true(updated_su_to_env >= 0)
  env_vals <- DBI::dbGetQuery(con, "SELECT UserSiteUnit FROM Env ORDER BY PlotNumber")$UserSiteUnit
  expect_equal(env_vals, c("SU_NEW", "BEC2"))
})

test_that("build_su_from_env builds filtered rows", {
  con <- DBI::dbConnect(duckdb::duckdb(), ":memory:")
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  DBI::dbExecute(con, "CREATE TABLE Env (PlotNumber TEXT, Zone TEXT, SubZone TEXT, UserSiteUnit TEXT)")
  DBI::dbExecute(con, "CREATE TABLE SU (PlotNumber TEXT, SiteUnit TEXT)")
  DBI::dbExecute(con, "INSERT INTO Env VALUES ('P1', 'Z1', 'A', 'SU1')")
  DBI::dbExecute(con, "INSERT INTO Env VALUES ('P2', 'Z1', 'B', 'SU2')")
  DBI::dbExecute(con, "INSERT INTO Env VALUES ('P3', 'Z2', 'A', 'SU3')")

  count <- build_su_from_env(con, zone = "Z1", subzone = "A", replace = TRUE)
  expect_true(count >= 0)
  rows <- DBI::dbGetQuery(con, "SELECT PlotNumber, SiteUnit FROM SU ORDER BY PlotNumber")
  expect_equal(rows$PlotNumber, "P1")
  expect_equal(rows$SiteUnit, "SU1")

  count2 <- build_su_from_env(con, zone = "Z1", subzone = "", replace = TRUE)
  expect_true(count2 >= 0)
  rows2 <- DBI::dbGetQuery(con, "SELECT PlotNumber FROM SU ORDER BY PlotNumber")$PlotNumber
  expect_equal(rows2, c("P1", "P2"))
})

test_that("build_su_from_env_filter respects column filters", {
  con <- DBI::dbConnect(duckdb::duckdb(), ":memory:")
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  DBI::dbExecute(con, "CREATE TABLE Env (PlotNumber TEXT, Zone TEXT, UserSiteUnit TEXT)")
  DBI::dbExecute(con, "CREATE TABLE SU (PlotNumber TEXT, SiteUnit TEXT)")
  DBI::dbExecute(con, "INSERT INTO Env VALUES ('P1', 'Z1', 'SU1')")
  DBI::dbExecute(con, "INSERT INTO Env VALUES ('P2', 'Z2', 'SU2')")

  count <- build_su_from_env_filter(con, column = "Zone", value = "Z1", replace = TRUE)
  expect_true(count >= 0)
  rows <- DBI::dbGetQuery(con, "SELECT PlotNumber, SiteUnit FROM SU")
  expect_equal(rows$PlotNumber, "P1")
  expect_equal(rows$SiteUnit, "SU1")
})

test_that("get_master_site_units filters by level", {
  con <- DBI::dbConnect(duckdb::duckdb(), ":memory:")
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  DBI::dbExecute(con, "CREATE SCHEMA lists")
  DBI::dbExecute(con, "CREATE TABLE lists.MasterSiteUnitList (SiteSeries TEXT, SiteSeriesLongName TEXT, Level INTEGER)")
  DBI::dbExecute(con, "INSERT INTO lists.MasterSiteUnitList VALUES ('SS1', 'Series 1', 1)")
  DBI::dbExecute(con, "INSERT INTO lists.MasterSiteUnitList VALUES ('SS2', 'Series 2', 2)")

  all_rows <- get_master_site_units(con)
  expect_equal(nrow(all_rows), 2)

  filtered <- get_master_site_units(con, level = "1")
  expect_equal(filtered$SiteSeries, "SS1")
})

test_that("get_user_site_units returns user list rows", {
  con <- DBI::dbConnect(duckdb::duckdb(), ":memory:")
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  DBI::dbExecute(con, "CREATE SCHEMA user")
  DBI::dbExecute(
    con,
    "CREATE TABLE user.UserSiteUnitList (ID INTEGER, SiteSeries TEXT, SiteSeriesLongName TEXT, Level INTEGER)"
  )
  DBI::dbExecute(con, "INSERT INTO user.UserSiteUnitList VALUES (1, 'U1', 'User 1', 11)")
  DBI::dbExecute(con, "INSERT INTO user.UserSiteUnitList VALUES (2, 'U2', 'User 2', 12)")

  rows <- get_user_site_units(con)
  expect_equal(nrow(rows), 2)
  expect_true(all(c("U1", "U2") %in% rows$SiteSeries))

  filtered <- get_user_site_units(con, level = "11")
  expect_equal(filtered$SiteSeries, "U1")
})

test_that("find_orphan_nodes identifies missing parents", {
  df <- data.frame(
    ID = c(1, 2, 3),
    Name = c("Root", "Orphan", "Child"),
    Parent = c(NA, 99, 1)
  )

  orphans <- find_orphan_nodes(df)
  expect_equal(orphans, 2)
})

test_that("fix_orphan_nodes resets missing parents", {
  con <- DBI::dbConnect(duckdb::duckdb(), ":memory:")
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  DBI::dbExecute(con, "CREATE TABLE Hierarchy (ID INTEGER, Parent INTEGER)")
  DBI::dbExecute(con, "INSERT INTO Hierarchy VALUES (1, NULL)")
  DBI::dbExecute(con, "INSERT INTO Hierarchy VALUES (2, 99)")

  count <- fix_orphan_nodes(con)
  expect_equal(count, 1)

  parents <- DBI::dbGetQuery(con, "SELECT Parent FROM Hierarchy WHERE ID = 2")$Parent
  expect_true(is.na(parents[1]))
})
