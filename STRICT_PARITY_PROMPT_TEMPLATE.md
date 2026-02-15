# Strict Parity Block Prompt Template

Use this prompt at the start of a fresh session when migrating an Access form block with strict parity requirements.

---

## Copy/Paste Prompt

Implement **strict Access parity** for this block (not MVP/minimal):

- **Block ID:** `<BLOCK_ID>`
- **Launcher form(s):** `<launcher_form_paths_or_NA>`
- **Destination form(s):** `<destination_form_paths>`
- **Target app path(s):** `R/mod_*`, `R/logic_*`, `ui.R`, `server.R`, `global.R` as needed
- **Navigation contract:**
	- Trigger control: `<trigger_control_id>`
	- Destination tab/module/form id: `<destination_id>`

### Mandatory workflow
1. Use `access-form-impl-spec` first.
2. Use `access-form-to-shiny-ui` second.
3. Then do targeted raw Access reads by line range from spec trace tables.

### Artifact retention (mandatory)
- Preserve generated artifacts in `/tmp/vpro_parity/<BLOCK_ID>/`.
- Keep at minimum:
	- `FORM_IMPL_SPEC_<form>.md`
	- `ui_<form>.R`
	- `PARITY_CHECKLIST_<BLOCK_ID>.md`
- Do **not** delete `/tmp` artifacts during this block.

### Scope guardrails
- Do not add extra features beyond this block.
- Do not claim completion based only on startup/smoke/save-load.
- Do not mark complete if changes are redirect-only or analysis-only.

### Required output
1. **Access source mapped:** exact controls/events and handler ranges.
2. **Implementation files changed:** runtime files only.
3. **Parity checklist:** each targeted item as `implemented | deferred | missing`.
4. **Deferred dependencies:** clear placeholder + integration point.
5. **Validation performed:** commands run + result.
6. **Artifact paths:** exact files under `/tmp/vpro_parity/<BLOCK_ID>/`.

### Completion gate
Mark block **incomplete** unless all targeted controls/events are either:
- implemented in runtime code, or
- explicitly deferred with a placeholder and hookup note.

---

## Example Values

- `BLOCK_ID`: `fs882-site-shell-01`
- `launcher_form_paths_or_NA`: `VPRO_ACCESS/VPro64_forAI/Forms/frmMainMenuFloat.txt`
- `destination_form_paths`: `VPRO_ACCESS/VPro64_forAI/Forms/FS882-6x4XL.txt`
- `trigger_control_id`: `btn_nav_data_entry`
- `destination_id`: `FS882-6x4XL`
