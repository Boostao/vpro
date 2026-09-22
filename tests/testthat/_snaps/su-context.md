# master SU policy is explicit and direct attachment is authorized

    Code
      vpro_su_mark_master(path, "Reference", deny)
    Condition
      Error:
      ! Marking a master VPRO SU requires `manage_master_su` authorization.

---

    Code
      vpro_su_attach(context, path, "Reference")
    Condition
      Error:
      ! Direct attachment of a master VPRO SU requires `attach_master_su` authorization; create a working copy instead.

# master working copies preserve data and provenance without attachment

    Code
      vpro_su_create_working_copy(context, source_path, "AnalystCopy", source_path,
        "SecondCopy")
    Condition
      Error:
      ! A VPRO working copy can only be created from an SU explicitly marked as master.

# SU activation filters the project and returns diagnostics

    Code
      vpro_su_detach(context, "Subset")
    Condition
      Error:
      ! The active VPRO SU cannot be detached.

# SU save-as preserves rows, indexes, and metadata without changing state

    Code
      vpro_su_save_as(context, "Subset", target_path, "Copy")
    Condition
      Error:
      ! Target VPRO SU table already exists: Copy_SU

---

    Code
      vpro_su_save_as(context, "Subset", tempfile(fileext = ".db"), "NewMaster",
      kind = "master")
    Condition
      Error:
      ! Creating a master VPRO SU requires `create_master_su` authorization.

