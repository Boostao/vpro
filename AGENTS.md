# VPRO migration memory

## Architecture

- Canonical persistent data is SQLite distributed under `inst/extdata/` and copied to `rappdirs::user_data_dir("vpro")`.
- An in-memory DuckDB connection is the cross-SQLite composition layer. Installing `sqlite_scanner` must be explicit; package load must not require network access.
- Configuration replaces Access registry state and lives at `rappdirs::user_config_dir("vpro")/config.yml` by default.
- Package loading must not launch Shiny or modify another installed package. Use `run_vpro()` explicitly.
- New domain APIs must be callable without a Shiny session and pass connections/context explicitly.

## Canonical migration evidence

- Access SaveAsText root: `../VPRO_ACCESS/VPro64_forAI` (case-sensitive).
- Evidence order: observed Access behavior on a disposable VM copy, raw SaveAsText, Access data/metadata via `mdbr`, canonical SQLite/data-raw conversion, current package code, tests/generated artifacts, then `_TO_CLASSIFY`.
- The Windows VM may be used as a controlled oracle. (terminal: ssh win11vm)
- Production translations should cite the VBA module/procedure and explain intentional differences, without embedding full VBA routines.

## Parity tooling

- Run `Rscript data-raw/parity/run_inventory.R --source ../VPRO_ACCESS/VPro64_forAI --target . --output data-raw/parity/generated`.
- The initial deterministic inventory contains 360 Access objects and 4,130 object/procedure/event requirements. It creates an overview Mermaid tree and one tree per Access object.
- Machine matches are candidates only. Completion requires reviewed equivalence, reviewed intentional difference, approved retirement, or not-applicable status with evidence.
- Inventory every legacy feature and explicitly assign migrate, modernize, retain externally, defer, or retire.

## Current milestone

- Foundation APIs cover config/bootstrap, explicit app launch, DuckDB coordinator lifecycle, bundled database paths, and SQLite project-family discovery/validation.
- Project lifecycle APIs now cover `vpro_project_context()`, VP08 inspection and attachment, active-project temporary views, startup recovery with Sample fallback, guarded detach, context close, and transactional core-family save-as. They correspond to the project branches of `V7mdlAttachProjects`, `V7mdlSetCurrent`, `V7mdlSplash`, `V7mdlUnattach`, and `V7mdlSaveAs`.
- Activation persists `CurrProject`, resets `CurrPlotlist` to `None`, and persists the normalized SQLite `ProjectPath` when an explicit config accessor is supplied. It uses DuckDB temporary views instead of persistent Access QueryDef rewrites.
- Project save-as copies the eight core tables, rows, indexes, foreign keys, and `_table_metadata` records in a SQLite transaction. It intentionally validates all target-family collisions and forbids `Sample`.
- `vpro_project_recover()` restores the configured project non-interactively and falls back to an explicit Sample SQLite path on any attachment or activation failure. Successful activation persists the normalized path and resets the plot list.
- The bundled `Sample.db` is a complete VP08 core family. Integration validation creates all 11 compatibility views and confirms 52 `USysEnv` rows and 1,633 `USysVeg` rows.
- Project, SU, hierarchy, and plot-domain CRUD tests skip in clean offline checks when `sqlite_scanner` is not installed. The complete active package-native suite passes, including explicit master-SU authorization, same-database working-copy coverage, audit-history retrieval, child creation/deletion, and vegetation mutation. `R CMD check --no-manual` completes with 0 errors, 0 warnings, and 0 notes.
- Reviewed parity overrides live in `data-raw/parity/reviewed-overrides.csv`. After child lifecycle and vegetation CRUD, the regenerated inventory contains 475 target items, 43 reviewed mappings, and 4,087 unresolved source requirements; historical tests remain outside the active package inventory.
- Historical app/PostgreSQL/report tests and fixtures have been moved from `tests/` to `_TO_CLASSIFY/tests/`; `tests/testthat.R` now runs every remaining package-native test without a filter.
- The `_Env.StartDate` relationship drift is resolved: the Windows Access oracle confirms `_Env` has `Date` but no `StartDate`, no Env–Metadata relation exists, and replaying `V7mdlRelationships.CreateRelationship` fails at relation 6 with DAO 3799 after leaving relations 1–5 appended and before relation 7. Treat the declaration as stale VBA; do not add a SQLite Env–Metadata foreign key or reinterpret `Env.Date`.
- SU lifecycle APIs now implement `vpro_su_inspect()`, attachment without activation, diagnostic Env-SU-Admin activation, project-view restoration, guarded detachment, transactional save-as, and startup recovery. They preserve blank/orphan rows, report duplicate plot rows, reuse path-level shared SQLite attachments, and persist `Current.SUPath` because DuckDB attachments are ephemeral.
- Master SU status is explicit `_vpro_su_policy` metadata. `vpro_su_mark_master()` requires `manage_master_su`; direct attachment requires `attach_master_su`; master creation requires `create_master_su`; `vpro_su_create_working_copy()` creates a provenance-bearing inactive copy without attaching or mutating the master. Permission decisions come from an explicit context or operation callback, not Access username matching or the legacy embedded password.
- Project activation always deactivates the current SU and clears `SUPath`. Failed SU recovery leaves the recovered project active and unfiltered. The bundled `Sample_SU` activates 51 project plots with no blank or orphan plot rows.
- Hierarchy lifecycle APIs now implement `vpro_hierarchy_inspect()`, attachment without activation, explicit selection through a temporary `Hierarchy` view, deactivation, guarded detachment, transactional save-as, and startup recovery. Inspection reports root, blank-name, orphan-parent, and cycle diagnostics without mutation; metadata is reported but not version-gated because Access does not gate hierarchy attachment.
- Hierarchies share path-level SQLite attachment ownership with projects and SUs. Selection persists `Current.CurrHierarchy` and `Current.HierarchyPath`; project and SU activation do not implicitly change hierarchy selection. The bundled `Sample_Hierarchy` has 43 rows and VP04 metadata.
- Domain CRUD in `R/plot-crud.R` includes `vpro_plot_get()` for paired active-project Env/Admin rows, `vpro_plot_update()` for validated transactional changes with Access-compatible field audit rows, and read-only `vpro_plot_audit_list()` for project-and-plot-filtered canonical audit history in Access chronological order.
- Other-child CRUD in `R/plot-other.R` includes list, create, update, and delete APIs. Creation uses a collision-checked signed 32-bit ID, preserves Access-observed false defaults for `UserFlag1` through `UserFlag3`, and audits populated fields at strength 2 or 3. Deletion requires one `(PlotNumber, ID)` row and adds no audit record, matching the Windows oracle.
- Soil-child CRUD in `R/plot-soil.R` includes list, get, create, update, and delete APIs for Humus and Mineral. Rows use compound `(PlotNumber, ID)` identity; Humus follows descending `UpperDepth`/`Horizon` order and Mineral ascending order. Creation uses collision-checked IDs and child-ID audit rows; deletion adds no audit record.
- Vegetation CRUD in `R/plot-vegetation.R` includes list, get, create, update, and delete. The Windows oracle confirmed IDs are stable across species edits but duplicate IDs, including duplicate `(PlotNumber, ID)`, are permitted. Package operations therefore require exactly one plot-ID match and fail safely on ambiguity; generated IDs are collision-checked project-wide.
- Windows oracle evidence and reproducible probes are documented in `data-raw/projects/CRUD_ORACLE.md` and `data-raw/oracle/`. Bound forms generated signed 32-bit IDs before commit, audited populated/defaulted fields at strength 2, discarded canceled rows, and added no audit rows for deletion.
- Audit restoration remains deferred as a deliberate correction: the oracle confirmed `_Env` restoration targets the physical Env table, so Admin fields recorded as `_Env` cannot be restored, while `_Admin` has no `RestoreTo()` branch. A future package restore must resolve fields across Env/Admin schemas transactionally rather than reproduce this defect.
- Next CRUD work may implement the corrected bounded audit-restoration design or investigate plot creation/renumbering/deletion. Keep multi-table plot lifecycle mutations unresolved until observed.
