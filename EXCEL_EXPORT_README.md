# Excel Export Feature - Installation & Usage

## Overview
The Excel export functionality provides professional, Access-report-like exports with:
- Styled headers (blue background, bold white text)
- Conditional formatting (colors for high/low/missing values)
- Multiple sheet organization (vegetation by layer, environment, soil, metadata)
- Auto-sized columns and frozen header rows
- Data validation and proper formatting

## Runtime Note

The canonical local databases are now SQLite files under `data/` and `data/projects/`.

The target app/runtime model is an in-memory DuckDB connection that attaches those SQLite databases at boot. The export code still expects the same logical tables/views, but backend examples should now be read as SQLite-backed DuckDB sessions rather than persistent local DuckDB files.

## Installation

### Required Package
The Excel export feature requires the `openxlsx` R package.

```r
# Install openxlsx
install.packages("openxlsx")

# Or with renv (recommended for project)
renv::install("openxlsx")
renv::snapshot()  # Update renv.lock
```

### Verify Installation
```r
# Check if installed
requireNamespace("openxlsx", quietly = TRUE)

# Check version
packageVersion("openxlsx")
```

## Usage

### From Shiny App
1. Navigate to **Export** tab
2. Select **Export Excel (Formatted)** card
3. Choose export type:
   - **Vegetation Only**: Multi-sheet workbook with vegetation data by layer
   - **Environment & Soil**: Site/environment data with soil profiles
   - **Combined (All Data)**: Everything in one workbook (recommended)
4. Configure options:
   - Separate sheet per vegetation layer (creates VegA_Trees1, VegB_Shrub1, etc.)
   - Apply species lumping (consolidate synonyms)
   - Include soil data (humus & mineral horizons)
   - Include project metadata sheet
   - Apply conditional formatting (color highlights)
5. Click **Download Excel (.xlsx)**
6. Check status message for file size and sheet count confirmation

### Programmatic Export (R Console)
```r
library(DBI)
library(duckdb)
source("R/logic_excel_export.R")

con <- dbConnect(duckdb(), dbdir = ":memory:")
dbExecute(con, "ATTACH 'data/VPro64.db' AS main (TYPE SQLITE)")
dbExecute(con, "ATTACH 'data/VLists.db' AS lists (TYPE SQLITE)")
dbExecute(con, "ATTACH 'data/VMetaData.db' AS metadata (TYPE SQLITE)")
dbExecute(con, "ATTACH 'data/VUser.db' AS user (TYPE SQLITE)")

# Export vegetation only
export_vegetation_excel(
  con, 
  "output/my_veg_export.xlsx",
  options = list(
    project_ids = c("ABC123"),
    layers = c("1", "6"),  # Trees and Herbs
    apply_lumping = TRUE,
    separate_sheets = TRUE,
    conditional_formatting = TRUE
  )
)

# Export combined dataset
export_combined_excel(
  con,
  "output/my_complete_export.xlsx",
  options = list(
    project_ids = c("ABC123", "DEF456"),
    layers = c("1", "2", "3", "4", "5", "6", "7"),
    include_soil = TRUE
  )
)

dbDisconnect(con, shutdown = TRUE)
```

## Excel Template

A template Excel file (`inst/excel_template.xlsx`) provides reference structure.

### Generate Template
```r
source("scripts/create_excel_template.R")
# Creates inst/excel_template.xlsx
```

The template shows:
- Expected sheet names and structure
- Column headers and widths
- Styling examples
- Instructions and data dictionary

## Features

### Styling Specifications

**Color Scheme (Access-like):**
- Header: Blue (#4472C4) background, white text, bold
- Alternating rows: White / Light gray (#F2F2F2)
- Conditional formatting:
  - High cover (>75%): Light green (#C6EFCE)
  - Missing required data: Light yellow (#FFF2CC)
  - Invalid data: Light red (#FFC7CE)

**Column Widths:**
- Plot ID: 12 characters
- Species Code: 10
- Scientific Name: 25
- Cover %: 8
- Comments/Notes: 30-40
- Auto-sized for other columns

**Data Formatting:**
- Dates: YYYY-MM-DD
- Decimals: 2 places for percentages
- Coordinates: 6 decimal places
- Numeric columns stored as numbers (not text)

### Sheet Organization

**Vegetation Export:**
- Separate sheets per layer (optional):
  - `VegA_Trees1`, `VegA_Trees2`, `VegA_Trees3`
  - `VegB_Shrub1`, `VegB_Shrub2`
  - `VegC_Herbs`
  - `VegD_Moss`
- Or single `Vegetation` sheet with all layers

**Environment Export:**
- `Environment`: Plot-level site characteristics
- `Soil_Humus`: Humus horizon descriptions
- `Soil_Mineral`: Mineral horizon descriptions

**Combined Export:**
- All vegetation sheets + Environment + Soil + Metadata + Instructions

**Metadata Sheet:**
- Project ID, Title, Lead, Organization
- Purpose, Status, Start/End dates

**Instructions Sheet:**
- Always included
- Overview of workbook structure
- Data dictionary and codes
- Usage notes

## Testing

Run automated tests:
```r
testthat::test_file("tests/testthat/test-logic_excel_export.R")
```

Test coverage:
- ✅ Workbook structure validation
- ✅ Data integrity (all rows exported)
- ✅ Styling applied correctly
- ✅ Valid Excel format
- ✅ Project filtering
- ✅ Species lumping integration
- ✅ Empty data handling
- ✅ Performance (large datasets)

## Performance Notes

- Small datasets (<100 rows): <1 second
- Medium datasets (100-1000 rows): 1-3 seconds
- Large datasets (1000+ rows): 3-5 seconds
- Combined exports add ~1-2 seconds per sheet

Conditional formatting adds minimal overhead (<0.5 seconds).

## Troubleshooting

### "openxlsx package is required" error
```r
install.packages("openxlsx")
```

### Empty export / No data warning
- Check project filter (may be excluding all data)
- Verify layer selection (at least one layer must be selected)
- Check database has data: `SELECT COUNT(*) FROM vw_USysAllVeg`

### Styling not appearing
- Ensure `conditional_formatting = TRUE` in options
- Some Excel viewers (e.g., web-based) may not show all formatting
- Open in desktop Excel/LibreOffice for full styling

### Large file size
- Excel files with formatting are larger than CSV
- Typical file sizes:
  - 100 rows: ~20-30 KB
  - 1000 rows: ~100-200 KB
  - 10000 rows: ~1-2 MB
- Disable conditional formatting to reduce size slightly

### Performance issues
- Disable conditional formatting for very large exports (>5000 rows)
- Consider exporting by project or layer subset
- CSV export is faster for data-only needs

## Comparison: Excel vs CSV

| Feature | Excel (.xlsx) | CSV (.csv) |
|---------|--------------|------------|
| Formatting | ✅ Yes | ❌ No |
| Multiple sheets | ✅ Yes | ❌ No |
| Conditional colors | ✅ Yes | ❌ No |
| Column widths | ✅ Auto-set | ❌ No |
| File size | Moderate | Small |
| Export time | 2-5 sec | <1 sec |
| User experience | Excellent | Basic |
| R analysis | Good | Excellent |

**Recommendation:**
- Excel for **human review and reporting**
- CSV for **R analysis and large datasets**

## Future Enhancements

Potential additions:
- [ ] Excel template cloning (pre-populate from template)
- [ ] Data validation dropdowns in cells
- [ ] Formulas for totals/summaries
- [ ] Print layout settings (page breaks, headers/footers)
- [ ] Chart/graph embedding
- [ ] Pivot table preparation
- [ ] Export history tracking

## Support

For issues or questions:
1. Check this README
2. Review test cases in `tests/testthat/test-logic_excel_export.R`
3. Examine source code in `R/logic_excel_export.R`
4. Contact project maintainer

## Related Files

- `R/logic_excel_export.R` - Core export logic
- `R/mod_export.R` - Shiny UI/server integration
- `tests/testthat/test-logic_excel_export.R` - Test suite
- `scripts/create_excel_template.R` - Template generator
- `inst/excel_template.xlsx` - Reference template (generated)
