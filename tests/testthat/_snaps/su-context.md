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

