# VPro64 → R/Shiny Migration Plan

## Overview

Migrate the **VPro64 Microsoft Access** application (BC Government ecosystem field data management) to **R/Shiny + DuckDB**. The original application spans 5 linked Access databases, 105 forms, 118 VBA modules, 21 queries, 15 reports, and 82 data tables.

**Stack**: R ≥ 4.3 · Shiny + bslib · DuckDB (local) · PostgreSQL (optional cloud) · Quarto (reports) · testthat (tests)

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

### ✅ Complete
- **Database build pipeline**: `scripts/01_build_database.R` ingests all 5 CSV sets → DuckDB files
- **Views**: `vw_USysAllVeg` (unpivot), `vw_USysEnv` (joined env) via `scripts/02_create_views.R`
- **Schema fixes**: `scripts/04_fix_metadata_schema.R`, `scripts/05_fix_spplist_schema.R`
- **Connection layer**: `R/db_connections.R` — factory, cloud ATTACH, helpers (323 lines)
- **Global state**: `R/logic_state.R` — `init_sys_state()`, `set_project()`, `set_su()` + VBA globals
- **Vegetation entry**: `R/mod_veg_sample.R` — 4-layer tabs, CRUD, species modal (rhandsontable)
- **Site/Env entry**: `R/mod_site_env.R` — General/Mensuration/Soil tabs, full CRUD (rhandsontable)
- **Administration**: `R/mod_admin.R` — Project Metadata CRUD + Code Maintenance (240 lines)
- **Export**: `R/mod_export.R` — CSV/RDS with lumping and vegan pivot (130 lines)
- **Images/Maps**: `R/mod_images.R` — Blob gallery + KML export (125 lines)
- **Reporting**: `R/mod_reporting.R` — Single Quarto template (65 lines)
- **Lumping**: `R/logic_lumping.R` — `apply_lumping()` species synonym resolution (53 lines)
- **Veg data**: `R/logic_veg_data.R` — `get_vegetation_data()` with joins (50 lines)
- **Test infra**: `tests/testthat/` — setup, helpers (in-memory DuckDB), db_connections + core logic/module tests
- **Keyboard shortcuts**: Ctrl+S / Ctrl+N via `shinyjs` (global save/new wiring)
- **Tab order**: Site/Env General + Mensuration explicit `tabindex`, Vegetation action buttons
- **Cloud infra**: docker-compose, PostgreSQL test schema, config.yml, DuckDB postgres ATTACH
- **App shell**: `global.R`, `ui.R` (6 nav_panels + sidebar), `server.R` (connection, state, module wiring)

### ⚠️ Partial
- **Global state**: remaining VBA globals to verify against `V7mdlGlobalDeclarations`
- **Coord tools**: DMS↔DD conversion inline in `mod_site_env.R` — needs `Nz()` safety audit
- **VENUS XML export**: Button exists in UI, logic not ported
- **Reporting**: 1/15 Access reports recreated as Quarto template
- **Compliance engine**: initial rules + tests in `R/logic_compliance.R` + Site/Env UI summary
- **Audit trail**: base helpers + logging for veg/soil/header edits + basic Audit tabs

### 🔲 Not Started
- **Hierarchy tools**: 5 VBA modules → `R/mod_hierarchy.R` (basic tree CRUD)
- **Import engine**: 12+ VBA modules → `R/mod_import.R` (UI shell + file preview + column checks)
- **Diagnostics/QC**: `V7mdlDiagnostic`, validation reports → `R/logic_compliance.R`
- **Audit trail**: `V7mdlAudit` → `R/logic_audit.R`
- **Cloud sync**: `R/logic_sync.R` (architecture in `.github/prompts/plan-becMasterCloudSync.prompt.md`, stub added)
- **Auth/RBAC**: `R/mod_auth.R` (UI shell)
- **Upload/Merge workflow**: `R/mod_upload.R`, `R/mod_merge.R` (UI shells)
- **RDS publishing**: `R/logic_publish.R` (stub added)
- **14 remaining report types**: Short/Long veg, Env, Hierarchy diagram, QC, Lifeform, etc.
- **Tests**: remaining module and report tests (view tests + compliance tests done)

---

## Phase 1: Foundation Hardening (Current → Solid Base)

**Goal**: Make core data entry robust and testable before adding new features.

### 1.1 Global State Completeness
- **Source**: `VPRO_ACCESS/VPro64_forAI/Modules/V7mdlGlobalDeclarations.txt`
- **Action**: Port remaining ~23 global variables to `R/logic_state.R`
- **Key additions**: `sysCurrHierarchy`, `sysCurrSuTable`, `sysConstancyTable`, `sysVegProfilePercent`, `sysCoordMethod`, diagnostic flags
- **Test**: `tests/testthat/test-logic_state.R`

### 1.2 Null Safety Audit
- **Scope**: All `R/mod_*.R` and `R/logic_*.R` files
- **Action**: Search for bare arithmetic on DB-sourced values; wrap in `coalesce()` or `replace(x, is.na(x), default)`
- **Priority**: Coordinate math in `mod_site_env.R` (DMS→DD), cover aggregation in `mod_veg_sample.R`

### 1.3 Test Suite Expansion
- `test-logic_state.R`: init, set_project, set_su with edge cases
- `test-logic_lumping.R`: synonym resolution, missing codes, empty tables
- `test-logic_veg_data.R`: wide→long, layer filtering, NA covers
- `test-mod_veg_sample.R`: Shiny module test with `testServer()`
- `test-mod_site_env.R`: form load, save, coord conversion
- `test-views.R`: `vw_USysAllVeg` row counts, `vw_USysEnv` schema

### 1.4 Keyboard Navigation & Accessibility
- Add `shinyjs::useShinyjs()` for Tab/Enter key handling
- Ensure tab order in forms matches Access form tab order (check `TabIndex` in form exports)
- Add keyboard shortcuts for common actions (Save: Ctrl+S, New: Ctrl+N)

---

## Phase 2: Data Integrity & Validation

### 2.1 Compliance Engine — `R/logic_compliance.R`
- **Source**: `V7mdlDiagnostic`, `V7mdlReportsValidateEnvData`, `V7mdlReportsValidateVegCodes`, `V7mdlReportsQualityControl`
- **Rules**:
  - Mandatory fields: PlotNumber, ProjectID, Zone, SubZone non-null
  - FK validation: species codes → `lists.SppList`, zones → `lists.USysZoneList`, dropdown values → `lists.USysTableOfLists`
  - Range checks: latitude (48–60), longitude (−140 to −114), elevation (0–4000), cover (0–100 or text codes)
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
  - Merge two hierarchies
  - Copy subtree to clipboard, paste into another hierarchy
  - Site unit table editor linked to hierarchy nodes
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
| 5 | Short veg + env | ✅ `reports/short_veg_env.qmd` | `V7mdlReportsShortVegEnv` |
| 6 | QC report | ✅ `reports/quality_control.qmd` | `V7mdlReportsQualityControl` |
| 7 | Lifeform summary | `reports/lifeform.qmd` | `V7mdlReportsLifeform` |
| 8 | Hierarchy diagram | `reports/hierarchy.qmd` | `V7mdlReportsHierarchyDiagram` |
| 9 | Flat hierarchy | `reports/flat_hierarchy.qmd` | `V7mdlReportFlatHierarchy` |
| 10 | BEC labels | `reports/bec_labels.qmd` | (simple label formatting) |
| 11–15 | Remaining | As needed | Various |

### 5.2 Report UI Enhancement — `R/mod_reporting.R`
- Report type selector (dropdown of available .qmd templates) ✅
- Parameter inputs per report type (project, plot range, layer filters)
- Download as PDF or HTML ✅
- Preview pane (rendered HTML inline) ✅

---

## Phase 6: Cloud Integration

Detailed architecture in `.github/prompts/plan-becMasterCloudSync.prompt.md`. Summary:

### 6.1 Sync Engine — `R/logic_sync.R`
- Pull: cloud `core.*` → local DuckDB (row_version comparison)
- Push: local changes → `staging.*` via merge-request workflow
- Conflict detection and resolution UI

### 6.2 Upload & Merge — `R/mod_upload.R`, `R/mod_merge.R`
- Upload: file → validate → stage
- Merge: reviewer diff view → accept/reject → promote to `core`

### 6.3 Auth — `R/mod_auth.R`
- Roles: viewer, field_user, project_lead, db_manager, admin
- Session-based auth against PostgreSQL `admin.users`
- Gate write operations per role

### 6.4 RDS Publishing — `R/logic_publish.R`
- Snapshot approved data → versioned `.rds` files
- Download logging to `public_export.download_log`

---

## VBA Module → R Target Map (Complete)

### Core Data Entry & Navigation
| VBA Module | R Target | Status |
|-----------|----------|--------|
| `V7mdlGlobalDeclarations` | `R/logic_state.R` | ⚠️ 7/30 |
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
| `V7mdlExportVenus` | `R/mod_export.R` (extend) | 🔲 |
| `V7mdlExportXML` | `R/mod_export.R` (extend) | 🔲 |
| `V7mdlExportVPro03/13/15` | Low priority (legacy formats) | 🔲 |
| `V7mdlVtabImportExport` | `R/mod_import.R` | 🔲 |
| `V7mdlAttach*` (9 modules) | `R/mod_import.R` | 🔲 |
| `V7mdlImport*` (6+ modules) | `R/mod_import.R` | 🔲 |

### Reporting
| VBA Module | R Target | Status |
|-----------|----------|--------|
| `V7mdlReportCombo1/2` | `R/mod_reporting.R` (parameter UI) | ⚠️ |
| `V7mdlReportsCommonCode` | Shared Quarto helpers | 🔲 |
| `V7mdlReportsShortVeg` | `reports/short_veg.qmd` | 🔲 |
| `V7mdlReportsLongVeg` | `reports/long_veg.qmd` | 🔲 |
| `V7mdlReportsEnv` | `reports/env_summary.qmd` | 🔲 |
| `V7mdlReportsShortVegEnv` | `reports/short_veg_env.qmd` | 🔲 |
| `V7mdlReportsShortVegHierarchy` | `reports/short_veg_hierarchy.qmd` | 🔲 |
| `V7mdlReportsShortVegOrderHierarchy` | Combine with above | 🔲 |
| `V7mdlReportsSiteUnitDetail` | ✅ `reports/site_summary.qmd` | ✅ |
| `V7mdlReportsValidateEnvData` | `R/logic_compliance.R` | 🔲 |
| `V7mdlReportsValidateVegCodes` | `R/logic_compliance.R` | 🔲 |
| `V7mdlReportsQualityControl` | `reports/quality_control.qmd` | 🔲 |
| `V7mdlReportsLifeform` | `reports/lifeform.qmd` | 🔲 |
| `V7mdlReportsHierarchyDiagram` | `reports/hierarchy.qmd` | 🔲 |
| `V7mdlReportFlatHierarchy` | `reports/flat_hierarchy.qmd` | 🔲 |

### Hierarchy & Classification
| VBA Module | R Target | Status |
|-----------|----------|--------|
| `V7mdlHierarchyTools` | `R/mod_hierarchy.R` | 🔲 |
| `V7mdlHierarchyShortcutFunctions` | `R/mod_hierarchy.R` | 🔲 |
| `V7mdlClipHierarchy` | `R/mod_hierarchy.R` | 🔲 |
| `V7mdlMergeHierarchies` | `R/mod_hierarchy.R` | 🔲 |
| `V7mdlSUTableTools1/2` | `R/mod_hierarchy.R` or `mod_admin.R` | 🔲 |
| `V7mdlMasterUnitListTools` | `R/mod_admin.R` (extend) | 🔲 |

### Utilities & System
| VBA Module | R Target | Status |
|-----------|----------|--------|
| `V7mdlUtility` | Various helpers inline | ⚠️ |
| `V7mdlAPICalls` | Not applicable (no Win32 API) | N/A |
| `V7mdlBackup` | `R/logic_backup.R` (DuckDB file copy) | 🔲 |
| `V7mdlAudit` | `R/logic_audit.R` | 🔲 |
| `V7mdlDiagnostic` | `R/logic_compliance.R` | 🔲 |
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
| `frmHierarchyTree` | `R/mod_hierarchy.R` | 🔲 Tree view |
| `frmHierarchyEdit` | `R/mod_hierarchy.R` | 🔲 Node editor |
| `frmSUTable` | `R/mod_hierarchy.R` | 🔲 SU table editor |
| `frmMoveNodeCopy` | Modal in `mod_hierarchy.R` | 🔲 |

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
| `frmLogin` | `R/mod_auth.R` (Phase 6) |
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
| **6** | Cloud sync, auth, upload/merge, publishing | 4 weeks | Phase 2–3 |

Phases 4 and 5 can run in parallel. Phase 6 builds on 2–3.

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
