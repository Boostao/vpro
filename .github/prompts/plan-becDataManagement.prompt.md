# Plan: BEC Data Management — PostgreSQL Back-End (Optimized)

Rewrite the PG schema from scratch. Audit via generic trigger + `audit.logged_actions` (JSONB, append-only, per the [exaspark article](https://exaspark.medium.com/the-ultimate-guide-to-postgresql-data-change-tracking-c3fa88779572) pattern). Delta sync uses row-level MD5 hashes in a local `_sync_meta` DuckDB table. Lists are pull-only (admin-managed). Name mapping in `R/logic_sync.R`. Each step = one commit + tests.

## Local Storage Note

This plan predates the SQLite-shard migration. For current work, interpret "local DuckDB" as the app's in-memory DuckDB session over attached canonical SQLite databases. Do not treat a persisted local DuckDB file as the canonical local store.

## Context

- **Source**: VPro64 Access database migrated to R Shiny + canonical local SQLite + PostgreSQL (cloud)
- **Local runtime DuckDB**: in-memory workspace over attached SQLite databases — user edits flow through the local canonical SQLite layer, no audit until push
- **PostgreSQL**: source of truth with audit triggers on `core.*` and `lists.*`
- **User identity**: simple dialog (name + email) at push time — no auth system yet
- **Dev/Test**: Docker PostgreSQL on `localhost:5433` (`docker-compose.yml`)
- **Production**: DigitalOcean PostgreSQL (future)

## Architecture

```
┌─────────────────┐         ┌──────────────────────────────────┐
│  Local DuckDB   │         │       PostgreSQL (cloud)         │
│                 │  pull   │                                  │
│  Sample_Veg     │◄────────│  core.sample_veg                 │
│  Sample_Env     │         │  core.sample_env                 │
│  Sample_SU      │         │  core.sample_su                  │
│  SppList        │         │  core.sample_metadata            │
│  LayerCode      │         │  lists.spplist                   │
│  ...            │         │  lists.layercode                 │
│                 │  push   │  lists.usyszonelist              │
│  _sync_meta     │────────►│  lists.usyssubzonelist           │
│  (hash tracker) │         │  lists.usystableoflists          │
│                 │         │                                  │
│                 │         │  staging.sample_veg  ──┐         │
│                 │         │  staging.sample_env    │ review  │
│                 │         │  staging.sample_su     │         │
│                 │         │  admin.merge_requests─┘         │
│                 │         │  staging.merge_conflicts          │
│                 │         │                                  │
│                 │         │  audit.logged_actions (append-only)│
│                 │         │  admin.users                     │
│                 │         │  admin.sync_state                │
└─────────────────┘         └──────────────────────────────────┘
```

## Steps

### Step 1: Rewrite the PostgreSQL schema

**File**: `scripts/00_schema_becmaster_test.sql` (full rewrite)

**4 schemas**:

- **`audit`** — `logged_actions` table:
  - `id SERIAL PRIMARY KEY`
  - `schema_name TEXT NOT NULL`
  - `table_name TEXT NOT NULL`
  - `user_name TEXT`
  - `action_tstamp TIMESTAMPTZ NOT NULL DEFAULT current_timestamp`
  - `action TEXT NOT NULL CHECK (action IN ('I','D','U'))`
  - `original_data JSONB`
  - `new_data JSONB`
  - `query TEXT`
  - Generic `audit.if_modified_func()` trigger function (JSONB variant from article)
  - `REVOKE DELETE, UPDATE ON audit.logged_actions` from non-superusers (append-only)
  - Applied to all `core.*` and `lists.*` tables via `AFTER INSERT OR UPDATE OR DELETE FOR EACH ROW`

- **`core`** — approved plot data:
  - `sample_veg` (id, plot_number, species_code, layer_code, cover_percent CHECK 0–100, height_cm CHECK ≥0, cover_code, project_id, row_version, last_modified_utc, modified_by, UNIQUE(plot_number, species_code, layer_code, project_id))
  - `sample_env` (id, plot_number UNIQUE, project_id, latitude CHECK 48–60, longitude CHECK −140 to −114, elevation_m CHECK 0–4000, survey_date, surveyor_name, plot_notes, row_version, last_modified_utc, modified_by)
  - `sample_su` (id, plot_number UNIQUE, project_id, su_number, bec_zone, bec_subzone, site_series, row_version, last_modified_utc, modified_by)
  - `sample_metadata` (id, project_id UNIQUE, project_name, description, organization, contact_email, created_utc, row_version, last_modified_utc, modified_by)
  - A `core.row_version_trigger()` function: auto-increments `row_version` and sets `last_modified_utc = now()` on UPDATE. Applied to each core table.

- **`lists`** — reference/lookup (admin-managed, pull-only for users):
  - `spplist` (spp_code PK, spp_name, spp_scientific, is_active, row_version, last_modified_utc)
  - `layercode` (layer_code PK, layer_name, sort_order, row_version, last_modified_utc)
  - `usyszonelist` (zone_code PK, zone_name, province, row_version, last_modified_utc)
  - `usyssubzonelist` (zone_code + subzone_code PK, subzone_name, FK→usyszonelist, row_version, last_modified_utc)
  - `usystableoflists` (list_id + item_code PK, item_name, item_sort, row_version, last_modified_utc)
  - Audit triggers applied to each lists table

- **`staging`** — pending submissions for review:
  - `sample_veg` (mirrors core + `merge_request_id INTEGER NOT NULL` + `change_type TEXT NOT NULL CHECK ('I','U','D')`)
  - `sample_env` (mirrors core + `merge_request_id` + `change_type`, no range constraints — staging is permissive)
  - `sample_su` (mirrors core + `merge_request_id` + `change_type`)
  - `merge_requests` (id, project_id, submitter_name, submitter_email, submitted_utc, status CHECK `pending_review/approved/rejected/merged`, reviewer, review_notes, reviewed_utc, record_counts)
  - `merge_conflicts` (id, merge_request_id FK, table_name, plot_number, column_name, local_value, incoming_value, resolved, resolution)
  - No audit triggers on staging tables

- **`admin`** — minimal user/sync tracking:
  - `users` (id, username UNIQUE, email UNIQUE, full_name, role CHECK `reader/writer/admin`, is_active, created_utc)
  - `sync_state` (id, user_id FK, table_name, last_pulled_utc, last_pulled_row_version)

**Indexes**:
- `last_modified_utc` on all `core.*` and `lists.*` tables (for delta sync)
- `plot_number` and `project_id` on `core.sample_veg`, `core.sample_env`
- `species_code` on `core.sample_veg`
- `merge_request_id` on all `staging.*` data tables
- `action_tstamp` on `audit.logged_actions`

**Seed data**: 10 species, 5 layers, 7 zones, 7 subzones, generic list values, 3 test users (reader/writer/admin), 1 sample project.

**Test**: Deploy to Docker PG. INSERT a `core.sample_veg` row → verify `audit.logged_actions` has `action='I'` with `new_data` JSONB. UPDATE that row → verify `row_version` incremented to 2, `last_modified_utc` updated, and `audit.logged_actions` has `action='U'` with both `original_data` and `new_data`.

---

### Step 2: Create PG roles & grants

**File**: `R/db_roles.R` (new)

**Functions**:
- `create_pg_roles(con)` — creates 3 PostgreSQL roles:
  - `vpro_reader`: `GRANT SELECT ON ALL TABLES IN SCHEMA core, lists`
  - `vpro_writer`: inherits vpro_reader + `GRANT INSERT, UPDATE ON ALL TABLES IN SCHEMA staging`
  - `vpro_admin`: `GRANT ALL PRIVILEGES` on all schemas
  - All roles: `REVOKE DELETE, UPDATE ON audit.logged_actions`

**Test**: Connect to Docker PG as superuser, call `create_pg_roles()`. Connect as each role. Assert:
- `vpro_reader` can SELECT `core.sample_veg` but cannot INSERT into `staging.sample_veg`
- `vpro_writer` can SELECT `core.*` and INSERT into `staging.*` but cannot UPDATE `core.*`
- `vpro_admin` can do everything except modify `audit.logged_actions`

---

### Step 3: Build validation helpers

**File**: `R/logic_validation.R` (new)

**Functions**:
- `validate_veg_row(row, con)` — checks:
  - `cover_percent` is integer 0–100
  - `height_cm` is integer ≥ 0
  - `species_code` exists in `lists.spplist` (or DuckDB `SppList`)
  - `layer_code` exists in `lists.layercode` (or DuckDB `LayerCode`)
  - `plot_number` is non-empty text
  - `project_id` is positive integer
  - Returns `list(valid = TRUE/FALSE, errors = character())`

- `validate_env_row(row, con)` — checks:
  - `latitude` is numeric 48–60
  - `longitude` is numeric −140 to −114
  - `elevation_m` is integer 0–4000
  - `survey_date` is valid date or NULL
  - `plot_number` is non-empty text
  - `project_id` is positive integer
  - Returns `list(valid = TRUE/FALSE, errors = character())`

- `validate_su_row(row, con)` — checks:
  - `bec_zone` exists in `lists.usyszonelist` (if provided)
  - `bec_subzone` + `bec_zone` combo exists in `lists.usyssubzonelist` (if provided)
  - Returns `list(valid = TRUE/FALSE, errors = character())`

- `validate_submission(data_list, con)` — validates a named list of data.frames (`veg`, `env`, `su`) and returns aggregated results.

**Test**: Create seeded DuckDB with reference data. Pass valid rows → assert `valid = TRUE`. Pass rows with cover = 150, lat = 999, unknown species → assert `valid = FALSE` with specific error messages.

---

### Step 4: Implement staging submission

**File**: `R/logic_staging.R` (new)

**Functions**:
- `submit_to_staging(pg_con, table, data, user_name, user_email, change_type = "I")` — in a transaction:
  1. Calls validation (step 3) against PG lists tables
  2. Creates `admin.merge_requests` row (submitter_name, submitter_email, status = `pending_review`)
  3. Inserts rows into `staging.{table}` with `merge_request_id` and `change_type`
  4. Updates record counts on `merge_requests`
  5. Returns the `merge_request_id`

- `submit_changes(pg_con, changes_list, user_name, user_email)` — wraps `submit_to_staging` for multiple tables at once. `changes_list` is a named list like `list(sample_veg = list(inserts = df, updates = df, deletes = df), ...)`.

**Test**: Submit veg + env rows to Docker PG. Query `staging.sample_veg` → assert rows present with correct `merge_request_id`. Query `admin.merge_requests` → assert status = `pending_review`, correct record counts.

---

### Step 5: Implement admin review & merge

**File**: `R/logic_merge.R` (new)

**Functions**:
- `list_pending_merges(pg_con)` — returns all `merge_requests` with `status = 'pending_review'`, joined with record counts and submitter info.

- `get_merge_details(pg_con, merge_request_id)` — returns all staging rows for a given request, grouped by table.

- `detect_conflicts(pg_con, merge_request_id)` — checks:
  - Key collisions: staging rows whose natural keys (e.g. `plot_number + species_code + layer_code + project_id`) already exist in `core.*`
  - Cross-request conflicts: same keys in other pending requests
  - Writes conflict rows to `staging.merge_conflicts`
  - Returns conflict summary

- `resolve_conflict(pg_con, conflict_id, resolution)` — marks a conflict resolved with chosen resolution (`keep_incoming`, `keep_existing`, `manual`).

- `approve_merge(pg_con, merge_request_id, reviewer)` — in a single transaction:
  1. Checks all conflicts are resolved
  2. For `change_type = 'I'`: INSERT into `core.*` (triggers auto-fire: audit row created, row_version set to 1)
  3. For `change_type = 'U'`: UPDATE `core.*` matching natural keys (triggers auto-fire: audit row with old/new JSONB, row_version incremented)
  4. For `change_type = 'D'`: DELETE from `core.*` (triggers auto-fire: audit row with original_data)
  5. Updates `merge_requests.status = 'merged'`, sets `reviewer`, `reviewed_utc`
  6. Returns merge summary

- `reject_merge(pg_con, merge_request_id, reviewer, reason)` — sets status = `rejected`, records review_notes.

**Test**: Submit two merge requests with overlapping keys (same plot/species/layer). Call `detect_conflicts()` → assert conflicts found. Resolve + `approve_merge()` for one → verify rows in `core.*`, `audit.logged_actions` entries with correct action types, and `merge_requests.status = 'merged'`. `reject_merge()` the other → verify status = `rejected`.

---

### Step 6: Implement delta sync with row hashing

**File**: `R/logic_sync.R` (new)

**Name mapping**:
```r
TABLE_MAP <- list(
  # DuckDB name = list(pg_table, pk_cols, data_cols)
  Sample_Veg = list(
    pg = "core.sample_veg",
    pk = c("plot_number", "species_code", "layer_code", "project_id"),
    cols = c("cover_percent", "height_cm", "cover_code")
  ),
  Sample_Env = list(
    pg = "core.sample_env",
    pk = c("plot_number"),
    cols = c("project_id", "latitude", "longitude", "elevation_m",
             "survey_date", "surveyor_name", "plot_notes")
  ),
  Sample_SU = list(
    pg = "core.sample_su",
    pk = c("plot_number"),
    cols = c("project_id", "su_number", "bec_zone", "bec_subzone", "site_series")
  ),
  SppList = list(
    pg = "lists.spplist",
    pk = c("spp_code"),
    cols = c("spp_name", "spp_scientific", "is_active")
  ),
  LayerCode = list(
    pg = "lists.layercode",
    pk = c("layer_code"),
    cols = c("layer_name", "sort_order")
  ),
  USysZoneList = list(
    pg = "lists.usyszonelist",
    pk = c("zone_code"),
    cols = c("zone_name", "province")
  ),
  USysSubZoneList = list(
    pg = "lists.usyssubzonelist",
    pk = c("zone_code", "subzone_code"),
    cols = c("subzone_name")
  ),
  USysTableOfLists = list(
    pg = "lists.usystableoflists",
    pk = c("list_id", "item_code"),
    cols = c("item_name", "item_sort")
  )
)
```

**Local DuckDB `_sync_meta` table**:
```sql
CREATE TABLE IF NOT EXISTS _sync_meta (
    table_name TEXT NOT NULL,
    pk_values TEXT NOT NULL,      -- pipe-delimited PK values
    row_hash TEXT NOT NULL,       -- MD5 of concatenated data columns
    synced_utc TIMESTAMP NOT NULL,
    PRIMARY KEY (table_name, pk_values)
);
```

**Functions**:

- `compute_row_hash(row, data_cols)` — computes `MD5(paste(row[data_cols], collapse = "|"))` for a single row or vectorized over a data.frame. Handles NULLs consistently (e.g. `"__NULL__"` placeholder).

- `make_pk_key(row, pk_cols)` — creates the pipe-delimited PK string for `_sync_meta` lookup.

- `init_local_from_master(pg_con, duck_con, user_id)` — first-time full pull:
  1. For each entry in `TABLE_MAP`:
     - Query all rows from PG table
     - Write into DuckDB table (creating if needed)
     - Compute hashes and populate `_sync_meta`
  2. Record watermarks in PG `admin.sync_state` (one row per table: `last_pulled_utc`, `last_pulled_row_version`)
  3. Return summary of rows pulled per table

- `pull_from_master(pg_con, duck_con, user_id)` — incremental delta pull:
  1. Read watermarks from `admin.sync_state` for this user
  2. For each table in `TABLE_MAP`:
     - Query PG: `SELECT * FROM {pg_table} WHERE last_modified_utc > {watermark}`
     - UPSERT into local DuckDB (INSERT OR REPLACE on PK)
     - Recompute hashes in `_sync_meta` for affected rows
     - Check for PG-side deletes: query PG PKs, compare with local, remove orphans from DuckDB + `_sync_meta`
  3. Advance watermarks in `admin.sync_state`
  4. Return summary of rows changed per table

- `push_to_staging(duck_con, pg_con, user_name, user_email)` — detect local changes and submit:
  1. For each `core.*` entry in `TABLE_MAP` (skip `lists.*` — pull-only):
     - Read all local rows from DuckDB
     - Compute current hashes
     - Compare against `_sync_meta`:
       - Hash mismatch → `change_type = 'U'` (update)
       - PK in local but not in `_sync_meta` → `change_type = 'I'` (insert)
       - PK in `_sync_meta` but not in local → `change_type = 'D'` (delete)
     - Collect changed rows into a changes list
  2. If no changes detected, return early
  3. Call `submit_changes(pg_con, changes_list, user_name, user_email)` from step 4
  4. Do NOT update `_sync_meta` hashes yet (rows are in staging, not in core — hashes update on next `pull_from_master` after merge)
  5. Return summary of rows pushed per table + merge_request_id

**Test**:
1. Seed PG core with sample data. Call `init_local_from_master()` → verify DuckDB row counts match PG, `_sync_meta` has correct hashes, `admin.sync_state` has watermarks.
2. Modify 1 row + add 1 row in local DuckDB. Call `push_to_staging()` → verify exactly 2 rows in `staging.sample_veg` with correct `change_type` (1× `U`, 1× `I`).
3. Delete 1 row locally. Call `push_to_staging()` → verify 1 row in staging with `change_type = 'D'`.
4. Simulate merged data: INSERT new row directly in PG `core.sample_veg`. Call `pull_from_master()` → verify only the new row transferred to DuckDB, `_sync_meta` updated, watermark advanced.

## Design Decisions

- **Audit is append-only in PG** — `REVOKE DELETE, UPDATE ON audit.logged_actions`. No audit in DuckDB; local changes are untracked until pushed to staging.
- **Lists are pull-only** — admin edits lists directly in PG; users receive updates via delta sync. No staging tables for lists.
- **Deletes supported** — staging tables include `change_type` column (`I/U/D`) so deletions go through the review workflow.
- **MD5 for diff** — sufficient for data integrity detection at < 1M rows. Handles NULLs via placeholder string. Upgrade to SHA-256 if dataset grows significantly.
- **Name mapping in R** — `TABLE_MAP` in `logic_sync.R` bridges DuckDB legacy names (e.g. `Sample_Veg`) to PG schema-qualified names (e.g. `core.sample_veg`). Single source of truth for column mappings.
- **Hashes don't update on push** — `_sync_meta` reflects "last known server state". After push, rows are in staging (not core). Hashes only update on next `pull_from_master` after admin merges.
- **No auth system** — user provides name + email via dialog at push time. Role enforcement is via PG connection roles, not application-level middleware.
