# FORM_IMPL_SPEC_USysVegOther

## 1) Form Summary
- Source form file: `VPRO_ACCESS/VPro64_forAI/Forms/USysVegOther.txt`
- Form name: `USysVegOther`
- Caption: (none)
- RecordSource: `USysVegOther`
- Filter: `0`
- OrderBy: (none)
- FilterOnLoad: `0`
- OrderByOn: (none)

## 2) Parent-Child UI Tree

- Form `Form_2` sources=RecordSource,FilterOnLoad
  - Label `Label_7`
  - TextBox `TextBox_8`
  - ComboBox `ComboBox_9`
  - FormHeader `FormHeader`
    - Label `Label4` caption="Species"
    - Label `Label5` caption="LL"
    - Label `Label17` caption="AF"
    - Label `Label18` caption="DC"
    - Label `Label19` caption="UT"
    - Label `Label20` caption="VI"
    - Label `Label21` caption="PV"
    - Label `Label22` caption="PG"
    - Label `Label23` caption="FFA"
    - Label `Label24` caption="Cultural 1"
    - Label `Label25` caption="Other 1"
    - Label `Label31` caption="Other 2"
    - Label `Label32` caption="Cultural 2"
  - Section `Detail`
    - TextBox `PlotNumber` sources=ControlSource
    - TextBox `Species` sources=ControlSource
    - ComboBox `LL` sources=ControlSource,RowSourceType,RowSource
    - ComboBox `DC` sources=ControlSource,RowSourceType,RowSource
    - ComboBox `UT` sources=ControlSource,RowSourceType,RowSource
    - ComboBox `VI` sources=ControlSource,RowSourceType,RowSource
    - ComboBox `PV` sources=ControlSource,RowSourceType,RowSource
    - ComboBox `PG` sources=ControlSource,RowSourceType,RowSource
    - ComboBox `FFA` sources=ControlSource,RowSourceType,RowSource
    - ComboBox `Cultural1` sources=ControlSource,RowSourceType,RowSource
    - ComboBox `Cultural2` sources=ControlSource,RowSourceType,RowSource
    - ComboBox `Other1` sources=ControlSource,RowSourceType,RowSource
    - ComboBox `Other2` sources=ControlSource,RowSourceType,RowSource
    - TextBox `AF` sources=ControlSource
  - FormFooter `FormFooter`

## 3) Control Source Dependencies
| Control | Type | Source Property | Value |
|---|---|---|---|
| Form_2 | Form | RecordSource | USysVegOther |
| Form_2 | Form | FilterOnLoad | 0 |
| PlotNumber | TextBox | ControlSource | PlotNumber |
| Species | TextBox | ControlSource | Species |
| LL | ComboBox | ControlSource | LL |
| LL | ComboBox | RowSourceType | Table/Query |
| LL | ComboBox | RowSource | SELECT USysTableOfLists.Item, USysTableOfLists.ItemDescription FROM USysTableOfLists WHERE (((USysTableOfLists.ListName)="ArborealLichenLoading")) ORDER BY USysTableOfLists.ItemOrder;  |
| DC | ComboBox | ControlSource | DC |
| DC | ComboBox | RowSourceType | Table/Query |
| DC | ComboBox | RowSource | SELECT USysTableOfLists.Item, USysTableOfLists.ItemDescription FROM USysTableOfLists WHERE (((USysTableOfLists.ListName)="DistributionCode")) ORDER BY USysTableOfLists.ItemOrder;  |
| UT | ComboBox | ControlSource | UT |
| UT | ComboBox | RowSourceType | Table/Query |
| UT | ComboBox | RowSource | SELECT USysTableOfLists.Item, USysTableOfLists.ItemDescription FROM USysTableOfLists WHERE (((USysTableOfLists.ListName)="UtilizationCode")) ORDER BY USysTableOfLists.ItemOrder;  |
| VI | ComboBox | ControlSource | VI |
| VI | ComboBox | RowSourceType | Table/Query |
| VI | ComboBox | RowSource | SELECT USysTableOfLists.Item, USysTableOfLists.ItemDescription FROM USysTableOfLists WHERE (((USysTableOfLists.ListName)="VigourCode")) ORDER BY USysTableOfLists.ItemOrder;  |
| PV | ComboBox | ControlSource | PV |
| PV | ComboBox | RowSourceType | Table/Query |
| PV | ComboBox | RowSource | SELECT USysTableOfLists.Item, USysTableOfLists.ItemDescription FROM USysTableOfLists WHERE (((USysTableOfLists.ListName)="phenologyCodeVeg")) ORDER BY USysTableOfLists.ItemOrder;  |
| PG | ComboBox | ControlSource | PG |
| PG | ComboBox | RowSourceType | Table/Query |
| PG | ComboBox | RowSource | SELECT USysTableOfLists.Item, USysTableOfLists.ItemDescription FROM USysTableOfLists WHERE (((USysTableOfLists.ListName)="PhenologyCodeGen")) ORDER BY USysTableOfLists.ItemOrder;  |
| FFA | ComboBox | ControlSource | FFA |
| FFA | ComboBox | RowSourceType | Table/Query |
| FFA | ComboBox | RowSource | SELECT USysTableOfLists.Item, USysTableOfLists.ItemDescription FROM USysTableOfLists WHERE (((USysTableOfLists.ListName)="fruitFlowerAbundance")) ORDER BY USysTableOfLists.ItemOrder;  |
| Cultural1 | ComboBox | ControlSource | Cultural1 |
| Cultural1 | ComboBox | RowSourceType | Table/Query |
| Cultural1 | ComboBox | RowSource | SELECT USysTableOfLists.Item, USysTableOfLists.ItemDescription FROM USysTableOfLists WHERE (((USysTableOfLists.ListName)="cultural1")) ORDER BY USysTableOfLists.ItemOrder;  |
| Cultural2 | ComboBox | ControlSource | Cultural2 |
| Cultural2 | ComboBox | RowSourceType | Table/Query |
| Cultural2 | ComboBox | RowSource | SELECT USysTableOfLists.Item, USysTableOfLists.ItemDescription FROM USysTableOfLists WHERE (((USysTableOfLists.ListName)="cultural2")) ORDER BY USysTableOfLists.ItemOrder;  |
| Other1 | ComboBox | ControlSource | Other1 |
| Other1 | ComboBox | RowSourceType | Table/Query |
| Other1 | ComboBox | RowSource | SELECT USysTableOfLists.Item, USysTableOfLists.ItemDescription FROM USysTableOfLists WHERE (((USysTableOfLists.ListName)="vegOther1")) ORDER BY USysTableOfLists.ItemOrder;  |
| Other2 | ComboBox | ControlSource | Other2 |
| Other2 | ComboBox | RowSourceType | Table/Query |
| Other2 | ComboBox | RowSource | SELECT USysTableOfLists.Item, USysTableOfLists.ItemDescription FROM USysTableOfLists WHERE (((USysTableOfLists.ListName)="vegOther2")) ORDER BY USysTableOfLists.ItemOrder;  |
| AF | TextBox | ControlSource | AF |

## 4) Event Procedure Mappings
| Control | Type | Event Property | Expected Handler | Local Procedure Found |
|---|---|---|---|---|
| (none) | - | - | - | - |

## 4b) Event Resolution Rules
- Access event properties with `[Event Procedure]` map by removing the `On` prefix and binding to VBA handlers.
- No `[Event Procedure]` bindings detected.

## 4c) Event-to-Logic Trace
| Control | Event Property | Handler | Local Handler Status | Local Calls | External Calls | Module Definitions |
|---|---|---|---|---|---|---|
| (none) | - | - | - | - | - | - |

## 5) VBA Procedure Graph (Form Scope)
No local VBA procedures parsed.

## 6) Data + VBA Dependencies
- Data objects inferred from SQL and source properties: AF, Cultural1, Cultural2, DC, FFA, LL, Other1, Other2, PG, PlotNumber, PV, Species, USysTableOfLists, UT, VI
- Global/module calls should be resolved in `Modules/*.txt` using function/sub names listed above.

## 7) Subforms (Recursive Architecture)
- None

## 8) Reimplementation Guidance
- Recreate this form as a component tree preserving parent-child relationships and absolute layout constraints.
- Implement event handlers by mapping Access event property -> handler naming convention (`<Control>_<Event>` or `Form_<Event>`).
- Port local procedures first; then resolve external calls in Modules to shared services/utilities.
- Treat `RecordSource`, `ControlSource`, `RowSource` and related fields as data-binding contracts.

