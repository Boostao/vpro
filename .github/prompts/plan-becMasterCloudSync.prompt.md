# Plan: VPro → BECMaster Cloud Sync & Data Management Platform

Migrate the current VPro Shiny app to a hybrid local/cloud architecture where an in-memory DuckDB runtime attaches the canonical local SQLite databases and, when needed, connects to a central **BECMaster PostgreSQL** database via DuckDB's native `postgres` extension (`ATTACH`). Role-based access control, data compliance validation, change-tracked merging, and public RDS data publishing remain in scope. **A single connection engine (DuckDB)** handles both local and remote data — no `RPostgres`/`pool` needed.

## Local Storage Note

This plan should now be read with the current local architecture in mind:

- Canonical local storage is SQLite under `data/`, `data/pics/`, and `data/projects/`
- DuckDB is the in-memory runtime attachment/query layer
- Any old references to local `vpro*.duckdb` files as persisted canonical stores are superseded

## Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│  Local Machine (field / analyst)                        │
│  ┌──────────────────────────────────────────────────┐   │
│  │ DuckDB (in-process, in-memory)                  │   │
│  │  ├── local data:  ATTACH 'data/VPro64.db'       │   │
│  │  ├── local lists: ATTACH 'data/VLists.db'       │   │
│  │  ├── local user:  ATTACH 'data/VUser.db'        │   │
│  │  ├── local meta:  ATTACH 'data/VMetaData.db'    │   │
│  │  └── cloud:       ATTACH 'postgres://...'       │   │
│  │                   AS master (TYPE postgres,       │   │
│  │                   READ_ONLY | READ_WRITE)         │   │
│  └──────────────────────────────────────────────────┘   │
│  R Shiny App (all queries via single DuckDB connection) │
└─────────────────────┬───────────────────────────────────┘
                      │ postgres wire protocol
                      ▼
┌─────────────────────────────────────────────────────────┐
│  Cloud PostgreSQL (Supabase / Neon / AWS RDS)           │
│  ├── core.*          (approved plot data)               │
│  ├── lists.*         (reference codes, species)         │
│  ├── staging.*       (pending uploads / merge requests) │
│  ├── admin.*         (users, roles, audit, logs)        │
│  └── public_export.* (RDS snapshots, download log)      │
└─────────────────────────────────────────────────────────┘
```

## Steps

### 1. Design and deploy the BECMaster PostgreSQL schema

Translate all table schemas from `../VPRO_ACCESS/VPro64_forAI/Tables_Def/` (plus VLists, VMetaData, VUser) into a PostgreSQL migration script. Use a **schema-per-concern** layout:

| Schema | Tables | Purpose |
|--------|--------|---------|
| `core` | `sample_veg`, `sample_env`, `sample_su`, `sample_admin`, `sample_humus`, `sample_mineral`, `sample_hierarchy`, `sample_metadata`, `sample_herbarium`, `sample_other`, `sample_lump` | Approved plot data |
| `lists` | `usystableoflists`, `spplist`, `layercode`, `usyszonelist`, `mastersiteunitlist`, `usyssppattributes`, `usyssiteseriesnames` | Reference/lookup codes |
| `staging` | Mirror of `core` tables + `merge_requests`, `compliance_results` | Pending uploads awaiting review |
| `admin` | `users`, `roles`, `user_roles`, `change_log`, `merge_history`, `user_restrictions` | Auth, audit, change tracking |
| `public_export` | `rds_snapshots`, `download_log` | Published datasets & access logging |

Add versioning columns to all `core` and `staging` tables: `row_version INTEGER DEFAULT 1`, `last_modified_utc TIMESTAMPTZ DEFAULT now()`, `modified_by TEXT`.

### 2. Build unified DuckDB connection layer with cloud ATTACH

Replace the hardcoded `db_path` in `global.R` with a connection module `R/db_connections.R`:

- Load connection settings for canonical local SQLite paths plus the remote postgres connection string.
- Open an in-memory DuckDB connection and `ATTACH` the canonical SQLite databases (`data/VLists.db AS lists`, etc.)
- **Conditionally `ATTACH` the remote PostgreSQL** when online:
  ```sql
  INSTALL postgres;
  LOAD postgres;
  CREATE SECRET (TYPE postgres, HOST '...', PORT 5432, DATABASE 'becmaster',
                 USER '...', PASSWORD '...');
  ATTACH '' AS master (TYPE postgres, READ_ONLY);
  ```
- Expose a helper `is_cloud_connected()` reactive for UI gating
- All existing `dbplyr`/`DBI` queries work unchanged — just prefix table references with `master.core.` or `master.lists.` when querying cloud
- For write operations (upload, sync-push), use a separate `ATTACH ... READ_WRITE` or `postgres_execute()` passthrough

**No new R package dependencies** — DuckDB's built-in `postgres` extension handles everything.

### 3. Implement data compliance validation engine

Create `R/logic_compliance.R` with rule functions checking mandatory field standards before any upload, update, or merge:

- **Mandatory fields**: `PlotNumber`, `Species`, `ProjectID`, `Zone`, `SubZone` non-null
- **Foreign-key validation**: species codes exist in `lists.spplist`, zone/subzone in `lists.usyszonelist`, dropdown values in `lists.usystableoflists` — validated via cross-database DuckDB queries (local or cloud lists)
- **Range checks**: latitude (48–60), longitude (−140 to −114), elevation (0–4000), cover values (0–100 or valid text codes `+`, `r`, `P`)
- **Format validation**: `PlotNumber` matches expected pattern, species codes ≤ 8 chars
- **Uniqueness**: no duplicate `PlotNumber` within a project, no duplicate `PlotNumber + Species` rows in `sample_veg`
- **Structural checks**: uploaded CSV/ZIP contains expected table names with correct column sets

Return a structured list: `list(passed = TRUE/FALSE, summary = tibble(rule, status, n_violations), details = tibble(rule, table, row, column, value, message))`. Wire a "Validate" button into the upload UI showing pass/fail badges and a drilldown DT table.

### 4. Build the dataset upload & merge-request workflow

Create `R/mod_upload.R`:

- UI: file input (CSV/ZIP), project selector, "Validate" and "Submit" buttons, compliance report display
- On upload: parse files into data frames, run compliance engine (step 3)
- If validation passes: write to PostgreSQL staging via DuckDB (`INSERT INTO master.staging.sample_veg SELECT * FROM uploaded_df`) and create a `merge_request` record (`submitter`, `project_id`, `timestamp`, `status = 'pending_review'`, `compliance_report_id`)

Create `R/mod_merge.R` for database managers:

- List pending merge requests with project, submitter, date, record counts
- Side-by-side diff view: incoming vs. existing records keyed on `PlotNumber`, highlighting changed fields
- Accept/reject per-record or bulk actions
- On accept: transactional merge into `core` schema with full before/after change history written to `admin.change_log` (extending the `USysAudit` pattern)
- On reject: update `merge_request.status = 'rejected'` with reviewer notes

### 5. Build local ↔ cloud sync with change tracking

Create `R/logic_sync.R`:

- **Sync-pull** (cloud → local): Compare `row_version` between `master.core.*` and local tables. Fetch and upsert records where remote `row_version > local row_version`:
  ```sql
  CREATE OR REPLACE TABLE local_sample_env AS
    FROM master.core.sample_env WHERE last_modified_utc > $last_sync;
  ```
- **Sync-push** (local → cloud): Detect locally modified records (local `row_version > synced_version`), package as a merge request (step 4) — changes go through the review workflow, not directly into `core`
- **Conflict detection**: Flag records modified in both local and cloud since last sync. Store conflicts in a local `sync_conflicts` table for manual resolution
- **Change log**: All sync operations log to `master.admin.change_log` with `sync_id`, `direction` (pull/push), `user_id`, `timestamp`, `table_name`, `pk`, `field`, `old_value`, `new_value`
- **Offline snapshot**: On sync-pull, cache a full local copy for offline work. On reconnect, diff and push changes

Add a sync panel in `R/mod_admin.R`: last sync timestamp, sync status indicator, conflict count badge, "Sync Now" button, conflict resolution UI.

### 6. Implement user accreditation & role-based access

Create `R/mod_auth.R` authenticating against `master.admin.users` / `master.admin.roles` via DuckDB postgres queries:

| Role | Permissions |
|------|-------------|
| `viewer` | Read-only access to public/exported data |
| `field_user` | Enter/edit own plots, upload datasets |
| `project_lead` | Manage own project's plots, approve field_user uploads within project |
| `db_manager` | Review all merge requests, edit all data, manage reference codes |
| `admin` | Manage users/roles, system configuration |

- Login UI with username/password (hashed with `bcrypt` in PostgreSQL)
- Session token stored in Shiny session, checked on every server call
- Gate write operations: `req(user_has_role(session, "field_user"))` in `R/mod_veg_sample.R`, `R/mod_site_env.R`, etc.
- Gate admin operations: `req(user_has_role(session, "db_manager"))` in merge/admin modules
- Port `USysUserRestrictions` concept: per-user project/tag restrictions stored in `admin.user_restrictions`
- `ATTACH` uses role-specific PostgreSQL credentials (read-only for viewers, read-write for field_user+)

### 7. Build RDS public data publishing pipeline

Create `R/logic_publish.R` with `publish_becmaster_rds()`:

1. Query approved plot data from `master.core.*` (or local synced copy) where `qa_status = 'approved'`
2. Apply lumping via `R/logic_lumping.R` (species synonym consolidation)
3. Pivot to wide species matrix reusing `R/mod_export.R` logic (Sites × Species_Layer)
4. Join environmental data from `core.sample_env` + `core.sample_su`
5. Write versioned `.rds` files (`becmaster_veg_YYYYMMDD.rds`, `becmaster_env_YYYYMMDD.rds`) to configured output directory or cloud storage
6. Record snapshot metadata in `public_export.rds_snapshots` (version, date, row counts, md5 hash)

Trigger from admin panel (db_manager role). Resulting RDS files served by a separate lightweight public Shiny app or Plumber API.

### 8. Record and store data download activity

Create `public_export.download_log` table in PostgreSQL:

| Column | Type | Description |
|--------|------|-------------|
| `id` | SERIAL PK | |
| `user_id` | TEXT | Authenticated user or 'anonymous' |
| `timestamp` | TIMESTAMPTZ | Download time |
| `dataset_name` | TEXT | e.g., 'becmaster_veg_20260207' |
| `format` | TEXT | 'rds', 'csv' |
| `filters_applied` | JSONB | Project, layer, region filters |
| `row_count` | INTEGER | Rows in downloaded dataset |
| `ip_address` | TEXT | Client IP |

- Wrap every `downloadHandler` in `R/mod_export.R` with a logging call: `INSERT INTO master.public_export.download_log ...` via DuckDB postgres write
- Build a read-only log viewer tab in `R/mod_admin.R` (db_manager/admin only): date-range filter, user filter, summary stats (downloads per dataset, per user, per month)

## Further Considerations

1. **PostgreSQL hosting**: Recommend **Supabase** (generous free tier, built-in auth extensions, Postgres 15+) or **Neon** (serverless, branching, free tier 0.5 GB) for initial deployment. AWS RDS for production scale.
2. **DuckDB postgres extension maturity**: Filter pushdown is experimental but enabled by default. For large tables, create local snapshots (`CREATE TABLE AS`) rather than querying remote on every interaction. Monitor `pg_connection_cache` and call `pg_clear_cache()` after schema changes.
3. **Offline-first workflow**: Confirmed — field users work on local DuckDB, `ATTACH` cloud on reconnect, sync-push goes through merge-request review. No connectivity required for day-to-day data entry.
4. **Public BECMaster access**: Recommend a **Plumber API** serving RDS/CSV files with download logging, plus a lightweight **Shiny viewer** for interactive exploration. Both read from `public_export.rds_snapshots`.
5. **Secrets management**: Use DuckDB `CREATE SECRET` with `SCOPE` for per-environment postgres credentials. Store secrets in environment variables (`PGHOST`, `PGUSER`, `PGPASSWORD`) — never in `config.yml` committed to git.
