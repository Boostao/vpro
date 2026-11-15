## Summary

<!-- Describe what changed and why. Reference any related issue or ROADMAP.md horizon. -->

## Affected Subsystems

- [ ] Desktop Workstation (`app/`)
- [ ] Headless R Companion SDK (`r/`)
- [ ] Help Bundle / Portal / Packaging (`docs-src/`, `site/`, `scripts/`)
- [ ] Operational Knowledge Framework / Governance (`okf/`, `.github/`, root docs)

## Domain & Architecture Invariants Checked

- [ ] Preserved shared `VP08` & BEC calibration rules (text `PlotNumber`, Access `-1/0/NULL` booleans, `float32` cover narrowing, `99%` lump/strata cap, ACE 15-sig-digit rounding, `LMH25` horizon depth signs, atomic `BEGIN IMMEDIATE` + `<P>_Audit`).
- [ ] Preserved `app/` 4-layer acyclic DAG (zero sibling Layer-2 imports) and **12** Wails domain services.
- [ ] If Go service signatures changed: ran `(cd app && wails3 generate bindings -ts -i)` and committed updated `app/frontend/bindings/`.
- [ ] If R exports/docs changed: kept `r/` 100% headless (no Shiny/widgets) and ran `roxygen2::roxygenise()` + tarball `R CMD check`.
- [ ] Cross-checked dependency lockstep (`python3 scripts/check-dep-lockstep.py`).

## Verification Run

```bash
# Paste the exact commands run and observed results
```
