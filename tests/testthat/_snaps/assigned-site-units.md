# assigned choices use the active project view and physical SU rows

    Code
      vpro_assigned_site_units(context, "su")
    Condition
      Error:
      ! An active VPRO SU is required for SU site-unit choices.

# master choices use the level-11 canonical list and explicit reference

    Code
      vpro_assigned_site_units(context, "other", path)
    Condition
      Error in `match.arg()`:
      ! 'arg' should be one of "project", "master", "su"

---

    Code
      vpro_assigned_site_units(context, "master", tempfile())
    Condition
      Error:
      ! VPRO master site-unit database does not exist.

---

    Code
      vpro_assigned_site_units(context, "project")
    Condition
      Error:
      ! A VPRO project must be active before plot data can be accessed.

