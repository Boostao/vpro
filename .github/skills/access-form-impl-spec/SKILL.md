````skill
---
name: access-form-impl-spec
description: Analyze Access SaveAsText form exports and produce implementation specs (FORM_IMPL_SPEC_<form>.md) with UI tree, event-to-VBA mapping, call/dependency tracing, and recursive subform coverage for AI reimplementation.
license: Proprietary - Internal project use only
---

# Access Form Implementation Spec

Use this skill when you need architectural documentation of how an Access form works so another AI agent can reimplement both UI and behavior in another framework.

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

- Control event: `<ControlName>_<EventSuffix>`
- Form-level event: `Form_<EventSuffix>`

## Output checklist

For each run, report:
1. Input form(s)
2. Generated spec file(s)
3. Recursive subforms included/excluded
4. Any unresolved procedure references

````
