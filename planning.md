# VPro64 → R/Shiny Migration Plan

## Overview

Migrate the **VPro64 Microsoft Access** application (BC Government ecosystem field data management) to **R/Shiny + DuckDB**. The original application spans 5 linked Access databases, 105 forms, 118 VBA modules, 21 queries, 15 reports, and 82 data tables.

**Stack**: R ≥ 4.3 · Shiny + bslib · DuckDB (local) · PostgreSQL (optional cloud) · Quarto (reports) · testthat (tests)

---

## Latest Session: VBA Reporting Logic Port (Complete ✅)

**Date**: January 2025

**Completed**: Full VBA reporting logic migration from 14 Access modules to R

**Deliverables**:
- **4 new R modules** (1,772 lines production code):
  - `R/logic_reports_qc.R` (413 lines) — Quality control filtering, plot thresholds, NULL handling
  - `R/logic_reports_hierarchy.R` (408 lines) — Tree walking, path building, depth-first ordering, indentation
  - `R/logic_reports_env.R` (490 lines) — Environmental statistics (numeric/categorical summaries), transposition, 450+ field labels
  - `R/logic_reports_validation.R` (461 lines) — Data validation, reference list checking, species code validation, orphan detection

- **Comprehensive test suite** (1,022 lines, 53 tests):
  - `test-logic_reports_qc.R` (12 tests) — Quality thresholds, plot filtering, NULL inclusion/exclusion
  - `test-logic_reports_hierarchy.R` (13 tests) — Tree construction, path building, level stats, circular reference detection
  - `test-logic_reports_env.R` (12 tests) — Numeric stats, categorical summaries, plot filtering, field name resolution
  - `test-logic_reports_validation.R` (16 tests) — Env validation, species code checking, orphaned record detection

- **Integration**: All 15 Quarto report templates now backed by complete R functions with Access VBA formula parity

**Key fixes**:
- DuckDB SQL syntax (ListName case-sensitivity, table aliasing, NULL operator precedence)
- Schema-qualified table existence checks (information_schema queries vs dbExistsTable)
- Quality filter WHERE clause construction with compound conditions

**Testing**: All 53 tests passing ✅

**VBA→R Mapping Complete**: All 14 Access reporting modules (`V7mdlReports*`) now have R equivalents across 6 files (`logic_reports_veg.R`, `logic_report_export.R`, plus 4 new modules)

---

## Next Session Bootstrap: Deployment Stack (Client Evaluation)

**Goal**: Stand up a simple, repeatable deployment stack so the client can evaluate progress.

**Scope (recommended MVP)**
- Shiny app running in container
- DuckDB data mounted read-only for evaluation
- Optional PostgreSQL service for cloud features (staging/admin schemas)
- Basic health check + restart policy

**Checklist**
1. Decide deployment target: Docker Compose (local), VPS, or managed Shiny Server.
2. Add `Dockerfile` for the Shiny app (renv restore, system deps, app run command).
3. Add `docker-compose.yml` (app + optional postgres + volumes).
4. Wire config: environment variables for paths and cloud toggles.
5. Add `healthcheck` and minimal logging config.
6. Provide client run instructions and update README.

**Artifacts to create**
- `Dockerfile`
- `docker-compose.deploy.yml` (or extend existing compose)
- `.env.example` with required settings
- README deployment section

**Validation**
- Start stack, open app in browser, load reports, confirm read-only data access.
- (Optional) Attach postgres and confirm sync panels show "connected".

---

## Source Inventory (VPRO_ACCESS/)

| Database | Forms | Modules | Queries | Reports | Tables | DuckDB Target |
|----------|-------|---------|---------|---------|--------|---------------|
| **VPro64_forAI** | 105 | 118 | 21 | 15 | 82 | `vpro.duckdb` |
| **VLists** | 0 | 0 | 0 | 0 | 14 | `vpro_lists.duckdb` |
| **VMetaData** | 0 | 0 | 0 | 0 | 2 | `vpro_metadata.duckdb` |
| **VUser** | 0 | 0 | 0 | 0 | 11 | `vpro_user.duckdb` |
| **VMessageBoard** | 2 | 0 | 3 | 0 | 2 | `vpro_messages.duckdb` |
| **VTrees** | — | — | — | — | — | Not migrated |

---

## Current Progress

### ✅ Complete (Local DuckDB Stack)
- **Database build pipeline**: `scripts/01_build_database.R` ingests all 5 CSV sets → DuckDB files
- **Views**: `vw_USysAllVeg` (unpivot), `vw_USysEnv` (joined env) via `scripts/02_create_views.R`
- **Schema fixes**: `scripts/04_fix_metadata_schema.R`, `scripts/05_fix_spplist_schema.R`
- **Connection layer**: `R/db_connections.R` — factory, cloud ATTACH, helpers (323 lines)
- **Global state**: `R/logic_state.R` — `init_sys_state()`, `set_project()`, `set_su()` + VBA globals
- **Preferences persistence**: `R/logic_state.R` + `server.R` — SaveSetting/GetSetting analog stored in `vpro_user.duckdb`
- **Report options persistence**: `R/mod_reporting.R` — Report options wired to preferences (colour/gray thresholds, apply theme)
- **Vegetation entry**: `R/mod_veg_sample.R` — 4-layer tabs, CRUD, species modal (rhandsontable)
- **Site/Env entry**: `R/mod_site_env.R` — General/Mensuration/Soil tabs, full CRUD (rhandsontable)
- **Administration**: `R/mod_admin.R` — Project Metadata CRUD + Code Maintenance (240 lines)
- **Export**: `R/mod_export.R` — CSV/RDS with lumping and vegan pivot (130 lines)
- **Excel Export**: `R/logic_excel_export.R` — Styled Excel exports with Access-like formatting, conditional colors, multiple sheet organization (vegetation by layer, environment, soil, metadata), auto-sized columns, frozen headers; UI integrated in `mod_export.R` with options; template generator in `scripts/create_excel_template.R`; comprehensive tests in `test-logic_excel_export.R`
- **Images/Maps**: `R/mod_images.R` — Blob gallery + KML export (125 lines)
- **Reporting templates**: 15/15 Quarto templates created
- **Reporting logic**: Complete VBA port across 6 R modules (`logic_reports_veg.R`, `logic_report_export.R`, `logic_reports_qc.R`, `logic_reports_hierarchy.R`, `logic_reports_env.R`, `logic_reports_validation.R`) covering all 14 Access VBA reporting modules with 53 comprehensive tests (12 QC, 13 hierarchy, 12 env, 16 validation); includes quality filtering, hierarchy tree walking, environmental statistics, data validation, species/code checking, plot filtering, orphan detection
- **Lumping**: `R/logic_lumping.R` — `apply_lumping()` species synonym resolution (53 lines)
- **Veg data**: `R/logic_veg_data.R` — `get_vegetation_data()` with joins (50 lines)
- **Test infra**: `tests/testthat/` — setup, helpers (in-memory DuckDB), db_connections + core logic/module tests
- **Compliance engine**: rule set + tests in `R/logic_compliance.R`, wired to Import + Reports diagnostics
- **Coord tools**: `R/logic_coord_tools.R` — Complete DMS↔DD with NULL-safe Access `Nz()` parity, format detection, validation, UTM conversions (17 passing tests); integrated in `mod_site_env.R` with validation feedback
- **ClimR integration**: `R/logic_climr.R` — Climate data fetching from bcgov/climr package (MAT, MAP, MWMT, MCMT, DD5, AHM, SHM, NFFD, PAS, MSP, Eref, CMD), BEC zone prediction, elevation from DEM, coordinate-based caching, batch processing, graceful degradation when unavailable; UI integrated in `mod_site_env.R` with "Fetch Climate Data" button and auto-fetch on coordinate change; database persistence in Sample_Env (climr_* columns); 24 passing tests (8 skipped when package unavailable)
- **Keyboard shortcuts**: Ctrl+S / Ctrl+N via `shinyjs` (global save/new wiring)
- **Tab order**: Site/Env General + Mensuration explicit `tabindex`, Vegetation action buttons
- **Cloud infra**: docker-compose, PostgreSQL test schema, config.yml, DuckDB postgres ATTACH
- **App shell**: `global.R`, `ui.R` (6 nav_panels + sidebar), `server.R` (connection, state, module wiring)

### ⚠️ Partial
- **VENUS XML export**: schema-ordered columns + DMS derivations + prefixing + project filtering + alias mapping for Location/Comment/Comments; remaining Access field transforms and legacy exports still pending
- **Audit trail**: audit tabs + logging in `mod_site_env.R`/`mod_veg_sample.R` + hierarchy SU logging + master audit helper (user DB tables + project ID resolution); still missing middleware coverage for all writes + broader UI parity
- **Master site unit list tools**: admin master list editor present; still missing full validation, diff/merge tooling, and audit parity
- **Import engine**: CSV/ZIP + Access ODBC analyze/import, validation, compliance gating, replace mode, and schema-qualified lists; still missing specialized AttachHierarchy/UserList flows and non-CSV formats (XML/legacy)
- **Hierarchy tools**: tree CRUD, merge, clip, SU tools, tag support, orphan repair, and audit logging implemented; still missing full Access shortcut parity and UI polish
- **Diagnostics/QC**: diagnostic matrix + flags + Reports→Diagnostics tab wired; QC parity rules and tuning still incomplete
- **UI regression tests**: shinytest2 smoke + tab navigation + basic flow coverage; full workflow and data-entry tests pending
- **Cloud sync**: `R/logic_sync.R` pull/push helpers + state tables + conflict tracking + admin resolution UI + compliance enforcement on push; still missing full veg push parity and reviewer workflow depth
- **Upload/Merge workflow**: `R/mod_upload.R`, `R/mod_merge.R` staging UI, validation, compliance status, and basic merge actions (approval blocked on compliance failure); still missing comprehensive diffing and review controls
- **Auth/RBAC**: `R/mod_auth.R` login + permission checks wired into upload/merge/publish; still missing user provisioning and persistence
- **RDS publishing**: `R/logic_publish.R` pipeline + admin publishing panel in `mod_admin.R` with unit tests; still missing offline fallbacks and end-to-end coverage

### 🔲 Not Started / Remaining
- **Tests**: full end-to-end workflow coverage (data entry, import, merge approval), conflict resolution UI tests, and deeper report parity tests

### Known mismatches
- Report templates are all present, but VBA parity and parameter logic are still partial.
- Audit and diagnostic logic exist, but UI parity and field coverage are not complete.
- VENUS/XML export is implemented but missing remaining Access field transforms.
- UI tests cover smoke + tab navigation + basic flow; full flow coverage is pending.

---

## Phase 1: Foundation Hardening (Current → Solid Base)

**Goal**: Make core data entry robust and testable before adding new features.

### 1.1 Global State Completeness
- **Source**: `VPRO_ACCESS/VPro64_forAI/Modules/V7mdlGlobalDeclarations.txt`
- **Status**: Complete (globals aligned with Access declarations)
- **Test**: `tests/testthat/test-logic_state.R`

### 1.2 Null Safety Audit
- **Scope**: All `R/mod_*.R` and `R/logic_*.R` files
- **Action**: Search for bare arithmetic on DB-sourced values; wrap in `coalesce()` or `replace(x, is.na(x), default)`
- **✅ Done**: Coordinate math in `mod_site_env.R` (DMS→DD via `logic_coord_tools.R` with comprehensive NULL guards)
- **Priority**: Cover aggregation in `mod_veg_sample.R`

### 1.3 Test Suite Expansion
- `test-logic_state.R`: init, set_project, set_su with edge cases (done)
- `test-logic_lumping.R`: synonym resolution, missing codes, empty tables (done)
- `test-logic_veg_data.R`: wide→long, layer filtering, NA covers (done)
- `tests/shinytest2/`: UI smoke, tab navigation, and basic flow coverage (done)
- `test-mod_veg_sample.R`: Shiny module test with `testServer()` (done)
- `test-mod_site_env.R`: form load, save, coord conversion (done)
- `test-mod_import.R`: CSV/ZIP analysis, validation gating, compliance rollback (done)
- `test-views.R`: `vw_USysAllVeg` row counts, `vw_USysEnv` schema (done)
- **Remaining**: end-to-end workflow tests (data entry -> save -> sync), merge approval, conflict resolution UI, and full report parity assertions

### 1.4 Keyboard Navigation & Accessibility
- Add `shinyjs::useShinyjs()` for Tab/Enter key handling
- Ensure tab order in forms matches Access form tab order (check `TabIndex` in form exports)
- Add keyboard shortcuts for common actions (Save: Ctrl+S, New: Ctrl+N)

---

## Phase 2: Data Integrity & Validation

### 2.1 Compliance Engine — `R/logic_compliance.R`
  - Mandatory fields: PlotNumber, ProjectID, Zone, SubZone non-null
  - FK validation: species codes → `lists.SppList`, zones/subzones → `lists.USysZoneList`, list-driven fields → `lists.USysTableOfLists`
  - Range checks: latitude (48–60), longitude (−140 to −114), elevation (0–4000), slope (0–100), aspect (0–360), cover (0–100)
  - Cover code validation: allow numeric or text codes (`+`, `r`, `P`)
  - Non-negative checks: rooting depth, seepage depth, SV depth fields, active layer depth
  - Uniqueness: no duplicate PlotNumber per project, no duplicate PlotNumber+Species+Layer in veg
- **Output**: `list(passed, summary_tibble, detail_tibble)` — wire to UI badges
- **Test**: `test-logic_compliance.R`

### 2.2 Audit Trail — `R/logic_audit.R`
- **Source**: `V7mdlAudit` — logs before/after values on every field edit
- **Action**: Implement as middleware pattern — wrap `dbExecute()` writes with diff logging
- **Storage**: `vpro_user.duckdb` → `USysAuditTrail` table (matches Access schema)
- **UI**: Audit tab in `mod_site_env.R` and `mod_veg_sample.R` (already stubbed)

---

## Phase 3: Import Engine

### 3.1 CSV/ZIP Import — `R/mod_import.R`
- **Source**: 9× `V7mdlAttach*` + 6× `V7mdlImport*` modules
- **Functionality**:
  - Accept CSVs (single table) or ZIP archives (multi-table VPro export format)
  - Parse uploaded file(s), validate column names against DuckDB schema
  - Run compliance engine (Phase 2) before inserting
  - Show preview table with row counts and validation status
  - Insert into `vpro.duckdb` on user confirmation
- **Submodules** (priority order):
  1. Import VPro projects (CSV/ZIP) — core data entry backup restore
  2. Import SU tables (`V7mdlAttachSU`)
  3. Import hierarchy (`V7mdlAttachHierarchy`)
  4. Import species lists (`V7mdlImportUserLists`)
  5. Import from other formats (FileMaker, VENUS XML — lower priority)

---

## Phase 4: Hierarchy & Classification

### 4.1 Hierarchy Module — `R/mod_hierarchy.R`
- **Source**: `V7mdlHierarchyTools`, `V7mdlHierarchyShortcutFunctions`, `V7mdlClipHierarchy`, `V7mdlMergeHierarchies`, `V7mdlSUTableTools1/2`
- **Forms**: `frmHierarchyTree`, `frmHierarchyEdit`, `frmSUTable`
- **Core features**:
  - Tree view of `Sample_Hierarchy` (parent→child recursive)
  - Add/move/delete nodes with cascade updates
  - Merge two hierarchies (preview + duplicate handling + rekeyed merge)
  - Copy subtree to clipboard, paste into another hierarchy
  - Sibling ordering + MyOrder updates
  - Find/search shortcuts + breadcrumb path helpers
  - Orphan detection + repair tools
  - Clip hierarchy view + below-breaks view (lowest breakpoints)
  - Site unit table editor linked to hierarchy nodes + env sync + filter-based SU builders + master list
- **UI**: `shinyTree` or `jsTreeR` for interactive tree; `rhandsontable` for SU table editing
- **Test**: `test-mod_hierarchy.R` — tree CRUD, merge logic, orphan detection

---

## Phase 5: Reporting System

### 5.1 Port Access Reports → Quarto Templates
- **Source**: `VPRO_ACCESS/VPro64_forAI/Reports/` (15 reports) + `Modules/V7mdlReports*.txt` (14 modules)
- **Priority order**:

| # | Access Report | Quarto Template | VBA Module |
|---|--------------|-----------------|------------|
| 1 | `USysSiteUnitReport` | ✅ `site_summary.qmd` | `V7mdlReportsSiteUnitDetail` |
| 2 | Short veg table | ✅ `reports/short_veg.qmd` | `V7mdlReportsShortVeg` |
| 3 | Long veg table | ✅ `reports/long_veg.qmd` | `V7mdlReportsLongVeg` |
| 4 | Environment summary | ✅ `reports/env_summary.qmd` | `V7mdlReportsEnv` |
| 4a | Long environment | ✅ `reports/long_env.qmd` | `V7mdlReportsEnv` |
| 5 | Short veg + env | ✅ `reports/short_veg_env.qmd` | `V7mdlReportsShortVegEnv` |
| 6 | QC report | ✅ `reports/quality_control.qmd` | `V7mdlReportsQualityControl` |
| 7 | Lifeform summary | ✅ `reports/lifeform.qmd` | `V7mdlReportsLifeform` |
| 8 | Hierarchy diagram | ✅ `reports/hierarchy.qmd` | `V7mdlReportsHierarchyDiagram` |
| 9 | Flat hierarchy | ✅ `reports/flat_hierarchy.qmd` | `V7mdlReportFlatHierarchy` |
| 10 | BEC labels | ✅ `reports/bec_labels.qmd` | (simple label formatting) |
| 11 | Short veg + hierarchy | ✅ `reports/short_veg_hierarchy.qmd` | `V7mdlReportsShortVegHierarchy` |
| 12 | Short veg ordered by hierarchy | ✅ `reports/short_veg_order_hierarchy.qmd` | `V7mdlReportsShortVegOrderHierarchy` |
| 13 | Veg Layer A | ✅ `reports/veg_layer_a.qmd` | `USysVegA` |
| 14 | Veg Layer C | ✅ `reports/veg_layer_c.qmd` | `USysVegC` |
| 15 | Veg Layer D | ✅ `reports/veg_layer_d.qmd` | `USysVegD` |

### 5.2 Report UI Enhancement — `R/mod_reporting.R`
- Report type selector (dropdown of available .qmd templates) ✅
- Parameter inputs per report type (project, plot range, layer filters)
- Download as PDF or HTML ✅
- Download as Excel (xlsx) with report tables (parity with Access export workflow)
- Preview pane (rendered HTML inline) ✅
- Report options persistence (colour/gray thresholds, apply theme) ✅

---

## Phase 6b: Access → Shiny Parity Review (Planned)

**Goal**: Produce a clear, client-friendly parity report that shows what is done, partial, and missing, and why certain design choices were made.

### 6.0 Parity Matrix + Acceptance Criteria (In Progress)

**Acceptance Criteria (Definition of Done)**
- **Workflow parity**: Access and Shiny complete the same task with equivalent steps and outcomes (save, edit, delete, export) using representative data.
- **Data integrity parity**: DB writes match Access rules (required fields, ranges, FK checks, null handling) and audit trail captures before/after values.
- **Report parity**: Output tables match Access for filters, ordering, grouping, and totals; document defaults align with VBA.
- **Error parity**: User-facing validation messages and blocking behaviors mirror Access intent.
- **Test parity**: Each parity item has at least one automated check (testthat or shinytest2) or a documented manual verification.

**Parity Matrix (High-Impact Workflows)**

| Area | Access Artifact | Shiny Target | Status | Remaining Gap |
|------|----------------|--------------|--------|----------------|
| Project + Plot selection | `frmMainMenuFloat` | `ui.R` selectors | ✅ | Edge-case validation for empty projects |
| Site/Env save | `frmSIVIsite` + VBA | `mod_site_env.R` | ⚠️ | DMS/Nz guard parity + audit middleware coverage |
| Vegetation data entry | `frmVegSample` + subforms | `mod_veg_sample.R` | ⚠️ | Edge-case cover codes + audit middleware coverage |
| Audit trail | `V7mdlAudit` | `logic_audit.R` + tabs | ⚠️ | Wrap all write paths + UI parity details |
| Compliance/QC | `V7mdlDiagnostic` | `logic_compliance.R` + Reports tab | ⚠️ | QC rule tuning + parity of messages |
| Import CSV/ZIP | `V7mdlAttach*` | `mod_import.R` | ⚠️ | AttachHierarchy/UserList + XML/legacy |
| Hierarchy tools | `frmHierarchyTree` + modules | `mod_hierarchy.R` | ⚠️ | Shortcut parity + UI polish + audit coverage |
| Reporting (short/long veg) | `V7mdlReportsShortVeg/LongVeg` | `logic_reports_veg.R` + `short_veg.qmd`/`long_veg.qmd` | ✅ | VBA logic ported with 53 comprehensive tests |
| Reporting (env + QC) | `V7mdlReportsEnv/QC` | `logic_reports_env.R` + `logic_reports_qc.R` + templates | ✅ | All 14 VBA modules ported, tested, integrated |
| Reporting (hierarchy) | `V7mdlReportsHierarchyDiagram` | `logic_reports_hierarchy.R` + `hierarchy.qmd` | ✅ | Tree walking, ordering, formatting complete |
| Reporting (validation) | `V7mdlReportsValidateEnvData/VegCodes` | `logic_reports_validation.R` + templates | ✅ | Environmental + species validation with tests |
| VENUS/XML export | `V7mdlExportVenus/XML` | `mod_export.R` | ⚠️ | Remaining field transforms + legacy formats |
| Cloud sync push/pull | `V7mdl*` sync workflows | `logic_sync.R` + admin UI | ⚠️ | Veg push parity + reviewer depth |
| Upload/Merge review | merge request workflow | `mod_upload.R`/`mod_merge.R` | ⚠️ | Diff tooling depth + reviewer UX |
| Auth/RBAC | `frmLogin` | `mod_auth.R` | ⚠️ | User provisioning + persistence |
| RDS publishing | export workflow | `logic_publish.R` + admin UI | ⚠️ | Offline fallback + end-to-end test |

### 6.1 Parity Inventory (Full)
- Forms: map Access forms to Shiny modules; status: done / partial / missing
- Modules: map VBA modules to `R/logic_*.R` and `R/mod_*.R`; status + notes
- Reports: map Access reports + VBA report modules to Quarto templates; status + gaps

### 6.2 Workflow Parity (Field-first)
- Project selection, plot selection, data entry, save, and export flows
- Vegetation + Site/Env workflows (happy path + edge cases)
- Import/export workflows (CSV/ZIP/VENUS/XML) and audit/compliance behavior

### 6.3 Client Design Decisions (Plain Language)
- Offline-first behavior (why DuckDB is used locally)
- Cloud sync optionality and how it preserves field workflows
- Single-table model keyed by ProjectID (why no per-project schemas)
- Data safety and audit trail approach

## Phase 7: Cloud Integration

Detailed architecture in `.github/prompts/plan-becMasterCloudSync.prompt.md`. Summary:

### 7.1 Sync Engine — `R/logic_sync.R`
- Pull: cloud `core.*` → local DuckDB (row_version comparison)
- Push: local changes → `staging.*` via merge-request workflow
- Conflict detection + admin resolution UI (still needs full veg push parity)

### 7.2 Upload & Merge — `R/mod_upload.R`, `R/mod_merge.R`
- Upload: file → validate → stage
- Merge: reviewer diff view → accept/reject → promote to `core` (compliance status visible; full diff tooling pending)

### 7.3 Auth — `R/mod_auth.R`
- Roles: viewer, field_user, project_lead, db_manager, admin
- Session-based auth against PostgreSQL `admin.users`
- Gate write operations per role

### 7.4 RDS Publishing — `R/logic_publish.R`
- Snapshot approved data → versioned `.rds` files
- Download logging to `public_export.download_log`

---

## VBA Module → R Target Map (Complete)

### Core Data Entry & Navigation
| VBA Module | R Target | Status |
|-----------|----------|--------|
| `V7mdlGlobalDeclarations` | `R/logic_state.R` | ✅ |
| `V7mdlSetCurrent` | `R/logic_state.R` (`set_project`, `set_su`) | ✅ |
| `V7mdlFormTools` | Inline in `server.R` / modules | ⚠️ Partial |
| `V7mdlMenuCommands` | `ui.R` navbar + module routing | ✅ |
| `V7mdlRibbon*` (6 modules) | Not applicable (no ribbon in Shiny) | N/A |

### Vegetation
| VBA Module | R Target | Status |
|-----------|----------|--------|
| `V7mdlLumping` | `R/logic_lumping.R` | ✅ |
| `V7mdlLumpingAttributes` | `R/logic_lumping.R` | ⚠️ Partial |
| `V7mdlOptimizeVeg` | `R/logic_veg_data.R` | 🔲 |
| `V7mdlVegProfiling` | `R/mod_veg_sample.R` or new module | 🔲 |
| `V7mdlSetAllToSample` | Inline in `mod_veg_sample.R` | 🔲 |

### Export / Import
| VBA Module | R Target | Status |
|-----------|----------|--------|
| `V7mdlExportToR1` | `R/mod_export.R` | ✅ |
| `V7mdlExportToR2` | `R/mod_export.R` | ✅ |
| `V7mdlExportCompactNew` | `R/mod_export.R` | ✅ |
| `V7mdlExportVenus` | `R/mod_export.R` (extend) | ⚠️ Partial |
| `V7mdlExportXML` | `R/mod_export.R` (extend) | ⚠️ Partial |
| `V7mdlExportVPro03/13/15` | Low priority (legacy formats) | 🔲 |
| `V7mdlVtabImportExport` | `R/mod_import.R` | ⚠️ |
| `V7mdlAttach*` (9 modules) | `R/mod_import.R` | ⚠️ |
| `V7mdlImport*` (6+ modules) | `R/mod_import.R` | ⚠️ |

### Reporting
| VBA Module | R Target | Status |
|-----------|----------|--------|
| `V7mdlReportCombo1/2` | `R/mod_reporting.R` (parameter UI) | ✅ |
| `V7mdlReportsCommonCode` | Shared Quarto helpers | ⚠️ Partial |
| `V7mdlReportsShortVeg` | `reports/short_veg.qmd` | ⚠️ Partial |
| `V7mdlReportsLongVeg` | `reports/long_veg.qmd` | ⚠️ Partial |
| `V7mdlReportsEnv` | `reports/env_summary.qmd` | ⚠️ Partial |
| `V7mdlReportsShortVegEnv` | `reports/short_veg_env.qmd` | ⚠️ Partial |
| `V7mdlReportsShortVegHierarchy` | `reports/short_veg_hierarchy.qmd` | ⚠️ Partial |
| `V7mdlReportsShortVegOrderHierarchy` | Combine with above | ⚠️ Partial |
| `V7mdlReportsSiteUnitDetail` | `reports/site_summary.qmd` | ⚠️ Partial |
| `V7mdlReportsValidateEnvData` | `R/logic_compliance.R` | ⚠️ Partial |
| `V7mdlReportsValidateVegCodes` | `R/logic_compliance.R` | ⚠️ Partial |
| `V7mdlReportsQualityControl` | `reports/quality_control.qmd` | ⚠️ Partial |
| `V7mdlReportsLifeform` | `reports/lifeform.qmd` | ⚠️ Partial |
| `V7mdlReportsHierarchyDiagram` | `reports/hierarchy.qmd` | ⚠️ Partial |
| `V7mdlReportFlatHierarchy` | `reports/flat_hierarchy.qmd` | ⚠️ Partial |

### Hierarchy & Classification
| VBA Module | R Target | Status |
|-----------|----------|--------|
| `V7mdlHierarchyTools` | `R/mod_hierarchy.R` | ⚠️ |
| `V7mdlHierarchyShortcutFunctions` | `R/mod_hierarchy.R` | ⚠️ |
| `V7mdlClipHierarchy` | `R/mod_hierarchy.R` | ⚠️ |
| `V7mdlMergeHierarchies` | `R/mod_hierarchy.R` | ⚠️ |
| `V7mdlSUTableTools1/2` | `R/mod_hierarchy.R` or `mod_admin.R` | ⚠️ |
| `V7mdlMasterUnitListTools` | `R/mod_admin.R` (extend) | ⚠️ |

### Utilities & System
| VBA Module | R Target | Status |
|-----------|----------|--------|
| `V7mdlUtility` | Various helpers inline | ⚠️ Partial |
| `V7mdlAPICalls` | Not applicable (no Win32 API) | N/A |
| `V7mdlBackup` | `R/logic_backup.R` (DuckDB file copy) | 🔲 |
| `V7mdlAudit` | `R/logic_audit.R` | ⚠️ Partial |
| `V7mdlDiagnostic` | `R/logic_compliance.R` | ⚠️ Partial |
| `V7mdlCoordTools` | Inline in `mod_site_env.R` | ⚠️ |
| `V7mdlGoogleEarth` | `R/mod_images.R` (KML section) | ✅ |
| `V7mdlSpellCheck*` | Not ported (browser handles spellcheck) | N/A |
| `V7mdlServicePack` | Not applicable (use Git/releases) | N/A |
| `V7mdlQuitVPro` | `onSessionEnded()` in `server.R` | ✅ |
| `V7mdlTableOfLists` | `R/mod_admin.R` (Code Maintenance tab) | ✅ |

### Classes
| VBA Class | R Target | Status |
|----------|----------|--------|
| `clsConstancy` | `R/logic_constancy.R` | 🔲 |
| `clsExport` | `R/mod_export.R` | ✅ |
| `clsFormInfo` | Not applicable (Shiny handles) | N/A |
| `clsPicture` | `R/mod_images.R` | ✅ |
| `clsRepOpt` | `R/mod_reporting.R` (report params) | ⚠️ |
| `clsStopWatch` | Not needed (R profiling tools) | N/A |
| `clsSystem` | `R/logic_state.R` | ⚠️ |
| `clsVProMessages` | `R/mod_messages.R` | 🔲 |
| `clsVProReg` | `config.yml` + `vpro_user.duckdb` | ✅ |

---

## Form → Module Map (Complete)

### Primary Data Entry Forms
| Access Form | R Module | Notes |
|------------|----------|-------|
| `frmMainMenuFloat` | `ui.R` sidebar + `page_navbar` | ✅ Context selectors |
| `frmVegSample` | `R/mod_veg_sample.R` | ✅ 4-layer tabs |
| `SubVegA` (Trees) | Embedded in `mod_veg_sample.R` | ✅ rhandsontable/DT |
| `SubVegB` (Shrubs) | Embedded in `mod_veg_sample.R` | ✅ |
| `SubVegC` (Herbs) | Embedded in `mod_veg_sample.R` | ✅ |
| `SubVegD` (Moss/Lichen) | Embedded in `mod_veg_sample.R` | ✅ |
| `frmSIVIsite` / `FS882-6x4` | `R/mod_site_env.R` | ✅ General/Mens/Soil tabs |
| `SoilHumus` subform | Embedded in `mod_site_env.R` | ✅ |
| `SoilMineral` subform | Embedded in `mod_site_env.R` | ✅ |

### Administration Forms
| Access Form | R Module | Notes |
|------------|----------|-------|
| `frmProjectMetaData` | `R/mod_admin.R` | ✅ CRUD |
| `frmTableOfLists` | `R/mod_admin.R` (Code Maintenance) | ✅ |
| `frmPlotPictures` | `R/mod_images.R` | ✅ Gallery + KML |

### Hierarchy Forms
| Access Form | R Module | Notes |
|------------|----------|-------|
| `frmHierarchyTree` | `R/mod_hierarchy.R` | ⚠️ Tree view |
| `frmHierarchyEdit` | `R/mod_hierarchy.R` | ⚠️ Node editor |
| `frmSUTable` | `R/mod_hierarchy.R` | ⚠️ SU table editor |
| `frmMoveNodeCopy` | Modal in `mod_hierarchy.R` | ⚠️ |

### Dialog / Popup Forms → Shiny Modals
| Access Form | R Implementation | Notes |
|------------|-----------------|-------|
| `frmPickItem` | `showModal(modalDialog(...))` | ✅ Partial (in mod_veg) |
| `frmAddSpp` | `showModal()` in `mod_veg_sample.R` | ✅ |
| `frmLumpTable` | Modal in `mod_admin.R` or `mod_export.R` | 🔲 |
| `frmTypeAhead*` | `selectizeInput(server = TRUE)` | ⚠️ Partial |

### System / Operational Forms → Not Migrated (replaced by R/Shiny architecture)
| Access Form | Replacement |
|------------|-------------|
| `frmSplash` | Shiny startup loading screen |
| `frmProgress` | `shiny::withProgress()` |
| `frmDirectories` | `config.yml` |
| `frmAbout` | Modal or footer text |
| `frmLogin` | `R/mod_auth.R` (Phase 7) |
| `frmServicePack` | Git releases |
| `frmDiagnostic` | `R/logic_compliance.R` outputs |

### Report Parameter Forms
| Access Form | R Implementation |
|------------|-----------------|
| `frmReportCombo1` | `R/mod_reporting.R` parameter inputs |
| `frmReportCombo2` | `R/mod_reporting.R` parameter inputs |
| `frmRepOpt*` | Report option modals |

---

## Milestones & Rough Timeline

| Phase | Scope | Est. Effort | Depends On |
|-------|-------|-------------|------------|
| **1** | Foundation hardening (state, null safety, tests, keyboard) | 2 weeks | — |
| **2** | Compliance engine + audit trail | 2 weeks | Phase 1 |
| **3** | Import engine (CSV/ZIP) | 2 weeks | Phase 2 |
| **4** | Hierarchy & classification tools | 3 weeks | Phase 1 |
| **5** | Reporting (14 remaining Quarto templates) | 3 weeks | Phase 1 |
| **6b** | Access → Shiny parity review | TBD | Phases 4–5 |
| **7** | Cloud sync, auth, upload/merge, publishing | 4 weeks | Phase 2–3 |

Phases 4 and 5 can run in parallel. Phase 7 builds on 2–3.

---

## Decision Log

| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-01 | R/Shiny over Electron/React | Target users = non-dev forestry staff; R is domain standard |
| 2026-01 | DuckDB over SQLite | Multi-file ATTACH, analytical queries, postgres extension |
| 2026-01 | bslib (Bootstrap 5) for UI | Modern, accessible, tabbed layout matches Access |
| 2026-01 | Quarto over RMarkdown | Active development, better HTML/PDF, parameterized |
| 2026-01 | rhandsontable for subforms | Excel-like editing for field users (over DT editable) |
| 2026-02 | Single DuckDB connection engine | DuckDB postgres ATTACH eliminates need for RPostgres/pool |
| 2026-02 | Merge-request workflow for cloud writes | Field users push changes through review, not direct to production |
