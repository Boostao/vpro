# succession detection rejects missing inputs rather than misclassifying

    Code
      vpro_project_is_successional(path, "Alpha")
    Condition
      Error:
      ! VPRO vegetation table does not exist: Alpha_Veg

---

    Code
      vpro_project_is_successional("missing.db", "Alpha")
    Condition
      Error:
      ! VPRO project database does not exist: missing.db

---

    Code
      vpro_project_is_successional(path, "not valid")
    Condition
      Error:
      ! VPRO project names must start with a letter, contain only letters, numbers, and underscores, and be at most 31 characters.

