// Unambiguous source field captions from frmProjectMetaData (UsysMetadata) in
// app/resources/project-metadata-layout.json, decoupled from the 360 kB layout JSON
// so ProjectMetadataEditor and Restore panels do not pull raw Access geometry.
const unambiguousSourceCaptions: Readonly<Record<string, string>> = {
  allspecs: 'Species table',
  coordinatesystem: 'Coordinate System',
  coordinatingagency: 'Coordinating Agency',
  cover10description: 'Ep',
  cover8description: 'Dw',
  cover9description: 'Dr',
  covera1description: 'A1',
  covera2description: 'A2',
  covera3description: 'A3',
  coveradescription: 'A',
  coverb1description: 'B1',
  coverb2adescription: 'B3',
  coverb2bdescription: 'B4',
  coverb2cdescription: 'B5',
  coverb2description: 'B2',
  coverbdescription: 'B',
  covercdescription: 'C',
  coverddescription: 'D',
  datum: 'Datum',
  ecosyscollectionstandard: 'Collection Standard',
  fieldcompanyagency: 'Field Company/Agency',
  fielddatacollectionteam: 'Field Data Collection Team',
  fieldleader: 'Field Leader',
  geographicstudyarea: 'Geographic Study Area',
  geographicstudyregion: 'Region/District',
  georefmethod: 'Georeference Method',
  mensurationmethod: 'Mensuration Method',
  numberoffs882plots: 'No. of Project FS882 Plots',
  numberofsitevisits: 'No. of Site Visits',
  plotmethod: 'Plot Method/Size',
  projectid: 'Project ID',
  projectpurpose: 'Purpose of Project',
  projecttitle: 'Project Title',
  projecttype: 'Project Type',
  proponentfunder: 'Proponent/Funder',
  tableoflists: 'Table Of Lists',
  vegcovermethod: 'Veg Cover Method',
};

const labels: Record<string, string> = {
  StartDate: 'Start year', EndDate: 'End year', BAPID: 'BAP ID',
  ExtraVegFieldDescription: 'Extra vegetation field description', DataCustodian: 'Data custodian',
  StorageLocation: 'Storage location', Notes: 'Notes', DateLastEdited: 'Last edited',
  CollectedCompleteOther: 'Other data collected completely', CollectedPartialOther: 'Other data collected partially',
  CollectedNoneOther: 'Other data not collected',
};
const categories: Record<string, string> = {
  Site: 'Site', Veg: 'Vegetation', Soil: 'Soil', Terrain: 'Terrain', Mens: 'Mensuration',
  CWD: 'Coarse woody debris', WildTree: 'Wildlife trees', SoilChem: 'Soil chemistry',
  WildlifeHabitatAssessment: 'Wildlife habitat assessment',
};
export function metadataLabel(name: string): string {
  if (Object.hasOwn(labels, name)) return labels[name];
  for (const prefix of ['Collected', 'DataQuality']) {
    if (name.startsWith(prefix) && Object.hasOwn(categories, name.slice(prefix.length))) {
      return `${categories[name.slice(prefix.length)]} — ${prefix === 'Collected' ? 'collection' : 'data quality'}`;
    }
  }
  if (name.endsWith('Other')) return `${metadataLabel(name.slice(0, -5))} — other`;
  const key = name.toLowerCase();
  if (!Object.hasOwn(unambiguousSourceCaptions, key)) {
    throw new Error(`Metadata ${name} has no unambiguous source/associated label.`);
  }
  const caption = unambiguousSourceCaptions[key];
  return name.startsWith('Cover') ? `${caption} layer description` : caption;
}
export const metadataGroups = [
  { title: 'Project and field team', names: ['ProjectTitle', 'ProjectType', 'ProjectTypeOther', 'EcosysCollectionStandard',
    'EcosysCollectionStandardOther', 'CoordinatingAgency', 'ProponentFunder', 'FieldCompanyAgency', 'FieldLeader',
    'FieldDataCollectionTeam', 'ProjectPurpose', 'GeographicStudyArea', 'GeographicStudyRegion', 'StartDate', 'EndDate',
    'NumberOfFS882Plots', 'NumberOfSiteVisits', 'BAPID'] },
  { title: 'Field methods', names: ['VegCoverMethod', 'VegCoverMethodOther', 'PlotMethod', 'PlotMethodOther',
    'MensurationMethod', 'MensurationMethodOther', 'ExtraVegFieldDescription'] },
  { title: 'Collection and data quality', names: Object.keys(categories).flatMap(name => [`Collected${name}`, `DataQuality${name}`])
    .concat(['CollectedCompleteOther', 'CollectedPartialOther', 'CollectedNoneOther']) },
  { title: 'Georeferencing', names: ['GeoRefMethod', 'GeoRefMethodOther', 'Datum', 'DatumOther', 'CoordinateSystem', 'CoordinateSystemOther'] },
  { title: 'Vegetation layer descriptions', names: ['CoverADescription', 'CoverA1Description', 'CoverA2Description',
    'CoverA3Description', 'CoverBDescription', 'CoverB1Description', 'CoverB2Description', 'CoverB2aDescription',
    'CoverB2bDescription', 'CoverB2cDescription', 'CoverCDescription', 'CoverDDescription', 'Cover8Description',
    'Cover9Description', 'Cover10Description'] },
  { title: 'Custody and notes', names: ['DataCustodian', 'StorageLocation', 'Notes'] },
];
