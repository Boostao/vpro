# export codes do not silently coerce unknown input types

    Code
      vpro_export_code(numeric())
    Condition
      Error:
      ! `code` must be a nonempty character vector.

---

    Code
      vpro_export_code(NA)
    Condition
      Error:
      ! `code` must be a nonempty character vector.

---

    Code
      vpro_export_code(1)
    Condition
      Error:
      ! `code` must be a nonempty character vector.

---

    Code
      vpro_export_code(list("BW", NA))
    Condition
      Error:
      ! `code` must be a nonempty character vector.

