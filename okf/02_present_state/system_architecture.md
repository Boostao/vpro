# Present State System Architecture (`Boostao/vpro`: `app/`, `vpro-web` & `r/`)

> **Navigation:** [Master Index](../00_index.md) | **Present State:** [Domain Model](./domain_model.md) · [Core Workflows](./core_workflows.md) · `System Architecture` · [Capability Matrix](./capability_matrix.md) · [Data Dictionary](./data_dictionary.md) · [Oracles](./oracles/DIAGNOSTIC_CLASSIFICATION.md) | **Playbooks:** [Desktop Engineering](../05_engineering_and_agents/desktop_app_engineering.md) · [R SDK Engineering](../05_engineering_and_agents/r_sdk_engineering.md) · [Web Read-Only Deployment](../05_engineering_and_agents/web_readonly_deployment.md)

---

## 1. Unified Monorepo Multi-Surface Topology (`Boostao/vpro`)

Following the October–November 2026 architectural qualification and November 2026 monorepo unification (`VproMailExchange` `0017`, `2026-10-02`; `archive/oct2026-parity-ledgers/CLIENT_SCOPE.md`; `98e214df`), VPro's production codebase lives in the unified **`Boostao/vpro`** monorepo as **three complementary, schema-compatible delivery surfaces** sharing an identical 7-database SQLite (`VP08`) family, `config.yml`, and PostgreSQL `BECMaster` contract:

1. **Primary Interactive Desktop Track — `app/` (`github.com/boostao/vpro/app`, `v2.0.0`):** Cross-platform desktop workstation built on **Go `1.27.0`**, **Wails v3 (`v3.1.0`)**, **Svelte 5 (`^5.57.3`, Runes mode)**, **MapLibre GL JS (`^6.18.0`) + `deck.gl` (`^9.4.1`) / `luma.gl` WebGPU + `pmtiles` (`^4.5.0`)**, **Tailwind CSS v4 (`^4.3.5`)**, **CGO SQLite (`github.com/mattn/go-sqlite3` `v1.14.53`, `WAL` mode)**, **`pgx/v5` (`v5.13.0`)** (`app/internal/cloudsync`), and an embedded C amalgamation of **`mdbtools` `1.0.1` (`libmdb`)** compiled across `windows`, `linux`, and `darwin` (`app/go.mod`, `app/frontend/package.json`, `app/internal/accessreader/reader.go`).
2. **Headless R Statistical & Companion SDK Track — `r/` (`vpro` `v2.0.0` + Wave 6 Cloud `BECMaster`):** Clean-slate companion R package (`43` `r/R/*.R` files, `R >= 4.4.0`, zero Shiny/widgets, zero-note `R CMD check`, qualified on 71,567-plot `BECMaster`) executing concurrent read-only SQLite WAL queries alongside `app/` via `RSQLite`/`data.table`/optional `duckdb`, providing community matrices, multivariate BEC clustering, `sf` GeoPackage export, `LMH25 (2023)` pedon validation, `climr` normals & Ministry `aSMR` modelling, dual edatopic grids, BEC diagnostics, guarded candidate `*_SU` write-back, PostgreSQL `BECMaster` cloud sync/staging/snapshots (`r/R/cloud_*.R`), and Quarto BEC ecosystem guides (`r/DESCRIPTION`).
3. **Pure-HTTP Read-Only Web Server — `app/cmd/vpro-web` & `app/cmd/vpro-snapshot` (`deploy/vpro-web/`):** Stateless, hardened read-only web viewer and analytical service compiled with `-tags vpro_headless` (zero Wails v3, GTK/WebKit, or `accessreader` dependencies), serving immutable `BECMaster` / `VP08` SQLite snapshots (`mode=ro&immutable=1`, `journal_mode=DELETE`, `0`-row `<Project>_Audit`, fail-closed `RedBlueList` coordinate redaction) through a concurrent **`ReadOnlyContextPool`**, a strict **290-method read-only RPC allowlist** (`12` services), the embedded Svelte 5 web SPA (`vite.web.config.ts`), and an optional semaphore-bounded read-only R/Quarto sidecar (`climr`/`vegclust`/Quarto) behind Caddy on DigitalOcean ([Section 5](#5-pure-http-read-only-web-server-appcmdvpro-web--appcmdvpro-snapshot), [Web Read-Only Deployment Runbook](../05_engineering_and_agents/web_readonly_deployment.md)).

```mermaid
flowchart TB
    subgraph Shared["Shared Local Persistence Contract"]
        CFG["config.yml (release_channel: stable | experimental)<br/>(Replaces HKCU\...\VPro64 Registry & Legacy JSON)"]
        FAM["7-DB Canonical SQLite Family<br/>VPro64.db, VLists.db (2026), VUser.db,<br/>VMetaData.db, VMessageBoard.db, VPics.db"]
        PROJ["User Project SQLite Files (<Project>.db, WAL Mode)<br/>8 VP08 Core Tables + *_SU / *_Hierarchy / *_Lump / *_Profile"]
        MDB["Legacy MS Access (.mdb / .accdb) & VENUS 5.0<br/>VP05, VP06, VP07, VP08 + 545 MB BECMaster"]
    end

    subgraph Desktop["Primary Desktop App: app/ (github.com/boostao/vpro/app · 4-Layer Go DAG + Wails v3)"]
        UI["Svelte 5 Runes Frontend (app/frontend · Vite 8 + Tailwind v4)<br/>24 Views · 267 Components · MapLibre v6 + WebGPU · F1 Help"]
        IPC["Wails v3 Typed IPC Bridge (-ts -i)<br/>Strictly 12 Domain Services + Close Nonce Handshake"]
        CTX["Dual-Connection SqliteContext (app/internal/vprocore)<br/>1) Pinned :memory: RO Coordinator + ProjectReadDB (4 conns, cached caps)<br/>2) Lazy rw+WAL ProjectDB Writer (FK=ON, busy_timeout=5000)"]
        CAT["2026 Embedded SHA-256 Read-Model Catalogues<br/>BECdb v13, BCPlantTaxonomy v19, LMH25 (2023), bc-overview.pmtiles"]
        CGO["app/internal/accessreader + accessimport (Win/Linux/macOS)<br/>Vendored libmdb 1.0.1 + Orphan Quarantine"]
        EXP["Interchange & Cloud Sync (app/internal/interchange + cloudsync)<br/>TurboVeg 3 SQLite+XML, .gpkg, .rds, .xlsx, .pdf, .kml, PG BECMaster"]
    end

    subgraph HeadlessR["Headless R Companion SDK & Sidecar: r/ (vpro v2.0.0)"]
        RSIDE["app/internal/rsidecar Out-of-Process Rscript Bridge"]
        RAPI["r/ — vpro R SDK (R >= 4.4 + RSQLite WAL / DuckDB / RPostgres)<br/>climr -> aSMR, vegclust, Dual Edatopic Grids, Cloud Sync & Quarto"]
    end

    subgraph WebServer["Read-Only Web Server: app/cmd/vpro-web & vpro-snapshot (-tags vpro_headless)"]
        SNAPCLI["cmd/vpro-snapshot (build & verify)<br/>Fail-Closed RedBlueList Redaction · 0-Row Audit · DELETE/VACUUM"]
        WHTTP["cmd/vpro-web (:8080 Public + 127.0.0.1:9090 Reload/Stats)<br/>Embedded Svelte 5 SPA · 290-Method RO Allowlist · Semaphores"]
        WPOOL["ReadOnlyContextPool (mode=ro&immutable=1)<br/>Keyed by (Dataset, SU, Hierarchy) · In-Memory Session Prefs"]
    end

    UI <-->|"JSON IPC ($state.snapshot)"| IPC
    IPC --> CTX
    IPC --> CAT
    IPC --> CGO
    IPC --> EXP
    IPC <-->|"Quoted Rscript CLI"| RSIDE
    RSIDE --> RAPI
    CTX <--> CFG
    CTX -->|"mode=ro (net/url escaped)"| FAM
    CTX <-->|"RO Snapshots + RW WAL Tx"| PROJ
    CGO -->|"Streaming Read + Orphan Quarantine"| MDB
    CGO -->|"Atomic os.Link VP08 .db"| PROJ
    RAPI <-->|"Concurrent WAL RO + Guarded *_SU"| PROJ
    RAPI --> FAM
    PROJ -->|"Offline Snapshot Build"| SNAPCLI
    SNAPCLI -->|"Immutable Bundle + manifest.json"| WPOOL
    WHTTP --> WPOOL
    WHTTP -->|"Bounded Semaphore (RO Guard)"| RSIDE
```

---

## 2. Verified Technology Stack (`Boostao/vpro` — `app/` `v2.0.0`)

| Architectural Layer | Component / Module | Exact Version | Source Evidence |
|---|---|---|---|
| **Backend Language** | Go (`github.com/boostao/vpro/app`, `CGO_ENABLED=1`, `toolchain go1.27.4`) | `go 1.27.0` (`toolchain go1.27.4`) | `app/go.mod`, `.github/workflows/release.yml` |
| **Desktop Shell & IPC** | Wails v3 (`github.com/wailsapp/wails/v3` + `@wailsio/runtime`, `wails3 generate bindings -ts -i`) | `v3.1.0` | `app/go.mod`, `app/frontend/package.json` |
| **Primary SQL Engine** | CGO SQLite3 (`github.com/mattn/go-sqlite3`, `PRAGMA journal_mode = WAL`) | `v1.14.53` | `app/go.mod`, `app/internal/vprocore/sqlitecontext.go` |
| **Cloud `BECMaster` Driver** | Pure-Go PostgreSQL (`github.com/jackc/pgx/v5`, `pgxpool`, `CopyFrom`, `Batch`) | `v5.13.0` | `app/go.mod`, `app/internal/cloudsync/` |
| **Access Binary Reader** | Internal CGO `accessreader` wrapping vendored `mdbtools` (`libmdb`) on `linux \|\| windows \|\| darwin` | `1.0.1` (`-fvisibility=hidden`, Win `-static`) | `internal/accessreader/reader.go:1-16` |
| **Windows Native Shell/COM** | `github.com/go-ole/go-ole` (`IFileDialog` / `IShellItem` COM syscalls, balanced STA) | `v1.3.0` | `app/go.mod`, `app/internal/pictures/` |
| **Document & Interchange** | `excelize/v2` (`.xlsx`), `go-pdf/fpdf` + `LiberationSans` (`.pdf`), `golang.org/x/text`, `go.yaml.in/yaml/v3` | `v2.11.1`, `v0.12.0`, `v0.44.0`, `v3.0.6` | `app/go.mod`, `app/resources/fonts/` |
| **Frontend & 3D GIS** | Svelte 5 (`^5.57.3`), `maplibre-gl` (`^6.18.0`), `@deck.gl/*` (`^9.4.1`), `@luma.gl/webgpu` (`^9.4.2`), `pmtiles` (`^4.5.0`) | Svelte 5 + MapLibre 6.18 | `app/frontend/package.json` |
| **CSS, Fonts & Icons** | Tailwind CSS v4 (`@tailwindcss/vite`), `@lucide/svelte`, BC Sans WOFF2 (`site/`, `app/frontend/src/`) | `^4.3.5`, `^1.73.0` | `app/frontend/package.json`, `site/fonts/` |
| **Bundler & Test Suites** | Vite 8 (`^8.3.8`), `svelte-check`, Node `24+` single-pass `app/frontend/scripts/run-tests.mjs` (`.test.cjs` suites in `app/frontend/tests/`), Go test (`*_test.go`) | `^8.3.8` / Node `24+` | `app/frontend/package.json`, `.github/workflows/ci.yml` |

---

## 3. Backend Go 4-Layer Acyclic Architecture (`487` Production `.go` Files)

### 3.1 Startup Lifecycle, Non-Destructive Recovery & Guarded Window Close
Unlike legacy `VPro64.accdb`—which silently resets or crashes when linked `.accdb` paths move (`VPro64_forAI/Modules/V7mdlSplash.txt:70-137`)—`app/main.go` enforces deterministic startup, build-tier (`dev` | `alpha` | `release`), and shutdown contracts:

1. **Startup & Recovery Mode (`app/main.go`, `app/internal/lifecycle/startupservice.go`, `app/internal/lifecycle/buildinfo.go`):** Resolves `%APPDATA%\vpro\config.yml` and `%LOCALAPPDATA%\vpro\`, verifies SHA-256 hashes of all 6 support databases (`VPro64.db`, `VLists.db`, `VUser.db`, `VMetaData.db`, `VMessageBoard.db`, `VPics.db` in `databasefamily.go`), provisions `<dataDir>/readmodels/vlists-lookup.db` alongside the embedded reference `.db` read-models, and opens `SQLiteProjectService`. If `config.yml`, a support database (e.g., `VUser.db`), or a configured external `.db` fails validation, `StartupService` enters non-destructive recovery mode (backing up corrupt `.db` files byte-for-byte before restoring clean seeds) so the user can relocate `.db` paths or materialize `Sample.db` **without overwriting `config.yml` without backup**.
2. **Cryptographic Nonce Window-Close Handshake (`app/internal/lifecycle/closeservice.go`, `app/main.go`):** Prevents data loss from dirty forms or in-flight workbook publications when the OS window close button is clicked:

```mermaid
sequenceDiagram
    actor User
    participant OS as Native Window (Wails v3)
    participant CS as Go CloseService
    participant App as Svelte 5 App.svelte / CloseConfirm

    User->>OS: Click Window [X] or Quit
    OS->>CS: WindowClosing / ShouldQuit event
    CS->>OS: event.Cancel() (block immediate exit)
    CS->>CS: Mint 128-bit random prefix + monotonic nonce
    CS-->>App: Emit "vpro:close-request" (nonce)
    alt Clean state (no dirty editors or active publications)
        App->>CS: ConfirmClose(nonce)
        CS->>OS: Application.Quit()
    else Unsaved drafts or in-flight export
        App->>User: Render CloseConfirm.svelte modal
        alt User chooses "Discard & Close"
            User->>App: Confirm discard
            App->>CS: ConfirmClose(nonce)
            CS->>OS: Application.Quit()
        else User chooses "Stay & Save"
            User->>App: Cancel close
            App->>CS: CancelClose(nonce)
        end
    end
```

### 3.2 Dual-Connection `SqliteContext`, Batched `GetPlotBundle` & Stale-Tab Isolation (`app/internal/vprocore/sqlitecontext.go`)
Legacy Access rewrote shared `QueryDefs` on disk (`SetCurrentProject`), making multi-window/multi-user operation unsafe. `app/` replaces this with an isolated connection and caching design (`app/internal/vprocore/sqlitecontext.go`, `plotbundle.go`, `sqliteprojectservice.go`):

* **Connection 1 — Pinned `:memory:` Read Coordinator (`MaxOpenConns(1)`):**
  * Attaches `VPro64.db`, `VLists.db`, `VUser.db`, `VMetaData.db`, `VMessageBoard.db`, active `<Project>.db`, and optional `<SU>.db`, `<Hierarchy>.db`, `<Profile>.db` using SQLite URI **`mode=ro`**, verifying `os.SameFile` before and after `ATTACH DATABASE` to prevent TOCTOU path swapping (`sqlitecontext.go`).
  * Validates exact column counts, indexes, and `_table_metadata` (`'VP08'`) across all 8 project tables, synthesizes temporary `:memory:` SQL views (`Filtered_Env`, `USysEnv`, `USysVeg`, `USysVegA..D`, `USysHumus`, `USysMineral`, `USysOther`, `USysAuditTrail`, `USysMetadata`, `MasterSiteUnitList`, `USysSU`, `USysHierarchy`), and serializes `VLists`/`VUser` species reference reads (`vegetationspeciesreference.go`) via `WithCoordinatorConn` (matching `soilchildreference.go`).
* **Connection 2 — Pooled Read-Only Project Handle (`ProjectReadDB`) & Lazy Writer (`ProjectDB`):**
  * `ProjectReadDB` (`ProjectReadDatabase(ctx)`, `SetMaxOpenConns(4)` / `SetMaxIdleConns(4)`) serves concurrent WAL read snapshots—including `ContextService.GetPlotBundle` and `WorkingUnitService.GetWorkingUnitChoices("env")` (eliminating per-switch disk opens while preserving `sqlutil.OpenReadOnly` for separate-file `"su"` mode).
  * `ProjectDB` opens lazily with `mode=rw&_foreign_keys=on&_busy_timeout=5000` (`MaxOpenConns(2)`) solely for atomic `BEGIN IMMEDIATE ... COMMIT` transactions writing `<Project>_Env`, `<Project>_Admin`, child tables, `<Project>_Audit`, and `__VPRO_*` receipt tables.
* **Schema Capability Cache, Batched `GetPlotBundle` & Two-Page Static Reference Cache:**
  * `SqliteContext` caches `headerCaps` and `childCaps` behind a leaf `capsMu sync.RWMutex` (`CachedHeaderCapabilities` / `CachedChildCapabilities` returning defensive map clones), exposes `InvalidateSchemaCache()` for DDL/migration paths, and invokes `OnClose(fn func())` teardown hooks on context close.
  * `ContextService.GetPlotBundle(ctx, contextID, plot, includeCapabilities)` (`app/internal/vprocore/plotbundle.go`, `app/domainservices_context.go`) reads `Header`, `Veg`, `Humus`, `Mineral`, and `Other` in a single `ReadOnly: true` SQLite WAL snapshot transaction using cached capabilities—preserving exact historical NULL-ID / duplicate / unsafe-int64 isolation (`Vegetation.Reason`, `HumusError`, `MineralError`) while omitting `Audit` (lazy-loaded when the Audit Trail tab opens).
  * Two-Page static ComboBox reference fields (`app/internal/twopage/twopageparententryreferencecomposition.go`, excluding plot-filtered `SubZone`/`SiteSeries` and dynamic `project`/`working-unit`/`bec-series` readers) are cached per `(owner, contextID, form, listsAlias, readers)` with `ProfileOwnedFiles`, `PRAGMA <alias>.data_version`, and file-stat validation, evicted via `owner.OnClose`, and defensively cloned to preserve exact `TwoPageEntryReferenceSnapshot` wire parity.
* **128-Bit `contextID` Epoch Fencing (`contextservice.go`):** Every project/SU/hierarchy switch mints a new 128-bit hex `contextID`. Every mutation and scoped query checks the caller's `contextID`, deterministically rejecting late IPC calls from stale UI views.

### 3.3 4-Layer Acyclic Package Decomposition & 12 Registered Wails Services
Wave 1C–1D consolidated the earlier 86 flat root Wails services into a strict **4-layer acyclic `app/internal/*` DAG** enforced by automated architectural tests (`app/internal/integration/architecture_dag_test.go`), registering **strictly 12 cohesive domain services** in `app/main.go` (`app/domainservices_*.go`):

* **Layer 0 — Embedded Assets & Foundations:** `app/resources` (`resources/embed.go` exporting embedded `embed.FS` / `[]byte` assets + `RepoRoot()`), `internal/sqlutil`, `internal/accessreader` (`linux || windows || darwin`), `internal/accessimport`, `internal/accessinventory`, `internal/accesslayout`, `internal/accesscompare`, `internal/fs882layout`, `internal/listcatalog`, `internal/reports/subzonematrix`.
* **Layer 1 — Core Context, Reference Catalogues & Shared Engines:** `internal/references` (`BECService`, `ReferenceService`, `Site/Soil/Parent/Geology/Region/Quality` code services), `internal/vprocore` (`SQLiteContext` with `beginReadSnapshot`, `DesktopConfig`, `report_preferences_handler.go`, 7-DB `DatabaseFamily` seeding `VPics.db` on cold boot, `ProjectService`, `ContextService`, `PlotService`), `internal/sourceform`, `internal/reports/reportcore`.
* **Layer 2 — Independent Domain Packages (zero sibling imports):** `internal/lifecycle`, `internal/plotentry`, `internal/sivi`, `internal/twopage`, `internal/datasheet`, `internal/classification`, `internal/lumping`, `internal/diagnostics`, `internal/lmh25rules`, `internal/projectops`, `internal/rsidecar`, `internal/validation`, `internal/vegreport`, `internal/envreport`, `internal/spatial`, `internal/pictures`, `internal/interchange`, `internal/cloudsync` (plus cross-domain `internal/integration`).
* **Layer 3 — Thin Wails Host (`package main` in `app/` — 12 Bound Services):**

| # | Registered Wails Service (`app/main.go`) | Backing Domain Package(s) & Core Responsibilities |
|---:|---|---|
| `1` | **`LifecycleService`** | Startup activation/recovery hints, cryptographic close nonce (`CloseService`), `USysUserLog` review |
| `2` | **`ContextService`** | Active `Project`/`SU`/`Hierarchy` switching, 128-bit `contextID` fencing, `New/SaveAs/Splinter/Compare/Merge` (`internal/projectops`), scoped plot lookup & single-snapshot `GetPlotBundle`, 19 `cloudsync` RPCs |
| `3` | **`PlotEntryService`** | 6-tab FS882, Two-Page (`internal/twopage`), FS1333 SIVI (`internal/sivi`), inline CHARS toggle, `LMH25` live pedon/edatopic diagnostics (`internal/lmh25rules`), `ProjectMetadata` presets & auto-derivation |
| `4` | **`DatasheetService`** | Universal editable spreadsheet grid (`_Env`, `_Admin`, `_Veg`, `_Humus`, `_Mineral`, `_Other`, `_SU`), global search, TSV paste (`internal/datasheet`) |
| `5` | **`ClassificationService`** | Dual-pane `SU`/`Hierarchy` tree explorer, `Env <-> SU` sync, Plot Profiling, `Combine Species` (`*_Lump` + `LumpSpec`), reactive BEC Diagnostics (`internal/diagnostics`), R Sidecar (`internal/rsidecar`) |
| `6` | **`ValidationService`** | Batch `USysTableOfLists` picklist & numeric bounds compliance gate, 1:N FK integrity, `SpeciesCodeCheck`, transactional `OptimizeVeg` |
| `7` | **`ImportExportService`** | Access `VP05`–`VP08` (`545 MB` `BECMaster` streaming + orphan quarantine), `VENUS 5.0`, **official `TurboVeg 3` 31-table SQLite & `Plot_package` XML**, `.gpkg`, `.rds`, Long/Wide CSV & `.zip`, `User Species`, Label PDF |
| `8` | **`VegetationReportService`** | Summary & Long Vegetation previews and `.xlsx` workbooks, SiteUnit suffix exclusions, Lifeform & Species Attributes summaries |
| `9` | **`EnvironmentReportService`** | Long Environment, Site Unit Summary (mean/quartiles + qualitative), and Subzone Matrix previews & `.xlsx` workbooks |
| `10` | **`SpatialService`** | MapLibre v6 + `PMTiles` byte-range streaming, NAD83 `UTM <-> DD` geodetic QA, FlatGeobuf BGC/Ecosection/District auto-stamp, AOI $\rightarrow$ `*_SU`, KML 2.1 |
| `11` | **`PictureService`** | Cold-boot `VPics.db` seeding, plot photo browser, metadata editing, native OS file selection, creation/deletion/restoration |
| `12` | **`HelpService`** | Offline `F1` `LMH25 (2023)` contextual help (`resources/help_bundle.json`), 4 guided tours, shortcuts, `What's New`, safe `Reset Workspace to Sample`, `About & Standards Stamps` |

### 3.4 Native Access `.mdb`/`.accdb` CGO Ingestion Pipeline (`accessreader` & `accessimport`)
`app/` eliminates runtime dependence on Microsoft Access, Windows ACE/Jet ODBC drivers, or PowerShell COM by embedding a cross-platform fork of **MDB Tools `1.0.1` (`libmdb`)** compiled directly via CGO (`app/internal/accessreader/reader.go:1-40`):

```mermaid
flowchart LR
    File[".mdb / .accdb File<br/>(VP05..VP08 + 545 MB BECMaster)"] -->|"Read-Only Stream<br/>(Win/Linux/macOS)"| LibMDB["CGO internal/accessreader<br/>Vendored libmdb 1.0.1 C<br/>(-fvisibility=hidden, Win -static)"]
    LibMDB -->|"Sticky C Error Guards<br/>Nanosecond DATETIME"| Inspect["InspectAccessDatabase()<br/>Detect *_Env + Version Tag<br/>Count Rows & Check Eligibility"]
    Inspect --> Stage["internal/accessimport<br/>Streaming SQLite Staging<br/>VP05/06/07 -> VP08 + Orphan Quarantine"]
    Stage -->|"SHA-256 Source Check<br/>+ Companion Tables"| Validate["inspectFileContext()<br/>Verify 8 VP08 Tables,<br/>Indexes & Foreign Keys"]
    Validate -->|"Atomic Publish"| Dest["Canonical <Target>.db (WAL)<br/>+ Optional Context Switch"]
```

* **Key Hardening Guarantees (`internal/interchange/accessprojectimport.go`):**
  * Rejects embedded `U+0000` NUL truncation, corrupt Jet3/Jet4 memo/OLE page chains, and lossy character conversions via sticky C error codes (`GO_MDB_ERROR_*`).
  * Compiles cleanly across **Windows (`amd64`/`arm64`, `-static` MinGW linking with zero non-inbox PE DLLs), Linux (`-fvisibility=hidden` isolating vendored `fakeglib` from GTK4), and macOS Universal (`darwin`)**.
  * Upgrades **`VP05`**, **`VP06`**, and **`VP07`** to canonical `VP08`, streams **`545 MB` `BECMaster_fixing.accdb` (`71,567` plots, `1.65M` veg rows)** with automatic orphan-row quarantine so `PRAGMA foreign_keys = ON` succeeds cleanly, and imports companion `*_SU`, `*_Hierarchy`, `*_Lump`, and `*_Profile` tables.

---

## 4. Frontend Svelte 5 Architecture (267 focused `.svelte` components, `24` Views)

### 4.1 Reactive State, Session Machines, Reference Caching & In-Place Plot Switching
* **Svelte 5 Runes + Class Session Machines:** Uses Svelte 5 Runes (`$state`, `$state.raw`, `$derived`, `$effect`, `$props`) paired with stateful TypeScript session classes cached across view switches so unsaved drafts and preview snapshots survive tab navigation and block context-switch/close barriers (`41a09f8`, `d630301`).
* **Multi-Tier Reference & Prefetch Cache (`app/frontend/src/entry/entryReferenceCache.ts`):** Registered with `registerContextDisposer` (`contextSessionRegistry.ts`) for automatic context-switch eviction and strict non-caching of rejected promises. Caches frozen global static catalogues, a 64-entry BEC `(zone, subZone)` LRU, coordinate/working-unit preferences, per-context capabilities and dynamic lookups, 3-canonical-group $\rightarrow$ 6-form deduplicated species lists (`SubVegAXL_BC`/`SubVegAXL`/`SubVegAhtXL`, `SubVegCXL`/`SubVegChtXL`, `SubVegDXL`) stored in `$state.raw`, and a 6-plot per-context `GetPlotBundle` prefetch LRU with in-flight promise deduplication and explicit mutation invalidation.
* **In-Place Plot Switching Across FS882, FS882 (2-Page) & SIVI:** `ShellEntryHost.svelte` keeps `{#key $projectState?.contextId}` and `{#key editorEntryForm}` while replacing `{#key editorPlotNumber}` with an audited in-place `resetForPlot()` boundary inside `FS882Form` (keying only `<TwoPageEntryEditor>` in `FS882Modals.svelte` so `twoPageEntrySessions` survives plot steps). Switching plots preserves `activeTab`, restricts `{#key headerRevision}` to leaf input grids (incremented only on Undo, diagnostic mutations, or restore), lazy-loads Audit Trail on tab entry, and gates `LMH25DiagnosticsBar` (`waitForDraft`) to a single debounced evaluation per plot switch.
* **Proxy Detachment & Generation-Fenced Async Reads:** Before calling Wails v3 bindings, Svelte 5 deep proxies are stripped with `$state.snapshot(...)`, while `ReadRequests` (`readRequests.ts`) and post-await generation checks prevent stale async results from populating remounted views.
* **Vendor & Sub-Editor Code Splitting (`e9fdb9d`):** Report workbenches, FS882 sub-editors, and MapLibre/WebGPU vendor chunks are lazy-loaded via dynamic `import(...)` with Vite worker asset bundling (`16960a8`).

### 4.2 UI Component & View Hierarchy (`24` Active Views)

```mermaid
flowchart TD
    App["App.svelte (Root Shell & 24-View Router)"]
    Nav["Navigation.svelte (Home · Plots · 3D Map · Forms · Reports · Interchange · Help)"]
    Side["Left Sidebar (#project-context)<br/>Project / SU / Hierarchy Selectors · New/Attach .db · Import .mdb/.accdb · Reveal in Explorer"]
    Help["HelpDrawer.svelte (F1 LMH25) + OnboardingTour.svelte + CloseConfirm.svelte"]

    App --> Nav
    App --> Side
    App --> Help

    subgraph Editors["Data Entry, Datasheet & Classification Views"]
        FS882["FS882Form.svelte (6-Tab + SIVI + Inline CHARS Toggle)<br/>Site · Veg · VegOther · Soils · Other · Audit · siviParent"]
        TwoPage["TwoPageEntryEditor.svelte (Full Soil/Veg CRUD & Restore)"]
        Grid["UniversalDatasheetGrid.svelte (_Env/_Admin/_Veg/_Humus/_Mineral/_Other/_SU)"]
        ProjAdm["ProjectAdminWorkbench.svelte (New/SaveAs/Splinter/Compare/3-Way Merge/QA)"]
        ClassEx["ClassificationExplorer.svelte (Dual-Pane SU & Hierarchy Tree) + LumpEditor.svelte"]
    end

    subgraph Synthesis["3D Geospatial, Diagnostics, R Sidecar, Reports & Interchange"]
        Map3D["GeospatialWorkbench.svelte (MapLibre v6 + WebGPU + Offline PMTiles + AOI->SU)"]
        Diag["ClassificationSynthesis.svelte (Live Differential d/dd/cd/c/ic + Outlier Queue)"]
        RSide["RSidecarWorkbench.svelte (climr -> aSMR + Dual Edatopic + vegclust + Quarto)"]
        VegEnv["Long/Summary Veg & Env (.xlsx) · Lifeform · SubzoneMatrix · PlotLabel (.pdf)"]
        Hub["InterchangeHub.svelte (VENUS 5, TurboVeg 3 SQLite+XML, .gpkg, .rds, CSV .zip, KML)"]
    end

    App --> Editors
    App --> Synthesis
```

### 4.3 Graduated Release-Channel Configuration (`config.yml`)
Wave 1A (`c4cbd1a`) graduated all validated desktop workflows to **default-ON** in standard builds, replacing the historical 79 `VITE_*` / 62 `VPRO_*` demo environment flags (`archive/oct2026-parity-ledgers/`) with a clean `release_channel: stable | experimental` setting in `config.yml` and pruning client-retired `CHARS` standalone forms and `PC-ORD Break Report` menus. Offline extraction tools under `app/cmd/` (`cmd/standards2026`, `cmd/accessinventory`, `cmd/fs882layout`, `cmd/*codefixture`) compile 2026 `BECWeb` standards and Access twip geometry into deterministic embedded assets under `app/resources/`.

---

## 5. Pure-HTTP Read-Only Web Server (`app/cmd/vpro-web` & `app/cmd/vpro-snapshot`)

To publish **`BECMaster`** and provincial `VP08` datasets for browser-based exploration, mapping, diagnostics, and read-only R analytics without duplicating backend domain logic, `app/` compiles a third delivery surface from the same 4-layer `app/internal/*` packages:

* **Headless Build Tag Isolation (`-tags vpro_headless`):** Build-tag splits across `internal/vprocore`, `internal/lifecycle`, `internal/pictures`, and `internal/interchange` compile `cmd/vpro-web` and `cmd/vpro-snapshot` with `CGO_ENABLED=1` (`go-sqlite3` only) and **zero** transitive `github.com/wailsapp/wails` or `internal/accessreader` (`libmdb`) imports—mechanically enforced by `TestHeadlessZeroWailsAndAccessReaderDeps` (`app/cmd/vpro-web/deps_headless_test.go`).
* **Concurrent `ReadOnlyContextPool` (`app/internal/vprocore/readonly_pool.go`, `sqlitecontext_readonly.go`, `desktopconfig_memory.go`):** Replaces desktop's single mutable `SqliteContext` with a bounded pool (`VPRO_WEB_POOL_SLOTS=6` slots per `(DatasetID, SU, Hierarchy)` key, `VPRO_WEB_MAX_POOLS=16` keys) opening snapshot SQLite files strictly with `mode=ro&immutable=1`. Each catalog generation issues generation-fenced `vproweb1:` context IDs (`ErrStaleWebContext` on reload), binds per-session preferences strictly in memory (`NewInMemoryDesktopConfig`), and supports atomic zero-downtime `Reload` triggered via loopback `POST /internal/reload`.
* **Strict 290-Method Read-Only RPC Allowlist & Web SPA Transport (`app/resources/web_rpc_allowlist.json`, `app/cmd/vpro-web/rpc_router.go`, `app/frontend/vite.web.config.ts`):**
  * Exposes exactly **290 read-only methods** across all 12 domain services (`220` `rpc`, `20` `download`, `50` `prefs`), verified both at frontend build time (`node scripts/generate-web-rpc-map.mjs --check`) and by a strict startup bijection check in `NewRPCRouter` (every allowlisted method has a handler; no unlisted handler may register).
  * `vite.web.config.ts` swaps `@wailsio/runtime` for the HTTP transport shim (`/api/rpc/<Service>/<Method>`, `/api/downloads/*`, `/api/meta`, `/pmtiles/*`, `/maps/*`), embedding the compiled `dist-web/` SPA into `vpro-web` (`static_embed.go`). Client-supplied filesystem paths are unconditionally ignored and rewritten to server-controlled temp directories under `tmpfs` `/tmp/vpro-exports`.
* **Read-Only R Sidecar (`climr`, `vegclust`, Quarto) with Bounded Semaphores:** `app/cmd/vpro-web/rpc_handlers_envreport.go` routes `DetectRRuntime`, `GetCachedPlotClimate`, `ComputePlotClimateAndDualEdatopic`, `RunMultivariateClustering`, and `RenderQuartoGuide` (returning HTML or HTML+PDF ZIP downloads) through `app/internal/rsidecar` with read-only SQLite write-back guards (`app/internal/rsidecar/readonly_regression_test.go`). Heavy jobs are bounded by `VPRO_WEB_R_CONCURRENCY=2` (`180s` timeout) and `VPRO_WEB_EXPORT_CONCURRENCY=3` (`120s` timeout) semaphores—returning HTTP `503 Service Unavailable` with `Retry-After: 5` when saturated—paired with a bounded in-memory LRU preview cache (`VPRO_WEB_CACHE_MAX_MB=256`).
* **Immutable Snapshot Publisher & Deployment (`app/cmd/vpro-snapshot/`, `deploy/vpro-web/`, `.github/workflows/web-deploy.yml`):** `vpro-snapshot build` / `verify` builds SHA-256-verified immutable `VP08` bundles (5 core support DBs + project/auxiliary DBs in `journal_mode = DELETE`, `VACUUM` + `ANALYZE`, `0`-row `<Project>_Audit`, fail-closed `RedBlueList` coordinate truncation by default, `0644`/`0755` portable bundle permissions). Production and staging run via Docker Compose (`read_only: true`, UID `10001:10001`, `cap_drop: ALL`, Caddy 2 automatic HTTPS + HTTP/3, loopback-only `:9090` control listener, and `sync-snapshot.sh` locking releases to `0444`/`0555` before `vpro-snapshot verify` and atomic symlink reload). See the [Web Read-Only Deployment Runbook](../05_engineering_and_agents/web_readonly_deployment.md) and [`D-14`](../04_evidence_and_sources/decisions_and_gaps.md).
