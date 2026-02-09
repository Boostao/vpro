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
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  DBI::dbExecute(con, "CREATE TABLE Sample_Hierarchy (ID INTEGER, Name TEXT, Parent INTEGER, Level INTEGER)")
  DBI::dbExecute(con, "INSERT INTO Sample_Hierarchy (ID, Name, Parent) VALUES (1, 'Root', NULL)")

  subtree <- data.frame(
    ID = c(10, 11),
    Name = c("A", "B"),
    Parent = c(NA, 10)
  )

  count <- insert_subtree(con, subtree, 1L, 0L)
  expect_equal(count, 2)

  rows <- DBI::dbGetQuery(con, "SELECT ID, Name, Parent FROM Sample_Hierarchy WHERE Name IN ('A','B')")
  expect_equal(nrow(rows), 2)

  a_id <- rows$ID[rows$Name == "A"][1]
  b_parent <- rows$Parent[rows$Name == "B"][1]
  expect_equal(rows$Parent[rows$Name == "A"][1], 1)
  expect_equal(b_parent, a_id)

  levels <- DBI::dbGetQuery(con, "SELECT Name, Level FROM Sample_Hierarchy WHERE Name IN ('A','B')")
  level_a <- levels$Level[levels$Name == "A"][1]
  level_b <- levels$Level[levels$Name == "B"][1]
  expect_equal(level_a, 1)
  expect_equal(level_b, 2)
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

test_that("get_subtree_names returns unique names", {
  df <- data.frame(
    ID = c(1, 2, 3, 4),
    Name = c("Root", "ChildA", "ChildB", "Grand"),
    Parent = c(NA, 1, 1, 2)
  )

  names <- get_subtree_names(df, 1)
  expect_true(all(c("Root", "ChildA", "ChildB", "Grand") %in% names))
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
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  DBI::dbExecute(con, "CREATE TABLE Sample_Hierarchy (ID INTEGER, Parent INTEGER)")
  DBI::dbExecute(con, "INSERT INTO Sample_Hierarchy VALUES (1, NULL)")
  DBI::dbExecute(con, "INSERT INTO Sample_Hierarchy VALUES (2, 99)")

  count <- fix_orphan_nodes(con)
  expect_equal(count, 1)

  parents <- DBI::dbGetQuery(con, "SELECT Parent FROM Sample_Hierarchy WHERE ID = 2")$Parent
  expect_true(is.na(parents[1]))
})
