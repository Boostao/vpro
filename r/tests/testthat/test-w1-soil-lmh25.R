test_that("horizon classifiers strip discontinuity prefixes and treat Hydric/Limno/Cumulo as wetland (ENG-XCUT-005)", {
  expect_identical(
    vpro_classify_horizon(c("Of", "2Of", "IIOf", "Om", "Hydric", "Limno", "Cumulo", "Lv", "2L", "F", "H", "Ah", "IXAh", "Bm", "", NA)),
    c(rep("wetland_organic", 7), rep("upland_organic", 4), rep("mineral", 5))
  )
  expect_identical(vpro_classify_humus_lmh25("2L"), "upland")
  expect_identical(vpro_classify_humus_lmh25("2Of"), "wetland")
  expect_identical(vpro_classify_humus_lmh25("IIOm"), "wetland")
  expect_identical(vpro_classify_humus_lmh25("Hydric"), "wetland")
})

test_that("soil ordering lists upland L/F/H top-down then wetland Of/Om/Oh downward", {
  df <- data.frame(
    PlotNumber = "00337",
    Horizon = c("Oh", "Fm", "Of", "Lv", "Om"),
    UpperDepth = c(50, 2, 0, 6, 20),
    LowerDepth = c(90, 0, 20, 2, 50),
    stringsAsFactors = FALSE
  )
  out <- vpro_order_soil_df(df)
  expect_identical(out$Horizon, c("Lv", "Fm", "Of", "Om", "Oh"))
  expect_identical(out$PlotNumber[[1]], "00337")
})
