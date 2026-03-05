# FORM_IMPL_SPEC_SoilMineral

## 1) Form Summary
- Source form file: `VPRO_ACCESS/VPro64_forAI/Forms/SoilMineral.txt`
- Form name: `SoilMineral`
- Caption: `SoilMineral`
- RecordSource: `UsysMineral`
- Filter: `0`
- OrderBy: `[UsysMineral].[UpperDepth], [UsysMineral].[Horizon]`
- FilterOnLoad: `0`
- OrderByOn: `NotDefault`

## 2) Parent-Child UI Tree

- Form `Form_2` caption="SoilMineral" sources=OrderByOn,OrderBy,RecordSource,FilterOnLoad events=OnCurrent,BeforeUpdate,OnGotFocus,OnLostFocus
  - Label `Label_12`
  - OptionButton `OptionButton_13`
  - CheckBox `CheckBox_14`
  - TextBox `TextBox_15`
  - ListBox `ListBox_16`
  - ComboBox `ComboBox_17`
  - FormHeader `FormHeader1`
    - Label `Text18` caption=" Texture"
    - Label `Text10` caption=" Horizon"
    - Label `Text12` caption="Depth"
    - Label `Text14` caption=" Colour"
    - Label `Text16` caption=" ASP"
    - Label `Text20` caption="% Coarse Fragments"
    - Label `Text22` caption="C"
    - Label `Text24` caption="S"
    - Label `Text26` caption="Tot."
    - Label `Text28` caption="Roots"
    - Label `Text30` caption="Size"
    - Label `Text32` caption="G"
    - Label `Text33` caption="AB."
    - Label `Text35` caption=" Comments (mottles, clay films, effervesc., etc):"
    - Label `Text58` caption="Structure"
    - Label `Text59` caption="Kind"
    - Label `Text60` caption="Class"
    - Label `Label151` caption="Shape"
    - Label `Label348` caption="pH"
    - Label `Label1844` caption="Up"
    - Label `Label1845` caption="Low"
    - Label `Label4611` caption="+"
  - Section `Detail0`
    - TextBox `PlotNumber` sources=ControlSource
    - TextBox `Horizon` sources=ControlSource
    - TextBox `Colour` sources=ControlSource
    - TextBox `PercentCoarseFragsGravel` sources=ControlSource
    - TextBox `PercentCoarseFragsCobbles` sources=ControlSource
    - TextBox `PercentCoarseFragsStones` sources=ControlSource
    - TextBox `PercentCoarseFragsTotal` sources=ControlSource
    - TextBox `Comments` sources=ControlSource
    - ComboBox `ASP` sources=ControlSource,RowSourceType,RowSource
    - ComboBox `Texture` sources=ControlSource,RowSourceType,RowSource
    - TextBox `PercentCoarseFragsShape` sources=ControlSource
    - TextBox `MineralFormpH` sources=ControlSource
    - ComboBox `MineralStructureClass` sources=ControlSource,RowSourceType,RowSource
    - ComboBox `MineralStructureKind` sources=ControlSource,RowSourceType,RowSource
    - TextBox `UpperDepth` sources=ControlSource
    - TextBox `LowerDepth` sources=ControlSource
    - TextBox `PitDepthLimit` sources=ControlSource
    - TextBox `ID` sources=ControlSource
    - TextBox `RootsAbundance` sources=ControlSource
    - TextBox `RootsSize` sources=ControlSource
  - FormFooter `FormFooter2`

## 3) Control Source Dependencies
| Control | Type | Source Property | Value |
|---|---|---|---|
| Form_2 | Form | OrderByOn | NotDefault |
| Form_2 | Form | OrderBy | [UsysMineral].[UpperDepth], [UsysMineral].[Horizon] |
| Form_2 | Form | RecordSource | UsysMineral |
| Form_2 | Form | FilterOnLoad | 0 |
| PlotNumber | TextBox | ControlSource | PlotNumber |
| Horizon | TextBox | ControlSource | Horizon |
| Colour | TextBox | ControlSource | Colour |
| PercentCoarseFragsGravel | TextBox | ControlSource | PercentCoarseFragsGravel |
| PercentCoarseFragsCobbles | TextBox | ControlSource | PercentCoarseFragsCobbles |
| PercentCoarseFragsStones | TextBox | ControlSource | PercentCoarseFragsStones |
| PercentCoarseFragsTotal | TextBox | ControlSource | PercentCoarseFragsTotal |
| Comments | TextBox | ControlSource | Comments |
| ASP | ComboBox | ControlSource | ASP |
| ASP | ComboBox | RowSourceType | Table/Query |
| ASP | ComboBox | RowSource | SELECT DISTINCTROW USysTableOfLists.Item, USysTableOfLists.ItemDescription FROM USysTableOfLists WHERE (((USysTableOfLists.ListName)="MinSoilAspect")) ORDER BY USysTableOfLists.ItemOrder;  |
| Texture | ComboBox | ControlSource | Texture |
| Texture | ComboBox | RowSourceType | Table/Query |
| Texture | ComboBox | RowSource | SELECT DISTINCTROW USysTableOfLists.Item, USysTableOfLists.ItemDescription FROM USysTableOfLists WHERE (((USysTableOfLists.ListName)="SoilTexture")) ORDER BY USysTableOfLists.ItemOrder;  |
| PercentCoarseFragsShape | TextBox | ControlSource | PercentCoarseFragsShape |
| MineralFormpH | TextBox | ControlSource | MineralFormpH |
| MineralStructureClass | ComboBox | ControlSource | MineralStructureClass |
| MineralStructureClass | ComboBox | RowSourceType | Table/Query |
| MineralStructureClass | ComboBox | RowSource | SELECT DISTINCTROW USysTableOfLists.Item, USysTableOfLists.ItemDescription FROM USysTableOfLists WHERE (((USysTableOfLists.ListName)="MineralStructureClass")) ORDER BY USysTableOfLists.ItemOrder;  |
| MineralStructureKind | ComboBox | ControlSource | MineralStructureKind |
| MineralStructureKind | ComboBox | RowSourceType | Table/Query |
| MineralStructureKind | ComboBox | RowSource | SELECT DISTINCTROW USysTableOfLists.Item, USysTableOfLists.ItemDescription FROM USysTableOfLists WHERE (((USysTableOfLists.ListName)="MineralStructureKind")) ORDER BY USysTableOfLists.ItemOrder;  |
| UpperDepth | TextBox | ControlSource | UpperDepth |
| LowerDepth | TextBox | ControlSource | LowerDepth |
| PitDepthLimit | TextBox | ControlSource | PitDepthLimit |
| ID | TextBox | ControlSource | ID |
| RootsAbundance | TextBox | ControlSource | RootsAbundance |
| RootsSize | TextBox | ControlSource | RootsSize |

## 4) Event Procedure Mappings
| Control | Type | Event Property | Expected Handler | Local Procedure Found |
|---|---|---|---|---|
| Form_2 | Form | OnCurrent | Form_Current | Yes (line 1130) |
| Form_2 | Form | BeforeUpdate | Form_BeforeUpdate | Yes (line 1126) |
| Form_2 | Form | OnGotFocus | Form_GotFocus | Yes (line 1134) |
| Form_2 | Form | OnLostFocus | Form_LostFocus | Yes (line 1138) |

## 4b) Event Resolution Rules
- Access event properties with `[Event Procedure]` map by removing the `On` prefix and binding to VBA handlers.
- `BeforeUpdate` -> control scope handler `<ControlName>_BeforeUpdate` ; form scope handler `Form_BeforeUpdate`
- `OnCurrent` -> control scope handler `<ControlName>_Current` ; form scope handler `Form_Current`
- `OnGotFocus` -> control scope handler `<ControlName>_GotFocus` ; form scope handler `Form_GotFocus`
- `OnLostFocus` -> control scope handler `<ControlName>_LostFocus` ; form scope handler `Form_LostFocus`

## 4c) Event-to-Logic Trace
| Control | Event Property | Handler | Local Handler Status | Local Calls | External Calls | Module Definitions |
|---|---|---|---|---|---|---|
| Form_2 | OnCurrent | Form_Current | lines 1130-1132 | None | None | None found |
| Form_2 | BeforeUpdate | Form_BeforeUpdate | lines 1126-1128 | None | None | None found |
| Form_2 | OnGotFocus | Form_GotFocus | lines 1134-1136 | None | RunEnterKeyActionNR | None found |
| Form_2 | OnLostFocus | Form_LostFocus | lines 1138-1140 | None | RunEnterKeyActionNF | None found |

## 5) VBA Procedure Graph (Form Scope)
### Form_BeforeUpdate (Sub)
- Lines: 1126-1128
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: ID

### Form_Current (Sub)
- Lines: 1130-1132
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: None

### Form_GotFocus (Sub)
- Lines: 1134-1136
- Local calls: None
- External calls: RunEnterKeyActionNR
- Module definitions: None found in Modules/
- Me.<control> references: None

### Form_LostFocus (Sub)
- Lines: 1138-1140
- Local calls: None
- External calls: RunEnterKeyActionNF
- Module definitions: None found in Modules/
- Me.<control> references: None


## 6) Data + VBA Dependencies
- Data objects inferred from SQL and source properties: ASP, Colour, Comments, Horizon, ID, LowerDepth, MineralFormpH, MineralStructureClass, MineralStructureKind, PercentCoarseFragsCobbles, PercentCoarseFragsGravel, PercentCoarseFragsShape, PercentCoarseFragsStones, PercentCoarseFragsTotal, PitDepthLimit, PlotNumber, RootsAbundance, RootsSize, Texture, UpperDepth, USysTableOfLists
- Global/module calls should be resolved in `Modules/*.txt` using function/sub names listed above.

## 7) Subforms (Recursive Architecture)
- None

## 8) Reimplementation Guidance
- Recreate this form as a component tree preserving parent-child relationships and absolute layout constraints.
- Implement event handlers by mapping Access event property -> handler naming convention (`<Control>_<Event>` or `Form_<Event>`).
- Port local procedures first; then resolve external calls in Modules to shared services/utilities.
- Treat `RecordSource`, `ControlSource`, `RowSource` and related fields as data-binding contracts.

