VPro 2.0 -> Legacy VPro64 (Microsoft Access) Import Bridge
==========================================================

Use this companion package to import any project database (.db) exported from
VPro 2.0 (Interchange -> VPro64, or Work Space -> Export to VPro64) directly
into a new or existing VPro64 Microsoft Access (.accdb) project.

Included files:
  - V7mdlImportSQLite.bas      VBA importer module for 64-bit Microsoft Access
  - Install-VPro64Bridge.ps1   Optional Windows setup helper (included in the zip)
  - README.txt                 This quick-start guide

-------------------------------------------------------------------------------
STEP 1: One-Time Windows ODBC Driver Setup
-------------------------------------------------------------------------------
No ODBC DSN configuration is required (the module connects DSN-less).

1. Confirm you are running 64-bit Microsoft Access (File -> Account -> About Access).
2. Download and install Christian Werner's 64-bit SQLite3 ODBC Driver:
     http://www.ch-werner.de/sqliteodbc/sqliteodbc_w64.exe
   Accept the default options and restart Microsoft Access if it was open.

-------------------------------------------------------------------------------
STEP 2: Install V7mdlImportSQLite.bas into your VPro64.accdb
-------------------------------------------------------------------------------
Option A — Manual Import (works on all Ministry workstations, 20 seconds):
  1. If you downloaded vpro64-sqlite-bridge.zip in a web browser, right-click
     the .zip file -> Properties -> check "Unblock" -> OK before extracting.
  2. Open your VPro64.accdb in Microsoft Access (enable macros if prompted).
  3. Press Alt+F11 to open the Visual Basic Editor.
  4. Choose File -> Import File... and select V7mdlImportSQLite.bas.
  5. Choose Debug -> Compile, then press Ctrl+S to save.

Option B — PowerShell Helper (when running from vpro64-sqlite-bridge.zip):
  1. Extract vpro64-sqlite-bridge.zip to a folder on your PC.
  2. Right-click Install-VPro64Bridge.ps1 -> Run with PowerShell, or run:
       powershell -ExecutionPolicy Bypass -File .\Install-VPro64Bridge.ps1
  3. Pick your VPro64.accdb when prompted. The helper backs up VPro64.accdb
     automatically before importing V7mdlImportSQLite.bas.

-------------------------------------------------------------------------------
STEP 3: Import a VPro 2.0 Project (.db) into VPro64
-------------------------------------------------------------------------------
1. In VPro 2.0, export your project via Interchange -> VPro64 (or Work Space ->
   Export to VPro64) to produce a clean single-file .db database.
2. In VPro64 (Microsoft Access), press Ctrl+G to open the Immediate Window.
3. Type:
     ImportSQLiteProject
   and press Enter (or wire a macro/button to RunCode -> ImportSQLiteProject()).
4. Follow the prompts to select the exported .db file, confirm the target
   project prefix and companion tables (SU, Hierarchy, Lump, Profile, Theme,
   Herbarium), pick the destination .accdb, and optionally link all tables
   into your active VPro64 session.

Quick driver self-test (in Access Immediate Window, Ctrl+G):
  ? TestSQLiteODBCDriver()
  (Should print True.)

What is preserved:
  - All 8 VP08 core tables (_Env, _Admin, _Veg, _Humus, _Mineral, _Other,
    _Audit, _Metadata) with exact VPro64 USys* field types, keys, and indexes
  - Leading-zero text PlotNumbers (e.g., "00337")
  - Checkboxes / booleans, AutoNumber IDs, long Memo notes, dates, and OLE photos
  - Optional companion tables (*_SU, *_Hierarchy, *_Lump, *_Profile, *_Theme,
    *_Herbarium) and all 6 valid VP08 table relationships
