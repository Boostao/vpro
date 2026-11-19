# GitHub Copilot Instructions — `Boostao/vpro` Monorepo

**Start at [`AGENTS.md`](../AGENTS.md) first**, then load the scoped contract for the directory you are modifying:

- **Desktop Workstation (`app/`):** [`app/AGENTS.md`](../app/AGENTS.md) $\rightarrow$ [`okf/05_engineering_and_agents/desktop_app_engineering.md`](../okf/05_engineering_and_agents/desktop_app_engineering.md)
- **Headless R Companion SDK (`r/`):** [`r/AGENTS.md`](../r/AGENTS.md) $\rightarrow$ [`okf/05_engineering_and_agents/r_sdk_engineering.md`](../okf/05_engineering_and_agents/r_sdk_engineering.md)
- **Specifications & Empirical Oracles (`okf/`):** [`okf/AGENTS.md`](../okf/AGENTS.md) $\rightarrow$ [`okf/00_index.md`](../okf/00_index.md) & [`okf/02_present_state/oracles/`](../okf/02_present_state/oracles/)

## Core Monorepo Guardrails

1. **Strict Subsystem Boundaries (`app/` + `r/` + `okf/`):**
   - **`app/` (`module github.com/boostao/vpro/app`):** Owns all interactive UI (Wails v3 + Go `1.27+` + Node `24+` + Svelte 5 + MapLibre GL JS v6/WebGPU + SQLite WAL + vendored C `libmdb`). Preserve the 4-layer acyclic `app/internal/*` DAG (zero sibling imports in Layer 2), strictly **12** registered Wails services in `app/main.go`, `-ts -i` TypeScript interface binding generation (`wails3 generate bindings -ts -i`), and `$state.snapshot(...)` proxy detachment before IPC.
   - **`r/` (Package `vpro`, `R >= 4.4.0`):** Strictly **headless** scientific analytics & stewardship SDK (`shiny`, `bslib`, `DT`, `rhandsontable`, `shinyTree`, `shinyjs`, `sass`, `leaflet`, and `rappdirs` are **forbidden** in `r/DESCRIPTION`). Default to `RSQLite::SQLITE_RO` / `query_only = ON` so R never blocks a live `app/` WAL session.
   - **`docs-src/`, `site/`, `scripts/`:** Single-source offline `F1` `LMH25 (2023)` help bundle authored in `docs-src/*.json` and compiled by `scripts/build-docs-src.mjs` $\rightarrow$ `app/resources/help_bundle.json`, plus BC Gov Design System static-manifest download portal (`site/build.mjs` $\rightarrow$ `site/dist`). Write all user-facing copy (`app/frontend/`, `docs-src/`, `site/`, `r/`) in plain CBC-level language and update `docs-src/whats_new.json` before release tags per [`CONTRIBUTING.md`](../CONTRIBUTING.md#6-user-facing-voice--plain-language-lexicon-cbc-standard). Keep `okf/` synchronized in place with code/export/policy changes (zero stray `.md` files outside allowlisted paths); historical files in `archive/oct2026-parity-ledgers/` and `archive/sep2026-r-prototype-notes/` never govern scope or feature flags.

2. **Shared `VP08`, Workspace & Cloud `BECMaster` Invariants:**
   - **Workspace Resolution:** `app/internal/sqlutil/sqlutil_foundation.go` (`UserDataDir`, `UserConfigDir`) and `r/R/workspace.R` (`vpro_data_dir`, `vpro_config_dir`) must match byte-for-byte across Windows, macOS, and Linux (`VPRO_DATA_DIR` / `VPRO_CONFIG_DIR` overrides first).
   - **`VP08` & BEC Math:** Preserve the 7-DB SQLite family (`<Project>.db`, `VPro64.db`, `VLists.db`, `VUser.db`, `VMetaData.db`, `VMessageBoard.db`, `VPics.db`), literal `TEXT`/`character` `PlotNumber` (`'00337'`), Access `BOOLEAN` (`-1` = true, `0` = false), IEEE-754 `float32` cover narrowing before `< 100`, `99%` lumped/fallback strata cover cap, ACE 15-sig-digit rounding (`1.005 -> 1.01`), `INT32` vs `INT16` `Lifeform`, `LayerCode.Layer1234567` short-veg joins, `LMH25 (2023)` horizon depth signs (`L/F/H` upward `UpperDepth DESC`; `Of/Om/Oh` & `A/B/C/R/W` downward `UpperDepth ASC`), and atomic `BEGIN IMMEDIATE` writes with `<Project>_Audit` + monotonic `__VPRO_*` child IDs.
   - **Cloud `BECMaster`:** `app/internal/cloudsync` and `r/R/cloud_*.R` share the 3-schema (`becmaster`, `staging`, `standards`) PostgreSQL/PostGIS contract with secret redaction, TLS on non-loopback hosts, pre-upload compliance gating, `SERIALIZABLE` Custodian 3-way merge, and SHA-256 hash-chained `becmaster.audit`.

3. **Targeted Validation Gates:**
   - **Desktop (`app/`):** `(cd app/frontend && npm test && npm run check && npm run build)` and `(cd app && GOTOOLCHAIN=go1.27.4+auto go test ./...)`
   - **R SDK (`r/`):** `bash scripts/format-r.sh && (cd r && Rscript -e "roxygen2::roxygenise()" && Rscript -e "testthat::test_local(stop_on_failure = TRUE)" && R CMD build . && R CMD check --no-manual vpro_*.tar.gz && rm -rf vpro_*.tar.gz vpro.Rcheck)` (`0 errors | 0 warnings | 0 notes`)
   - **Portal, Help & OKF Hygiene (`site/`, `scripts/`, `okf/`):** `python3 scripts/check-okf-hygiene.py`, `python3 scripts/check-dep-lockstep.py`, `python3 -m unittest discover -s scripts/tests -p 'test_*.py'`, and `node scripts/build-docs-src.mjs && node site/build.mjs && node --test scripts/tests/downloadPortal.test.cjs`
