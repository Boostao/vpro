# FORM_IMPL_SPEC_SoilHumus

## 1) Form Summary
- Source form file: `VPRO_ACCESS/VPro64_forAI/Forms/SoilHumus.txt`
- Form name: `SoilHumus`
- Caption: `SoilHumus`
- RecordSource: `UsysHumus`
- Filter: `0`
- OrderBy: `[UsysHumus].[UpperDepth] DESC, [UsysHumus].[Horizon] DESC`
- FilterOnLoad: `0`
- OrderByOn: `NotDefault`

## 2) Parent-Child UI Tree

- Form `Form_2` caption="SoilHumus" sources=OrderByOn,OrderBy,RecordSource,FilterOnLoad events=OnCurrent,BeforeUpdate,OnGotFocus,OnLostFocus
  - Label `Label_12`
  - OptionButton `OptionButton_13`
  - CheckBox `CheckBox_14`
  - TextBox `TextBox_15`
  - ListBox `ListBox_16`
  - ComboBox `ComboBox_17`
  - FormHeader `FormHeader1`
    - Label `Text8` caption=" Plot"
    - Label `Text10` caption=" Horizon"
    - Label `Text12` caption="Depth"
    - Label `Text14` caption="Structure"
    - Label `Text16` caption="AB"
    - Label `Text18` caption="Roots"
    - Label `Text20` caption=" Comments (consistency, character, fauna, etc.)"
    - Label `Text21` caption="Size"
    - Label `Text22` caption="Fabric"
    - Label `Text38` caption="Von Post"
    - Label `Text40` caption="Fecal AB"
    - Label `Text41` caption="Mycel AB"
    - Label `Label113` caption="pH"
    - Label `Label1844` caption="Up"
    - Label `Label1845` caption="Low"
  - Section `Detail0`
    - TextBox `ID` sources=ControlSource
    - TextBox `PlotNumber` sources=ControlSource
    - TextBox `UpperDepth` sources=ControlSource
    - TextBox `Comment` sources=ControlSource
    - ComboBox `Horizon` sources=ControlSource,RowSourceType,RowSource
    - TextBox `HumusFormpH` sources=ControlSource
    - ComboBox `HumusStructureKind` sources=ControlSource,RowSourceType,RowSource
    - ComboBox `HumusStructureDegree` sources=ControlSource,RowSourceType,RowSource
    - ComboBox `vonPost` sources=ControlSource,RowSourceType,RowSource
    - ComboBox `MycelAbundance` sources=ControlSource,RowSourceType,RowSource
    - ComboBox `FecalAbundance` sources=ControlSource,RowSourceType,RowSource
    - TextBox `LowerDepth` sources=ControlSource
    - TextBox `RootsAbundance` sources=ControlSource
    - TextBox `RootsSize` sources=ControlSource
  - FormFooter `FormFooter2`

## 3) Control Source Dependencies
| Control | Type | Source Property | Value |
|---|---|---|---|
| Form_2 | Form | OrderByOn | NotDefault |
| Form_2 | Form | OrderBy | [UsysHumus].[UpperDepth] DESC, [UsysHumus].[Horizon] DESC |
| Form_2 | Form | RecordSource | UsysHumus |
| Form_2 | Form | FilterOnLoad | 0 |
| ID | TextBox | ControlSource | ID |
| PlotNumber | TextBox | ControlSource | PlotNumber |
| UpperDepth | TextBox | ControlSource | UpperDepth |
| Comment | TextBox | ControlSource | Comment |
| Horizon | ComboBox | ControlSource | Horizon |
| Horizon | ComboBox | RowSourceType | Table/Query |
| Horizon | ComboBox | RowSource | SELECT DISTINCTROW USysTableOfLists.Item, USysTableOfLists.ItemDescription FROM USysTableOfLists WHERE (((USysTableOfLists.ListName)="HumusHorizon")) ORDER BY USysTableOfLists.ItemOrder;  |
| HumusFormpH | TextBox | ControlSource | HumusFormpH |
| HumusStructureKind | ComboBox | ControlSource | HumusStructureKind |
| HumusStructureKind | ComboBox | RowSourceType | Table/Query |
| HumusStructureKind | ComboBox | RowSource | SELECT USysTableOfLists.Item, USysTableOfLists.ItemDescription FROM USysTableOfLists WHERE (((USysTableOfLists.ListName)="HumusStructureKind")) ORDER BY USysTableOfLists.ItemOrder;  |
| HumusStructureDegree | ComboBox | ControlSource | HumusStructureDegree |
| HumusStructureDegree | ComboBox | RowSourceType | Table/Query |
| HumusStructureDegree | ComboBox | RowSource | SELECT USysTableOfLists.Item, USysTableOfLists.ItemDescription FROM USysTableOfLists WHERE (((USysTableOfLists.ListName)="HumusStructureDegree")) ORDER BY USysTableOfLists.ItemOrder;  |
| vonPost | ComboBox | ControlSource | vonPost |
| vonPost | ComboBox | RowSourceType | Table/Query |
| vonPost | ComboBox | RowSource | SELECT USysTableOfLists.Item, USysTableOfLists.ItemDescription FROM USysTableOfLists WHERE (((USysTableOfLists.ListName)="vonPost")) ORDER BY USysTableOfLists.ItemOrder;  |
| MycelAbundance | ComboBox | ControlSource | MycelAbundance |
| MycelAbundance | ComboBox | RowSourceType | Table/Query |
| MycelAbundance | ComboBox | RowSource | SELECT USysTableOfLists.Item, USysTableOfLists.ItemDescription FROM USysTableOfLists WHERE (((USysTableOfLists.ListName)="MycelAbundance")) ORDER BY USysTableOfLists.ItemOrder;  |
| FecalAbundance | ComboBox | ControlSource | FecalAbundance |
| FecalAbundance | ComboBox | RowSourceType | Table/Query |
| FecalAbundance | ComboBox | RowSource | SELECT USysTableOfLists.Item, USysTableOfLists.ItemDescription FROM USysTableOfLists WHERE (((USysTableOfLists.ListName)="MycelAbundance")) ORDER BY USysTableOfLists.ItemOrder;  |
| LowerDepth | TextBox | ControlSource | LowerDepth |
| RootsAbundance | TextBox | ControlSource | RootsAbundance |
| RootsSize | TextBox | ControlSource | RootsSize |

## 4) Event Procedure Mappings
| Control | Type | Event Property | Expected Handler | Local Procedure Found |
|---|---|---|---|---|
| Form_2 | Form | OnCurrent | Form_Current | Yes (line 873) |
| Form_2 | Form | BeforeUpdate | Form_BeforeUpdate | Yes (line 869) |
| Form_2 | Form | OnGotFocus | Form_GotFocus | Yes (line 877) |
| Form_2 | Form | OnLostFocus | Form_LostFocus | Yes (line 881) |

## 4b) Event Resolution Rules
- Access event properties with `[Event Procedure]` map by removing the `On` prefix and binding to VBA handlers.
- `BeforeUpdate` -> control scope handler `<ControlName>_BeforeUpdate` ; form scope handler `Form_BeforeUpdate`
- `OnCurrent` -> control scope handler `<ControlName>_Current` ; form scope handler `Form_Current`
- `OnGotFocus` -> control scope handler `<ControlName>_GotFocus` ; form scope handler `Form_GotFocus`
- `OnLostFocus` -> control scope handler `<ControlName>_LostFocus` ; form scope handler `Form_LostFocus`

## 4c) Event-to-Logic Trace
| Control | Event Property | Handler | Local Handler Status | Local Calls | External Calls | Module Definitions |
|---|---|---|---|---|---|---|
| Form_2 | OnCurrent | Form_Current | lines 873-875 | None | None | None found |
| Form_2 | BeforeUpdate | Form_BeforeUpdate | lines 869-871 | None | None | None found |
| Form_2 | OnGotFocus | Form_GotFocus | lines 877-879 | None | RunEnterKeyActionNR | None found |
| Form_2 | OnLostFocus | Form_LostFocus | lines 881-883 | None | RunEnterKeyActionNF | None found |

## 5) VBA Procedure Graph (Form Scope)
### Form_BeforeUpdate (Sub)
- Lines: 869-871
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: ID

### Form_Current (Sub)
- Lines: 873-875
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: None

### Form_GotFocus (Sub)
- Lines: 877-879
- Local calls: None
- External calls: RunEnterKeyActionNR
- Module definitions: None found in Modules/
- Me.<control> references: None

### Form_LostFocus (Sub)
- Lines: 881-883
- Local calls: None
- External calls: RunEnterKeyActionNF
- Module definitions: None found in Modules/
- Me.<control> references: None


## 6) Data + VBA Dependencies
- Data objects inferred from SQL and source properties: Comment, FecalAbundance, Horizon, HumusFormpH, HumusStructureDegree, HumusStructureKind, ID, LowerDepth, MycelAbundance, PlotNumber, RootsAbundance, RootsSize, UpperDepth, USysTableOfLists, vonPost
- Global/module calls should be resolved in `Modules/*.txt` using function/sub names listed above.

## 7) Subforms (Recursive Architecture)
- None

## 8) Reimplementation Guidance
- Recreate this form as a component tree preserving parent-child relationships and absolute layout constraints.
- Implement event handlers by mapping Access event property -> handler naming convention (`<Control>_<Event>` or `Form_<Event>`).
- Port local procedures first; then resolve external calls in Modules to shared services/utilities.
- Treat `RecordSource`, `ControlSource`, `RowSource` and related fields as data-binding contracts.

