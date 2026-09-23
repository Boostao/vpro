# GitHub Copilot Agent Instructions — VPRO

## Orientation
Migrate VPro64 from Access to R/Shiny with Access-accurate behavior and complete requested work autonomously unless the user explicitly narrows scope.

## Default Working Mode
1. Continue implementation until the requested task is complete or a real blocker is reached.
2. Match Access behavior in Shiny paradigms.
3. Use incremental validation during execution, but do not stop at intermediate slices unless the user asks to pause.

## Execution Contract
For each requested task:
1. **Access source**: identify exact form/module event(s) in `../VPRO_ACCESS/VPro64_forAI` when Access parity is relevant.
2. **Expected behavior**: restate only what the requested work must do.
3. **Implementation**: edit only necessary files, but continue through connected runtime/test fixes needed to complete the task.
4. **Validation**: run the smallest meaningful verification needed to confirm the work.
5. **Handoff**: list what changed and what remains only when the requested task is actually complete or explicitly blocked.

## Scope Rules
- No extra features beyond the requested scope.
- No design/system rewrites unless requested.
- Preserve existing naming and UX language from Access captions/status text.

## Access-Parity Rules
- `../VPRO_ACCESS/` is read-only canonical reference.
- Port semantics, not just labels.
- Mirror event intent:
  - Access `GotFocus`/`Click` list refresh behavior
  - Access `Change`/`AfterUpdate` side effects
  - Access special options (`Attach`, `New`, `Unattach`, `None`, separators)
- Handle Access-to-R null differences explicitly (`Nz` vs `NA`/`NULL`).

## Technical Standards
- Shiny modules use `mod_<name>_ui(id)` and `mod_<name>_server(id, state, con)`.
- Business logic goes in `R/logic_*.R`; UI wiring stays in `mod_*` or `server.R`.
- Use safe SQL patterns (validated inputs, parameterized queries where possible).
- Use `lists.` prefix for attached list/reference tables.

## Database Runtime (Current)
- Canonical local storage is SQLite, not local DuckDB files.
- Canonical SQLite files live under `data/`, `data/pics/`, and `data/projects/`.
- Planned app runtime is an in-memory DuckDB connection with attached SQLite databases.
- Runtime-only cross-database queries/views belong in the in-memory DuckDB layer, not in the canonical SQLite initdb files.
- Do not propose local `.duckdb` files as the canonical backend unless the user explicitly asks for a historical or superseded plan.

## Access Form Module Strategy
- For Access main-menu button migrations, create focused context modules that capture form-open intent and persist selection state.
- Keep Access form-open semantics in module server logic (for example: set `state$CurrForm`, `state$sysCurrForm`, and `Current/DataFormName` preference).
- Reuse existing destination tabs/modules for rendering whenever possible; add placeholders only for unresolved Access-only dependencies.

## Project Map (Minimal)
- App shell: `global.R`, `ui.R`, `server.R`
- Core logic: `R/logic_state.R`, `R/logic_*.R`
- Modules: `R/mod_*.R`
- Canonical local DBs: `data/*.db`, `data/pics/*.db`, `data/projects/*.db`
- Canonical Access reference: `../VPRO_ACCESS/VPro64_forAI/`

## Validation Mode (Current)
- Default: source/load smoke + manual in-app verification.
- Run tests only when explicitly requested.

## Git / Commit Discipline
- Commit scoped changes when asked.
- Stage only relevant files.
- Do not commit generated `.duckdb` artifacts.
- Do not replace canonical SQLite storage with generated local `.duckdb` files unless explicitly requested.
- Keep commit messages scoped (example: `Sidebar: align cmbCurrSU semantics with Access`).

## Communication Style
- Be concise and implementation-first.
- Call out assumptions and mismatches quickly.
- If ambiguity exists, ask for one precise clarification and continue.

## Immediate Priority
Deliver Access-accurate workflows end-to-end with fast feedback, using intermediate validation without prematurely stopping implementation.

## Form migration execution (mandatory)

When the user asks to migrate, port, adapt, reimplement, or modernize an Access form (UI + behavior), execute the migration directly in the primary agent.

Default mode for migration requests is **strict parity**, not MVP. Do not silently downgrade to MVP unless the user explicitly requests MVP/minimal scope.

Use both skills in this order:
1. `access-form-impl-spec` for behavior/architecture contract (`FORM_IMPL_SPEC_<form>.md`)
2. `access-form-to-shiny-ui` for generated layout scaffold/reference (`ui_<form>.R`)
3. Targeted raw form lookups by line-range from spec trace tables

## Skill artifact retention (mandatory)

During migration, preserve generated skill artifacts under `/tmp` and do not delete them during the active migration session.

Default location:
- `/tmp/vpro_parity/<work_id>/`

Expected retained artifacts (at minimum):
- `FORM_IMPL_SPEC_<form>.md`
- `ui_<form>.R`
- parity notes/checklist (for example `PARITY_CHECKLIST_<work_id>.md`)

If a skill writes outputs under `../VPRO_ACCESS/.../Forms/`, copy the artifacts to `/tmp/vpro_parity/<work_id>/` immediately and keep that `/tmp` copy as canonical migration evidence for the task.

Do not parse whole Access form exports upfront as a primary discovery method.

Required migration inputs:
- Target form path(s) in `../VPRO_ACCESS/VPro64_forAI/Forms/`
- If a launcher/menu opens another form, include both launcher and destination form paths
- Target framework and execution environment (default to Shiny if unspecified)
- Constraints (minimal/MVP, design system, deployment/runtime)
- Explicit navigation contract in app runtime (trigger control + destination tab/module/form id)

Completion requirements:
- Apply concrete runtime code changes in app files (`R/mod_*`, `R/logic_*`, `ui.R`, `server.R`, `global.R`) for destination-form behavior
- Do not treat redirect-only changes as complete when destination implementation is requested
- Do not treat analysis-only output as complete
- Do not report success when no workspace files changed
- Do not defer, recursively implement, find solution and search for details to move forward.

Strict parity completion gates:
- Do not mark a task complete based only on startup or save/load smoke when deeper runtime behavior was in scope.
- Include a control/event parity checklist in handoff with `implemented | missing` status per item.

Do not claim feature parity unless event mapping, dependency tracing, and source bindings are implemented.

## Missing dependency handling (mandatory)

If dependencies cannot be wired end-to-end:
- Add non-breaking placeholders/stubs in implementation.
- Clearly report unresolved hooks and expected integration points.
- Provide actionable next steps for completing hookup.