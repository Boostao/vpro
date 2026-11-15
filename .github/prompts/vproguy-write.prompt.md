---
name: "vproguy-write"
description: "Draft or revise headless vpro R roxygen2 documentation, vignettes, Quarto BEC unit guides, NEWS.md release notes, or ecological and SQLite WAL data-safety warnings in VPro's field-first voice."
argument-hint: "Describe the function, vignette, Quarto BEC unit guide, release note, or ecological warning to draft or revise."
agent: "vproguy"
tools: [read, search]
---

# Write Headless `vpro` R Documentation in VPro Voice

Use the `vproguy` agent to draft or revise documentation for the headless `vpro` R Companion SDK & Scientific Analytics Package.

Supported output types:
- `roxygen2` function documentation (`@title`, `@param`, `@return`, `@details`, `@section Ecological & Data-Safety Cautions:`, `@examples`)
- package vignette or reproducible Quarto / `_targets` workflow tutorial
- Quarto BEC unit / BGC subzone guide narrative (`inst/reports/*.qmd`)
- `NEWS.md` release notes
- R condition / diagnostic warning text (`rlang::abort` / `rlang::warn`)

Before writing:
1. Inspect relevant domain oracle notes in `inst/doc-oracles/`, `/home/bruno/Work/VPRO_ACCESS/okf/`, and `/home/bruno/Work/MoF-Skeena-Research/`.
2. Reuse canonical BEC and VPro terminology (`PlotNumber` text, `VP08`, `*_SU`, `*_Hierarchy` `~` breakpoints, `*_Lump` `99%` cap, `rSMR`/`aSMR`/`rSNR`, Presence `I–V`, Domin-Krajina Significance `+`/`1–9`, `UserSiteUnit` vs `BECSiteUnit`).
3. State SQLite WAL concurrency and write-back boundaries plainly (read-only by default alongside `vpro_wails`; opt-in `BEGIN IMMEDIATE` write-back only to candidate/working tables with `<Project>_Audit` + `__VPRO_*` provenance, never mutating `Master*` or `USys*` tables).

Writing rules:
- Start from the ecologist's or analyst's scientific task.
- Prefer practical, verifiable wording over marketing language or generic software abstractions.
- Never write Shiny UI copy or Access GUI form-migration notes.
- Do not invent biography or unsupported historical claims.

Output requirements:
- State the chosen output type.
- Deliver the requested documentation cleanly formatted for R / `roxygen2` / Quarto.
- End with a short `VPro domain & safety check` confirming BEC terminology accuracy and data-safety disclosures.