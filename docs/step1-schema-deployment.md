# Step 1: PostgreSQL Schema Deployment

## Overview

This step implements the foundational PostgreSQL schema with 5 schemas:
- **audit**: Append-only audit log using JSONB (based on ExaSpark pattern)
- **core**: Approved plot data (sample_veg, sample_env, sample_su, sample_metadata)
- **lists**: Reference/lookup tables (species, layers, BEC zones, etc.)
- **staging**: Pending submissions for review workflow
- **admin**: User registry and sync state tracking

## Key Features

1. **Audit Triggers**: Generic trigger function `audit.if_modified_func()` captures all INSERT/UPDATE/DELETE operations on `core.*` and `lists.*` tables
2. **Row Versioning**: Automatic `row_version` increment and `last_modified_utc` update via `core.row_version_trigger()`
3. **Seed Data**: Pre-populated with 10 species, 5 layers, 7 zones, 3 test users, and 2 sample plots
4. **Check Constraints**: Data validation at database level (cover_percent 0-100, latitude 48-60, etc.)

## Files Created

- `scripts/00_schema_becmaster_test.sql` - Complete schema definition with seed data
- `tests/testthat/test-schema_deployment.R` - Comprehensive test suite (16 tests)

## Deployment

### 1. Start Docker PostgreSQL

```bash
cd /Users/nicolas/Documents/GitHub/vpro
docker-compose up -d
```

Wait for PostgreSQL to be healthy:

```bash
docker-compose ps
```

### 2. Deploy Schema

The schema auto-deploys on container startup via `docker-compose.yml` volume mount.

To manually redeploy:

```bash
docker exec -i vpro-postgres-test psql -U testuser -d becmaster < scripts/00_schema_becmaster_test.sql
```

### 3. Verify Deployment

Connect to PostgreSQL:

```bash
docker exec -it vpro-postgres-test psql -U testuser -d becmaster
```

Check schemas:

```sql
\dn
-- Should show: admin, audit, core, lists, staging
```

Check seed data:

```sql
SELECT COUNT(*) FROM lists.spplist;  -- 10
SELECT COUNT(*) FROM lists.layercode;  -- 5
SELECT COUNT(*) FROM core.sample_veg;  -- 5
```

Exit: `\q`

## Running Tests

### From R Console

```r
# Load testthat
library(testthat)

# Run all schema tests
test_file("tests/testthat/test-schema_deployment.R")
```

### From Terminal

```bash
# With devtools
Rscript -e "devtools::test(filter = 'schema_deployment')"
```

## Test Coverage

The test suite includes 16 tests covering:

1. ✓ Docker PostgreSQL connectivity
2. ✓ Schema file deployment
3. ✓ All 5 schemas created
4. ✓ Audit schema components (logged_actions table, trigger function)
5. ✓ Core schema tables (sample_veg, sample_env, sample_su, sample_metadata)
6. ✓ Lists schema tables (spplist, layercode, usyszonelist, etc.)
7. ✓ Staging schema tables (merge_requests, merge_conflicts, etc.)
8. ✓ Seed data counts
9. ✓ Row version trigger on INSERT (sets version to 1)
10. ✓ Row version trigger on UPDATE (increments version)
11. ✓ Audit trigger captures INSERT (action='I', new_data JSONB)
12. ✓ Audit trigger captures UPDATE (action='U', original_data + new_data JSONB)
13. ✓ Audit trigger captures DELETE (action='D', original_data JSONB)
14. ✓ All core/lists tables have audit triggers attached
15. ✓ Check constraints enforce data rules

## Manual Testing

The schema file includes built-in test queries at the end. After deployment:

```bash
docker exec -it vpro-postgres-test psql -U testuser -d becmaster
```

Run the embedded tests:

```sql
-- Test 1: Seed data counts
SELECT 'Species count:' as metric, COUNT(*) as value FROM lists.spplist
UNION ALL SELECT 'Layer count:', COUNT(*) FROM lists.layercode;

-- Test 2: Initial row versions
SELECT id, plot_number, species_code, row_version 
FROM core.sample_veg LIMIT 3;

-- Test 3-5: INSERT/UPDATE/DELETE audit verification
-- (See schema file for full test queries)
```

## Expected Output

All tests should PASS. Example output:

```
✔ Docker PostgreSQL is accessible
✔ Schema file can be deployed to PostgreSQL
✔ All schemas were created
✔ Audit schema has logged_actions table and trigger function
✔ Core schema has all expected tables
✔ Lists schema has all reference tables
✔ Staging schema has all workflow tables
✔ Seed data was inserted correctly
✔ Row version trigger works on INSERT
✔ Row version trigger increments on UPDATE
✔ Audit trigger captures INSERT
✔ Audit trigger captures UPDATE with old and new data
✔ Audit trigger captures DELETE
✔ All core and lists tables have audit triggers attached
✔ Check constraints work correctly

══ Results ════════════════════════════════════════════════════════════════
Duration: 2.3 s

OK:       16
Failed:   0
Warnings: 0
Skipped:  0
```

## Troubleshooting

### Container won't start

```bash
# Check logs
docker-compose logs postgres

# Remove old data volume
docker-compose down -v
docker-compose up -d
```

### Schema errors

```bash
# Check PostgreSQL logs
docker logs vpro-postgres-test

# Manually deploy to see errors
docker exec -i vpro-postgres-test psql -U testuser -d becmaster < scripts/00_schema_becmaster_test.sql
```

### Tests fail with "PostgreSQL not available"

```bash
# Verify container is running
docker ps | grep vpro-postgres

# Test connection
docker exec vpro-postgres-test pg_isready -U testuser -d becmaster
```

## Next Steps

After Step 1 passes all tests:
- **Step 2**: Create PostgreSQL roles and grants (`R/db_roles.R`)
- **Step 3**: Build validation helpers (`R/logic_validation.R`)
