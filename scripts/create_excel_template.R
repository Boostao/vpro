#!/usr/bin/env Rscript
# Script to Generate Excel Template for VPRO Exports
# Creates a pre-styled template with sheet structure and instructions

if (!requireNamespace("openxlsx", quietly = TRUE)) {
  stop("openxlsx package required. Install with: install.packages('openxlsx')")
}

library(openxlsx)

# Create template workbook
wb <- createWorkbook()

# Define color scheme (Access-like)
HEADER_BG <- "#4472C4"  # Blue
HEADER_FG <- "#FFFFFF"  # White
ALT_ROW <- "#F2F2F2"    # Light gray

# Helper: Create header style
header_style <- createStyle(
  fgFill = HEADER_BG,
  halign = "center",
  textDecoration = "bold",
  fontColour = HEADER_FG,
  fontSize = 11,
  border = "TopBottomLeftRight",
  borderColour = "#FFFFFF"
)

# --- Instructions Sheet ---
addWorksheet(wb, "Instructions")

instructions <- data.frame(
  Section = c(
    "About This Template",
    "Vegetation Sheets",
    "Environment Sheet",
    "Soil Sheets",
    "Metadata Sheet",
    "Data Entry",
    "Export Options",
    "Support"
  ),
  Description = c(
    "This template provides a standardized structure for VPRO field data exports in Excel format with professional formatting.",
    "Vegetation data is organized by layer: A1-A3 (Trees), B1-B2 (Shrubs), C (Herbs), D (Moss). Each species observation includes scientific name, common name, and cover%.",
    "Site-level environmental data includes location, BEC classification, topography, and site characteristics.",
    "Soil profile data is organized by horizon with humus and mineral characteristics separately.",
    "Project-level information including ID, title, lead, organization, and purpose.",
    "DO NOT edit directly in this template. Use the VPRO Shiny app Export tab to generate populated workbooks from database.",
    "When exporting, you can choose: separate sheets per layer, apply species lumping, include soil data, and apply conditional formatting (colors).",
    "For questions or issues, refer to the VPRO documentation or contact your project administrator."
  )
)

writeData(wb, "Instructions", instructions)
addStyle(wb, "Instructions", header_style, rows = 1, cols = 1:2, gridExpand = TRUE)
setColWidths(wb, "Instructions", cols = 1, widths = 20)
setColWidths(wb, "Instructions", cols = 2, widths = 90)
freezePane(wb, "Instructions", firstRow = TRUE)

# --- VegA_Trees1 Template ---
addWorksheet(wb, "VegA_Trees1")

veg_headers <- data.frame(
  Plot = character(),
  Layer = character(),
  Code = character(),
  `Scientific Name` = character(),
  `Common Name` = character(),
  `Cover %` = numeric(),
  check.names = FALSE
)

writeData(wb, "VegA_Trees1", veg_headers)
addStyle(wb, "VegA_Trees1", header_style, rows = 1, cols = 1:6, gridExpand = TRUE)

# Set column widths
setColWidths(wb, "VegA_Trees1", cols = 1, widths = 12)  # Plot
setColWidths(wb, "VegA_Trees1", cols = 2, widths = 6)   # Layer
setColWidths(wb, "VegA_Trees1", cols = 3, widths = 10)  # Code
setColWidths(wb, "VegA_Trees1", cols = 4, widths = 25)  # Scientific Name
setColWidths(wb, "VegA_Trees1", cols = 5, widths = 25)  # Common Name
setColWidths(wb, "VegA_Trees1", cols = 6, widths = 8)   # Cover

freezePane(wb, "VegA_Trees1", firstRow = TRUE)

# Add instruction row
writeData(wb, "VegA_Trees1", 
          data.frame(Plot = "Sample data will appear here when exported from VPRO",
                     Layer = "", Code = "", `Scientific Name` = "", `Common Name` = "", `Cover %` = NA,
                     check.names = FALSE),
          startRow = 2)

# --- VegC_Herbs Template ---
addWorksheet(wb, "VegC_Herbs")
writeData(wb, "VegC_Herbs", veg_headers)
addStyle(wb, "VegC_Herbs", header_style, rows = 1, cols = 1:6, gridExpand = TRUE)
setColWidths(wb, "VegC_Herbs", cols = 1:6, widths = c(12, 6, 10, 25, 25, 8))
freezePane(wb, "VegC_Herbs", firstRow = TRUE)

# --- Environment Template ---
addWorksheet(wb, "Environment")

env_headers <- data.frame(
  Plot = character(),
  Project = character(),
  Location = character(),
  Date = character(),
  Surveyor = character(),
  Latitude = numeric(),
  Longitude = numeric(),
  Elevation = numeric(),
  Slope = numeric(),
  Aspect = numeric(),
  Zone = character(),
  Subzone = character(),
  `Site Series` = character(),
  Moisture = character(),
  Nutrient = character(),
  Notes = character(),
  check.names = FALSE
)

writeData(wb, "Environment", env_headers)
addStyle(wb, "Environment", header_style, rows = 1, cols = 1:ncol(env_headers), gridExpand = TRUE)
setColWidths(wb, "Environment", cols = 1:ncol(env_headers), widths = "auto")
setColWidths(wb, "Environment", cols = 3, widths = 25)  # Location
setColWidths(wb, "Environment", cols = 16, widths = 40) # Notes
freezePane(wb, "Environment", firstRow = TRUE)

# --- Soil_Humus Template ---
addWorksheet(wb, "Soil_Humus")

humus_headers <- data.frame(
  Plot = character(),
  Horizon = character(),
  `Upper Depth (cm)` = numeric(),
  `Lower Depth (cm)` = numeric(),
  `Humus Form pH` = numeric(),
  `von Post` = character(),
  Comment = character(),
  check.names = FALSE
)

writeData(wb, "Soil_Humus", humus_headers)
addStyle(wb, "Soil_Humus", header_style, rows = 1, cols = 1:ncol(humus_headers), gridExpand = TRUE)
setColWidths(wb, "Soil_Humus", cols = 1:ncol(humus_headers), widths = "auto")
freezePane(wb, "Soil_Humus", firstRow = TRUE)

# --- Soil_Mineral Template ---
addWorksheet(wb, "Soil_Mineral")

mineral_headers <- data.frame(
  Plot = character(),
  Horizon = character(),
  `Upper Depth (cm)` = numeric(),
  `Lower Depth (cm)` = numeric(),
  Texture = character(),
  `Coarse Frags %` = numeric(),
  pH = numeric(),
  Comment = character(),
  check.names = FALSE
)

writeData(wb, "Soil_Mineral", mineral_headers)
addStyle(wb, "Soil_Mineral", header_style, rows = 1, cols = 1:ncol(mineral_headers), gridExpand = TRUE)
setColWidths(wb, "Soil_Mineral", cols = 1:ncol(mineral_headers), widths = "auto")
freezePane(wb, "Soil_Mineral", firstRow = TRUE)

# --- Project_Metadata Template ---
addWorksheet(wb, "Project_Metadata")

meta_headers <- data.frame(
  `Project ID` = character(),
  `Project Title` = character(),
  `Project Lead` = character(),
  Organisation = character(),
  Purpose = character(),
  Status = character(),
  `Start Date` = character(),
  `End Date` = character(),
  check.names = FALSE
)

writeData(wb, "Project_Metadata", meta_headers)
addStyle(wb, "Project_Metadata", header_style, rows = 1, cols = 1:ncol(meta_headers), gridExpand = TRUE)
setColWidths(wb, "Project_Metadata", cols = 1:ncol(meta_headers), widths = "auto")
setColWidths(wb, "Project_Metadata", cols = 2, widths = 30)  # Title
setColWidths(wb, "Project_Metadata", cols = 5, widths = 40)  # Purpose
freezePane(wb, "Project_Metadata", firstRow = TRUE)

# Save template
output_dir <- "inst"
if (!dir.exists(output_dir)) {
  dir.create(output_dir, recursive = TRUE)
}

output_path <- file.path(output_dir, "excel_template.xlsx")
saveWorkbook(wb, output_path, overwrite = TRUE)

cat("Excel template created successfully:\n")
cat("  ", normalizePath(output_path), "\n")
cat("\nTemplate contains", length(names(wb)), "sheets:\n")
cat("  ", paste(names(wb), collapse = ", "), "\n")
