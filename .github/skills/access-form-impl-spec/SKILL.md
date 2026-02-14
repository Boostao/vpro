---
name: access-form-impl-spec
description: Analyze Access SaveAsText form exports and produce implementation specs (FORM_IMPL_SPEC_<form>.md) with UI tree, event-to-VBA mapping, call/dependency tracing, and recursive subform coverage for AI reimplementation.
license: Proprietary - Internal project use only
---

# Access Form Implementation Spec

Use this skill when you need architectural documentation of how an Access form works so another AI agent can reimplement both UI and behavior in another framework.

This skill is optimized for downstream implementation agents, not human prose.

## Purpose

Generate a comprehensive implementation report next to each form export:

`VPRO_ACCESS/VPro64_forAI/Forms/FORM_IMPL_SPEC_<form>.md`

## Preconditions

1. Run from repository root.
2. Confirm script exists: `scripts/Tools/access_form_impl_spec.R`
3. Confirm form export file(s) exist in `VPRO_ACCESS/VPro64_forAI/Forms/`.

## Primary workflow

### Single form (recursive by default)

`Rscript "scripts/Tools/access_form_impl_spec.R" "VPRO_ACCESS/VPro64_forAI/Forms/<form>.txt"`

### Single form (disable recursive subform traversal)

`Rscript "scripts/Tools/access_form_impl_spec.R" --recursive=false "VPRO_ACCESS/VPro64_forAI/Forms/<form>.txt"`

### Entire forms directory

`Rscript "scripts/Tools/access_form_impl_spec.R" "VPRO_ACCESS/VPro64_forAI/Forms"`

## Event mapping conventions

- For any property named `On*` where value is `[Event Procedure]`, strip the `On` prefix.
- Control scope handler convention: `<ControlName>_<EventSuffix>`
- Form scope handler convention: `Form_<EventSuffix>`
- Examples:
  - `OnAfterUpdate` on `optAssignedSource` -> `Private Sub optAssignedSource_AfterUpdate()`
  - `OnMouseUp` on `cmdApply` -> `Private Sub cmdApply_MouseUp()`
  - `OnCurrent` on form -> `Private Sub Form_Current()`

Do not hardcode only specific events; apply this rule to every `On*` event property detected.

## Required analysis coverage

1. Parent-child UI tree for every form element (full nesting path).
2. Event bindings for every `[Event Procedure]` occurrence.
3. Event-to-logic trace:
	- handler location and line range
	- internal (same form file) procedure calls
	- external (Modules) call targets where found
4. Data/source bindings:
	- `RecordSource`, `ControlSource`, `RowSource`, and any other `*Source` contracts
	- inferred table/query objects referenced by SQL strings
5. Subforms recursively:
	- include subform architecture and generate subform specs
	- prevent infinite loops on recursive references

## Output contract (must be implementation-ready)

Each `FORM_IMPL_SPEC_<form>.md` must include:

- Form summary (name, caption, record source)
- Full parent-child tree
- Control source dependency table
- Event mapping table
- Generic event resolution rules
- Event-to-logic trace table
- Form-scope VBA procedure graph with local/external dependency split
- Data + module dependency notes
- Recursive subform references and generated specs
- Reimplementation guidance for framework migration

## Output checklist

For each run, report:
1. Input form(s)
2. Generated spec file(s)
3. Recursive subforms included/excluded
4. Any unresolved procedure references

When unresolved items exist, record actionable follow-up hooks (where to connect and expected behavior).
