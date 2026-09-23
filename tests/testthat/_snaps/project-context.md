# attachment enforces version and complete-family gates

    Code
      vpro_project_attach(context, old_path, "Alpha")
    Condition
      Error:
      ! VPRO project version VP07 requires conversion before it can be attached.

---

    Code
      vpro_project_attach(context, partial_path, "Partial")
    Condition
      Error:
      ! VPRO project family is incomplete; missing: Partial_Veg

# activation creates scoped views and persists current state

    Code
      vpro_project_detach(context, "Alpha")
    Condition
      Error:
      ! The active VPRO project cannot be detached.

# save-as clones the core family and rejects collisions

    Code
      vpro_project_save_as(context, "Alpha", target_path, "Beta")
    Condition
      Error:
      ! Target VPRO project tables already exist: Beta_Env, Beta_Admin, Beta_Audit, Beta_Humus, Beta_Metadata, Beta_Mineral, Beta_Other, Beta_Veg

