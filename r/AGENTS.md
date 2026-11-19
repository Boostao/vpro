# `r/` — Headless `vpro` R Companion SDK Agent Instructions

**Read root [`../AGENTS.md`](../AGENTS.md) for monorepo routing and [`../okf/05_engineering_and_agents/r_sdk_engineering.md`](../okf/05_engineering_and_agents/r_sdk_engineering.md) + [`../okf/02_present_state/oracles/`](../okf/02_present_state/oracles/) for exhaustive invariants.**

## 1. Strict Zero-Shiny / Headless Architectural Boundary

- **Official Role:** `r/` (`R >= 4.4.0`) is exclusively the programmatic **headless `vpro` R Companion SDK & Scientific Analytics Package** for the VPro 2.0 Desktop Workstation (`../app/`). All interactive FS882/Two-Page/SIVI forms, datasheet grids, `SU`/`Hierarchy` trees, and 3D MapLibre/WebGPU GIS live solely in `../app/`.
- **Forbidden UI Dependencies:** `shiny`, `bslib`, `DT`, `rhandsontable`, `shinyTree`, `shinyjs`, `sass`, `leaflet`, and `rappdirs` are **strictly forbidden** in `DESCRIPTION` (`Depends` and `Imports`). Never create Shiny modules (`mod_*`), app shells (`ui.R`, `server.R`), HTML widgets, modal prompts, or Access-form GUI clones.
- **Startup & Sidecar Contract:** `.onLoad()` (`R/zzz.R`) must be fast, 100% offline, non-interactive, and side-effect-free. `vpro_project_inspect()` must preserve `isTRUE(insp$compatible)` expected by `../app/internal/rsidecar`.

## 2. Workspace Resolution & Concurrent SQLite WAL Guards

- **Byte-for-Byte Directory Parity (`R/workspace.R` $\leftrightarrow$ `../app/internal/sqlutil/sqlutil_foundation.go`):**
  - Never use `rappdirs` (causes doubled `vpro/vpro` on Windows and macOS/Linux config drift).
  - Honor `getOption("vpro.data_dir")` / `VPRO_DATA_DIR` and `getOption("vpro.config_dir")` / `VPRO_CONFIG_DIR` when non-empty; otherwise resolve Windows (`%LOCALAPPDATA%/vpro` & `%APPDATA%/vpro`), macOS (`~/Library/Application Support/vpro`), and Linux (`${XDG_DATA_HOME:-~/.local/share}/vpro` & `${XDG_CONFIG_HOME:-~/.config}/vpro`).
- **Read-Only Default (`SQLITE_RO`):** Open connections with `flags = RSQLite::SQLITE_RO` + `on.exit(DBI::dbDisconnect(con), add = TRUE)` (or `busy_timeout = 5000`, `synchronous = NORMAL`, `query_only = ON`), percent-encoding `#`, `?`, and `%` in `file:` URIs. Never hold idle write locks or run in-place `VACUUM` against live workspace DBs open in `../app/`.
- **Guarded Opt-In Write-Back (`BEGIN IMMEDIATE`):**
  - Permitted targets strictly limited to `<Name>_ClusterCandidate_SU`, user-confirmed working `<Name>_SU`, `<Name>_Lump`, `__VPRO_PlotClimate`, and `__VPRO_RSidecarHistory`.
  - Unconditionally refuse `Master*` (case-insensitive), `USys*` tables/views, bundled `VLists.db`, or unauthorized `BECSiteUnit`. Require `overwrite = TRUE` before replacing existing `*_SU` or `*_Lump` tables, and append `<Project>_Audit` + `__VPRO_*` provenance atomically without reusing deleted child IDs.

## 3. `VP08`, BEC Calibration & Cloud `BECMaster` Rules

- **Domain & Oracle Calibration (`../okf/02_present_state/oracles/`):**
  - Preserve the 7-DB SQLite family (`<Project>.db`, `VPro64.db`, `VLists.db`, `VUser.db`, `VMetaData.db`, `VMessageBoard.db`, `VPics.db`, uniformly seeded as `*.db.gz` in `inst/extdata/`) and `_table_metadata` (`'VP08'`).
  - Keep `PlotNumber` strictly R `character` / SQLite `TEXT` (never stripping leading zeroes like `'00337'`).
  - Convert Access `BOOLEAN` (`-1L` = `TRUE`, `0L` = `FALSE`, `NULL` = `NA` on disk $\leftrightarrow$ R `logical`).
  - Narrow cover to IEEE-754 `float32` before `< 100`, cap lumped (`*_Lump`) and fallback `TotalA`/`TotalB` strata sums at `99%` without mutating `<Project>_Veg`, honor `cover_precedence = c("strata_totals", "sublayer_sum")` across `vpro_veg()`, `vpro_master_veg()`, `vpro_summary_veg()`, and `vpro_matrix()`, apply ACE 15-sig-digit rounding (`1.005 -> 1.01`), respect `VLists.USysAllSpecs.Lifeform` (`INT32`) vs `VUser.USysUserSpp.LifeForm` (`INT16`), join short-veg layers on `LayerCode.Layer1234567`, enforce UTF-16 code-unit limits, and order `LMH25 (2023)` horizons (`L/F/H` upward `UpperDepth DESC`; `Of/Om/Oh` & `A/B/C/R/W` downward `UpperDepth ASC`).
- **Cloud `BECMaster` (`R/cloud_*.R`):**
  - Keep `RPostgres` optional in `Suggests`; resolve credentials from `.env` / `becmaster.env` / `VPRO_PG_*` / `BECMASTER_*` (`.env*` git/build-ignored) with strict password/DSN redaction in `vpro_pg_conn` `print()` methods and errors.
  - Enforce TLS (`sslmode = "require"` / `"verify-full"`) on non-loopback hosts, RBAC/RLS session roles (`public`, `contributor`, `ecologist`, `custodian`), fail-closed rare-plant coordinate truncation (`0.1°` ~10 km lat/lon, `10,000 m` UTM via `USysSppAttributes.RedBlueList`) on non-custodian reads/snapshots, `becmaster.download_log` entries on `vpro_master_pull()`, mandatory pre-upload compliance gating on `vpro_staging_submit()`, `SERIALIZABLE` Custodian 3-way merge (`vpro_staging_merge()`) with monotonic `child_identity`, and SHA-256 hash-chained `becmaster.audit` (`prev_hash` $\rightarrow$ `row_hash`) verified by `vpro_master_audit(..., verify_chain = TRUE)`.

## 4. R Formatting, Quality Gates & Worktree Rules

Keep `TMPDIR`/`TEMP`/`TMP` free of whitespace (`Rscript` aborts at C startup if `R_TempDir` contains spaces), keep `^AGENTS\.md$` in `.Rbuildignore`, write all user-facing docs (`DESCRIPTION`, `NEWS.md`, `README.md`, `vignettes/`, `roxygen2`, and user warnings) in plain field-focused language per [`../CONTRIBUTING.md`](../CONTRIBUTING.md#6-user-facing-voice--plain-language-lexicon-cbc-standard), and always run `R CMD check` on the built tarball (`0 errors | 0 warnings | 0 notes`):

```bash
bash scripts/format-r.sh
(cd r && Rscript -e "roxygen2::roxygenise()")
(cd r && Rscript -e "testthat::test_local(stop_on_failure = TRUE)")
(cd r && R CMD build . && R CMD check --no-manual vpro_*.tar.gz && rm -rf vpro_*.tar.gz vpro.Rcheck)
```

In parallel worktrees (`../vpro.worktrees/waveN-<track>`), maintain disjoint `R/<domain>_*.R` and `tests/testthat/test-<domain>_*.R` ownership and regenerate `NAMESPACE` / `man/*.Rd` via `roxygen2::roxygenise()` only at wave merge gates.
