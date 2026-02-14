# GitHub Copilot Agent Instructions — VPRO (Block-by-Block)

## Orientation
Migrate VPro64 from Access to R/Shiny in small, collaborative blocks.
Do not attempt wholesale parity in one pass.

## Default Working Mode
1. Work on one block at a time.
2. Match Access behavior first, then optimize later.
3. Keep changes minimal and scoped.
4. Prefer manual validation for now (tests are optional unless explicitly requested).
5. Stop after each block with a short summary and next-block suggestion.

## Block Contract (Use This Every Time)
For each requested block:
1. **Access source**: identify exact form/module event(s) in `VPRO_ACCESS/VPro64_forAI`.
2. **Expected behavior**: restate only what that block must do.
3. **Implementation**: edit only necessary files.
4. **Manual check**: provide quick run/check steps (no test harness by default).
5. **Handoff**: list what changed and what remains.

## Scope Rules
- No extra features beyond the block.
- No broad refactors unless they unblock the block.
- No design/system rewrites unless requested.
- Preserve existing naming and UX language from Access captions/status text.

## Access-Parity Rules
- `VPRO_ACCESS/` is read-only canonical reference.
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

## Access Form Module Strategy
- For Access main-menu button migrations, create focused context modules that capture form-open intent and persist selection state.
- Keep Access form-open semantics in module server logic (for example: set `state$CurrForm`, `state$sysCurrForm`, and `Current/DataFormName` preference).
- Reuse existing destination tabs/modules for rendering whenever possible; add placeholders only for unresolved Access-only dependencies.

## Project Map (Minimal)
- App shell: `global.R`, `ui.R`, `server.R`
- Core logic: `R/logic_state.R`, `R/logic_*.R`
- Modules: `R/mod_*.R`
- Canonical Access reference: `VPRO_ACCESS/VPro64_forAI/`

## Validation Mode (Current)
- Default: source/load smoke + manual in-app verification.
- Run tests only when explicitly requested.

## Git / Commit Discipline
- Commit per completed block when asked.
- Stage only relevant files.
- Do not commit generated `.duckdb` artifacts.
- Keep commit messages scoped (example: `Sidebar: align cmbCurrSU semantics with Access`).

## Communication Style
- Be concise and implementation-first.
- Call out assumptions and mismatches quickly.
- If ambiguity exists, ask for one precise clarification and continue.

## Immediate Priority
Deliver Access-accurate workflows incrementally, block by block, with fast feedback.

## Form migration routing (mandatory)

When the user asks to migrate, port, adapt, reimplement, or modernize an Access form (UI + behavior), you MUST delegate execution to the subagent spec at:

`.github/subagents/access-form-migration.subagent.md`

Trigger this delegation for prompts containing intents such as:
- "migrate form"
- "reimplement Access form"
- "port form logic"
- "adapt this form to <framework/environment>"

## Delegation requirements

When using the subagent, include these inputs in the prompt:
- Target form path(s) in `VPRO_ACCESS/VPro64_forAI/Forms/`
- Target framework
- Target execution environment
- Any constraints (minimal/MVP, design-system restrictions, deployment/runtime constraints)

If framework/environment is unspecified, default to Shiny and state the assumption.

## Required skill usage during migration

The delegated migration MUST leverage both skills:
1. `access-form-impl-spec` for behavior/architecture contract (`FORM_IMPL_SPEC_<form>.md`)
2. `access-form-to-shiny-ui` for generated layout scaffold/reference (`ui_<form>.R`)

Do not claim feature parity unless event mapping, dependency tracing, and source bindings are implemented or explicitly deferred with placeholders.

## Missing dependency handling (mandatory)

If dependencies cannot be wired end-to-end:
- Add non-breaking placeholders/stubs in implementation.
- Clearly report unresolved hooks and expected integration points.
- Provide actionable next steps for completing hookup.