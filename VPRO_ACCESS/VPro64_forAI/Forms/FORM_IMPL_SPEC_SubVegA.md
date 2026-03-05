# FORM_IMPL_SPEC_SubVegA

## 1) Form Summary
- Source form file: `VPRO_ACCESS/VPro64_forAI/Forms/SubVegA.txt`
- Form name: `SubVegA`
- Caption: `VegA`
- RecordSource: `USysVegA`
- Filter: `0`
- OrderBy: `USysVegA.Species`
- FilterOnLoad: `0`
- OrderByOn: `NotDefault`

## 2) Parent-Child UI Tree

- Form `Form_2` caption="VegA" sources=OrderByOn,OrderBy,RecordSource,FilterOnLoad events=OnCurrent,BeforeUpdate,AfterUpdate,OnGotFocus
  - Label `Label_12`
  - CommandButton `CommandButton_13`
  - OptionButton `OptionButton_14`
  - CheckBox `CheckBox_15`
  - TextBox `TextBox_16`
  - ComboBox `ComboBox_17`
  - ToggleButton `ToggleButton_18`
  - FormHeader `FormHeader0`
    - Label `Text14` caption="Plot"
    - Label `lblSpp` caption="Tree/Shrubs"
    - Label `lblA1` caption="A1"
    - Label `lblA2` caption="A2"
    - Label `lblA3` caption="A3"
    - Label `lblA` caption="A"
    - Label `lblB1` caption="B1"
    - Label `lblB2` caption="B2"
    - Label `lblB` caption="B"
    - Label `Label2344` caption="?"
  - Section `Detail0`
    - TextBox `ID` sources=ControlSource
    - TextBox `PlotNumber` sources=ControlSource
    - TextBox `Cover1` sources=ControlSource events=OnGotFocus,OnLostFocus
    - TextBox `Cover2` sources=ControlSource events=OnGotFocus,OnLostFocus
    - TextBox `Cover3` sources=ControlSource events=OnGotFocus,OnLostFocus
    - TextBox `TotalA` sources=ControlSource events=OnGotFocus,OnLostFocus
    - ComboBox `Species` sources=ControlSource,RowSourceType,RowSource events=OnGotFocus,OnLostFocus,OnNotInList
    - TextBox `Cover4` sources=ControlSource events=OnGotFocus,OnLostFocus
    - TextBox `Cover5` sources=ControlSource events=OnGotFocus,OnLostFocus
    - TextBox `TotalB` sources=ControlSource events=OnGotFocus,OnLostFocus
    - TextBox `Collected` sources=ControlSource events=OnClick
  - FormFooter `FormFooter1`

## 3) Control Source Dependencies
| Control | Type | Source Property | Value |
|---|---|---|---|
| Form_2 | Form | OrderByOn | NotDefault |
| Form_2 | Form | OrderBy | USysVegA.Species |
| Form_2 | Form | RecordSource | USysVegA |
| Form_2 | Form | FilterOnLoad | 0 |
| ID | TextBox | ControlSource | ID |
| PlotNumber | TextBox | ControlSource | PlotNumber |
| Cover1 | TextBox | ControlSource | Cover1 |
| Cover2 | TextBox | ControlSource | Cover2 |
| Cover3 | TextBox | ControlSource | cover3 |
| TotalA | TextBox | ControlSource | TotalA |
| Species | ComboBox | ControlSource | Species |
| Species | ComboBox | RowSourceType | Table/Query |
| Species | ComboBox | RowSource | SELECT DISTINCTROW USysAllSpecies.Code, USysAllSpecies.ScientificName, USysAllSpecies.Codetype, USysAllSpecies.Lifeform, USysAllSpecies.EnglishName FROM USysAllSpecies WHERE (((USysAllSpecies.Codetype)='u' Or (USysAllSpecies.Codetype)='x') AND ((USysAllSpecies.Lifeform)=1 Or (USysAllSpecies.Lifeform)=2 Or (USysAllSpecies.Lifeform)=3 Or (USysAllSpecies.Lifeform)=4)) ORDER BY USysAllSpecies.Code; |
| Cover4 | TextBox | ControlSource | Cover4 |
| Cover5 | TextBox | ControlSource | Cover5 |
| TotalB | TextBox | ControlSource | TotalB |
| Collected | TextBox | ControlSource | Collected |

## 4) Event Procedure Mappings
| Control | Type | Event Property | Expected Handler | Local Procedure Found |
|---|---|---|---|---|
| Form_2 | Form | OnCurrent | Form_Current | Yes (line 1184) |
| Form_2 | Form | BeforeUpdate | Form_BeforeUpdate | Yes (line 1178) |
| Form_2 | Form | AfterUpdate | Form_AfterUpdate | Yes (line 1160) |
| Form_2 | Form | OnGotFocus | Form_GotFocus | No local handler |
| Cover1 | TextBox | OnGotFocus | Cover1_GotFocus | Yes (line 1120) |
| Cover1 | TextBox | OnLostFocus | Cover1_LostFocus | Yes (line 1124) |
| Cover2 | TextBox | OnGotFocus | Cover2_GotFocus | Yes (line 1128) |
| Cover2 | TextBox | OnLostFocus | Cover2_LostFocus | Yes (line 1132) |
| Cover3 | TextBox | OnGotFocus | Cover3_GotFocus | Yes (line 1136) |
| Cover3 | TextBox | OnLostFocus | Cover3_LostFocus | Yes (line 1140) |
| TotalA | TextBox | OnGotFocus | TotalA_GotFocus | Yes (line 1259) |
| TotalA | TextBox | OnLostFocus | TotalA_LostFocus | Yes (line 1263) |
| Species | ComboBox | OnGotFocus | Species_GotFocus | Yes (line 1191) |
| Species | ComboBox | OnLostFocus | Species_LostFocus | Yes (line 1196) |
| Species | ComboBox | OnNotInList | Species_NotInList | Yes (line 1200) |
| Cover4 | TextBox | OnGotFocus | Cover4_GotFocus | Yes (line 1144) |
| Cover4 | TextBox | OnLostFocus | Cover4_LostFocus | Yes (line 1148) |
| Cover5 | TextBox | OnGotFocus | Cover5_GotFocus | Yes (line 1152) |
| Cover5 | TextBox | OnLostFocus | Cover5_LostFocus | Yes (line 1156) |
| TotalB | TextBox | OnGotFocus | TotalB_GotFocus | Yes (line 1267) |
| TotalB | TextBox | OnLostFocus | TotalB_LostFocus | Yes (line 1271) |
| Collected | TextBox | OnClick | Collected_Click | Yes (line 1102) |

## 4b) Event Resolution Rules
- Access event properties with `[Event Procedure]` map by removing the `On` prefix and binding to VBA handlers.
- `AfterUpdate` -> control scope handler `<ControlName>_AfterUpdate` ; form scope handler `Form_AfterUpdate`
- `BeforeUpdate` -> control scope handler `<ControlName>_BeforeUpdate` ; form scope handler `Form_BeforeUpdate`
- `OnClick` -> control scope handler `<ControlName>_Click` ; form scope handler `Form_Click`
- `OnCurrent` -> control scope handler `<ControlName>_Current` ; form scope handler `Form_Current`
- `OnGotFocus` -> control scope handler `<ControlName>_GotFocus` ; form scope handler `Form_GotFocus`
- `OnLostFocus` -> control scope handler `<ControlName>_LostFocus` ; form scope handler `Form_LostFocus`
- `OnNotInList` -> control scope handler `<ControlName>_NotInList` ; form scope handler `Form_NotInList`

## 4c) Event-to-Logic Trace
| Control | Event Property | Handler | Local Handler Status | Local Calls | External Calls | Module Definitions |
|---|---|---|---|---|---|---|
| Form_2 | OnCurrent | Form_Current | lines 1184-1189 | None | None | None found |
| Form_2 | BeforeUpdate | Form_BeforeUpdate | lines 1178-1182 | None | None | None found |
| Form_2 | AfterUpdate | Form_AfterUpdate | lines 1160-1176 | None | None | None found |
| Form_2 | OnGotFocus | Form_GotFocus | Missing local handler | None | None | None found |
| Cover1 | OnGotFocus | Cover1_GotFocus | lines 1120-1122 | None | None | None found |
| Cover1 | OnLostFocus | Cover1_LostFocus | lines 1124-1126 | None | None | None found |
| Cover2 | OnGotFocus | Cover2_GotFocus | lines 1128-1130 | None | None | None found |
| Cover2 | OnLostFocus | Cover2_LostFocus | lines 1132-1134 | None | None | None found |
| Cover3 | OnGotFocus | Cover3_GotFocus | lines 1136-1138 | None | None | None found |
| Cover3 | OnLostFocus | Cover3_LostFocus | lines 1140-1142 | None | None | None found |
| TotalA | OnGotFocus | TotalA_GotFocus | lines 1259-1261 | None | None | None found |
| TotalA | OnLostFocus | TotalA_LostFocus | lines 1263-1265 | None | None | None found |
| Species | OnGotFocus | Species_GotFocus | lines 1191-1194 | None | None | None found |
| Species | OnLostFocus | Species_LostFocus | lines 1196-1198 | None | None | None found |
| Species | OnNotInList | Species_NotInList | lines 1200-1257 | None | ProgramName, DLookup | None found |
| Cover4 | OnGotFocus | Cover4_GotFocus | lines 1144-1146 | None | None | None found |
| Cover4 | OnLostFocus | Cover4_LostFocus | lines 1148-1150 | None | None | None found |
| Cover5 | OnGotFocus | Cover5_GotFocus | lines 1152-1154 | None | None | None found |
| Cover5 | OnLostFocus | Cover5_LostFocus | lines 1156-1158 | None | None | None found |
| TotalB | OnGotFocus | TotalB_GotFocus | lines 1267-1269 | None | None | None found |
| TotalB | OnLostFocus | TotalB_LostFocus | lines 1271-1273 | None | None | None found |
| Collected | OnClick | Collected_Click | lines 1102-1118 | None | None | None found |

## 5) VBA Procedure Graph (Form Scope)
### Collected_Click (Sub)
- Lines: 1102-1118
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: Collected

### Cover1_GotFocus (Sub)
- Lines: 1120-1122
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: None

### Cover1_LostFocus (Sub)
- Lines: 1124-1126
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: None

### Cover2_GotFocus (Sub)
- Lines: 1128-1130
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: None

### Cover2_LostFocus (Sub)
- Lines: 1132-1134
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: None

### Cover3_GotFocus (Sub)
- Lines: 1136-1138
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: None

### Cover3_LostFocus (Sub)
- Lines: 1140-1142
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: None

### Cover4_GotFocus (Sub)
- Lines: 1144-1146
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: None

### Cover4_LostFocus (Sub)
- Lines: 1148-1150
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: None

### Cover5_GotFocus (Sub)
- Lines: 1152-1154
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: None

### Cover5_LostFocus (Sub)
- Lines: 1156-1158
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: None

### Form_AfterUpdate (Sub)
- Lines: 1160-1176
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: None

### Form_BeforeUpdate (Sub)
- Lines: 1178-1182
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: ID

### Form_Current (Sub)
- Lines: 1184-1189
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: None

### Species_GotFocus (Sub)
- Lines: 1191-1194
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: None

### Species_LostFocus (Sub)
- Lines: 1196-1198
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: None

### Species_NotInList (Sub)
- Lines: 1200-1257
- Local calls: None
- External calls: ProgramName, DLookup
- Module definitions: None found in Modules/
- Me.<control> references: None

### TotalA_GotFocus (Sub)
- Lines: 1259-1261
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: None

### TotalA_LostFocus (Sub)
- Lines: 1263-1265
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: None

### TotalB_GotFocus (Sub)
- Lines: 1267-1269
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: None

### TotalB_LostFocus (Sub)
- Lines: 1271-1273
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: None


## 6) Data + VBA Dependencies
- Data objects inferred from SQL and source properties: Collected, Cover1, Cover2, cover3, Cover4, Cover5, ID, PlotNumber, Species, TotalA, TotalB, USysAllSpecies
- Global/module calls should be resolved in `Modules/*.txt` using function/sub names listed above.

## 7) Subforms (Recursive Architecture)
- None

## 8) Reimplementation Guidance
- Recreate this form as a component tree preserving parent-child relationships and absolute layout constraints.
- Implement event handlers by mapping Access event property -> handler naming convention (`<Control>_<Event>` or `Form_<Event>`).
- Port local procedures first; then resolve external calls in Modules to shared services/utilities.
- Treat `RecordSource`, `ControlSource`, `RowSource` and related fields as data-binding contracts.

