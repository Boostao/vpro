# environment report validates inputs, active context, and source immutability

    Code
      vpro_report_environment(context)
    Condition
      Error:
      ! A VPRO project must be active before plot data can be accessed.

---

    Code
      vpro_report_environment(context, c("P1", NA_character_))
    Condition
      Error:
      ! `plot_numbers` must be a character vector of non-missing, nonblank plot numbers.

---

    Code
      vpro_report_environment(context, "")
    Condition
      Error:
      ! `plot_numbers` must be a character vector of non-missing, nonblank plot numbers.

---

    Code
      vpro_report_environment(context, 1)
    Condition
      Error:
      ! `plot_numbers` must be a character vector of non-missing, nonblank plot numbers.

