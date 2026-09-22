# plot deletion rejects missing and incomplete plot pairs

    Code
      vpro_plot_delete(context, "MISSING")
    Condition
      Error:
      ! VPRO plot does not exist in the active project: MISSING

---

    Code
      vpro_plot_delete(context, "DEL0001")
    Condition
      Error:
      ! VPRO plot must have exactly one Env row and one Admin row: DEL0001

