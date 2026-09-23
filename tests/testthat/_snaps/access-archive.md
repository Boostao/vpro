# Access archive preserves tables and descriptions without altering source

    Code
      vpro_access_archive(copy, archive_path, max_rows_per_table = 2000L)
    Condition
      Error:
      ! VPRO SQLite output must be unused, outside source files, and in an existing directory.

---

    Code
      vpro_access_archive(copy, file.path(root, "too-small.db"), max_rows_per_table = 1L)
    Condition
      Error:
      ! Access tables exceed the per-table in-memory row limit: LayerCode, LifeformCodes, Sample_Admin, Sample_Audit, Sample_Env, Sample_Herbarium, Sample_Hierarchy, Sample_Humus, Sample_Lump, Sample_Metadata, Sample_Mineral, Sample_Profile, Sample_SU, Sample_Theme, Sample_Veg, SampleVeg_Profile, tblHelpSubjects, tblSppCodesAndCover, tblWhatsNew, UnitLevelCodes, USysComboFields, USysComparePlotAssignments, USysExportToR, USysRibbonDescriptions, USysRibbons, USysServicePacks, USysShortVegSummaryFieldList, USysSubzoneMatrixLabels, USysThemeTable, USysUserLog, USysUserRestrictions, CodesToReplace, SppListUnique, tblTaxonLevel, topmostSubform, USysSppAttributeSummary

# older Access families remain archives rather than VP08 projects

    Code
      vpro_access_promote_vp08(archive, "VProXP", promoted)
    Condition
      Error:
      ! Access archive lacks a complete eight-table project family: VProXP

# VP08 promotion preserves data and refuses uncertain conversions

    Code
      vpro_access_promote_vp08(archive, "Sample", promoted)
    Condition
      Error:
      ! VPRO SQLite output must be unused, outside source files, and in an existing directory.

---

    Code
      vpro_access_promote_vp08(archive, "Sample", older)
    Condition
      Error:
      ! Only an Access project with VP08 Env description can be promoted.

---

    Code
      vpro_access_promote_vp08(archive, "Sample", drift)
    Condition
      Error:
      ! VP08 field names/order differ from the canonical template: Sample_Admin

