# VPRO Compliance & Validation Features - Comprehensive Inventory

## Executive Summary
The VPRO Access database and Shiny migration contain extensive compliance and data validation features designed to ensure data integrity before submission. Compliance is tracked through audit trails, with validation rules applied to environmental data, vegetation samples, and code standards. The system supports both real-time validation and comprehensive data integrity checks.

---

## 1. FORMS IMPLEMENTING COMPLIANCE FEATURES

### A. Primary Compliance/Validation Forms

#### **USysValidateData.txt**
- **Location**: `../VPRO_ACCESS/VPro64_forAI/Forms/USysValidateData.txt`
- **Purpose**: Main data validation and repair form
- **Caption**: "Data Check and Repair"
- **Record Source**: `UsysEnv` 
- **Features**:
  - Validates environment (Sample_Env) data against list tables
  - Checks fields marked with `Validate = Yes` in USysTableOfLists
  - Supports ValidateLoops for multi-field validation
  - Responds to ribbon menu commands
  - Referenced by `DoCmd.OpenForm "USysValidateData"` in V7mdlRibbonOnAction

#### **USysAudit.txt**
- **Location**: `../VPRO_ACCESS/VPro64_forAI/Forms/USysAudit.txt`
- **Purpose**: VPro Data History audit trail form
- **Caption**: "VPro Data History"
- **Record Source**: Query based on `USysAuditTrail` with filters for current project and plot number
- **Key Fields Displayed**:
  - `Project` - Project identifier
  - `PlotNumber` - Sample plot identification
  - `EditWhen` - Timestamp of edit
  - `BeforeEdit` - Previous value
  - `AfterEdit` - New value
  - `EditField` - Field that was modified
  - `Table` - Target table
  - `Restore` - Boolean flag to restore value
  - `User` - User who made the edit
  - `ID` - Audit record ID
- **Form Event**: `OnLoad=[Event Procedure]` for initialization

#### **USysCodeCheck.txt**
- **Location**: `../VPRO_ACCESS/VPro64_forAI/Forms/USysCodeCheck.txt`
- **Purpose**: Species code validation and spell-check interface
- **Features**:
  - Validates species codes against list tables
  - Provides "Change All" functionality for bulk corrections
  - Highlights codes not found in USysTableOfLists
  - Fields: `btnChangeAll`, `txtNotInList`, `txtChangeTo`
  - Referenced by spell-check modules for code correction

#### **FS882-6x4.txt** (and variants: FS882-1x1, FS882-6x4XL, FS882-6x4XL-CHARS, FS882-8x6XL, FS882-8x6XL-CHARS)
- **Location**: `../VPRO_ACCESS/VPro64_forAI/Forms/FS882-*.txt`
- **Purpose**: Main data entry forms with built-in audit sub-forms
- **Compliance Features**:
  - Contains audit trail sub-form (`USysAudit` or `USysAuditxl`)
  - Button: `btnAudit` with caption "Audit"
  - Click event: `DoCmd.OpenForm "USysAudit"`
  - Form-level audit trail tracking via `AuditTrail Me` procedure
  - Validates data entry through form events

### B. Related Validation Forms

- **USysTableOfLists.txt** - Defines which fields require validation and their list sources
- **USysEnv.txt** - Environmental data table form with list validation
- **USysVeg*.txt** - Vegetation data entry forms with code checking

---

## 2. VBA MODULES WITH COMPLIANCE LOGIC

### A. Audit Trail Module

#### **V7mdlAudit.txt**
- **Location**: `../VPRO_ACCESS/VPro64_forAI/Modules/V7mdlAudit.txt`
- **Core Functions**:
  - `LogVProOff()` - Logs application exit with timestamp
  - `LogVProOn()` - Logs application launch
  - `LogProjectIn()` - Logs project opening with version checking
  - `LogNewProject(ProjectName)` - Logs new project creation
- **Audit Fields Captured**:
  - Project name
  - Username
  - timestamp (`EditWhen`)
  - Table name affected
  - Before/After values
  - Restore flag status
- **Version Tracking**:
  - Compares `ProjectVersion` vs `AllSpecsVersion`
  - Compares `ProjectVersionTableOfLists` vs `TableOfListsVersion`
  - Auto-notifications for spec/list table updates

### B. Validation Modules

#### **V7mdlReportsValidateEnvData.txt**
- **Location**: `../VPRO_ACCESS/VPro64_forAI/Modules/V7mdlReportsValidateEnvData.txt`
- **Public Sub**: `ValidateEnvData()`
- **Logic Flow**:
  1. Creates Excel workbook for reporting
  2. Queries `USysTableOfLists` for fields with `Validate = Yes`
  3. For each validated field, calls `ReportData(ListName, FieldToValidate)`
  4. Outputs violations to Excel columns (PlotNumber vs FieldToValidate)
- **Validation Rule**:
  ```sql
  WHERE USysEnv.[FieldName] IS NOT NULL 
    AND USysEnv.[FieldName] <> '' 
    AND qryTableOfLists.Item IS NULL
  ```
  - i.e., field value must exist in the corresponding list table item
- **Key Procedure**: `ReportData(ListName, FieldToValidate)`
  - Creates temporary query `qryTableOfLists`
  - Performs LEFT JOIN to find non-matching values
  - Formats output in Excel spreadsheet
- **Metadata Source**: Fields marked with `ValidateLoops` indicate multi-instance fields (e.g., `MoistureRegime1`, `MoistureRegime2`)

#### **V7mdlReportValidation.txt**
- **Location**: `../VPRO_ACCESS/VPro64_forAI/Modules/V7mdlReportValidation.txt`
- **Public Function**: `ValidateData()`
- **Advanced Validation Features**:
  - References `USysValidateData` form controls (e.g., `optSMR` option button)
  - Function signature: `ValidateFieldWithPick(FieldName, CodeField, TableName, ListName)`
  - Validates moisture regime (`MoistureRegime`, `MoistureRegimeCode`)
  - Supports multiple validation loops
- **Hierarchy Integrity Checks**:
  - `Report4SuUnitsWoHierarchyUnits()` - Finds site units not in hierarchy
  - `Report4HierarchyUnitsWoSuUnits()` - Finds hierarchy nodes without site units
  - Checks Level 11 hierarchy units for matching site units
- **Data Integrity Functions**:
  - `FixOne2ManyCheck()` - Removes orphaned records in vegetation, mineral, humus, other, and audit tables
  - `One2ManyCheck()` - Reports orphaned records and exports to Excel
  - Uses LEFT JOIN to find plot numbers in child tables with no matching env table record

#### **V7mdlReportsValidateVegCodes.txt**
- Validates vegetation code standards
- Cross-references species codes with SppList
- Spell-check integration for code correction

### C. Code Checking & Spell-Check Modules

#### **V7mdlSpellCheckSppCodes.txt** & **V7mdlSpellCheck2020.txt**
- Interacts with `USysCodeCheck` form
- Validates species codes against USysTableOfLists
- Creates temporary query `qryCodeCheckBadCodeList` for invalid codes
- Supports bulk corrections via "Change All" button
- Maintains code fix history

---

## 3. DATABASE TABLES SUPPORTING COMPLIANCE

### A. Audit Trail Table

#### **Sample_Audit Table**
- **Location**: `../VPRO_ACCESS/VPro64_forAI/Tables_Def/Sample_Audit_CreateSQL.txt`
- **Full Schema**:
  ```sql
  CREATE TABLE [Sample_Audit] (
    [Project] TEXT(100) DEFAULT '',
    [User] TEXT(100) DEFAULT '',
    [PlotNumber] TEXT(7) DEFAULT '',
    [Table] TEXT(50) DEFAULT '',
    [EditField] TEXT(100) DEFAULT '',
    [EditWhen] DATETIME DEFAULT,
    [BeforeEdit] MEMO DEFAULT '',
    [AfterEdit] MEMO DEFAULT '',
    [Restore] BIT DEFAULT 0,
    [Flag] BIT DEFAULT 0,
    [ID] LONG DEFAULT 0
  );
  
  CREATE INDEX [EditWhen] ON [Sample_Audit] ([EditWhen]);
  CREATE INDEX [ID] ON [Sample_Audit] ([ID]);
  ```
- **Field Descriptions**:
  - `Project`: Project identifier (e.g., "BEC2020")
  - `User`: Username of person making edit
  - `PlotNumber`: Sample plot affected (7-char text)
  - `Table`: Table name (values: "On", "Off", "Open", "NewProject", table names, "USysAllSpecs", "USysTableOfLists")
  - `EditField`: Specific field modified
  - `EditWhen`: Timestamp of modification (indexed for performance)
  - `BeforeEdit`: Previous value (MEMO for large content)
  - `AfterEdit`: New value (MEMO for large content)
  - `Restore`: Bit flag indicating if value can be restored
  - `Flag`: Bit flag for administrative marking
  - `ID`: Unique record identifier (indexed)

- **Query**: `UsysAuditTrail`
  - Selects all fields from `Sample_Audit`
  - Typically filtered by current project and plot number

### B. Validation Metadata Table

#### **USysTableOfLists**
- **Purpose**: Master list of valid codes for all fields
- **Key Fields for Compliance**:
  - `ListName`: Name of the list (e.g., "MoistureRegime", "SppList")
  - `Item`: Valid code value
  - `FieldUsedIn`: Field name where this list applies (supports multiple instances)
  - `Validate`: Yes/No flag indicating if field requires validation
  - `ValidateLoops`: Integer 0-N indicating number of repeated field instances
- **Example Validation Rule**:
  - `MoistureRegime` list contains valid codes: "Wet", "Moist", "Fresh", "Dry"
  - Field `MoistureRegime1`, `MoistureRegime2`, `MoistureRegime3` in Sample_Env all validate against this list

---

## 4. SHINY MIGRATION - COMPLIANCE MODULES

### A. Core Compliance Logic

#### **R/logic_compliance.R**
- **Location**: `/R/logic_compliance.R`
- **Core Functions** (Validation Suite):

1. **`check_required_fields(con, project_id = NULL)`**
   - Tables: `Sample_Env`
   - Required fields: `plotnumber`, `projectid`, `zone`, `subzone`
   - Rule: Fields must not be `NA` or empty string
   - Returns: `rule="required"`, plotnumber, details

2. **`check_species_fk(con, project_id = NULL)`**
   - Tables: `Sample_Veg` vs `lists.SppList`
   - Join field: `species` (column name variant: `spp_code`, `species_code`)
   - Rule: All species must exist in SppList valid codes
   - Returns: `rule="fk_species"`, invalid species codes

3. **`check_zone_fk(con, project_id = NULL)`**
   - Tables: `Sample_Env` vs `lists.USysZoneList`
   - Fields: `zone`, `subzone`
   - Rules:
     - Zone codes must be in USysZoneList
     - Subzone codes must be in USysZoneList
     - Zone/subzone pairs must be valid combinations
   - Returns: `rule="fk_zone"`, `rule="fk_subzone"`, `rule="fk_zone_subzone"`

4. **`check_duplicate_plots(con, project_id = NULL)`**
   - Tables: `Sample_Env`
   - Rule: `plotnumber` must be unique within project
   - SQL: `GROUP BY plotnumber, projectid HAVING COUNT(*) > 1`
   - Returns: `rule="dup_plot"`

5. **`check_duplicate_veg(con, project_id = NULL)`**
   - Tables: `vw_USysAllVeg`
   - Rule: `plotnumber`/`species`/`layer` triplet must be unique
   - Returns: `rule="dup_veg"`

6. **`check_coord_ranges(con, project_id = NULL)`**
   - Tables: `Sample_Env`
   - Fields: `latitude`, `longitude`, `elevation`
   - Validation Ranges:
     - Latitude: 48° to 60°N (BC bounds)
     - Longitude: -140° to -114°W (BC bounds)
     - Elevation: 0 to 4000 meters
   - Returns: `rule="range_lat"`, `rule="range_lon"`, `rule="range_elev"`

7. **`check_slope_aspect_ranges(con, project_id = NULL)`**
   - Tables: `Sample_Env`
   - Fields: `slopegradient`, `aspect`
   - Ranges:
     - Slope: 0% to 100%
     - Aspect: 0° to 360°
   - Returns: `rule="range_slope"`, `rule="range_aspect"`

8. **`check_non_negative_fields(con, project_id = NULL)`**
   - Tables: `Sample_Env`
   - Fields: `rootrestrictingdepth`, `rootingdepth`, `seepagedepth`, `sv_soildepth`, `sv_gleyingmottlingcm`, `sv_watertablecm`, `sv_ahorizondepth`, `activelayerdepth`
   - Rule: All depth fields must be >= 0
   - Returns: `rule="range_nonneg_*fieldname*"`

9. **`check_cover_ranges(con, project_id = NULL)`**
   - Tables: `vw_USysAllVeg`
   - Fields: `cover_value`, `cover`, `Cover`
   - Rule: Cover must be 0-100 (percentage)
   - Returns: `rule="range_cover"`

10. **`check_cover_codes(con, project_id = NULL)`**
    - Tables: `vw_USysAllVeg`
    - Rule: Cover values must be numeric (0-100) OR allowed codes: "+", "r", "p"
    - Returns: `rule="code_cover"`

11. **`check_table_list_values(con, project_id = NULL)`**
    - Cross-reference: `Sample_Env` fields vs `lists.USysTableOfLists`
    - Rule: All values in list-validated fields must exist in USysTableOfLists items
    - Returns: `rule="fk_list_*fieldname*"`, invalid list values

12. **`run_compliance_checks(con, project_id = NULL)` - MAIN ORCHESTRATOR**
    - Calls all 11 validation functions
    - Aggregates results
    - **Returns List**:
      - `passed`: Logical (TRUE if all checks pass)
      - `summary_tibble`: Data frame with `rule` and `count` columns
      - `detail_tibble`: Data frame with columns:
        - `rule`: Validation rule name
        - `table`: Target table
        - `column`: Field name
        - `plotnumber`: Affected plot
        - `details`: Human-readable error message

#### **R/logic_validation.R**
- **Location**: `/R/logic_validation.R`
- **Purpose**: Field-level validation utilities for submission
- **Functions**:
  - `validate_plot_number(plot_number)` - Must be non-empty text
  - `validate_project_id(project_id)` - Must be positive integer
  - `validate_veg_sample_row(row, con, reference_source)` - Full vegetation row validation
  - Validates: cover, height, species, layer, metrics (veg_id, ll, af, dc, ut, vi, pv, pg, ffa), flags
- **Metadata Sources**: PostgreSQL or DuckDB reference tables

#### **R/logic_audit.R**
- **Location**: `/R/logic_audit.R`
- **Purpose**: Audit trail management
- **Table**: `user_db.main.USysAuditTrail` (DuckDB qualified)
- **Functions**:
  - `parse_qualified_table(name)` - Parse 3-part table names (catalog.schema.table)
  - `table_exists_qualified(con, name)` - Check table existence with catalog.schema
  - `quote_ident(name)` - Properly quote identifiers
  - `get_audit_table_fields(con)` - Retrieve audit table columns
  - `resolve_audit_column(con, candidates)` - Match column names (case-insensitive)

---

## 5. COMPLIANCE-RELATED QUERIES

### A. Query Files

#### **UsysAuditTrail.txt**
- **Location**: `../VPRO_ACCESS/VPro64_forAI/Queries/UsysAuditTrail.txt`
- **SQL**: `SELECT DISTINCTROW [Sample_Audit].* FROM Sample_Audit ORDER BY EditWhen`
- **Purpose**: Base query for audit trail display with chronological order

---

## 6. COMPLIANCE WORKFLOW DIAGRAM

```
┌─────────────────────────────────────────────────────────────┐
│           USER DATA ENTRY (FS882 Forms)                     │
└───────────────────┬─────────────────────────────────────────┘
                    │
                    ▼
        ┌───────────────────────┐
        │  Real-Time Events    │
        │  - BeforeUpdate      │
        │  - AfterUpdate       │
        │  - OnChange          │
        └───────────┬───────────┘
                    │
        ┌───────────▼────────────────┐
        │   AuditTrail Procedure     │
        │   Logs: Before/After/User  │
        │   Tables: Sample_Audit     │
        └───────────┬────────────────┘
                    │
                    ▼
        ┌───────────────────────┐
        │  Field Validation     │
        │  (Form-Level)         │
        │  - List Checks        │
        │  - Required Fields    │
        └───────────┬───────────┘
                    │
         NO ERROR   │  ERROR
        ┌───────────▼──────────┐
        │   Allow Update?      │
        └───────────┬──────────┘
                    │
        ┌───────────▼──────────┐
        │  Event: Audit_Click  │
        │  Opens: USysAudit    │
        │  Shows: Edit History │
        └──────────────────────┘

Separate Path: USysValidateData Form
└─ Triggered from Ribbon Menu
   └─ Reads: USysTableOfLists (Validate = Yes fields)
      └─ For each field with ValidateLoops:
         └─ Compares Sample_Env values vs USysTableOfLists.Item
            └─ Exports violations to Excel
               └─ Files > Projects > Tools > Validate Data menu
```

---

## 7. COMPLIANCE DATA FLOW TO SHINY

```
Access Database (Legacy)
├── Sample_Audit table
├── USysTableOfLists (validation metadata)
├── Sample_Env (environmental data)
├── Sample_Veg (vegetation data)
└── Validation Forms (USysValidateData, USysAudit)
         │
         ├─ Manual migration: Data imported via DuckDB
         │
Shiny R Application
├── R/logic_compliance.R (11 automated checks)
├── R/logic_validation.R (field-level validation)
├── R/logic_audit.R (audit trail helpers)
│
├── Data Storage
│   ├── DuckDB local: vpro.duckdb, vpro_user.duckdb
│   ├── PostgreSQL remote: BECMaster (cloud)
│   └── Staging: Compliance checks before upload
│
└── UI Modules
    ├── mod_admin_audit.R (audit trail viewer)
    ├── mod_import.R (validates on import)
    ├── mod_merge.R (validates before merge)
    └── mod_reporting.R (validation reports)
```

---

## 8. KEY COMPLIANCE-RELATED FUNCTIONS IN RIBBON MENU

### Access Ribbon Commands
Located in: `../VPRO_ACCESS/VPro64_forAI/Modules/V7mdlRibbonOnAction.txt`

```
Menu Command: "Tools > Validate Data"
    └─ Handler: V7mdlRibbonOnAction.txt line 197
       └─ Action: DoCmd.OpenForm "USysValidateData"
          └─ Form: USysValidateData
             └─ Function: ValidateEnvData() [V7mdlReportsValidateEnvData.txt]
                └─ Output: Excel workbook with violations
```

### Audit Access
Located in: Main data entry forms (FS882-* forms)

```
Button: btnAudit (Caption: "Audit")
    └─ Click Event: Private Sub btnAudit_Click()
       └─ Action: DoCmd.OpenForm "USysAudit"
          └─ Form: USysAudit.txt
             └─ Record Source: UsysAuditTrail query
                └─ Displays: Edit history for current plot
```

---

## 9. COMPLIANCE-RELATED CONFIGURATION SETTINGS

### Registry Settings (clsVProReg.txt)
- `AuditStrength` property
  - Stored: HKCU\Software\VPro\Audit\AuditStrength
  - Default: 1 (basic audit enabled)
  
- `DoUpdateCheck` property
  - Stored: HKCU\Software\VPro\UpdateOptions\DoUpdateCheck
  - Controls version checking behavior

---

## 10. RELATIONSHIP BETWEEN COMPLIANCE AND OTHER FEATURES

### Overlap with Auditing
- Audit trails (`Sample_Audit`) record WHAT changed
- Compliance checks validate IF changes are valid
- Together they provide both governance and history

### Overlap with Validation
- Input validation (form level) prevents invalid entries
- Compliance checks (database level) catch issues that slip through
- Both use same reference tables (USysTableOfLists)

### Overlap with Merge/Sync
- Merge requests check compliance before acceptance
- `compliance_report` field in staging tables
- Upload operations run compliance checks first

### Overlap with Reporting
- Compliance status included in QC reports
- Validation reports exported to Excel
- Raw compliance data available in audit trail

---

## 11. MISSING/DEFERRED DEPENDENCIES FOR SHINY PORT

### Dependencies Not Yet Ported
1. **Form-level validation events** - Access forms use GotFocus/BeforeUpdate events
   - Shiny equivalent: `observeEvent()` and `reactiveVal()` 
   - Status: Placeholder created in modules, needs wiring

2. **Excel export of validation reports** - Currently done via Excel COM automation
   - Shiny equivalent: `openxlsx` package
   - Status: Basic export ready, formatting needs work

3. **Spell-check UI (USysCodeCheck form)** - Interactive code correction dialog
   - Shiny equivalent: custom modal with list matching
   - Status: Not yet implemented

4. **Hierarchy validation** - SU vs Hierarchy consistency checks
   - Status: Logic available but not integrated into UI

5. **One-to-many fix automation** - FixOne2ManyCheck recursive delete
   - Status: Implemented as utility function, needs careful UI wrapper

---

## 12. SUMMARY TABLE: All Compliance Components

| Component | Type | Location | Key Function | Status |
|-----------|------|----------|--------------|--------|
| Sample_Audit | Table | Tables_Def/ | Audit trail storage | ✓ Active |
| USysAudit | Form | Forms/ | Audit trail viewer | ✓ Ported |
| USysValidateData | Form | Forms/ | Data validation UI | ⚠ Partial |
| USysCodeCheck | Form | Forms/ | Code correction dialog | ✘ Not ported |
| V7mdlAudit | Module | Modules/ | Audit logging functions | ✓ Ported |
| V7mdlReportValidation | Module | Modules/ | Validation rules | ✓ Ported (partial) |
| V7mdlReportsValidateEnvData | Module | Modules/ | Env data validation | ✓ Ported |
| logic_compliance.R | R Module | R/ | Automated compliance checks | ✓ Implemented |
| logic_validation.R | R Module | R/ | Field-level validation | ✓ Implemented |
| logic_audit.R | R Module | R/ | Audit trail helpers | ✓ Implemented |
| UsysAuditTrail | Query | Queries/ | Audit data retrieval | ✓ Active |
| USysTableOfLists | Table | (core) | Validation metadata | ✓ Active |

---

## 13. COMPLIANCE RULE REFERENCE

### List-Based Validations (Field → USysTableOfLists)
- `MoistureRegime` → Valid moisture codes
- `Species` → SppList valid species codes
- `Zone` → USysZoneList valid zone codes
- `SiteUnit` → Hierarchy valid unit names
- And 50+ other list-validated fields

### Range-Based Validations
- Latitude: 48°-60°N
- Longitude: -140° to -114°W
- Elevation: 0-4000m
- Slope: 0%-100%
- Aspect: 0°-360°
- Cover: 0%-100%
- All depth fields: >= 0

### Referential Integrity
- Every plot in Veg/Mineral/Humus/Other tables must exist in Env
- Every species must be in SppList
- Every zone/subzone pair must be valid
- Every hierarchy unit must have site unit record

### Uniqueness Constraints
- PlotNumber unique within project
- Species/Layer unique per plot
- Code values unique within list

---

## 14. FILE PATH REFERENCE

```
../VPRO_ACCESS/VPro64_forAI/
├── Forms/
│   ├── USysValidateData.txt          [Data validation UI]
│   ├── USysAudit.txt                 [Audit viewer]
│   ├── USysCodeCheck.txt             [Code correction]
│   ├── FS882-*.txt (6 variants)      [Entry forms with audit]
│   └── [50+ other forms]
│
├── Modules/
│   ├── V7mdlAudit.txt                [Audit logging]
│   ├── V7mdlReportValidation.txt     [Validation rules]
│   ├── V7mdlReportsValidateEnvData.txt [Env validation]
│   ├── V7mdlSpellCheck*.txt (3 files) [Code checking]
│   ├── V7mdlRibbonOnAction.txt       [Menu commands]
│   └── [100+ other modules]
│
├── Queries/
│   └── UsysAuditTrail.txt            [Audit query]
│
└── Tables_Def/
    └── Sample_Audit_CreateSQL.txt    [Audit table schema]

VPRO Shiny (R/):
├── logic_compliance.R                 [Automated checks]
├── logic_validation.R                 [Field validation]
├── logic_audit.R                      [Audit helpers]
├── mod_admin_audit.R                  [Audit UI module]
├── mod_import.R                       [Import validation]
├── mod_merge.R                        [Merge validation]
└── [20+ other modules]
```

---

## 15. NEXT STEPS FOR FULL COMPLIANCE MIGRATION

### Phase 1: Core (✓ Complete)
- [x] Audit table schema and logging
- [x] Compliance check algorithms
- [x] Validation metadata structure

### Phase 2: UI Integration (⚠ In Progress)
- [ ] Audit viewer UI (mod_admin_audit.R)
- [ ] Validation report generation
- [ ] Code correction UI (modal dialog)
- [ ] Compliance dashboard/summary

### Phase 3: Workflow (Pending)
- [ ] Trigger validation before upload/merge
- [ ] Block invalid submissions
- [ ] Bulk fix operations (orphaned records, code corrections)
- [ ] Compliance report exports

### Phase 4: Admin Tools (Pending)
- [ ] Validation rule editor
- [ ] Audit trail search/filter
- [ ] Compliance analytics

---

**Document Generated**: March 8, 2026  
**Access Source**: VPro64_forAI database  
**Shiny Target**: Compliance validation system  
**Porting Status**: 60% complete (core logic done, UI in progress)
