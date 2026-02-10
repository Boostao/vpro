test_that("build_download_log_query handles empty filters", {
  query <- build_download_log_query(list())
  expect_true(grepl("FROM master.public_export.download_log", query$sql))
  expect_false(grepl("WHERE", query$sql))
  expect_length(query$params, 0)
})

test_that("build_download_log_query builds parameter order", {
  from_time <- as.POSIXct("2026-02-01 00:00:00", tz = "UTC")
  to_time <- as.POSIXct("2026-02-02 00:00:00", tz = "UTC")
  query <- build_download_log_query(
    filters = list(
      user = "bob",
      dataset = "veg",
      format = "rds",
      status = "failed",
      from = from_time,
      to = to_time
    ),
    limit = 25
  )

  expect_true(grepl("username ILIKE \\?", query$sql))
  expect_true(grepl("dataset_name ILIKE \\?", query$sql))
  expect_true(grepl("format = \\?", query$sql))
  expect_true(grepl("download_status = \\?", query$sql))
  expect_true(grepl("timestamp_utc >= \\?", query$sql))
  expect_true(grepl("timestamp_utc <= \\?", query$sql))
  expect_true(grepl("LIMIT 25", query$sql))

  expect_equal(length(query$params), 6)
  expect_equal(query$params[[1]], "%bob%")
  expect_equal(query$params[[2]], "%veg%")
  expect_equal(query$params[[3]], "rds")
  expect_equal(query$params[[4]], "failed")
  expect_equal(query$params[[5]], from_time)
  expect_equal(query$params[[6]], to_time)
})
