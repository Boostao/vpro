# value conversion APIs validate inputs

    Code
      vpro_presence_class("0.5")
    Condition
      Error:
      ! `presence` must be a nonempty numeric vector.

---

    Code
      vpro_prominence_class(1:2, 1:3)
    Condition
      Error:
      ! Inputs must have a common length or length one.

---

    Code
      vpro_prominence_class(1, 1, return_score = NA)
    Condition
      Error:
      ! `return_score` must be TRUE or FALSE.

---

    Code
      vpro_significance_class(Inf)
    Condition
      Error:
      ! `significance` must contain only finite values or NA.

---

    Code
      vpro_round_minimum(1, digits = 1.5)
    Condition
      Error:
      ! `digits` must be one nonnegative integer.

---

    Code
      vpro_round_minimum(1, minimum = Inf)
    Condition
      Error:
      ! `minimum` must be one finite numeric value.

