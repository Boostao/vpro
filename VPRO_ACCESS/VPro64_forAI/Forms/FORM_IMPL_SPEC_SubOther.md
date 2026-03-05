# FORM_IMPL_SPEC_SubOther

## 1) Form Summary
- Source form file: `VPRO_ACCESS/VPro64_forAI/Forms/SubOther.txt`
- Form name: `SubOther`
- Caption: `UsysOther`
- RecordSource: `UsysOther`
- Filter: `0`
- OrderBy: `UsysOther.DataName`
- FilterOnLoad: `0`
- OrderByOn: `NotDefault`

## 2) Parent-Child UI Tree

- Form `Form_2` caption="UsysOther" sources=OrderByOn,OrderBy,RecordSource,FilterOnLoad events=BeforeUpdate
  - Label `Label_13`
  - Rectangle `Rectangle_14`
  - Line `Line_15`
  - Image `Image_16`
  - CommandButton `CommandButton_17`
  - OptionButton `OptionButton_18`
  - CheckBox `CheckBox_19`
  - OptionGroup `OptionGroup_20`
  - BoundObjectFrame `BoundObjectFrame_21`
  - TextBox `TextBox_22`
  - ListBox `ListBox_23`
  - ComboBox `ComboBox_24`
  - Subform `Subform_25`
  - UnboundObjectFrame `UnboundObjectFrame_26`
  - ToggleButton `ToggleButton_27`
  - Tab `Tab_28`
  - FormHeader `FormHeader`
  - Section `Detail`
    - TextBox `DataName` sources=ControlSource
      - Label `DataName Label` caption="Data Name"
    - TextBox `DataItem` sources=ControlSource
      - Label `DataItem Label` caption="Data Item"
    - TextBox `UserItem1` sources=ControlSource
      - Label `UserItem1 Label` caption="User Item1"
    - TextBox `UserItem2` sources=ControlSource
      - Label `UserItem2 Label` caption="User Item2"
    - TextBox `UserItem3` sources=ControlSource
      - Label `UserItem3 Label` caption="User Item3"
    - CheckBox `UserFlag1` sources=ControlSource
      - Label `Label14` caption="User Flag 1"
    - CheckBox `UserFlag2` sources=ControlSource
      - Label `Label15` caption="User Flag 2"
    - CheckBox `UserFlag3` sources=ControlSource
      - Label `Label16` caption="User Flag 3"
  - FormFooter `FormFooter`

## 3) Control Source Dependencies
| Control | Type | Source Property | Value |
|---|---|---|---|
| Form_2 | Form | OrderByOn | NotDefault |
| Form_2 | Form | OrderBy | UsysOther.DataName |
| Form_2 | Form | RecordSource | UsysOther |
| Form_2 | Form | FilterOnLoad | 0 |
| DataName | TextBox | ControlSource | DataName |
| DataItem | TextBox | ControlSource | DataItem |
| UserItem1 | TextBox | ControlSource | UserItem1 |
| UserItem2 | TextBox | ControlSource | UserItem2 |
| UserItem3 | TextBox | ControlSource | UserItem3 |
| UserFlag1 | CheckBox | ControlSource | UserFlag1 |
| UserFlag2 | CheckBox | ControlSource | UserFlag2 |
| UserFlag3 | CheckBox | ControlSource | UserFlag3 |

## 4) Event Procedure Mappings
| Control | Type | Event Property | Expected Handler | Local Procedure Found |
|---|---|---|---|---|
| Form_2 | Form | BeforeUpdate | Form_BeforeUpdate | Yes (line 524) |

## 4b) Event Resolution Rules
- Access event properties with `[Event Procedure]` map by removing the `On` prefix and binding to VBA handlers.
- `BeforeUpdate` -> control scope handler `<ControlName>_BeforeUpdate` ; form scope handler `Form_BeforeUpdate`

## 4c) Event-to-Logic Trace
| Control | Event Property | Handler | Local Handler Status | Local Calls | External Calls | Module Definitions |
|---|---|---|---|---|---|---|
| Form_2 | BeforeUpdate | Form_BeforeUpdate | lines 524-526 | None | None | None found |

## 5) VBA Procedure Graph (Form Scope)
### Form_BeforeUpdate (Sub)
- Lines: 524-526
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: ID


## 6) Data + VBA Dependencies
- Data objects inferred from SQL and source properties: DataItem, DataName, UserFlag1, UserFlag2, UserFlag3, UserItem1, UserItem2, UserItem3
- Global/module calls should be resolved in `Modules/*.txt` using function/sub names listed above.

## 7) Subforms (Recursive Architecture)
- None

## 8) Reimplementation Guidance
- Recreate this form as a component tree preserving parent-child relationships and absolute layout constraints.
- Implement event handlers by mapping Access event property -> handler naming convention (`<Control>_<Event>` or `Form_<Event>`).
- Port local procedures first; then resolve external calls in Modules to shared services/utilities.
- Treat `RecordSource`, `ControlSource`, `RowSource` and related fields as data-binding contracts.

