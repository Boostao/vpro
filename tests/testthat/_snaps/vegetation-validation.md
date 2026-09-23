# vegetation validation checks context and reference inputs

    Code
      vpro_validate_vegetation_codes(context, reference_path)
    Condition
      Error:
      ! A VPRO project must be active before plot data can be accessed.

---

    Code
      vpro_validate_vegetation_codes(context, "missing.db")
    Condition
      Error:
      ! VPRO species-reference database does not exist: missing.db

---

    Code
      vpro_validate_vegetation_codes(context, reference_path, use_active_su = NA)
    Condition
      Error:
      ! `use_active_su` must be TRUE or FALSE.

---

    Code
      vpro_validate_vegetation_codes(context, invalid_reference)
    Condition
      Error:
      ! VPRO species-reference table does not exist: USysAllSpecs

