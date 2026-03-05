# FORM_IMPL_SPEC_SubVegD

## 1) Form Summary
- Source form file: `VPRO_ACCESS/VPro64_forAI/Forms/SubVegD.txt`
- Form name: `SubVegD`
- Caption: `VegD`
- RecordSource: `USysVegD`
- Filter: `0`
- OrderBy: `USysVegD.Species`
- FilterOnLoad: `0`
- OrderByOn: `NotDefault`

## 2) Parent-Child UI Tree

- Form `Form_2` caption="VegD" sources=OrderByOn,OrderBy,RecordSource,FilterOnLoad events=OnCurrent,BeforeUpdate
  - Label `Label_12`
  - CommandButton `CommandButton_13`
  - CheckBox `CheckBox_14`
  - TextBox `TextBox_15`
  - ComboBox `ComboBox_16`
  - ToggleButton `ToggleButton_17`
  - FormHeader `FormHeader0`
    - Label `Text14` caption="Plot"
    - Label `lblSpp` caption="Moss/Lichen"
    - Label `lblD` caption="D"
    - Label `lblD2` caption="Dr/Dw"
    - Label `lblD3` caption="Ep"
    - Label `Label2344` caption="?"
  - Section `Detail0`
    - TextBox `ID` sources=ControlSource
    - TextBox `PlotNumber` sources=ControlSource
    - TextBox `Cover7` sources=ControlSource events=OnGotFocus,OnLostFocus
    - ComboBox `Species` sources=ControlSource,RowSourceType,RowSource events=OnGotFocus,OnLostFocus,OnNotInList
    - TextBox `Cover8` sources=ControlSource events=OnGotFocus,OnLostFocus
    - TextBox `Cover9` sources=ControlSource events=OnGotFocus,OnLostFocus
    - TextBox `Collected` sources=ControlSource events=OnClick
  - FormFooter `FormFooter1`

## 3) Control Source Dependencies
| Control | Type | Source Property | Value |
|---|---|---|---|
| Form_2 | Form | OrderByOn | NotDefault |
| Form_2 | Form | OrderBy | USysVegD.Species |
| Form_2 | Form | RecordSource | USysVegD |
| Form_2 | Form | FilterOnLoad | 0 |
| ID | TextBox | ControlSource | ID |
| PlotNumber | TextBox | ControlSource | PlotNumber |
| Cover7 | TextBox | ControlSource | Cover7 |
| Species | ComboBox | ControlSource | Species |
| Species | ComboBox | RowSourceType | Table/Query |
| Species | ComboBox | RowSource | SELECT DISTINCTROW USysAllSpecies.Code, USysAllSpecies.ScientificName, USysAllSpecies.Codetype, USysAllSpecies.Lifeform, USysAllSpecies.EnglishName FROM USysAllSpecies WHERE (((USysAllSpecies.Codetype)='u' Or (USysAllSpecies.Codetype)='x') AND ((USysAllSpecies.Lifeform)=1 Or (USysAllSpecies.Lifeform)=2 Or (USysAllSpecies.Lifeform)=9 Or (USysAllSpecies.Lifeform)=10 Or (USysAllSpecies.Lifeform)=11)) ORDER BY USysAllSpecies.Code; |
| Cover8 | TextBox | ControlSource | Cover8 |
| Cover9 | TextBox | ControlSource | Cover9 |
| Collected | TextBox | ControlSource | Collected |

## 4) Event Procedure Mappings
| Control | Type | Event Property | Expected Handler | Local Procedure Found |
|---|---|---|---|---|
| Form_2 | Form | OnCurrent | Form_Current | Yes (line 1003) |
| Form_2 | Form | BeforeUpdate | Form_BeforeUpdate | Yes (line 993) |
| Cover7 | TextBox | OnGotFocus | Cover7_GotFocus | Yes (line 969) |
| Cover7 | TextBox | OnLostFocus | Cover7_LostFocus | Yes (line 973) |
| Species | ComboBox | OnGotFocus | Species_GotFocus | Yes (line 1007) |
| Species | ComboBox | OnLostFocus | Species_LostFocus | Yes (line 1011) |
| Species | ComboBox | OnNotInList | Species_NotInList | Yes (line 1015) |
| Cover8 | TextBox | OnGotFocus | Cover8_GotFocus | Yes (line 977) |
| Cover8 | TextBox | OnLostFocus | Cover8_LostFocus | Yes (line 981) |
| Cover9 | TextBox | OnGotFocus | Cover9_GotFocus | Yes (line 985) |
| Cover9 | TextBox | OnLostFocus | Cover9_LostFocus | Yes (line 989) |
| Collected | TextBox | OnClick | Collected_Click | Yes (line 951) |

## 4b) Event Resolution Rules
- Access event properties with `[Event Procedure]` map by removing the `On` prefix and binding to VBA handlers.
- `BeforeUpdate` -> control scope handler `<ControlName>_BeforeUpdate` ; form scope handler `Form_BeforeUpdate`
- `OnClick` -> control scope handler `<ControlName>_Click` ; form scope handler `Form_Click`
- `OnCurrent` -> control scope handler `<ControlName>_Current` ; form scope handler `Form_Current`
- `OnGotFocus` -> control scope handler `<ControlName>_GotFocus` ; form scope handler `Form_GotFocus`
- `OnLostFocus` -> control scope handler `<ControlName>_LostFocus` ; form scope handler `Form_LostFocus`
- `OnNotInList` -> control scope handler `<ControlName>_NotInList` ; form scope handler `Form_NotInList`

## 4c) Event-to-Logic Trace
| Control | Event Property | Handler | Local Handler Status | Local Calls | External Calls | Module Definitions |
|---|---|---|---|---|---|---|
| Form_2 | OnCurrent | Form_Current | lines 1003-1005 | None | None | None found |
| Form_2 | BeforeUpdate | Form_BeforeUpdate | lines 993-1001 | None | None | None found |
| Cover7 | OnGotFocus | Cover7_GotFocus | lines 969-971 | None | None | None found |
| Cover7 | OnLostFocus | Cover7_LostFocus | lines 973-975 | None | None | None found |
| Species | OnGotFocus | Species_GotFocus | lines 1007-1009 | None | None | None found |
| Species | OnLostFocus | Species_LostFocus | lines 1011-1013 | None | None | None found |
| Species | OnNotInList | Species_NotInList | lines 1015-1073 | None | ProgramName, DLookup | None found |
| Cover8 | OnGotFocus | Cover8_GotFocus | lines 977-979 | None | None | None found |
| Cover8 | OnLostFocus | Cover8_LostFocus | lines 981-983 | None | None | None found |
| Cover9 | OnGotFocus | Cover9_GotFocus | lines 985-987 | None | None | None found |
| Cover9 | OnLostFocus | Cover9_LostFocus | lines 989-991 | None | None | None found |
| Collected | OnClick | Collected_Click | lines 951-967 | None | None | None found |

## 5) VBA Procedure Graph (Form Scope)
### Collected_Click (Sub)
- Lines: 951-967
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: Collected

### Cover7_GotFocus (Sub)
- Lines: 969-971
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: None

### Cover7_LostFocus (Sub)
- Lines: 973-975
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: None

### Cover8_GotFocus (Sub)
- Lines: 977-979
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: None

### Cover8_LostFocus (Sub)
- Lines: 981-983
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: None

### Cover9_GotFocus (Sub)
- Lines: 985-987
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: None

### Cover9_LostFocus (Sub)
- Lines: 989-991
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: None

### Form_BeforeUpdate (Sub)
- Lines: 993-1001
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: ID

### Form_Current (Sub)
- Lines: 1003-1005
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: None

### Species_GotFocus (Sub)
- Lines: 1007-1009
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: None

### Species_LostFocus (Sub)
- Lines: 1011-1013
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: None

### Species_NotInList (Sub)
- Lines: 1015-1073
- Local calls: None
- External calls: ProgramName, DLookup
- Module definitions: None found in Modules/
- Me.<control> references: None


## 6) Data + VBA Dependencies
- Data objects inferred from SQL and source properties: Collected, Cover7, Cover8, Cover9, ID, PlotNumber, Species, USysAllSpecies
- Global/module calls should be resolved in `Modules/*.txt` using function/sub names listed above.

## 7) Subforms (Recursive Architecture)
- None

## 8) Reimplementation Guidance
- Recreate this form as a component tree preserving parent-child relationships and absolute layout constraints.
- Implement event handlers by mapping Access event property -> handler naming convention (`<Control>_<Event>` or `Form_<Event>`).
- Port local procedures first; then resolve external calls in Modules to shared services/utilities.
- Treat `RecordSource`, `ControlSource`, `RowSource` and related fields as data-binding contracts.

