## Plan: Site Unit Plot Picker

Replace the current plot-number dropdown with a two-step selector that uses the canonical SU table, but only for the active project: derive the current project's plot numbers from `Env`, keep only matching rows in `SU`, then show a Site Unit dropdown plus a PlotNumber datatable in an alternate sidebar view. Keep the app-level sidebar intact, swap its contents between main navigation and a dedicated Site Unit picker panel, and preserve the existing global plot state contract so the rest of the app continues to read `state$CurrSU` / `CurrPlotNumber` unchanged.

**Steps**
1. Confirm and preserve the state contract in the app shell: keep `state$CurrSU` and preference key `CurrPlotNumber` as the active plot for downstream modules, but stop treating `CurrPlotList` / `PrefSUTable` as the selected plot. Update the plan-of-record behavior so Site Unit changes only update Site Unit context and do not change the active plot until a table row is selected.
2. Refactor the sidebar container in `/Users/nicolas/Documents/GitHub/vpro/ui.R` so the existing app-level `sidebar(id = "context_sidebar")` remains in place, but its inner content is rendered conditionally as either the main navigation panel or a dedicated Site Unit picker panel. This avoids rewriting layout structure while satisfying the requirement to replace the whole side panel view.
3. In the dedicated picker panel, add a modern card-style layout with: current project/context summary, a `Site Unit` select control populated from project-scoped `SU` rows only, a `DT::datatable` listing only `PlotNumber` for the selected Site Unit, a clear selected/current-plot indicator, and a back button to restore the main sidebar view.
4. Replace the current `sel_su` flow in `/Users/nicolas/Documents/GitHub/vpro/server.R`: remove the `Env`-driven plot dropdown refresh, add a project-scoped Site Unit query that derives eligible plot numbers from `Env` for `state$CurrProject` and then filters `SU` to those plot numbers, add a reactive/query for plots by selected Site Unit within that same project-scoped subset, and wire DT row selection so only an explicit row click updates `set_su(state, plot_number)` and persists `CurrPlotNumber`.
5. Normalize selection updates from other parts of the app that currently write directly to `sel_su`, especially the hierarchy navigation in `/Users/nicolas/Documents/GitHub/vpro/R/mod_hierarchy.R`. Route those paths through the same current-plot update logic used by the new picker so cross-module navigation still works after `sel_su` is removed.
6. Rewire the existing `Site Unit Tree View` button so it opens the alternate sidebar picker view instead of navigating to the Hierarchy tab, and add a matching back action inside the picker. Keep existing Hierarchy tab buttons (`Site Unit Table`, `Hierarchy Tree View`) unchanged unless they are directly impacted by the selector refactor.
7. Update automated coverage that assumes a `sel_su` dropdown exists. Revise shinytest2 tests to set project, open the Site Unit picker, choose a Site Unit, select a plot row from the DT widget, and assert that the app state and downstream modules reflect the chosen plot.
8. Verify the UI manually and with targeted tests: project switch recalculates eligible plot numbers from `Env` and limits the visible Site Units to only those represented by those plots in `SU`, Site Unit change leaves current plot unchanged until row selection, row selection updates all plot-bound modules, hierarchy-triggered navigation still sets the current plot, and the alternate sidebar view remains usable on both desktop and mobile widths.

**Relevant files**
- `/Users/nicolas/Documents/GitHub/vpro/ui.R` — current app-level `page_navbar()` and `sidebar(id = "context_sidebar")`; this is where sidebar content swapping and the new picker/back controls will be anchored.
- `/Users/nicolas/Documents/GitHub/vpro/server.R` — current `refresh_su_dropdown()`, `observeEvent(input$sel_su, ...)`, and `btn_nav_su_tree` navigation; this is the main selector/state wiring to replace.
- `/Users/nicolas/Documents/GitHub/vpro/R/logic_state.R` — `set_su(state, plot_number)` and preference semantics; reuse this as the stable plot-selection contract.
- `/Users/nicolas/Documents/GitHub/vpro/R/mod_hierarchy.R` — existing hierarchy actions call `updateSelectInput(session$parent, "sel_su", ...)`; these call sites must be redirected to the new selection path.
- `/Users/nicolas/Documents/GitHub/vpro/tests/shinytest2/test-e2e-workflows.R` — multiple workflows currently set/read `sel_su` directly.
- `/Users/nicolas/Documents/GitHub/vpro/tests/shinytest2/test-data-entry.R` — data-entry tests depend on current plot selection.
- `/Users/nicolas/Documents/GitHub/vpro/tests/shinytest2/test-admin.R` — admin flows also set `sel_su` directly.
- `/Users/nicolas/Documents/GitHub/vpro/tests/shinytest2/test-smoke.R` and `/Users/nicolas/Documents/GitHub/vpro/tests/shinytest2/test-flow.R` — smoke/flow coverage currently assumes the old selector exists.

**Verification**
1. Run the app, choose a project, open `Site Unit Tree View`, and confirm the Site Unit dropdown is sourced from `SU.SiteUnit` filtered to rows whose `PlotNumber` belongs to the current project's plots in `Env`, not from all `SU` rows and not directly from `Env.plotnumber`.
2. Change project and verify the Site Unit list shrinks or expands to match only that project's `Env` plot set; then change Site Unit and verify the plot table refreshes while the previously active plot remains unchanged until a DT row is selected.
3. Select a plot row and verify downstream plot-bound modules load the selected plot via `state$CurrSU`, including FS882, Vegetation, Site/Env, Images, and Reports entry points.
4. Use hierarchy actions that previously updated `sel_su` and confirm they still move the app to the correct plot after the refactor.
5. Run targeted shinytest2 files covering selection and state persistence after updating them for the new UI flow.

**Decisions**
- Included: replacing the current sidebar plot dropdown with a Site Unit driven selector and alternate sidebar view.
- Included: modernizing the picker presentation within the existing bslib/BCGov visual system using cards, spacing, and a cleaner selection workflow.
- Excluded: redesigning the overall app shell, changing the meaning of `state$CurrSU`, or refactoring unrelated Hierarchy tab functionality.
- Confirmed with user: Site Unit changes should keep the current plot unchanged until the user explicitly selects a row.
- Confirmed with user: the plot table only needs a single `PlotNumber` column.

**Further Considerations**
1. Keep the implementation minimal by swapping sidebar contents inside the existing app sidebar rather than creating a new page/tab for the picker.
2. Prefer a shared server-side plot-selection helper during implementation so both the new picker and hierarchy navigation use one state-update path instead of duplicating `set_su()` + preference writes.
3. Preserve the current BCGov theme and make the new view feel modern through layout and interaction polish, not by introducing a separate design system.
