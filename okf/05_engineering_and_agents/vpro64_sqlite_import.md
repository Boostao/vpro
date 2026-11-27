# VPro64 VBA SQLite Importer (`V7mdlImportSQLite.bas`) — Setup & Operator Guide

> **Navigation:** [Master Index](../00_index.md) | **Playbooks:** [Desktop App Engineering](./desktop_app_engineering.md) · [Headless R SDK](./r_sdk_engineering.md) · [Web Read-Only Deployment](./web_readonly_deployment.md) · `VPro64 SQLite Importer`

---

## 1. Purpose & Rationale

Exporting directly from VPro 2.0 to native Microsoft Access `.accdb` binaries across platforms is fragile because embedded `libmdb` is read-only and ACE/Jet binary writers require Microsoft Access on Windows. Instead, **`scripts/vpro64/V7mdlImportSQLite.bas`** runs natively inside **VPro64 (`VPro64.accdb`)** and imports any **VPro 2.0 SQLite `.db`** file (in `WAL` or `DELETE` journal mode) directly into a new or existing Access `.accdb` database using the **SQLite3 ODBC Driver** and VPro64's canonical `USys*` template tables.

### What It Imports & Preserves
- **All 8 Core `VP08` Project Tables:** `_Env`, `_Admin`, `_Veg`, `_Humus`, `_Mineral`, `_Other`, `_Audit`, `_Metadata` (created from `VPro64.accdb`'s `USys*` templates with exact field types, indexes, primary keys, and `"VP08"` `Description` properties).
- **Optional Companion Tables:** `*_SU`, `*_Hierarchy` (including `Parent.RowSource` update), `*_Lump`, `*_Profile`, `*_Theme`, and `*_Herbarium` (including OLE `Photo` BLOBs).
- **Exact VPro 2.0 / Access Fidelity:**
  - Leading-zero literal text `PlotNumber` values (e.g., `'00337'`, `'00001'`).
  - VPro 2.0 booleans (`-1` and `1` $\rightarrow$ `True`; `0` and `NULL` $\rightarrow$ `False`), normalized in SQLite SQL before crossing ODBC so Christian Werner's SQLite3 ODBC Driver never misinterprets `-1` as `False`.
  - Exact `AutoNumber` `ID` / `RecID` preservation (positive and negative IDs) via prepared DAO `QueryDef` inserts so `Hierarchy.Parent` and child row IDs remain intact.
  - Lossless `Memo` (`>255` characters, full UTF-8) and `OLE` (`dbLongBinary`) transfer via deferred `DAO.Recordset` writes on AutoNumber tables (working around ACE `PARAMETERS` 255-char limits).
  - Locale-independent ISO-8601 `Date` / `TIMESTAMP` parsing (`YYYY-MM-DD`, `YYYY-MM-DD HH:NN:SS`, `YYYY-MM-DDTHH:NN:SSZ`).
  - Batched transactions (`2,000` rows per `BeginTrans`/`CommitTrans`) to avoid Jet/ACE `MaxLocksPerFile` (Error 3052) on large datasets.
  - All 6 valid `VP08` relationships (`<P>1`–`<P>5` + `<P>7` `_Env -> _Admin`), omitting legacy dead `_Env.StartDate -> _Metadata`.
  - Optional immediate linking (`acLink`) of all imported tables into the active `VPro64.accdb` session.

---

## 2. One-Time Windows Setup (SQLite3 ODBC Driver)

No ODBC Data Source Name (DSN) configuration is needed — `V7mdlImportSQLite.bas` connects **DSN-less**.

1. **Confirm your Microsoft Access bitness:**
   - Open Microsoft Access $\rightarrow$ **File** $\rightarrow$ **Account** $\rightarrow$ **About Access**.
   - VPro64 runs on **64-bit** Microsoft Access.
2. **Download and install Christian Werner's SQLite3 ODBC Driver:**
   - **64-bit Access (VPro64 standard):** `http://www.ch-werner.de/sqliteodbc/sqliteodbc_w64.exe`
   - *(32-bit Access only: `http://www.ch-werner.de/sqliteodbc/sqliteodbc.exe`)*
   - Run the installer (accept defaults; silent unattended install switch is `/S`).
3. **Verify driver registration (optional PowerShell check):**
   ```powershell
   Get-OdbcDriver | Where-Object { $_.Name -like "*SQLite*" } | Format-Table Name, Platform
   # Expected output:
   # SQLite3 ODBC Driver   64-bit
   ```
4. **Restart Microsoft Access** if it was open during driver installation.

---

## 3. Obtaining & Installing `V7mdlImportSQLite.bas` into `VPro64.accdb`

The bridge ships in three synchronized places (byte-for-byte identical `.bas` verified by `scripts/release.py` and Go tests):
- **GitHub Releases & Download Portal (`site/`):** `vpro64-sqlite-bridge.zip` (attached to every official `vX.Y.Z` release and nightly `dev-*` pre-release with SHA-256 checksums, containing `V7mdlImportSQLite.bas`, `Install-VPro64Bridge.ps1`, and `README.txt`).
- **Offline inside VPro 2.0 Desktop:** **Interchange** $\rightarrow$ **VPro64** (checked by default: *"Include VPro64 VBA importer (`V7mdlImportSQLite.bas`) & setup guide"* writes both files right next to the exported `.db`).
- **Monorepo source:** `scripts/vpro64/V7mdlImportSQLite.bas` (mirrored into `app/resources/vpro64/V7mdlImportSQLite.bas`).

### Option A: Automated Windows Setup (`Install-VPro64Bridge.ps1` in `vpro64-sqlite-bridge.zip`)
1. Right-click `vpro64-sqlite-bridge.zip` $\rightarrow$ **Properties** $\rightarrow$ check **Unblock** $\rightarrow$ **OK**, then extract.
2. Run PowerShell in the extracted folder:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\Install-VPro64Bridge.ps1
   ```
   The helper clears any remaining Mark-of-the-Web flags, verifies the 64-bit `SQLite3 ODBC Driver`, saves a timestamped backup of your `VPro64.accdb`, and imports `V7mdlImportSQLite.bas` via Access COM (falling back cleanly to manual instructions if VBA project trust is locked down by Group Policy).

### Option B: Manual Import (20 seconds, works on all Ministry workstations)
1. Open **`VPro64.accdb`** in Microsoft Access (enable macros/content if prompted).
2. Press **`Alt+F11`** to open the VBA Editor.
3. Choose **File** $\rightarrow$ **Import File...** and select **`V7mdlImportSQLite.bas`**.
4. Confirm **`V7mdlImportSQLite`** appears under **Modules**.
5. Choose **Debug** $\rightarrow$ **Compile** (no extra **Tools** $\rightarrow$ **References** are required — the module uses `DAO` already referenced in `VPro64.accdb` plus late-bound `ADODB`).
6. Save (`Ctrl+S`).

---

## 4. Usage

### Option A: Interactive GUI Wizard
Run **`ImportSQLiteProject`** from:
- The VBA Immediate Window (`Ctrl+G` $\rightarrow$ type `ImportSQLiteProject` $\rightarrow$ `Enter`), or
- A button/menu/macro wired to `RunCode` $\rightarrow$ `ImportSQLiteProject()`.

The wizard walks through:
1. Checking that `SQLite3 ODBC Driver` is installed.
2. Picking the source VPro 2.0 `.db` file.
3. Selecting the detected project (and optionally choosing a new Access project prefix).
4. Choosing whether to also import companion tables (`*_SU`, `*_Hierarchy`, `*_Lump`, `*_Profile`, `*_Theme`, `*_Herbarium`).
5. Picking a new or existing target `.accdb` file.
6. Optionally attaching (linking) all imported tables straight into `VPro64.accdb`.

### Option B: Driver Self-Test
In the VBA Immediate Window:
```vb
? TestSQLiteODBCDriver()
' Returns True if SQLite3 ODBC Driver is installed and working.
? TestSQLiteODBCDriver("C:\path\to\Sample.db")
' Also verifies reading the specified SQLite file.
```

### Option C: Scripted / Batch API
```vb
Dim summary As String
summary = ImportSQLiteDatabaseToAccdb( _
    SqlitePath:="C:\path\to\MyProject.db", _
    TargetAccdbPath:="C:\path\to\MyProject.accdb", _
    SourceProjectName:="MyProject", _
    TargetProjectName:="MyProject", _
    IncludeCompanions:=True, _
    AttachToCurrentVPro:=True, _
    Silent:=False)
```

---

## 5. Technical Notes & Troubleshooting

| Symptom | Cause | Resolution |
|---|---|---|
| `SQLite3 ODBC Driver not found` | Driver not installed, or 32-bit driver installed for 64-bit Access | Install `sqliteodbc_w64.exe` (64-bit) and restart Microsoft Access. |
| `Required VPro64 template table 'USys...' was not found` | Module was run from a blank `.accdb` instead of `VPro64.accdb` | Import and run `V7mdlImportSQLite.bas` inside `VPro64.accdb`. |
| `Target table '..._Env' already exists` | Target `.accdb` already contains that project prefix | Pick a new `.accdb` filename or enter a different target project prefix. |
| Relationship warning in summary (`Could not enforce relationship...`) | Source SQLite project contains legacy orphan child rows missing a matching `_Env.PlotNumber` | All rows are still imported safely; clean up orphan rows in Access (or VPro 2.0 Quarantine) before re-enforcing the relationship. |
| Importing while VPro 2.0 has the `.db` open | VPro 2.0 uses SQLite `WAL` mode | Supported: the importer opens SQLite read-only (`NoCreat=1;SyncPragma=OFF;NoTXN=1`) and reads committed WAL state without modifying the `.db` file. |
