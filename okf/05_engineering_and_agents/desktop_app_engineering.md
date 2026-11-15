# Desktop Workstation Engineering Playbook (`app/` — Go, Wails v3 & Svelte 5)

> **Navigation:** [Master Index](../00_index.md) | **Engineering & Agents:** `Desktop App Engineering` · [R SDK Engineering](./r_sdk_engineering.md) | **Related:** [System Architecture](../02_present_state/system_architecture.md) · [Empirical Oracles](../02_present_state/oracles/DIAGNOSTIC_CLASSIFICATION.md) · [Analytics & Governance](../03_future_architecture/analytics_and_governance.md)

---

## 1. Scope, Product Identity & Anti-Drift Governance

This playbook preserves the complete engineering invariants, 4-layer Go architecture, Wails v3 IPC/COM guards, Access calibration contracts, and PostgreSQL `BECMaster` sync rules for the **VPro 2.0 Desktop Workstation** (`app/`, Go module `github.com/boostao/vpro/app`). For day-to-day agent routing inside `app/`, start at [`app/AGENTS.md`](../../app/AGENTS.md) and root [`AGENTS.md`](../../AGENTS.md).

- **Authoritative In-Tree Specifications (`okf/`):**
  - [`okf/00_index.md`](../00_index.md), [`okf/02_present_state/capability_matrix.md`](../02_present_state/capability_matrix.md), and [`okf/02_present_state/data_dictionary.md`](../02_present_state/data_dictionary.md)
  - Empirical Access/BEC oracle contracts in [`okf/02_present_state/oracles/`](../02_present_state/oracles/)
  - [`okf/03_future_architecture/transition_and_adoption.md`](../03_future_architecture/transition_and_adoption.md), [`target_stack_recommendation.md`](../03_future_architecture/target_stack_recommendation.md), [`analytics_and_governance.md`](../03_future_architecture/analytics_and_governance.md), [`intelligent_automation_and_abstractions.md`](../03_future_architecture/intelligent_automation_and_abstractions.md) (`Auto-1`..`Auto-7`), and [`documentation_help_and_release_portal.md`](../03_future_architecture/documentation_help_and_release_portal.md)
  - [`okf/04_evidence_and_sources/decisions_and_gaps.md`](../04_evidence_and_sources/decisions_and_gaps.md)
- **Historical Archive Only (`archive/oct2026-parity-ledgers/`):** Superseded October 2026 slice-by-slice parity ledgers (`MIGRATION_PLAN.md`, `WINDOWS_HANDOFF.md`, `CLIENT_SCOPE.md`, `FEATURE_CAPABILITIES.md`, `*_CONTRACT.md`) are retained strictly for historical provenance. **They do NOT govern scope, feature gating, or work organization.**
- **Feature Graduation & Build-Tier Rules:**
  - Validated workflows run **unconditionally default-ON** in standard `-tags sqliteonly` builds (`PRAGMA journal_mode = WAL`).
  - Do **not** introduce `VITE_*` or per-slice `VPRO_*` feature-flag sprawl. Use `config.yml` `release_channel: stable | experimental` for user-facing Phase 2 preview controls, and `app/internal/lifecycle/buildinfo.go` (`buildMode: "dev" | "alpha" | "release"`, `-ldflags "-X github.com/boostao/vpro/app/internal/lifecycle.buildMode=..."`) for compile-time build-tier gating (`VPRO_WEBVIEW_DEBUG_PORT` is restricted strictly to `dev` builds).
  - Follow Will MacKenzie's verified `VPro2.0_Functions` triage (`Red = Remove`, `Orange = Deferred`, `Green/Unmarked = Priority Retain/Modify`): keep Red-marked over-builds (`PC-ORD Break Report` and standalone `CHARS` forms/menus) pruned, and expose CHARS Arctic extensions (`Cover5a..5c`, `Height5a..5c`, `SnowCoverregime`, `ActiveLayerDepth`) exclusively via the inline `"Show extended shrub layers"` toggle on standard FS882, Two-Page, and SIVI forms.
- **Product Identity & Packaging Boundaries:**
  - Official product identity is **`VPro`** (*VENUS — Vegetation and Environment NexUS — Professional*, **B.C. Ministry of Forests, Research Branch — Biogeoclimatic Ecosystem Classification (BEC) Program**; macOS bundle `VPro.app`) — never `"My Company"`, `"My Product"`, `"Wails Edition"`, or `vpro-wails.app`.
  - Release packages are **unsigned for Phase 1** (`"unsignedNotice": true`), relying on static `site/release-manifest.json` + `SHA256SUMS.txt` verification (zero runtime `api.github.com` browser rate-limiting).
  - `VTrees` / standalone Mensuration, CWD, and WHA remain **out of scope** for Phase 1 (`D-09`).

---

## 2. Surrounding Workspace & Sibling Asset Map (`/home/bruno/Work/`)

Workspace `glob` and `grep` tools default solely to the `Boostao/vpro` monorepo root. Always pass explicit absolute `paths` when inspecting external sibling directories under `/home/bruno/Work/`, include relevant sibling paths in subagent prompts, and **never mutate `.accdb`/`.mdb`/`.zip` source archives**:

1. **In-Tree Monorepo Companions (`Boostao/vpro`):**
   - `okf/` — Authoritative Operational Knowledge Framework, 9 empirical oracles (`okf/02_present_state/oracles/`), and engineering playbooks (`okf/05_engineering_and_agents/`).
   - `r/` — Official headless `vpro` R Companion SDK (`r/R/*.R`, `r/inst/extdata/`, `r/inst/quarto/*.qmd`, `r/data-raw/oracle/`).
   - `docs-src/`, `site/`, `scripts/` — Single-source offline `F1` `LMH25 (2023)` help compiler (`scripts/build-docs-src.mjs` $\rightarrow$ `app/resources/help_bundle.json`), BC Gov Design System download portal (`site/build.mjs` $\rightarrow$ `site/dist`), and release/PE verification scripts (`scripts/release.py`).
2. **Legacy Manuals, Triage, Correspondence & Decompiled `VPro64` Exports (`/home/bruno/Work/VPRO_ACCESS/`):**
   - Field & Legacy Manuals: `LMH25_2023_web.pdf` (2023 ed.), `Lmh25_2015.pdf` (2015 ed.), `VProXP_Userguide.pdf`.
   - Client Scope & Triage: `VPro2.0_Functions to remove-retain-modify.pdf` (`.docx`), `_BEC_data_system_fs1a_schedule_of_services_v2 (13).md`, `VproMailExchange/` (106 emails incl. executed contract `RE26OCF433` in `0072`), `SCREENCAPS/` (21 VPro 64 PNGs).
   - Decompiled Access Forms/VBA/Tables: `VPro64_forAI/` (`Modules/`, `Queries/`, `Forms/`, `Tables_Data/`, `Tables_Def/`), `VPro64/`, `VLists/`, `VUser/`, `VMetaData/`, `Diagnostic10.xla`.
3. **545 MB Production-Scale Provincial Dataset (`/home/bruno/Work/VPRO_ACCESS_1/VPro64/`):**
   - `BECMaster_fixing.accdb` (`71,567` plots, `1,651,842` veg rows, `597,277` audit rows, `BECMaster_fixing_edatopic` `57,023` rows, `spatial_overlay_BGCv13_4/8`), `Haida_Gwaii_2019.accdb`, `Manning_TEM_Vpro19.accdb` (strictly read-only).
4. **2026 Official `BECWeb` Master Standards (`/home/bruno/Work/becweb_standards_2025_2026/`):**
   - `BECdb_v13_2026.zip` (`BECdb_v13_2026.accdb` `2026-05-28` Version 13 + `Current_BGCunits_v13.csv` + `Current_Unique_SiteUnits_v13.csv`).
   - `BCPlantTaxa2025_access.zip` (`BCPlantTaxonomy.accdb` `2026-02-09` Version 19 `USysAllSpecs`) + `Species_Readme_Feb_2025_Ver19.docx` + `Tree_codes_2021.docx`.
5. **Staged BC Gov Spatial Layers (`/home/bruno/Work/spatial_assets/`):**
   - `bc-bgc-v13.pmtiles`, `bc-admin-ecosections-districts.pmtiles`, `bc_ecosections_epsg4326.geojson` (`139` polygons), `bc_nr_districts_epsg4326.geojson` (`23` polygons), plus live unauthenticated BC OpenMaps WFS `pub:WHSE_FOREST_VEGETATION.BEC_BIOGEOCLIMATIC_POLY` (`17,870` BGC polygons).
6. **Cloned MoF & BCGov Reference Repos & CGO MDB Upstream:**
   - `/home/bruno/Work/MoF-Skeena-Research/`: `BEC_R_working` (`_functions/*.R`), `BEC_Classification_Analysis`, `BEC_Unit_Reporting` (`unit.report.qmd`), `aSMR-x-rSMR` (`CMD -> aSMR`), `EdatopicGrid_Spp_Distribution`, `BEC_Clean_BECdb`, `BEC_soils_fixing`, `BGC_Postgres`, `CCISS_VectorTiles`.
   - `/home/bruno/Work/bcgov_ref/`: `BEC_ReportR`, `cciss-docs`.
   - `/home/bruno/Work/go-mdbtools/` (CGO `libmdb` upstream hardening reference).
7. **Isolated Parallel Worktrees:** `/home/bruno/Work/vpro.worktrees/waveN-<track>` (`../vpro.worktrees/waveN-<track>`).

---

## 3. 4-Layer Acyclic Go Architecture (`github.com/boostao/vpro/app`) & 12 Wails Services

The Go backend in `app/` (`module github.com/boostao/vpro/app`) enforces a strict **4-layer acyclic directed graph (DAG)** verified continuously by `app/internal/integration/architecture_dag_test.go`:

1. **Layer 0 — Embedded Assets & Foundations (zero domain imports):**
   - `app/resources` (`app/resources/embed.go` exporting embedded `embed.FS` and `[]byte` assets + `RepoRoot()` / `Path(...)`),
   - `app/internal/sqlutil` (`UserDataDir`, `UserConfigDir`, `ValidateRawJSONWire`, `DecodeStrictJSON`),
   - `app/internal/accessreader` (vendored `mdbtools` `1.0.1` C `libmdb` across `linux || windows || darwin`, compiled with `-fvisibility=hidden` on Linux CGO so vendored `fakeglib` never interposes on GTK4/WebKitGTK, and `-static` on Windows MinGW with zero non-inbox PE DLL imports; sticky `GO_MDB_ERROR_*` error guards),
   - `app/internal/accessimport`, `app/internal/accessinventory`, `app/internal/accesslayout`, `app/internal/accesscompare`, `app/internal/fs882layout`, `app/internal/listcatalog`, `app/internal/reports/subzonematrix`.
2. **Layer 1 — Core Context, Reference Catalogues & Shared Engines:**
   - `app/internal/references` (`BECService`, `ReferenceService`, `Site/Soil/Parent/Geology/Region/Quality` code services),
   - `app/internal/vprocore` (`SQLiteContext`, `DesktopConfig`, `DatabaseFamily`, `ProjectService`, `ContextService`, `PlotService` + `app/internal/vprocore/vprotest`),
   - `app/internal/sourceform` (+ `app/internal/sourceform/sftest`),
   - `app/internal/reports/reportcore`.
3. **Layer 2 — Independent Parallel Domain Packages (strictly zero sibling Layer-2 imports):**
   - `app/internal/lifecycle`, `app/internal/plotentry`, `app/internal/sivi`, `app/internal/twopage`, `app/internal/datasheet`, `app/internal/classification`, `app/internal/validation`, `app/internal/vegreport`, `app/internal/envreport`, `app/internal/spatial`, `app/internal/pictures`, `app/internal/interchange`, `app/internal/cloudsync`, `app/internal/projectops`, `app/internal/diagnostics`, `app/internal/lumping`, `app/internal/lmh25rules`, `app/internal/rsidecar`
   - Cross-domain integration tests reside solely in `app/internal/integration/*_test.go`; offline extraction CLIs reside in `app/cmd/*`.
4. **Layer 3 — Thin Wails Host (`package main` in `app/`):**
   - `app/main.go`, `app/native_options.go`, `app/aliases.go`, and `app/domainservices_*.go` register **strictly 12 cohesive Wails domain services**:
     1. `LifecycleService` — startup/recovery hints, cryptographic close nonce (`CloseService`), `USysUserLog` review.
     2. `ContextService` — active `Project`/`SU`/`Hierarchy` switching, 128-bit `contextID` fencing, `New/SaveAs/Splinter/Compare/Merge`, scoped plot lookup, and 19 `cloudsync` RPCs (preserving the 12-service ceiling).
     3. `PlotEntryService` — 6-tab FS882, Two-Page (`twopage`), FS1333 SIVI (`sivi`), inline CHARS shrub-layer toggle, live `LMH25 (2023)` rules (`lmh25rules`), `ProjectMetadata` presets & auto-derivation.
     4. `DatasheetService` — universal spreadsheet grid (`_Env`, `_Admin`, `_Veg`, `_Humus`, `_Mineral`, `_Other`, `_SU`), global search, TSV paste (`datasheet`).
     5. `ClassificationService` — dual-pane `SU`/`Hierarchy` tree explorer, `Env <-> SU` sync, Plot Profiling, `Combine Species` (`*_Lump` + `LumpSpec`), reactive BEC Diagnostics (`diagnostics`), R Sidecar (`rsidecar`).
     6. `ValidationService` — batch `USysTableOfLists` picklist & numeric bounds compliance gate, 1:N FK integrity, `SpeciesCodeCheck`, transactional `OptimizeVeg`.
     7. `ImportExportService` — Access `VP05`–`VP08` (`545 MB` `BECMaster` streaming + orphan quarantine), `VENUS 5.0`, official `TurboVeg 3` 31-table SQLite & `Plot_package` XML, `.gpkg`, `.rds`, Long/Wide CSV & Store `.zip`, `User Species`, Label PDF.
     8. `VegetationReportService` — Summary & Long Vegetation previews and `.xlsx` workbooks, SiteUnit suffix exclusions, Lifeform & Species Attributes summaries.
     9. `EnvironmentReportService` — Long Environment, Site Unit Summary (mean/quartiles + qualitative), and Subzone Matrix previews & `.xlsx` workbooks.
     10. `SpatialService` — MapLibre v6 + `PMTiles` byte-range streaming, NAD83 `UTM <-> DD` geodetic QA, FlatGeobuf BGC/Ecosection/District auto-stamp, AOI $\rightarrow$ `*_SU`, KML 2.1.
     11. `PictureService` — cold-boot `VPics.db` seeding, plot photo browser, metadata editing, native OS file dialogs, add/delete/restore.
     12. `HelpService` — offline `F1` `LMH25 (2023)` contextual help (`app/resources/help_bundle.json`), 4 spotlight tours, keyboard shortcuts, `What's New`, lock-safe `Reset Workspace to Sample`, `About & Standards Stamps`.

### Frontend Svelte 5 Domain Organization (`app/frontend/`)

- Preserve the 13-domain directory layout under `app/frontend/src/{shell,entry,datasheet,classification,reports,spatial,diagnostics,rsidecar,interchange,admin,pictures,help,shared}/` and the single-pass Node test suite under `app/frontend/tests/` (`app/frontend/scripts/run-tests.mjs` + shared wire round-trip `fixtures/`).

---

## 4. Preserved Backend, Domain & Calibration Invariants (Must Not Regress)

### 4.1 Canonical SQLite Family, Cross-OS Directories & `SQLiteContext` Isolation (`app/internal/vprocore/sqlitecontext.go`)

1. **7-Database SQLite Family & `config.yml`:**
   - Preserve `<Project>.db` (`VP08` 8 core tables: `_Env`, `_Admin`, `_Veg`, `_Humus`, `_Mineral`, `_Other`, `_Audit`, `_Metadata`), `VPro64.db`, `VLists.db`, `VUser.db`, `VMetaData.db`, `VMessageBoard.db`, `VPics.db`, `_table_metadata` (`'VP08'`), and `config.yml` (with lossless legacy JSON migration).
   - Embedded reference `.db` files in `app/resources/` are read-models, **never** replacements for `VLists.db` / `VUser.db`.
   - `app/internal/sqlutil/sqlutil_foundation.go` (`UserDataDir()` and `UserConfigDir()`) defines the shared workspace contract consumed identically by `r/R/workspace.R` (`VPRO_DATA_DIR` / `VPRO_CONFIG_DIR` overrides first; Windows `%LOCALAPPDATA%\vpro` & `%APPDATA%\vpro`; macOS `~/Library/Application Support/vpro`; Linux `${XDG_DATA_HOME:-~/.local/share}/vpro` & `${XDG_CONFIG_HOME:-~/.config}/vpro`).
2. **URI Escaping & TOCTOU Protection:**
   - Always build SQLite `file:` URIs from resolved absolute paths using proper `net/url` escaping (`#`, `?`, or `%` in raw file paths can truncate `mode=ro`!) and verify `os.SameFile` before and after `ATTACH DATABASE`.
3. **Pinned `:memory:` Read Coordinator & Snapshot Cleanup:**
   - On the pinned `:memory:` read coordinator (`MaxOpenConns(1)`), use caller-owned read snapshot cleanup (`beginReadSnapshot`) so cancelled queries never drop `ATTACH`ed databases or `TEMP` `USys*` views (`Filtered_Env`, `USysEnv`, `USysVeg`, `USysVegA..D`, `USysHumus`, `USysMineral`, `USysOther`, `USysAuditTrail`, `USysMetadata`, `MasterSiteUnitList`, `USysSU`, `USysHierarchy`).
4. **Deadlock-Free Read-Lease Reuse & 128-Bit `contextID` Epoch Fencing:**
   - Scoped operations already holding the context's operation read lease must reuse it when borrowing pools rather than recursively re-acquiring `RWMutex.RLock` (prevents reader-writer deadlock behind a queued context switch).
   - Every context switch mints a new 128-bit `contextID`; deterministically reject stale IPC requests carrying an older `contextID`.

### 4.2 Data Types, Validation & Access Calibration (`okf/02_present_state/oracles/`)

- **Atomic Mutations & Monotonic Child Identity Reservations:**
  - Parent/child mutations, `<Project>_Audit` rows (`AuditStrength` `0..3`), and `__VPRO_*` identity/history reservations (`__VPRO_ChildIdentity`, `__VPRO_ProfileIdentity`, `__VPRO_PictureCreationIdentity`, etc.) share a single atomic SQLite transaction (`BEGIN IMMEDIATE` on `c.projectDB` with `_foreign_keys=on&_busy_timeout=5000`). **Never reuse deleted child IDs.**
- **Access `BOOLEAN` Encoding:**
  - Normalize reads explicitly and preserve `true = -1`, `false = 0` (`NULL` = `nil`) in SQLite storage and `<Project>_Audit` rows.
- **IEEE-754 `SINGLE` (`float32`) Cover Narrowing:**
  - Narrow `float64` cover inputs to `float32` *before* evaluating `<100 Or Is Null` (`99.999996` narrows to `99.99999237060547` and passes; `99.999999` narrows to `100` and rejects). Cap lumped (`*_Lump`) and fallback `TotalA`/`TotalB` strata sums at `99%` without mutating raw `<Project>_Veg`.
- **ACE Fixed-Decimal Rounding ([`VALUE_CONVERSIONS.md`](../02_present_state/oracles/VALUE_CONVERSIONS.md)):**
  - Format `DOUBLE` to 15 significant decimal digits before half-away rounding (`1.005 -> 1.01` at 2 decimals; reuse the calibrated decimal formatter in Plot Profiling and reports).
- **UTF-16 Code-Unit Bounds & Strict Wire JSON Decoding:**
  - Enforce Access field lengths in UTF-16 code units (`PlotNumber <= 7`, `Species <= 8`, `Horizon <= 8`, `Texture <= 4`, `Colour <= 14`, quality labels `<= 15`).
  - Reject malformed UTF-8 (`CAST(X'FF' AS TEXT)`) and duplicate/raw-surrogate JSON keys *prior* to Go JSON repair via `sqlutil.ValidateRawJSONWire` / `sqlutil.DecodeStrictJSON`.
- **Historical Field Tolerance:**
  - Omit unchanged historical out-of-rule columns on `UPDATE` so legacy plots (e.g., 1980s DEIF records) can be edited without failing validation on untouched fields.
- **Literal Scoped `PlotNumber` Lookup:**
  - Use `typeof(col)='text'` and `CAST(col AS BLOB)=CAST(? AS BLOB)` so SQLite numeric affinity never coerces leading-zero plot numbers (e.g., `'00337'`).
- **Species Catalogue Widths & Layer Mapping ([`SHORT_VEG_LAYER_MAPPING_DESIGN.md`](../02_present_state/oracles/SHORT_VEG_LAYER_MAPPING_DESIGN.md)):**
  - `VLists.USysAllSpecs.Lifeform` is `INT32` (`LONG`) while `VUser.USysUserSpp.LifeForm` is `INT16` (`INTEGER`); preserve explicit projection rules and `NotInList` synonym (`OldCode -> Code`) vs. personal species (`VUser.USysUserSpp`) decisions. Join short-vegetation report keys on `LayerCode.Layer1234567` (never padded `LayerCode.LayerCode`).
- **`LMH25 (2023)` Soil Horizon Ordering & Depth Sign:**
  - Upland `L/F/H` humus horizons measure upward from `0 cm` (`UpperDepth > LowerDepth`, ordered `UpperDepth DESC`); wetland `Of/Om/Oh` and mineral `A/B/C/R/W` horizons measure downward (`UpperDepth < LowerDepth`, ordered `UpperDepth ASC`).
- **545 MB `BECMaster` Quarantine & Out-of-Process R Sidecar (`app/internal/rsidecar`):**
  - Streaming Access import (`VP05`–`VP08`) quarantines orphan child rows (`Env -> Veg` dropped FK in `BECMaster_fixing.accdb`) with full receipt reporting before enabling `PRAGMA foreign_keys = ON`.
  - `internal/rsidecar` invokes `Rscript --vanilla` with quoted arguments and Windows 8.3 short-path normalization (`shortpath_windows.go`), never opens read-only climate/clustering queries in `rw` mode, and checks `isTRUE(insp$compatible)` from `vpro::vpro_project_inspect()`.

---

## 5. Frontend Svelte 5, Wails IPC, Native COM & Excelize Guards

1. **Svelte 5 Proxy Detachment:**
   - Detach Svelte 5 deep-reactive proxies with `$state.snapshot(...)` (or store immutable DTOs in `$state.raw`) before passing values to Wails v3 bindings or `structuredClone`.
2. **Draft Barriers & Cryptographic Close Handshake (`CloseService`):**
   - Draft validation errors must survive tab remounts and block Save, Lock, context-switch, and window-close (`CloseService` cryptographic 128-bit nonce handshake `"vpro:close-request"` $\rightarrow$ `ConfirmClose(nonce)` / `CancelClose(nonce)`). Wait for explicit `CancelClose` acknowledgement in lifecycle tests before mutating barriers.
3. **Excelize & YAML v3 Invariants:**
   - Use `strings.EqualFold` (matching `excelize/v2`) when checking worksheet name collisions, and validate case-folded joined grouping keys *before* threshold filtering in reports.
   - With `gopkg.in/yaml.v3`, keep `type configValues = map[string]any` as a type alias (`=`) so nested map type assertions stay `map[string]any`.
4. **Generation-Fenced Async Client Validation & Yielding:**
   - After awaited client-side result validation, recheck the request generation before assigning UI state. Large XML validation must yield to the event loop so Cancel/remount/close guards can run; test a held validation yield in actual Wails, release it after remount, and prove the old result cannot populate the new panel.
5. **Wire-Faithful Shared Fixtures & Production Binding Checks:**
   - Frontend mocks must match the production wire contract, not merely their own validator. Share a strict-Go round-trip fixture (`app/frontend/tests/fixtures/`) for boundaries such as metadata columns (`declaredType`, not `type`). Because `go test` resolves test-only package helpers, also compile production builds and inspect `wails3 generate bindings -ts -i` warnings.
6. **Chunked UTF-8 Wails Request Reassembly:**
   - Large Wails IPC requests transmit as UTF-8 byte chunks; a native fetch guard that inspects only string bodies can miss a successful Save. Reassemble chunks by their upload ID and hold the final actual response. If capture was missed, inspect owned physical history/data first and **never replay a completed mutation**.
7. **Windows Native COM File Dialogs (`go-ole` `IFileDialog` / `IShellItem`):**
   - Native COM wrappers must keep `HWND`/Go state outside native COM interface memory and pass the COM interface receiver plus every syscall argument — a compiling public binding can still crash in Release builds (as `go-common-file-dialog v1.2.0` did).
   - Interpret `HRESULT` as signed 32-bit (`int32`), classify normal user Cancel strictly from `Show`'s `ERROR_CANCELLED`, and remember that `IUnknown.Release` returns a reference count (`uint32`), **not** an `HRESULT`.
   - Balance successful STA initialization (`CoInitializeEx` / `CoUninitialize`) *after* releasing all COM interface and `CoTaskMemFree` path resources; fake-dialog unit tests do not replace actual owned native Cancel and literal-selection acceptance tests.

---

## 6. PostgreSQL `BECMaster` Cloud Sync Rules (`app/internal/cloudsync`)

- **Layer-2 Isolation & 12-Service Preservation:**
  - `app/internal/cloudsync` (`pgx/v5` + `pgxpool` + `pgx.CopyFrom` + `pgx.Batch`) is a pure Layer-2 package with zero sibling Layer-2 imports, surfaced via 19 RPC methods on `ContextService` (`app/domainservices_context.go`) and `CloudSyncWorkbench.svelte` (5th tab of `ProjectAdminWorkbench.svelte`), preserving the strict 12-service Wails registration ceiling and `sqlutil.DecodeStrictJSON` wire validation.
- **3 Isolated PostgreSQL Schemas (`schema.go`):**
  1. `becmaster` — `env` (`112` cols + PostGIS `geom`), `admin` (`20` cols), `veg`/`humus`/`mineral`/`other` with monotonic `child_identity` + watermark, `metadata` (`75` cols), SHA-256 hash-chained `audit` (`prev_hash` $\rightarrow$ `entry_hash`) + `merge_ledger`, `snapshots`, and `download_log`.
  2. `staging` — `submissions` enforced by PostgreSQL Row-Level Security (RLS) + `BEFORE INSERT` role/compliance trigger + submission-keyed `VP08` staging tables.
  3. `standards` — `library_releases` + versioned 2026 `BCPlantTaxonomy v19` (`USysAllSpecs`) & `BECdb v13` catalogues.
- **Security, Compliance Gate & `SERIALIZABLE` Custodian 3-Way Merge:**
  - Resolve connection configs offline-first (`becmaster.env` / `VPRO_PG_*` / `BECMASTER_*` env vars), strictly redact passwords/DSNs across all logs, errors, and frontend DTOs, and require TLS (`sslmode=require` / `verify-full`) for non-loopback hosts.
  - Enforce local `RunComplianceValidation` + `UserSpeciesManifest` packaging prior to every `staging.submissions` upload (`contributor.go`).
  - Standards publish/pull (`< 3 s`) performs an atomic local `VLists.db` swap after SHA-256 verification; baseline seeding (`seed.go`) streams all `71,567` `BECMaster` plots (`1.65M` veg, `597K` audit) via `pgx.CopyFrom` without OOM; regional subset checkouts write canonical WAL `VP08` `.db` files and append `becmaster.download_log` entries.
  - Custodian 3-way merge (`custodian_merge.go`, `< 300 ms`) executes `pgx.Batch`-pipelined mutations inside a `SERIALIZABLE` PostgreSQL transaction with monotonic `child_identity` allocation and tamper-evident SHA-256 hash-chained `becmaster.audit` + `becmaster.merge_ledger` provenance, remaining 100% interoperable with `r/R/cloud_*.R`.

---

## 7. Toolchain, Build Tiers & Validation Reference

### Prerequisites
- **Node `22.12+` & npm** on `PATH`.
- **Go `1.27+` (`CGO_ENABLED=1`)** plus `~/go/bin` (`wails3` `v3.1.0`, `task`, `nfpm`) and `~/.local/bin` (`pmtiles`, `tippecanoe`).
- **CGO Compilers & WebView Dev Libraries:** Linux `gcc` + GTK4 & WebKitGTK 6.0 dev packages (GTK3 & WebKitGTK 4.1 for legacy `gtk3` build tag); Windows `x86_64-w64-mingw32-gcc` / LLVM-MinGW + `makensis`.
- **Optional Sidecar Runtime:** `Rscript` (`R >= 4.4.0` with `vpro` and `climr`), `quarto`, and `gh` CLI.

### Canonical Commands (Run from Monorepo Root or `app/`)
```bash
# Regenerate Wails TypeScript bindings (MUST include -ts -i so nullable arrays emit interfaces, not classes)
(cd app && wails3 generate bindings -ts -i)

# Frontend unit tests (single-pass runner), svelte-check & Vite production bundle
(cd app/frontend && npm test && npm run check && npm run build)

# Backend Go test suite (canonical SQLite-only desktop profile)
(cd app && go test -tags sqliteonly ./...)

# Native desktop packaging (supports VERSION=2.1.0-alpha.1 / BUILD_MODE=dev|alpha|release)
(cd app && wails3 task linux:build EXTRA_TAGS=sqliteonly)
(cd app && wails3 task windows:build:sqliteonly)

# Root single-source F1 help bundle, BC Gov release portal & packaging unit tests
python3 -m unittest discover -s scripts/tests -p 'test_*.py'
node scripts/build-docs-src.mjs && node site/build.mjs && node --test scripts/tests/downloadPortal.test.cjs
```

- **CGO Rebuild Note (`app/internal/accessreader`):** After editing C headers or C sources included by an amalgamating CGO file, pass **`-a`** (`(cd app && go test -a -tags sqliteonly ./internal/accessreader/...)`), because `-count=1` alone can reuse cached C object files. For full-repo `-race` runs on Windows, pass `-timeout 45m` (or `-timeout 150m` across all packages).
- **Parallel Multi-Agent Worktree Rule:** Give each mutating parallel subagent an isolated worktree (`/home/bruno/Work/vpro.worktrees/waveN-<track>`) with strictly disjoint file ownership, especially around generated `app/frontend/bindings/` and shared root documentation/scripts.
