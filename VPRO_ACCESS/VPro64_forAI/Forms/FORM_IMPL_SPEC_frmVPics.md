# FORM_IMPL_SPEC_frmVPics

## 1) Form Summary
- Source form file: `VPRO_ACCESS/VPro64_forAI/Forms/frmVPics.txt`
- Form name: `frmVPics`
- Caption: (none)
- RecordSource: `tblVPics`
- Filter: `0`
- OrderBy: (none)
- FilterOnLoad: `0`
- OrderByOn: (none)

## 2) Parent-Child UI Tree

- Form `Form_2` sources=RecordSource,FilterOnLoad events=OnCurrent,BeforeInsert
  - Label `Label_12`
  - Image `Image_13`
  - TextBox `TextBox_14`
  - Section `Detail`
    - Image `imgCtl` events=OnDblClick
    - TextBox `PicName` sources=ControlSource
    - TextBox `PicDir` sources=ControlSource

## 3) Control Source Dependencies
| Control | Type | Source Property | Value |
|---|---|---|---|
| Form_2 | Form | RecordSource | tblVPics |
| Form_2 | Form | FilterOnLoad | 0 |
| PicName | TextBox | ControlSource | PicName |
| PicDir | TextBox | ControlSource | PicDir |

## 4) Event Procedure Mappings
| Control | Type | Event Property | Expected Handler | Local Procedure Found |
|---|---|---|---|---|
| Form_2 | Form | OnCurrent | Form_Current | Yes (line 2636) |
| Form_2 | Form | BeforeInsert | Form_BeforeInsert | Yes (line 2632) |
| imgCtl | Image | OnDblClick | imgCtl_DblClick | Yes (line 2706) |

## 4b) Event Resolution Rules
- Access event properties with `[Event Procedure]` map by removing the `On` prefix and binding to VBA handlers.
- `BeforeInsert` -> control scope handler `<ControlName>_BeforeInsert` ; form scope handler `Form_BeforeInsert`
- `OnCurrent` -> control scope handler `<ControlName>_Current` ; form scope handler `Form_Current`
- `OnDblClick` -> control scope handler `<ControlName>_DblClick` ; form scope handler `Form_DblClick`

## 4c) Event-to-Logic Trace
| Control | Event Property | Handler | Local Handler Status | Local Calls | External Calls | Module Definitions |
|---|---|---|---|---|---|---|
| Form_2 | OnCurrent | Form_Current | lines 2636-2680 | None | WHERE, OpenRecordset, IsLoaded, Forms, Chr | None found |
| Form_2 | BeforeInsert | Form_BeforeInsert | lines 2632-2634 | None | None | None found |
| imgCtl | OnDblClick | imgCtl_DblClick | lines 2706-2727 | None | Forms, Chr | None found |

## 5) VBA Procedure Graph (Form Scope)
### Form_BeforeInsert (Sub)
- Lines: 2632-2634
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: PlotNumber

### Form_Current (Sub)
- Lines: 2636-2680
- Local calls: None
- External calls: WHERE, OpenRecordset, IsLoaded, Forms, Chr
- Module definitions: None found in Modules/
- Me.<control> references: PlotNumber, imgCtl, PicName, Repaint

### AddPic (Sub)
- Lines: 2681-2705
- Local calls: None
- External calls: FileDialog, Item, Dir
- Module definitions: None found in Modules/
- Me.<control> references: PlotNumber, PicName, PicDir

### imgCtl_DblClick (Sub)
- Lines: 2706-2727
- Local calls: None
- External calls: Forms, Chr
- Module definitions: None found in Modules/
- Me.<control> references: PicName, imgCtl

### test (Sub)
- Lines: 2729-2733
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: None


## 6) Data + VBA Dependencies
- Data objects inferred from SQL and source properties: PicDir, PicName
- Global/module calls should be resolved in `Modules/*.txt` using function/sub names listed above.

## 7) Subforms (Recursive Architecture)
- None

## 8) Reimplementation Guidance
- Recreate this form as a component tree preserving parent-child relationships and absolute layout constraints.
- Implement event handlers by mapping Access event property -> handler naming convention (`<Control>_<Event>` or `Form_<Event>`).
- Port local procedures first; then resolve external calls in Modules to shared services/utilities.
- Treat `RecordSource`, `ControlSource`, `RowSource` and related fields as data-binding contracts.

