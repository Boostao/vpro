# Build a read-only review inventory; this script never modifies bundled sources.
# Run from the package root with: source("data-raw/projects/build-short-veg-species-conflicts.R")

if (!requireNamespace("DBI", quietly = TRUE) ||
    !requireNamespace("RSQLite", quietly = TRUE)) {
  stop("Packages DBI and RSQLite are required.", call. = FALSE)
}

script_path <- tryCatch(normalizePath(sys.frame(1)$ofile), error = function(e) NA_character_)
root <- if (!is.na(script_path)) {
  normalizePath(file.path(dirname(script_path), "..", ".."))
} else {
  normalizePath(getwd())
}

source_paths <- c(
  VLists = file.path(root, "inst", "extdata", "VLists.db"),
  VUser = file.path(root, "inst", "extdata", "VUser.db"),
  Sample = file.path(root, "inst", "extdata", "projects", "Sample.db")
)
output_path <- file.path(
  root, "data-raw", "projects", "SHORT_VEG_SPECIES_CONFLICT_CANDIDATES.csv"
)

for (path in source_paths) {
  if (!file.exists(path)) stop("Required source does not exist: ", path, call. = FALSE)
}

connect_read_only <- function(path) {
  DBI::dbConnect(
    RSQLite::SQLite(),
    sprintf("file:%s?mode=ro", normalizePath(path, winslash = "/")),
    uri = TRUE
  )
}

read_species <- function(path, table, source) {
  con <- connect_read_only(path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  if (!DBI::dbExistsTable(con, table)) {
    stop("Required table does not exist: ", table, call. = FALSE)
  }
  value <- DBI::dbGetQuery(
    con,
    sprintf(
      'SELECT "Code", "ScientificName", "LifeForm", "EnglishName", "Codetype" FROM "%s"',
      table
    )
  )
  names(value)[names(value) == "LifeForm"] <- "Lifeform"
  value$source_provenance <- source
  value
}

read_usage <- function(path) {
  con <- connect_read_only(path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  if (!DBI::dbExistsTable(con, "Sample_Veg")) {
    stop("Required table does not exist: Sample_Veg", call. = FALSE)
  }
  value <- DBI::dbGetQuery(
    con,
    'SELECT "Species", COUNT(*) AS "sample_veg_usage_count"\n     FROM "Sample_Veg"\n     GROUP BY "Species"'
  )
  value$normalized_code <- toupper(trimws(value$Species))
  aggregate(sample_veg_usage_count ~ normalized_code, data = value, FUN = sum)
}

# Access WHERE Codetype <> 's' omits NULL Codetype values; make that consequence
# explicit while applying a case-insensitive comparison for reproducibility.
species <- rbind(
  read_species(source_paths[["VLists"]], "USysAllSpecs", "VLists.db::USysAllSpecs"),
  read_species(source_paths[["VUser"]], "USysUserSpp", "VUser.db::USysUserSpp")
)
species <- species[!is.na(species$Codetype) & tolower(species$Codetype) != "s", , drop = FALSE]

five_fields <- c("Code", "ScientificName", "Lifeform", "EnglishName", "Codetype")
value_key <- function(value) ifelse(is.na(value), "<NULL>", enc2utf8(as.character(value)))
five_field_key <- do.call(
  paste,
  c(lapply(species[five_fields], value_key), sep = "\r")
)

# UNION (not UNION ALL): retain one five-field tuple while retaining all source
# labels in a provenance field that is outside the Access UNION tuple.
keep <- !duplicated(five_field_key)
candidates <- species[keep, five_fields, drop = FALSE]
candidates$source_provenance <- vapply(
  five_field_key[keep],
  function(key) paste(sort(unique(species$source_provenance[five_field_key == key])), collapse = "; "),
  character(1)
)
candidates$normalized_code <- toupper(trimws(candidates$Code))

candidate_group_size <- table(candidates$normalized_code)
candidates <- candidates[
  candidates$normalized_code %in% names(candidate_group_size[candidate_group_size > 1L]),
  ,
  drop = FALSE
]

usage <- read_usage(source_paths[["Sample"]])
candidates$sample_veg_usage_count <- usage$sample_veg_usage_count[
  match(candidates$normalized_code, usage$normalized_code)
]
candidates$sample_veg_usage_count[is.na(candidates$sample_veg_usage_count)] <- 0L
candidates$status <- "pending"
candidates$reviewer <- ""
candidates$review_date <- ""
candidates$rationale <- ""

candidates <- candidates[, c(
  "normalized_code", five_fields, "source_provenance", "sample_veg_usage_count",
  "status", "reviewer", "review_date", "rationale"
)]
candidates <- candidates[do.call(order, c(
  candidates[c("normalized_code", five_fields, "source_provenance")], na.last = TRUE
)), , drop = FALSE]
row.names(candidates) <- NULL

write.csv(candidates, output_path, row.names = FALSE, na = "", quote = TRUE)

summary <- list(
  candidate_rows = nrow(candidates),
  normalized_code_groups = length(unique(candidates$normalized_code)),
  used_candidate_rows = sum(candidates$sample_veg_usage_count > 0L),
  used_normalized_code_groups = length(unique(candidates$normalized_code[candidates$sample_veg_usage_count > 0L]))
)
message(sprintf(
  "Wrote %d pending candidate rows across %d normalized code groups (%d rows, %d groups used in Sample_Veg).",
  summary$candidate_rows, summary$normalized_code_groups,
  summary$used_candidate_rows, summary$used_normalized_code_groups
))
invisible(summary)
