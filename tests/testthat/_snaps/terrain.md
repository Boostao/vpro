# terrain combination requires compatible character vectors

    Code
      vpro_terrain_combine(1, "B", "C")
    Condition
      Error:
      ! Terrain components must be character vectors.

---

    Code
      vpro_terrain_combine("A", c("B", "C"), c("D", "E", "F"))
    Condition
      Error:
      ! Terrain components must have length one or a common length.

---

    Code
      vpro_terrain_combine(character(), "B", "C")
    Condition
      Error:
      ! Terrain components must have length one or a common length.

# terrain splitting validates inputs without changing missing semantics

    Code
      vpro_terrain_split(1, "TerrainTextureSurf", 1)
    Condition
      Error:
      ! `value` must be a character vector.

---

    Code
      vpro_terrain_split("AB", "OtherField", 1)
    Condition
      Error:
      ! `field` must name a supported terrain field.

---

    Code
      vpro_terrain_split("AB", "TerrainTextureSurf", 0)
    Condition
      Error:
      ! `position` must be a positive whole number within the Access Integer range.

---

    Code
      vpro_terrain_split("AB", "TerrainTextureSurf", 1.5)
    Condition
      Error:
      ! `position` must be a positive whole number within the Access Integer range.

