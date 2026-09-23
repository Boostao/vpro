# coordinate APIs reject invalid numeric inputs

    Code
      vpro_coordinate_decimal(character())
    Condition
      Error:
      ! `degrees` must be a nonempty numeric vector.

---

    Code
      vpro_coordinate_decimal(1:2, 1:3)
    Condition
      Error:
      ! Coordinate components must have a common length or length one.

---

    Code
      vpro_coordinate_dms(Inf)
    Condition
      Error:
      ! `value` must contain only finite values or NA.

---

    Code
      vpro_coordinate_dm("49.5")
    Condition
      Error:
      ! `value` must be a nonempty numeric vector.

