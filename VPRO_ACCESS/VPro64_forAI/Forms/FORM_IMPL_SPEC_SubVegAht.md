# FORM_IMPL_SPEC_SubVegAht

## 1) Form Summary
- Source form file: `VPRO_ACCESS/VPro64_forAI/Forms/SubVegAht.txt`
- Form name: `SubVegAht`
- Caption: `VegA`
- RecordSource: `SELECT UsysVeg.ID, UsysVeg.PlotNumber, UsysVeg.Species, UsysVeg.Cover1, UsysVeg.Height1, UsysVeg.Cover2, UsysVeg.Height2, UsysVeg.Cover3, UsysVeg.Height3, UsysVeg.TotalA, UsysVeg.Cover4, UsysVeg.Height4, UsysVeg.Cover5, UsysVeg.Height5, UsysVeg.TotalB, UsysVeg.Collected FROM UsysVeg WHERE (((UsysVeg.Cover1) Is Not Null)) OR (((UsysVeg.Height1) Is Not Null)) OR (((UsysVeg.Cover2) Is Not Null)) OR (((UsysVeg.Height2) Is Not Null)) OR (((UsysVeg.Cover3) Is Not Null)) OR (((UsysVeg.Height3) Is Not Null)) OR (((UsysVeg.TotalA) Is Not Null)) OR (((UsysVeg.Cover4) Is Not Null)) OR (((UsysVeg.Height4) Is Not Null)) OR (((UsysVeg.Cover5) Is Not Null)) OR (((UsysVeg.Height5) Is Not Null)) OR (((UsysVeg.TotalB) Is Not Null)); `
- Filter: `0`
- OrderBy: (none)
- FilterOnLoad: `0`
- OrderByOn: (none)

## 2) Parent-Child UI Tree

- Form `Form_2` caption="VegA" sources=RecordSource,FilterOnLoad events=OnCurrent,BeforeUpdate,AfterUpdate,OnOpen,OnGotFocus
  - Label `Label_12`
  - CommandButton `CommandButton_13`
  - OptionButton `OptionButton_14`
  - CheckBox `CheckBox_15`
  - TextBox `TextBox_16`
  - ComboBox `ComboBox_17`
  - ToggleButton `ToggleButton_18`
  - FormHeader `FormHeader0`
    - Label `Text14` caption="Plot"
    - Label `lblSpp` caption=" Tree/Shrubs"
    - Label `lblA1` caption="A1"
    - Label `lblA2` caption="A2"
    - Label `lblA3` caption="A3"
    - Label `lblA` caption="A"
    - Label `lblB1` caption="B1"
    - Label `lblB2` caption="B2"
    - Label `lblB` caption="B"
    - Label `Label2344` caption="?"
    - Label `Label2353` caption="%"
    - Label `Label2354` caption="HT"
    - Label `Label2355` caption="%"
    - Label `Label2356` caption="HT"
    - Label `Label2357` caption="%"
    - Label `Label2358` caption="HT"
    - Label `Label2359` caption="%"
    - Label `Label2360` caption="HT"
    - Label `Label2361` caption="%"
    - Label `Label2362` caption="HT"
    - Label `Label2363` caption="%"
    - Label `Label2364` caption="%"
  - Section `Detail0`
    - TextBox `ID` sources=ControlSource
    - TextBox `PlotNumber` sources=ControlSource
    - TextBox `Cover1` sources=ControlSource events=OnGotFocus,OnLostFocus
    - TextBox `Cover2` sources=ControlSource events=OnGotFocus,OnLostFocus
    - TextBox `Cover3` sources=ControlSource events=OnGotFocus,OnLostFocus
    - TextBox `TotalA` sources=ControlSource events=OnGotFocus,OnLostFocus
    - ComboBox `Species` sources=ControlSource,RowSourceType,RowSource events=OnMouseDown,OnGotFocus,OnLostFocus,OnClick,OnNotInList
    - TextBox `Cover4` sources=ControlSource events=OnGotFocus,OnLostFocus
    - TextBox `Cover5` sources=ControlSource events=OnGotFocus,OnLostFocus
    - TextBox `TotalB` sources=ControlSource events=OnGotFocus,OnLostFocus
    - TextBox `Collected` sources=ControlSource events=OnClick
    - TextBox `Height1` sources=ControlSource
    - TextBox `Height2` sources=ControlSource
    - TextBox `Height3` sources=ControlSource
    - TextBox `Height4` sources=ControlSource
    - TextBox `Height5` sources=ControlSource
  - FormFooter `FormFooter1`

## 3) Control Source Dependencies
| Control | Type | Source Property | Value |
|---|---|---|---|
| Form_2 | Form | RecordSource | SELECT UsysVeg.ID, UsysVeg.PlotNumber, UsysVeg.Species, UsysVeg.Cover1, UsysVeg.Height1, UsysVeg.Cover2, UsysVeg.Height2, UsysVeg.Cover3, UsysVeg.Height3, UsysVeg.TotalA, UsysVeg.Cover4, UsysVeg.Height4, UsysVeg.Cover5, UsysVeg.Height5, UsysVeg.TotalB, UsysVeg.Collected FROM UsysVeg WHERE (((UsysVeg.Cover1) Is Not Null)) OR (((UsysVeg.Height1) Is Not Null)) OR (((UsysVeg.Cover2) Is Not Null)) OR (((UsysVeg.Height2) Is Not Null)) OR (((UsysVeg.Cover3) Is Not Null)) OR (((UsysVeg.Height3) Is Not Null)) OR (((UsysVeg.TotalA) Is Not Null)) OR (((UsysVeg.Cover4) Is Not Null)) OR (((UsysVeg.Height4) Is Not Null)) OR (((UsysVeg.Cover5) Is Not Null)) OR (((UsysVeg.Height5) Is Not Null)) OR (((UsysVeg.TotalB) Is Not Null));  |
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
| Height1 | TextBox | ControlSource | Height1 |
| Height2 | TextBox | ControlSource | Height2 |
| Height3 | TextBox | ControlSource | Height3 |
| Height4 | TextBox | ControlSource | Height4 |
| Height5 | TextBox | ControlSource | Height5 |

## 4) Event Procedure Mappings
| Control | Type | Event Property | Expected Handler | Local Procedure Found |
|---|---|---|---|---|
| Form_2 | Form | OnCurrent | Form_Current | Yes (line 1675) |
| Form_2 | Form | BeforeUpdate | Form_BeforeUpdate | Yes (line 1669) |
| Form_2 | Form | AfterUpdate | Form_AfterUpdate | Yes (line 1651) |
| Form_2 | Form | OnOpen | Form_Open | Yes (line 1679) |
| Form_2 | Form | OnGotFocus | Form_GotFocus | No local handler |
| Cover1 | TextBox | OnGotFocus | Cover1_GotFocus | Yes (line 1611) |
| Cover1 | TextBox | OnLostFocus | Cover1_LostFocus | Yes (line 1615) |
| Cover2 | TextBox | OnGotFocus | Cover2_GotFocus | Yes (line 1619) |
| Cover2 | TextBox | OnLostFocus | Cover2_LostFocus | Yes (line 1623) |
| Cover3 | TextBox | OnGotFocus | Cover3_GotFocus | Yes (line 1627) |
| Cover3 | TextBox | OnLostFocus | Cover3_LostFocus | Yes (line 1631) |
| TotalA | TextBox | OnGotFocus | TotalA_GotFocus | Yes (line 1787) |
| TotalA | TextBox | OnLostFocus | TotalA_LostFocus | Yes (line 1791) |
| Species | ComboBox | OnMouseDown | Species_MouseDown | Yes (line 1724) |
| Species | ComboBox | OnGotFocus | Species_GotFocus | Yes (line 1711) |
| Species | ComboBox | OnLostFocus | Species_LostFocus | Yes (line 1720) |
| Species | ComboBox | OnClick | Species_Click | Yes (line 1707) |
| Species | ComboBox | OnNotInList | Species_NotInList | Yes (line 1728) |
| Cover4 | TextBox | OnGotFocus | Cover4_GotFocus | Yes (line 1635) |
| Cover4 | TextBox | OnLostFocus | Cover4_LostFocus | Yes (line 1639) |
| Cover5 | TextBox | OnGotFocus | Cover5_GotFocus | Yes (line 1643) |
| Cover5 | TextBox | OnLostFocus | Cover5_LostFocus | Yes (line 1647) |
| TotalB | TextBox | OnGotFocus | TotalB_GotFocus | Yes (line 1795) |
| TotalB | TextBox | OnLostFocus | TotalB_LostFocus | Yes (line 1799) |
| Collected | TextBox | OnClick | Collected_Click | Yes (line 1593) |

## 4b) Event Resolution Rules
- Access event properties with `[Event Procedure]` map by removing the `On` prefix and binding to VBA handlers.
- `AfterUpdate` -> control scope handler `<ControlName>_AfterUpdate` ; form scope handler `Form_AfterUpdate`
- `BeforeUpdate` -> control scope handler `<ControlName>_BeforeUpdate` ; form scope handler `Form_BeforeUpdate`
- `OnClick` -> control scope handler `<ControlName>_Click` ; form scope handler `Form_Click`
- `OnCurrent` -> control scope handler `<ControlName>_Current` ; form scope handler `Form_Current`
- `OnGotFocus` -> control scope handler `<ControlName>_GotFocus` ; form scope handler `Form_GotFocus`
- `OnLostFocus` -> control scope handler `<ControlName>_LostFocus` ; form scope handler `Form_LostFocus`
- `OnMouseDown` -> control scope handler `<ControlName>_MouseDown` ; form scope handler `Form_MouseDown`
- `OnNotInList` -> control scope handler `<ControlName>_NotInList` ; form scope handler `Form_NotInList`
- `OnOpen` -> control scope handler `<ControlName>_Open` ; form scope handler `Form_Open`

## 4c) Event-to-Logic Trace
| Control | Event Property | Handler | Local Handler Status | Local Calls | External Calls | Module Definitions |
|---|---|---|---|---|---|---|
| Form_2 | OnCurrent | Form_Current | lines 1675-1677 | None | None | None found |
| Form_2 | BeforeUpdate | Form_BeforeUpdate | lines 1669-1673 | None | None | None found |
| Form_2 | AfterUpdate | Form_AfterUpdate | lines 1651-1667 | None | None | None found |
| Form_2 | OnOpen | Form_Open | lines 1679-1705 | None | None | None found |
| Form_2 | OnGotFocus | Form_GotFocus | Missing local handler | None | None | None found |
| Cover1 | OnGotFocus | Cover1_GotFocus | lines 1611-1613 | None | None | None found |
| Cover1 | OnLostFocus | Cover1_LostFocus | lines 1615-1617 | None | None | None found |
| Cover2 | OnGotFocus | Cover2_GotFocus | lines 1619-1621 | None | None | None found |
| Cover2 | OnLostFocus | Cover2_LostFocus | lines 1623-1625 | None | None | None found |
| Cover3 | OnGotFocus | Cover3_GotFocus | lines 1627-1629 | None | None | None found |
| Cover3 | OnLostFocus | Cover3_LostFocus | lines 1631-1633 | None | None | None found |
| TotalA | OnGotFocus | TotalA_GotFocus | lines 1787-1789 | None | None | None found |
| TotalA | OnLostFocus | TotalA_LostFocus | lines 1791-1793 | None | None | None found |
| Species | OnMouseDown | Species_MouseDown | lines 1724-1726 | None | None | None found |
| Species | OnGotFocus | Species_GotFocus | lines 1711-1718 | None | None | None found |
| Species | OnLostFocus | Species_LostFocus | lines 1720-1722 | None | None | None found |
| Species | OnClick | Species_Click | lines 1707-1709 | None | None | None found |
| Species | OnNotInList | Species_NotInList | lines 1728-1785 | None | ProgramName, DLookup | None found |
| Cover4 | OnGotFocus | Cover4_GotFocus | lines 1635-1637 | None | None | None found |
| Cover4 | OnLostFocus | Cover4_LostFocus | lines 1639-1641 | None | None | None found |
| Cover5 | OnGotFocus | Cover5_GotFocus | lines 1643-1645 | None | None | None found |
| Cover5 | OnLostFocus | Cover5_LostFocus | lines 1647-1649 | None | None | None found |
| TotalB | OnGotFocus | TotalB_GotFocus | lines 1795-1797 | None | None | None found |
| TotalB | OnLostFocus | TotalB_LostFocus | lines 1799-1801 | None | None | None found |
| Collected | OnClick | Collected_Click | lines 1593-1609 | None | None | None found |

## 5) VBA Procedure Graph (Form Scope)
### Collected_Click (Sub)
- Lines: 1593-1609
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: Collected

### Cover1_GotFocus (Sub)
- Lines: 1611-1613
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: None

### Cover1_LostFocus (Sub)
- Lines: 1615-1617
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: None

### Cover2_GotFocus (Sub)
- Lines: 1619-1621
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: None

### Cover2_LostFocus (Sub)
- Lines: 1623-1625
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: None

### Cover3_GotFocus (Sub)
- Lines: 1627-1629
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: None

### Cover3_LostFocus (Sub)
- Lines: 1631-1633
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: None

### Cover4_GotFocus (Sub)
- Lines: 1635-1637
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: None

### Cover4_LostFocus (Sub)
- Lines: 1639-1641
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: None

### Cover5_GotFocus (Sub)
- Lines: 1643-1645
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: None

### Cover5_LostFocus (Sub)
- Lines: 1647-1649
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: None

### Form_AfterUpdate (Sub)
- Lines: 1651-1667
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: None

### Form_BeforeUpdate (Sub)
- Lines: 1669-1673
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: ID

### Form_Current (Sub)
- Lines: 1675-1677
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: None

### Form_Open (Sub)
- Lines: 1679-1705
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: OrderBy, lblA1, lblA2, lblA3, lblA, lblB1, lblB2, lblB, Width

### Species_Click (Sub)
- Lines: 1707-1709
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: Parent, Species

### Species_GotFocus (Sub)
- Lines: 1711-1718
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: Species, Parent

### Species_LostFocus (Sub)
- Lines: 1720-1722
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: None

### Species_MouseDown (Sub)
- Lines: 1724-1726
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: Parent, Species

### Species_NotInList (Sub)
- Lines: 1728-1785
- Local calls: None
- External calls: ProgramName, DLookup
- Module definitions: None found in Modules/
- Me.<control> references: None

### TotalA_GotFocus (Sub)
- Lines: 1787-1789
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: None

### TotalA_LostFocus (Sub)
- Lines: 1791-1793
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: None

### TotalB_GotFocus (Sub)
- Lines: 1795-1797
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: None

### TotalB_LostFocus (Sub)
- Lines: 1799-1801
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: None


## 6) Data + VBA Dependencies
- Data objects inferred from SQL and source properties: Collected, Cover1, Cover2, cover3, Cover4, Cover5, Height1, Height2, Height3, Height4, Height5, ID, PlotNumber, Species, TotalA, TotalB, USysAllSpecies, UsysVeg
- Global/module calls should be resolved in `Modules/*.txt` using function/sub names listed above.

## 7) Subforms (Recursive Architecture)
- None

## 8) Reimplementation Guidance
- Recreate this form as a component tree preserving parent-child relationships and absolute layout constraints.
- Implement event handlers by mapping Access event property -> handler naming convention (`<Control>_<Event>` or `Form_<Event>`).
- Port local procedures first; then resolve external calls in Modules to shared services/utilities.
- Treat `RecordSource`, `ControlSource`, `RowSource` and related fields as data-binding contracts.

