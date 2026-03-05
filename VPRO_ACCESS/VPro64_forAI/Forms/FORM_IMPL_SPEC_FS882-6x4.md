# FORM_IMPL_SPEC_FS882-6x4

## 1) Form Summary
- Source form file: `VPRO_ACCESS/VPro64_forAI/Forms/FS882-6x4.txt`
- Form name: `FS882-6x4`
- Caption: `FS882`
- RecordSource: `USysEnv`
- Filter: `([USysEnv].[NutrientRegime] In ("B","C"))`
- OrderBy: `[USysEnv].[RootingDepth] DESC, [USysEnv].[SeepageDepth] DESC, [USysEnv].[PlotNumber]`
- FilterOnLoad: `0`
- OrderByOn: `NotDefault`

## 2) Parent-Child UI Tree

- Form `Form_2` caption="FS882" sources=OrderByOn,Filter,OrderBy,RecordSource,FilterOnLoad events=OnCurrent,BeforeUpdate,OnOpen,OnClose,OnMouseDown,OnLostFocus,OnClick,OnLoad
  - Label `Label_13`
  - Rectangle `Rectangle_14`
  - CommandButton `CommandButton_15`
  - OptionButton `OptionButton_16`
  - CheckBox `CheckBox_17`
  - OptionGroup `OptionGroup_18`
  - TextBox `TextBox_19`
  - ListBox `ListBox_20`
  - ComboBox `ComboBox_21`
  - Subform `Subform_22`
  - CustomControl `CustomControl_23`
  - ToggleButton `ToggleButton_24`
  - Tab `Tab_25`
  - FormHeader `FormHeader`
  - Section `Detail`
    - Tab `tabPages` events=OnChange
      - Page `&Site` caption="&Site"
        - TextBox `PlotNumber` sources=ControlSource events=AfterUpdate,OnMouseUp,OnLostFocus
          - Label `Text35` caption="Plot Number"
        - TextBox `Date` sources=ControlSource
          - Label `Text29` caption="Date"
        - ComboBox `ProjectID` sources=ControlSource,RowSourceType,RowSource events=OnGotFocus,OnLostFocus,OnNotInList
          - Label `lblProjectID` caption="Project ID"
        - TextBox `StartDate` sources=ControlSource
          - Label `Label452` caption="Yr."
        - TextBox `SiteSurveyor` sources=ControlSource
          - Label `Text31` caption="Surveyor"
        - TextBox `FieldNumber` sources=ControlSource
          - Label `Text33` caption="Field No."
        - ComboBox `BECSiteUnit` sources=ControlSource,RowSourceType,RowSource
        - ComboBox `UserSiteUnit` sources=ControlSource,RowSourceType,RowSource
          - Label `Label441` caption="Working Unit"
        - TextBox `Location` sources=ControlSource
          - Label `Text9` caption="General Location"
        - ComboBox `FSRegionDistrict` sources=ControlSource,RowSourceType,RowSource
          - Label `Text203` caption="Forest Region/Dist."
        - TextBox `NtsMapSheet` sources=ControlSource
          - Label `Text13` caption="Map Sheet"
        - TextBox `UTMZone` sources=ControlSource
          - Label `Text184` caption="UTM Zone"
        - TextBox `UTMEasting` sources=ControlSource
          - Label `Text186` caption="Easting"
        - TextBox `UTMNorthing` sources=ControlSource
          - Label `Text188` caption="Northing"
        - TextBox `LocationAccuracy` sources=ControlSource
          - Label `Label358` caption="Accur. (m)"
        - OptionGroup `optCoordMethod2` events=AfterUpdate
          - CheckBox `Check369`
            - Label `Label370` caption="D.d"
          - CheckBox `Check371`
            - Label `Label372` caption="DM.m"
          - CheckBox `Check373`
            - Label `Label375` caption="DMS.s"
        - TextBox `AirPhotoNum` sources=ControlSource
          - Label `Text11` caption="Air Photo No."
        - TextBox `XCoord` sources=ControlSource
          - Label `Text49` caption="X Co-ord."
        - TextBox `YCoord` sources=ControlSource
          - Label `Text51` caption="Y Co-ord"
        - TextBox `LatD2` events=AfterUpdate
        - TextBox `LatD` events=AfterUpdate
          - Label `lblLatD` caption="D"
        - TextBox `LatMD` events=AfterUpdate
          - Label `lblLatMD` caption="M"
        - TextBox `Latitude` sources=ControlSource events=AfterUpdate
          - Label `lblLatitude` caption="Latitude"
        - TextBox `LatM` events=AfterUpdate
          - Label `lblLatM` caption="M"
        - TextBox `LatS` events=AfterUpdate
          - Label `lblLatS` caption="S"
        - TextBox `LonD2` events=AfterUpdate
        - TextBox `LonD` events=AfterUpdate
          - Label `lblLonD` caption="D"
        - TextBox `Longitude` sources=ControlSource events=AfterUpdate
          - Label `lblLongitude` caption="Longitude"
        - TextBox `LonM` events=AfterUpdate
          - Label `lblLonM` caption="M"
        - TextBox `LonMD` events=AfterUpdate
          - Label `lblLonMD` caption="M"
        - TextBox `LonS` events=AfterUpdate
          - Label `lblLonS` caption="S"
        - ComboBox `Ecosection` sources=ControlSource,RowSourceType,RowSource
          - Label `Text98` caption="Ecosection"
        - TextBox `PlotRepresenting` sources=ControlSource
          - Label `Text215` caption="Plot Representing"
        - ComboBox `Zone` sources=ControlSource,RowSourceType,RowSource
          - Label `Text106` caption="Biogeoclimatic Unit"
        - ComboBox `SubZone` sources=RowSourceTypeInt,ControlSource,RowSourceType events=OnGotFocus
        - ComboBox `RealmClass` sources=ControlSource,RowSourceType,RowSource
          - Label `Label120` caption="Realm/Class"
        - ComboBox `TransDistrib` sources=ControlSource,RowSourceType,RowSource
        - TextBox `MapUnit` sources=ControlSource
          - Label `Text67` caption="Map Unit"
        - ComboBox `SiteSeries` sources=RowSourceTypeInt,ControlSource,RowSourceType events=OnEnter
          - Label `Text115` caption="Site Series"
        - ComboBox `MoistureRegime` sources=ControlSource,RowSourceType,RowSource
        - ComboBox `NutrientRegime` sources=ControlSource,RowSourceType,RowSource
        - ComboBox `SuccessionalStatus` sources=ControlSource,RowSourceType,RowSource
          - Label `Text90` caption="Successional Status"
        - ComboBox `StructuralStage` sources=ControlSource,RowSourceType,RowSource
          - Label `Text121` caption="Structural Stage"
        - TextBox `StandAge` sources=ControlSource
          - Label `Label311` caption="Stand Age"
        - TextBox `Photo` sources=ControlSource
        - TextBox `Elevation` sources=ControlSource
          - Label `Text15` caption="Elevation (m)"
        - TextBox `SlopeGradient` sources=ControlSource
          - Label `Text57` caption="Slope (%)"
        - TextBox `Aspect` sources=ControlSource
          - Label `Text59` caption="Aspect"
        - ComboBox `MesoSlopePosition` sources=ControlSource,RowSourceType,RowSource
        - ComboBox `SurfaceShape` sources=ControlSource,RowSourceType,RowSource
        - ComboBox `SurfaceTopographyType` sources=ControlSource,RowSourceType,RowSource
          - Label `Label123` caption="Microtop. type"
        - ComboBox `SurfaceTopographySize` sources=ControlSource,RowSourceType,RowSource
          - Label `Label125` caption="Microtop. size"
        - ComboBox `SiteDisturbance1` sources=ControlSource,RowSourceType,RowSource
          - Label `Text190` caption="Site Disturbance"
        - ComboBox `SiteDisturbance2` sources=ControlSource,RowSourceType,RowSource
        - ComboBox `SiteDisturbance3` sources=ControlSource,RowSourceType,RowSource
        - ComboBox `Exposure1` sources=ControlSource,RowSourceType,RowSource
        - ComboBox `Exposure2` sources=ControlSource,RowSourceType,RowSource
        - CommandButton `btnCopyToUserSU` caption="Copy to Working Unit" events=OnClick
        - CommandButton `btnLoadMetadata` caption="Edit Metadata" events=OnClick
        - ComboBox `SitePlotQuality` sources=ControlSource,RowSourceType,RowSource
          - Label `Label211` caption="Site"
        - ComboBox `VegPlotQuality` sources=ControlSource,RowSourceType,RowSource
          - Label `Label390` caption="Veg"
        - ComboBox `SoilPlotQuality` sources=ControlSource,RowSourceType,RowSource
          - Label `Label392` caption="Soil"
        - TextBox `SubstrateOrganicMatter` sources=ControlSource
          - Label `Text37` caption="Org. Matter"
        - TextBox `SubstrateRocks` sources=ControlSource
          - Label `Text43` caption="Rocks"
        - TextBox `SubstrateDecWood` sources=ControlSource
          - Label `Text39` caption="Dec. Wood"
        - TextBox `SubstrateMineralSoil` sources=ControlSource
          - Label `Text45` caption="Mineral Soil"
        - TextBox `SubstrateBedRock` sources=ControlSource
          - Label `Text41` caption="Bedrock"
        - TextBox `SubstrateWater` sources=ControlSource
          - Label `Text47` caption="Water"
        - TextBox `SiteNotes` sources=ControlSource
        - TextBox `OfficeNotes` sources=ControlSource
          - Label `Label398` caption="OFFICE NOTES"
        - OptionGroup `optLockData` events=AfterUpdate
          - Label `Label406` caption="Data"
          - ToggleButton `Toggle408` caption="Lock"
          - ToggleButton `Toggle409` caption="Unlock" events=OnMouseDown
        - Subform `frmVPics` sources=SourceObject,LinkChildFields,LinkMasterFields
        - CommandButton `btnManagePictures` caption="Picture Manager" events=OnClick
        - OptionGroup `optAssignedSuSource` events=AfterUpdate
          - OptionButton `Option445`
            - Label `Label446` caption="Env"
          - OptionButton `Option447`
            - Label `Label448` caption="Master"
          - OptionButton `Option449`
            - Label `Label450` caption="SU Tbl"
        - Label `Text75` caption="Meso Slope Pos."
        - Label `Text76` caption="Exposure Type"
        - Label `Text77` caption="Surface Shape"
        - Label `Text78` caption="Moisture Regime"
        - Label `Text79` caption="Nutrient Regime"
        - Label `Text80` caption="LOCATION"
        - Label `Text81` caption="SUBSTRATE %"
        - Label `Text109` caption="SITE INFORMATION"
        - Label `Text122` caption="FIELD NOTES"
        - Label `lblLat` caption="Lat"
        - Label `lblLon` caption="Lon"
        - Label `lblLatD2` caption="D"
        - Label `lblLonD2` caption="D"
        - Label `Label353` caption="Photo:"
        - Label `Label376` caption="Coordinate Method"
        - Label `Label171` caption="SITE DIAGRAM/PICTURE"
        - Label `Label118` caption="Transition/Distrib."
        - Label `Label386` caption="BEC Master"
        - Label `Label393` caption="Data Quality"
        - Rectangle `Box394`
        - Label `Label432` caption="Double-click picture for larger view"
        - OptionGroup `optProjectID` events=AfterUpdate
          - OptionButton `Option456`
            - Label `Label457` caption="Env"
          - OptionButton `Option458`
            - Label `Label459` caption="Master"
      - Page `&Vegetation` caption="&Vegetation"
        - TextBox `VegPlotNumber` sources=ControlSource
        - TextBox `StrataCoverTree` sources=ControlSource
          - Label `Label152` caption="Tree(A)"
        - TextBox `StrataCoverShrub` sources=ControlSource
          - Label `Label154` caption="Shrub(B)"
        - TextBox `StrataCoverHerb` sources=ControlSource
          - Label `Label156` caption="Herb(C)"
        - Label `Label157` caption="% Cover By Layer"
        - TextBox `StrataCoverMoss` sources=ControlSource
          - Label `Label159` caption="Moss/Lichen(D)"
        - TextBox `VegSurveyor` sources=ControlSource
          - Label `Label161` caption="Surveyor"
        - Subform `SubVegA` sources=SourceObject,LinkChildFields,LinkMasterFields events=OnEnter,OnExit
        - Subform `SubVegC` sources=SourceObject,LinkChildFields,LinkMasterFields events=OnEnter,OnExit
        - Subform `SubVegD` sources=SourceObject,LinkChildFields,LinkMasterFields events=OnEnter,OnExit
        - TextBox `VegNotes` sources=ControlSource events=OnKeyDown
        - Label `lblNotes` caption="NOTES"
        - ToggleButton `btnAllowSmallEntry` caption="Allow <0.1% Entry" events=OnClick
        - CommandButton `btnFindPlot` caption="Find Plot" events=OnClick
        - CheckBox `SpeciesListComplete` sources=ControlSource
          - Label `Label378` caption="Spp. List Complete?"
        - Subform `SubVegAht` sources=SourceObject,LinkChildFields,LinkMasterFields
        - ToggleButton `btnCoverAndHeight` caption="Cover && Height" events=OnClick
        - Subform `SubVegCht` sources=SourceObject,LinkChildFields,LinkMasterFields
      - Page `Page413` caption="Veg Other"
        - Subform `USysVegOther` sources=SourceObject,LinkChildFields,LinkMasterFields
        - Label `Label417` caption="LL = Arboreal Lichen loading code"
        - Label `Label418` caption="AF = Available Forage Code"
        - Label `Label419` caption="DC = Distribution Code"
        - Label `Label420` caption="UT = Utilization Code"
        - Label `Label421` caption="VI = Vigour Code"
        - Label `Label422` caption="PV = Phenology Code - Vegetative"
        - Label `Label423` caption="PG = Phenology Code - Generative"
        - Label `Label426` caption="FFA = Fruit/Flower abundance code"
      - Page `Soil/&Terrain` caption="Soil/&Terrain"
        - TextBox `MensPlotNumber` sources=ControlSource
        - Label `Label148` caption="System"
        - ComboBox `BedrockGeology1` sources=ControlSource,RowSourceType,RowSource
          - Label `Text100` caption="Bedrock Type"
        - Label `Label185` caption="Flood Regime Frequency"
        - ComboBox `CoarseFragLith1` sources=ControlSource,RowSourceType,RowSource
          - Label `Text71` caption="Coarse Frag. Lith."
        - TextBox `SoilSurveyor` sources=ControlSource
          - Label `Text30` caption="SURVEYOR(S)"
        - Label `Label184` caption="Water Source"
        - Label `Label209` caption="Great group"
        - ComboBox `TerrainTextureSurf` sources=ControlSource,RowSourceType,RowSource
        - ComboBox `SurficialMaterialSurf` sources=ControlSource,RowSourceType,RowSource
        - ComboBox `SurfaceExpSurf` sources=ControlSource,RowSourceType,RowSource
        - ComboBox `GeoMorProSurf` sources=ControlSource,RowSourceType,RowSource
        - ComboBox `TerrainTextureSubSurf` sources=ControlSource,RowSourceType,RowSource
        - ComboBox `SurficialMaterialSubSurf` sources=ControlSource,RowSourceType,RowSource
        - ComboBox `SurfaceExpSubSurf` sources=ControlSource,RowSourceType,RowSource
        - Label `Text73` caption="Root Restrict. Layer"
        - ComboBox `GeoMorProSubSurf` sources=ControlSource,RowSourceType,RowSource
        - ComboBox `SoilClassSubGroup` sources=ControlSource,RowSourceType,RowSource
          - Label `Text66` caption="Soil subgroup"
        - ComboBox `SoilClassGroup` sources=ControlSource,RowSourceType,RowSource
        - ComboBox `HumusForm` sources=ControlSource,RowSourceType,RowSource
          - Label `Text56` caption="HUMUS FORM"
        - ComboBox `HumusFormPhase` sources=ControlSource,RowSourceType,RowSource
        - TextBox `HumusThickness` sources=ControlSource
          - Label `Label309` caption="Thickness"
        - ComboBox `HydroGeoSystem` sources=ControlSource,RowSourceType,RowSource
        - Label `Label74` caption="GEOLOGY"
        - Label `Label75` caption="TERRAIN"
        - ComboBox `HydroGeoSubSystem` sources=ControlSource,RowSourceType,RowSource
        - TextBox `RootingDepth` sources=ControlSource
          - Label `Text21` caption="Rooting  Depth (cm)"
        - ComboBox `RootRestrictingType` sources=ControlSource,RowSourceType,RowSource
          - Label `Type_Label` caption="Type"
        - Label `Label91` caption="ORGANIC HORIZONS/LAYERS"
        - Label `Label92` caption="MINERAL HORIZONS/LAYERS"
        - ComboBox `WaterSource` sources=ControlSource,RowSourceType,RowSource
        - Label `Label127` caption="Surface Texture 1"
        - ComboBox `SoilDrainage` sources=ControlSource,RowSourceType,RowSource
          - Label `Text17` caption="Drainage Class"
        - Label `Label130` caption="Surficial Material 1"
        - ComboBox `RootZoneParticleSize` sources=ControlSource,RowSourceType,RowSource
          - Label `Text70` caption="R. Z. Particle Size"
        - Label `Label132` caption="Surface Expression 1"
        - TextBox `RootRestrictingDepth` sources=ControlSource
          - Label `Text25` caption="Depth (cm)"
        - Label `Label134` caption="Geomorphological Process 1"
        - Label `Label135` caption="Surface Texture 2"
        - TextBox `SeepageDepth` sources=ControlSource
          - Label `Text16` caption="Seepage  (cm)"
        - ComboBox `FloodingRegimeFreq` sources=ControlSource,RowSourceType,RowSource
        - Label `Label138` caption="Surficial Material 2"
        - ComboBox `FloodingRegimeDur` sources=ControlSource,RowSourceType,RowSource
        - Label `Label140` caption="Surface Expression 2"
        - Label `Label142` caption="Geomorphological Process 2"
        - Label `Label77` caption="HYDROGEO."
        - Label `Label144` caption="Phase"
        - Subform `SoilHumus` sources=SourceObject,LinkChildFields,LinkMasterFields events=OnEnter,OnExit
        - Subform `SoilMineral` sources=SourceObject,LinkChildFields,LinkMasterFields events=OnEnter,OnExit
        - TextBox `SoilNotes` sources=ControlSource
          - Label `Text64` caption="NOTES"
        - ComboBox `BedrockGeology2` sources=ControlSource,RowSourceType,RowSource
        - ComboBox `BedrockGeology3` sources=ControlSource,RowSourceType,RowSource
        - ComboBox `CoarseFragLith2` sources=ControlSource,RowSourceType,RowSource
        - ComboBox `CoarseFragLith3` sources=ControlSource,RowSourceType,RowSource
        - Label `Label385` caption="Duration"
      - Page `&Other` caption="&Other"
        - Subform `SubOther` sources=SourceObject,LinkChildFields,LinkMasterFields
        - TextBox `Text287` sources=ControlSource
      - Page `&Audit` caption="&Audit"
        - Label `Text180` caption="AUDIT"
        - TextBox `MensWildPlotNumber` sources=ControlSource
        - Subform `USysAudit` sources=SourceObject,LinkChildFields,LinkMasterFields
        - CommandButton `btnRestoreSelectedChanges` caption="Restore selected change(s)" events=OnClick
    - Label `Label416` caption="ECOSYSTEM FIELD FORM (FS882)"
  - FormFooter `FormFooter`
    - CommandButton `btnG2MainMenu` caption="Close" events=OnClick
    - CommandButton `btnSaveRecord` caption="Save" events=OnClick
    - CommandButton `btnGoogleEarth` caption="Command396" events=OnClick
    - CommandButton `btnVegProfiling` caption="Plot Profiling" events=OnClick
    - CommandButton `btnAudit` caption="Audit" events=OnClick
    - CommandButton `btnSuIntoEnv` caption="SU Into Env" events=OnClick
    - CommandButton `btnEnvIntoSu` caption="Env Into SU" events=OnClick
    - ToggleButton `btnPlotPicture` caption="Plot picture" events=OnClick
    - CommandButton `btnCreateSuFromFilter` caption="Create SU From Form Filter" events=OnClick

## 3) Control Source Dependencies
| Control | Type | Source Property | Value |
|---|---|---|---|
| Form_2 | Form | OrderByOn | NotDefault |
| Form_2 | Form | Filter | ([USysEnv].[NutrientRegime] In ("B","C")) |
| Form_2 | Form | OrderBy | [USysEnv].[RootingDepth] DESC, [USysEnv].[SeepageDepth] DESC, [USysEnv].[PlotNumber] |
| Form_2 | Form | RecordSource | USysEnv |
| Form_2 | Form | FilterOnLoad | 0 |
| PlotNumber | TextBox | ControlSource | PlotNumber |
| Date | TextBox | ControlSource | Date |
| ProjectID | ComboBox | ControlSource | ProjectID |
| ProjectID | ComboBox | RowSourceType | Table/Query |
| ProjectID | ComboBox | RowSource | SELECT ProjectMetaData.ProjectID, ProjectMetaData.ProjectTitle FROM ProjectMetaData;  |
| StartDate | TextBox | ControlSource | StartDate |
| SiteSurveyor | TextBox | ControlSource | SiteSurveyor |
| FieldNumber | TextBox | ControlSource | FieldNumber |
| BECSiteUnit | ComboBox | ControlSource | BECSiteUnit |
| BECSiteUnit | ComboBox | RowSourceType | Table/Query |
| BECSiteUnit | ComboBox | RowSource | SELECT USysMasterSiteUnitList.Name, USysMasterSiteUnitList.UnitLongName FROM USysMasterSiteUnitList WHERE (((USysMasterSiteUnitList.Level)=11)) ORDER BY USysMasterSiteUnitList.[Name]; |
| UserSiteUnit | ComboBox | ControlSource | UserSiteUnit |
| UserSiteUnit | ComboBox | RowSourceType | Table/Query |
| UserSiteUnit | ComboBox | RowSource | SELECT USysMasterSiteUnitList.Name, USysMasterSiteUnitList.UnitLongName FROM USysMasterSiteUnitList WHERE (((USysMasterSiteUnitList.Level)=11)) ORDER BY USysMasterSiteUnitList.[Name]; |
| Location | TextBox | ControlSource | Location |
| FSRegionDistrict | ComboBox | ControlSource | FSRegionDistrict |
| FSRegionDistrict | ComboBox | RowSourceType | Table/Query |
| FSRegionDistrict | ComboBox | RowSource | SELECT DISTINCTROW USysTableOfLists.Item, USysTableOfLists.ItemDescription FROM USysTableOfLists WHERE (((USysTableOfLists.ListName)="Region")) ORDER BY USysTableOfLists.ItemOrder; |
| NtsMapSheet | TextBox | ControlSource | NtsMapSheet |
| UTMZone | TextBox | ControlSource | UTMZone |
| UTMEasting | TextBox | ControlSource | UTMEasting |
| UTMNorthing | TextBox | ControlSource | UTMNorthing |
| LocationAccuracy | TextBox | ControlSource | LocationAccuracy |
| AirPhotoNum | TextBox | ControlSource | AirPhotoNum |
| XCoord | TextBox | ControlSource | XCoord |
| YCoord | TextBox | ControlSource | YCoord |
| Latitude | TextBox | ControlSource | Latitude |
| Longitude | TextBox | ControlSource | Longitude |
| Ecosection | ComboBox | ControlSource | Ecosection |
| Ecosection | ComboBox | RowSourceType | Table/Query |
| Ecosection | ComboBox | RowSource | SELECT DISTINCTROW USysTableOfLists.Item, USysTableOfLists.ItemDescription FROM USysTableOfLists WHERE (((USysTableOfLists.ListName)="ecosection"));  |
| PlotRepresenting | TextBox | ControlSource | PlotRepresenting |
| Zone | ComboBox | ControlSource | Zone |
| Zone | ComboBox | RowSourceType | Table/Query |
| Zone | ComboBox | RowSource | SELECT DISTINCT USysZoneList.Zone, USysZoneList.ZoneDescription FROM USysZoneList;  |
| SubZone | ComboBox | RowSourceTypeInt | 1 |
| SubZone | ComboBox | ControlSource | SubZone |
| SubZone | ComboBox | RowSourceType | Value List |
| RealmClass | ComboBox | ControlSource | RealmClass |
| RealmClass | ComboBox | RowSourceType | Table/Query |
| RealmClass | ComboBox | RowSource | SELECT USysTableOfLists.Item, USysTableOfLists.ItemDescription FROM USysTableOfLists WHERE (((USysTableOfLists.ListName)="RealmClass")) ORDER BY USysTableOfLists.ItemOrder;  |
| TransDistrib | ComboBox | ControlSource | TransDistrib |
| TransDistrib | ComboBox | RowSourceType | Table/Query |
| TransDistrib | ComboBox | RowSource | SELECT USysTableOfLists.Item, USysTableOfLists.ItemDescription FROM USysTableOfLists WHERE (((USysTableOfLists.ListName)="TransDistrib")) ORDER BY USysTableOfLists.ItemOrder;  |
| MapUnit | TextBox | ControlSource | MapUnit |
| SiteSeries | ComboBox | RowSourceTypeInt | 1 |
| SiteSeries | ComboBox | ControlSource | SiteSeries |
| SiteSeries | ComboBox | RowSourceType | Value List |
| MoistureRegime | ComboBox | ControlSource | MoistureRegime |
| MoistureRegime | ComboBox | RowSourceType | Table/Query |
| MoistureRegime | ComboBox | RowSource | SELECT DISTINCTROW USysTableOfLists.Item, USysTableOfLists.ItemDescription FROM USysTableOfLists WHERE (((USysTableOfLists.ListName)="MoistureRegime")) ORDER BY USysTableOfLists.ItemOrder;  |
| NutrientRegime | ComboBox | ControlSource | NutrientRegime |
| NutrientRegime | ComboBox | RowSourceType | Table/Query |
| NutrientRegime | ComboBox | RowSource | SELECT DISTINCTROW USysTableOfLists.Item, USysTableOfLists.ItemDescription FROM USysTableOfLists WHERE (((USysTableOfLists.ListName)="NutrientRegime")) ORDER BY USysTableOfLists.ItemOrder;  |
| SuccessionalStatus | ComboBox | ControlSource | SuccessionalStatus |
| SuccessionalStatus | ComboBox | RowSourceType | Table/Query |
| SuccessionalStatus | ComboBox | RowSource | SELECT USysTableOfLists.Item, USysTableOfLists.ItemDescription FROM USysTableOfLists WHERE (((USysTableOfLists.ListName)="SuccessionalStatus")) ORDER BY USysTableOfLists.ItemOrder;  |
| StructuralStage | ComboBox | ControlSource | StructuralStage |
| StructuralStage | ComboBox | RowSourceType | Table/Query |
| StructuralStage | ComboBox | RowSource | SELECT USysTableOfLists.Item, USysTableOfLists.ItemDescription FROM USysTableOfLists WHERE (((USysTableOfLists.ListName)="StructuralStage")) ORDER BY USysTableOfLists.ItemOrder;  |
| StandAge | TextBox | ControlSource | StandAge |
| Photo | TextBox | ControlSource | Photo |
| Elevation | TextBox | ControlSource | Elevation |
| SlopeGradient | TextBox | ControlSource | SlopeGradient |
| Aspect | TextBox | ControlSource | Aspect |
| MesoSlopePosition | ComboBox | ControlSource | MesoSlopePosition |
| MesoSlopePosition | ComboBox | RowSourceType | Table/Query |
| MesoSlopePosition | ComboBox | RowSource | SELECT DISTINCTROW USysTableOfLists.Item, USysTableOfLists.ItemDescription FROM USysTableOfLists WHERE (((USysTableOfLists.ListName)="MesoSlopePosition")) ORDER BY USysTableOfLists.ItemOrder;  |
| SurfaceShape | ComboBox | ControlSource | SurfaceShape |
| SurfaceShape | ComboBox | RowSourceType | Table/Query |
| SurfaceShape | ComboBox | RowSource | SELECT DISTINCTROW USysTableOfLists.Item, USysTableOfLists.ItemDescription FROM USysTableOfLists WHERE (((USysTableOfLists.ListName)="SurfaceShape")) ORDER BY USysTableOfLists.ItemOrder; |
| SurfaceTopographyType | ComboBox | ControlSource | SurfaceTopographyType |
| SurfaceTopographyType | ComboBox | RowSourceType | Table/Query |
| SurfaceTopographyType | ComboBox | RowSource | SELECT USysTableOfLists.Item, USysTableOfLists.ItemDescription FROM USysTableOfLists WHERE ((Not (USysTableOfLists.Item)='cc' And Not (USysTableOfLists.Item)='cv' And Not (USysTableOfLists.Item)='st') AND ((USysTableOfLists.ListName)="SurfaceTopography")) ORDER BY USysTableOfLists.ItemOrder;  |
| SurfaceTopographySize | ComboBox | ControlSource | SurfaceTopographySize |
| SurfaceTopographySize | ComboBox | RowSourceType | Table/Query |
| SurfaceTopographySize | ComboBox | RowSource | SELECT USysTableOfLists.Item, USysTableOfLists.ItemDescription FROM USysTableOfLists WHERE (((USysTableOfLists.ListName)="SurfaceTopographySize")) ORDER BY USysTableOfLists.ItemOrder;  |
| SiteDisturbance1 | ComboBox | ControlSource | SiteDisturbance1 |
| SiteDisturbance1 | ComboBox | RowSourceType | Table/Query |
| SiteDisturbance1 | ComboBox | RowSource | SELECT DISTINCTROW USysTableOfLists.Item, USysTableOfLists.ItemDescription FROM USysTableOfLists WHERE (((USysTableOfLists.ListName)="SiteDisturbance")) ORDER BY USysTableOfLists.ItemOrder; |
| SiteDisturbance2 | ComboBox | ControlSource | SiteDisturbance2 |
| SiteDisturbance2 | ComboBox | RowSourceType | Table/Query |
| SiteDisturbance2 | ComboBox | RowSource | SELECT DISTINCTROW USysTableOfLists.Item, USysTableOfLists.ItemDescription FROM USysTableOfLists WHERE (((USysTableOfLists.ListName)="SiteDisturbance")) ORDER BY USysTableOfLists.ItemOrder;  |
| SiteDisturbance3 | ComboBox | ControlSource | SiteDisturbance3 |
| SiteDisturbance3 | ComboBox | RowSourceType | Table/Query |
| SiteDisturbance3 | ComboBox | RowSource | SELECT DISTINCTROW USysTableOfLists.Item, USysTableOfLists.ItemDescription FROM USysTableOfLists WHERE (((USysTableOfLists.ListName)="SiteDisturbance")) ORDER BY USysTableOfLists.ItemOrder;  |
| Exposure1 | ComboBox | ControlSource | Exposure1 |
| Exposure1 | ComboBox | RowSourceType | Table/Query |
| Exposure1 | ComboBox | RowSource | SELECT DISTINCTROW USysTableOfLists.Item, USysTableOfLists.ItemDescription FROM USysTableOfLists WHERE (((USysTableOfLists.ListName)="Exposure")) ORDER BY USysTableOfLists.ItemOrder;  |
| Exposure2 | ComboBox | ControlSource | Exposure2 |
| Exposure2 | ComboBox | RowSourceType | Table/Query |
| Exposure2 | ComboBox | RowSource | SELECT DISTINCTROW USysTableOfLists.Item, USysTableOfLists.ItemDescription FROM USysTableOfLists WHERE (((USysTableOfLists.ListName)="Exposure")) ORDER BY USysTableOfLists.ItemOrder;  |
| SitePlotQuality | ComboBox | ControlSource | SitePlotQuality |
| SitePlotQuality | ComboBox | RowSourceType | Table/Query |
| SitePlotQuality | ComboBox | RowSource | SELECT USysTableOfLists.Item FROM USysTableOfLists WHERE (((USysTableOfLists.ListName)="PlotQualitySite")) ORDER BY USysTableOfLists.ItemOrder; |
| VegPlotQuality | ComboBox | ControlSource | VegPlotQuality |
| VegPlotQuality | ComboBox | RowSourceType | Table/Query |
| VegPlotQuality | ComboBox | RowSource | SELECT USysTableOfLists.Item FROM USysTableOfLists WHERE (((USysTableOfLists.ListName)="PlotQualitySite")) ORDER BY USysTableOfLists.ItemOrder; |
| SoilPlotQuality | ComboBox | ControlSource | SoilPlotQuality |
| SoilPlotQuality | ComboBox | RowSourceType | Table/Query |
| SoilPlotQuality | ComboBox | RowSource | SELECT USysTableOfLists.Item FROM USysTableOfLists WHERE (((USysTableOfLists.ListName)="PlotQualitySite")) ORDER BY USysTableOfLists.ItemOrder; |
| SubstrateOrganicMatter | TextBox | ControlSource | SubstrateOrganicMatter |
| SubstrateRocks | TextBox | ControlSource | SubstrateRocks |
| SubstrateDecWood | TextBox | ControlSource | SubstrateDecWood |
| SubstrateMineralSoil | TextBox | ControlSource | SubstrateMineralSoil |
| SubstrateBedRock | TextBox | ControlSource | SubstrateBedRock |
| SubstrateWater | TextBox | ControlSource | SubstrateWater |
| SiteNotes | TextBox | ControlSource | SiteNotes |
| OfficeNotes | TextBox | ControlSource | OfficeNotes |
| frmVPics | Subform | SourceObject | Form.frmVPics |
| frmVPics | Subform | LinkChildFields | PlotNumber |
| frmVPics | Subform | LinkMasterFields | PlotNumber |
| VegPlotNumber | TextBox | ControlSource | PlotNumber |
| StrataCoverTree | TextBox | ControlSource | StrataCoverTree |
| StrataCoverShrub | TextBox | ControlSource | StrataCoverShrub |
| StrataCoverHerb | TextBox | ControlSource | StrataCoverHerb |
| StrataCoverMoss | TextBox | ControlSource | StrataCoverMoss |
| VegSurveyor | TextBox | ControlSource | VegSurveyor |
| SubVegA | Subform | SourceObject | Form.SubVegA |
| SubVegA | Subform | LinkChildFields | PlotNumber |
| SubVegA | Subform | LinkMasterFields | PlotNumber |
| SubVegC | Subform | SourceObject | Form.SubVegC |
| SubVegC | Subform | LinkChildFields | PlotNumber |
| SubVegC | Subform | LinkMasterFields | PlotNumber |
| SubVegD | Subform | SourceObject | Form.SubVegD |
| SubVegD | Subform | LinkChildFields | PlotNumber |
| SubVegD | Subform | LinkMasterFields | PlotNumber |
| VegNotes | TextBox | ControlSource | VegNotes |
| SpeciesListComplete | CheckBox | ControlSource | SpeciesListComplete |
| SubVegAht | Subform | SourceObject | Form.SubVegAht |
| SubVegAht | Subform | LinkChildFields | plotnumber |
| SubVegAht | Subform | LinkMasterFields | plotnumber |
| SubVegCht | Subform | SourceObject | Form.SubVegCht |
| SubVegCht | Subform | LinkChildFields | plotnumber |
| SubVegCht | Subform | LinkMasterFields | plotnumber |
| USysVegOther | Subform | SourceObject | Form.USysVegOther |
| USysVegOther | Subform | LinkChildFields | PlotNumber |
| USysVegOther | Subform | LinkMasterFields | PlotNumber |
| MensPlotNumber | TextBox | ControlSource | PlotNumber |
| BedrockGeology1 | ComboBox | ControlSource | BedrockGeology1 |
| BedrockGeology1 | ComboBox | RowSourceType | Table/Query |
| BedrockGeology1 | ComboBox | RowSource | SELECT USysTableOfLists.Item, USysTableOfLists.ItemDescription FROM USysTableOfLists WHERE (((USysTableOfLists.ListName)="BedrockType")) ORDER BY USysTableOfLists.ItemOrder;  |
| CoarseFragLith1 | ComboBox | ControlSource | CoarseFragLith1 |
| CoarseFragLith1 | ComboBox | RowSourceType | Table/Query |
| CoarseFragLith1 | ComboBox | RowSource | SELECT USysTableOfLists.Item, USysTableOfLists.ItemDescription FROM USysTableOfLists WHERE (((USysTableOfLists.ListName)="BedrockType")) ORDER BY USysTableOfLists.ItemOrder;  |
| SoilSurveyor | TextBox | ControlSource | SoilSurveyor |
| TerrainTextureSurf | ComboBox | ControlSource | TerrainTextureSurf |
| TerrainTextureSurf | ComboBox | RowSourceType | Table/Query |
| TerrainTextureSurf | ComboBox | RowSource | SELECT USysTableOfLists.Item, USysTableOfLists.ItemDescription FROM USysTableOfLists WHERE (((USysTableOfLists.ListName)="TerrainTexture")) ORDER BY USysTableOfLists.ItemOrder;  |
| SurficialMaterialSurf | ComboBox | ControlSource | SurficialMaterialSurf |
| SurficialMaterialSurf | ComboBox | RowSourceType | Table/Query |
| SurficialMaterialSurf | ComboBox | RowSource | SELECT USysTableOfLists.Item, USysTableOfLists.ItemDescription FROM USysTableOfLists WHERE (((USysTableOfLists.ListName)="SurficialMaterial")) ORDER BY USysTableOfLists.ItemOrder;  |
| SurfaceExpSurf | ComboBox | ControlSource | SurfaceExpSurf |
| SurfaceExpSurf | ComboBox | RowSourceType | Table/Query |
| SurfaceExpSurf | ComboBox | RowSource | SELECT USysTableOfLists.Item, USysTableOfLists.ItemDescription FROM USysTableOfLists WHERE (((USysTableOfLists.ListName)="SurfaceExp")) ORDER BY USysTableOfLists.ItemOrder;  |
| GeoMorProSurf | ComboBox | ControlSource | GeoMorProSurf |
| GeoMorProSurf | ComboBox | RowSourceType | Table/Query |
| GeoMorProSurf | ComboBox | RowSource | SELECT USysTableOfLists.Item, USysTableOfLists.ItemDescription FROM USysTableOfLists WHERE (((USysTableOfLists.ListName)="GeoMorPro")) ORDER BY USysTableOfLists.ItemOrder;  |
| TerrainTextureSubSurf | ComboBox | ControlSource | TerrainTextureSubSurf |
| TerrainTextureSubSurf | ComboBox | RowSourceType | Table/Query |
| TerrainTextureSubSurf | ComboBox | RowSource | SELECT USysTableOfLists.Item, USysTableOfLists.ItemDescription FROM USysTableOfLists WHERE (((USysTableOfLists.ListName)="TerrainTexture")) ORDER BY USysTableOfLists.ItemOrder;  |
| SurficialMaterialSubSurf | ComboBox | ControlSource | SurficialMaterialSubSurf |
| SurficialMaterialSubSurf | ComboBox | RowSourceType | Table/Query |
| SurficialMaterialSubSurf | ComboBox | RowSource | SELECT USysTableOfLists.Item, USysTableOfLists.ItemDescription FROM USysTableOfLists WHERE (((USysTableOfLists.ListName)="SurficialMaterial")) ORDER BY USysTableOfLists.ItemOrder;  |
| SurfaceExpSubSurf | ComboBox | ControlSource | SurfaceExpSubSurf |
| SurfaceExpSubSurf | ComboBox | RowSourceType | Table/Query |
| SurfaceExpSubSurf | ComboBox | RowSource | SELECT USysTableOfLists.Item, USysTableOfLists.ItemDescription FROM USysTableOfLists WHERE (((USysTableOfLists.ListName)="SurfaceExp")) ORDER BY USysTableOfLists.ItemOrder;  |
| GeoMorProSubSurf | ComboBox | ControlSource | GeoMorProSubSurf |
| GeoMorProSubSurf | ComboBox | RowSourceType | Table/Query |
| GeoMorProSubSurf | ComboBox | RowSource | SELECT USysTableOfLists.Item, USysTableOfLists.ItemDescription FROM USysTableOfLists WHERE (((USysTableOfLists.ListName)="GeoMorPro")) ORDER BY USysTableOfLists.ItemOrder;  |
| SoilClassSubGroup | ComboBox | ControlSource | SoilClassSubGroup |
| SoilClassSubGroup | ComboBox | RowSourceType | Table/Query |
| SoilClassSubGroup | ComboBox | RowSource | SELECT DISTINCTROW USysTableOfLists.Item, USysTableOfLists.ItemDescription FROM USysTableOfLists WHERE (((USysTableOfLists.ListName)="SoilClassSubgroup")) ORDER BY USysTableOfLists.ItemOrder;  |
| SoilClassGroup | ComboBox | ControlSource | SoilClassGroup |
| SoilClassGroup | ComboBox | RowSourceType | Table/Query |
| SoilClassGroup | ComboBox | RowSource | SELECT DISTINCTROW USysTableOfLists.Item, USysTableOfLists.ItemDescription FROM USysTableOfLists WHERE (((USysTableOfLists.ListName)="SoilClassGroup")) ORDER BY USysTableOfLists.ItemOrder;  |
| HumusForm | ComboBox | ControlSource | HumusForm |
| HumusForm | ComboBox | RowSourceType | Table/Query |
| HumusForm | ComboBox | RowSource | SELECT USysTableOfLists.Item, USysTableOfLists.ItemDescription FROM USysTableOfLists WHERE (((USysTableOfLists.ListName)="HumusForm")) ORDER BY USysTableOfLists.ItemOrder;  |
| HumusFormPhase | ComboBox | ControlSource | HumusFormPhase |
| HumusFormPhase | ComboBox | RowSourceType | Table/Query |
| HumusFormPhase | ComboBox | RowSource | SELECT USysTableOfLists.Item, USysTableOfLists.ItemDescription FROM USysTableOfLists WHERE (((USysTableOfLists.ListName)="HumusFormPhase")) ORDER BY USysTableOfLists.ItemOrder;  |
| HumusThickness | TextBox | ControlSource | HumusThickness |
| HydroGeoSystem | ComboBox | ControlSource | HydroGeoSystem |
| HydroGeoSystem | ComboBox | RowSourceType | Table/Query |
| HydroGeoSystem | ComboBox | RowSource | SELECT USysTableOfLists.Item, USysTableOfLists.ItemDescription FROM USysTableOfLists WHERE (((USysTableOfLists.ListName)="HydrogeoSystem")) ORDER BY USysTableOfLists.ItemOrder;  |
| HydroGeoSubSystem | ComboBox | ControlSource | HydroGeoSubSystem |
| HydroGeoSubSystem | ComboBox | RowSourceType | Table/Query |
| HydroGeoSubSystem | ComboBox | RowSource | SELECT USysTableOfLists.Item, USysTableOfLists.ItemDescription FROM USysTableOfLists WHERE (((USysTableOfLists.ListName)="HydrogeoSubsystem")) ORDER BY USysTableOfLists.ItemOrder;  |
| RootingDepth | TextBox | ControlSource | RootingDepth |
| RootRestrictingType | ComboBox | ControlSource | RootRestrictingType |
| RootRestrictingType | ComboBox | RowSourceType | Table/Query |
| RootRestrictingType | ComboBox | RowSource | SELECT DISTINCTROW USysTableOfLists.Item, USysTableOfLists.ItemDescription FROM USysTableOfLists WHERE (((USysTableOfLists.ListName)="RootRestrictingType")) ORDER BY USysTableOfLists.ItemOrder;  |
| WaterSource | ComboBox | ControlSource | WaterSource |
| WaterSource | ComboBox | RowSourceType | Table/Query |
| WaterSource | ComboBox | RowSource | SELECT USysTableOfLists.Item, USysTableOfLists.ItemDescription FROM USysTableOfLists WHERE (((USysTableOfLists.ListName)="WaterSource")) ORDER BY USysTableOfLists.ItemOrder;  |
| SoilDrainage | ComboBox | ControlSource | SoilDrainage |
| SoilDrainage | ComboBox | RowSourceType | Table/Query |
| SoilDrainage | ComboBox | RowSource | SELECT DISTINCTROW USysTableOfLists.Item, USysTableOfLists.ItemDescription FROM USysTableOfLists WHERE (((USysTableOfLists.ListName)="SoilDrainage")) ORDER BY USysTableOfLists.ItemOrder;  |
| RootZoneParticleSize | ComboBox | ControlSource | RootZoneParticleSize |
| RootZoneParticleSize | ComboBox | RowSourceType | Table/Query |
| RootZoneParticleSize | ComboBox | RowSource | SELECT DISTINCTROW USysTableOfLists.Item, USysTableOfLists.ItemDescription FROM USysTableOfLists WHERE (((USysTableOfLists.ListName)="RootZoneParticleSize")) ORDER BY USysTableOfLists.ItemOrder;  |
| RootRestrictingDepth | TextBox | ControlSource | RootRestrictingDepth |
| SeepageDepth | TextBox | ControlSource | SeepageDepth |
| FloodingRegimeFreq | ComboBox | ControlSource | FloodingRegimeFreq |
| FloodingRegimeFreq | ComboBox | RowSourceType | Table/Query |
| FloodingRegimeFreq | ComboBox | RowSource | SELECT USysTableOfLists.Item, USysTableOfLists.ItemDescription FROM USysTableOfLists WHERE (((USysTableOfLists.ListName)="FloodingRegimeFreq")) ORDER BY USysTableOfLists.ItemOrder;  |
| FloodingRegimeDur | ComboBox | ControlSource | FloodingRegimeDur |
| FloodingRegimeDur | ComboBox | RowSourceType | Table/Query |
| FloodingRegimeDur | ComboBox | RowSource | SELECT USysTableOfLists.Item, USysTableOfLists.ItemDescription FROM USysTableOfLists WHERE (((USysTableOfLists.ListName)="FloodingRegimeDur")) ORDER BY USysTableOfLists.ItemOrder;  |
| SoilHumus | Subform | SourceObject | Form.SoilHumus |
| SoilHumus | Subform | LinkChildFields | PlotNumber |
| SoilHumus | Subform | LinkMasterFields | PlotNumber |
| SoilMineral | Subform | SourceObject | Form.SoilMineral |
| SoilMineral | Subform | LinkChildFields | PlotNumber |
| SoilMineral | Subform | LinkMasterFields | PlotNumber |
| SoilNotes | TextBox | ControlSource | SoilNotes |
| BedrockGeology2 | ComboBox | ControlSource | BedrockGeology2 |
| BedrockGeology2 | ComboBox | RowSourceType | Table/Query |
| BedrockGeology2 | ComboBox | RowSource | SELECT USysTableOfLists.Item, USysTableOfLists.ItemDescription FROM USysTableOfLists WHERE (((USysTableOfLists.ListName)="BedrockType")) ORDER BY USysTableOfLists.ItemOrder;  |
| BedrockGeology3 | ComboBox | ControlSource | BedrockGeology3 |
| BedrockGeology3 | ComboBox | RowSourceType | Table/Query |
| BedrockGeology3 | ComboBox | RowSource | SELECT USysTableOfLists.Item, USysTableOfLists.ItemDescription FROM USysTableOfLists WHERE (((USysTableOfLists.ListName)="BedrockType")) ORDER BY USysTableOfLists.ItemOrder;  |
| CoarseFragLith2 | ComboBox | ControlSource | CoarseFragLith2 |
| CoarseFragLith2 | ComboBox | RowSourceType | Table/Query |
| CoarseFragLith2 | ComboBox | RowSource | SELECT USysTableOfLists.Item, USysTableOfLists.ItemDescription FROM USysTableOfLists WHERE (((USysTableOfLists.ListName)="BedrockType")) ORDER BY USysTableOfLists.ItemOrder;  |
| CoarseFragLith3 | ComboBox | ControlSource | CoarseFragLith3 |
| CoarseFragLith3 | ComboBox | RowSourceType | Table/Query |
| CoarseFragLith3 | ComboBox | RowSource | SELECT USysTableOfLists.Item, USysTableOfLists.ItemDescription FROM USysTableOfLists WHERE (((USysTableOfLists.ListName)="BedrockType")) ORDER BY USysTableOfLists.ItemOrder;  |
| SubOther | Subform | SourceObject | Form.SubOther |
| SubOther | Subform | LinkChildFields | PlotNumber |
| SubOther | Subform | LinkMasterFields | PlotNumber |
| Text287 | TextBox | ControlSource | PlotNumber |
| MensWildPlotNumber | TextBox | ControlSource | PlotNumber |
| USysAudit | Subform | SourceObject | Form.USysAudit |
| USysAudit | Subform | LinkChildFields | PlotNumber |
| USysAudit | Subform | LinkMasterFields | PlotNumber |

## 4) Event Procedure Mappings
| Control | Type | Event Property | Expected Handler | Local Procedure Found |
|---|---|---|---|---|
| Form_2 | Form | OnCurrent | Form_Current | Yes (line 8830) |
| Form_2 | Form | BeforeUpdate | Form_BeforeUpdate | Yes (line 8815) |
| Form_2 | Form | OnOpen | Form_Open | Yes (line 9048) |
| Form_2 | Form | OnClose | Form_Close | Yes (line 8823) |
| Form_2 | Form | OnMouseDown | Form_MouseDown | No local handler |
| Form_2 | Form | OnLostFocus | Form_LostFocus | No local handler |
| Form_2 | Form | OnClick | Form_Click | Yes (line 8819) |
| Form_2 | Form | OnLoad | Form_Load | Yes (line 8836) |
| tabPages | Tab | OnChange | tabPages_Change | Yes (line 9295) |
| PlotNumber | TextBox | AfterUpdate | PlotNumber_AfterUpdate | Yes (line 9100) |
| PlotNumber | TextBox | OnMouseUp | PlotNumber_MouseUp | Yes (line 9131) |
| PlotNumber | TextBox | OnLostFocus | PlotNumber_LostFocus | Yes (line 9105) |
| ProjectID | ComboBox | OnGotFocus | ProjectID_GotFocus | Yes (line 9137) |
| ProjectID | ComboBox | OnLostFocus | ProjectID_LostFocus | Yes (line 9176) |
| ProjectID | ComboBox | OnNotInList | ProjectID_NotInList | Yes (line 9180) |
| optCoordMethod2 | OptionGroup | AfterUpdate | optCoordMethod2_AfterUpdate | Yes (line 9065) |
| LatD2 | TextBox | AfterUpdate | LatD2_AfterUpdate | Yes (line 9004) |
| LatD | TextBox | AfterUpdate | LatD_AfterUpdate | Yes (line 9000) |
| LatMD | TextBox | AfterUpdate | LatMD_AfterUpdate | Yes (line 9016) |
| Latitude | TextBox | AfterUpdate | Latitude_AfterUpdate | Yes (line 9008) |
| LatM | TextBox | AfterUpdate | LatM_AfterUpdate | Yes (line 9012) |
| LatS | TextBox | AfterUpdate | LatS_AfterUpdate | Yes (line 9020) |
| LonD2 | TextBox | AfterUpdate | LonD2_AfterUpdate | Yes (line 9028) |
| LonD | TextBox | AfterUpdate | LonD_AfterUpdate | Yes (line 9024) |
| Longitude | TextBox | AfterUpdate | Longitude_AfterUpdate | Yes (line 9032) |
| LonM | TextBox | AfterUpdate | LonM_AfterUpdate | Yes (line 9036) |
| LonMD | TextBox | AfterUpdate | LonMD_AfterUpdate | Yes (line 9040) |
| LonS | TextBox | AfterUpdate | LonS_AfterUpdate | Yes (line 9044) |
| SubZone | ComboBox | OnGotFocus | SubZone_GotFocus | Yes (line 9287) |
| SiteSeries | ComboBox | OnEnter | SiteSeries_Enter | Yes (line 9201) |
| btnCopyToUserSU | CommandButton | OnClick | btnCopyToUserSU_Click | Yes (line 8624) |
| btnLoadMetadata | CommandButton | OnClick | btnLoadMetadata_Click | Yes (line 8684) |
| optLockData | OptionGroup | AfterUpdate | optLockData_AfterUpdate | Yes (line 9069) |
| Toggle409 | ToggleButton | OnMouseDown | Toggle409_MouseDown | Yes (line 9303) |
| btnManagePictures | CommandButton | OnClick | btnManagePictures_Click | Yes (line 8751) |
| optAssignedSuSource | OptionGroup | AfterUpdate | optAssignedSuSource_AfterUpdate | Yes (line 9054) |
| optProjectID | OptionGroup | AfterUpdate | optProjectID_AfterUpdate | Yes (line 9094) |
| SubVegA | Subform | OnEnter | SubVegA_Enter | Yes (line 9257) |
| SubVegA | Subform | OnExit | SubVegA_Exit | Yes (line 9261) |
| SubVegC | Subform | OnEnter | SubVegC_Enter | Yes (line 9267) |
| SubVegC | Subform | OnExit | SubVegC_Exit | Yes (line 9271) |
| SubVegD | Subform | OnEnter | SubVegD_Enter | Yes (line 9277) |
| SubVegD | Subform | OnExit | SubVegD_Exit | Yes (line 9281) |
| VegNotes | TextBox | OnKeyDown | VegNotes_KeyDown | Yes (line 9307) |
| btnAllowSmallEntry | ToggleButton | OnClick | btnAllowSmallEntry_Click | Yes (line 8591) |
| btnFindPlot | CommandButton | OnClick | btnFindPlot_Click | Yes (line 9313) |
| btnCoverAndHeight | ToggleButton | OnClick | btnCoverAndHeight_Click | Yes (line 8629) |
| SoilHumus | Subform | OnEnter | SoilHumus_Enter | Yes (line 9241) |
| SoilHumus | Subform | OnExit | SoilHumus_Exit | Yes (line 9245) |
| SoilMineral | Subform | OnEnter | SoilMineral_Enter | Yes (line 9249) |
| SoilMineral | Subform | OnExit | SoilMineral_Exit | Yes (line 9253) |
| btnRestoreSelectedChanges | CommandButton | OnClick | btnRestoreSelectedChanges_Click | Yes (line 8767) |
| btnG2MainMenu | CommandButton | OnClick | btnG2MainMenu_Click | Yes (line 8661) |
| btnSaveRecord | CommandButton | OnClick | btnSaveRecord_Click | Yes (line 8775) |
| btnGoogleEarth | CommandButton | OnClick | btnGoogleEarth_Click | Yes (line 8672) |
| btnVegProfiling | CommandButton | OnClick | btnVegProfiling_Click | Yes (line 8809) |
| btnAudit | CommandButton | OnClick | btnAudit_Click | Yes (line 8618) |
| btnSuIntoEnv | CommandButton | OnClick | btnSuIntoEnv_Click | Yes (line 8803) |
| btnEnvIntoSu | CommandButton | OnClick | btnEnvIntoSu_Click | Yes (line 8655) |
| btnPlotPicture | ToggleButton | OnClick | btnPlotPicture_Click | Yes (line 8757) |
| btnCreateSuFromFilter | CommandButton | OnClick | btnCreateSuFromFilter_Click | Yes (line 8649) |

## 4b) Event Resolution Rules
- Access event properties with `[Event Procedure]` map by removing the `On` prefix and binding to VBA handlers.
- `AfterUpdate` -> control scope handler `<ControlName>_AfterUpdate` ; form scope handler `Form_AfterUpdate`
- `BeforeUpdate` -> control scope handler `<ControlName>_BeforeUpdate` ; form scope handler `Form_BeforeUpdate`
- `OnChange` -> control scope handler `<ControlName>_Change` ; form scope handler `Form_Change`
- `OnClick` -> control scope handler `<ControlName>_Click` ; form scope handler `Form_Click`
- `OnClose` -> control scope handler `<ControlName>_Close` ; form scope handler `Form_Close`
- `OnCurrent` -> control scope handler `<ControlName>_Current` ; form scope handler `Form_Current`
- `OnEnter` -> control scope handler `<ControlName>_Enter` ; form scope handler `Form_Enter`
- `OnExit` -> control scope handler `<ControlName>_Exit` ; form scope handler `Form_Exit`
- `OnGotFocus` -> control scope handler `<ControlName>_GotFocus` ; form scope handler `Form_GotFocus`
- `OnKeyDown` -> control scope handler `<ControlName>_KeyDown` ; form scope handler `Form_KeyDown`
- `OnLoad` -> control scope handler `<ControlName>_Load` ; form scope handler `Form_Load`
- `OnLostFocus` -> control scope handler `<ControlName>_LostFocus` ; form scope handler `Form_LostFocus`
- `OnMouseDown` -> control scope handler `<ControlName>_MouseDown` ; form scope handler `Form_MouseDown`
- `OnMouseUp` -> control scope handler `<ControlName>_MouseUp` ; form scope handler `Form_MouseUp`
- `OnNotInList` -> control scope handler `<ControlName>_NotInList` ; form scope handler `Form_NotInList`
- `OnOpen` -> control scope handler `<ControlName>_Open` ; form scope handler `Form_Open`

## 4c) Event-to-Logic Trace
| Control | Event Property | Handler | Local Handler Status | Local Calls | External Calls | Module Definitions |
|---|---|---|---|---|---|---|
| Form_2 | OnCurrent | Form_Current | lines 8830-8834 | None | None | None found |
| Form_2 | BeforeUpdate | Form_BeforeUpdate | lines 8815-8817 | None | None | None found |
| Form_2 | OnOpen | Form_Open | lines 9048-9052 | None | None | None found |
| Form_2 | OnClose | Form_Close | lines 8823-8828 | None | None | None found |
| Form_2 | OnMouseDown | Form_MouseDown | Missing local handler | None | None | None found |
| Form_2 | OnLostFocus | Form_LostFocus | Missing local handler | None | None | None found |
| Form_2 | OnClick | Form_Click | lines 8819-8821 | None | None | None found |
| Form_2 | OnLoad | Form_Load | lines 8836-8853 | None | None | None found |
| tabPages | OnChange | tabPages_Change | lines 9295-9301 | None | None | None found |
| PlotNumber | AfterUpdate | PlotNumber_AfterUpdate | lines 9100-9103 | None | None | None found |
| PlotNumber | OnMouseUp | PlotNumber_MouseUp | lines 9131-9135 | None | CommandBars | None found |
| PlotNumber | OnLostFocus | PlotNumber_LostFocus | lines 9105-9129 | None | WHERE, OpenRecordset | None found |
| ProjectID | OnGotFocus | ProjectID_GotFocus | lines 9137-9174 | None | OpenRecordset | None found |
| ProjectID | OnLostFocus | ProjectID_LostFocus | lines 9176-9178 | None | None | None found |
| ProjectID | OnNotInList | ProjectID_NotInList | lines 9180-9199 | None | None | None found |
| optCoordMethod2 | AfterUpdate | optCoordMethod2_AfterUpdate | lines 9065-9067 | None | None | None found |
| LatD2 | AfterUpdate | LatD2_AfterUpdate | lines 9004-9006 | None | None | None found |
| LatD | AfterUpdate | LatD_AfterUpdate | lines 9000-9002 | None | None | None found |
| LatMD | AfterUpdate | LatMD_AfterUpdate | lines 9016-9018 | None | None | None found |
| Latitude | AfterUpdate | Latitude_AfterUpdate | lines 9008-9010 | None | None | None found |
| LatM | AfterUpdate | LatM_AfterUpdate | lines 9012-9014 | None | None | None found |
| LatS | AfterUpdate | LatS_AfterUpdate | lines 9020-9022 | None | None | None found |
| LonD2 | AfterUpdate | LonD2_AfterUpdate | lines 9028-9030 | None | None | None found |
| LonD | AfterUpdate | LonD_AfterUpdate | lines 9024-9026 | None | None | None found |
| Longitude | AfterUpdate | Longitude_AfterUpdate | lines 9032-9034 | None | None | None found |
| LonM | AfterUpdate | LonM_AfterUpdate | lines 9036-9038 | None | None | None found |
| LonMD | AfterUpdate | LonMD_AfterUpdate | lines 9040-9042 | None | None | None found |
| LonS | AfterUpdate | LonS_AfterUpdate | lines 9044-9046 | None | None | None found |
| SubZone | OnGotFocus | SubZone_GotFocus | lines 9287-9293 | None | SubZoneList | None found |
| SiteSeries | OnEnter | SiteSeries_Enter | lines 9201-9239 | None | CurrentDb, OpenRecordset | None found |
| btnCopyToUserSU | OnClick | btnCopyToUserSU_Click | lines 8624-8627 | None | None | None found |
| btnLoadMetadata | OnClick | btnLoadMetadata_Click | lines 8684-8749 | None | Forms, Controls, OpenRecordset, _Metadata, WHERE | None found |
| optLockData | AfterUpdate | optLockData_AfterUpdate | lines 9069-9092 | None | None | None found |
| Toggle409 | OnMouseDown | Toggle409_MouseDown | lines 9303-9305 | None | None | None found |
| btnManagePictures | OnClick | btnManagePictures_Click | lines 8751-8755 | None | None | None found |
| optAssignedSuSource | AfterUpdate | optAssignedSuSource_AfterUpdate | lines 9054-9063 | None | AssignedSiteUnitList | None found |
| optProjectID | AfterUpdate | optProjectID_AfterUpdate | lines 9094-9098 | None | None | None found |
| SubVegA | OnEnter | SubVegA_Enter | lines 9257-9259 | None | None | None found |
| SubVegA | OnExit | SubVegA_Exit | lines 9261-9265 | None | None | None found |
| SubVegC | OnEnter | SubVegC_Enter | lines 9267-9269 | None | None | None found |
| SubVegC | OnExit | SubVegC_Exit | lines 9271-9275 | None | None | None found |
| SubVegD | OnEnter | SubVegD_Enter | lines 9277-9279 | None | None | None found |
| SubVegD | OnExit | SubVegD_Exit | lines 9281-9285 | None | None | None found |
| VegNotes | OnKeyDown | VegNotes_KeyDown | lines 9307-9311 | None | Pages | None found |
| btnAllowSmallEntry | OnClick | btnAllowSmallEntry_Click | lines 8591-8616 | None | Controls | None found |
| btnFindPlot | OnClick | btnFindPlot_Click | lines 9313-9326 | None | None | None found |
| btnCoverAndHeight | OnClick | btnCoverAndHeight_Click | lines 8629-8647 | None | None | None found |
| SoilHumus | OnEnter | SoilHumus_Enter | lines 9241-9243 | None | None | None found |
| SoilHumus | OnExit | SoilHumus_Exit | lines 9245-9247 | None | None | None found |
| SoilMineral | OnEnter | SoilMineral_Enter | lines 9249-9251 | None | None | None found |
| SoilMineral | OnExit | SoilMineral_Exit | lines 9253-9255 | None | None | None found |
| btnRestoreSelectedChanges | OnClick | btnRestoreSelectedChanges_Click | lines 8767-8773 | None | None | None found |
| btnG2MainMenu | OnClick | btnG2MainMenu_Click | lines 8661-8670 | None | None | None found |
| btnSaveRecord | OnClick | btnSaveRecord_Click | lines 8775-8777 | None | None | None found |
| btnGoogleEarth | OnClick | btnGoogleEarth_Click | lines 8672-8682 | None | None | None found |
| btnVegProfiling | OnClick | btnVegProfiling_Click | lines 8809-8813 | None | None | None found |
| btnAudit | OnClick | btnAudit_Click | lines 8618-8622 | None | None | None found |
| btnSuIntoEnv | OnClick | btnSuIntoEnv_Click | lines 8803-8807 | None | None | None found |
| btnEnvIntoSu | OnClick | btnEnvIntoSu_Click | lines 8655-8659 | None | None | None found |
| btnPlotPicture | OnClick | btnPlotPicture_Click | lines 8757-8765 | None | None | None found |
| btnCreateSuFromFilter | OnClick | btnCreateSuFromFilter_Click | lines 8649-8653 | None | None | None found |

## 5) VBA Procedure Graph (Form Scope)
### Audit_Click (Sub)
- Lines: 8587-8589
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: Requery

### btnAllowSmallEntry_Click (Sub)
- Lines: 8591-8616
- Local calls: None
- External calls: Controls
- Module definitions: None found in Modules/
- Me.<control> references: btnAllowSmallEntry, SubVegA, SubVegC, SubVegD, Repaint

### btnAudit_Click (Sub)
- Lines: 8618-8622
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: None

### btnCopyToUserSU_Click (Sub)
- Lines: 8624-8627
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: UserSiteUnit, BECSiteUnit, Requery

### btnCoverAndHeight_Click (Sub)
- Lines: 8629-8647
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: btnCoverAndHeight, SubVegA, SubVegAht, SubVegC, SubVegCht, SubVegD

### btnCreateSuFromFilter_Click (Sub)
- Lines: 8649-8653
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: None

### btnEnvIntoSu_Click (Sub)
- Lines: 8655-8659
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: None

### btnG2MainMenu_Click (Sub)
- Lines: 8661-8670
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: Name

### btnGoogleEarth_Click (Sub)
- Lines: 8672-8682
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: Latitude, Longitude, PlotNumber

### btnLoadMetadata_Click (Sub)
- Lines: 8684-8749
- Local calls: None
- External calls: Forms, Controls, OpenRecordset, _Metadata, WHERE
- Module definitions: None found in Modules/
- Me.<control> references: StartDate, ProjectID

### btnManagePictures_Click (Sub)
- Lines: 8751-8755
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: PlotNumber

### btnPlotPicture_Click (Sub)
- Lines: 8757-8765
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: PlotNumber

### btnRestoreSelectedChanges_Click (Sub)
- Lines: 8767-8773
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: PlotNumber, USysAudit, Requery

### btnSaveRecord_Click (Sub)
- Lines: 8775-8777
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: None

### Child162_Enter (Sub)
- Lines: 8779-8781
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: None

### Child162_Exit (Sub)
- Lines: 8783-8785
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: None

### Child164_Enter (Sub)
- Lines: 8787-8789
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: None

### Child164_Exit (Sub)
- Lines: 8791-8793
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: None

### Child165_Enter (Sub)
- Lines: 8795-8797
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: None

### Child165_Exit (Sub)
- Lines: 8799-8801
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: None

### btnSuIntoEnv_Click (Sub)
- Lines: 8803-8807
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: None

### btnVegProfiling_Click (Sub)
- Lines: 8809-8813
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: None

### Form_BeforeUpdate (Sub)
- Lines: 8815-8817
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: None

### Form_Click (Sub)
- Lines: 8819-8821
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: None

### Form_Close (Sub)
- Lines: 8823-8828
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: CurrentView

### Form_Current (Sub)
- Lines: 8830-8834
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: None

### Form_Load (Sub)
- Lines: 8836-8853
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: optProjectID, optCoordMethod2, BECSiteUnit, optAssignedSuSource

### SetCoords (Sub)
- Lines: 8855-8869
- Local calls: None
- External calls: GetLatDMS, GetLatDM, GetLongDMS, GetLongDM
- Module definitions: None found in Modules/
- Me.<control> references: LatD, Latitude, LatM, LatS, LatD2, LatMD, LonD, Longitude, LonM, LonS, LonD2, LonMD

### UpdateDecimalDegreesFromDMS (Sub)
- Lines: 8871-8880
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: LatD, LatM, LatS, Latitude, LonD, LonM, LonS, Longitude

### UpdateDecimalDegreesFromDM (Sub)
- Lines: 8882-8891
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: LatD2, LatMD, Latitude, LonD2, LonMD, Longitude

### ChangeCoordMethod (Sub)
- Lines: 8893-8998
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: Longitude, Latitude, lblLatitude, lblLongitude, lblLat, LatD, lblLatD, LatM, lblLatM, LatS, lblLatS, LatD2, LatMD, lblLatMD, lblLatD2, lblLon, LonD, lblLonD, LonM, lblLonM, LonS, lblLonS, LonD2, LonMD, lblLonMD, lblLonD2

### LatD_AfterUpdate (Sub)
- Lines: 9000-9002
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: None

### LatD2_AfterUpdate (Sub)
- Lines: 9004-9006
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: None

### Latitude_AfterUpdate (Sub)
- Lines: 9008-9010
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: None

### LatM_AfterUpdate (Sub)
- Lines: 9012-9014
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: None

### LatMD_AfterUpdate (Sub)
- Lines: 9016-9018
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: None

### LatS_AfterUpdate (Sub)
- Lines: 9020-9022
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: None

### LonD_AfterUpdate (Sub)
- Lines: 9024-9026
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: None

### LonD2_AfterUpdate (Sub)
- Lines: 9028-9030
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: None

### Longitude_AfterUpdate (Sub)
- Lines: 9032-9034
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: None

### LonM_AfterUpdate (Sub)
- Lines: 9036-9038
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: None

### LonMD_AfterUpdate (Sub)
- Lines: 9040-9042
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: None

### LonS_AfterUpdate (Sub)
- Lines: 9044-9046
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: None

### Form_Open (Sub)
- Lines: 9048-9052
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: Caption

### optAssignedSuSource_AfterUpdate (Sub)
- Lines: 9054-9063
- Local calls: None
- External calls: AssignedSiteUnitList
- Module definitions: None found in Modules/
- Me.<control> references: optAssignedSuSource, UserSiteUnit

### optCoordMethod2_AfterUpdate (Sub)
- Lines: 9065-9067
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: optCoordMethod2

### optLockData_AfterUpdate (Sub)
- Lines: 9069-9092
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: optLockData, AllowEdits, SubVegA, SubVegC, SubVegD, SoilHumus, SoilMineral, SubOther, USysAudit

### optProjectID_AfterUpdate (Sub)
- Lines: 9094-9098
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: optProjectID

### PlotNumber_AfterUpdate (Sub)
- Lines: 9100-9103
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: None

### PlotNumber_LostFocus (Sub)
- Lines: 9105-9129
- Local calls: None
- External calls: WHERE, OpenRecordset
- Module definitions: None found in Modules/
- Me.<control> references: PlotNumber

### PlotNumber_MouseUp (Sub)
- Lines: 9131-9135
- Local calls: None
- External calls: CommandBars
- Module definitions: None found in Modules/
- Me.<control> references: None

### ProjectID_GotFocus (Sub)
- Lines: 9137-9174
- Local calls: None
- External calls: OpenRecordset
- Module definitions: None found in Modules/
- Me.<control> references: optProjectID, ProjectID

### ProjectID_LostFocus (Sub)
- Lines: 9176-9178
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: None

### ProjectID_NotInList (Sub)
- Lines: 9180-9199
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: ProjectID, Refresh

### SiteSeries_Enter (Sub)
- Lines: 9201-9239
- Local calls: None
- External calls: CurrentDb, OpenRecordset
- Module definitions: None found in Modules/
- Me.<control> references: Zone, SubZone

### SoilHumus_Enter (Sub)
- Lines: 9241-9243
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: None

### SoilHumus_Exit (Sub)
- Lines: 9245-9247
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: None

### SoilMineral_Enter (Sub)
- Lines: 9249-9251
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: None

### SoilMineral_Exit (Sub)
- Lines: 9253-9255
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: None

### SubVegA_Enter (Sub)
- Lines: 9257-9259
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: None

### SubVegA_Exit (Sub)
- Lines: 9261-9265
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: None

### SubVegC_Enter (Sub)
- Lines: 9267-9269
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: None

### SubVegC_Exit (Sub)
- Lines: 9271-9275
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: None

### SubVegD_Enter (Sub)
- Lines: 9277-9279
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: None

### SubVegD_Exit (Sub)
- Lines: 9281-9285
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: None

### SubZone_GotFocus (Sub)
- Lines: 9287-9293
- Local calls: None
- External calls: SubZoneList
- Module definitions: None found in Modules/
- Me.<control> references: Zone, SubZone

### tabPages_Change (Sub)
- Lines: 9295-9301
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: tabPages, USysAudit

### Toggle409_MouseDown (Sub)
- Lines: 9303-9305
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: AllowEdits

### VegNotes_KeyDown (Sub)
- Lines: 9307-9311
- Local calls: None
- External calls: Pages
- Module definitions: None found in Modules/
- Me.<control> references: tabPages

### btnFindPlot_Click (Sub)
- Lines: 9313-9326
- Local calls: None
- External calls: None
- Module definitions: None found in Modules/
- Me.<control> references: VegPlotNumber


## 6) Data + VBA Dependencies
- Data objects inferred from SQL and source properties: AirPhotoNum, Aspect, BECSiteUnit, BedrockGeology1, BedrockGeology2, BedrockGeology3, CoarseFragLith1, CoarseFragLith2, CoarseFragLith3, Date, Ecosection, Elevation, Exposure1, Exposure2, FieldNumber, FloodingRegimeDur, FloodingRegimeFreq, FSRegionDistrict, GeoMorProSubSurf, GeoMorProSurf, HumusForm, HumusFormPhase, HumusThickness, HydroGeoSubSystem, HydroGeoSystem, Latitude, Location, LocationAccuracy, Longitude, MapUnit, MesoSlopePosition, MoistureRegime, NtsMapSheet, NutrientRegime, OfficeNotes, Photo, PlotNumber, PlotRepresenting, ProjectID, ProjectMetaData, RealmClass, RootingDepth, RootRestrictingDepth, RootRestrictingType, RootZoneParticleSize, SeepageDepth, SiteDisturbance1, SiteDisturbance2, SiteDisturbance3, SiteNotes, SitePlotQuality, SiteSeries, SiteSurveyor, SlopeGradient, SoilClassGroup, SoilClassSubGroup, SoilDrainage, SoilNotes, SoilPlotQuality, SoilSurveyor, SpeciesListComplete, StandAge, StartDate, StrataCoverHerb, StrataCoverMoss, StrataCoverShrub, StrataCoverTree, StructuralStage, SubstrateBedRock, SubstrateDecWood, SubstrateMineralSoil, SubstrateOrganicMatter, SubstrateRocks, SubstrateWater, SubZone, SuccessionalStatus, SurfaceExpSubSurf, SurfaceExpSurf, SurfaceShape, SurfaceTopographySize, SurfaceTopographyType, SurficialMaterialSubSurf, SurficialMaterialSurf, TerrainTextureSubSurf, TerrainTextureSurf, TransDistrib, UserSiteUnit, USysMasterSiteUnitList, USysTableOfLists, USysZoneList, UTMEasting, UTMNorthing, UTMZone, VegNotes, VegPlotQuality, VegSurveyor, WaterSource, XCoord, YCoord, Zone
- Global/module calls should be resolved in `Modules/*.txt` using function/sub names listed above.

## 7) Subforms (Recursive Architecture)
- frmVPics (Form.frmVPics) -> frmVPics.txt
- SubVegA (Form.SubVegA) -> SubVegA.txt
- SubVegC (Form.SubVegC) -> SubVegC.txt
- SubVegD (Form.SubVegD) -> SubVegD.txt
- SubVegAht (Form.SubVegAht) -> SubVegAht.txt
- SubVegCht (Form.SubVegCht) -> SubVegCht.txt
- USysVegOther (Form.USysVegOther) -> USysVegOther.txt
- SoilHumus (Form.SoilHumus) -> SoilHumus.txt
- SoilMineral (Form.SoilMineral) -> SoilMineral.txt
- SubOther (Form.SubOther) -> SubOther.txt
- USysAudit (Form.USysAudit) -> USysAudit.txt

## 8) Reimplementation Guidance
- Recreate this form as a component tree preserving parent-child relationships and absolute layout constraints.
- Implement event handlers by mapping Access event property -> handler naming convention (`<Control>_<Event>` or `Form_<Event>`).
- Port local procedures first; then resolve external calls in Modules to shared services/utilities.
- Treat `RecordSource`, `ControlSource`, `RowSource` and related fields as data-binding contracts.

