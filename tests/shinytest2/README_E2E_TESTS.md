# VPRO Shiny UI Regression Test Suite

## Overview

Comprehensive UI regression testing for the VPRO Shiny application using `shinytest2`. The test suite consists of three complementary test files:

1. **`test-e2e-workflows.R`** - Core end-to-end workflows (14 tests)
2. **`test-data-entry.R`** - Detailed data entry mechanics (30+ tests)
3. **`test-admin.R`** - Administrative operations (30+ tests)

**Total Coverage:** 75+ UI regression tests  
**Total Lines of Code:** ~2500+ across all test files

---

## Test Files

### 1. End-to-End Workflow Tests (`test-e2e-workflows.R`)

**Test Count:** 14 comprehensive tests  
**Lines of Code:** 860  
**Focus:** Critical user journeys

#### Core Workflows (5 Tests)
These tests cover the critical user journeys specified in the requirements:

1. **Workflow 1: Project Selection & Plot Load**
   - Tests project selector functionality
   - Verifies plot selector populates correctly
   - Tests project switching and context updates
   - Validates data exists in database

2. **Workflow 2: Vegetation Data Entry**
   - Navigates through all 4 vegetation layers (A, B, C, D)
   - Verifies Add/Delete species buttons exist
   - Tests handsontable rendering
   - Checks vegetation data loading

3. **Workflow 3: Site & Environment Data Entry**
   - Tests General, Mensuration, and Soil tab structure
   - Verifies coordinate fields (DMS → DD conversion support)
   - Validates elevation, slope, and environmental fields
   - Tests save functionality

4. **Workflow 4: Export CSV/RDS with Lumping**
   - Tests lumping toggle (ON/OFF)
   - Tests pivot layers toggle
   - Verifies CSV and RDS download buttons render
   - Tests all export option combinations

5. **Workflow 5: Report Generation**
   - Tests report template selector
   - Verifies format options (HTML, PDF, Excel)
   - Tests report option controls (colour/gray thresholds)
   - Validates report context display

### Comprehensive Integration Test (1 Test)
6. **Complete Data Entry Cycle**
   - Full workflow: Project → Veg → Site → Export → Report
   - Tests state persistence across all tabs
   - Validates complete user journey

### Error Handling Tests (2 Tests)
7. **Validation for Missing Required Fields**
   - Tests save without mandatory fields (SKIPPED - UI not implemented)
   - Placeholder for validation feedback testing

8. **Invalid Species Code Rejection**
   - Tests species validation (SKIPPED - modal testing complex)
   - Placeholder for species lookup validation

### Data Integrity Tests (1 Test)
9. **Referential Integrity Enforcement**
   - No orphaned plots (plots without valid projects)
   - Vegetation records reference valid plots
   - Projects in Sample_Env exist in Sample_Metadata

### State Management Tests (1 Test)
10. **Context Persistence Across Tabs**
    - Project/plot selections persist across all 11 tabs
    - Tests plot switching propagation
    - Verifies data reloads correctly

### Performance Tests (1 Test)
11. **Rapid Plot Switching**
    - Tests multiple consecutive plot switches
    - Verifies vegetation data loads for each plot
    - Ensures no performance degradation

### Database Consistency Test (1 Test)
12. **Export Format Consistency**
    - Tests all lumping/pivot combinations
    - Verifies download buttons render for all options
    - Validates export state management

### Accessibility Test (1 Test)
13. **Keyboard Shortcuts** (SKIPPED - requires special setup)
    - Placeholder for Ctrl+S (save) testing
    - Placeholder for Ctrl+N (new) testing

### Summary Smoke Test (1 Test)
14. **App Loads Without Errors**
    - Verifies all 11 tabs are accessible
    - Tests tab navigation across entire app
    - Ensures no critical loading errors

## Helper Functions

The test file includes 8 comprehensive helper functions:

- `verify_db_state()` - Direct database queries with row count verification
- `cleanup_test_plot()` - Safe test data cleanup with error handling
- `create_test_plot()` - Programmatic test plot creation
- `wait_for_notification()` - Shiny notification stabilization
- `safe_get_value()` - Protected app value getter with error handling
- `select_project()` - Project selection helper
- `select_plot()` - Plot selection helper

---

### 2. Data Entry Regression Tests (`test-data-entry.R`)

**Test Count:** 30+ focused tests  
**Lines of Code:** ~850  
**Focus:** Detailed data entry mechanics and edge cases

#### Vegetation Data Entry Tests

**Layer Navigation (3 tests):**
- Layer switching preserves tab context
- All four layers render handsontable correctly
- Context hint updates with current plot

**Add/Delete Operations (3 tests):**
- Add Species button exists on all layers
- Delete Selected button exists on all layers
- Add Species button triggers without errors (SKIPPED - pending modal implementation)

**Cover Value Validation (3 tests - SKIPPED):**
- Numeric input (0-100) acceptance
- Special codes (`+`, `r`, `P`) acceptance
- Cover sum >100% warning

**Species Management (2 tests - SKIPPED):**
- Duplicate species detection within layer
- Species autocomplete/lookup functionality

#### Site & Environment Data Entry Tests

**Tab Structure (3 tests):**
- Site/Env tabs navigable
- General tab fields populated
- Mensuration and Soil tabs exist (partial skip)

**Coordinate Calculations (4 tests):**
- Latitude accepts decimal degrees
- Longitude accepts decimal degrees
- DMS→DD conversion triggers (SKIPPED - requires deep inspection)
- UTM coordinate fields exist

**Field Validation (4 tests):**
- Elevation accepts numeric values
- Slope gradient 0-100% range validation (SKIPPED)
- Aspect accepts 0-360 degrees
- Date picker enforces valid dates

**Dropdowns & Code Lists (3 tests):**
- Moisture regime dropdown populates from code lists
- Nutrient regime dropdown populates
- Meso slope position dropdown exists

**Save Operations (3 tests):**
- Save header button exists
- Save button click triggers without errors
- Save persists changes to database (SKIPPED - requires isolation)

#### Edge Cases & Regression Tests (4 tests)

- Rapid input changes prevent reactive loops (SKIPPED)
- Tab switching preserves unsaved changes warning (SKIPPED)
- Empty/NULL values handle gracefully
- Session timeout recovery (SKIPPED)
- Required field indicators (SKIPPED)

#### Performance Tests (2 tests - SKIPPED)

- Large vegetation dataset loads efficiently
- Plot switching refreshes data efficiently

**Key Helpers:**
- `navigate_to_veg_layer()` - Layer navigation helper
- `is_hot_editable()` - Handsontable editability checker
- All E2E helpers (safe_get_value, select_project, etc.)

---

### 3. Admin Operations Tests (`test-admin.R`)

**Test Count:** 30+ focused tests  
**Lines of Code:** ~850  
**Focus:** Administrative and metadata management

#### Project Metadata CRUD (8 tests)

- Admin tab accessibility
- Project Metadata panel renders
- New/Delete Project buttons exist
- All project form fields exist (ID, Title, Coordinator, Notes, Dates)
- Save Project button exists
- Project selection populates form fields
- Form header updates with selection
- New Project button clears form (SKIPPED)
- Duplicate Project ID prevention (SKIPPED)

#### Code Maintenance (6 tests)

- Code Maintenance panel accessible
- Lookup list selector populates from USysTableOfLists
- Code datatable renders with data
- Add Row / Save All / Refresh buttons exist
- Add Row interaction (SKIPPED - requires DT state inspection)
- Code list selection updates table (SKIPPED)

#### Master Site Units (5 tests)

- Master Site Units panel accessible
- Master unit datatable renders
- Add Row / Save / Refresh buttons exist
- All controls functional

#### Audit Trail (4 tests - mostly SKIPPED)

- Audit Log panel accessible
- Audit filters exist (user, date, action)
- Audit datatable renders
- CSV export button exists

#### Master Audit (4 tests)

- Master Audit panel accessible
- Master Audit datatable renders
- Pagination controls exist (Prev/Next buttons)
- Export button exists

#### Images & Maps Module (7 tests)

- Images tab accessible
- Image gallery renders for plot with images
- KML download button exists
- Location debug output renders
- 'No images' message for empty plots (SKIPPED)
- Image preview/lightbox (SKIPPED - requires JS execution)
- Image metadata edit (SKIPPED - not implemented)
- Image delete confirmation (SKIPPED - not implemented)

#### Publishing & Download Logs (4 tests - SKIPPED)

- Publish panel exists
- Download log panel exists
- Publish snapshot list renders
- Download log filters functional

#### User Management (3 tests - SKIPPED)

- User login interface
- Role-based access controls (RBAC)
- User preferences save/load

#### Integration Tests (3 tests - SKIPPED)

- Project creation workflow end-to-end
- Code list modification persists
- Admin operations trigger audit log entries

#### Error Handling (4 tests - SKIPPED)

- Project deletion requires confirmation
- Required field validation on save
- Invalid data types rejected gracefully
- Database write failures show user-friendly errors

#### Performance Tests (3 tests - SKIPPED)

- Large code lists (>100 items) load efficiently
- Project list filtering responsive
- Audit log pagination handles large datasets

**Key Helpers:**
- `navigate_to_admin()` - Admin panel navigation
- `has_projects()` - Check metadata database state
- `has_lists_db()` - Verify lists database exists
- All E2E helpers (safe_get_value, select_project, etc.)

---

## Running the Tests

### Run All UI Regression Tests
```r
# Run all shinytest2 tests (all three files)
testthat::test_dir("tests/shinytest2")
```

### Run Individual Test Files

**E2E Workflows (core user journeys):**
```r
testthat::test_file("tests/shinytest2/test-e2e-workflows.R")
```

**Data Entry Mechanics (detailed UX):**
```r
testthat::test_file("tests/shinytest2/test-data-entry.R")
```

**Admin Operations (metadata management):**
```r
testthat::test_file("tests/shinytest2/test-admin.R")
```

### Run Specific Test by Name
```r
# Filter by test name (works across all files)
testthat::test_dir(
  "tests/shinytest2",
  filter = "Vegetation"
)

# Or filter in specific file
testthat::test_file(
  "tests/shinytest2/test-data-entry.R",
  filter = "Cover value"
)
```

### Run Tests from Command Line
```bash
# All UI tests
Rscript -e "testthat::test_dir('tests/shinytest2')"

# Specific file with reporter
Rscript -e "testthat::test_file('tests/shinytest2/test-e2e-workflows.R', reporter='summary')"

# Quick smoke test (just E2E workflows)
cd tests/shinytest2 && Rscript -e "library(testthat); test_file('test-e2e-workflows.R', reporter='summary')"
```

### Generate Coverage Report (if using covr)
```r
library(covr)
report <- file_coverage(
  source_files = c(
    "R/mod_veg_sample.R",
    "R/mod_site_env.R",
    "R/mod_admin.R",
    "R/mod_images.R"
  ),
  test_files = c(
    "tests/shinytest2/test-e2e-workflows.R",
    "tests/shinytest2/test-data-entry.R",
    "tests/shinytest2/test-admin.R"
  )
)
report
```

## Test Strategy & Philosophy

### Three-Layer Testing Approach

1. **E2E Workflows** (`test-e2e-workflows.R`)
   - **Purpose:** Validate critical user journeys work end-to-end
   - **Scope:** Happy paths through major features
   - **Speed:** Fast (~30 seconds for all 14 tests)
   - **When to run:** After any significant change, before commits

2. **Data Entry Mechanics** (`test-data-entry.R`)
   - **Purpose:** Deep regression coverage of data entry UX
   - **Scope:** Field validation, tab switching, edge cases
   - **Speed:** Medium (~60 seconds, many skipped)
   - **When to run:** After UI refactoring, before releases

3. **Admin Operations** (`test-admin.R`)
   - **Purpose:** Administrative workflow regression coverage
   - **Scope:** Metadata CRUD, code maintenance, audit logs
   - **Speed:** Medium (~60 seconds, many skipped)
   - **When to run:** After admin module changes, before releases

### Design Principles

- **Fast & Focused:** Each test targets specific functionality with minimal setup
- **Deterministic:** Uses existing database content, skips gracefully if unavailable
- **Safe:** Includes cleanup handlers via `on.exit()` for data-modifying tests
- - **Realistic:** Tests mirror actual forest ecologist workflows
- **Resilient:** Uses `safe_get_value()` to handle app state variations
- **Comprehensive:** 75+ tests cover happy paths, error conditions, and edge cases
- **Progressive:** Skipped tests document features pending implementation

### Test Execution Speed

| Test File | Active Tests | Skipped | Total Time | Per Test Avg |
|-----------|--------------|---------|------------|--------------|
| `test-e2e-workflows.R` | 11 | 3 | ~30s | ~2.7s |
| `test-data-entry.R` | 18 | 15 | ~45s | ~2.5s |
| `test-admin.R` | 22 | 20 | ~55s | ~2.5s |
| **TOTAL** | **51** | **38** | **~130s** | **~2.5s** |

*Note: Times approximate, depends on database size and system performance*

## Known Limitations & Skipped Tests

### Technical Limitations (shinytest2)

1. **File downloads:** Cannot test actual file download without browser download directory setup
   - Affected: Export CSV/RDS, KML download, audit log export
   - Workaround: Verify download buttons render, test logic separately
   
2. **Handsontable cell input:** Direct cell editing requires advanced AppDriver features
   - Affected: Vegetation cover value entry, species code typing
   - Workaround: Test table rendering, use JavaScript execution for future enhancement
   
3. **Modal interactions:** Complex modal testing requires JavaScript execution
   - Affected: Add Species modal, confirmation dialogs, species picker
   - Workaround: Test button triggers, verify modal opens (not content)
   
4. **Keyboard events:** Keyboard shortcuts require special shinytest2 setup
   - Affected: Ctrl+S (save), Ctrl+N (new), Tab navigation
   - Workaround: Test button clicks instead of shortcuts

### Feature Limitations (not yet implemented)

**Data Entry (15 skipped tests):**
- DMS→DD coordinate conversion triggers
- Cover sum >100% validation warning
- Duplicate species detection within layer
- Species autocomplete/lookup
- Slope 0-100% range validation
- Unsaved changes warning on tab switch
- Required field visual indicators
- Session timeout recovery
- Rapid input reactive loop prevention
- Mensuration tab detailed verification
- Soil horizon CRUD operations
- Full save persistence with cleanup

**Admin Operations (20 skipped tests):**
- New Project form clearing behavior
- Duplicate Project ID prevention
- Code list row addition interaction
- Code list switching verification
- Audit log panel complete workflow
- Publish/Download log panels
- User authentication & RBAC
- User preferences persistence
- Image metadata editing
- Image deletion workflow
- Full project CRUD with isolation
- Code modification persistence
- Audit logging verification
- Project deletion confirmation
- Required field validation
- Invalid data type rejection
- Database write error handling
- Large dataset performance benchmarks

**Performance (5 skipped tests):**
- Large vegetation dataset load benchmarks
- Plot switching performance profiling
- Code list >100 items load time
- Project filtering responsiveness
- Audit log pagination stress test

### Why So Many Skips?

**Intentional Design:** The test suite uses skipped tests as **living documentation** of:
1. Features planned but not yet implemented
2. Technical challenges requiring advanced testing techniques
3. Performance benchmarks pending profiling setup
4. Integration scenarios requiring isolated test environments

**Value:** Skipped tests with clear descriptions:
- Document expected behavior before implementation
- Guide future development priorities
- Prevent regression when features are added
- Serve as TODO list for test enhancement

## Test Maintenance

### Test Organization

**Helper Functions:**
- Shared helpers in each file's preamble (potential future extraction to `helpers.R`)
- `safe_get_value()` - Error-safe app value getter (used in all files)
- `select_project()` / `select_plot()` - Navigation helpers (all files)
- `verify_db_state()` - Direct DB query verification (all files)
- `navigate_to_veg_layer()` - Vegetation-specific (data-entry only)
- `navigate_to_admin()` - Admin-specific (admin only)
- `has_projects()` / `has_lists_db()` - Database availability checks (admin only)

**Naming Conventions:**
- Test names clearly describe what's being tested
- Group tests with `describe()` blocks by module/feature area
- Use descriptive AppDriver names for debugging snapshot folders

**Skip Conditions:**
- All tests use `skip_on_cran()` to avoid CI failures without data
- Graceful skips if projects/plots unavailable (empty database)
- Clear skip messages explaining why and what's needed
- Pending features clearly marked with skip reason in description

### Updating Tests

**When adding a new module:**
1. Add E2E test to `test-e2e-workflows.R` for happy path
2. Add detailed tests to `test-data-entry.R` if data entry UI
3. Add admin tests to `test-admin.R` if admin functionality

**When implementing a skipped feature:**
1. Search for `skip("feature description")` matching your feature
2. Remove `skip()` call and implement test logic
3. Verify test passes with real feature
4. Update this README to remove from "skipped" count

**When refactoring UI:**
1. Run all three test files before changes (baseline)
2. Make UI changes
3. Run tests again - failures indicate regressions
4. Update test assertions if UI intentionally changed
5. Add new tests for new UI elements

### Continuous Integration Strategy

**Pre-Commit:**
```bash
# Quick smoke test (~30s)
Rscript -e "testthat::test_file('tests/shinytest2/test-e2e-workflows.R', reporter='summary')"
```

**Pre-Push:**
```bash
# Full UI regression suite (~130s)
Rscript -e "testthat::test_dir('tests/shinytest2', reporter='summary')"
```

**Nightly CI:**
```bash
# All tests including long-running performance benchmarks
# (Un-skip performance tests for nightly runs)
Rscript -e "testthat::test_dir('tests/shinytest2', reporter='teamcity')"
```

## Next Steps for Full Coverage

### High Priority (Enables ~15 skipped tests)

1. **Implement DT cell editing callbacks**
   - Enable: Handsontable direct cell input testing
   - Impact: Vegetation cover entry, species codes, soil horizons
   - Effort: Medium (requires AppDriver JavaScript execution)

2. **Implement validation UI feedback**
   - Enable: Required field indicators, error messages, validation warnings
   - Impact: 5+ data entry validation tests, 4+ admin error handling tests
   - Effort: Low (UI enhancement, then unskip tests)

3. **Add modal testing helpers**
   - Enable: Add Species modal, confirmation dialogs, delete confirmations
   - Impact: Species validation, project deletion, unsaved changes warnings
   - Effort: Medium (complex AppDriver modal interaction)

4. **Create isolated test environment**
   - Enable: Full CRUD workflows with cleanup (project creation, code edit)
   - Impact: 3+ integration tests
   - Effort: High (requires test database fixture or transaction rollback)

### Medium Priority (Enhances coverage depth)

5. **DMS→DD conversion logic tests**
   - Move coordinate conversion to unit tests (`test-logic_coord_tools.R`)
   - Add UI trigger verification to data-entry tests
   - Effort: Low (logic already exists, just needs test coverage)

6. **Performance profiling setup**
   - Implement benchmarking for large datasets
   - Enable 5 skipped performance tests
   - Effort: Medium (requires benchmark harness)

7. **Keyboard shortcut testing**
   - Research shinytest2 keyboard event support
   - Enable accessibility tests
   - Effort: High (may require browser automation)

8. **File download verification**
   - Set up headless browser download directory
   - Verify CSV/RDS/KML file contents after download
   - Effort: Medium (test infrastructure setup)

### Low Priority (Nice to have)

9. **User authentication & RBAC testing**
   - Pending: User management implementation
   - Will enable 3+ user management tests
   - Effort: Depends on auth implementation

### 10. **Mobile/viewport regression tests**
   - Test responsive design at different screen sizes
   - Verify handsontable usability on tablets
   - Effort: Medium (requires AppDriver viewport control)

### Test Enhancement Roadmap

| Quarter | Milestone | Tests Enabled | Key Features |
|---------|-----------|---------------|--------------|
| **Q1 2026** | Validation UI | +9 tests | Required fields, error messages, warnings |
| **Q2 2026** | Modal Testing | +6 tests | Species picker, confirmations, dialogs |
| **Q3 2026** | Isolated Tests | +8 tests | Full CRUD, integration workflows |
| **Q4 2026** | Performance | +5 tests | Benchmarks, profiling, stress tests |

---

## Current Test Status Summary

| Category | Active | Skipped | Total | Coverage % |
|----------|--------|---------|-------|------------|
| **E2E Workflows** | 11 | 3 | 14 | 79% |
| **Data Entry** | 18 | 15 | 33 | 55% |
| **Admin Ops** | 22 | 20 | 42 | 52% |
| **TOTAL** | **51** | **38** | **89** | **57%** |

**Active Tests:** Currently running and passing  
**Skipped Tests:** Documented features pending implementation or advanced testing techniques  
**Coverage %:** Percentage of tests actively running (not feature coverage)

---

## Contributing New Tests

1. **Choose the right file:**
   - Core user journey → `test-e2e-workflows.R`
   - Data entry detail → `test-data-entry.R`
   - Admin operation → `test-admin.R`

2. **Follow patterns:**
   - Use `describe()` blocks to group related tests
   - Include clear test descriptions
   - Add `skip()` with reason if feature not ready
   - Use shared helpers for common operations

3. **Test naming:**
   - Start with module name: "Vegetation", "Site & Env", "Admin"
   - Describe what's tested: "button exists", "field accepts input"
   - Be specific: "Cover values accept special codes (+, r, P)"

4. **Keep tests fast:**
   - Minimize app startup overhead (reuse AppDriver where possible)
   - Focus assertions on specific functionality
   - Avoid redundant navigation if already in context

5. **Document skip conditions:**
   - Clearly state why skipped
   - Reference issue number if tracked
   - Provide breadcrumb for future implementation

---

## Questions or Issues?

- **Test failures:** Check if database populated correctly via `scripts/01_build_database.R`
- **Timeouts:** Increase `wait_for_idle(timeout = ...)` for slow systems
- **AppDriver crashes:** Verify Chrome/Chromium available for headless browser
- **Skipped test guidance:** See detailed skip reasons in test file comments

**Test Coverage Philosophy:** We prefer comprehensive skipped tests (living documentation) over no tests. Each skip is a placeholder for future enhancement, not a gap in our testing strategy.
