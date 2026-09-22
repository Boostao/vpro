# schema comparison validates projects and template resources

    Code
      vpro_project_compare_schema("missing.db", "Alpha")
    Condition
      Error:
      ! VPRO project database does not exist: missing.db

---

    Code
      vpro_project_compare_schema(path, "not valid")
    Condition
      Error:
      ! VPRO project names must start with a letter, contain only letters, numbers, and underscores, and be at most 31 characters.

---

    Code
      vpro_project_compare_schema(path, "Alpha", "missing-template.db")
    Condition
      Error:
      ! VPRO template database does not exist: missing-template.db

---

    Code
      vpro_project_compare_schema(path, "Alpha", path, "Absent")
    Condition
      Error:
      ! VPRO template table does not exist: Absent_Admin
