# vegetation identity ambiguity is rejected without mutation

    Code
      vpro_plot_vegetation_get(context, plot_number, 2000000004)
    Condition
      Error:
      ! VPRO vegetation record identity is not unique for plot 00337 and ID 2000000004.

---

    Code
      vpro_plot_vegetation_update(context, plot_number, 2000000004, list(Cover1 = 5),
      user = "editor")
    Condition
      Error:
      ! VPRO vegetation record identity is not unique for plot 00337 and ID 2000000004.

---

    Code
      vpro_plot_vegetation_delete(context, plot_number, 2000000004)
    Condition
      Error:
      ! VPRO vegetation record identity is not unique for plot 00337 and ID 2000000004.

# vegetation values and species are validated

    Code
      vpro_plot_vegetation_create(context, plot_number, list(Cover1 = 1), user = "creator")
    Condition
      Error:
      ! `values$Species` must be one nonblank character value of at most 8 characters.

---

    Code
      vpro_plot_vegetation_create(context, plot_number, list(Species = "TOO-LONG-CODE",
        Cover1 = 1), user = "creator")
    Condition
      Error:
      ! `values$Species` must be one nonblank character value of at most 8 characters.

---

    Code
      vpro_plot_vegetation_update(context, plot_number, created$vegetation$ID, list(
        Cover1 = "high"), user = "editor")
    Condition
      Error:
      ! Value for `Cover1` is incompatible with declared SQLite type REAL.

