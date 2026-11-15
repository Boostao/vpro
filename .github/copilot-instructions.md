# GitHub Copilot Instructions — `vpro` (Headless R Companion SDK)

**Read [`AGENTS.md`](../AGENTS.md) first.** `AGENTS.md` is the single authoritative architectural, domain, and workflow contract for this repository.

## Core Rules Summary

1. **Headless R Companion SDK Only (`R >= 4.4.0`):**
   - `vpro` is the programmatic R SDK & scientific analytics companion to the official **`vpro_wails`** desktop application (`/home/bruno/Work/vpro_wails`, Wails v3 + Go + Svelte 5 + SQLite WAL) for the B.C. Ministry of Forests **BEC Program**.
   - **Zero Shiny / Widget UI:** `shiny`, `bslib`, `DT`, `rhandsontable`, `shinyTree`, `shinyjs`, `sass`, `leaflet`, and `rappdirs` are **forbidden** in `Imports`. Desktop forms, CRUD UI, and interactive WebGPU maps live exclusively in `vpro_wails`.
   - R owns tidy `VP08` SQLite extraction, standards/QC validation, `vegan`/`vegclust`/`indicspecies`/`labdsv` community matrices, `sf`/`terra` spatial analysis, `bcgov/climr` + `CMD -> aSMR` edatopic modelling, BEC differential/diagnostic synthesis, guarded opt-in `*_ClusterCandidate_SU` / `*_SU` / `*_Lump` / `__VPRO_PlotClimate` write-back, and Quarto BEC reporting.

2. **Exact `vpro_wails` Directory & SQLite WAL Coexistence:**
   - `vpro_data_dir()` and `vpro_config_dir()` must match `/home/bruno/Work/vpro_wails/internal/sqlutil/sqlutil_foundation.go` byte-for-byte (`VPRO_DATA_DIR` / `getOption("vpro.data_dir")` and `VPRO_CONFIG_DIR` / `getOption("vpro.config_dir")` overrides first; never `rappdirs`'s doubled `vpro/vpro` on Windows).
   - Default to read-only `RSQLite` connections (`SQLITE_RO` or `busy_timeout = 5000`, `synchronous = NORMAL`, `query_only = ON`) so R never blocks a live `vpro_wails` WAL session.
   - Opt-in write-back uses `BEGIN IMMEDIATE`, refuses `Master*` and `USys*` tables, requires `confirm_overwrite = TRUE` before replacing existing `*_SU`/`*_Lump` tables, and appends `<Project>_Audit` + `__VPRO_*` provenance atomically.

3. **Non-Negotiable `VP08` & BEC Domain Invariants (Details in `AGENTS.md` §3 & `inst/doc-oracles/`):**
   - Preserve the 7-DB SQLite family (`<Project>.db`, `VPro64.db`, `VLists.db`, `VUser.db`, `VMetaData.db`, `VMessageBoard.db`, `VPics.db`) and `_table_metadata` (`'VP08'`).
   - `PlotNumber` is **always** literal `character` (`typeof(PlotNumber) = 'text'`, preserving leading zeroes like `'00337'`).
   - Access `BOOLEAN`: `-1L` = `TRUE`, `0L` = `FALSE` on disk $\leftrightarrow$ R `logical` in memory.
   - Narrow cover to IEEE-754 `float32` before `< 100`, cap lumped (`*_Lump`) per-layer cover at `99%`, apply ACE 15-significant-digit half-away rounding where calibrated, respect `VLists.USysAllSpecs.Lifeform` (`INT32`) vs `VUser.USysUserSpp.LifeForm` (`INT16`), and order `LMH25 (2023)` soil horizons (`L/F/H` `UpperDepth > LowerDepth` `DESC`; `Of/Om/Oh` & `A/B/C/R/W` `UpperDepth < LowerDepth` `ASC`).

4. **Sibling Asset Discovery & Verification Gates (Details in `AGENTS.md` §4–§5):**
   - Pass explicit absolute paths when searching sibling directories (`/home/bruno/Work/vpro_wails/`, `/home/bruno/Work/VPRO_ACCESS/okf/00_index.md`, `/home/bruno/Work/MoF-Skeena-Research/`, `/home/bruno/Work/bcgov_ref/`, `/home/bruno/Work/VPRO_ACCESS_1/VPro64/BECMaster_fixing.accdb` [read-only], `/home/bruno/Work/spatial_assets/`).
   - Validate package changes with `Rscript -e "roxygen2::roxygenise()"`, `Rscript -e "testthat::test_local(stop_on_failure = TRUE)"`, and tarball check `R CMD build . && R CMD check --no-manual vpro_*.tar.gz` (`0 errors | 0 warnings | 0 notes`).
   - Isolate parallel subagents in `/home/bruno/Work/vpro.worktrees/waveN-<track>` with strictly disjoint `R/<domain>_*.R` and `tests/testthat/test-<domain>_*.R` files, regenerating `NAMESPACE` and `man/` only on `master` at wave merge gates.
