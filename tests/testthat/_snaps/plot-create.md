# plot creation rejects collisions and invalid requests without mutation

    Code
      vpro_plot_create(context, existing)
    Condition
      Error:
      ! VPRO plot already exists in the active project: 00337

---

    Code
      vpro_plot_create(context, "NEW1005", env = list(PlotNumber = "OTHER"))
    Condition
      Error:
      ! Plot keys are managed by `vpro_plot_create()`.

---

    Code
      vpro_plot_create(context, "NEW1005", admin = list(Plot = "OTHER"))
    Condition
      Error:
      ! Plot keys are managed by `vpro_plot_create()`.

---

    Code
      vpro_plot_create(context, "NEW1005", env = list(NotAField = "invalid"))
    Condition
      Error:
      ! Unknown VPRO Env field(s): NotAField

---

    Code
      vpro_plot_create(context, "NEW1005", admin = list(StartDate = 1800L))
    Condition
      Error:
      ! `StartDate` must be between 1900 and 2500.

---

    Code
      vpro_plot_create(context, "NEW1005", env = list(Elevation = "high"))
    Condition
      Error:
      ! Value for `Elevation` is incompatible with declared SQLite type SMALLINT.

# legacy incomplete pairs are diagnosed and left untouched

    Code
      vpro_plot_create(context, "ORPHENV")
    Condition
      Error:
      ! VPRO plot has an incomplete Env/Admin pair and cannot be created safely: ORPHENV

---

    Code
      vpro_plot_create(context, "ORPHADM")
    Condition
      Error:
      ! VPRO plot has an incomplete Env/Admin pair and cannot be created safely: ORPHADM

# protected Admin values require explicit authorization

    Code
      vpro_plot_create(denied, "NEW1007", admin = list(BECSiteUnit = "restricted"))
    Condition
      Error:
      ! Creating protected VPRO Admin field requires `update_protected_plot_field` authorization: BECSiteUnit

