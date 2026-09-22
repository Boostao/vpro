# plot reads require an active project and exact Env/Admin rows

    Code
      vpro_plot_get(context, "1976071")
    Condition
      Error:
      ! A VPRO project must be active before plot data can be accessed.

---

    Code
      vpro_plot_get(context, "Missing")
    Condition
      Error:
      ! VPRO plot does not exist in the active project: Missing

# plot update validates fields and rolls back the entire request

    Code
      vpro_plot_update(context, plot_number, env = list(Location = "Must roll back"),
      admin = list(NotAField = "invalid"), user = "tester")
    Condition
      Error:
      ! Unknown VPRO Admin field(s): NotAField

---

    Code
      vpro_plot_update(context, plot_number, env = list(PlotNumber = "NEW"), user = "tester")
    Condition
      Error:
      ! Plot keys are immutable in `vpro_plot_update()`.

---

    Code
      vpro_plot_update(context, plot_number, admin = list(BECSiteUnit = "restricted"),
      user = "tester")
    Condition
      Error:
      ! Updating protected VPRO Admin field requires `update_protected_plot_field` authorization: BECSiteUnit

---

    Code
      vpro_plot_update(context, plot_number, admin = list(StartDate = 1800L), user = "tester")
    Condition
      Error:
      ! `StartDate` must be between 1900 and 2500.

---

    Code
      vpro_plot_update(context, plot_number, env = list(Elevation = "not numeric"),
      user = "tester")
    Condition
      Error:
      ! Value for `Elevation` is incompatible with declared SQLite type SMALLINT.

