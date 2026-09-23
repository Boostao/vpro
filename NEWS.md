# vpro 0.0.0.9000

* `vpro_access_archive()` now preserves the character type of empty date columns during SQLite round-trip verification (Access archive).

* `vpro_diagnostic_classify()` calculates diagnostic labels from ordered, already-formatted site-unit codes without creating report queries or writing tables (V7mdlDiagnostic.Diagnostic calculation).
* `vpro_export_code()` marks missing six-column R-export codes with periods without changing blank or whitespace-only codes (V7mdlExportToR2.NullToPeriod).
* `vpro_profile_max_cover()` calculates a zero-bounded maximum across ten vegetation cover columns without modifying plot-profile state (V7mdlPlotProfiling.MadMax).

* `vpro_access_inspect()` and `vpro_access_archive()` inventory and archive local Access tables and their translated descriptions without changing the source; `vpro_access_promote_vp08()` separately promotes a verified eight-table VP08 family. Historical versions and schema drift remain archive-only until reviewed mappings exist.

* `vpro_project_create()` creates an empty VP08 project from bundled schemas and records the new-project event and reference-list versions atomically (V7mdlCreateTables.CreateTableSet and V7mdlAudit.LogNewProject).
* Bundled `VLists.db` now includes translated Access table descriptions in `_table_metadata`, and its conversion script preserves them.
* `vpro_project_save_as()` creates target indexes before copying project rows so foreign keys remain valid for newly created VP08 projects.

* `db_log_project()` now records Open/Close and reference-version changes atomically, fixes the missing connection on TableOfLists lookups, and notifies the UI only after successful audit writes (V7mdlAudit.LogProjectIn and LogProjectOut).

* `vpro_assigned_site_units()` lists project, active-SU, and master-list site-unit choices without returning SQL text or requiring UI state (V7mdlTableOfLists.AssignedSiteUnitList).

* `vpro_project_reference_versions()` reads the active project's recorded species and table-of-lists versions without global configuration or writes, and flags latest-timestamp ties as ambiguous (V7mdlAllSpecsTools.ProjectVersion and V7mdlTableOfLists.ProjectVersionTableOfLists).

* `vpro_validate_su_hierarchy()` returns unmatched active SU site units and unmatched level-11 hierarchy names without changing source tables or opening Excel (V7mdlReportValidation.Report4SuUnitsWoHierarchyUnits and Report4HierarchyUnitsWoSuUnits).

* `vpro_report_location()` returns plots with both coordinates from the active project or SU, applying the legacy longitude sign change without Excel automation (V7mdlReportLocation.ReportLocation).

* `vpro_terrain_combine()` concatenates three terrain-code components, ignoring missing values and returning a missing result for empty codes (V7mdlTerrain.CombineTerrain).
* `vpro_terrain_inspect_schema()` reports eight terrain field widths as matching, undersized, oversized, unknown, non-text, or missing without altering SQLite projects (V7mdlTerrain.TestTerrainFieldSize and SetTerrainFieldSize).
* `vpro_terrain_split()` extracts terrain-code components, treating `FG` as one surficial-material component for Venus export compatibility (V7mdlTerrain.SplitTerrain).

* `vpro_project_convert_succession()`, `vpro_project_succession_status()`, and `vpro_project_recover_succession()` add explicit, backed-up, transactional SQLite succession conversion and conservative partial-state recovery (V7mdlSuccession.Convert2Succession).

* `vpro_project_is_successional()` detects the `SuccessionYear` field on a project's SQLite vegetation table without modifying the project (V7mdlSuccession.SuccessionProject).

* `vpro_validate_vegetation_codes()` finds active-project vegetation species absent from the VPRO master list, optionally preserving the active-SU scope used by Access, and returns deterministic structured findings instead of opening Excel.
* `vpro_project_compare_schema()` compares the eight core tables of a SQLite project with the bundled VP08 template or a caller-supplied template and returns missing-field, declared-type, and declared-size differences as structured data.
* `vpro_presence_class()`, `vpro_presence_class_numeric()`, `vpro_prominence_class()`, `vpro_goldstream_class()`, and `vpro_significance_class()` provide vectorized Access-compatible report classifications; `vpro_round_minimum()` and `vpro_cap_percent()` provide stable numeric rounding and capping helpers.
* `vpro_coordinate_decimal()`, `vpro_coordinate_dms()`, and `vpro_coordinate_dm()` provide vectorized package-native coordinate conversion while preserving the original Access sign and missing-component conventions.
* Plot-domain CRUD now transactionally creates, renumbers, and deletes paired Env/Admin plots, creates/reads/updates/deletes `_Humus`, `_Mineral`, `_Other`, and vegetation child rows, and supports guarded audit restoration. Plot renumbering preserves project-family cascades and updates every SU attached to the context without adding an audit event; plot deletion removes the complete project row family and matching rows from every attached SU.
* Hierarchy lifecycle APIs now inspect, attach, activate, deactivate, recover, safely detach, and transactionally save independent hierarchy tables with non-destructive tree diagnostics.
* SU lifecycle APIs now inspect, attach, activate, deactivate, recover, safely detach, and transactionally save independent site-unit tables while preserving shared SQLite attachments. Explicit master metadata, permission callbacks, and provenance-bearing working copies replace Access name matching and its embedded password.
* Project lifecycle APIs now inspect and attach VP08 SQLite projects, activate coordinator-scoped compatibility views, guard detach operations, and transactionally save a project under a new name.
* `vpro_project_recover()` restores the configured current project at startup and falls back to an explicit Sample database when recovery fails.
* `run_vpro()` now launches the packaged application explicitly; attaching the package no longer starts Shiny or modifies the installed `bslib` package.
* `vpro_install()`, `vpro_data_install()`, and `vpro_config_install()` initialize user-owned storage without replacing existing files by default.
* `vpro_config_get()` and `vpro_config_set()` provide a YAML-backed replacement for settings historically stored in the Windows registry.
