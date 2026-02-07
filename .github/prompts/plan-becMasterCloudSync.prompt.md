# Plan: VPro → BECMaster Cloud Sync & Data Management Platform

Migrate the current single-user, file-based VPro Shiny app to a hybrid local/cloud architecture where local DuckDB instances sync with a central **BECMaster PostgreSQL** database on the server, with role-based access control, data compliance validation, change-tracked merging, and public RDS data publishing.

## Steps

### 1. Design and deploy the BECMaster PostgreSQL schema

Translate all table schemas from `VPRO_ACCESS/VPro64_forAI/Tables_Def/` (plus VLists, VMetaData, VUser) into a PostgreSQL migration script. Add cloud-only tables: `users`, `roles`, `user_roles`, `merge_requests`, `merge_history`, `change_log`, `download_log`, `data_compliance_results`, and `rds_publish_snapshots`. Use a schema-per-concern layout (e.g., `core`, `lists`, `admin`, `public_export`).

### 2. Build a dual-connection data layer

Create a new `R/db_connections.R` module exposing `pg_connect()` (via `RPostgres`/`pool`) and the existing `duckdb_connect()`, with a config file (`config.yml` via the `config` package) for connection strings, environments (local/staging/prod). Refactor `global.R` and `server.R` to use this shared layer instead of hardcoded paths.

### 3. Implement data compliance validation engine

Create `R/logic_compliance.R` with rule functions checking mandatory field standards before any upload/merge:

- Required columns present and non-null (`PlotNumber`, `Species`, `ProjectID`, `Zone`, `SubZone`, etc.)
- Valid foreign-key references against `lists.USysTableOfLists` and `SppList`
- Numeric range checks on cover/coordinate/elevation values
- Species code format validation
- `PlotNumber` uniqueness

Return a structured report (pass/fail per rule with row-level detail). Wire a "Validate" button into a new upload UI.

### 4. Build the dataset upload & merge-request workflow

Create `R/mod_upload.R` with UI to upload CSV/ZIP packages of plot data. On upload: run the compliance engine (step 3), show results, and if passing, write data to a PostgreSQL `staging` schema with status `pending_review`.

Create `R/mod_merge.R` for database managers to review staged submissions: side-by-side diff of incoming vs. existing records (keyed on `PlotNumber`), accept/reject per-record, and on accept execute a transactional merge into the `core` schema writing full before/after change history to `change_log` (extending the existing `USysAudit` pattern from `VPRO_ACCESS/VUser/Tables_Data/`).

### 5. Build local ↔ cloud sync with change tracking

Create `R/logic_sync.R` implementing bi-directional sync: each record gets a `row_version` (integer) and `last_modified_utc` timestamp in both DuckDB and PostgreSQL. On sync-pull, fetch remote records newer than local `row_version`; on sync-push, upload local changes as a merge request (step 4). Conflict detection flags records modified in both since last sync. All sync operations log to `change_log` with `sync_id`, `direction`, `user_id`, `timestamp`, `table`, `pk`, `field`, `old_value`, `new_value`. Add a Shiny sync panel in `R/mod_admin.R` showing sync status, conflicts, and resolution UI.

### 6. Implement user accreditation & role-based access

Create `R/mod_auth.R` using `shinyauthr` (or custom token-based auth against the PostgreSQL `users`/`roles` tables). Define roles:

| Role | Permissions |
|------|-------------|
| `viewer` | Read-only public data |
| `field_user` | Enter/edit own plots |
| `project_lead` | Manage own project's plots |
| `db_manager` | Review merges, edit all data, manage codes |
| `admin` | Manage users/roles |

Gate every write operation in `R/mod_veg_sample.R`, `R/mod_site_env.R`, `R/mod_admin.R`, and the new upload/merge modules behind `req(user_has_role(...))` checks. Port the existing `USysUserRestrictions` concept from Access.

### 7. Build RDS public data publishing pipeline

Create `R/logic_publish.R` with a function `publish_becmaster_rds()` that:

1. Queries approved (`qa_status = 'approved'`) plot data from PostgreSQL
2. Applies lumping via `R/logic_lumping.R`
3. Pivots to the wide species matrix (reusing `R/mod_export.R` logic)
4. Joins environmental data
5. Writes compact `.rds` files (versioned with date stamp) to a configured output directory or cloud storage (S3/Azure Blob)

A `db_manager` triggers this from the admin panel; the resulting RDS files are served by a separate lightweight public Shiny app or API.

### 8. Record and store data download activity

Create a `download_log` table in PostgreSQL (`id`, `user_id`, `timestamp`, `dataset_name`, `format`, `filters_applied`, `row_count`, `ip_address`). Wrap every `downloadHandler` in `R/mod_export.R` and the public RDS endpoint with a logging call that inserts into this table before serving the file. Build a read-only log viewer in `R/mod_admin.R` for `db_manager`/`admin` roles with date-range filtering and summary statistics.

## Further Considerations

1. **PostgreSQL hosting**: Self-hosted VM vs. managed service (AWS RDS / Azure Database for PostgreSQL / Supabase)? Managed reduces ops burden; recommend **Supabase** or **AWS RDS** for built-in auth extensions and backups.
2. **Local open-source DB**: Should the local equivalent be DuckDB (current) or SQLite for broader tool compatibility? Recommend **keeping DuckDB** — it already works and handles the analytical query patterns well.
3. **Public BECMaster app**: Should public data access be a separate Shiny app, a Plumber API, or static RDS files on a download page? A **Plumber API + lightweight Shiny viewer** offers the most flexibility for programmatic and interactive access.
4. **Offline-first vs. online-required**: Should field users be able to work fully offline and sync later, or require connectivity? Recommend **offline-first with DuckDB** and sync-on-connect, matching current field workflow.
