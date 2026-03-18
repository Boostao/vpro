# Tests for VENUS XML Export Logic

library(testthat)
library(DBI)
library(duckdb)
library(xml2)

# Helper: Create in-memory test database
create_test_db <- function() {
  con <- dbConnect(duckdb::duckdb(), ":memory:")
  
  # Create tables
  dbExecute(con, "
    CREATE TABLE Metadata (
      projectid VARCHAR,
      projecttitle VARCHAR,
      projectdescription VARCHAR
    )
  ")
  
  dbExecute(con, "
    CREATE TABLE Env (
      plotnumber VARCHAR,
      fieldnumber VARCHAR,
      projectid VARCHAR,
      date VARCHAR,
      sitesurveyor VARCHAR,
      plotrepresenting VARCHAR,
      _location VARCHAR,
      ecosection VARCHAR,
      ntsmapsheet VARCHAR,
      latitude DOUBLE,
      longitude DOUBLE,
      utmzone VARCHAR,
      utmeasting DOUBLE,
      utmnorthing DOUBLE,
      elevation DOUBLE,
      slopegradient DOUBLE,
      aspect DOUBLE,
      mesoslopeposition VARCHAR,
      surfaceshape VARCHAR,
      zone VARCHAR,
      subzone VARCHAR,
      siteseries VARCHAR,
      sitemodifier1 VARCHAR,
      sitemodifier2 VARCHAR,
      moistureregime VARCHAR,
      nutrientregime VARCHAR,
      structuralstage VARCHAR,
      successionalstatus VARCHAR,
      stratacovertree DOUBLE,
      stratacovershrub DOUBLE,
      stratacoverherb DOUBLE,
      stratacovermoss DOUBLE,
      vegsurveyor VARCHAR,
      vegnotes VARCHAR,
      substratedecwood DOUBLE,
      substratebedrock DOUBLE,
      substraterocks DOUBLE,
      substratemineralsoil DOUBLE,
      substrateorganicmatter DOUBLE,
      substratewater DOUBLE,
      sitedisturbance1 VARCHAR,
      sitedisturbance2 VARCHAR,
      sitedisturbance3 VARCHAR,
      sitenotes VARCHAR,
      temporary INTEGER,
      flag INTEGER
    )
  ")
  
  dbExecute(con, "
    CREATE TABLE Veg (
      plotnumber VARCHAR,
      species VARCHAR,
      cover1 VARCHAR,
      cover2 VARCHAR,
      cover3 VARCHAR,
      cover4 VARCHAR,
      cover5 VARCHAR,
      cover6 VARCHAR,
      cover7 VARCHAR
    )
  ")
  
  # Create view
  dbExecute(con, "
    CREATE VIEW vw_USysAllVeg AS
    SELECT PlotNumber, 1 AS MyLayer, Species, Cover1 AS Cover FROM Veg WHERE Cover1 IS NOT NULL
    UNION ALL
    SELECT PlotNumber, 2 AS MyLayer, Species, Cover2 AS Cover FROM Veg WHERE Cover2 IS NOT NULL
    UNION ALL
    SELECT PlotNumber, 3 AS MyLayer, Species, Cover3 AS Cover FROM Veg WHERE Cover3 IS NOT NULL
    UNION ALL
    SELECT PlotNumber, 4 AS MyLayer, Species, Cover4 AS Cover FROM Veg WHERE Cover4 IS NOT NULL
    UNION ALL
    SELECT PlotNumber, 5 AS MyLayer, Species, Cover5 AS Cover FROM Veg WHERE Cover5 IS NOT NULL
    UNION ALL
    SELECT PlotNumber, 6 AS MyLayer, Species, Cover6 AS Cover FROM Veg WHERE Cover6 IS NOT NULL
    UNION ALL
    SELECT PlotNumber, 7 AS MyLayer, Species, Cover7 AS Cover FROM Veg WHERE Cover7 IS NOT NULL
  ")
  
  dbExecute(con, "
    CREATE TABLE Humus (
      plotnumber VARCHAR,
      horizon VARCHAR,
      upperdepth DOUBLE,
      lowerdepth DOUBLE,
      vonpost INTEGER,
      humusformpH DOUBLE,
      _comment VARCHAR
    )
  ")
  
  dbExecute(con, "
    CREATE TABLE Mineral (
      plotnumber VARCHAR,
      horizon VARCHAR,
      upperdepth DOUBLE,
      lowerdepth DOUBLE,
      colour VARCHAR,
      texture VARCHAR,
      percentcoarsefragstotal DOUBLE,
      mineralformpH DOUBLE,
      _comments VARCHAR
    )
  ")
  
  dbExecute(con, "
    CREATE TABLE Lump (
      sppcode VARCHAR,
      lumpcode VARCHAR,
      _use INTEGER
    )
  ")
  
  con
}

# Seed test data
seed_test_data <- function(con) {
  # Add metadata
  dbExecute(con, "
    INSERT INTO Metadata VALUES
    ('TEST01', 'Test Project 1', 'A test project for VENUS export'),
    ('TEST02', 'Test Project 2', 'Another test project')
  ")
  
  # Add plots
  dbExecute(con, "
    INSERT INTO Env (
      plotnumber, fieldnumber, projectid, date, sitesurveyor,
      plotrepresenting, _location, ecosection, ntsmapsheet,
      latitude, longitude, utmzone, utmeasting, utmnorthing,
      elevation, slopegradient, aspect, mesoslopeposition,
      zone, subzone, siteseries, moistureregime, nutrientregime,
      structuralstage, successionalstatus,
      stratacovertree, stratacovershrub, stratacoverherb, stratacovermoss,
      vegsurveyor, vegnotes, sitenotes,
      temporary, flag
    ) VALUES
    ('P001', 'F001', 'TEST01', '2024-06-15', 'John Doe',
     'Stand', 'Near creek', 'SIM', '92J/03',
     49.5, -121.5, '10U', 500000, 5500000,
     850, 25, 180, 'mid',
     'CWH', 'dm', '01', '5', 'C',
     '6', 'climax',
     65, 40, 20, 80,
     'Jane Smith', 'Mature forest', 'Access via logging road',
     0, 0),
    ('P002', 'F002', 'TEST01', '2024-06-16', 'John Doe',
     'Stand', 'Ridge top', 'SIM', '92J/03',
     49.6, -121.6, '10U', 501000, 5501000,
     1200, 35, 90, 'upper',
     'ESSF', 'mk', '02', '3', 'B',
     '4', 'pioneer',
     30, 50, 15, 60,
     'Jane Smith', NULL, 'Rocky outcrop',
     0, 0),
    ('P003', 'F003', 'TEST01', '2024-06-17', 'John Doe',
     'Stand', 'Valley bottom', 'SIM', '92J/03',
     NULL, NULL, NULL, NULL, NULL,
     500, 10, 270, 'lower',
     'ICH', 'mw', '03', '6', 'D',
     '5', 'mature',
     50, 30, 40, 70,
     'Jane Smith', NULL, 'No coordinates',
     1, 0)
  ")
  
  # Add vegetation
  dbExecute(con, "
    INSERT INTO Veg (plotnumber, species, cover1, cover2, cover4, cover6, cover7) VALUES
    ('P001', 'TSHE', '40', '15', NULL, NULL, NULL),
    ('P001', 'THPL', '25', NULL, NULL, NULL, NULL),
    ('P001', 'VAOV', NULL, NULL, '30', NULL, NULL),
    ('P001', 'MEFE', NULL, NULL, NULL, '10', NULL),
    ('P001', 'HYSP', NULL, NULL, NULL, NULL, '70'),
    ('P002', 'ABLA', '25', NULL, NULL, NULL, NULL),
    ('P002', 'PIEN', '5', NULL, NULL, NULL, NULL),
    ('P002', 'VASC', NULL, NULL, '40', NULL, NULL),
    ('P002', 'PLSC', NULL, NULL, NULL, NULL, '50')
  ")
  
  # Add soil horizons
  dbExecute(con, "
    INSERT INTO Humus (plotnumber, horizon, upperdepth, lowerdepth, vonpost, humusformpH, _comment) VALUES
    ('P001', 'L', 0, 2, NULL, NULL, 'Fresh litter'),
    ('P001', 'F', 2, 5, 3, 4.5, 'Partially decomposed'),
    ('P001', 'H', 5, 10, 6, 4.2, 'Well decomposed')
  ")
  
  dbExecute(con, "
    INSERT INTO Mineral (plotnumber, horizon, upperdepth, lowerdepth, colour, texture, percentcoarsefragstotal, mineralformpH, _comments) VALUES
    ('P001', 'Ae', 10, 15, '10YR 5/2', 'SL', 15, 5.0, 'Eluviated horizon'),
    ('P001', 'Bt', 15, 45, '7.5YR 4/4', 'SCL', 25, 5.5, 'Clay accumulation'),
    ('P001', 'C', 45, 100, '2.5Y 5/3', 'L', 30, 6.0, 'Parent material')
  ")
  
  # Add lumping data
  dbExecute(con, "
    INSERT INTO Lump (sppcode, lumpcode, _use) VALUES
    ('TSHE', 'TSHE', 1),
    ('THPL', 'THPL', 1),
    ('VAOV', 'VACCINIUM', 1),
    ('VASC', 'VACCINIUM', 1)
  ")
}

# --- TESTS ---

test_that("export_venus_xml creates valid XML file", {
  con <- create_test_db()
  seed_test_data(con)
  
  tmp_file <- tempfile(fileext = ".xml")
  
  result <- export_venus_xml(con, "TEST01", tmp_file, list(coords_required = FALSE))
  
  expect_true(result$success)
  expect_true(file.exists(tmp_file))
  expect_gt(result$file_size, 0)
  expect_equal(result$plot_count, 3)
  
  # Read and validate XML
  doc <- read_xml(tmp_file)
  expect_s3_class(doc, "xml_document")
  
  # Check root element
  expect_equal(xml_name(doc), "VENUSDataset")
  expect_equal(xml_attr(doc, "version"), "5.0")
  
  # Clean up
  dbDisconnect(con, shutdown = TRUE)
  unlink(tmp_file)
})

test_that("VENUS XML contains correct header information", {
  con <- create_test_db()
  seed_test_data(con)
  
  tmp_file <- tempfile(fileext = ".xml")
  result <- export_venus_xml(con, "TEST01", tmp_file, list(coords_required = FALSE))
  
  doc <- read_xml(tmp_file)
  
  # Check header
  header <- xml_find_first(doc, "//Header")
  expect_s3_class(header, "xml_node")
  
  # Check project info
  proj_id <- xml_text(xml_find_first(header, "//ProjectID"))
  expect_equal(proj_id, "TEST01")
  
  proj_name <- xml_text(xml_find_first(header, "//ProjectName"))
  expect_equal(proj_name, "Test Project 1")
  
  # Check export metadata
  export_date <- xml_text(xml_find_first(header, "//ExportDate"))
  expect_match(export_date, "\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}")
  
  source_sys <- xml_text(xml_find_first(header, "//SourceSystem"))
  expect_equal(source_sys, "VPro R/Shiny")
  
  dbDisconnect(con, shutdown = TRUE)
  unlink(tmp_file)
})

test_that("VENUS XML contains correct plot structure", {
  con <- create_test_db()
  seed_test_data(con)
  
  tmp_file <- tempfile(fileext = ".xml")
  result <- export_venus_xml(con, "TEST01", tmp_file, list(coords_required = FALSE))
  
  doc <- read_xml(tmp_file)
  
  # Check plots
  plots <- xml_find_all(doc, "//Plot")
  expect_length(plots, 3)
  
  # Check first plot
  plot1 <- plots[[1]]
  expect_equal(xml_attr(plot1, "id"), "P001")
  
  # Check PlotInfo
  plot_num <- xml_text(xml_find_first(plot1, ".//PlotNumber"))
  expect_equal(plot_num, "P001")
  
  field_num <- xml_text(xml_find_first(plot1, ".//FieldNumber"))
  expect_equal(field_num, "F001")
  
  date <- xml_text(xml_find_first(plot1, ".//Date"))
  expect_equal(date, "2024-06-15")
  
  dbDisconnect(con, shutdown = TRUE)
  unlink(tmp_file)
})

test_that("VENUS XML includes location data", {
  con <- create_test_db()
  seed_test_data(con)
  
  tmp_file <- tempfile(fileext = ".xml")
  result <- export_venus_xml(con, "TEST01", tmp_file, list(coords_required = FALSE))
  
  doc <- read_xml(tmp_file)
  plot1 <- xml_find_first(doc, "//Plot[@id='P001']")
  
  # Check geographic coordinates
  lat <- xml_text(xml_find_first(plot1, ".//Latitude"))
  expect_match(lat, "49\\.5")
  
  lon <- xml_text(xml_find_first(plot1, ".//Longitude"))
  expect_match(lon, "-121\\.5")
  
  # Check UTM
  utm_zone <- xml_text(xml_find_first(plot1, ".//UTMCoordinates/Zone"))
  expect_equal(utm_zone, "10U")
  
  easting <- xml_text(xml_find_first(plot1, ".//Easting"))
  expect_equal(easting, "5e+05")
  
  # Check administrative
  ecosection <- xml_text(xml_find_first(plot1, ".//Ecosection"))
  expect_equal(ecosection, "SIM")
  
  elevation <- xml_text(xml_find_first(plot1, ".//Elevation"))
  expect_equal(elevation, "850")
  
  dbDisconnect(con, shutdown = TRUE)
  unlink(tmp_file)
})

test_that("VENUS XML includes site classification", {
  con <- create_test_db()
  seed_test_data(con)
  
  tmp_file <- tempfile(fileext = ".xml")
  result <- export_venus_xml(con, "TEST01", tmp_file, list(coords_required = FALSE))
  
  doc <- read_xml(tmp_file)
  plot1 <- xml_find_first(doc, "//Plot[@id='P001']")
  
  # Check BEC classification
  zone <- xml_text(xml_find_first(plot1, ".//BEC/Zone"))
  expect_equal(zone, "CWH")
  
  subzone <- xml_text(xml_find_first(plot1, ".//BEC/SubZone"))
  expect_equal(subzone, "dm")
  
  site_series <- xml_text(xml_find_first(plot1, ".//BEC/SiteSeries"))
  expect_equal(site_series, "01")
  
  # Check site conditions
  moisture <- xml_text(xml_find_first(plot1, ".//MoistureRegime"))
  expect_equal(moisture, "5")
  
  nutrient <- xml_text(xml_find_first(plot1, ".//NutrientRegime"))
  expect_equal(nutrient, "C")
  
  dbDisconnect(con, shutdown = TRUE)
  unlink(tmp_file)
})

test_that("VENUS XML includes vegetation data", {
  con <- create_test_db()
  seed_test_data(con)
  
  tmp_file <- tempfile(fileext = ".xml")
  result <- export_venus_xml(con, "TEST01", tmp_file, list(
    coords_required = FALSE,
    apply_lumping = FALSE
  ))
  
  doc <- read_xml(tmp_file)
  plot1 <- xml_find_first(doc, "//Plot[@id='P001']")
  
  # Check surveyor
  surveyor <- xml_text(xml_find_first(plot1, ".//Vegetation/Surveyor"))
  expect_equal(surveyor, "Jane Smith")
  
  # Check strata totals
  tree_cover <- xml_text(xml_find_first(plot1, ".//TreeCover"))
  expect_equal(tree_cover, "65")
  
  shrub_cover <- xml_text(xml_find_first(plot1, ".//ShrubCover"))
  expect_equal(shrub_cover, "40")
  
  # Check layers
  layers <- xml_find_all(plot1, ".//Vegetation/Layer")
  expect_gte(length(layers), 3)
  
  # Check layer 1 (Tree A1)
  layer1 <- xml_find_first(plot1, ".//Layer[@code='1']")
  expect_equal(xml_attr(layer1, "name"), "Tree Layer A1")
  
  # Check species in layer 1
  species <- xml_find_all(layer1, "./Species")
  expect_gte(length(species), 2)
  
  # Check TSHE
  tshe <- xml_find_first(layer1, "./Species[@code='TSHE']")
  tshe_cover <- xml_text(xml_find_first(tshe, "./Cover"))
  expect_equal(tshe_cover, "40")
  
  dbDisconnect(con, shutdown = TRUE)
  unlink(tmp_file)
})

test_that("VENUS XML includes environment data", {
  con <- create_test_db()
  seed_test_data(con)
  
  tmp_file <- tempfile(fileext = ".xml")
  result <- export_venus_xml(con, "TEST01", tmp_file, list(coords_required = FALSE))
  
  doc <- read_xml(tmp_file)
  plot1 <- xml_find_first(doc, "//Plot[@id='P001']")
  
  env <- xml_find_first(plot1, ".//Environment")
  expect_s3_class(env, "xml_node")
  
  # Check surveyor
  surveyor <- xml_text(xml_find_first(env, "./Surveyor"))
  expect_equal(surveyor, "John Doe")
  
  # Check topography
  aspect <- xml_text(xml_find_first(env, ".//Aspect"))
  expect_equal(aspect, "180")
  
  slope <- xml_text(xml_find_first(env, ".//SlopeGradient"))
  expect_equal(slope, "25")
  
  # Check substrate
  decwood <- xml_text(xml_find_first(env, ".//DecayedWood"))
  expect_true(nzchar(decwood))
  
  dbDisconnect(con, shutdown = TRUE)
  unlink(tmp_file)
})

test_that("VENUS XML includes soil horizon data", {
  con <- create_test_db()
  seed_test_data(con)
  
  tmp_file <- tempfile(fileext = ".xml")
  result <- export_venus_xml(con, "TEST01", tmp_file, list(coords_required = FALSE))
  
  doc <- read_xml(tmp_file)
  plot1 <- xml_find_first(doc, "//Plot[@id='P001']")
  
  soil <- xml_find_first(plot1, ".//Soil")
  expect_s3_class(soil, "xml_node")
  
  # Check organic horizons
  organic_horizons <- xml_find_all(soil, ".//OrganicHorizons/Horizon")
  expect_length(organic_horizons, 3)
  
  # Check first organic horizon
  hz1 <- organic_horizons[[1]]
  hz_code <- xml_text(xml_find_first(hz1, "./HorizonCode"))
  expect_equal(hz_code, "L")
  
  upper <- xml_text(xml_find_first(hz1, "./UpperDepth"))
  expect_equal(upper, "0")
  
  lower <- xml_text(xml_find_first(hz1, "./LowerDepth"))
  expect_equal(lower, "2")
  
  # Check mineral horizons
  mineral_horizons <- xml_find_all(soil, ".//MineralHorizons/Horizon")
  expect_length(mineral_horizons, 3)
  
  # Check first mineral horizon
  mhz1 <- mineral_horizons[[1]]
  mhz_code <- xml_text(xml_find_first(mhz1, "./HorizonCode"))
  expect_equal(mhz_code, "Ae")
  
  colour <- xml_text(xml_find_first(mhz1, "./Colour"))
  expect_equal(colour, "10YR 5/2")
  
  texture <- xml_text(xml_find_first(mhz1, "./Texture"))
  expect_equal(texture, "SL")
  
  dbDisconnect(con, shutdown = TRUE)
  unlink(tmp_file)
})

test_that("coords_required option filters plots correctly", {
  con <- create_test_db()
  seed_test_data(con)
  
  # Without coords requirement
  tmp_file1 <- tempfile(fileext = ".xml")
  result1 <- export_venus_xml(con, "TEST01", tmp_file1, list(coords_required = FALSE))
  expect_equal(result1$plot_count, 3)
  
  # With coords requirement (should exclude P003)
  tmp_file2 <- tempfile(fileext = ".xml")
  result2 <- export_venus_xml(con, "TEST01", tmp_file2, list(coords_required = TRUE))
  expect_equal(result2$plot_count, 2)
  
  # Verify P003 is excluded
  doc2 <- read_xml(tmp_file2)
  plot3 <- xml_find_first(doc2, "//Plot[@id='P003']")
  expect_true(inherits(plot3, "xml_missing"))
  
  dbDisconnect(con, shutdown = TRUE)
  unlink(c(tmp_file1, tmp_file2))
})

test_that("include_draft option filters plots correctly", {
  con <- create_test_db()
  seed_test_data(con)
  
  # Exclude draft (P003 has temporary=1)
  tmp_file1 <- tempfile(fileext = ".xml")
  result1 <- export_venus_xml(con, "TEST01", tmp_file1, list(
    coords_required = FALSE,
    include_draft = FALSE
  ))
  expect_equal(result1$plot_count, 2)
  
  # Include draft
  tmp_file2 <- tempfile(fileext = ".xml")
  result2 <- export_venus_xml(con, "TEST01", tmp_file2, list(
    coords_required = FALSE,
    include_draft = TRUE
  ))
  expect_equal(result2$plot_count, 3)
  
  dbDisconnect(con, shutdown = TRUE)
  unlink(c(tmp_file1, tmp_file2))
})

test_that("apply_lumping option consolidates species", {
  con <- create_test_db()
  seed_test_data(con)
  
  # Without lumping
  tmp_file1 <- tempfile(fileext = ".xml")
  result1 <- export_venus_xml(con, "TEST01", tmp_file1, list(
    coords_required = FALSE,
    apply_lumping = FALSE
  ))
  
  doc1 <- read_xml(tmp_file1)
  plot1 <- xml_find_first(doc1, "//Plot[@id='P001']")
  vaov <- xml_find_first(plot1, ".//Species[@code='VAOV']")
  expect_s3_class(vaov, "xml_node")
  
  # With lumping (VAOV should become VACCINIUM)
  tmp_file2 <- tempfile(fileext = ".xml")
  result2 <- export_venus_xml(con, "TEST01", tmp_file2, list(
    coords_required = FALSE,
    apply_lumping = TRUE
  ))
  
  doc2 <- read_xml(tmp_file2)
  plot1_lumped <- xml_find_first(doc2, "//Plot[@id='P001']")
  
  # VAOV should not exist
  vaov_lumped <- xml_find_first(plot1_lumped, ".//Species[@code='VAOV']")
  expect_true(inherits(vaov_lumped, "xml_missing"))
  
  # VACCINIUM should exist
  vaccinium <- xml_find_first(plot1_lumped, ".//Species[@code='VACCINIUM']")
  expect_s3_class(vaccinium, "xml_node")
  
  dbDisconnect(con, shutdown = TRUE)
  unlink(c(tmp_file1, tmp_file2))
})

test_that("date range filtering works correctly", {
  con <- create_test_db()
  seed_test_data(con)
  
  # Filter to only 2024-06-15
  tmp_file1 <- tempfile(fileext = ".xml")
  result1 <- export_venus_xml(con, "TEST01", tmp_file1, list(
    coords_required = FALSE,
    date_from = "2024-06-15",
    date_to = "2024-06-15"
  ))
  expect_equal(result1$plot_count, 1)
  
  # Filter to 2024-06-15 and later
  tmp_file2 <- tempfile(fileext = ".xml")
  result2 <- export_venus_xml(con, "TEST01", tmp_file2, list(
    coords_required = FALSE,
    date_from = "2024-06-15"
  ))
  expect_equal(result2$plot_count, 3)
  
  # Filter to before 2024-06-17
  tmp_file3 <- tempfile(fileext = ".xml")
  result3 <- export_venus_xml(con, "TEST01", tmp_file3, list(
    coords_required = FALSE,
    date_to = "2024-06-16"
  ))
  expect_equal(result3$plot_count, 2)
  
  dbDisconnect(con, shutdown = TRUE)
  unlink(c(tmp_file1, tmp_file2, tmp_file3))
})

test_that("export handles missing project gracefully", {
  con <- create_test_db()
  seed_test_data(con)
  
  tmp_file <- tempfile(fileext = ".xml")
  result <- export_venus_xml(con, "NONEXISTENT", tmp_file, list(coords_required = FALSE))
  
  # Should succeed but with 0 plots
  expect_true(result$success)
  expect_equal(result$plot_count, 0)
  
  dbDisconnect(con, shutdown = TRUE)
  unlink(tmp_file)
})

test_that("export handles NULL project ID", {
  con <- create_test_db()
  seed_test_data(con)
  
  tmp_file <- tempfile(fileext = ".xml")
  result <- export_venus_xml(con, NULL, tmp_file, list(coords_required = FALSE))
  
  # Should export all plots from all projects
  expect_true(result$success)
  expect_gte(result$plot_count, 3)
  
  dbDisconnect(con, shutdown = TRUE)
  unlink(tmp_file)
})

test_that("validate_venus_schema detects missing plots", {
  root <- xml_new_root("VENUSDataset")
  xml_set_attr(root, "version", "5.0")
  
  validation <- validate_venus_schema(root)
  
  expect_false(validation$valid)
  expect_match(validation$message, "No plots found")
})

test_that("validate_venus_schema detects missing required elements", {
  root <- xml_new_root("VENUSDataset")
  plots_node <- xml_add_child(root, "Plots")
  plot_node <- xml_add_child(plots_node, "Plot")
  xml_set_attr(plot_node, "id", "P001")
  # Missing PlotInfo
  xml_add_child(plot_node, "Location")
  
  validation <- validate_venus_schema(root)
  
  expect_false(validation$valid)
  expect_match(validation$message, "PlotInfo")
})

test_that("export returns error on failure", {
  con <- create_test_db()
  
  # Invalid path should cause error
  result <- export_venus_xml(con, "TEST01", "/invalid/path/file.xml", list())
  
  expect_false(result$success)
  expect_true(!is.null(result$error))
  
  dbDisconnect(con, shutdown = TRUE)
})
