# FORM_IMPL_SPEC_USysAudit

## 1) Form Summary
- Source form file: `VPRO_ACCESS/VPro64_forAI/Forms/USysAudit.txt`
- Form name: `USysAudit`
- Caption: `VPro Data History`
- RecordSource: `SELECT USysAuditTrail.* FROM USysAuditTrail WHERE (((Project)=currproject()) AND ((PlotNumber)='108050'));`
- Filter: `0`
- OrderBy: (none)
- FilterOnLoad: `0`
- OrderByOn: (none)

## 2) Parent-Child UI Tree

- Form `Form_2` caption="VPro Data History" sources=RecordSource,FilterOnLoad events=OnLoad
  - Label `Label_12`
  - CommandButton `CommandButton_13`
  - OptionButton `OptionButton_14`
  - CheckBox `CheckBox_15`
  - OptionGroup `OptionGroup_16`
  - TextBox `TextBox_17`
  - ComboBox `ComboBox_18`
  - FormHeader `FormHeader`
    - Label `Label16` caption="Date/Time"
    - Label `Label17` caption="Plot"
    - Label `Label18` caption="Field"
    - Label `Label19` caption="Value Before Edit"
    - Label `Label23` caption="Table"
    - Label `Label27` caption="Value After Edit"
    - Label `Label30` caption="Flag"
    - Label `Label32` caption="User"
    - Label `Label34` caption="RecID"
  - Section `Detail`
    - TextBox `EditWhen` sources=ControlSource
    - TextBox `BeforeEdit` sources=ControlSource
    - TextBox `PlotNumber` sources=ControlSource
    - TextBox `EditField` sources=ControlSource
    - TextBox `Table` sources=ControlSource
    - TextBox `AfterEdit` sources=ControlSource
    - CheckBox `Restore` sources=ControlSource
    - TextBox `User` sources=ControlSource
    - TextBox `ID` sources=ControlSource
  - FormFooter `FormFooter`
    - OptionGroup `optAuditStrength` events=BeforeUpdate
      - Label `Label38` caption="Audit Strength"
      - OptionButton `Option40`
        - Label `Label41` caption="Edit"
      - OptionButton `Option42`
        - Label `Label43` caption="Edit && Add"
      - OptionButton `Option44`
        - Label `Label45` caption="Edit, Add, && Delete"

## 3) Control Source Dependencies
| Control | Type | Source Property | Value |
|---|---|---|---|
| Form_2 | Form | RecordSource | SELECT USysAuditTrail.* FROM USysAuditTrail WHERE (((Project)=currproject()) AND ((PlotNumber)='108050')); |
| Form_2 | Form | FilterOnLoad | 0 |
| EditWhen | TextBox | ControlSource | EditWhen |
| BeforeEdit | TextBox | ControlSource | BeforeEdit |
| PlotNumber | TextBox | ControlSource | PlotNumber |
| EditField | TextBox | ControlSource | EditField |
| Table | TextBox | ControlSource | Table |
| AfterEdit | TextBox | ControlSource | AfterEdit |
| Restore | CheckBox | ControlSource | Restore |
| User | TextBox | ControlSource | User |
| ID | TextBox | ControlSource | ID |

## 4) Event Procedure Mappings
| Control | Type | Event Property | Expected Handler | Local Procedure Found |
|---|---|---|---|---|
| Form_2 | Form | OnLoad | Form_Load | Yes (line 744) |
| optAuditStrength | OptionGroup | BeforeUpdate | optAuditStrength_BeforeUpdate | Yes (line 748) |

## 4b) Event Resolution Rules
- Access event properties with `[Event Procedure]` map by removing the `On` prefix and binding to VBA handlers.
- `BeforeUpdate` -> control scope handler `<ControlName>_BeforeUpdate` ; form scope handler `Form_BeforeUpdate`
- `OnLoad` -> control scope handler `<ControlName>_Load` ; form scope handler `Form_Load`

## 4c) Event-to-Logic Trace
| Control | Event Property | Handler | Local Handler Status | Local Calls | External Calls | Module Definitions |
|---|---|---|---|---|---|---|
| Form_2 | OnLoad | Form_Load | lines 744-746 | None | None | None found |
| optAuditStrength | BeforeUpdate | optAuditStrength_BeforeUpdate | lines 748-754 | None | None | None found |

## 5) VBA Procedure Graph (Form Scope)
### Form_Load (Sub)
- Lines: 744-746
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: optAuditStrength

### optAuditStrength_BeforeUpdate (Sub)
- Lines: 748-754
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: optAuditStrength


## 6) Data + VBA Dependencies
- Data objects inferred from SQL and source properties: AfterEdit, BeforeEdit, EditField, EditWhen, ID, PlotNumber, Restore, Table, User, USysAuditTrail
- Global/module calls should be resolved in `Modules/*.txt` using function/sub names listed above.

## 7) Subforms (Recursive Architecture)
- None

## 8) Reimplementation Guidance
- Recreate this form as a component tree preserving parent-child relationships and absolute layout constraints.
- Implement event handlers by mapping Access event property -> handler naming convention (`<Control>_<Event>` or `Form_<Event>`).
- Port local procedures first; then resolve external calls in Modules to shared services/utilities.
- Treat `RecordSource`, `ControlSource`, `RowSource` and related fields as data-binding contracts.

