# creation respects existing families and unknown reference descriptions

    Code
      vpro_project_create(path, "Second", "tester", reference_path)
    Condition
      Error:
      ! Target VPRO project tables already exist: Second_Env, Second_Admin, Second_Audit, Second_Humus, Second_Metadata, Second_Mineral, Second_Other, Second_Veg

---

    Code
      vpro_project_create(path, "Sample", "tester", reference_path)
    Condition
      Error:
      ! `Sample` is reserved and cannot be used as a new project name.

# bootstrap failure rolls back tables and metadata in existing database

    Code
      vpro_project_create(path, "Failed", "tester")
    Condition
      Error:
      ! blocked

