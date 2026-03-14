# Nav Menu Module Completion - Subagent Bootstrap

Use this prompt pack to drive subagents through remaining `npt(...)` menu items until each item is linked to a real module UI and server implementation.

## Non-Negotiable Completion Rules
- Work one nav item at a time.
- Do not move to the next nav item until the current item is fully implemented.
- Do not return with `Deferred` placeholders for the assigned item.
- If any hook is unresolved, implement a working in-app fallback in the same module so behavior is usable now.
- Required wiring per item:
  - `ui.R`: `npt(..., mod = mod_<name>_ui("<id>"))`
  - `server.R`: `mod_<name>_server("<id>", state, con)`
  - `global.R`: `source("R/mod_<name>.R")`
- Required validation per item:
  - `Rscript -e "parse(file='R/mod_<name>.R')"`
  - `get_errors` on touched files
- If a subagent response contains lines like:
  - `Deferred: ...`
  - `placeholder status only`
  then immediately continue on the same module and finish those items before any next module.

## Master Subagent Prompt (Copy/Paste)
You are migrating one Access ribbon/nav item to a complete Shiny module in this repo.

Target nav item:
- value: `<VALUE>`
- label: `<LABEL>`
- Access source form: `<ACCESS_FORM>`
- Access launcher mapping: `<RIBBON_CASE_OR_HANDLER>`

Scope:
1. Implement `R/mod_<MODULE>.R` with `mod_<MODULE>_ui(id)` and `mod_<MODULE>_server(id, state, con)`.
2. Wire `ui.R`, `server.R`, and `global.R`.
3. Match Access behavior for the target form events first.
4. Do not leave deferred placeholders. If external dependency is missing, implement an in-module working fallback now.
5. Validate parse/errors and report exact file/line changes.

Hard stop condition:
- Do not stop at analysis.
- Do not stop with "Deferred" or "placeholder" for assigned behavior.
- Only finish when module is runnable and wired.

Return format:
1. Implemented behaviors (event mapping).
2. Files changed.
3. Validation results.
4. Remaining risks (only if non-blocking and not the assigned behavior).

## Enforcement Follow-up Prompt (Use when subagent returns deferred)
Continue the SAME module. Do not move to any next nav item.
You returned deferred or placeholder behavior for assigned functionality.
Implement those missing parts now and update the module until no deferred items remain for this nav target.
Then rerun parse/error checks and return updated completion only.

## Current Backlog (npt items without `mod = ...`)
- `colour_theme` | Colour-theme
- `user_setup` | User setup
- `user_log` | User log
- `project_new` | New Project
- `project_save_as` | Save As...
- `project_export_splinter` | Export Splinter Project
- `project_merge` | Merge Projects
- `project_compare` | Compare Two Projects
- `project_metadata` | Project Metadata
- `project_metadata_export` | Export Project Metadata
- `project_metadata_import` | Import Project Metadata
- `su_table_new` | New Site Unit Table
- `su_table_save_as` | Save As...
- `su_table_from_query` | SU Table From Filter Query
- `su_table_from_form_filter` | SU Table From Form Filter
- `su_table_from_environment` | Create Site Units From Environment Fields
- `su_table_compare_assignments` | Compare Plot Assignments
- `su_table_list_units_with_plots` | List Site Units With Plots
- `su_table_write_bec_master` | Write BEC Master into SU Table
- `hierarchy_new` | New Hierarchy Table
- `hierarchy_save_as` | Save As...
- `hierarchy_merge` | Merge Hierarchies
- `hierarchy_diagram` | Hierarchy Diagram
- `import_vpro_64_project` | VPro 64 Project
- `import_venus_5_0` | VENUS 5.0
- `data_turboveg` | TurboVeg
- `export_to_r` | R (rds)
- `export_to_turboveg` | TurboVeg
- `export_user_species_list` | User Species List
- `validate_data` | Validate Data
- `report_long_vegetation` | Long Vegetation
- `report_summary_vegetation` | Summary Vegetation
- `report_long_environment` | Long Environment
- `report_summary_environment` | Summary Environment
- `report_subzone_matrix_of_units` | Subzone Matrix of Units
- `report_hierarchy_diagram` | Hierarchy Diagram
- `report_print_plot_label` | Print a Plot Label
- `report_create_plot_locations_file` | Create Plot Locations File
- `report_show_plot_locations_google_earth` | Show Plot Locations in Google Earth
- `reference_site_environment_codes` | Site and Environment Codes
- `reference_species_name_codes` | Species Name and Codes Table
- `reference_attach_species_table` | Attach species table
- `reference_attach_code_list_table` | Attach code list table
- `reference_colour_theme` | Colour-theme
- `reference_user_setup` | User setup
- `reference_directories` | Directories
- `help_vpro_help` | VPro Help
- `help_service_packs` | VPro Service Packs
- `help_set_all_to_sample` | Set all to Sample
- `help_about_vpro` | About VPro

## Suggested Run Order
1. Finish Forms menu first (already started): `colour_theme`, `user_setup`, `user_log`.
2. Then Data menu items.
3. Then Reports menu items.
4. Then References.
5. Then Help.

Keep module names stable and explicit (example: `mod_colour_theme`, `mod_user_setup`, etc.).
