# VPro64 → R/Shiny Migration Plan

## Status Snapshot (as of 2026-02-12)

**Goal**: Migrate the VPro64 Microsoft Access application (BC Gov ecosystem field data management) to **R/Shiny + DuckDB** (offline-first) with optional cloud sync to **PostgreSQL**.

**Core capabilities working now**
- Local DuckDB stack (multi-file topology + ATTACH patterns)
- Site/Env + Vegetation data entry modules
- Reporting (Quarto templates backed by R reporting logic)
- Export: CSV/RDS + Excel export pipeline
- Public browse: BEC Web Map Explorer + publishing pipeline to `data/published/`
- Docker-based deployment artifacts for client evaluation

**Highest-impact gaps (still in progress)**
- Audit trail parity (ensure all write paths are logged consistently)
- Import parity (CSV/ZIP breadth + specialized attach flows)
- Cloud workflow depth (veg push parity + richer merge-review diffs)
- VENUS/XML export: remaining Access field transforms
- UI regression breadth (expand shinytest2 coverage to full workflows)

---

## Yesterday’s Commits (2026-02-11) → Plan-Relevant Changes

This file was refreshed based on the Feb 11 commit series:
- Reports: completed VBA reporting logic port + expanded parity/smoke tests
- ClimR: climate integration + unit tests + integration guide
- BEC Web Map Explorer: new module + publishing scripts + demo published datasets + tests
- Deploy: Docker stack + env template + client-facing deployment docs
- Sync/Publish/Merge: incremental cloud attach/sync engine work + merge-review workflow + tests/docs
- Compliance/Coord tools: coord utilities + edge-case tests/docs
- Tests: shinytest2 E2E scaffolding + workflow tests + documentation

---

## Maintenance Workflow (How to Update This Plan)

Keep updates grounded in git history; keep details in dedicated docs.

### Step 1 — Inspect “yesterday” commits
- **Command**: `git log --since="yesterday 00:00" --until="today 00:00" --name-only`
- **Goal**: extract “themes” (Reports, ClimR, Deploy, etc.) and affected areas
- **Dependencies**: local git repo; correct system date/time

### Step 2 — Identify changes that belong here
- Include changes that affect **status**, **dependencies**, **risks**, or **next work**
- Prefer linking to authoritative docs rather than duplicating specs

### Step 3 — Edit this file only
- Update “Status Snapshot” and “Yesterday’s Commits”
- Update roadmap priorities + explicit file ownership

---

## Roadmap (Next Work)

### 1) Stabilization & Parity Hardening
- Audit middleware: ensure every INSERT/UPDATE/DELETE path is wrapped and logged consistently
- Compliance enforcement at boundaries (import, sync push, merge approval)
- Shiny UX reliability: keyboard-first flows, robust validation messages, NA/NULL safety

**Primary files**
- `R/logic_audit.R` plus write paths in modules (`R/mod_site_env.R`, `R/mod_veg_sample.R`, `R/mod_hierarchy.R`, `R/mod_admin.R`)
- `R/logic_compliance.R`

**Dependencies**
- Stable table schemas + consistent primary keys across local/cloud

### 2) Import Engine Completion
- Finish CSV/ZIP import parity (including specialized attach flows: hierarchy, user lists)
- Ensure import is compliance-gated and auditable

**Primary files**
- `R/mod_import.R`
- `R/logic_compliance.R`

**Dependencies**
- Clear supported-format expectations (CSV/ZIP first; legacy XML later)

### 3) Cloud Workflow Depth (Sync + Merge)
- Achieve veg push parity and improve reviewer diff tooling
- Make merge approval strict: compliance must pass and conflicts must be resolvable

**Primary files**
- `R/logic_sync.R`
- `R/mod_upload.R`, `R/mod_merge.R`, `R/mod_auth.R`

**Dependencies**
- Postgres availability + roles + schemas (`admin`, `staging`, `core`)

### 4) Export & Publishing Finishing
- VENUS/XML: complete remaining field transforms and legacy compatibility
- Publishing: finalize pipeline conventions (versioning/provenance) and validation

**Primary files**
- `R/logic_venus_export.R`, `R/mod_export.R`
- `R/logic_publish.R`

---

## Testing & Validation

**Test layers**
- `testthat`: unit tests for pure logic + DB helpers
- `shinytest2`: UI smoke + workflow regression tests

**Run commands**
- App: `Rscript -e "shiny::runApp('.', port = 3838)"`
- Unit tests: `Rscript -e "testthat::test_dir('tests/testthat')"`
- UI tests: `Rscript -e "shinytest2::record_test()"`

---

## Deployment (Client Evaluation)

Deployment artifacts exist for a repeatable Docker-based evaluation.

**Key artifacts**
- `Dockerfile`
- `docker-compose.deploy.yml`
- `.env.example`
- `deploy/README.md`

**Dependency notes**
- DuckDB is single-writer: don’t run build scripts while the Shiny app holds the write connection
- Cloud features require Postgres + DuckDB postgres extension support

---

## Reference Docs (Authoritative Detail)

- `README.md`
- `CLIMR_INTEGRATION_GUIDE.md`
- `BEC_MAP_README.md`
- `EXCEL_EXPORT_README.md` and `EXCEL_EXPORT_IMPLEMENTATION.md`
- `REPORTS_PORT_SUMMARY.md`
- `deploy/README.md` and `deploy/CLIENT_REVIEW_SCOPE.md`
