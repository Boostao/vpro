# `app/` — VPro 2.0 Desktop Workstation Agent Instructions

**Read root [`../AGENTS.md`](../AGENTS.md) for monorepo routing and [`../okf/05_engineering_and_agents/desktop_app_engineering.md`](../okf/05_engineering_and_agents/desktop_app_engineering.md) + [`../okf/02_present_state/oracles/`](../okf/02_present_state/oracles/) for exhaustive invariants.**

## 1. Go Module, 4-Layer DAG & 12 Wails Services

- **Go Module:** `github.com/boostao/vpro/app` (`app/go.mod`, Go `1.25+`, `CGO_ENABLED=1`, `-tags sqliteonly` canonical profile).
- **4-Layer Acyclic DAG (`internal/integration/architecture_dag_test.go`):**
  - **Layer 0 (Assets & Foundations):** `resources` (`resources/embed.go`), `internal/sqlutil`, `internal/accessreader` (vendored `libmdb` `1.0.1` across `linux || windows || darwin`, Linux `-fvisibility=hidden` isolating `fakeglib` from GTK4, Windows `-static` zero non-inbox PE DLLs), `internal/accessimport`, `internal/accessinventory`, `internal/accesslayout`, `internal/accesscompare`, `internal/fs882layout`, `internal/listcatalog`, `internal/reports/subzonematrix`.
  - **Layer 1 (Core & Catalogues):** `internal/references`, `internal/vprocore` (`SQLiteContext`, `DesktopConfig`, `DatabaseFamily`, `ProjectService`, `ContextService`, `PlotService` + `vprotest`), `internal/sourceform` (+ `sftest`), `internal/reports/reportcore`.
  - **Layer 2 (Independent Domain Packages — zero sibling Layer-2 imports):** `internal/lifecycle`, `internal/plotentry`, `internal/sivi`, `internal/twopage`, `internal/datasheet`, `internal/classification`, `internal/validation`, `internal/vegreport`, `internal/envreport`, `internal/spatial`, `internal/pictures`, `internal/interchange`, `internal/cloudsync`, `internal/projectops`, `internal/diagnostics`, `internal/lumping`, `internal/lmh25rules`, `internal/rsidecar` (+ cross-domain `internal/integration`).
  - **Layer 3 (Thin Wails Host `package main`):** `main.go`, `native_options.go`, `aliases.go`, and `domainservices_*.go` registering **strictly 12 services**: `LifecycleService`, `ContextService` (incl. 19 `cloudsync` RPCs), `PlotEntryService`, `DatasheetService`, `ClassificationService`, `ValidationService`, `ImportExportService`, `VegetationReportService`, `EnvironmentReportService`, `SpatialService`, `PictureService`, `HelpService`.
- **Frontend Layout:** Preserve `frontend/src/{shell,entry,datasheet,classification,reports,spatial,diagnostics,rsidecar,interchange,admin,pictures,help,shared}/` and `frontend/tests/` (`frontend/scripts/run-tests.mjs` + shared wire round-trip `fixtures/`).
- **Feature Graduation & Branding:** Validated features run default-ON (`config.yml` `release_channel: stable | experimental`, `internal/lifecycle/buildinfo.go` `dev|alpha|release`, `VPRO_WEBVIEW_DEBUG_PORT` strictly `dev`-only). Keep client Red items (`PC-ORD Break Report`, standalone `CHARS` forms) pruned; expose CHARS (`Cover5a..5c`, `SnowCoverregime`, `ActiveLayerDepth`) via `"Show extended shrub layers"`. Brand strictly as **`VPro`** (`VPro.app`).

## 2. Backend SQLite WAL, Cloud Sync & Access Calibration Guards

- **Dual-Connection `SQLiteContext`:** Escape `file:` URIs via `net/url` (`#` truncates `mode=ro`!), verify `os.SameFile` around `ATTACH DATABASE`, use caller-owned `beginReadSnapshot` on the `:memory:` read coordinator, reuse held operation read leases instead of recursive `RWMutex.RLock`, and fence every switch with a fresh 128-bit `contextID`.
- **Atomic Writes & Calibration:** Wrap mutations + `<Project>_Audit` + `__VPRO_*` child ID reservations in one `BEGIN IMMEDIATE` transaction (never reuse deleted child IDs). Preserve Access `BOOLEAN` (`true = -1`, `false = 0`), narrow cover to `float32` before `<100` (`99.999996` passes; `99.999999` rejects), cap lumped/fallback strata cover at `99%`, apply 15-sig-digit ACE rounding (`1.005 -> 1.01`), enforce UTF-16 code-unit bounds & `sqlutil.ValidateRawJSONWire` / `DecodeStrictJSON`, omit unchanged legacy out-of-rule columns on `UPDATE`, use `typeof(col)='text'` + `CAST(col AS BLOB)=CAST(? AS BLOB)` for `PlotNumber`, honor `INT32` vs `INT16` `Lifeform` & `LayerCode.Layer1234567`, and order `LMH25` horizons (`L/F/H` upward `UpperDepth DESC`; `Of/Om/Oh` & `A/B/C/R/W` downward `UpperDepth ASC`).
- **Cloud `BECMaster` (`internal/cloudsync`) & R Sidecar (`internal/rsidecar`):** Maintain 3-schema (`becmaster`, `staging`, `standards`) parity with `../r/R/cloud_*.R`, redact secrets/DSNs, require TLS on non-loopback hosts, run `RunComplianceValidation` before staging upload, and keep Custodian 3-way merge `SERIALIZABLE` with SHA-256 hash-chained `audit`. Quote/short-path `Rscript --vanilla` calls and never open read-only sidecar queries in `rw` mode.

## 3. Svelte 5, Wails IPC, Native COM & Excelize Guards

- **Wails Bindings:** Always run `wails3 generate bindings -ts -i` (`-i` is mandatory so nullable arrays emit TypeScript interfaces rather than classes).
- **Svelte 5 & Async Fencing:** Detach proxies with `$state.snapshot(...)` (or `$state.raw`) before IPC/`structuredClone`. Recheck request generation after awaited client validation and yield during large XML validation so Cancel/remount/close barriers (`CloseService` `"vpro:close-request"` $\rightarrow$ `ConfirmClose`/`CancelClose`; wait for `CancelClose` ack in tests) can run.
- **Wire Fixtures, Chunked IPC, Excelize & YAML:** Match frontend mocks to shared strict-Go round-trip fixtures (`declaredType`, not `type`). Reassemble chunked UTF-8 Wails request bodies by upload ID and never replay a completed mutation if response capture was missed. Use `strings.EqualFold` for `excelize/v2` worksheet collisions, validate case-folded grouping keys before threshold filtering, and keep `type configValues = map[string]any` as a `yaml.v3` type alias.
- **Native Windows COM (`go-ole`):** Keep `HWND`/state outside native COM interface memory, pass receiver + all args, treat `HRESULT` as signed `int32`, classify Cancel only from `Show`'s `ERROR_CANCELLED`, treat `IUnknown.Release` return as refcount (not `HRESULT`), and balance STA init after releasing interfaces/paths.

## 4. Validation Commands (from Monorepo Root)

```bash
(cd app/frontend && npm test && npm run check && npm run build)
(cd app && go test -tags sqliteonly ./...)
(cd app && wails3 generate bindings -ts -i)
# Use -a after editing C headers/sources inside app/internal/accessreader:
(cd app && go test -a -tags sqliteonly ./internal/accessreader/...)
```
