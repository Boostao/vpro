# plot renumbering cascades the complete project family and attached SUs

    Code
      vpro_plot_get(context, source)
    Condition
      Error:
      ! VPRO plot does not exist in the active project: 108050

# plot renumbering rejects invalid sources and target collisions

    Code
      vpro_plot_renumber(context, source, source)
    Condition
      Error:
      ! `new_plot_number` must differ from `plot_number`.

---

    Code
      vpro_plot_renumber(context, "MISSING", "RNP0002")
    Condition
      Error:
      ! VPRO plot does not exist in the active project: MISSING

---

    Code
      vpro_plot_renumber(context, source, existing)
    Condition
      Error:
      ! VPRO plot already exists in the active project: 00337

# plot renumbering rejects incomplete and orphan target families

    Code
      vpro_plot_renumber(context, source, "RNP0003")
    Condition
      Error:
      ! VPRO target plot has an incomplete Env/Admin pair and cannot be used safely: RNP0003

---

    Code
      vpro_plot_renumber(context, source, "RNP0004")
    Condition
      Error:
      ! VPRO target plot has orphan dependent rows in: Audit

# attached SU collisions fail before project mutation

    Code
      vpro_plot_renumber(context, source, target)
    Condition
      Error:
      ! Attached VPRO SU already contains both source and target plot numbers: External

