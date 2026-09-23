# profile maximum rejects ambiguous or invalid cover inputs

    Code
      vpro_profile_max_cover("1", 0, 0, 0, 0, 0, 0, 0, 0, 0)
    Condition
      Error:
      ! `cover1` must be a nonempty numeric vector.

---

    Code
      vpro_profile_max_cover(numeric(), 0, 0, 0, 0, 0, 0, 0, 0, 0)
    Condition
      Error:
      ! `cover1` must be a nonempty numeric vector.

---

    Code
      vpro_profile_max_cover(Inf, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    Condition
      Error:
      ! `cover1` must contain only finite values or NA.

---

    Code
      vpro_profile_max_cover(1:2, 1:3, 0, 0, 0, 0, 0, 0, 0, 0)
    Condition
      Error:
      ! Inputs must have a common length or length one.

