# diagnostic input must contain ordered named crosstab codes

    Code
      vpro_diagnostic_classify(character())
    Condition
      Error:
      ! `unit_codes` must be a nonempty named character vector with distinct, nonempty unit names.

---

    Code
      vpro_diagnostic_classify("3 - 5")
    Condition
      Error:
      ! `unit_codes` must be a nonempty named character vector with distinct, nonempty unit names.

---

    Code
      vpro_diagnostic_classify(c(A = "3 - 5", A = "2 - 3"))
    Condition
      Error:
      ! `unit_codes` must be a nonempty named character vector with distinct, nonempty unit names.

---

    Code
      vpro_diagnostic_classify(c(A = "3 - 5", "2 - 3"))
    Condition
      Error:
      ! `unit_codes` must be a nonempty named character vector with distinct, nonempty unit names.

---

    Code
      vpro_diagnostic_classify(c(A = "3-5"))
    Condition
      Error:
      ! Nonmissing `unit_codes` must have the form '1 - +' through '5 - 9'.

---

    Code
      vpro_diagnostic_classify(c(A = "0 - 5"))
    Condition
      Error:
      ! Nonmissing `unit_codes` must have the form '1 - +' through '5 - 9'.

---

    Code
      vpro_diagnostic_classify(c(A = "3 - 0"))
    Condition
      Error:
      ! Nonmissing `unit_codes` must have the form '1 - +' through '5 - 9'.

---

    Code
      vpro_diagnostic_classify(c(A = "3 - X"))
    Condition
      Error:
      ! Nonmissing `unit_codes` must have the form '1 - +' through '5 - 9'.

---

    Code
      vpro_diagnostic_classify(c(A = 3))
    Condition
      Error:
      ! `unit_codes` must be a nonempty named character vector with distinct, nonempty unit names.

