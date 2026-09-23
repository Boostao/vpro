# terrain diagnostics distinguish missing table and invalid paths

    Code
      vpro_terrain_inspect_schema("missing.db", "Old")
    Condition
      Error:
      ! VPRO project database does not exist: missing.db

---

    Code
      vpro_terrain_inspect_schema(path, "bad project")
    Condition
      Error:
      ! VPRO project names must start with a letter, contain only letters, numbers, and underscores, and be at most 31 characters.

