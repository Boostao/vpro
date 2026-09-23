test_that("terrain combination ignores null components but not empty results", {
  expect_identical(
    vpro_terrain_combine(c("A", NA, "", "FG"), c("B", "B", NA, NA), c("C", NA, "", "Z")),
    c("ABC", "B", NA_character_, "FGZ")
  )
  expect_identical(vpro_terrain_combine(NA_character_, NA_character_, NA_character_), NA_character_)
  expect_identical(vpro_terrain_combine("", "", ""), NA_character_)
  expect_identical(vpro_terrain_combine(character(), character(), character()), character())
  expect_identical(vpro_terrain_combine("A", c("B", "C"), NA_character_), c("AB", "AC"))
})

test_that("terrain combination requires compatible character vectors", {
  expect_snapshot(error = TRUE, vpro_terrain_combine(1, "B", "C"))
  expect_snapshot(error = TRUE, vpro_terrain_combine("A", c("B", "C"), c("D", "E", "F")))
  expect_snapshot(error = TRUE, vpro_terrain_combine(character(), "B", "C"))
})

test_that("terrain splitting follows Access one-based component positions", {
  expect_identical(vpro_terrain_split(c("ABC", "A", "", NA_character_), "TerrainTextureSurf", 2), c("B", "", "", ""))
  expect_identical(vpro_terrain_split("ABC", "SurfaceExpSubSurf", 3), "C")
  expect_identical(vpro_terrain_split("FGZ", "GeoMorProSurf", 2), "G")
})

test_that("surficial-material FG is a single two-character component", {
  expect_identical(vpro_terrain_split(c("AFGB", "FGBC", "BCFG", "ABC"), "SurficialMaterialSurf", 1), c("A", "FG", "B", "A"))
  expect_identical(vpro_terrain_split(c("AFGB", "FGBC", "BCFG", "ABC"), "SurficialMaterialSubSurf", 2), c("FG", "B", "C", "B"))
  expect_identical(vpro_terrain_split(c("AFGB", "FGBC", "BCFG", "ABC"), "SurficialMaterialSurf", 3), c("B", "C", "FG", "C"))
  expect_identical(vpro_terrain_split(c("FGFGX", "fgX"), "SurficialMaterialSurf", 2), c("F", "g"))
})

test_that("terrain splitting validates inputs without changing missing semantics", {
  expect_identical(vpro_terrain_split(character(), "TerrainTextureSurf", 1), character())
  expect_snapshot(error = TRUE, vpro_terrain_split(1, "TerrainTextureSurf", 1))
  expect_snapshot(error = TRUE, vpro_terrain_split("AB", "OtherField", 1))
  expect_snapshot(error = TRUE, vpro_terrain_split("AB", "TerrainTextureSurf", 0))
  expect_snapshot(error = TRUE, vpro_terrain_split("AB", "TerrainTextureSurf", 1.5))
})
