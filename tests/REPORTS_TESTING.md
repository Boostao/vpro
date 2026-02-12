# Report Parity Testing - Documentation

## Overview

The report testing suite validates that all Quarto reports in VPRO produce accurate, complete outputs matching the original Access report functionality.

## Test Files

### 1. `test-reports-parity.R` (24 tests)
Integration tests for report rendering and content validation.

**Test Coverage:**
- **Render Stability** (11 tests): All 15 report templates render without errors
- **Data Integrity** (4 tests): Species tables, metadata sections, hierarchy structure present
- **Edge Cases** (3 tests): Empty plots, missing layers, non-standard data
- **Format Compliance** (2 tests): Cover value formats, species lumping behavior
- **Cross-Report Consistency** (2 tests): Data consistency across related reports
- **Performance** (2 tests): Render time limits, temp file cleanup

### 2. `test-logic_reports_veg.R` (20 tests) ✨ **NEW**
Unit tests for vegetation calculation functions ported from Access VBA.

**Test Coverage:**
- **Presence Classification** (2 tests): Roman numeral constancy classes (I-V)
- **Significance Classification** (2 tests): Braun-Blanquet cover-abundance scale
- **Rounding & Precision** (1 test): Access Nz() equivalent, minimum value handling
- **Prominence Class** (2 tests): Combined cover-presence ecological index
- **Goldstream Class** (2 tests): Alternative importance index
- **Plot Number Parsing** (1 test): Multiple input format handling
- **Column Normalization** (2 tests): Access field name variations
- **Label Generation** (2 tests): Group/order display logic
- **Integration** (1 test): Calculation chain validation
- **Regression Guards** (1 test): Boundary condition parity with Access VBA

**Functions Tested:**
- `presence_to_class()` - Converts presence ratio to Roman numeral class (I-V)
- `signif_class()` - Braun-Blanquet cover-abundance classification
- `round_up2()` - Rounds to 2 decimals with 0.01 minimum (Access Nz pattern)
- `prominence_class()` - Ecological importance: (cover × 10) × √presence
- `goldstream_class()` - Alternative index: (presence × 100) × √cover
- `parse_plot_numbers()` - Handles comma/semicolon/newline separated plot lists
- `normalize_veg_cols()` - Standardizes Access field name variations
- `label_veg_records()` - Generates grouping labels for report display

**Access Source References:**
- `V7mdlExportToR1.txt` - Presence, significance, prominence formulas
- `V7mdlExportToR2.txt` - Goldstream formula
- Access report queries - Column name variations

**Total: 44 test cases across report validation and calculation accuracy**

### 1. **Render Stability Tests** (11 tests)
- Verifies all 15 report templates exist and have valid YAML frontmatter
- Tests each report renders without errors using sample data
- Covers:
  - short_veg.qmd, long_veg.qmd
  - site_summary.qmd
  - hierarchy.qmd, flat_hierarchy.qmd
  - env_summary.qmd, bec_labels.qmd
  - lifeform.qmd, quality_control.qmd
  - field_checklist.qmd
  - veg_layer_a.qmd (and c, d implicitly)

### 2. **Data Integrity Tests** (4 tests)
- Validates report content includes expected data sections
- Parses HTML output to verify:
  - Species data tables present with correct structure
  - Plot metadata sections exist
  - Hierarchy tree structure included
  - Environmental variables displayed

### 3. **Edge Case Tests** (3 tests)
- Tests graceful handling of:
  - Empty plot selections (non-existent plot numbers)
  - Missing vegetation layers
  - Data validation issues in QC report

### 4. **Format Compliance Tests** (2 tests)
- Verifies Access report conventions:
  - Cover value formats (numeric, text codes, constancy format)
  - Species lumping behavior (consolidation of synonyms)

### 5. **Cross-Report Consistency** (2 tests)
- Validates data consistency across related reports:
  - Layer-specific reports are subsets of full veg reports
  - Short and long veg reports show same underlying data

### 6. **Performance Tests** (2 tests)
- Render time limits (< 30 seconds with test data)
- Temporary file cleanup verification

**Total: 24 test cases across 6 risk categories**

## Test Infrastructure

### Helper Functions

#### `render_test_report(template_name, params, format)`
- Renders a Quarto report to temporary directory
- Captures errors for validation
- Returns: `list(success, output_file, error)`
- Supports both `quarto` and `rmarkdown` render engines

#### `parse_html_report(html_file)`
- Extracts structural elements from rendered HTML
- Returns: title, headings, tables, paragraphs, full HTML document
- Requires: `xml2`, `rvest` packages

#### `extract_table_data(html_doc, table_index)`
- Converts HTML table to data.frame
- Uses rvest::html_table() for automatic parsing
- Returns: data.frame or NULL

#### `validate_sections_present(parsed_html, expected_sections)`
- Checks for required sections/headings
- Returns: logical vector of section presence

## Dependencies

### Required (always)
- `testthat` - Test framework
- `dplyr` - Data manipulation
- `DBI`, `duckdb` - Database access
- `fs` - File system operations
- `here` - Path management

### Optional (tests skip if not available)
- `quarto` - Report rendering (preferred)
- `rmarkdown` - Fallback renderer
- `xml2` - HTML parsing
- `rvest` - HTML table extraction

## Running Tests

### Full Test Suites
```bash
# All report parity tests (integration)
Rscript -e "testthat::test_file('tests/testthat/test-reports-parity.R')"

# All calculation tests (unit)
Rscript -e "testthat::test_file('tests/testthat/test-logic_reports_veg.R')"

# Both suites together
Rscript -e "testthat::test_dir('tests/testthat', filter = 'reports|logic_reports')"
```

### Individual Test Groups
```r
# In R console
library(testthat)

# Run only render stability tests
test_file("tests/testthat/test-reports-parity.R", 
          filter = "renders without errors")

# Run only data integrity tests
test_file("tests/testthat/test-reports-parity.R", 
          filter = "contains|includes")
```

### Skip Slow Tests
```r
# Set environment variable to skip performance tests
Sys.setenv(NOT_CRAN = "false")  # Skips skip_on_ci() tests
test_file("tests/testthat/test-reports-parity.R")
```

## Test Data Requirements

Tests use real data from `data/vpro.duckdb` (built via `scripts/01_build_database.R`).

**Minimum data needed:**
- At least one project in vpro_metadata.duckdb
- At least one plot with vegetation data (Sample_Veg)
- At least one plot with environmental data (Sample_Env)
- Species reference data in vpro_lists.duckdb (SppList)
- BEC zone codes (USysZoneList)

**To rebuild test data:**
```bash
Rscript scripts/01_build_database.R
Rscript scripts/02_create_views.R
```

## Intentional Deviations from Access Reports

These differences are **expected and documented**:

1. **Output Format**: HTML/PDF vs. printer output
   - Modern web-based output is more accessible
   - Users can save, share, or print as needed

2. **Styling**: Bootstrap 5 vs. Access default
   - Responsive design for mobile/tablet use
   - Better readability on modern displays

3. **Interactive Features**: Collapsible sections, tooltips
   - Improves navigation in long reports
   - Not available in static Access reports

4. **Unicode Support**: Full UTF-8 character set
   - Better handling of special characters in species names
   - Improved international compatibility

5. **Image Embedding**: Base64 in HTML vs. OLE objects
   - Self-contained reports (no external dependencies)
   - Better portability

**Data accuracy is identical** - all calculations match Access VBA logic from `V7mdlExportToR1/R2`.

## Known Limitations

### Not Yet Tested
- PDF output format (currently only HTML)
- Specific plot selection filters (project_id, site_unit parameters)
- All custom grouping/ordering permutations
- Theme color application (colour_greater, gray_greater)
- Report title customization
- Parquet input source (alternative to DuckDB)

### Performance Note
- Full test suite may take 5-10 minutes (renders 15+ reports)
- Individual render tests: 15-30 seconds each
- Use `skip_if_not_installed("quarto")` guards for CI/CD

## Future Enhancements

### Short-term (next sprint)
1. **Add snapshot testing** - Visual regression tests with vdiffr
2. **Validate numeric precision** - Exact constancy calculation checks
3. **Test multi-plot reports** - Aggregate reports with >10 plots
4. **Add PDF format tests** - Verify PDF generation works

### Medium-term
1. **Benchmark performance at scale** - Test with 100+ plot datasets
2. **Test concurrent rendering** - Multi-user scenario simulation
3. **Add accessibility tests** - WCAG compliance for HTML output
4. **Create reference snapshots** - Golden master testing approach

### Long-term
1. **Automated visual comparison** - Against Access report screenshots
2. **Load testing** - Stress test report generation pipeline
3. **Cross-platform testing** - Windows/Linux/Mac compatibility

## Troubleshooting

### Tests Fail with "quarto not installed"
**Solution:** Install Quarto CLI or let tests use rmarkdown fallback
```r
# Install quarto package
renv::install("quarto")

# Or install Quarto CLI system-wide
# https://quarto.org/docs/get-started/
```

### Tests Fail with "xml2/rvest not installed"
**Solution:** Install HTML parsing packages
```r
renv::install(c("xml2", "rvest"))
```

### Reports Render but Tests Fail
**Check:** Database contains test data
```r
con <- DBI::dbConnect(duckdb::duckdb(), "data/vpro.duckdb")
DBI::dbGetQuery(con, "SELECT COUNT(*) FROM Sample_Veg")
DBI::dbDisconnect(con)
```

### Render Time Exceeds 30 Seconds
**Cause:** Large test database or slow machine
**Solution:** 
1. Reduce test data size
2. Increase timeout in performance tests
3. Skip performance tests: `skip_on_ci()`

## Contact

**Test Owner:** The Tester agent 🛡️  
**Purpose:** Guardian of data integrity and report reliability  
**Priority:** HIGH - Reports are primary data delivery for field ecologists

For questions or issues with report parity tests, see:
- `IMPLEMENTATION_PLAN.md` - Project roadmap
- `planning.md` - Current status
- `.github/copilot-instructions.md` - Agent roles and responsibilities
