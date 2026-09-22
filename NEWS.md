# vpro 0.0.0.9000

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
