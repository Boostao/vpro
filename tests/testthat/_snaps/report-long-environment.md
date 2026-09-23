# long environment report validates active scope, empty membership, and schemas

    Code
      vpro_report_long_environment(context, reference)
    Condition
      Error:
      ! An active VPRO SU is required for the long environment report.

---

    Code
      vpro_report_long_environment(context, reference)
    Condition
      Error:
      ! VPRO long environment report Env table is missing fields: FieldNumber

# long environment report rejects ambiguous Env and Admin keys

    Code
      vpro_report_long_environment(context, reference)
    Condition
      Error:
      ! VPRO long environment report cannot safely use ambiguous duplicate Env keys.

---

    Code
      vpro_report_long_environment(context, reference)
    Condition
      Error:
      ! VPRO long environment report cannot safely use ambiguous duplicate Admin keys.

# long environment report validates the reference table and path

    Code
      vpro_report_long_environment(context, tempfile(fileext = ".db"))
    Condition
      Error:
      ! VPRO long environment reference database does not exist.

---

    Code
      vpro_report_long_environment(context, dirname(reference))
    Condition
      Error:
      ! VPRO long environment reference database does not exist.

---

    Code
      vpro_report_long_environment(context, reference)
    Condition
      Error:
      ! VPRO master site-unit table is missing fields: SiteSeriesLongName

