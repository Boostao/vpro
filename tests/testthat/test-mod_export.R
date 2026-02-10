# Tests for Export module

source(here::here("R", "mod_export.R"))

setup_export_tables <- function(con) {
  DBI::dbExecute(con, "CREATE TABLE Sample_Env (plotnumber TEXT, projectid TEXT, latitude DOUBLE, longitude DOUBLE, _location TEXT, extrafield TEXT)")
  DBI::dbExecute(con, "CREATE TABLE Sample_Veg (plotnumber TEXT, species TEXT)")
  DBI::dbExecute(con, "CREATE TABLE Sample_Humus (plotnumber TEXT, horizon TEXT, upperdepth DOUBLE, lowerdepth DOUBLE, humusstructuredegree TEXT, _comment TEXT)")
  DBI::dbExecute(con, "CREATE TABLE Sample_Mineral (plotnumber TEXT, horizon TEXT, upperdepth DOUBLE, lowerdepth DOUBLE, pitdepthlimit TEXT, _comments TEXT)")
  DBI::dbExecute(con, "CREATE TABLE Sample_Other (plotnumber TEXT, dataname TEXT, dataitem TEXT, useritem1 TEXT, useritem2 TEXT)")
  DBI::dbExecute(con, "CREATE TABLE Sample_Audit (Project TEXT, \"User\" TEXT, PlotNumber TEXT, \"Table\" TEXT, EditField TEXT)")

  DBI::dbExecute(con, "INSERT INTO Sample_Env VALUES ('P1', 'PRJ1', 49.0, -123.5, 'LOC1', 'X')")
  DBI::dbExecute(con, "INSERT INTO Sample_Env VALUES ('P2', 'PRJ2', 50.0, -120.0, 'LOC2', 'Y')")
  DBI::dbExecute(con, "INSERT INTO Sample_Veg VALUES ('P1', 'AB')")
  DBI::dbExecute(con, "INSERT INTO Sample_Veg VALUES ('P2', 'FD')")
  DBI::dbExecute(con, "INSERT INTO Sample_Humus VALUES ('P1', 'H1', 0, 5, 'D', 'Humus note')")
  DBI::dbExecute(con, "INSERT INTO Sample_Mineral VALUES ('P1', 'M1', 5, 10, 'Y', 'Mineral note')")
  DBI::dbExecute(con, "INSERT INTO Sample_Other VALUES ('P1', 'Note', 'Item', 'U1', 'U2')")
  DBI::dbExecute(con, "INSERT INTO Sample_Audit (Project, \"User\", PlotNumber, \"Table\", EditField) VALUES ('PRJ1', 'tester', 'P1', 'Sample_Env', 'FieldNumber')")
  DBI::dbExecute(con, "INSERT INTO Sample_Audit (Project, \"User\", PlotNumber, \"Table\", EditField) VALUES ('PRJ2', 'tester', 'P2', 'Sample_Env', 'FieldNumber')")
}

test_that("build_venus_xml_doc filters by project", {
  testthat::skip_if_not_installed("xml2")

  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  setup_export_tables(con)

  doc <- build_venus_xml_doc(
    con,
    project_ids = "PRJ1",
    tables = c("Sample_Env", "Sample_Veg", "Sample_Humus", "Sample_Mineral", "Sample_Other", "Sample_Audit")
  )

  meta_name <- xml2::xml_text(xml2::xml_find_first(doc, "/VProExport/ExportMeta/Name"))
  meta_count <- xml2::xml_text(xml2::xml_find_first(doc, "/VProExport/ExportMeta/ProjectCount"))
  expect_equal(meta_name, "PRJ1")
  expect_equal(meta_count, "1")

  project_nodes <- xml2::xml_find_all(doc, "/VProExport/Project")
  expect_equal(length(project_nodes), 1)
  expect_equal(xml2::xml_attr(project_nodes, "id"), "PRJ1")

  env_rows <- xml2::xml_find_all(doc, "/VProExport/Project/PRJ1_Env/Row")
  veg_rows <- xml2::xml_find_all(doc, "/VProExport/Project/PRJ1_Veg/Row")
  audit_rows <- xml2::xml_find_all(doc, "/VProExport/Project/PRJ1_Audit/Row")
  expect_equal(length(env_rows), 1)
  expect_equal(length(veg_rows), 1)
  expect_equal(length(audit_rows), 1)

  lat_deg <- xml2::xml_text(xml2::xml_find_first(doc, "/VProExport/Project/PRJ1_Env/Row/LatitudeDegrees"))
  lat_min <- xml2::xml_text(xml2::xml_find_first(doc, "/VProExport/Project/PRJ1_Env/Row/LatitudeMinutes"))
  lat_sec <- xml2::xml_text(xml2::xml_find_first(doc, "/VProExport/Project/PRJ1_Env/Row/LatitudeSeconds"))
  lon_deg <- xml2::xml_text(xml2::xml_find_first(doc, "/VProExport/Project/PRJ1_Env/Row/LongitudeDegrees"))
  lon_min <- xml2::xml_text(xml2::xml_find_first(doc, "/VProExport/Project/PRJ1_Env/Row/LongitudeMinutes"))
  lon_sec <- xml2::xml_text(xml2::xml_find_first(doc, "/VProExport/Project/PRJ1_Env/Row/LongitudeSeconds"))

  expect_equal(lat_deg, "49")
  expect_equal(lat_min, "0")
  expect_equal(lat_sec, "0")
  expect_equal(lon_deg, "123")
  expect_equal(lon_min, "30")
  expect_equal(lon_sec, "0")

  extra_nodes <- xml2::xml_find_all(doc, "//ExtraField|//extrafield")
  expect_equal(length(extra_nodes), 0)

  env_row <- xml2::xml_find_first(doc, "/VProExport/Project/PRJ1_Env/Row")
  env_names <- xml2::xml_name(xml2::xml_children(env_row))
  expect_equal(env_names[1:5], c("PlotNumber", "FieldNumber", "ProjectID", "FSRegionDistrict", "Date"))

  field_number <- xml2::xml_text(xml2::xml_find_first(env_row, "FieldNumber"))
  fs_region <- xml2::xml_text(xml2::xml_find_first(env_row, "FSRegionDistrict"))
  location_val <- xml2::xml_text(xml2::xml_find_first(env_row, "Location"))
  expect_equal(field_number, "")
  expect_equal(fs_region, "")
  expect_equal(location_val, "LOC1")

  lat_idx <- which(env_names == "Latitude")
  lon_idx <- which(env_names == "Longitude")
  expect_true(length(lat_idx) == 1)
  expect_true(length(lon_idx) == 1)
  expect_equal(env_names[(lat_idx + 1):(lat_idx + 3)], c("LatitudeDegrees", "LatitudeMinutes", "LatitudeSeconds"))
  expect_equal(env_names[(lon_idx + 1):(lon_idx + 3)], c("LongitudeDegrees", "LongitudeMinutes", "LongitudeSeconds"))

  veg_row <- xml2::xml_find_first(doc, "/VProExport/Project/PRJ1_Veg/Row")
  veg_names <- xml2::xml_name(xml2::xml_children(veg_row))
  expect_equal(veg_names[1:5], c("PlotNumber", "Species", "Layer", "Cover1", "Height1"))

  humus_row <- xml2::xml_find_first(doc, "/VProExport/Project/PRJ1_Humus/Row")
  humus_names <- xml2::xml_name(xml2::xml_children(humus_row))
  expect_equal(humus_names[1:5], c("PlotNumber", "Horizon", "UpperDepth", "LowerDepth", "HumusStructureDegree"))
  humus_mycel <- xml2::xml_text(xml2::xml_find_first(humus_row, "MycelAbundance"))
  humus_comment <- xml2::xml_text(xml2::xml_find_first(humus_row, "Comment"))
  expect_equal(humus_mycel, "")
  expect_equal(humus_comment, "Humus note")

  mineral_row <- xml2::xml_find_first(doc, "/VProExport/Project/PRJ1_Mineral/Row")
  mineral_names <- xml2::xml_name(xml2::xml_children(mineral_row))
  expect_equal(mineral_names[1:5], c("PlotNumber", "Horizon", "UpperDepth", "LowerDepth", "PitDepthLimit"))
  mineral_colour <- xml2::xml_text(xml2::xml_find_first(mineral_row, "Colour"))
  expect_equal(mineral_colour, "")
  mineral_comment <- xml2::xml_text(xml2::xml_find_first(mineral_row, "Comments"))
  expect_equal(mineral_comment, "Mineral note")

  other_row <- xml2::xml_find_first(doc, "/VProExport/Project/PRJ1_Other/Row")
  other_names <- xml2::xml_name(xml2::xml_children(other_row))
  expect_equal(other_names[1:5], c("PlotNumber", "DataName", "DataItem", "UserItem1", "UserItem2"))

  audit_row <- xml2::xml_find_first(doc, "/VProExport/Project/PRJ1_Audit/Row")
  audit_names <- xml2::xml_name(xml2::xml_children(audit_row))
  expect_equal(audit_names[1:5], c("Project", "User", "PlotNumber", "Table", "EditField"))
})

test_that("build_venus_xml_doc exports all when project_ids empty", {
  testthat::skip_if_not_installed("xml2")

  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  setup_export_tables(con)

  doc <- build_venus_xml_doc(con, project_ids = character(0), tables = c("Sample_Env"))

  meta_name <- xml2::xml_text(xml2::xml_find_first(doc, "/VProExport/ExportMeta/Name"))
  meta_count <- xml2::xml_text(xml2::xml_find_first(doc, "/VProExport/ExportMeta/ProjectCount"))
  expect_equal(meta_name, "ALL")
  expect_equal(meta_count, "2")

  project_nodes <- xml2::xml_find_all(doc, "/VProExport/Project")
  expect_equal(length(project_nodes), 1)
  expect_equal(xml2::xml_attr(project_nodes, "id"), "ALL")

  env_rows <- xml2::xml_find_all(doc, "/VProExport/Project/ALL_Env/Row")
  expect_equal(length(env_rows), 2)
})

test_that("build_venus_xml_doc uses optional table prefix", {
  testthat::skip_if_not_installed("xml2")

  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  setup_export_tables(con)

  doc <- build_venus_xml_doc(con, project_ids = "PRJ1", tables = c("Sample_Env"), table_prefix = "MyExport")

  meta_name <- xml2::xml_text(xml2::xml_find_first(doc, "/VProExport/ExportMeta/Name"))
  expect_equal(meta_name, "MyExport")

  env_rows <- xml2::xml_find_all(doc, "/VProExport/Project/MyExport_Env/Row")
  expect_equal(length(env_rows), 1)
})

test_that("build_venus_xml_doc prefixes per project when exporting multiple", {
  testthat::skip_if_not_installed("xml2")

  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  setup_export_tables(con)

  doc <- build_venus_xml_doc(
    con,
    project_ids = c("PRJ1", "PRJ2"),
    tables = c("Sample_Env"),
    table_prefix = "Batch"
  )

  meta_count <- xml2::xml_text(xml2::xml_find_first(doc, "/VProExport/ExportMeta/ProjectCount"))
  expect_equal(meta_count, "2")

  env_prj1 <- xml2::xml_find_all(doc, "/VProExport/Project/Batch_PRJ1_Env/Row")
  env_prj2 <- xml2::xml_find_all(doc, "/VProExport/Project/Batch_PRJ2_Env/Row")
  expect_equal(length(env_prj1), 1)
  expect_equal(length(env_prj2), 1)
})

test_that("build_venus_xml_doc uses project ids when no prefix provided", {
  testthat::skip_if_not_installed("xml2")

  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  setup_export_tables(con)

  doc <- build_venus_xml_doc(
    con,
    project_ids = c("PRJ1", "PRJ2"),
    tables = c("Sample_Env")
  )

  env_prj1 <- xml2::xml_find_all(doc, "/VProExport/Project/PRJ1_Env/Row")
  env_prj2 <- xml2::xml_find_all(doc, "/VProExport/Project/PRJ2_Env/Row")
  expect_equal(length(env_prj1), 1)
  expect_equal(length(env_prj2), 1)
})
