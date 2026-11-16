---
name: user-facing-copy
description: Enforces CBC-level plain language (feature shape over tech stack), preserves BEC/VPro domain terminology, and applies the whatsNew / NEWS.md release notes condenser whenever drafting or reviewing user-facing text in app/frontend/, docs-src/, site/, README.md, ROADMAP.md, or r/.
---

# VPro User-Facing Copy & Release Notes Condenser

Load this skill whenever writing, editing, or reviewing text visible to ecologists, BEC analysts, field crews, or data custodians across:
- Desktop UI (`app/frontend/src/`, user-surfaced errors)
- Single-source in-app help, tours & release notes (`docs-src/*.json` compiled by `scripts/build-docs-src.mjs` into `app/resources/help_bundle.json`)
- Public release & docs portal (`site/build.mjs`, `site/src/*.mjs`, `README.md`, `ROADMAP.md`)
- R package metadata, vignettes, Quarto guides, `r/NEWS.md`, and `roxygen2` / `cli_abort` copy (`r/`)

Follow the full **User-Facing Voice & Plain-Language Lexicon ("CBC Standard")** and **Release Notes Condenser** in [`CONTRIBUTING.md`](../../../CONTRIBUTING.md#6-user-facing-voice--plain-language-lexicon-cbc-standard).

## Core Rules

1. **Lead with the ecological task and shape of the feature, never the tech stack:**
   - Replace rendering/storage/IPC/contract terms (`MapLibre`, `WebGPU`, `PMTiles`, `SQLite WAL`, `Wails`, `Svelte`, `Go`, `Sidecar`, `Auto-1..7`, `Schedule A`, `UTF-16 code units`, `IEEE-754 float32`, `BEGIN IMMEDIATE`, `SERIALIZABLE`, `__VPRO_*`, `LumpSpec`, `Diagnostic10.xla`) using the **Say This, Not That** table in `CONTRIBUTING.md`.
   - Keep real BEC & VPro domain terms (`FS882`, `SIVI`, `LMH25 (2023)`, `BECdb v13`, `BCPlantTaxonomy v19`, `rSMR`/`aSMR`/`rSNR`, `Site Unit`, `Hierarchy`, `Lumping`, `Presence Class`, `Domin-Krajina`, `PlotNumber`, `BECMaster`, `VENUS 5.0`, `TurboVeg 3`).
2. **Condense `whatsNew` (`docs-src/whats_new.json`) and `r/NEWS.md` before every release tag:**
   - Group changes into **4–7 workflow bullets** (never commit-by-commit lists or benchmark numbers).
   - Put the newest version at index `0` of `docs-src/whats_new.json`.
   - Never edit `app/resources/help_bundle.json` by hand — always run `node scripts/build-docs-src.mjs && node site/build.mjs && node --test scripts/tests/downloadPortal.test.cjs` after editing `docs-src/*.json`.
3. **Preserve test & accessibility invariants:**
   - Zero emojis (`\p{Extended_Pictographic}`) in `docs-src/`, `site/`, and `app/frontend/src/`.
   - Keep stable HTML/DOM IDs, `data-tour` selectors, and lockstep assertions in `app/frontend/tests/*.test.cjs`, `scripts/tests/downloadPortal.test.cjs`, `app/internal/lifecycle/helpservice_test.go`, and `r/tests/testthat/*.R` synchronized.
