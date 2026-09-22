# audit restoration rejects stale current values and invalid targets

    Code
      vpro_plot_audit_restore(context, plot_number, stale_event)
    Condition
      Error:
      ! The target field no longer matches the audit event's `AfterEdit` value; restoration was not applied.

---

    Code
      vpro_plot_audit_restore(context, plot_number, transform(stale_event,
        audit_rowid = 999999999))
    Condition
      Error:
      ! VPRO audit event does not exist for the active project and plot: 999999999

---

    Code
      vpro_plot_audit_restore(context, plot_number, transform(stale_event, User = "changed fingerprint"))
    Condition
      Error:
      ! The selected audit event no longer matches the active database.

# ambiguous child identity prevents restoration

    Code
      vpro_plot_audit_restore(context, plot_number, event)
    Condition
      Error:
      ! VPRO veg record identity is not unique for plot 00337 and ID 2000000010.

# protected Admin restoration requires authorization

    Code
      vpro_plot_audit_restore(unauthorized, plot_number, event)
    Condition
      Error:
      ! Restoring protected VPRO Admin field requires `update_protected_plot_field` authorization: BECSiteUnit

