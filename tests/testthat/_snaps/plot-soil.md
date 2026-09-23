# soil reads require an active project and existing plot

    Code
      vpro_plot_humus_list(context, "1976071")
    Condition
      Error:
      ! A VPRO project must be active before plot data can be accessed.

---

    Code
      vpro_plot_mineral_list(context, "Missing")
    Condition
      Error:
      ! VPRO plot does not exist in the active project: Missing

# soil get uses compound plot and child identity

    Code
      vpro_plot_humus_get(context, plots[[2L]], -9201L)
    Condition
      Error:
      ! VPRO Humus record does not exist for plot 108050 and ID -9201.

---

    Code
      vpro_plot_humus_get(context, plots[[1L]], 2147483648)
    Condition
      Error:
      ! `id` must be one nonmissing signed 32-bit integer value.

# soil updates validate keys, fields, values, and audit strength

    Code
      vpro_plot_mineral_update(context, plots[[1L]], 9501L, list(ID = 9502L), user = "tester")
    Condition
      Error:
      ! Mineral record keys are immutable in soil update operations.

---

    Code
      vpro_plot_mineral_update(context, plots[[1L]], 9501L, list(NotAField = "invalid"),
      user = "tester")
    Condition
      Error:
      ! Unknown VPRO Mineral field(s): NotAField

---

    Code
      vpro_plot_mineral_update(context, plots[[1L]], 9501L, list(UpperDepth = "deep"),
      user = "tester")
    Condition
      Error:
      ! Value for `UpperDepth` is incompatible with declared SQLite type REAL.

---

    Code
      vpro_plot_mineral_update(context, plots[[2L]], 9501L, list(Comments = "wrong plot"),
      user = "tester")
    Condition
      Error:
      ! VPRO Mineral record does not exist for plot 108050 and ID 9501.

# soil row and audit writes roll back together

    Code
      vpro_plot_humus_update(context, plot_number, 9601L, list(Comment = "After"),
      user = "tester", audit_strength = 1)
    Condition
      Error:
      ! no such table: Sample_Audit

