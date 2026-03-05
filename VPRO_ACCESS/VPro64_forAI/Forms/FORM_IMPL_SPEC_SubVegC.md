# FORM_IMPL_SPEC_SubVegC

## 1) Form Summary
- Source form file: `VPRO_ACCESS/VPro64_forAI/Forms/SubVegC.txt`
- Form name: `SubVegC`
- Caption: `VegC`
- RecordSource: `USysVegC`
- Filter: `0`
- OrderBy: `[USysVegC].[Species]`
- FilterOnLoad: `0`
- OrderByOn: `NotDefault`

## 2) Parent-Child UI Tree

- Form `Form_2` caption="VegC" sources=OrderByOn,OrderBy,RecordSource,FilterOnLoad events=OnCurrent,BeforeUpdate
  - CommandButton `CommandButton_12`
  - CheckBox `CheckBox_13`
  - TextBox `TextBox_14`
  - ComboBox `ComboBox_15`
  - ToggleButton `ToggleButton_16`
  - FormHeader `FormHeader0`
    - Label `Text14` caption="Plot"
    - Label `lblSpp` caption="Herb"
    - Label `lblC` caption="C"
    - Label `Label2344` caption="?"
  - Section `Detail0`
    - TextBox `ID` sources=ControlSource
    - TextBox `PlotNumber` sources=ControlSource
    - TextBox `Cover6` sources=ControlSource events=OnGotFocus,OnLostFocus
    - ComboBox `Species` sources=ControlSource,RowSourceType,RowSource events=OnGotFocus,OnLostFocus,OnNotInList
    - TextBox `Collected` sources=ControlSource events=OnClick
  - FormFooter `FormFooter1`

## 3) Control Source Dependencies
| Control | Type | Source Property | Value |
|---|---|---|---|
| Form_2 | Form | OrderByOn | NotDefault |
| Form_2 | Form | OrderBy | [USysVegC].[Species] |
| Form_2 | Form | RecordSource | USysVegC |
| Form_2 | Form | FilterOnLoad | 0 |
| ID | TextBox | ControlSource | ID |
| PlotNumber | TextBox | ControlSource | PlotNumber |
| Cover6 | TextBox | ControlSource | Cover6 |
| Species | ComboBox | ControlSource | Species |
| Species | ComboBox | RowSourceType | Table/Query |
| Species | ComboBox | RowSource | SELECT DISTINCTROW USysAllSpecies.Code, USysAllSpecies.ScientificName, USysAllSpecies.Codetype, USysAllSpecies.Lifeform, USysAllSpecies.EnglishName FROM USysAllSpecies WHERE (((USysAllSpecies.Codetype)='u' Or (USysAllSpecies.Codetype)='x') AND ((USysAllSpecies.Lifeform)=5 Or (USysAllSpecies.Lifeform)=6 Or (USysAllSpecies.Lifeform)=7 Or (USysAllSpecies.Lifeform)=8 Or (USysAllSpecies.Lifeform)=12)) ORDER BY USysAllSpecies.Code; |
| Collected | TextBox | ControlSource | Collected |

## 4) Event Procedure Mappings
| Control | Type | Event Property | Expected Handler | Local Procedure Found |
|---|---|---|---|---|
| Form_2 | Form | OnCurrent | Form_Current | Yes (line 866) |
| Form_2 | Form | BeforeUpdate | Form_BeforeUpdate | Yes (line 857) |
| Cover6 | TextBox | OnGotFocus | Cover6_GotFocus | Yes (line 849) |
| Cover6 | TextBox | OnLostFocus | Cover6_LostFocus | Yes (line 853) |
| Species | ComboBox | OnGotFocus | Species_GotFocus | Yes (line 870) |
| Species | ComboBox | OnLostFocus | Species_LostFocus | Yes (line 874) |
| Species | ComboBox | OnNotInList | Species_NotInList | Yes (line 879) |
| Collected | TextBox | OnClick | Collected_Click | Yes (line 831) |

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
| Form_2 | OnCurrent | Form_Current | lines 866-868 | None | None | None found |
| Form_2 | BeforeUpdate | Form_BeforeUpdate | lines 857-864 | None | None | None found |
| Cover6 | OnGotFocus | Cover6_GotFocus | lines 849-851 | None | None | None found |
| Cover6 | OnLostFocus | Cover6_LostFocus | lines 853-855 | None | None | None found |
| Species | OnGotFocus | Species_GotFocus | lines 870-872 | None | None | None found |
| Species | OnLostFocus | Species_LostFocus | lines 874-876 | None | None | None found |
| Species | OnNotInList | Species_NotInList | lines 879-937 | None | ProgramName, DLookup | None found |
| Collected | OnClick | Collected_Click | lines 831-847 | None | None | None found |

## 5) VBA Procedure Graph (Form Scope)
### Collected_Click (Sub)
- Lines: 831-847
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: Collected

### Cover6_GotFocus (Sub)
- Lines: 849-851
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: None

### Cover6_LostFocus (Sub)
- Lines: 853-855
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: None

### Form_BeforeUpdate (Sub)
- Lines: 857-864
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: ID

### Form_Current (Sub)
- Lines: 866-868
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: None

### Species_GotFocus (Sub)
- Lines: 870-872
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: None

### Species_LostFocus (Sub)
- Lines: 874-876
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: None

### Species_NotInList (Sub)
- Lines: 879-937
- Local calls: None
- External calls: ProgramName, DLookup
- Module definitions: None found in Modules/
- Me.<control> references: None


## 6) Data + VBA Dependencies
- Data objects inferred from SQL and source properties: Collected, Cover6, ID, PlotNumber, Species, USysAllSpecies
- Global/module calls should be resolved in `Modules/*.txt` using function/sub names listed above.

## 7) Subforms (Recursive Architecture)
- None

## 8) Reimplementation Guidance
- Recreate this form as a component tree preserving parent-child relationships and absolute layout constraints.
- Implement event handlers by mapping Access event property -> handler naming convention (`<Control>_<Event>` or `Form_<Event>`).
- Port local procedures first; then resolve external calls in Modules to shared services/utilities.
- Treat `RecordSource`, `ControlSource`, `RowSource` and related fields as data-binding contracts.

