# `vpro` Engineering & Multi-Agent Instructions (Headless R Companion SDK)

## 1. Product Identity & Hard Architectural Boundary

- **Official Role:** `/home/bruno/Work/vpro` (`master` branch) is **exclusively the official headless `vpro` R Companion SDK & Scientific Analytics Package** (`R >= 4.4.0`) for **`vpro_wails`** (**`VPro`** — *VENUS — Vegetation and Environment NexUS — Professional*, **B.C. Ministry of Forests, Research Branch — Biogeoclimatic Ecosystem Classification (BEC) Program**).
- **Target Audience:** BEC research ecologists, quantitative vegetation scientists, spatial/climate analysts, reproducible Quarto / `_targets` pipelines on `vpro_wails` SQLite databases, and out-of-process `Rscript --vanilla` calls from `vpro_wails/internal/rsidecar`.
- **Desktop GUI Lives Exclusively in `vpro_wails`:** `/home/bruno/Work/vpro_wails` (Wails v3 + Go 1.25 + Svelte 5 + SQLite WAL) owns all interactive FS882 / 2-Page / FS1333 (SIVI) forms, datasheet grids, hierarchy/SU trees, CRUD dialogs, and MapLibre GL JS v6 + WebGPU GIS.
- **Zero Shiny / Widget UI Rule:**
  - `shiny`, `bslib`, `DT`, `rhandsontable`, `shinyTree`, `shinyjs`, `sass`, `leaflet`, and `rappdirs` are **strictly forbidden** in `DESCRIPTION` (`Depends` and `Imports`).
  - Never create Shiny modules (`mod_*`), app shells (`ui.R`, `server.R`, `global.R`), HTML widgets, modal prompts, or Access-form GUI clones.
  - `.onLoad()` must be fast, 100% offline, non-interactive, and side-effect-free (no network access, server launches, global state mutation, or automatic DuckDB extension installs).
  - **Retired Historical Baggage:** The 4,130-item Access GUI parity ledger, Access-form-to-Shiny translators, and legacy Shiny/Postgres sync prototypes are permanently retired. Legacy Shiny files still in `R/` or `inst/app/` awaiting the clean-slate `R/` rebuild must never be extended or imitated.

### Core R SDK Scope

1. **Workspace & `VP08` SQLite Layer:** Cross-OS `vpro_data_dir()` / `vpro_config_dir()` discovery, WAL-safe `RSQLite` connections, `VP08` family inspection (`vpro_project_inspect()`, preserving `isTRUE(insp$compatible)` expected by `vpro_wails/internal/rsidecar`), and optional explicit in-memory DuckDB (`sqlite_scanner`) cross-project queries.
2. **Tidy Ecological Extraction & Taxonomy:** Tibble/data-frame readers for `Env`, `Admin`, `Veg`, `Humus`, `Mineral`, `Other`, `Audit`, `Metadata`, `*_SU`, `*_Hierarchy` (`~` breakpoint rollups), `*_Lump`, and harmonized `VLists.db` (`USysAllSpecs`) + `VUser.db` (`USysUserSpp`) species catalogues.
3. **Standards, Integrity & QC Validation:** Checks calibrated to `V7mdlReportsValidateVegCodes`, `V7mdlReportsValidateEnvData`, `V7mdlReportValidation`, `V7mdlReportsQualityControl` (`DataQuality` ranks + lexical `BEC_Use`), and read-only duplicate-species diagnostics (`V7mdlOptimizeVeg.Check4DuplicatedSpecies`).
4. **Community Matrices & Multivariate Phytosociology:** `plot x species` matrices (layer/strata collapsing, `*_Lump` folding with `99%` cap, `sqrt` / `log1p` / `chord` / `hellinger` / `raw` transforms) directly feeding `vegan`, `vegclust` (`NC`, `FCM`, `KM`, `HCLUST`), `indicspecies` (`multipatt` IndVal), and `labdsv`.
5. **Spatial, Climate & Edatopic (`CMD -> aSMR`) Workflows:** `sf` (`EPSG:4326` $\leftrightarrow$ `EPSG:3005`, GeoPackage `.gpkg`, `PMTiles`/GeoJSON overlays), `terra`, `bcgov/climr` normals (with offline BGC lapse fallback + `__VPRO_PlotClimate` cache), and Ministry `CMD -> aSMR` rules (`aSMR_Rules_HalfStep.csv`, `CMD_adjustments.csv`) for paired Relative (`rSMR x rSNR`) and Actual (`aSMR x rSNR`) edatopic grids.
6. **BEC Diagnostic Synthesis & Plot Profiling:** Presence (`I–V`), Domin-Krajina Significance (`+`, `1–9`), Prominence, Goldstream, BEC Differential/Diagnostic species fidelity (`d`, `dd`, `cd`, `c`, `ic` matching `V7mdlDiagnostic` & `vpro_wails/internal/diagnostics`), pairwise unit similarity, and Plot Profiling set algebra (`Add` $\cup$, `Common` $\cap$, `Subtract` $\setminus$).
7. **Guarded Non-Destructive Write-Back:** Opt-in transactional write-back (`*_ClusterCandidate_SU`, working `*_SU`, `*_Lump`, `__VPRO_PlotClimate`) with `<Project>_Audit` + `__VPRO_*` provenance.
8. **Quarto BEC Reporting:** Reproducible BEC Unit and BGC Subzone guides (`.qmd` HTML/PDF with standalone `rmarkdown`/`knitr` fallback) and `_targets`-ready pure functions.

---

## 2. Cross-OS `vpro_wails` Workspace & SQLite WAL Interoperability Contract

### 2.1 Exact Directory Resolution (`vpro_data_dir()` & `vpro_config_dir()`)

`vpro` must resolve paths identically to `/home/bruno/Work/vpro_wails/internal/sqlutil/sqlutil_foundation.go` (`UserDataDir()` and `UserConfigDir()`). **Never use `rappdirs`** (on Windows `rappdirs` emits doubled `.../AppData/Local/vpro/vpro`, and on macOS/Linux diverges from Go `os.UserConfigDir()`):

- **`vpro_data_dir()`:**
  1. `getOption("vpro.data_dir")` or `Sys.getenv("VPRO_DATA_DIR")` when non-empty (`normalizePath(..., winslash = "/", mustWork = FALSE)`).
  2. Otherwise by OS (treat empty `""` env vars as unset):
     - **Windows:** `file.path(Sys.getenv("LOCALAPPDATA"), "vpro")` (fallback: `file.path(Sys.getenv("USERPROFILE"), "AppData", "Local", "vpro")` when `LOCALAPPDATA` is empty).
     - **macOS (`Darwin`):** `file.path(Sys.getenv("HOME"), "Library", "Application Support", "vpro")`.
     - **Linux / Unix:** `file.path(Sys.getenv("XDG_DATA_HOME", unset = file.path(Sys.getenv("HOME"), ".local", "share")), "vpro")`.

- **`vpro_config_dir()` (`config.yml` at `file.path(vpro_config_dir(), "config.yml")`):**
  1. `getOption("vpro.config_dir")` or `Sys.getenv("VPRO_CONFIG_DIR")` when non-empty (`normalizePath(..., winslash = "/", mustWork = FALSE)`).
  2. Otherwise by OS (matching Go `os.UserConfigDir()` + `"vpro"`, treating empty `""` env vars as unset):
     - **Windows:** `file.path(Sys.getenv("APPDATA"), "vpro")`.
     - **macOS (`Darwin`):** `file.path(Sys.getenv("HOME"), "Library", "Application Support", "vpro")`.
     - **Linux / Unix:** `file.path(Sys.getenv("XDG_CONFIG_HOME", unset = file.path(Sys.getenv("HOME"), ".config")), "vpro")`.

### 2.2 Concurrent SQLite WAL Safety Alongside `vpro_wails`

- **Read Connections (Default):** Open with `DBI::dbConnect(RSQLite::SQLite(), path, flags = RSQLite::SQLITE_RO)` (and `on.exit(DBI::dbDisconnect(con), add = TRUE)`), or configure managed read handles with `PRAGMA busy_timeout = 5000; PRAGMA synchronous = NORMAL; PRAGMA query_only = ON;`. Percent-encode `#`, `?`, and `%` if constructing `file:` URIs (`?mode=ro`). Never hold idle write transactions, `EXCLUSIVE` locks, or run in-place `VACUUM` against live workspace DBs open in `vpro_wails`.
- **Guarded Opt-In Write-Back (`BEGIN IMMEDIATE`):**
  - Permitted targets only: `<Name>_ClusterCandidate_SU`, user-confirmed working `<Name>_SU`, `<Name>_Lump`, `__VPRO_PlotClimate`, and `__VPRO_RSidecarHistory`.
  - Set `PRAGMA busy_timeout = 5000; PRAGMA synchronous = NORMAL; PRAGMA foreign_keys = ON;` and wrap mutations in `BEGIN IMMEDIATE ... COMMIT` with clean rollback on failure.
  - **Refusal Guards:** Unconditionally reject writes targeting `Master*` tables (or prefixes matching `"master"` case-insensitively), `USys*` tables/views, bundled `VLists.db`, or custodian-locked `BECSiteUnit` without explicit authorization. Require `confirm_overwrite = TRUE` before replacing existing `*_SU` or `*_Lump` tables.
  - **Provenance:** Append `<Project>_Audit` rows and `__VPRO_*` provenance/identity reservations inside the same `BEGIN IMMEDIATE` transaction; never reuse deleted child IDs.

---

## 3. Preserved `VP08` & BEC Ecological Domain Invariants

1. **7-DB SQLite Family & `_table_metadata`:**
   - Family: `<Project>.db` (8 tables per prefix `<P>`: `_Env`, `_Admin`, `_Veg`, `_Humus`, `_Mineral`, `_Other`, `_Audit`, `_Metadata`), `VPro64.db`, `VLists.db`, `VUser.db`, `VMetaData.db`, `VMessageBoard.db`, `VPics.db`.
   - `_table_metadata` version tag `'VP08'`. Do not invent `_Env.StartDate` or an `Env -> Metadata` FK (confirmed dead VBA in `V7mdlRelationships`).
   - Shared tables in `<Project>.db`: `__VPRO_PlotClimate` (`PlotNumber TEXT PRIMARY KEY`, `CoordElevHash`, `RefPeriod`, `Source`, `MAT`, `MWMT`, `MCMT`, `MAP`, `MSP`, `PAS`, `CMD`, `PPT_05`..`PPT_09`, `PPT_at`, `PPT_wt`, `DD5`, `NFFD`, `ComputedAt`), `<Name>_ClusterCandidate_SU`, `<Name>_SU` (`PlotNumber`, `SiteUnit`), `<Name>_Lump` (`SppCode`, `LumpCode`, `Use`), `<Name>_Hierarchy` (`~Name` breakpoint semantics), `__VPRO_RSidecarHistory`.
2. **Literal `character` `PlotNumber` (`Text 7`):**
   - Always R `character` and SQLite `TEXT` (`typeof("PlotNumber") = 'text'`, `CAST("PlotNumber" AS BLOB) = CAST(? AS BLOB)` when guarding affinity). Never strip leading zeroes (e.g., `'00337'`) across SQL, CSV readers, matrix row names, `sf`, or JSON.
3. **Access `BOOLEAN` Storage (`-1` vs `0`):**
   - Disk SQLite & Audit rows use **`-1L` = `TRUE`**, **`0L` = `FALSE`**, `NULL` = `NA`. Normalize non-zero integers to `TRUE` on read into R `logical`; serialize `TRUE -> -1L`, `FALSE -> 0L`, `NA -> NULL` on write.
4. **IEEE-754 `float32` Cover Narrowing & `99%` Lumped Cap:**
   - Narrow `double` inputs to IEEE-754 `float32` *before* checking `< 100` (`99.999996 -> 99.99999237 < 100` passes; `99.999999 -> 100.0` rejects).
   - Taxonomic lumping (`<Name>_Lump` where `Use != 0`, `UPPER(TRIM(SppCode)) -> UPPER(TRIM(LumpCode))`) and fallback `TotalA`/`TotalB` sums cap per-layer summed cover at **`99%`** (`pmin(sum_cover, 99)`), never mutating raw `<Project>_Veg`. State explicitly when Pielou probabilistic stratum overlap $100 \times (1 - \prod_i (1 - c_i / 100))$ is used instead of additive sums.
5. **ACE 15-Significant-Digit Rounding & BEC Thresholds:**
   - Format `double` to 15 significant decimal digits before half-away rounding (`1.005 -> 1.01` at 2 decimals) for calibrated Access/Plot Profiling/report outputs (`inst/doc-oracles/VALUE_CONVERSIONS.md`).
   - Thresholds (`inst/doc-oracles/DIAGNOSTIC_CLASSIFICATION.md`): Presence `I–V` (`<= 0.2, 0.4, 0.6, 0.8, > 0.8`), Domin-Krajina Significance `+` (`<= 0.3`, weight `0`) & `1–9` (`<= 1.0, 2.2, 5.0, 10.0, 20.0, 33.0, 50.0, 75.0, > 75.0`), Prominence (`mean_cover * 10 * sqrt(presence)` at `15, 50, 100, 200`), Goldstream (`presence * 100 * sqrt(mean_cover)` at `5, 25, 75, 150, 300, 500`).
6. **Species Catalogue Asymmetry & Layer Mapping:**
   - `VLists.USysAllSpecs.Lifeform` is `INT32` (`LONG`) vs. `VUser.USysUserSpp.LifeForm` `INT16` (`INTEGER`). Exclude synonyms (`LOWER(Codetype) = 's'`) in 5-field `USysAllSpecies` unions and surface conflicting used-code tuples rather than silently picking `First()`. Join short-veg layer keys on `LayerCode.Layer1234567` (never padded `LayerCode.LayerCode`).
7. **`LMH25 (2023)` Soil Horizon Ordering:**
   - **Upland organic (`L`, `F`, `H`):** upward from `0 cm` (`UpperDepth > LowerDepth`, ordered **`UpperDepth DESC`**).
   - **Wetland organic (`Of`, `Om`, `Oh`) & Mineral (`A`, `B`, `C`, `R`, `W`):** downward from `0 cm` (`UpperDepth < LowerDepth`, ordered **`UpperDepth ASC`**).
8. **UTF-16 Code-Unit Limits:**
   - Enforce Access UTF-16 code-unit bounds (`PlotNumber <= 7`, `Species <= 8`, `Horizon <= 8`, `Texture <= 4`, `Colour <= 14`, quality labels `<= 15`) and reject malformed UTF-8 or unpaired surrogates.

---

## 4. Surrounding Sibling Asset Map (Explicit Absolute Paths Required)

`glob` and `grep` default solely to `/home/bruno/Work/vpro`. **Always pass explicit absolute paths** for sibling lookups, **include them in subagent prompts**, and **never mutate `.accdb`/`.mdb`/`.zip` originals**:

1. **`/home/bruno/Work/vpro_wails/`** — Canonical desktop app: `AGENTS.md`, `internal/sqlutil/sqlutil_foundation.go` (`UserDataDir`, `UserConfigDir`), `internal/rsidecar/` (`bridge.go`, `climate_asmr.go`, `clustering.go`, `quarto_reports.go`, `assets/*.R`, `assets/*.qmd`, `assets/*.csv`), `internal/diagnostics/` (`bec_math.go`, `engine.go`), `resources/standards-2026-provenance.json`, `resources/database-family/*.db`, `resources/Sample.db`.
2. **`/home/bruno/Work/VPRO_ACCESS/okf/`** — 17 authoritative specs (**start at `/home/bruno/Work/VPRO_ACCESS/okf/00_index.md`**), plus `/home/bruno/Work/VPRO_ACCESS/VPro64_forAI/` (`Modules/`, `Queries/`, `Tables_Data/`), `LMH25_2023_web.pdf`, and `Diagnostic10.xla`.
3. **`/home/bruno/Work/MoF-Skeena-Research/`** — Ministry R/Quarto repos: `BEC_R_working/_functions/*.R`, `BEC_Classification_Analysis`, `BEC_Unit_Reporting/unit.report.qmd`, `aSMR-x-rSMR`, `EdatopicGrid_Spp_Distribution`, `BEC_soils_fixing`, `BEC_Clean_BECdb`, `CCISS_VectorTiles`.
4. **`/home/bruno/Work/bcgov_ref/`** — `BEC_ReportR`, `cciss-docs`.
5. **`/home/bruno/Work/VPRO_ACCESS_1/VPro64/BECMaster_fixing.accdb`** — `545 MB` provincial master (`71,567` plots, `1,651,842` veg rows; plus `Haida_Gwaii_2019.accdb`, `Manning_TEM_Vpro19.accdb`). **Read-only — never mutate; copy to `/tmp` for scale benchmarks.** Also `/home/bruno/Work/becweb_standards_2025_2026/` (`BECdb_v13_2026.zip`, `BCPlantTaxa2025_access.zip`).
6. **`/home/bruno/Work/spatial_assets/`** — `bc-bgc-v13.pmtiles`, `bc-admin-ecosections-districts.pmtiles`, `bc_ecosections_epsg4326.geojson`, `bc_nr_districts_epsg4326.geojson`.
7. **`/home/bruno/Work/vpro/inst/doc-oracles/`** — Preserved empirical domain oracle specs (`DIAGNOSTIC_CLASSIFICATION.md`, `VALUE_CONVERSIONS.md`, `SHORT_VEG_LAYER_MAPPING_DESIGN.md`, `SHORT_VEG_LAYER_STRATA_ORACLE.md`, `COORDINATE_CONVERSIONS.md`, `ENVIRONMENT_CODE_VALIDATION.md`, `VEGETATION_CODE_VALIDATION.md`, `VEGETATION_OPTIMIZATION_POLICY.md`, `REPORT_QUALITY_FILTER.md`; ignored in tarball builds via `^inst/doc-oracles$` in `.Rbuildignore`).

---

## 5. R Toolchain, Quality Gates & Multi-Agent Worktree Rules

- **Local Toolchain:** R 4.6 (`Rscript` on `PATH`; `Depends: R (>= 4.4.0)`), `quarto` CLI, `air` formatter (`air format R tests`). Keep `TMPDIR`/`TEMP`/`TMP` free of whitespace (`Rscript` aborts at C startup if `R_TempDir` contains spaces).
- **Mandatory Quality Gates (`0 errors | 0 warnings | 0 notes`):**
  ```bash
  Rscript -e "roxygen2::roxygenise()"
  Rscript -e "testthat::test_local(stop_on_failure = TRUE)"
  R CMD build . && R CMD check --no-manual vpro_*.tar.gz
  rm -rf vpro_*.tar.gz vpro.Rcheck
  ```
  *(Always check the built `vpro_*.tar.gz` tarball rather than `R CMD check .`, which under R 4.6 spuriously flags derived `Author`/`Maintainer` fields.)*
- **Multi-Agent Worktree Isolation:**
  - Track multi-wave plans in session SQLite `todos` and `todo_deps`.
  - Give each mutating parallel `general-purpose` subagent an isolated worktree (`/home/bruno/Work/vpro.worktrees/waveN-<track>`) with strictly disjoint `R/<domain>_*.R` and `tests/testthat/test-<domain>_*.R` ownership.
  - Subagents must **not** edit `DESCRIPTION` concurrently or commit generated `NAMESPACE` / `man/*.Rd` files; regenerate `NAMESPACE` and `man/` via `roxygen2::roxygenise()` **only on `master` at each wave merge gate**, verify tests + tarball check, and remove merged worktrees.
  - Specialized repo agents: `vba-analyzer` (read-only VBA/SQL domain math oracle, never UI/forms) and `vproguy` (field-first `roxygen2`, vignettes, Quarto BEC guides, and ecological/SQLite WAL safety warnings).
