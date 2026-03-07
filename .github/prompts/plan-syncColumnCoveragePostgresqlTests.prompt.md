# Plan: Comprehensive Sync Column Coverage & PostgreSQL Test Integration

## TL;DR
Three interconnected issues:
1. **Pull mechanism** skips several columns during conflict detection (env: Zone/SubZone/SiteSeries; veg: Height3-6, ID, AF-FFA, Cultural1-2, Other1-2)
2. **Push mechanism** either incompletely compares or doesn't store all columns (env missing Zone/SubZone/SiteSeries; push functions work but pull comparisons incomplete)
3. **Tests** use in-memory DuckDB simulation instead of actual PostgreSQL from docker-compose, and don't validate full column coverage

## Key Findings

### PULL ISSUES
- **`.pull_env`** (L283-289): `env_fields` list missing Zone, SubZone, SiteSeries comparisons
- **`.pull_veg`** (L598-608): `veg_fields` list incomplete; missing Height3, Height4, Height5, Height5a, Height5b, Height5c, Height6 and ID, AF, DC, UT, VI, PV, PG, FFA, Cultural1-2, Other1-2
- **Impact**: Conflicts undetected if these columns diverge; silently lost data on fast-forward

### PUSH ISSUES
- **`.push_env`** (L1150+): Delta comparison queries missing Zone, SubZone, SiteSeries sniff checks
- **`.push_su`** (L1205+): References Zone/SubZone/SiteSeries from Env but SU table may not store them dually
- **`.push_veg`**: Appears complete (all columns selected into staging)
- **Impact**: Changes to Zone/SubZone/SiteSeries in Env might not trigger env push; SU push may miss updates

### TEST ISSUES
- **Current setup** (setup.R): Uses in-memory DuckDB with hardcoded schema, not PostgreSQL docker-compose
- **No validation**: Tests don't assert that specific columns were actually synced
- **Fresh DuckDB**: No test for pulling into a completely empty DuckDB
- **Lists sync**: Limited test coverage for lists tables

### SCHEMA REFERENCE
- **Env**: PlotNumber, ProjectID, Latitude, Longitude, Elevation, Date, SiteSurveyor, SiteNotes, **Zone, SubZone, SiteSeries**, master_row_version, local_modified_utc
- **SU**: PlotNumber, SiteUnit, master_row_version, local_modified_utc
- **Veg**: PlotNumber, Species, Layer, Cover1-10 pairs with Height, TotalA/B with HeightA/B, **Height3, Height4, Height5, Height5a, Height5b, Height5c, Height6**, Collected, Flag, **ID, LL, AF, DC, UT, VI, PV, PG, FFA, Cultural1-2, Other1-2**, master_row_version, local_modified_utc

## Implementation Steps

### Phase 1: Fix Pull Mechanisms (logic_sync.R)
1. **Update `.pull_env` env_fields list** to include Zone, SubZone, SiteSeries
   - File: `/Users/nicolas/Documents/GitHub/vpro/R/logic_sync.R` lines 283-289
   - Add 3 field pairs to list
2. **Update `.pull_veg` veg_fields list** to include all missing Height and supplemental columns
   - File: same, lines 598-608
   - Expand list from ~12 pairs to ~35+ pairs
3. **Verify .upsert_local_veg** handles all new columns in UPDATE/INSERT
   - Lines 726-774 already have full param list, just need to verify it aligns with query

### Phase 2: Fix Push Mechanisms (logic_sync.R)
4. **Update `.push_env` delta query** to sniff Zone, SubZone, SiteSeries
   - File: same, lines 1150-1195
   - Add three more OR clauses to the IS DISTINCT FROM condition
5. **Verify `.push_su` data model** — confirm SU table stores or derives Zone/SubZone/SiteSeries correctly
   - Current code (lines 1205-1253) pulls from Env table; check if this is correct per schema
6. **No changes needed for `.push_veg`** — already complete

### Phase 3: Refactor Tests (test-logic_sync.R)
7. **Create PostgreSQL test helper** that:
   - Connects to docker-compose postgres (localhost:5433)
   - Configures master, core, staging, admin, lists schemas from 00_schema_becmaster_test.sql
   - Seeds sample data (env, su, veg, lists)
   - Cleans up after each test
   
8. **Add PostgreSQL-based integration test suite**:
   - Test pull into fresh empty Env/SU/Veg tables with all columns
   - Assert every column listed in veg_fields/env_fields is actually synced
   - Test push with rows that have all supplemental columns filled
   - Test conflict detection on Zone/SubZone/SiteSeries changes
   - Test lists sync with multiple reference tables
   
9. **Keep existing in-memory tests** as fast unit tests (optional, don't remove)

### Phase 4: Validation
10. **Add column-coverage assertions** to pull tests:
    - After pull, query local table and verify columns not NULL/NaN
    - Explicitly test Height3-6 sync, AF-FFA sync, Cultural/Other sync
11. **Add fresh DuckDB test**:
    - Create completely empty local DuckDB with only schema (no seed rows)
    - Pull from master
    - Assert env/su/veg rows populated with all expected columns

## Relevant Files
- [`R/logic_sync.R`](R/logic_sync.R) — Pull/push implementations to fix
- [`tests/testthat/test-logic_sync.R`](tests/testthat/test-logic_sync.R) — Test refactor
- [`tests/testthat/setup.R`](tests/testthat/setup.R) — Already has postgres env vars configured
- [`scripts/00_schema_becmaster_test.sql`](scripts/00_schema_becmaster_test.sql) — Schema for postgres setup

## Verification Strategy
1. **Unit**: Each field pair in veg_fields/env_fields can be tested independently
2. **Integration**: PostgreSQL docker-compose tests with full data round-trip (push → admin review → pull)
3. **Fresh DuckDB**: Empty local DB pull confirms all columns migrate
4. **Lists**: Verify reference tables in lists catalog can be synced without conflicts

## Non-Breaking Decisions
- Preserve existing `.pull_env`, `.pull_su`, `.pull_veg` function signatures
- Keep column naming conventions (local: PascalCase; master: snake_case)
- No changes to conflict resolution logic
- No schema changes to postgres (already has all columns)
