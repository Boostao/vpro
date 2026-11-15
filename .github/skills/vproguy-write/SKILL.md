---
name: vproguy-write
description: "Draft or revise headless vpro R roxygen2 documentation, vignettes, Quarto BEC unit guides, NEWS.md release notes, or ecological and SQLite WAL data-safety warnings in VPro's field-first voice."
disable-model-invocation: true
argument-hint: "Describe the function, vignette, Quarto BEC unit guide, release note, or ecological warning to draft or revise."
---
# Write Headless `vpro` R Documentation in VPro Voice

Use the `vproguy` agent to draft or revise documentation for the headless `vpro` R Companion SDK & Scientific Analytics Package (`r/` in `Boostao/vpro`).

Supported output types:
- `roxygen2` function documentation (`r/R/*.R`: `@title`, `@param`, `@return`, `@details`, `@section Ecological & Data-Safety Cautions:`, `@examples`)
- package vignette or reproducible Quarto / `_targets` workflow tutorial (`r/vignettes/`)
- Quarto BEC unit / BGC subzone guide narrative (`r/inst/quarto/*.qmd` & `app/internal/rsidecar/assets/*.qmd`)
- `r/NEWS.md` release notes
- R condition / diagnostic warning text (`rlang::abort` / `rlang::warn`)

Before writing:
1. Inspect relevant domain oracle notes and references in `okf/00_index.md`, `okf/02_present_state/oracles/`, `app/internal/diagnostics/`, `app/internal/reports/`, `app/internal/rsidecar/assets/`, `r/`, and `/home/bruno/Work/MoF-Skeena-Research/`.
2. Reuse canonical BEC and VPro terminology (`PlotNumber` text, `VP08`, `*_SU`, `*_Hierarchy` `~` breakpoints, `*_Lump` `99%` cap, `rSMR`/`aSMR`/`rSNR`, Presence `I–V`, Domin-Krajina Significance `+`/`1–9`, `UserSiteUnit` vs `BECSiteUnit`).
3. State SQLite WAL concurrency and write-back boundaries plainly (read-only by default alongside VPro Desktop `app/`; opt-in `BEGIN IMMEDIATE` write-back only to candidate/working tables with `<Project>_Audit` + `__VPRO_*` provenance, never mutating `Master*` or `USys*` tables; governed Cloud `BECMaster` staging/merge via `r/R/cloud_*.R`).

Writing rules:
- Start from the ecologist's or analyst's scientific task.
- Prefer practical, verifiable wording over marketing language or generic software abstractions.
- Never write Shiny UI copy or Access GUI form-migration notes.
- Do not invent biography or unsupported historical claims.

Output requirements:
- State the chosen output type.
- Deliver the requested documentation cleanly formatted for R / `roxygen2` / Quarto.
- End with a short `VPro domain & safety check` confirming BEC terminology accuracy and data-safety disclosures.