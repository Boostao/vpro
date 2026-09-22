# long-report filtering does not require a BEC field

    Code
      vpro_filter_plot_quality(context, reference_path, bec_min = "1")
    Condition
      Error:
      ! VPRO Admin table is missing quality fields: BEC_Use

# quality filtering validates context, options, and reference metadata

    Code
      vpro_filter_plot_quality(context, reference_path)
    Condition
      Error:
      ! An active VPRO SU is required for report quality filtering.

---

    Code
      vpro_filter_plot_quality(context, reference_path, site_min = "Unknown")
    Condition
      Error:
      ! `site_min` is not a configured DataQuality level: Unknown

---

    Code
      vpro_filter_plot_quality(context, reference_path, include_bec_missing = NA)
    Condition
      Error:
      ! `include_bec_missing` must be TRUE or FALSE.

---

    Code
      vpro_filter_plot_quality(context, "missing.db")
    Condition
      Error:
      ! VPRO list-reference database does not exist: missing.db

---

    Code
      vpro_filter_plot_quality(context, duplicate_path)
    Condition
      Error:
      ! VPRO DataQuality levels contain duplicate labels: good
