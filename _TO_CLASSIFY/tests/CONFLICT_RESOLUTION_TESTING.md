# Conflict Resolution UI Testing Documentation

## Overview

This document describes the comprehensive test suite for the **local DuckDB ↔ cloud PostgreSQL sync conflict resolution workflow**. These tests verify that users can detect, review, and resolve data conflicts that occur when the same records are modified both locally and in the cloud between sync operations.

## Architecture Context

### Conflict Scenarios

Conflicts occur in the following situations:

1. **Same Field Modified**: User edits `Elevation` locally to `1250`, while another user edits it to `1255` in the cloud
2. **Different Fields Modified**: User edits `Latitude` locally, another user edits `Longitude` remotely (auto-mergeable)
3. **Multi-Field Conflicts**: Multiple fields in the same record changed in both locations
4. **Delete Conflicts**: Record deleted locally but edited remotely (or vice versa)
5. **UUID Collisions**: Rare case where two users create plots with identical `PlotNumber` (different internal IDs)

### Conflict Resolution Options

- **Keep Local**: Apply local changes to cloud, discarding cloud changes
- **Keep Cloud**: Apply cloud changes to local, discarding local changes  
- **Dismiss**: Remove conflict from list without making changes (manual resolution required)
- **Auto-Merge**: When different fields are modified, changes can be merged automatically

### Data Flow

```
┌─────────────────┐           ┌──────────────────┐
│  Local DuckDB   │           │ Cloud PostgreSQL │
│  Sample_Env     │  sync_    │  core.sample_env │
│  row_version: 5 │◄─ pull ──►│  row_version: 6  │
└─────────────────┘           └──────────────────┘
         │                              │
         └──── Conflict Detected ───────┘
                      ▼
         ┌────────────────────────┐
         │   sync_conflicts       │
         │  - plot_number         │
         │  - table_name          │
         │  - details (JSON)      │
         │  - detected_utc        │
         └────────────────────────┘
                      ▼
         ┌────────────────────────┐
         │  Conflict Resolution   │
         │  UI (mod_merge.R or    │
         │  dedicated module)     │
         └────────────────────────┘
```

## Test File: `test-conflicts.R`

### Test Categories

#### 1. **Setup & Infrastructure Tests** ✅ (Currently Passing)

These tests verify the sync infrastructure is correctly set up:

- `sync_state` table creation
- `sync_conflicts` table creation with correct schema
- Helper functions for creating test conflicts
- Conflict counting and retrieval functions

**Status**: Implemented and passing (non-UI tests)

#### 2. **Conflict Detection Tests** ✅ (Currently Passing)

Tests for programmatic conflict detection:

- Single conflict creation
- Multiple conflict scenarios (5 different types)
- Conflict counting by project
- Conflict filtering by table name

**Status**: Implemented and passing (non-UI tests)

#### 3. **Conflict Resolution UI Tests** ⏸️ (Skipped - Pending Implementation)

Tests for the user-facing conflict resolution interface:

- **Visibility**: Conflict count badge, resolution button enabled state
- **Diff Viewer**: Side-by-side display of local vs cloud values
- **Single Resolution**: Keep Local, Keep Cloud, Dismiss actions
- **Batch Resolution**: Accept All Local, Accept All Cloud
- **Selective Resolution**: Checkbox selection + batch action

**Status**: Written but skipped until UI module is complete

#### 4. **Edge Case Tests** ⏸️ (Skipped - Pending Implementation)

Tests for complex conflict scenarios:

- **Delete Conflicts**: Special UI for locally deleted + remotely edited records
- **UUID Collisions**: Plot number conflicts between independent users
- **Sync Cancellation**: Preserve local data when user cancels mid-resolution
- **Re-sync After Partial**: Unresolved conflicts persist across sync operations

**Status**: Written but skipped pending feature implementation

#### 5. **Integration Tests** ⏸️ (Skipped - Requires Cloud Mock)

Tests for sync engine integration:

- Conflict detection during `sync_pull()` operations
- Auto-merge for non-conflicting field changes
- UI state when no conflicts exist

**Status**: Requires PostgreSQL mock infrastructure

#### 6. **Performance & Usability Tests** ⏸️ (Skipped - Pending Implementation)

Tests for UI performance with large datasets:

- Pagination for 50+ conflicts
- Resolution speed benchmarks (< 10 seconds for batch operations)

**Status**: Written as performance benchmarks

## Running the Tests

### Run All Conflict Tests

```bash
Rscript -e "testthat::test_file('tests/shinytest2/test-conflicts.R')"
```

### Run Only Non-Skipped Tests (Infrastructure)

```bash
Rscript -e "
  testthat::test_file(
    'tests/shinytest2/test-conflicts.R',
    reporter = 'progress'
  )
"
```

### Enable UI Tests (When Implemented)

Remove `skip()` calls from individual tests or use:

```r
# In test file, comment out skip() lines
# test_that("conflict resolution UI appears when conflicts exist", {
#   skip("Conflict resolution UI not yet implemented")  # ← Remove this
```

### Visual Regression Testing

For UI tests, shinytest2 can capture screenshots:

```r
app$get_screenshot("conflict-resolution-ui")
```

Compare screenshots across test runs to detect visual regressions.

## Test Data Setup

### Helper Functions

The test suite provides helper functions for creating conflict scenarios:

#### `setup_sync_environment()`
Creates `sync_state` and `sync_conflicts` tables, adds `row_version` column if missing.

#### `create_test_conflict(plot_number, field_name, local_value, cloud_value)`
Inserts a single conflict into `sync_conflicts` table with JSON details.

#### `create_conflict_scenario(n_conflicts = 5)`
Creates 5 diverse conflict types:
1. Auto-mergeable (same value)
2. Same field conflict (text)
3. Numeric field conflict
4. Vegetation cover conflict
5. Multi-field conflict

#### `count_conflicts(project_id = NULL)`
Returns conflict count, optionally filtered by project.

#### `verify_conflict_resolved(conflict_id)`
Checks if conflict was deleted from database (resolution successful).

#### `create_plot_for_conflict_test(plot_number)`
Creates test plot records in `Sample_SU` and `Sample_Env`.

### Teardown

All tests use `cleanup_sync_environment()` to delete test conflicts:

```r
on.exit(cleanup_sync_environment(), add = TRUE)
```

## Expected UI Behavior (Design Specification)

### Conflict Count Badge

Admin panel should display a badge showing unresolved conflict count:

```
┌─────────────────────────┐
│ Admin Panel             │
│ ┌─────────────────────┐ │
│ │ Conflicts:     [3]  │◄── Red badge when > 0
│ │ [Resolve Conflicts] │◄── Enabled when conflicts exist
│ └─────────────────────┘ │
└─────────────────────────┘
```

### Conflict List View

Table showing all conflicts with key details:

| Plot Number | Table      | Field(s)   | Detected   | Actions |
|-------------|------------|------------|------------|---------|
| CONF-001    | Sample_Env | Elevation  | 2026-02-11 | [View]  |
| CONF-002    | Sample_Veg | Cover      | 2026-02-11 | [View]  |
| CONF-003    | Sample_Env | Lat, Long  | 2026-02-11 | [View]  |

### Diff Viewer

Side-by-side comparison when a conflict is selected:

```
┌────────────────────────────────────────────────────────┐
│ Conflict: Plot CONF-001 - Elevation                   │
├─────────────────────────┬──────────────────────────────┤
│ Local Value             │ Cloud Value                  │
│ 1250 m                  │ 1255 m                       │
│                         │                              │
│ Modified: 2026-02-10    │ Modified: 2026-02-11        │
│ By: field_user_1        │ By: field_user_2            │
└─────────────────────────┴──────────────────────────────┘
│ [Keep Local] [Keep Cloud] [Dismiss]                   │
└────────────────────────────────────────────────────────┘
```

### Batch Actions

When multiple conflicts are selected:

```
☑ CONF-001 - Elevation
☑ CONF-002 - Cover
☐ CONF-003 - Lat/Long

[Accept All Local] [Accept All Cloud] [Dismiss Selected]
```

## CI/CD Integration

### GitHub Actions Workflow

Add to `.github/workflows/test-conflicts.yml`:

```yaml
name: Conflict Resolution Tests

on:
  push:
    paths:
      - 'R/logic_sync.R'
      - 'R/mod_merge.R'
      - 'tests/shinytest2/test-conflicts.R'
  pull_request:

jobs:
  test-conflicts:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - uses: r-lib/actions/setup-r@v2
        with:
          r-version: '4.3'
      
      - name: Install dependencies
        run: |
          Rscript -e "renv::restore()"
      
      - name: Build test database
        run: Rscript scripts/01_build_database.R
      
      - name: Run conflict tests
        run: |
          Rscript -e "testthat::test_file(
            'tests/shinytest2/test-conflicts.R',
            reporter = 'junit',
            stop_on_failure = FALSE
          )"
      
      - name: Publish test results
        uses: EnricoMi/publish-unit-test-result-action@v2
        if: always()
        with:
          files: test-results/*.xml
```

### Local Pre-commit Hook

Add to `.git/hooks/pre-commit`:

```bash
#!/bin/bash
# Run conflict tests before allowing commit to sync-related code

if git diff --cached --name-only | grep -E '(logic_sync|mod_merge)\.R$'; then
  echo "🧪 Running conflict resolution tests..."
  Rscript -e "testthat::test_file('tests/shinytest2/test-conflicts.R')"
  
  if [ $? -ne 0 ]; then
    echo "❌ Tests failed. Fix issues before committing."
    exit 1
  fi
fi
```

## Future Enhancements

### 1. Cloud Mock Infrastructure

Currently, tests requiring actual PostgreSQL interaction are skipped. Future work:

- Build in-memory PostgreSQL mock using DuckDB ATTACH to a second local database
- Simulate cloud state changes for integration tests
- Enable `sync_pull()` / `sync_push()` roundtrip testing

### 2. Visual Regression Testing

- Capture baseline screenshots of conflict UI states
- Compare across test runs to detect layout/styling regressions
- Integrate with Percy or Chromatic for visual diff review

### 3. Property-Based Testing

Use `quickcheck` or similar to generate random conflict scenarios:

```r
test_that("conflict resolution is idempotent", {
  # Generate random local/cloud value pairs
  # Verify resolution produces consistent results regardless of order
})
```

### 4. Load Testing

Simulate large-scale conflict scenarios:

- 1000+ conflicts across multiple projects
- Verify UI remains responsive
- Test pagination performance
- Benchmark batch resolution speed

## Related Documentation

- [Sync Architecture Plan](../../.github/prompts/plan-becMasterCloudSync.prompt.md) - Overall cloud sync design
- [Compliance Testing](./COMPLIANCE_TESTING.md) - Data validation before sync
- [E2E Tests](./test-e2e-workflows.R) - Full user workflow tests
- [logic_sync.R](../../R/logic_sync.R) - Sync engine implementation
- [mod_merge.R](../../R/mod_merge.R) - Merge request review UI (foundation for conflict resolution)

## Troubleshooting

### Test Failures: "sync_conflicts table does not exist"

**Solution**: Run `setup_sync_environment()` in test setup:

```r
test_that("...", {
  setup_sync_environment()
  on.exit(cleanup_sync_environment(), add = TRUE)
  # ... test code
})
```

### Test Failures: "Conflict not found after creation"

**Cause**: Database connection not properly closed/reopened.

**Solution**: Always use `on.exit(dbDisconnect(con))` pattern.

### Skipped Tests Not Running

**Expected**: Most UI tests are intentionally skipped until conflict resolution UI is implemented.

**To enable**: Remove `skip("reason")` lines from test bodies.

### Performance Tests Timing Out

**Solution**: Increase timeout in `AppDriver$new(timeout = 30000)` or skip on CI:

```r
test_that("...", {
  skip_on_ci()  # Skip performance benchmarks in CI
  # ... test code
})
```

---

**Maintainer**: Tester Agent  
**Last Updated**: 2026-02-11  
**Status**: Infrastructure tests passing, UI tests pending implementation
