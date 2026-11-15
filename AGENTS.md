# `Boostao/vpro` — Monorepo Engineering & Multi-Agent Router

Welcome to **`Boostao/vpro`**, the unified repository for **`VPro` 2.0** (*VENUS — Vegetation and Environment NexUS — Professional*), built for the **B.C. Ministry of Forests, Research Branch — Biogeoclimatic Ecosystem Classification (BEC) Program** (Contract `RE26OCF433`).

## 1. Authoritative Routing Map (Read Scoped Contracts Before Editing)

To avoid context bloat while preserving 100% of engineering invariants, instructions are layered by subsystem:

| Scope | Scoped Agent Contract | Deep Engineering Playbook / Specification |
|---|---|---|
| **Monorepo Root (`/*`)** | **`AGENTS.md`** *(this file)* · [`.github/copilot-instructions.md`](./.github/copilot-instructions.md) | [`okf/00_index.md`](./okf/00_index.md) · [`okf/04_evidence_and_sources/decisions_and_gaps.md`](./okf/04_evidence_and_sources/decisions_and_gaps.md) |
| **Desktop Workstation (`app/`)** | **[`app/AGENTS.md`](./app/AGENTS.md)** | **[`okf/05_engineering_and_agents/desktop_app_engineering.md`](./okf/05_engineering_and_agents/desktop_app_engineering.md)** · [`okf/02_present_state/system_architecture.md`](./okf/02_present_state/system_architecture.md) |
| **Headless R SDK (`r/`)** | **[`r/AGENTS.md`](./r/AGENTS.md)** | **[`okf/05_engineering_and_agents/r_sdk_engineering.md`](./okf/05_engineering_and_agents/r_sdk_engineering.md)** · [`okf/03_future_architecture/analytics_and_governance.md`](./okf/03_future_architecture/analytics_and_governance.md) |
| **Empirical Access & BEC Oracles** | [`okf/02_present_state/oracles/`](./okf/02_present_state/oracles/) | 9 disposable-VM DAO & BEC math/validation contracts + [`okf/02_present_state/data_dictionary.md`](./okf/02_present_state/data_dictionary.md) |

---

## 2. Monorepo Directory Layout

- **`app/`** — **VPro 2.0 Desktop Workstation** (`module github.com/boostao/vpro/app`): Go `1.27+` (`CGO_ENABLED=1`), Wails v3 (`v3.1.0`), Svelte 5, MapLibre GL JS v6 + WebGPU + offline `PMTiles`, SQLite `VP08` (`WAL`), vendored C `libmdb` (`mdbtools 1.0.1`), `pgx/v5` Cloud `BECMaster` sync, and native `.xlsx`/`.gpkg`/TurboVeg 3 SQLite+XML/`.rds` interchange.
- **`r/`** — **Headless `vpro` R Companion SDK** (`R >= 4.4.0`, **zero Shiny/widgets**): WAL-safe `RSQLite`/`duckdb` readers, 2026 `BCPlantTaxonomy v19` & `BECdb v13` harmonization, `vegan`/`vegclust`/`indicspecies` phytosociology, `sf` GeoPackage, `bcgov/climr` $\rightarrow$ Ministry `aSMR` edatopic grids, BEC diagnostics, PostgreSQL `BECMaster` cloud sync/snapshots, and Quarto BEC guides.
- **`okf/`** — **Operational Knowledge Framework**: authoritative specifications across `01_history_and_evolution/`, `02_present_state/` (incl. `oracles/`), `03_future_architecture/`, `04_evidence_and_sources/`, and `05_engineering_and_agents/`.
- **`docs-src/`** — Single-source JSON authoring (`lmh25_fields.json`, `guides.json`, `tours.json`, `shortcuts.json`, `whats_new.json`, `data_use_agreement.json`) compiled into `app/resources/help_bundle.json`.
- **`site/`** — BC Government Design System (`BC Sans`, `#003366` BC Navy, `#FCBA19` Gold) static-manifest download & documentation portal (`site/build.mjs` $\rightarrow$ `site/dist`, `site/release-manifest.json`).
- **`scripts/`** — Help compiler (`build-docs-src.mjs`), release packaging/PE DLL validator (`release.py`, `release-windows.ps1`), and portal/release test suites (`scripts/tests/`).
- **`archive/`** — Historical October 2026 parity ledgers (`archive/oct2026-parity-ledgers/`); **historical provenance only — never governs scope or feature gating**.
- **`.github/`** — Unified CI/Pages/Release workflows, Copilot instructions, specialized agents (`vba-analyzer`, `vproguy`), and prompts (`vproguy-write`).

---

## 3. Shared `VP08`, BEC & Cloud `BECMaster` Domain Invariants

Both `app/` (Go) and `r/` (R) share one physical data contract and **must never diverge** on these rules:

1. **7-Database SQLite Family (`WAL` Mode) & `_table_metadata` (`'VP08'`):**
   - `<Project>.db` (8 tables per `<P>_`: `_Env`, `_Admin`, `_Veg`, `_Humus` [`SoilHumus`], `_Mineral` [`SoilMineral`], `_Other`, `_Audit`, `_Metadata`, plus optional `*_SU`, `*_Hierarchy` with `~` breakpoints, `*_Lump`, `*_Profile`, and `__VPRO_*` receipt/cache/identity tables), `VPro64.db`, `VLists.db` (`BCPlantTaxonomy v19`, `BECdb v13`, `LMH25 2023`), `VUser.db`, `VMetaData.db`, `VMessageBoard.db`, and `VPics.db`.
   - Do not invent `_Env.StartDate` or an `Env -> Metadata` FK (dead legacy VBA). Embedded `app/resources/*.db` read-models never replace `VLists.db` / `VUser.db`.
2. **Literal Text `PlotNumber` (`Text 7`):**
   - Always SQLite `TEXT` / Go `string` / R `character` (`typeof(PlotNumber) = 'text'`, `CAST(PlotNumber AS BLOB) = CAST(? AS BLOB)`), preserving leading zeroes (e.g., `'00337'`).
3. **Access `BOOLEAN`, `float32` Cover Narrowing, `99%` Lump Cap & ACE Rounding:**
   - Disk SQLite & `_Audit` store `true = -1`, `false = 0`, `NULL` = unset.
   - Narrow cover inputs to IEEE-754 `float32` *before* `< 100` (`99.999996` passes; `99.999999` narrows to `100` and rejects). Cap summed lumped (`*_Lump`) and fallback `TotalA`/`TotalB` strata covers at `99%` without mutating raw `<Project>_Veg`.
   - Format `double` to 15 significant decimal digits before half-away rounding (`1.005 -> 1.01`, [`VALUE_CONVERSIONS.md`](./okf/02_present_state/oracles/VALUE_CONVERSIONS.md)).
4. **`LMH25 (2023)` Soil Horizon Depth Sign & Ordering:**
   - Upland organic `SoilHumus` (`L`, `F`, `H`) measures **upward** from `0 cm` (`UpperDepth > LowerDepth`, ordered `UpperDepth DESC`); wetland organic (`Of`, `Om`, `Oh`) and `SoilMineral` (`A`, `B`, `C`, `R`, `W`) measure **downward** (`UpperDepth < LowerDepth`, ordered `UpperDepth ASC`).
5. **Catalogue Asymmetry, UTF-16 Bounds, Atomic Provenance & Cloud `BECMaster`:**
   - `VLists.USysAllSpecs.Lifeform` is `INT32` vs. `VUser.USysUserSpp.LifeForm` `INT16`; short-veg layer keys join `LayerCode.Layer1234567` (never padded `LayerCode.LayerCode`).
   - Enforce UTF-16 code-unit limits (`PlotNumber <= 7`, `Species <= 8`, `Horizon <= 8`, `Texture <= 4`, `Colour <= 14`).
   - Wrap every local write in `BEGIN IMMEDIATE` with `<Project>_Audit` + monotonic `__VPRO_*` child ID reservations (never reusing deleted IDs).
   - PostgreSQL `BECMaster` sync (`app/internal/cloudsync` & `r/R/cloud_*.R`) operates over 3 isolated schemas (`becmaster`, `staging`, `standards`) with TLS, secret redaction, pre-upload compliance gating, `SERIALIZABLE` Custodian 3-way merge, and SHA-256 hash-chained `becmaster.audit`.

---

## 4. Identical Cross-OS `vpro_data_dir()` & `vpro_config_dir()` Resolution

Go (`app/internal/sqlutil/sqlutil_foundation.go`: `UserDataDir()`, `UserConfigDir()`) and R (`r/R/workspace.R`: `vpro_data_dir()`, `vpro_config_dir()` — **never `rappdirs`**) resolve workspace paths identically (treating empty `""` env vars as unset):

| Function / Role | Priority 1: Explicit Override | Windows | macOS (`Darwin`) | Linux / Unix |
|---|---|---|---|---|
| **Data Dir** (`VLists.db`, `VUser.db`, `projects/`, `maps/`) | R `getOption("vpro.data_dir")`, then `VPRO_DATA_DIR` | `%LOCALAPPDATA%/vpro` *(fallback `%USERPROFILE%/AppData/Local/vpro`)* | `~/Library/Application Support/vpro` | `${XDG_DATA_HOME:-~/.local/share}/vpro` |
| **Config Dir** (`config.yml`) | R `getOption("vpro.config_dir")`, then `VPRO_CONFIG_DIR` | `%APPDATA%/vpro` | `~/Library/Application Support/vpro` | `${XDG_CONFIG_HOME:-~/.config}/vpro` |

---

## 5. Local Sibling Assets (`/home/bruno/Work/`) & Worktree Isolation

`glob` and `grep` default solely to this repository root. Pass explicit absolute `paths` when inspecting external local reference archives, include them in subagent prompts, and **never mutate `.accdb`/`.mdb`/`.zip` originals**:

- **`/home/bruno/Work/VPRO_ACCESS/`** — `LMH25_2023_web.pdf`, `Lmh25_2015.pdf`, `VProXP_Userguide.pdf`, `VPro2.0_Functions to remove-retain-modify.pdf`, `VproMailExchange/` (`RE26OCF433`), `SCREENCAPS/`, `Diagnostic10.xla`, and decompiled `VPro64_forAI/` (`Modules/`, `Queries/`, `Forms/`, `Tables_Data/`).
- **`/home/bruno/Work/VPRO_ACCESS_1/VPro64/`** — `BECMaster_fixing.accdb` (`545 MB`, `71,567` plots, `1.65M` veg rows — strictly read-only), `Haida_Gwaii_2019.accdb`, `Manning_TEM_Vpro19.accdb`.
- **`/home/bruno/Work/becweb_standards_2025_2026/`** — `BECdb_v13_2026.zip` & `BCPlantTaxa2025_access.zip`.
- **`/home/bruno/Work/spatial_assets/`**, **`/home/bruno/Work/MoF-Skeena-Research/`**, **`/home/bruno/Work/bcgov_ref/`**, and **`/home/bruno/Work/go-mdbtools/`**.
- **Parallel Multi-Agent Worktree Convention:** Isolate each mutating parallel subagent in `../vpro.worktrees/waveN-<track>` (`/home/bruno/Work/vpro.worktrees/waveN-<track>`) with strictly disjoint file ownership (never concurrently edit `app/frontend/bindings/`, `r/DESCRIPTION`, or generated `r/NAMESPACE` / `r/man/*.Rd`).

---

## 6. Quick Monorepo Validation Matrix

```bash
# 1. Desktop Frontend (Svelte 5 unit tests, svelte-check & Vite bundle)
(cd app/frontend && npm test && npm run check && npm run build)

# 2. Desktop Go Backend (SQLite-only canonical desktop profile) & Wails TS bindings
(cd app && go test -tags sqliteonly ./...)
(cd app && wails3 generate bindings -ts -i)

# 3. Headless R Companion SDK (air format, roxygen2, testthat & tarball R CMD check: 0E/0W/0N)
(cd r && air format R tests)
(cd r && Rscript -e "roxygen2::roxygenise()" && Rscript -e "testthat::test_local(stop_on_failure = TRUE)")
(cd r && R CMD build . && R CMD check --no-manual vpro_*.tar.gz && rm -rf vpro_*.tar.gz vpro.Rcheck)

# 4. Root Offline F1 Help Bundle, BC Gov Release Portal & Packaging Scripts
python3 -m unittest discover -s scripts/tests -p 'test_*.py'
node scripts/build-docs-src.mjs && node site/build.mjs && node --test scripts/tests/downloadPortal.test.cjs
```

