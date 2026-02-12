# VPro Mock PostgreSQL Testing Setup

This directory contains the complete testing infrastructure for developing and validating the BECMaster cloud database integration in VPro.

## Quick Start

### 1. Start the Mock PostgreSQL Database (Docker)

```bash
cd /Users/nicolas/Documents/GitHub/vpro
docker-compose up -d
```

This starts a PostgreSQL 15 container at `localhost:5433` with:
- **User**: `testuser`
- **Password**: `testpass`
- **Database**: `becmaster`
- **Schema**: Automatically initialized with BECMaster schema and seed data

Verify the database is ready:
```bash
docker-compose ps
docker logs vpro-postgres-test | grep "database system is ready"
```

### 2. Run Integration Tests

```bash
cd /Users/nicolas/Documents/GitHub/vpro
Rscript -e "testthat::test_dir('tests/testthat')"
```

Or from R/RStudio:
```r
setwd("/Users/nicolas/Documents/GitHub/vpro")
testthat::test_dir("tests/testthat")
```

### 2a. UI Regression Tests (shinytest2)

System dependency (Fedora):
```bash
sudo dnf install -y chromium
```

Scaffold and record:
```bash
Rscript -e "shinytest2::use_shinytest2()"
Rscript -e "shinytest2::record_test()"
```

Run all tests (unit + UI):
```bash
Rscript -e "testthat::test_dir('tests/testthat')"
```

Run only E2E workflow tests:
```bash
Rscript -e "testthat::test_file('tests/shinytest2/test-e2e-workflows.R')"
```

### 3. Stop the Database

```bash
docker-compose down
```

To also remove the persistent volume (reset database):
```bash
docker-compose down -v
```

---

## Architecture

### Components

**docker-compose.yml**
- PostgreSQL 15 Alpine container
- Mounts `scripts/00_schema_becmaster_test.sql` as initialization script
- Health check ensures database is ready before tests
- Persistent volume for data between container restarts

**scripts/00_schema_becmaster_test.sql**
- Creates 5 schemas: `core`, `lists`, `staging`, `admin`, `public_export`
- Defines 25+ tables matching the BECMaster data model
- Populates reference data (species, zones, users, roles)
- Sets up proper constraints and indexes

**config.yml**
- Environment-specific settings (development, test, production)
- PostgreSQL connection strings
- DuckDB local database paths
- Cloud attachment flags

**R/db_connections.R**
- `connect_local_db()` — Opens local DuckDB + attaches auxiliary DBs
- `attach_cloud_db()` — Attaches PostgreSQL via DuckDB's postgres extension
- `is_cloud_connected()` — Tests cloud connectivity
- `query_db()` — Wrapper for safe SQL execution
- Helper functions for manage attachments

**tests/testthat/setup.R**
- Initializes test environment before test suite runs
- Checks PostgreSQL availability
- Provides cleanup teardown

**tests/testthat/helpers.R**
- `test_connect_duckdb()` — Creates in-memory DuckDB for tests
- `initialize_test_schema()` — Sets up minimal schema
- `seed_test_reference_data()` — Populates lookup tables
- `insert_test_plot()` — Helper to create test plots
- `expect_query_result()` — Assertion helper for queries

**tests/testthat/test-db_connections.R**
- 20+ tests covering:
  - Local DuckDB connections
  - Schema initialization
**tests/shinytest2/test-e2e-workflows.R** 🆕
- Comprehensive end-to-end workflow tests for critical data paths:
  1. **Complete Data Entry Cycle**: Project → Plot → Veg → Site/Env → Save → DB Verification
  2. **Lumping Application**: Export with/without species lumping enabled
  3. **Import Workflow**: CSV upload → validation → save (skipped: not yet implemented)
  4. **Hierarchy Operations**: Create → Assign → Merge → Clip (skipped: 0% complete per roadmap)
  5. **Cloud Sync**: Local change → Push → Pull → Verify (skipped: not yet implemented)
  6. **Merge Requests**: Upload → Review → Approve → Cloud verification (skipped: not yet implemented)
  7. **Referential Integrity**: FK enforcement across tables
  8. **Compliance Validation**: Mandatory field checks (skipped: UI not complete)
  9. **State Consistency**: Project/Plot persistence across tab navigation
  10. **Export Formats**: CSV vs RDS consistency
- Uses `AppDriver` for UI interaction + direct DB queries to verify state
- Each test creates/cleans up own test data
- Async operation handling with `wait_for_idle()`
- Database verification via `verify_db_state()` helper

  - Reference data seeding
  - Data insertion & retrieval
  - PostgreSQL attachment (when available)
  - Query execution

---

## Test Categories

### Local DuckDB Tests (Always Run)
- `test-db_connections.R::connect_local_db() creates valid connection`
- `test-db_connections.R::test schema initializes with required tables`
- `test-db_connections.R::insert_test_plot() creates valid records`

**Status**: ✅ Fast, no external dependencies

### shinytest2 UI Tests (Require Chromium/Chrome)
- `test-smoke.R` — Basic app loading and context inputs
- `test-tabs.R` — Secondary tab navigation without errors
- `test-flow.R` — Project → Site/Env → Export workflow
- `test-import.R` — Import tab loading
- **`test-e2e-workflows.R`** 🆕 — **Comprehensive end-to-end critical paths**:
  - ✅ Test 1: Complete data entry cycle (runs always)
  - ✅ Test 2: Lumping application during export (runs always)
  - ⏭️ Test 3: Import validation workflow (skipped: not implemented)
  - ⏭️ Test 4: Hierarchy operations (skipped: 0% complete)
  - ⏭️ Test 5: Cloud sync bidirectional (skipped: not implemented)
  - ⏭️ Test 6: Merge request workflow (skipped: not implemented)
  - ✅ Test 7: Referential integrity checks (runs always)
  - ⏭️ Test 8: Compliance validation UI (skipped: not complete)
  - ✅ Test 9: Multi-tab state consistency (runs always)
  - ✅ Test 10: Export format validation (runs always)

**Status**: ✅ 5 tests run immediately, 5 ready for future feature implementation

**Run E2E tests only**:
```bash
Rscript -e "testthat::test_file('tests/shinytest2/test-e2e-workflows.R')"
```

### Conflict Resolution Tests (Cloud Sync Workflow)
- **`test-conflicts.R`** 🆕 — **Comprehensive conflict detection & resolution UI tests**:
  - ✅ Infrastructure tests: `sync_state`, `sync_conflicts` table setup (runs always)
  - ✅ Conflict creation: Single, multiple, diverse scenario helpers (runs always)
  - ⏭️ UI Tests: Diff viewer, Keep Local/Cloud, Dismiss actions (skipped: UI pending)
  - ⏭️ Batch Tests: Accept All Local/Cloud, selective resolution (skipped: UI pending)
  - ⏭️ Edge Cases: Delete conflicts, UUID collisions, sync cancellation (skipped: pending)
  - ⏭️ Integration: Conflict detection during sync operations (skipped: requires cloud mock)
  - ⏭️ Performance: Pagination, resolution speed benchmarks (skipped: pending)

**Status**: ✅ 6 infrastructure tests run immediately, 15 UI tests ready for implementation

**Documentation**: See [CONFLICT_RESOLUTION_TESTING.md](CONFLICT_RESOLUTION_TESTING.md) for detailed architecture, helper functions, and UI design specs.

**Run conflict tests only**:
```bash
Rscript -e "testthat::test_file('tests/shinytest2/test-conflicts.R')"
```

### PostgreSQL Integration Tests (Require docker-compose)
- `test-db_connections.R::attach_cloud_db() successfully attaches`
- `test-db_connections.R::Queries can reference attached PostgreSQL tables`
- `test-db_connections.R::DuckDB can write to PostgreSQL staging`

**Status**: ⏭️ Skipped if PostgreSQL unavailable (uses `skip_if_not()`)

### Running Only Local Tests
```r
testthat::test_file("tests/testthat/test-db_connections.R",
                    filter = "connect_local_db|schema initializes|insert_test_plot")
```

---

## Configuration Management

### config.yml Structure

```yaml
default:
  duckdb:
    main_db: "data/vpro.duckdb"
    lists_db: "data/vpro_lists.duckdb"
  log_level: INFO

development:
  postgres:
    host: localhost
    port: 5433
    database: becmaster
    user: testuser
    password: testpass
  cloud:
    enabled: true
    attach_on_startup: false  # Manual ATTACH for dev

test:
  postgres:
    host: localhost
    port: 5433
    # (same credentials)
  cloud:
    enabled: true
    attach_on_startup: true  # Auto-ATTACH for tests

production:
  postgres:
    host: prod-db.supabase.co
    use_env_vars: true  # Always use env vars in prod
  cloud:
    enabled: true
    attach_on_startup: true
```

### Using config.yml

**In R code:**
```r
library(config)

# Load environment-specific config
cfg <- config::get(config = "test")
pghost <- cfg$postgres$host
pgport <- cfg$postgres$port

# Or use environment variables (recommended for production)
Sys.setenv(PGHOST = cfg$postgres$host)
attach_cloud_db(con)
```

**In tests:**
```r
# Set test environment before loading test suite
Sys.setenv(R_CONFIG_ACTIVE = "test")

# Now all config::get() calls use test settings
cfg <- config::get()  # Loads from 'test' section
```

---

## Troubleshooting

### PostgreSQL Not Starting

```bash
# Check Docker installation
docker --version

# Check container logs
docker-compose logs vpro-postgres-test

# Try to manually connect
psql -h localhost -p 5433 -U testuser -d becmaster

# If psql not available, use docker exec
docker exec -it vpro-postgres-test psql -U testuser -d becmaster
```

### Tests Timeout or Hang

Usually indicates PostgreSQL connection issue. Check:

```bash
# Verify container is healthy
docker-compose ps

# Check health status
docker inspect vpro-postgres-test | grep -A 20 '"Health"'

# Restart container
docker-compose down
docker-compose up -d
sleep 10  # Wait for initialization
```

### DuckDB postgres Extension Error

If you see `Extension not found: postgres`:

1. Your DuckDB version may be too old (< 0.8.0)
2. Update DuckDB: `renv::update("duckdb")`
3. Or ensure postgres extension is installed:
   ```r
   con <- DBI::dbConnect(duckdb::duckdb(), ":memory:")
   DBI::dbExecute(con, "INSTALL postgres")
   DBI::dbExecute(con, "LOAD postgres")
   ```

### Test Files Not Found

Ensure working directory is project root:

```r
setwd("/Users/nicolas/Documents/GitHub/vpro")
```

Or run from command line:
```bash
cd /Users/nicolas/Documents/GitHub/vpro
Rscript -e "testthat::test_dir('tests/testthat')"
```

---

## Next Steps

### 1. Add to Global CI/CD (GitHub Actions)

Create `.github/workflows/test.yml`:
```yaml
name: Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:15
        env:
          POSTGRES_USER: testuser
          POSTGRES_PASSWORD: testpass
          POSTGRES_DB: becmaster
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
        ports:
          - 5432:5432

    steps:
      - uses: actions/checkout@v3
      - uses: r-lib/actions/setup-r@v2
      - run: Rscript -e "renv::restore()"
      - run: Rscript -e "testthat::test_dir('tests/testthat')"
```

### 2. Extend Tests for Other Modules

Create test files for each module:
- `test-mod_veg_sample.R` — Vegetation editing
- `test-mod_site_env.R` — Environment data
- `test-logic_compliance.R` — Data validation
- `test-logic_sync.R` — Local/cloud sync

Each should use helpers from `helpers.R` and follow the same structure.

### 3. Add Test Data Fixtures

For more complex scenarios, create SQL fixture files:
```
tests/fixtures/
  ├── sample_plots.sql      # 100 test plots
  ├── sync_conflicts.sql    # Conflict scenarios
  └── compliance_failures.sql # Invalid data samples
```

Load in tests:
```r
setup_fixture <- function(con, fixture_name) {
  sql <- readLines(here::here("tests/fixtures", paste0(fixture_name, ".sql")))
  DBI::dbExecute(con, paste(sql, collapse = "\n"))
}
```

---

## Key Files Overview

| File | Purpose |
|------|---------|
| `docker-compose.yml` | PostgreSQL 15 test container definition |
| `scripts/00_schema_becmaster_test.sql` | BECMaster schema + seed data (25+ tables) |
| `config.yml` | Environment-specific configuration |
| `R/db_connections.R` | DuckDB + PostgreSQL connection factory (150+ lines) |
| `tests/testthat/setup.R` | Test environment initialization |
| `tests/testthat/helpers.R` | Reusable test utilities (250+ lines) |
| `tests/testthat/test-db_connections.R` | 20+ integration tests |

---

## Development Workflow

### Local Development

1. **Start PostgreSQL once**:
   ```bash
   docker-compose up -d
   ```

2. **Open R/RStudio**:
   ```r
   setwd("/Users/nicolas/Documents/GitHub/vpro")
   source("R/db_connections.R")
   
   # Test local connection
   con <- connect_local_db(environment = "development")
   DBI::dbListTables(con)
   
   # Test cloud attachment (if postgres running)
   DBI::dbExecute(con, "INSTALL postgres; LOAD postgres;")
   attach_cloud_db(con, environment = "development")
   is_cloud_connected(con)  # Should be TRUE
   ```

3. **Run tests interactively**:
   ```r
   source("tests/testthat/helpers.R")
   
   con <- test_connect_duckdb()
   insert_test_plot(con)
   result <- DBI::dbGetQuery(con, "SELECT * FROM core.sample_veg")
   ```

### Continuous Integration

Tests run on every push via GitHub Actions. Tests that require PostgreSQL are automatically skipped if service unavailable, ensuring CI passes even without Docker.

---

## References

- **DuckDB postgres extension**: https://duckdb.org/docs/extensions/postgres
- **testthat**: https://testthat.r-lib.org/
- **config package**: https://rstudio.github.io/config/
- **Docker Compose**: https://docs.docker.com/compose/
- **PostgreSQL Docker**: https://hub.docker.com/_/postgres
