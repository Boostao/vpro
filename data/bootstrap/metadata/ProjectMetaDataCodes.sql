CREATE TABLE "ProjectMetaDataCodes" (
  "PlotQualityVegetationCode" TEXT,
  "PlotQualityVegetationdescription" TEXT,
  "PlotQualitySoilsCode" TEXT,
  "PlotQualitySoilsdescription" TEXT,
  "DatumCode" TEXT,
  "Datumdescription" TEXT,
  "CoordinateSystemCode" TEXT,
  "CoordinateSystemdescription" TEXT,
  "GeoReferenceMethodCode" TEXT,
  "GeoReferenceMethoddescription" TEXT,
  "FieldCollectionStdsCode" TEXT,
  "FieldCollectionStdsdescription" TEXT,
  "VegCoverClassTypeCode" TEXT,
  "VegCoverClassTypedescription" TEXT,
  "ExtraVegFieldTypeCode" TEXT,
  "ExtraVegFieldTypedescription" TEXT
);

CREATE INDEX "idx_ProjectMetaDataCodes_CoordinateSystemCode" ON "ProjectMetaDataCodes" ("CoordinateSystemCode");
CREATE INDEX "idx_ProjectMetaDataCodes_DatumCode" ON "ProjectMetaDataCodes" ("DatumCode");
CREATE INDEX "idx_ProjectMetaDataCodes_ExtraVegFieldTypeCode" ON "ProjectMetaDataCodes" ("ExtraVegFieldTypeCode");
CREATE INDEX "idx_ProjectMetaDataCodes_FieldCollectionStdsCode" ON "ProjectMetaDataCodes" ("FieldCollectionStdsCode");
CREATE INDEX "idx_ProjectMetaDataCodes_GeoReferenceMethodCode" ON "ProjectMetaDataCodes" ("GeoReferenceMethodCode");
CREATE INDEX "idx_ProjectMetaDataCodes_PlotQualitySoilsCode" ON "ProjectMetaDataCodes" ("PlotQualitySoilsCode");
CREATE INDEX "idx_ProjectMetaDataCodes_PlotQualityVegetationCode" ON "ProjectMetaDataCodes" ("PlotQualityVegetationCode");
CREATE UNIQUE INDEX "uidx_ProjectMetaDataCodes_VegCoverClassTypeCode" ON "ProjectMetaDataCodes" ("VegCoverClassTypeCode");

/*
Access metadata notes for ProjectMetaDataCodes:
- VegCoverClassTypeCode is unique in Access.
- The other code fields are indexed with duplicates allowed in Access.
*/