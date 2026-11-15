# Headless R Companion SDK Engineering Playbook (`r/` — `vpro` Package)

> **Navigation:** [Master Index](../00_index.md) | **Engineering & Agents:** [Desktop App Engineering](./desktop_app_engineering.md) · `R SDK Engineering` | **Related:** [System Architecture](../02_present_state/system_architecture.md) · [Empirical Oracles](../02_present_state/oracles/DIAGNOSTIC_CLASSIFICATION.md) · [Analytics & Governance](../03_future_architecture/analytics_and_governance.md)

---

## 1. Product Identity & Hard Zero-Shiny Headless Boundary

This playbook preserves every architectural, SQLite WAL concurrency, Access/BEC calibration, PostgreSQL `BECMaster` cloud-governance, and CRAN/`R CMD check` quality-gate rule for the **Headless `vpro` R Companion SDK & Scientific Analytics Package** (`r/`, `R >= 4.4.0`). For concise day-to-day agent rules when working inside `r/`, start at [`r/AGENTS.md`](../../r/AGENTS.md) and root [`AGENTS.md`](../../AGENTS.md).

- **Official Role:** `r/` (`Boostao/vpro` subdirectory `r`, installed via `pak::pak("Boostao/vpro/r")` or `remotes::install_github("Boostao/vpro", subdir = "r")`) is **exclusively the headless `vpro` R Companion SDK** for the **`VPro` 2.0 Desktop Workstation** (`app/` — *VENUS — Vegetation and Environment NexUS — Professional*, **B.C. Ministry of Forests, Research Branch — Biogeoclimatic Ecosystem Classification (BEC) Program**).
- **Target Audience:** BEC research ecologists, quantitative vegetation scientists, spatial/climate modellers, reproducible Quarto / `_targets` pipeline authors operating on local `VP08` SQLite workspaces or Cloud `BECMaster` PostgreSQL, and out-of-process `Rscript --vanilla` invocations from `app/internal/rsidecar`.
- **Desktop GUI Lives Exclusively in `app/`:** `app/` (Wails v3 + Go `1.25+` + Svelte 5 + SQLite WAL + MapLibre GL JS v6 + WebGPU) owns all interactive FS882 / Two-Page / FS1333 (SIVI) forms, universal datasheet grids, `SU`/`Hierarchy` trees, CRUD dialogs, and 3D WebGPU GIS.
- **Strict Zero Shiny / Widget UI Rule:**
  - `shiny`, `bslib`, `DT`, `rhandsontable`, `shinyTree`, `shinyjs`, `sass`, `leaflet`, and `rappdirs` are **strictly forbidden** in `r/DESCRIPTION` (`Depends` and `Imports`).
  - Never create Shiny modules (`mod_*`), app shells (`ui.R`, `server.R`, `global.R`), HTML widgets, interactive modal prompts, or Access-form GUI clones inside `r/`.
  - `.onLoad()` (`r/R/zzz.R`) must remain fast, 100% offline, non-interactive, and side-effect-free (zero network calls, server launches, global option/state mutations, or automatic DuckDB extension installs).
  - **Retired Historical Baggage:** The 4,130-item Access GUI parity ledger and Access-form-to-Shiny translators remain permanently retired and must never be reintroduced or imitated.

### Core R SDK Scope (`25` `r/R/*.R` Modules, `5` Vignettes & `4` Quarto Templates)

1. **Workspace & `VP08` SQLite Layer (`workspace.R`, `import_access.R`):** Cross-OS `vpro_data_dir()` / `vpro_config_dir()` discovery, WAL-safe `RSQLite` connections, `VP08` family inspection (`vpro_project_inspect()`, preserving `isTRUE(insp$compatible)` expected by `app/internal/rsidecar`), Access `.mdb`/`.accdb` ingestion helpers, and optional explicit in-memory DuckDB (`sqlite_scanner`) cross-project queries.
2. **Tidy Ecological Extraction & Taxonomy (`read_plots.R`, `standards.R`, `taxonomy_lump.R`):** Tibble/data-frame readers for `Env`, `Admin`, `Veg`, `Humus`, `Mineral`, `Other`, `Audit`, `Metadata`, `*_SU`, `*_Hierarchy` (`~` breakpoint rollups), `*_Lump`, and harmonized 2026 `VLists.db` (`USysAllSpecs` `BCPlantTaxonomy v19`, `BECdb v13`) + `VUser.db` (`USysUserSpp`) species catalogues.
3. **Standards, Integrity & `LMH25 (2023)` QC Validation (`lmh25_validation.R`, `utils_domain.R`):** Checks calibrated to `V7mdlReportsValidateVegCodes`, `V7mdlReportsValidateEnvData`, `V7mdlReportValidation`, `V7mdlReportsQualityControl` (`DataQuality` ranks `Poor=1..Excellent=4` + lexical `BEC_Use`), `LMH25 (2023)` pedon/substrate/edatopic rules, and read-only duplicate-species diagnostics (`V7mdlOptimizeVeg.Check4DuplicatedSpecies`).
4. **Community Matrices, Plot Profiling & Multivariate Phytosociology (`community_matrix.R`, `clustering.R`, `profiling.R`):** `plot x species` matrices (layer/strata collapsing, `*_Lump` folding with `99%` cap, `sqrt` / `log1p` / `chord` / `hellinger` / `raw` transforms) directly feeding `vegan`, `vegclust` (`NC`, `FCM`, `KM`, `HCLUST`), `indicspecies` (`multipatt` IndVal), and `labdsv`, plus Plot Profiling set algebra (`Add` $\cup$, `Common` $\cap$, `Subtract` $\setminus$).
5. **Spatial, Climate & Edatopic (`CMD -> aSMR`) Workflows (`spatial_sf.R`, `climate_asmr.R`, `edatopic.R`):** `sf` (`EPSG:4326` $\leftrightarrow$ `EPSG:3005` BC Albers, GeoPackage `.gpkg`, `PMTiles`/GeoJSON overlays), `terra`, `bcgov/climr` normals (with offline `r/inst/extdata/bgc_climate_normals.csv` BGC lapse fallback + `__VPRO_PlotClimate` cache), and Ministry `CMD -> aSMR` rules (`aSMR_Rules_HalfStep.csv`, `CMD_adjustments.csv`) for paired Relative (`rSMR x rSNR`) and Actual (`aSMR x rSNR`) edatopic grids.
6. **BEC Diagnostic Synthesis & Summary Reports (`diagnostics.R`, `pairwise_outliers.R`, `summary_reports.R`):** Presence (`I–V`), Domin-Krajina Significance (`+`, `1–9`), Prominence, Goldstream, BEC Differential/Diagnostic species fidelity (`d`, `dd`, `cd`, `c`, `ic` matching `V7mdlDiagnostic` & `app/internal/diagnostics`), pairwise unit similarity, and LOO misplaced-plot detection.
7. **Guarded Non-Destructive Write-Back & Sidecar CLI (`writeback.R`, `sidecar_cli.R`):** Opt-in transactional write-back (`*_ClusterCandidate_SU`, working `*_SU`, `*_Lump`, `__VPRO_PlotClimate`, `__VPRO_RSidecarHistory`) with `<Project>_Audit` + `__VPRO_*` provenance, plus CLI entrypoints invoked by `app/internal/rsidecar`.
8. **Quarto BEC Reporting (`quarto_guides.R`, `r/inst/quarto/{unit_guide,bgc_synopsis,veg_summary_book,qc_audit}.qmd`):** Reproducible BEC Unit, BGC Subzone, Vegetation Summary, and QC Audit HTML/PDF guides (with standalone `rmarkdown`/`knitr` fallback when Quarto CLI is absent) and `_targets`-ready pure functions.
9. **Wave 6 Cloud `BECMaster` PostgreSQL Governance & Snapshots (`cloud_connect.R`, `cloud_read.R`, `cloud_sync.R`, `cloud_snapshots.R`, `r/vignettes/cloud-becmaster-governance-and-sync.Rmd`):** Accredited PostgreSQL/PostGIS `BECMaster` readers, regional WAL `.db` checkout, pre-flight validated staging queue submission, Custodian `SERIALIZABLE` 3-way merge, SHA-256 hash-chained audit verification, and dated `.rds`/SQLite snapshot publishing.

---

## 2. Cross-OS Desktop Workspace & SQLite WAL Interoperability Contract

### 2.1 Exact Directory Resolution (`vpro_data_dir()` & `vpro_config_dir()`)

`r/R/workspace.R` must resolve paths **byte-for-byte identically** to `app/internal/sqlutil/sqlutil_foundation.go` (`UserDataDir()` and `UserConfigDir()`). **Never use `rappdirs`** (on Windows `rappdirs` emits doubled `.../AppData/Local/vpro/vpro`, and on macOS/Linux diverges from Go `os.UserConfigDir()`):

- **`vpro_data_dir()`:**
  1. `getOption("vpro.data_dir")` or `Sys.getenv("VPRO_DATA_DIR")` when non-empty (`normalizePath(..., winslash = "/", mustWork = FALSE)`).
  2. Otherwise by OS (treating empty `""` environment variables as unset):
     - **Windows:** `file.path(Sys.getenv("LOCALAPPDATA"), "vpro")` (fallback: `file.path(Sys.getenv("USERPROFILE"), "AppData", "Local", "vpro")` when `LOCALAPPDATA` is empty).
     - **macOS (`Darwin`):** `file.path(Sys.getenv("HOME"), "Library", "Application Support", "vpro")`.
     - **Linux / Unix:** `file.path(Sys.getenv("XDG_DATA_HOME", unset = file.path(Sys.getenv("HOME"), ".local", "share")), "vpro")`.

- **`vpro_config_dir()` (`config.yml` at `file.path(vpro_config_dir(), "config.yml")`):**
  1. `getOption("vpro.config_dir")` or `Sys.getenv("VPRO_CONFIG_DIR")` when non-empty (`normalizePath(..., winslash = "/", mustWork = FALSE)`).
  2. Otherwise by OS (matching Go `os.UserConfigDir()` + `"vpro"`, treating empty `""` environment variables as unset):
     - **Windows:** `file.path(Sys.getenv("APPDATA"), "vpro")`.
     - **macOS (`Darwin`):** `file.path(Sys.getenv("HOME"), "Library", "Application Support", "vpro")`.
     - **Linux / Unix:** `file.path(Sys.getenv("XDG_CONFIG_HOME", unset = file.path(Sys.getenv("HOME"), ".config")), "vpro")`.

### 2.2 Concurrent SQLite WAL Safety Alongside `app/`

- **Read Connections (Mandatory Default):**
  - Open with `DBI::dbConnect(RSQLite::SQLite(), path, flags = RSQLite::SQLITE_RO)` and register `on.exit(DBI::dbDisconnect(con), add = TRUE)`, or configure managed read handles with `PRAGMA busy_timeout = 5000; PRAGMA synchronous = NORMAL; PRAGMA query_only = ON;`.
  - Percent-encode `#`, `?`, and `%` whenever constructing SQLite `file:` URIs (`?mode=ro`).
  - Never hold idle write transactions, acquire `EXCLUSIVE` locks, or run in-place `VACUUM` against live workspace `.db` files open in the desktop app (`app/`).
- **Guarded Opt-In Write-Back (`BEGIN IMMEDIATE`):**
  - **Permitted write targets only:** `<Name>_ClusterCandidate_SU`, user-confirmed working `<Name>_SU`, `<Name>_Lump`, `__VPRO_PlotClimate`, and `__VPRO_RSidecarHistory`.
  - Set `PRAGMA busy_timeout = 5000; PRAGMA synchronous = NORMAL; PRAGMA foreign_keys = ON;` and wrap every mutation in an explicit `BEGIN IMMEDIATE ... COMMIT` transaction with clean `ROLLBACK` on error.
  - **Hard Refusal Guards:** Unconditionally reject writes targeting `Master*` tables (or prefixes matching `"master"` case-insensitively), `USys*` tables/views, bundled `VLists.db`, or custodian-locked `BECSiteUnit` without explicit authorization. Require `confirm_overwrite = TRUE` before replacing existing `*_SU` or `*_Lump` tables.
  - **Atomic Provenance:** Append `<Project>_Audit` rows and `__VPRO_*` provenance/identity reservations inside the **same** `BEGIN IMMEDIATE` transaction; never reuse deleted child IDs.

---

## 3. Preserved `VP08`, Access Calibration & Empirical Oracle Rules

All ecological calculations and validators in `r/` are anchored to the 9 empirical Access/BEC oracle contracts in [`okf/02_present_state/oracles/`](../02_present_state/oracles/) and reproducible DAO fixtures in `r/data-raw/oracle/` and [`r/data-raw/projects/VEGETATION_DUPLICATES.md`](../../r/data-raw/projects/VEGETATION_DUPLICATES.md):

| Empirical Oracle Document | Calibrated Legacy Source & R SDK Contract |
|---|---|
| [`COORDINATE_CONVERSIONS.md`](../02_present_state/oracles/COORDINATE_CONVERSIONS.md) | `V7mdlCoordTools` (`ConvertLongLatToDeg`, `GetLongDMS`/`GetLatDMS`, `GetLongDM`/`GetLatDM`) in R `double` precision without VBA `Single` intermediate drift. |
| [`DIAGNOSTIC_CLASSIFICATION.md`](../02_present_state/oracles/DIAGNOSTIC_CLASSIFICATION.md) | `V7mdlDiagnostic.Diagnostic` & `MakeDiagnosticData` (`d`, `dd`, `cd`, `c`, `ic`, first-field tie-break, `+ -> 0`, unreachable `ic` under `1..5` presence). |
| [`ENVIRONMENT_CODE_VALIDATION.md`](../02_present_state/oracles/ENVIRONMENT_CODE_VALIDATION.md) | `V7mdlReportsValidateEnvData` (`USysTableOfLists` `ValidateLoops` expansion e.g. `SiteDisturbance1..3`, `USysEnv` active-SU scope, deterministic `findings` + `skipped`). |
| [`REPORT_QUALITY_FILTER.md`](../02_present_state/oracles/REPORT_QUALITY_FILTER.md) | `V7mdlReportsQualityControl` (`QC` vs `QCLV`, `DataQuality` `Poor=1..Excellent=4`, independent null flags, lexical `BEC_Use >= threshold`, explicit `Project` orphan diagnostics). |
| [`SHORT_VEG_LAYER_MAPPING_DESIGN.md`](../02_present_state/oracles/SHORT_VEG_LAYER_MAPPING_DESIGN.md) | Versioned `LayerCode` mapping (`Layer1234567` join key vs legacy padded `LayerCode` lifeform bug). |
| [`SHORT_VEG_LAYER_STRATA_ORACLE.md`](../02_present_state/oracles/SHORT_VEG_LAYER_STRATA_ORACLE.md) | `ConvertProVeg2V2` & `BuildStrataTable` (`TotalA`/`TotalB` authoritative override vs `99%`-capped sub-layer sum; positive-only A/B strata vs non-null zero C/D). |
| [`VALUE_CONVERSIONS.md`](../02_present_state/oracles/VALUE_CONVERSIONS.md) | `V7mdlValueConversions` (`Presence2Class` `I–V`, `SignifClass` `+`/`1–9`, `ProminenceClass`, `GoldstreamClass`, no-op `vpRoundUp` identity, `vpRoundDown1` cap at 100, ACE 15-sig-digit rounding). |
| [`VEGETATION_CODE_VALIDATION.md`](../02_present_state/oracles/VEGETATION_CODE_VALIDATION.md) | `V7mdlReportsValidateVegCodes.CheckVegData` (physical `USysAllSpecs.Code` left join, active-SU vs full-project orphan plot semantics). |
| [`VEGETATION_OPTIMIZATION_POLICY.md`](../02_present_state/oracles/VEGETATION_OPTIMIZATION_POLICY.md) | Full-run DAO & `_Audit` probe of `V7mdlOptimizeVeg.OptimizeVeg` (`First()` order sensitivity, singleton ID regeneration breaking `_Audit` joins) & deterministic minimum-ID survivor policy. |

### Eight Non-Negotiable Domain Invariants

1. **7-DB SQLite Family & `_table_metadata` (`'VP08'`):**
   - `<Project>.db` (8 tables per prefix `<P>`: `_Env`, `_Admin`, `_Veg`, `_Humus`, `_Mineral`, `_Other`, `_Audit`, `_Metadata`), `VPro64.db`, `VLists.db`, `VUser.db`, `VMetaData.db`, `VMessageBoard.db`, `VPics.db`.
   - Never invent `_Env.StartDate` or an `Env -> Metadata` FK (confirmed dead VBA in `V7mdlRelationships`).
   - Preserve shared `<Project>.db` tables: `__VPRO_PlotClimate` (`PlotNumber TEXT PRIMARY KEY`, `CoordElevHash`, `RefPeriod`, `Source`, `MAT`, `MWMT`, `MCMT`, `MAP`, `MSP`, `PAS`, `CMD`, `PPT_05`..`PPT_09`, `PPT_at`, `PPT_wt`, `DD5`, `NFFD`, `ComputedAt`), `<Name>_ClusterCandidate_SU`, `<Name>_SU` (`PlotNumber`, `SiteUnit`), `<Name>_Lump` (`SppCode`, `LumpCode`, `Use`), `<Name>_Hierarchy` (`~Name` breakpoint semantics), and `__VPRO_RSidecarHistory`.
2. **Literal `character` `PlotNumber` (`Text 7`):**
   - Always R `character` and SQLite `TEXT` (`typeof("PlotNumber") = 'text'`, `CAST("PlotNumber" AS BLOB) = CAST(? AS BLOB)` when guarding affinity). Never strip leading zeroes (`'00337'`) across SQL, CSV readers, community matrix row names, `sf` features, or JSON.
3. **Access `BOOLEAN` Storage (`-1` vs `0`):**
   - On-disk SQLite and `<Project>_Audit` rows store **`-1L` = `TRUE`**, **`0L` = `FALSE`**, `NULL` = `NA`. Normalize non-zero integers to `TRUE` on read into R `logical`; serialize `TRUE -> -1L`, `FALSE -> 0L`, `NA -> NULL` on write.
4. **IEEE-754 `float32` Cover Narrowing & `99%` Lumped Cap:**
   - Narrow `double` inputs to IEEE-754 `float32` *before* checking `< 100` (`99.999996 -> 99.99999237 < 100` passes; `99.999999 -> 100.0` rejects).
   - Taxonomic lumping (`<Name>_Lump` where `Use != 0`, `UPPER(TRIM(SppCode)) -> UPPER(TRIM(LumpCode))`) and fallback `TotalA`/`TotalB` sums cap per-layer summed cover at **`99%`** (`pmin(sum_cover, 99)`), never mutating raw `<Project>_Veg`. State explicitly when Pielou probabilistic stratum overlap $100 \times (1 - \prod_i (1 - c_i / 100))$ is used instead of additive sums.
5. **ACE 15-Significant-Digit Rounding & BEC Thresholds:**
   - Format `double` to 15 significant decimal digits before half-away rounding (`1.005 -> 1.01` at 2 decimals) for calibrated Access/Plot Profiling/report outputs.
   - Thresholds: Presence `I–V` (`<= 0.2, 0.4, 0.6, 0.8, > 0.8`), Domin-Krajina Significance `+` (`<= 0.3`, weight `0`) & `1–9` (`<= 1.0, 2.2, 5.0, 10.0, 20.0, 33.0, 50.0, 75.0, > 75.0`), Prominence (`mean_cover * 10 * sqrt(presence)` at `15, 50, 100, 200`), Goldstream (`presence * 100 * sqrt(mean_cover)` at `5, 25, 75, 150, 300, 500`).
6. **Species Catalogue Asymmetry & Layer Mapping:**
   - `VLists.USysAllSpecs.Lifeform` is `INT32` (`LONG`) vs. `VUser.USysUserSpp.LifeForm` `INT16` (`INTEGER`). Exclude synonyms (`LOWER(Codetype) = 's'`) in 5-field `USysAllSpecies` unions and surface conflicting used-code tuples rather than silently picking `First()`. Join short-veg layer keys on `LayerCode.Layer1234567` (never padded `LayerCode.LayerCode`).
7. **`LMH25 (2023)` Soil Horizon Ordering:**
   - **Upland organic (`L`, `F`, `H`):** upward from `0 cm` (`UpperDepth > LowerDepth`, ordered **`UpperDepth DESC`**).
   - **Wetland organic (`Of`, `Om`, `Oh`) & Mineral (`A`, `B`, `C`, `R`, `W`):** downward from `0 cm` (`UpperDepth < LowerDepth`, ordered **`UpperDepth ASC`**).
8. **UTF-16 Code-Unit Limits:**
   - Enforce Access UTF-16 code-unit bounds (`PlotNumber <= 7`, `Species <= 8`, `Horizon <= 8`, `Texture <= 4`, `Colour <= 14`, quality labels `<= 15`) and reject malformed UTF-8 or unpaired surrogates.

---

## 4. Wave 6 Cloud `BECMaster` PostgreSQL Governance, Staging & 3-Way Merge (`r/R/cloud_*.R`)

`r/R/cloud_connect.R`, `cloud_read.R`, `cloud_sync.R`, and `cloud_snapshots.R` interoperate directly with Go `app/internal/cloudsync` over the shared 3-schema PostgreSQL/PostGIS contract (`becmaster`, `staging`, `standards`), keeping `RPostgres` optional in `Suggests` so offline users never require PostgreSQL client libraries:

1. **Credentials, Secret Redaction & Transport Security (`cloud_connect.R`):**
   - Resolve credentials strictly via explicit parameters, `VPRO_PG_*` / `BECMASTER_*` environment variables, or local `.env` / `becmaster.env` files (`vpro_has_pg_credentials()`, `vpro_master_connect()`, `vpro_master_disconnect()`, `vpro_master_status()`, `vpro_master_bootstrap()`); `.env*` files must remain excluded in `.gitignore` and `r/.Rbuildignore`.
   - Never print, log, or serialize raw passwords, tokens, or unredacted DSNs in `vpro_master_con` S3 print methods or error conditions.
   - Enforce TLS (`sslmode = "require"` or `"verify-full"`) for all non-loopback PostgreSQL hosts, and bind accredited session role/actor context (`public`, `contributor`, `ecologist`, `custodian`) for PostgreSQL Row-Level Security (RLS) policies.
2. **Accredited Read Queries, Rare-Plant Redaction & Regional WAL Checkout (`cloud_read.R`):**
   - `vpro_master_env()`, `vpro_master_veg()`, `vpro_master_soil()`, `vpro_master_audit()`, `vpro_master_standards()`, and `vpro_master_workspace()` return tidy `VP08`-typed tibbles preserving literal `character` `PlotNumber` and `-1/0 -> logical` `BOOLEAN` conversion.
   - Public/anonymous roles receive approved snapshot views with sensitive Red/Blue-listed rare-plant coordinates redacted (`USysSppAttributes.RedBlueList`).
   - `vpro_master_pull()` materializes filtered regional or BGC subsets into canonical WAL-mode `VP08` SQLite `.db` files ready for immediate offline use in `app/` or `r/`, atomically recording every checkout in `becmaster.download_log`.
3. **Pre-Flight Compliance Gate, Staging Queue & Custodian `SERIALIZABLE` 3-Way Merge (`cloud_sync.R`):**
   - `vpro_staging_submit()` runs mandatory pre-upload compliance validation (`USysTableOfLists`, `USysAllSpecs` taxonomy + `UserSpeciesManifest` capture, 1:N FK integrity, UTF-16/numeric/`LMH25` bounds) before writing an immutable submission bundle into `staging.submissions` (enforced server-side by RLS + `BEFORE INSERT` compliance/role triggers).
   - `vpro_staging_list()`, `vpro_staging_inspect()`, and `vpro_staging_diff()` (`vpro_merge_preview`) compute deterministic plot- and field-level 3-way diffs (`added`, `identical`, `fast_forward`, `conflict`) against baseline watermarks.
   - `vpro_staging_merge()` requires `custodian` role authorization and executes inside a **`SERIALIZABLE` PostgreSQL transaction**: applies explicit conflict resolutions (`accept_source` vs. `keep_target`), allocates monotonic `becmaster` `child_identity` IDs (never reusing deleted child IDs), advances watermarks, records `becmaster.merge_ledger`, and appends SHA-256 hash-chained `becmaster.audit` entries (`prev_hash` $\rightarrow$ `entry_hash`).
   - `vpro_master_verify_audit()` cryptographically verifies the unbroken `prev_hash` $\rightarrow$ `entry_hash` SHA-256 chain across `becmaster.audit`. `vpro_staging_reject()` records structured rejection provenance, and `vpro_standards_sync()` publishes or pulls versioned `BCPlantTaxonomy v19` & `BECdb v13` releases with atomic local `VLists.db` swap.
4. **Approved Dataset Snapshots (`cloud_snapshots.R`):**
   - `vpro_publish_snapshot()`, `vpro_list_snapshots()`, `vpro_write_rds_snapshot()`, and `vpro_read_rds_project()` cut, register, and round-trip SHA-256-verified `.rds` and read-only SQLite snapshots carrying pinned `AllSpecs` / `TableOfLists` / `BECdb` version stamps (`Schedule A 1.iii, 2.i`).

---

## 5. Sibling Asset Discovery, R Toolchain, `air` & Mandatory Quality Gates

- **Explicit Sibling Paths:** Workspace `glob`/`grep` default to the `Boostao/vpro` monorepo root (`app/`, `r/`, `okf/`). Pass explicit absolute paths for external sibling references (`/home/bruno/Work/VPRO_ACCESS/`, `/home/bruno/Work/VPRO_ACCESS_1/VPro64/BECMaster_fixing.accdb` [strictly read-only], `/home/bruno/Work/becweb_standards_2025_2026/`, `/home/bruno/Work/MoF-Skeena-Research/`, `/home/bruno/Work/bcgov_ref/`, `/home/bruno/Work/spatial_assets/`).
- **Local R Toolchain & Formatting:**
  - R 4.6 (`Rscript` on `PATH`; package `Depends: R (>= 4.4.0)`), `quarto` CLI, and `air` formatter (`(cd r && air format R tests)` using `r/air.toml`).
  - Keep `TMPDIR` / `TEMP` / `TMP` free of whitespace (`Rscript` aborts at C startup if `R_TempDir` contains spaces).
- **Mandatory Quality Gates (`0 errors | 0 warnings | 0 notes`):**
  ```bash
  (cd r && air format R tests)
  (cd r && Rscript -e "roxygen2::roxygenise()")
  (cd r && Rscript -e "testthat::test_local(stop_on_failure = TRUE)")
  (cd r && R CMD build . && R CMD check --no-manual vpro_*.tar.gz && rm -rf vpro_*.tar.gz vpro.Rcheck)
  ```
  *(Always run `R CMD check --no-manual` on the built `vpro_*.tar.gz` tarball rather than `R CMD check .`, which under R 4.6 spuriously flags derived `Author`/`Maintainer` fields. Keep `^AGENTS\.md$` in `r/.Rbuildignore` so `r/AGENTS.md` never triggers a top-level file `NOTE`.)*
- **Multi-Agent Worktree Isolation & `roxygen2` Merge Gate:**
  - Isolate parallel mutating subagents in `/home/bruno/Work/vpro.worktrees/waveN-<track>` with strictly disjoint `r/R/<domain>_*.R` and `r/tests/testthat/test-<domain>_*.R` file ownership.
  - Subagents must **not** edit `r/DESCRIPTION` concurrently or commit generated `r/NAMESPACE` / `r/man/*.Rd` files in parallel feature branches; regenerate `r/NAMESPACE` and `r/man/` via `roxygen2::roxygenise()` at wave merge gates, verify `test_local` + tarball `R CMD check`, and prune merged worktrees.
  - Specialized repo agents in `.github/agents/`: `vba-analyzer` (read-only Access VBA/SQL domain math oracle — never UI/forms) and `vproguy` (field-first `roxygen2`, vignettes, Quarto BEC guides, and ecological/SQLite WAL safety disclosures).
