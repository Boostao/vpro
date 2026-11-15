# QMD report-template migration audit

The 18 templates in `inst/app/reports/` were inspected on 2026-09-23. This is a dependency audit, **not** an assessment of report calculation parity. The new standalone `inst/reports/quick_summary.qmd` is deliberately outside that legacy directory: it uses an explicit VP08 SQLite path and project prefix, calls `vpro_report_quick_summary()` through an activated package context, and renders HTML without the old application reporting UI. It does not change the UI or provide XLSX/PDF export.

| Existing templates | Legacy dependency | Action before package-native rendering |
| --- | --- | --- |
| `bec_labels`, `env_summary`, `lifeform`, `long_env`, `long_veg`, `short_veg`, `short_veg_env`, `short_veg_hierarchy`, `short_veg_order_hierarchy`, `site_summary`, `veg_layer_a`, `veg_layer_c`, `veg_layer_d` | All 13 source `R/logic_reports_veg.R`, now in `_TO_CLASSIFY/R/` rather than active `R/`. Four (`lifeform`, `long_veg`, `short_veg`, `short_veg_env`) also source the retired `logic_lumping.R`. | Review calculations and source data separately; no single active API replaces every legacy helper. |
| `flat_hierarchy`, `hierarchy`, `hierarchy_collapsible_tree`, `quality_control` | Open a persisted `vpro.duckdb` or use old `Sample_*` names. `hierarchy_collapsible_tree` has no Parquet export entry. | Port to explicit package contexts, SQLite hierarchy/project data, and tested report queries. |
| `field_checklist` | Static: no database or retired report helper. | Does not require a data-source migration. |

All 17 data-dependent QMDs refer to the old `../data/vpro.duckdb` path. Fourteen mention `Sample_Env`, `Sample_SU`, `Sample_Veg`, or `Sample_Hierarchy`, and 16 refer to Parquet execution. These are source-reference counts, not a claim that every reference is executed for every render. The canonical runtime instead persists SQLite files and uses an in-memory DuckDB coordinator; a DuckDB file at that old path is not a supported replacement. `inst/app/reports/_vpro_report_utils.R:215-262` still resolves and opens a persisted DuckDB file. The app reporting module supplies `getwd()/data/vpro.duckdb` and an explicit Parquet export mapping (`inst/app/modules/mod_reporting.R:114-162,633-635`). It exports names such as `Env`, `SU`, `Veg`, `Hierarchy`, whereas many QMDs load `Sample_*` filenames, so preview/export wiring also needs review. The extra `site_summary.Rmd` is not counted among QMDs.

## Package-native API coverage by template

The entries below describe **data API coverage**, not working templates or Access output parity. `vpro_report_environment()` reads the active `USysEnv` view: the view drops duplicate SU memberships, and unlike `V7mdlReportsEnv.EnvReport` it does not retain SU rows missing Env, group worksheets by site unit, or transpose Excel output. Other existing partial helpers include `vpro_report_all_veg()` (project-wide distinct union), `vpro_filter_plot_quality()` (active-SU selection), and `vpro_assigned_site_units()` (unit choices). `vpro_report_quick_veg()` uses a different layer range and SU scope from `vpro_report_all_veg()`.

| Legacy QMD | Existing package data API | Missing report-specific API or contract |
| --- | --- | --- |
| `bec_labels` | `vpro_report_environment()` provides active plot rows | Label-field/plot-selection contract and label-ready projection. |
| `env_summary` | `vpro_report_environment()`; `vpro_assigned_site_units()` partly supplies unit choices | Site-unit grouping and authoritative master-list long-name join; summary calculations. |
| `field_checklist` | None required | Static document; rendering/UI registration only. |
| `flat_hierarchy` | Hierarchy selection exposes the `Hierarchy` view | Node/tag ordering and flattened-tree projection; no report API. |
| `hierarchy` | Hierarchy lifecycle/selection only; `vpro_assigned_site_units()` supplies some list choices | Hierarchy tree and master-unit long-name enrichment contract. |
| `hierarchy_collapsible_tree` | Hierarchy lifecycle/selection only | Tree-node data contract including ordering and interactive output policy. |
| `lifeform` | `vpro_report_all_veg()` supplies unsummarized project-wide layers | Species attributes, lifeform aggregation, active-SU scope and lumping policy. |
| `long_env` | `vpro_report_environment()` supplies unsummarized Env/Admin view rows | Full field projection, site-unit headings and master-list join; Access `EnvReport` Excel layout is not migrated. |
| `long_veg` | `vpro_report_all_veg()` and `vpro_filter_plot_quality()` cover partial inputs | Joined vegetation/admin/environment rows, SU scope, threshold/lumping rules and long summary. |
| `quality_control` | `vpro_filter_plot_quality()` supplies selection/removal diagnostics; vegetation/environment validators cover separate checks | Combined QC report contract and species/plot diagnostics integration. |
| `short_veg` | `vpro_report_all_veg()` supplies unsummarized project-wide layers | SU-scoped grouping, lumping, thresholds and summary projection. |
| `short_veg_env` | `vpro_report_all_veg()` and `vpro_report_environment()` supply separate inputs | Combined per-plot join, SU scope and vegetation summary contract. |
| `short_veg_hierarchy` | `vpro_report_all_veg()` supplies layers | Hierarchy-enriched vegetation rows and group-summary contract. |
| `short_veg_order_hierarchy` | `vpro_report_all_veg()` supplies layers | Ordered hierarchy-enriched vegetation rows and group-summary contract. |
| `site_summary` | `vpro_report_environment()`, `vpro_report_all_veg()`, soil-child list APIs offer separate inputs | Site-level Env/soil/vegetation/reference-data assembly and section projection. |
| `veg_layer_a` | `vpro_report_environment()` supplies plot selection inputs; vegetation CRUD reads rows | Layer-A cover/height extraction, SU/plot selection and display contract. |
| `veg_layer_c` | Same partial inputs as `veg_layer_a` | Cover6/Height6 extraction, SU/plot selection and display contract. |
| `veg_layer_d` | Same partial inputs as `veg_layer_a` | Cover7 extraction, SU/plot selection and display contract. |

The detailed field/grouping review for `long_env` and the proposed SU-scoped `short_veg` summary contract are in `data-raw/projects/LONG_ENV_SHORT_VEG_CONTRACTS.md`. They identify unapproved edge-case policies and do not imply that either legacy template now renders package-native data.

The standalone `inst/reports/quick_summary.qmd` already calls `vpro_report_quick_summary()`. It is not one of these 18 legacy templates and is not integrated into the app reporting UI.

Recommended sequence: establish a report-specific package data contract; write one standalone template; render-test from an isolated directory with explicit project path; only then wire template parameters, data provisioning, and formats into the UI. The Quick Summary HTML QMD is the first such standalone slice. The separate legacy Excel path (`mod_reporting.R:927-937,993-1009`) is not provided by merely adding a QMD file.
