# succession conversion preserves rows and produces a restorable WAL-safe backup

    Code
      vpro_project_convert_succession(path, "Alpha", 2022, tempfile(fileext = ".db"),
      authorize)
    Condition
      Error:
      ! Expected unconverted succession state; found converted.

# partial recovery adds only Env flag and refuses unexpected years

    Code
      vpro_project_convert_succession(path, "Alpha", 2022, tempfile(fileext = ".db"),
      authorize)
    Condition
      Error:
      ! Succession operation requires `convert_succession` authorization.

---

    Code
      vpro_project_recover_succession(mixed, "Alpha", tempfile(fileext = ".db"),
      authorize)
    Condition
      Error:
      ! Partial recovery requires one nonmissing valid existing year; vegetation is unchanged.

---

    Code
      vpro_project_recover_succession(mixed, "Alpha", tempfile(fileext = ".db"),
      authorize)
    Condition
      Error:
      ! Partial recovery requires one nonmissing valid existing year; vegetation is unchanged.

# preflight rejects protected targets and requires explicit authorization

    Code
      vpro_project_convert_succession(path, "Alpha", 2021, tempfile(fileext = ".db"),
      authorize)
    Condition
      Error:
      ! Succession operation requires `convert_succession` authorization.

---

    Code
      vpro_project_convert_succession(path, "Sample", 2021, tempfile(fileext = ".db"),
      authorize)
    Condition
      Error:
      ! Sample cannot be converted.

---

    Code
      vpro_project_convert_succession(path, "Alpha", 0, tempfile(fileext = ".db"),
      authorize)
    Condition
      Error:
      ! Succession year must be a whole calendar year from 1 to 9999.

---

    Code
      vpro_project_convert_succession(path, "Alpha", 2021, path, authorize)
    Condition
      Error:
      ! Backup path must name a new file in an existing directory, distinct from the project.

---

    Code
      vpro_project_succession_status(system.file("extdata", "projects", "Sample.db",
        package = "vpro"), "Missing")
    Condition
      Error:
      ! Incomplete VPRO project family: Missing_Admin, Missing_Audit, Missing_Env, Missing_Humus, Missing_Metadata, Missing_Mineral, Missing_Other, Missing_Veg

