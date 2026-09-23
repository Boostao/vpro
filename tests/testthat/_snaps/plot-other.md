# Other rows require an active project and existing plot

    Code
      vpro_plot_other_list(context, "1976071")
    Condition
      Error:
      ! A VPRO project must be active before plot data can be accessed.

---

    Code
      vpro_plot_other_list(context, "Missing")
    Condition
      Error:
      ! VPRO plot does not exist in the active project: Missing

# Other update validates identity, keys, fields, and values

    Code
      vpro_plot_other_update(context, plots[[2]], 9201L, list(DataItem = "Wrong plot"),
      user = "tester")
    Condition
      Error:
      ! VPRO Other record does not exist for plot 108050 and ID 9201.

---

    Code
      vpro_plot_other_update(context, plots[[1]], 9999L, list(DataItem = "Missing"),
      user = "tester")
    Condition
      Error:
      ! VPRO Other record does not exist for plot 00337 and ID 9999.

---

    Code
      vpro_plot_other_update(context, plots[[1]], 2147483648, list(DataItem = "Invalid ID"),
      user = "tester")
    Condition
      Error:
      ! `id` must be one nonmissing signed 32-bit integer value.

---

    Code
      vpro_plot_other_update(context, plots[[1]], 9201L, list(ID = 9202L), user = "tester")
    Condition
      Error:
      ! Other record keys are immutable in `vpro_plot_other_update()`.

---

    Code
      vpro_plot_other_update(context, plots[[1]], 9201L, list(NotAField = "invalid"),
      user = "tester")
    Condition
      Error:
      ! Unknown VPRO Other field(s): NotAField

---

    Code
      vpro_plot_other_update(context, plots[[1]], 9201L, list(UserFlag1 = "yes"),
      user = "tester")
    Condition
      Error:
      ! Value for `UserFlag1` is incompatible with declared SQLite type BOOLEAN.

