# VPRO 2.0 Implementation Plan
## Contract Completion Roadmap

**Created**: 2026-02-11  
**Target Completion**: Phase 1-3 within 2 weeks, Phase 4-6 within 4 weeks

---

## Executive Summary

This plan completes the BC Government BEC Data Management contract by:
1. Closing testing gaps (end-to-end workflows, conflict resolution)
2. Building map-based public access tool for BECMaster
3. Completing BEC Unit Reporting Scripts (edatopic grids, Excel add-ins, graphics)
4. Finalizing deployment stack (Docker + local .exe)
5. Polishing partial features (coord tools, VENUS XML, report parity)

**Current completion**: ~85% of core functionality, 60% of contract deliverables
**Target**: 100% feature-complete, production-ready deployment

---

## Phase 1: Complete Core Testing (Priority: CRITICAL)
**Timeline**: 3-4 days  
**Goal**: Ensure data integrity and workflow reliability

### 1.1 End-to-End Workflow Tests
**Complexity**: Medium  
**Files**: `tests/shinytest2/test-e2e-workflows.R` (new)  
**Dependencies**: None

**Tasks**:
- Test complete data entry cycle: Login → Select Project → Create Plot → Enter Veg → Enter Site/Env → Save → Verify DB
- Test lumping application during export
- Test import → validation → compliance → save workflow
- Test hierarchy operations: Create SU → Assign plots → Merge → Clip
- Test cloud sync: Local change → Push → Pull on second instance → Verify
- Test merge request workflow: Upload → Review → Approve → Verify cloud state

**Acceptance**: All workflows pass without errors, data integrity verified in DuckDB

---

### 1.2 Conflict Resolution UI Tests
**Complexity**: Medium  
**Files**: `tests/shinytest2/test-conflicts.R` (new)  
**Dependencies**: Task 1.1

**Tasks**:
- Simulate concurrent edits (two users edit same plot)
- Test conflict detection in sync pull
- Test manual conflict resolution UI (choose local/cloud/merge)
- Test automatic merges for non-overlapping changes
- Test conflict logging in audit trail

**Acceptance**: Conflict UI correctly presents choices, resolutions apply cleanly

---

### 1.3 Report Parity Validation
**Complexity**: Small  
**Files**: `tests/testthat/test-reports-parity.R` (new)  
**Dependencies**: None

**Tasks**:
- Compare Quarto report outputs against Access report screenshots (in `VPRO_ACCESS/VPro64_forAI/Reports/`)
- Verify all data fields present in original reports appear in Quarto versions
- Test report generation with edge cases: empty plots, missing layers, non-standard codes
- Document any intentional deviations from Access format
- Test PDF rendering for all 15 reports

**Acceptance**: All reports render without errors, key data fields match Access originals

---

### 1.4 Compliance Engine Stress Tests
**Complexity**: Small  
**Files**: `tests/testthat/test-compliance-edge-cases.R` (new)  
**Dependencies**: None

**Tasks**:
- Test all 47 validation rules with boundary conditions
- Test cascading failures (one bad field blocking save)
- Test rule overrides (admin force-save)
- Test compliance reporting (flag summary by project)
- Test import rejection on compliance failures

**Acceptance**: No false positives, all true violations caught

---

## Phase 2: Complete Partial Features (Priority: HIGH)
**Timeline**: 2-3 days  
**Goal**: Finish features marked as "partial" in current state

### 2.1 Coordinate Tools (DMS/DD Conversion)
**Complexity**: Small  
**Files**: `R/logic_coord_tools.R` (new), `R/mod_site_env.R` (modify)  
**Dependencies**: None

**Tasks**:
- Port `V7mdlCoordTools` VBA to R (8 functions)
- Implement robust `Nz()` guards: `parse_dms()`, `format_dd_to_dms()`, `validate_utm()`
- Add coordinate format switcher to Site/Env form (toggle DD ↔ DMS)
- Handle edge cases: NULL coords, partial DMS (missing seconds), invalid UTM zones
- Add unit tests for all conversions with NA/NULL handling

**VBA Reference**: `VPRO_ACCESS/VPro64_forAI/Modules/V7mdlCoordTools.txt`

**Acceptance**: All coord conversions pass tests, no NA propagation errors

---

### 2.2 VENUS XML Export (Field Transforms)
**Complexity**: Medium  
**Files**: `R/logic_venus_export.R` (new), `R/mod_export.R` (modify)  
**Dependencies**: None

**Tasks**:
- Port `V7mdlExportVenus` and `V7mdlExportXML` field mapping logic
- Implement VENUS schema transforms:
  - Cover codes (`+`, `r`, `P`) → numeric equivalents
  - Site descriptor code → VENUS vocabulary lookup
  - Date formats, coordinate system codes, taxonomy codes
- Add XML validation against VENUS 1.0 XSD schema
- Add "Export VENUS XML" button to Export module
- Test with real VPRO projects, validate against VENUS importer

**VBA Reference**: 
- `VPRO_ACCESS/VPro64_forAI/Modules/V7mdlExportVenus.txt`
- `VPRO_ACCESS/VPro64_forAI/Modules/V7mdlExportXML.txt`

**Acceptance**: XML validates, imports successfully into VENUS test system

---

### 2.3 Reporting VBA Logic Parity
**Complexity**: Medium  
**Files**: `R/logic_reports_veg.R`, `R/logic_report_export.R` (modify)  
**Dependencies**: Phase 1.3

**Tasks**:
- Port remaining VBA report logic from 14 `V7mdlReports*` modules:
  - `V7mdlReportsShortVeg` → constancy/cover calculations
  - `V7mdlReportsVegTable` → structure table formatting
  - `V7mdlReportsAspectsUnitsPlots` → aspect rose data prep
  - `V7mdlReportsBoxWhiskerUnit` → box plot data aggregation
  - `V7mdlReportsEdatopicGridUnit` → grid cell assignment
  - Others: diagnostic flags, hierarchy formatting, sorting logic
- Update Quarto templates to use ported logic functions
- Add computed fields missing from templates (e.g., constancy %, mean cover by BEC unit)
- Test with multiple projects to verify calculations match Access

**VBA Reference**: `VPRO_ACCESS/VPro64_forAI/Modules/V7mdlReports*.txt` (14 files)

**Acceptance**: All report calculations match Access outputs (±1% for rounding)

---

### 2.4 UI Regression Test Expansion
**Complexity**: Small  
**Files**: `tests/shinytest2/test-data-entry.R`, `test-admin.R` (new)  
**Dependencies**: Phase 1.1

**Tasks**:
- Expand smoke tests to cover:
  - All Vegetation layer tabs (A, B, C, D, E/F, G)
  - All Site/Env tabs (General, Mensuration, Soil)
  - Admin module (Project Metadata CRUD, Code Maintenance)
  - Image gallery (upload, delete, KML export)
- Test keyboard shortcuts (Ctrl+S, Ctrl+N, F5 refresh)
- Test validation feedback UI (error messages, field highlighting)
- Test dynamic dropdowns (species list filtering, code lookups)

**Acceptance**: 90%+ UI interaction coverage, all critical paths tested

---

## Phase 3: Contract Deliverable - BEC Data Management (Priority: HIGH)
**Timeline**: 4-5 days  
**Goal**: Complete remaining items from Contract Section 1

### 3.1 Map-Based Public Access Tool (BECWeb Integration)
**Complexity**: Large  
**Files**: `R/mod_becweb_map.R` (new), `ui.R` (modify)  
**Dependencies**: None (can run parallel)

**Tasks**:
- Create new Shiny module for public map interface:
  - Leaflet map with BEC polygon boundaries (from PostgreSQL spatial table)
  - Click polygon → Load unit summary (constancy table, photos, description)
  - Filter controls: BEC zone, subzone, variant, phase
  - Search by plot ID or coordinates
  - Export unit data as CSV/PDF
- Connect to PostgreSQL read-only view (published RDS data)
- Implement caching layer (cache unit summaries in `vpro_metadata.duckdb`)
- Add authentication bypass for public read (vs. editor login)
- Deploy as separate app or add "Public View" tab with restricted UI

**Data Source**: PostgreSQL `becmaster_published` schema (created by `logic_publish.R`)

**UI Design**: 
- Left panel: Map with polygon selection
- Right panel: Tabbed display (Summary, Vegetation, Environment, Photos)
- Bottom panel: Export controls

**Acceptance**: Non-authenticated users can browse BEC units, view data, export PDFs

---

### 3.2 Controlled Merge Enhancement
**Complexity**: Small  
**Files**: `R/mod_merge.R` (modify), `R/logic_sync.R` (modify)  
**Dependencies**: Phase 1.2

**Tasks**:
- Add merge approval workflow enhancements:
  - Email notifications on merge request submission (via `R/logic_notifications.R` - new)
  - Change diff visualization (show before/after for affected records)
  - Multi-reviewer approval (require 2+ approvals for sensitive tables)
  - Merge request comments/discussion thread
  - Automatic tests before merge (compliance + referential integrity)
- Add merge history report (who approved what, when)

**Acceptance**: Merge process has audit trail, approval controls enforced

---

### 3.3 RDS Publishing Enhancements
**Complexity**: Small  
**Files**: `R/logic_publish.R` (modify)  
**Dependencies**: None

**Tasks**:
- Add publication checklist enforcement:
  - Data completeness check (all mandatory fields populated)
  - Compliance pass required before publish
  - Taxonomic validation (all species in SppList)
- Add version tagging (track published RDS versions over time)
- Add embargo support (publish with future release date)
- Add publication metadata (author, citation, DOI placeholder)
- Generate data dictionary alongside RDS (field descriptions, units)

**Acceptance**: Published RDS includes metadata, passes validation gate

---

## Phase 4: Contract Deliverable - BEC Unit Reporting (Priority: HIGH)
**Timeline**: 5-6 days  
**Goal**: Complete Contract Section 3 (Reporting Scripts)

### 4.1 Excel Export Add-In (Formatted Tables)
**Complexity**: Medium  
**Files**: `R/logic_excel_export.R` (new), `inst/excel_template.xlsx` (new)  
**Dependencies**: None

**Tasks**:
- Create Excel export functions using `openxlsx2`:
  - Apply BEC standard formatting (fonts, colors, borders)
  - Multi-sheet workbooks: Veg by layer, Environment, Site list, Hierarchy
  - Conditional formatting: Cover values color-coded, flagged records highlighted
  - Formulas: Auto-calculate constancy %, mean cover
  - Charts: Embedded structure charts, cover by layer
- Add "Export to Excel" button to Export module
- Include template file with pre-formatted sheets
- Test with large projects (100+ plots)

**Output Format**: 
- Sheet 1: Vegetation (wide format, layers in columns)
- Sheet 2: Environment (one plot per row)
- Sheet 3: Summary Statistics (pivot table ready)
- Sheet 4: Hierarchy (tree structure outline view)

**Acceptance**: Excel files open cleanly in Excel 2016+, formatting preserved

---

### 4.2 Edatopic Grid Generator
**Complexity**: Large  
**Files**: `R/logic_edatopic.R` (new), `reports/edatopic_grid.qmd` (new)  
**Dependencies**: Phase 2.3

**Tasks**:
- Port edatopic grid logic from `V7mdlReportsEdatopicGridUnit`:
  - Assign plots to grid cells based on soil moisture regime (SMR) + soil nutrient regime (SNR)
  - Calculate cell statistics: plot count, dominant species, mean cover
  - Generate grid visualization (9x9 matrix, color by plot density)
- Implement grid export formats:
  - PDF: Formatted grid with BEC unit header
  - CSV: Grid data for GIS import
  - HTML: Interactive grid (click cell → plot list)
- Add "Generate Edatopic Grid" to Reporting module
- Test with BEC projects covering full SMR/SNR range

**VBA Reference**: `VPRO_ACCESS/VPro64_forAI/Modules/V7mdlReportsEdatopicGridUnit.txt`

**Grid Dimensions**: SMR (0-8) × SNR (A-E typically, but codes vary)

**Acceptance**: Grid output matches Access version, handles sparse cells gracefully

---

### 4.3 Climr Data Integration
**Complexity**: Medium  
**Files**: `R/logic_climr.R` (new), `R/mod_site_env.R` (modify)  
**Dependencies**: None (can run parallel)

**Tasks**:
- Integrate with [ClimateBC-R](https://github.com/bcgov/climr) package:
  - Auto-fetch climate normals for plot coordinates
  - Display climate variables in Site/Env form (read-only panel)
  - Include in Environment reports: MAT, MAP, MWMT, MCMT, DD5, etc.
  - Cache climate data in `Sample_Env` table (avoid repeated API calls)
- Add "Refresh Climate Data" button
- Handle offline mode (skip if no internet, use cached)
- Add climate variable plots to reports (scatter: MAT vs. elevation)

**API**: ClimateBC web service or `climr` R package (check which is current)

**Acceptance**: Climate data displays correctly, caches persist, offline graceful

---

### 4.4 Publication Graphics Suite
**Complexity**: Large  
**Files**: `R/logic_graphics_veg.R`, `R/logic_graphics_env.R` (new), Quarto templates (modify)  
**Dependencies**: Phase 2.3

**Tasks**:
- **Aspect Rose** (`reports/aspect_rose.qmd`):
  - Port logic from `V7mdlReportsAspectsUnitsPlots`
  - Generate polar plot: aspect bins (0-359°) with plot count
  - Color by BEC unit or site series
  - Export as PNG/PDF for publication
  
- **Box Plots** (`reports/box_plots.qmd`):
  - Port logic from `V7mdlReportsBoxWhiskerUnit`
  - Generate box-whisker plots for continuous variables: cover %, height, age, elevation
  - Group by layer or BEC unit
  - Export publication-ready (ggplot2 theme_bw)
  
- **Vegetation Structure Chart** (`logic_graphics_veg.R`):
  - Generate layered bar chart: mean cover by layer (A-G)
  - Stacked by lifeform or species
  - Include error bars (SD or SE)
  
- **Environment Summary Plots** (`logic_graphics_env.R`):
  - Scatter: Elevation vs. Slope, UTM coordinates
  - Histogram: Soil depth, humus depth
  - Heatmap: Correlation matrix for env variables
  
- **Improved Maps** (`R/mod_images.R` modify):
  - Add basemap selector (OpenStreetMap, satellite, terrain)
  - Cluster markers for dense plot groups
  - Color plots by BEC unit or site series
  - Add legend and scale bar
  - Export map as static PNG (via `mapview::mapshot()`)

**Acceptance**: All graphics render publication-quality, export cleanly to PDF/PNG

---

## Phase 5: Deployment Stack (Priority: CRITICAL)
**Timeline**: 3-4 days  
**Goal**: Enable client evaluation and production rollout

### 5.1 Docker Deployment Package
**Complexity**: Medium  
**Files**: `Dockerfile`, `docker-compose.prod.yml` (new), `deploy/README.md` (new)  
**Dependencies**: None

**Tasks**:
- Create production Dockerfile:
  - Base: `rocker/shiny:4.3` (R 4.3 + Shiny Server)
  - Install system deps: DuckDB CLI, PostgreSQL client, Quarto
  - Copy app files, install renv packages
  - Set up persistent volume mounts for `data/` directory
  - Configure Shiny Server (port 3838, app timeout, max connections)
- Create `docker-compose.prod.yml`:
  - Shiny app container
  - PostgreSQL container (BECMaster cloud backend)
  - Persistent volumes: database files, uploaded images, logs
  - Reverse proxy (Traefik or Nginx) with SSL termination
- Test on clean VM (Ubuntu 22.04)
- Document deployment steps in `deploy/README.md`

**Deliverable**: Single `docker compose up -d` command deploys full stack

**Acceptance**: App runs stably for 24h under load (10 concurrent users)

---

### 5.2 Local Desktop Build (Windows .exe)
**Complexity**: Large  
**Files**: `deploy/build_desktop.R` (new), `deploy/installer_script.iss` (new)  
**Dependencies**: Phase 5.1

**Tasks**:
- Choose desktop packaging approach:
  - **Option A**: [ElectroShiny](https://github.com/chasemc/ElectronShiny) - Electron wrapper, large bundle (~200MB)
  - **Option B**: [RInno](https://github.com/ficonsulting/RInno) - Inno Setup installer, R portable (~150MB)
  - **Recommendation**: RInno (smaller, familiar installer UX for Windows users)
- Create installer script:
  - Bundle R portable (4.3.2) + Shiny + app code
  - Bundle DuckDB embedded
  - Create Start Menu shortcut → launches local Shiny app on port 3838
  - Create desktop icon
  - Auto-open browser to `http://localhost:3838` on launch
- Test on clean Windows 10/11 machine (no R installed)
- Code-sign installer (if client provides cert)
- Create uninstaller

**Deliverable**: `VPro2_Setup_v2.0.exe` (50-150MB)

**Acceptance**: Installs cleanly, app launches, offline DuckDB works

---

### 5.3 Cloud Deployment Documentation
**Complexity**: Small  
**Files**: `deploy/CLOUD_SETUP.md` (new)  
**Dependencies**: Phase 5.1

**Tasks**:
- Document cloud deployment on BC Gov infrastructure:
  - Options: OpenShift, AWS EC2, Azure VM
  - Recommended: Docker on Ubuntu VM + managed PostgreSQL
- Provide Terraform/Ansible scripts for infrastructure as code
- Document SSL certificate setup (Let's Encrypt)
- Document backup strategy: Daily DB snapshots, image file backups
- Document monitoring: Uptime checks, error logging (sentry.io or self-hosted)
- Document scaling: Shiny Server Pro for concurrent users, read replicas for PostgreSQL

**Acceptance**: Step-by-step guide enables IT admin to deploy in 1 day

---

### 5.4 User Documentation & Training Materials
**Complexity**: Medium  
**Files**: `docs/USER_GUIDE.md`, `docs/ADMIN_GUIDE.md`, `docs/VIDEO_SCRIPTS.md` (new)  
**Dependencies**: All features complete

**Tasks**:
- Create User Guide (Markdown → PDF via Pandoc):
  - Getting Started: Login, select project, navigate tabs
  - Data Entry: Vegetation layers, site/env forms, keyboard shortcuts
  - Hierarchy Management: Create SU, merge, clip, assign plots
  - Import/Export: CSV upload, export formats, lumping
  - Reporting: Generate reports, customize filters
  - Maps & Images: Upload photos, view gallery, export KML
  - Troubleshooting: Common errors, data validation
  
- Create Admin Guide:
  - Installation: Docker vs. desktop
  - Project setup: Create new project, configure codes
  - User management: RBAC, permissions
  - Cloud sync: Configure PostgreSQL, approve merges
  - Maintenance: Backups, updates, log rotation
  
- Create Video Script Outlines (for client's video producer):
  - Video 1: "Quick Start - Your First Plot" (5 min)
  - Video 2: "Advanced Features - Hierarchy Tools" (8 min)
  - Video 3: "Admin Functions - Cloud Sync & Merges" (10 min)

**Deliverable**: `docs/` folder with PDF guides + video scripts

**Acceptance**: Non-technical user can complete data entry workflow following guide

---

## Phase 6: Final Polish & Handoff (Priority: MEDIUM)
**Timeline**: 2-3 days  
**Goal**: Production-ready, maintainable codebase

### 6.1 Performance Optimization
**Complexity**: Medium  
**Files**: Various (profiling-driven)  
**Dependencies**: Phase 5.2

**Tasks**:
- Profile app with `profvis`:
  - Identify slow queries (DuckDB query optimization, add indexes)
  - Identify slow UI renders (cache reactive data, debounce inputs)
- Optimize large table loads:
  - Pagination for `mod_veg_sample` (load 50 plots at a time)
  - Virtual scrolling for large species lists
- Add loading indicators for slow operations (sync, report generation)
- Pre-compute expensive views during database build
- Test with large project (1000+ plots)

**Acceptance**: UI remains responsive with 500+ plots, reports generate <30s

---

### 6.2 Accessibility & UX Polish
**Complexity**: Small  
**Files**: `ui.R`, CSS files (new), modules (modify)  
**Dependencies**: None

**Tasks**:
- Accessibility audit:
  - ARIA labels for screen readers
  - Keyboard navigation (tab order, focus indicators)
  - Color contrast compliance (WCAG AA)
  - Form field labels and error messages
- UX improvements:
  - Tooltips for all form fields (field descriptions from Access)
  - Consistent button placement (Save top-right, Cancel bottom-left)
  - Confirmation dialogs for destructive actions (delete plot, reject merge)
  - Progress indicators for imports
- Add dark mode toggle (optional, nice-to-have)

**Acceptance**: Passes basic accessibility scan (WAVE or axe DevTools)

---

### 6.3 Code Quality & Maintenance
**Complexity**: Small  
**Files**: All R files (review & refactor)  
**Dependencies**: Phase 6.1

**Tasks**:
- Run `lintr` across all R files, fix style issues
- Add roxygen2 documentation to all exported functions
- Extract magic numbers to constants (`R/constants.R`)
- Add package-level documentation (`R/vpro-package.R`)
- Ensure all database queries use parameterized inputs (SQL injection audit)
- Add input validation to all user-facing functions (type checks, range checks)
- Remove debug code, commented-out blocks
- Consolidate duplicated logic (DRY principle)

**Acceptance**: `lintr::lint_package()` passes, all functions documented

---

### 6.4 Final Test Suite & CI/CD
**Complexity**: Medium  
**Files**: `.github/workflows/test.yml`, `.github/workflows/deploy.yml` (new)  
**Dependencies**: All tests from Phase 1

**Tasks**:
- Set up GitHub Actions CI:
  - Run `testthat` tests on push (unit + integration)
  - Run `shinytest2` tests on PR (UI regression)
  - Run `lintr` and `styler` checks
  - Generate test coverage report (upload to Codecov)
- Set up deployment automation:
  - Build Docker image on tag push
  - Push to container registry (GitHub Container Registry or DockerHub)
  - Deploy to staging server for client review
- Add pre-commit hooks (local):
  - Auto-format R code with `styler`
  - Prevent commits with TODO/FIXME
  - Run tests before push

**Acceptance**: All tests pass in CI, Docker image builds successfully

---

### 6.5 Handoff Package
**Complexity**: Small  
**Files**: `HANDOFF.md`, `CHANGELOG.md`, `LICENSE` (new)  
**Dependencies**: All phases complete

**Tasks**:
- Create handoff documentation:
  - System architecture overview (diagrams)
  - Database schema documentation (ERD)
  - API/module reference (auto-generated from roxygen2)
  - Known limitations and future enhancements
  - Maintenance calendar (suggested update schedule)
  - Support contact information
  
- Create changelog:
  - Document all changes from VPro64 Access → VPro 2.0
  - List new features, removed features, breaking changes
  - Migration notes (how to import Access data)
  
- License and legal:
  - Apply BC Gov license (if specified)
  - Document third-party dependencies and licenses
  - Export control / data privacy compliance notes
  
- Create client acceptance checklist:
  - Feature parity verification (105 forms → modules mapped)
  - Performance benchmarks
  - Security audit results
  - Training completion sign-off

**Deliverable**: `HANDOFF.md` with sign-off section

**Acceptance**: Client signs off on deliverable

---

## Task Dependency Graph

```
Phase 1: Testing
├─ 1.1 E2E Tests → 1.2 Conflict Tests
├─ 1.3 Report Parity → (Phase 2.3, 4.4)
└─ 1.4 Compliance Tests → (Phase 3.3)

Phase 2: Partial Features
├─ 2.1 Coord Tools → (independent)
├─ 2.2 VENUS Export → (independent)
├─ 2.3 Report Logic → 1.3 → 4.4
└─ 2.4 UI Tests → 1.1

Phase 3: BEC Data Mgmt
├─ 3.1 Map Tool → (independent)
├─ 3.2 Merge Controls → 1.2
└─ 3.3 RDS Publish → 1.4

Phase 4: Reporting
├─ 4.1 Excel Export → (independent)
├─ 4.2 Edatopic Grid → 2.3
├─ 4.3 Climr Integration → (independent)
└─ 4.4 Graphics → 2.3

Phase 5: Deployment
├─ 5.1 Docker → All features
├─ 5.2 Desktop Build → 5.1
├─ 5.3 Cloud Docs → 5.1
└─ 5.4 User Docs → All features

Phase 6: Polish
├─ 6.1 Performance → 5.2
├─ 6.2 UX Polish → (independent)
├─ 6.3 Code Quality → 6.1
├─ 6.4 CI/CD → All tests
└─ 6.5 Handoff → All phases
```

---

## Parallelization Strategy

**Week 1**: 
- Stream A: Phase 1 (Testing)
- Stream B: Phase 2.1, 2.2 (Coord Tools, VENUS)
- Stream C: Phase 4.1, 4.3 (Excel, Climr)

**Week 2**:
- Stream A: Phase 2.3, 2.4 (Report Logic, UI Tests)
- Stream B: Phase 3.1 (Map Tool)
- Stream C: Phase 3.2, 3.3 (Merge Controls, RDS Publish)

**Week 3**:
- Stream A: Phase 4.2, 4.4 (Edatopic, Graphics)
- Stream B: Phase 5.1, 5.3 (Docker, Cloud Docs)
- Stream C: Phase 6.2, 6.3 (UX Polish, Code Quality)

**Week 4**:
- Stream A: Phase 5.2 (Desktop Build)
- Stream B: Phase 5.4 (User Docs)
- Stream C: Phase 6.1, 6.4 (Performance, CI/CD)

**Week 5** (Buffer):
- Phase 6.5 (Handoff)
- Client review cycles
- Bug fixes from testing

---

## Risk Mitigation

| Risk | Impact | Mitigation |
|------|--------|------------|
| Desktop build fails on client machines | HIGH | Test on 3+ clean Windows VMs, provide Docker fallback |
| Edatopic grid logic unclear from VBA | MEDIUM | Contact original developer (if available), implement simplified version |
| Cloud deployment blocked by IT policies | HIGH | Provide desktop-only option, assist with security review |
| Report graphics don't match Access exactly | MEDIUM | Document intentional improvements, get client sign-off early |
| Performance issues with 1000+ plots | MEDIUM | Implement pagination, lazy loading, database indexes |
| Climr API unavailable | LOW | Cache all climate data, provide offline mode |

---

## Success Metrics

- **Feature Parity**: 100% of Access forms/modules mapped to R equivalents
- **Test Coverage**: ≥80% code coverage, all critical workflows tested
- **Performance**: <3s page load, <30s report generation
- **Deployment**: 1-click Docker deploy, <15min desktop install
- **Documentation**: Complete user/admin guides, video scripts ready
- **Client Satisfaction**: Sign-off on all contract deliverables

---

## Next Steps

1. **Review with client**: Confirm priorities, adjust timeline
2. **Assign resources**: If multiple developers, split streams A/B/C
3. **Set up project tracking**: GitHub Projects board with tasks from this plan
4. **Begin Phase 1**: Start with E2E tests (highest risk)

---

**End of Implementation Plan**
