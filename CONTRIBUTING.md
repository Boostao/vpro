# Contributing, Maintenance & Release Runbook (`Boostao/vpro`)

Thank you for maintaining **VPro 2.0**. Before editing any subsystem, read the monorepo routing contract in [`AGENTS.md`](./AGENTS.md) and the scoped contract for your target directory ([`app/AGENTS.md`](./app/AGENTS.md) or [`r/AGENTS.md`](./r/AGENTS.md)).

---

## 1. Prerequisites & Local Validation Matrix

- **Desktop (`app/`):** Go `1.27+` (`CGO_ENABLED=1`), Node `24+`, `wails3` CLI matching `app/go.mod` (`v3.1.0`), plus GTK4 & WebKitGTK 6.0 dev headers on Linux (or MinGW/LLVM-MinGW + NSIS on Windows).
- **R SDK (`r/`):** R `>= 4.4.0`, `quarto` CLI (optional for guides), `air` formatter.

```bash
# Desktop frontend unit suites, typecheck & Vite bundle
(cd app/frontend && npm test && npm run check && npm run build)

# Desktop Go backend & TS interface bindings
(cd app && go test ./...)
(cd app && wails3 generate bindings -ts -i)

# Headless R Companion SDK (zero-note tarball R CMD check)
(cd r && air format R tests)
(cd r && Rscript -e "roxygen2::roxygenise()" && Rscript -e "testthat::test_local(stop_on_failure = TRUE)")
(cd r && R CMD build . && R CMD check --no-manual vpro_*.tar.gz && rm -rf vpro_*.tar.gz vpro.Rcheck)

# Dependency lockstep, F1 help bundle, BC Gov portal & release verifier
python3 scripts/check-dep-lockstep.py
python3 -m unittest discover -s scripts/tests -p 'test_*.py'
node scripts/build-docs-src.mjs && node site/build.mjs && node --test scripts/tests/downloadPortal.test.cjs
```

---

## 2. 4-Tier Dependency Update Policy

Third-party upgrades are partitioned by blast radius (enforced by `.github/dependabot.yml`, `scripts/check-dep-lockstep.py`, and `.github/workflows/upstream-canary.yml`):

| Tier | Covered Dependencies | Update Cadence & Mechanism | Guardrails |
|---|---|---|---|
| **1. Routine Patches** | GitHub Actions, isolated Go/npm libs | Monthly grouped PRs via `.github/dependabot.yml` | Standard `ci.yml` + weekly `govulncheck` & `npm audit` |
| **2. Coupled Runtimes (Lockstep)** | `wailsapp/wails/v3` $\leftrightarrow$ `@wailsio/runtime` $\leftrightarrow$ `wails3` CLI; `@deck.gl/*` & `@luma.gl/*` | Manual coordinated bump PR (ignored by Dependabot) | Must pass `python3 scripts/check-dep-lockstep.py` + `wails3 generate bindings -ts -i` |
| **3. Native CGO / Cross-OS** | `mattn/go-sqlite3`, vendored `libmdb`, Windows `winlibs`/`llvm-mingw` toolchains in `scripts/release.py` | Manual PR with explicit toolchain & PE DLL verification | Must run `go test -a ./internal/accessreader/...` and cross-OS compile smoke (`upstream-canary.yml`) |
| **4. Scientific R & Annual BEC Standards** | `bcgov/climr`, `vegan`, `vegclust`, `BECdb`, `BCPlantTaxonomy` | Weekly R `Suggests` canary (`upstream-canary.yml`) + Annual Standards ingestion | Heavy R analytics stay in `Suggests` (`r/DESCRIPTION`); standards updates follow §3 below |

---

## 3. Annual BEC Standards Update Runbook (`VLists.db`)

When the BC Ministry of Forests publishes a new `BECdb` or `BCPlantTaxonomy` release:

1. Place the official `.zip`/`.accdb` archives in the local read-only standards staging directory (never mutate source archives) and record their SHA-256 checksums.
2. Regenerate `app/resources/` SQLite read-models, `app/resources/database-family/VLists.db`, and `app/resources/standards-2026-provenance.json` via `app/cmd/standards2026` (verify expected table counts and `Codetype = 'XX'` preservation).
3. Sync `r/data-raw/lists/`, recompress `r/inst/extdata/VLists.db.gz`, and update any version labels in `docs-src/` and `site/build.mjs`.
4. Run the full Desktop, R `R CMD check`, and `site/` test matrices, and test `vpro_standards()` + `standards.library_releases` ingestion against PostgreSQL `BECMaster`.

---

## 4. 5-Tier Reliability Testing Pyramid

Changes affecting ecological calculations, storage, or UI must satisfy the applicable tier:

1. **Tier 1 — Data Safety & Parser Fuzzing:** Atomic `BEGIN IMMEDIATE` SQLite WAL mutations, `<P>_Audit` receipts, monotonic child IDs, unsaved-draft close barriers, and malformed `.accdb` / XML / TSV inputs.
2. **Tier 2 — Empirical Oracle & Go $\leftrightarrow$ R Equivalence:** Bitwise/numeric parity against `okf/02_present_state/oracles/` (`float32` cover narrowing, `99%` lump cap, 15-sig-digit ACE rounding, `LMH25` horizon depth signs, `d/dd/cd/c/ic` fidelity).
3. **Tier 3 — Service, 4-Layer DAG & Live PG16 RBAC/RLS:** Executed automatically on PRs in `.github/workflows/ci.yml`.
4. **Tier 4 — Multi-Viewport Browser & Spotlight Tour QA:** Verify zero horizontal overflow, legible controls across desktop (`1920×1080`), field laptop (`1366×768`), Toughbook/tablet (`1024×768`, `768×1024`), and mobile (`390×844`), plus non-overlapping tour spotlights.
5. **Tier 5 — Cross-OS Artifact & Installer Verification:** Enforced in `.github/workflows/release.yml` via `scripts/release.py` (PE DLL allowlist, universal Mach-O slices, `SHA256SUMS.txt`, and `site/release-manifest.json`).

---

## 5. BC Field-Season Release Cycle

Releases align with the British Columbia ecological field season:

- **Spring Stable (`v2.x.0` — March / April):** Pre-season desktop + R SDK release (`scope: full`) promoted from `preview` to `stable` in `site/release-manifest.json` after multi-OS UAT.
- **Summer Field-Season Freeze (May – September):** Strict `v2.x.y` patch-only bugfixes for data-entry stability; zero disruptive schema or workflow UI changes during active plot collection.
- **Fall / Winter Analytics & Standards (`v2.(x+1).0` / `r-v*` — October – February):** Annual `BECdb`/`BCPlantTaxonomy` updates, new diagnostics/interchange features, and rapid standalone `r-vX.Y.Z` (`scope: r-only`) R SDK releases.

---

## 6. User-Facing Voice & Plain-Language Lexicon ("CBC Standard")

All user-facing copy across VPro (`app/frontend/src/`, `docs-src/*.json`, `site/`, `README.md` overview/quickstart, `ROADMAP.md`, and `r/` package descriptions, `NEWS.md`, vignettes, and errors) must read at **CBC plain-language level**: clear, concrete, calm prose focused on **what the feature does and looks like** for field ecologists, foresters, BEC analysts, and data custodians—never on internal software libraries, protocols, or storage mechanics.

- **Keep authentic BEC & VPro domain terms:** `FS882`, `FS1333 (SIVI)`, `LMH25 (2023)`, `BECdb v13`, `BCPlantTaxonomy v19`, `rSMR`, `aSMR`, `rSNR`, `Site Unit`, `Hierarchy`, `Lumping`, `Presence Class`, `Domin-Krajina`, `PlotNumber`, `BECMaster`, `VENUS 5.0`, `TurboVeg 3`.
- **Replace engineering/contract jargon with plain equivalents:**

| Avoid in User-Facing Copy | Use Instead |
|---|---|
| `MapLibre` / `WebGPU` / `deck.gl` / `WGSL` / `FlatGeobuf` | `3D Map` / `Map` (or omit rendering engine details) |
| `PMTiles` / `HTTP 206 byte-range PMTiles` / `PMTiles v3 Hilbert MVT` | `offline map` / `offline BGC & boundary layers` |
| `SQLite WAL` / `PRAGMA journal_mode = WAL` / `WAL-safe` | `VPro project file (.db)` / `live VPro workspace` |
| `Out-of-process R & Quarto Sidecar` / `Headless R Companion SDK` | `R Companion` / `vpro R package` / `R Analysis & Guides` |
| `Auto-1..Auto-7`, `Schedule A 3.c.ii`, `(4.d)` / `(4.e)` | `Coordinate & BGC Stamp`, `LMH25 Field Checks`, `Lumping Presets & Rules`, `Auto-Populate Project Metadata`, `Single Site Unit Guide`, `BGC Subzone / Variant Guide` |
| `Diagnostic10.xla` | `VPro diagnostic Excel workbook (.xlsx)` |
| `Declarative LumpSpec` | `Lumping Presets & Rules` |
| `UTF-16 code units` | `characters` (keep `"8 UTF-16"` only where an existing test regex explicitly matches it) |
| `IEEE-754 SINGLE` / `float32 < 100` | `percent cover from 0 to under 100% (e.g. 99.9%)` |
| `BEGIN IMMEDIATE` / `atomic transaction` / `SERIALIZABLE` / `cryptographic stale-request protection` | `saved safely in one step` / `conflict-checked custodian merge` / `protected against accidental overwrites` |
| `__VPRO_PlotClimate`, `__VPRO_ImportQuarantine`, `<Name>_ClusterCandidate_SU` | `plot climate cache`, `import quarantine log`, `candidate Site Unit table` |
| `< 10 ms` / `sub-50ms` / `virtualized grid` / `Materialize` | `updates immediately` / `multi-plot spreadsheet` / `Build` or `Restore` |
| `Wails` / `Svelte` / `Go 1.27` / `C/Go reader` / `VP05–VP08` (unless inspecting schema metadata) | omit or say `VPro Desktop` / `legacy Access projects` |

---

## 7. Release Notes (`whatsNew` & `r/NEWS.md`) Condenser & Pre-Tag Checklist

Because `app/resources/help_bundle.json` is compiled into the desktop binary (`//go:embed`), desktop release notes **must be updated before cutting a `vX.Y.Z` release tag**:

1. **Edit `docs-src/whats_new.json`:** Place the newest release entry at index `0` (`version`, `date` `YYYY-MM-DD`, `channel` `"stable"` or `"preview"`, `highlights`). Index `0` is treated as `"latest"` by `HelpService.AcknowledgeWhatsNew`.
2. **Condenser rules (for both `docs-src/whats_new.json` and `r/NEWS.md`):**
   - Condense commits and PRs into **4–7 workflow-themed bullets** (*Data Entry*, *3D Map*, *Classification & Diagnostics*, *Reports & Interchange*, *Standards & Fixes*)—never a commit log or file list.
   - Lead every bullet with the **user-visible outcome** in one plain sentence answering *"What can an ecologist do now?"*.
   - Omit library names, internal `__VPRO_*` tables, SQL isolation levels, contract codes, and millisecond micro-benchmarks.
3. **Compile and verify zero drift before tagging:**
   ```bash
   node scripts/build-docs-src.mjs && node site/build.mjs && node --test scripts/tests/downloadPortal.test.cjs
   ```
   Commit `docs-src/whats_new.json`, `app/resources/help_bundle.json`, and `r/NEWS.md` (when applicable) together.

---

## 8. Parallel AI Agent Worktree Isolation

When running parallel mutating agents, isolate each track in `../vpro.worktrees/waveN-<track>` with strictly disjoint file ownership. Never modify `app/frontend/bindings/`, `r/DESCRIPTION`, `r/NAMESPACE`, or `r/man/*.Rd` concurrently across multiple worktrees; regenerate shared bindings and roxygen docs at the merge gate.
