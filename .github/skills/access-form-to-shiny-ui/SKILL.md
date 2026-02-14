```skill
---
name: access-form-to-shiny-ui
description: Convert Microsoft Access forms exported with Application.SaveAsText into Shiny UI R files using Tools/access_form_to_shiny.R. Use this when asked to migrate or scaffold Access form UI into Shiny.
license: Proprietary - Internal project use only
---

# Access Form to Shiny UI

Use this skill to convert Access form export files (`*.txt`, generated with `Application.SaveAsText`) into Shiny UI files (`ui_<form>.R`) while preserving visual layout metadata and control names.

## Preconditions

1. Work from the repository root.
2. Confirm the converter exists at `scripts/Tools/access_form_to_shiny.R`.
3. Confirm input file(s) exist in `VPRO_ACCESS/VPro64_forAI/Forms/` or another provided path.

## Primary workflow

1. `Rscript "scripts/Tools/access_form_to_shiny.R" "VPRO_ACCESS/VPro64_forAI/Forms/<form>.txt"`
2. Optional output path:
   `Rscript "scripts/Tools/access_form_to_shiny.R" "VPRO_ACCESS/VPro64_forAI/Forms/<form>.txt" "VPRO_ACCESS/VPro64_forAI/Forms/ui_<form>.R"`
3. Whole folder:
   `Rscript "scripts/Tools/access_form_to_shiny.R" "VPRO_ACCESS/VPro64_forAI/Forms"`

## Notes

- Preserve layout scaffold and control names where possible.
- Do not claim VBA/event logic has been migrated by this script.
- Report unsupported controls as placeholders.

```
