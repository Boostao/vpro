# Create Sample Published Datasets for BEC Web Map Demo
# This creates two demo projects to showcase the BEC Map Explorer functionality

library(duckdb)

# Output directory
pub_dir <- "app/data/published"
if (!dir.exists(pub_dir)) {
  dir.create(pub_dir, recursive = TRUE)
}

cat("Creating sample published datasets for BEC Web Map demo...\n\n")

# --- Dataset 1: Okanagan IDF Survey ---
cat("1. Creating DEMO_IDF_2023 (Okanagan Interior Douglas-fir)\n")

env_idf <- data.frame(
  plotnumber = c("IDF-001", "IDF-002", "IDF-003", "IDF-004", "IDF-005"),
  date_sampled = as.Date(c("2023-06-15", "2023-06-16", "2023-06-17", "2023-06-18", "2023-06-19")),
  latitude = c(49.8844, 49.9125, 49.8567, 49.9203, 49.8901),
  longitude = c(-119.4960, -119.5234, -119.4567, -119.5012, -119.4789),
  bec_zone = "IDF",
  bec_subzone = rep(c("xh", "dk"), length.out = 5),
  bec_site_series = c("01", "02", "01", "03", "02"),
  data_quality = c("Excellent", "Good", "Excellent", "Good", "Excellent"),
  location = c("Near Kelowna", "Okanagan Mountain", "Knox Mountain", "Mission Creek", "Myra Canyon"),
  stringsAsFactors = FALSE
)

veg_idf <- data.frame(
  plot_id = c(
    rep("IDF-001", 6), rep("IDF-002", 5), rep("IDF-003", 7), 
    rep("IDF-004", 4), rep("IDF-005", 6)
  ),
  species_code = c(
    # IDF-001
    "PSME", "PIPO", "CARU", "SPBE", "JUCO", "AGSP",
    # IDF-002
    "PSME", "PIPO", "CARU", "BASA", "AMAL",
    # IDF-003
    "PSME", "PIPO", "LAOC", "CARU", "SPBE", "FEID", "KOMA",
    # IDF-004
    "PIPO", "PSME", "CARU", "AGSP",
    # IDF-005
    "PSME", "PIPO", "LAOC", "CARU", "SPBE", "ARTR"
  ),
  cover = c(
    # IDF-001
    "60", "35", "45", "25", "15", "10",
    # IDF-002
    "55", "30", "40", "20", "5",
    # IDF-003
    "50", "40", "10", "50", "30", "15", "5",
    # IDF-004
    "65", "20", "35", "15",
    # IDF-005
    "58", "32", "8", "42", "28", "12"
  ),
  layer = c(
    # IDF-001
    "A", "A", "C", "D", "D", "C",
    # IDF-002
    "A", "A", "C", "D", "D",
    # IDF-003
    "A", "A", "A", "C", "D", "C", "C",
    # IDF-004
    "A", "A", "C", "C",
    # IDF-005
    "A", "A", "A", "C", "D", "D"
  ),
  stringsAsFactors = FALSE
)

meta_idf <- data.frame(
  project_id = "DEMO_IDF_2023",
  project_name = "Okanagan IDF Survey 2023",
  is_public = TRUE,
  primary_bec_zone = "IDF",
  description = "Interior Douglas-fir ecosystem survey in the Okanagan region, focusing on typical dry forest associations.",
  stringsAsFactors = FALSE
)

saveRDS(env_idf, file.path(pub_dir, "DEMO_IDF_2023_environment.rds"))
saveRDS(veg_idf, file.path(pub_dir, "DEMO_IDF_2023_vegetation.rds"))
saveRDS(meta_idf, file.path(pub_dir, "DEMO_IDF_2023_metadata.rds"))

cat("  ✓ 5 plots with", nrow(veg_idf), "veg records\n\n")

# --- Dataset 2: Revelstoke ESSF Survey ---
cat("2. Creating DEMO_ESSF_2022 (Revelstoke Engelmann Spruce-Subalpine Fir)\n")

env_essf <- data.frame(
  plotnumber = c("ESSF-101", "ESSF-102", "ESSF-103", "ESSF-104"),
  date_sampled = as.Date(c("2022-08-10", "2022-08-11", "2022-08-12", "2022-08-13")),
  latitude = c(51.0447, 51.0589, 51.0723, 51.0312),
  longitude = c(-118.1956, -118.2134, -118.1789, -118.2201),
  bec_zone = "ESSF",
  bec_subzone = rep(c("wc", "dc"), length.out = 4),
  bec_site_series = c("05", "06", "05", "07"),
  data_quality = c("Excellent", "Excellent", "Good", "Good"),
  location = c("Mt. Revelstoke", "Balsam Lake", "Eva Lake", "Jade Lakes"),
  stringsAsFactors = FALSE
)

veg_essf <- data.frame(
  plot_id = c(
    rep("ESSF-101", 5), rep("ESSF-102", 6), 
    rep("ESSF-103", 5), rep("ESSF-104", 7)
  ),
  species_code = c(
    # ESSF-101
    "ABLA", "PIEN", "VASC", "MEFE", "RHGR",
    # ESSF-102
    "ABLA", "PIEN", "VASC", "PHLE", "MEFE", "CLUN",
    # ESSF-103
    "ABLA", "PIEN", "VASC", "MEFE", "CALA",
    # ESSF-104
    "PIEN", "ABLA", "VASC", "MEFE", "RHGR", "PHLE", "CALA"
  ),
  cover = c(
    # ESSF-101
    "50", "35", "40", "25", "15",
    # ESSF-102
    "55", "30", "45", "10", "20", "5",
    # ESSF-103
    "48", "32", "38", "22", "12",
    # ESSF-104
    "42", "38", "50", "28", "18", "8", "10"
  ),
  layer = c(
    # ESSF-101
    "A", "A", "D", "D", "D",
    # ESSF-102
    "A", "A", "D", "D", "D", "C",
    # ESSF-103
    "A", "A", "D", "D", "C",
    # ESSF-104
    "A", "A", "D", "D", "D", "D", "C"
  ),
  stringsAsFactors = FALSE
)

meta_essf <- data.frame(
  project_id = "DEMO_ESSF_2022",
  project_name = "Revelstoke ESSF Monitoring 2022",
  is_public = TRUE,
  primary_bec_zone = "ESSF",
  description = "High-elevation subalpine forest monitoring in the Selkirk Mountains near Revelstoke.",
  stringsAsFactors = FALSE
)

saveRDS(env_essf, file.path(pub_dir, "DEMO_ESSF_2022_environment.rds"))
saveRDS(veg_essf, file.path(pub_dir, "DEMO_ESSF_2022_vegetation.rds"))
saveRDS(meta_essf, file.path(pub_dir, "DEMO_ESSF_2022_metadata.rds"))

cat("  ✓ 4 plots with", nrow(veg_essf), "veg records\n\n")

# --- Dataset 3: Whistler CWH Survey ---
cat("3. Creating DEMO_CWH_2021 (Whistler Coastal Western Hemlock)\n")

env_cwh <- data.frame(
  plotnumber = c("CWH-201", "CWH-202", "CWH-203"),
  date_sampled = as.Date(c("2021-07-05", "2021-07-06", "2021-07-07")),
  latitude = c(50.1163, 50.0985, 50.1287),
  longitude = c(-122.9574, -122.9789, -122.9423),
  bec_zone = "CWH",
  bec_subzone = "vm",
  bec_site_series = c("04", "05", "04"),
  data_quality = c("Excellent", "Good", "Excellent"),
  location = c("Lost Lake", "Rainbow Park", "Cheakamus Lake Trail"),
  stringsAsFactors = FALSE
)

veg_cwh <- data.frame(
  plot_id = c(rep("CWH-201", 6), rep("CWH-202", 5), rep("CWH-203", 7)),
  species_code = c(
    # CWH-201
    "TSHE", "THPL", "POMU", "ACGL", "BENE", "MAAQ",
    # CWH-202
    "TSHE", "THPL", "POMU", "TITR", "PHEM",
    # CWH-203
    "TSHE", "THPL", "ABAM", "POMU", "BENE", "MAAQ", "ACGL"
  ),
  cover = c(
    # CWH-201
    "70", "25", "55", "15", "30", "10",
    # CWH-202
    "65", "30", "60", "20", "12",
    # CWH-203
    "68", "22", "8", "58", "32", "15", "18"
  ),
  layer = c(
    # CWH-201
    "A", "A", "C", "D", "D", "C",
    # CWH-202
    "A", "A", "C", "D", "D",
    # CWH-203
    "A", "A", "A", "C", "D", "C", "D"
  ),
  stringsAsFactors = FALSE
)

meta_cwh <- data.frame(
  project_id = "DEMO_CWH_2021",
  project_name = "Whistler CWH Baseline 2021",
  is_public = TRUE,
  primary_bec_zone = "CWH",
  description = "Coastal temperate rainforest baseline study in the Sea-to-Sky corridor.",
  stringsAsFactors = FALSE
)

saveRDS(env_cwh, file.path(pub_dir, "DEMO_CWH_2021_environment.rds"))
saveRDS(veg_cwh, file.path(pub_dir, "DEMO_CWH_2021_vegetation.rds"))
saveRDS(meta_cwh, file.path(pub_dir, "DEMO_CWH_2021_metadata.rds"))

cat("  ✓ 3 plots with", nrow(veg_cwh), "veg records\n\n")

# Summary
cat("════════════════════════════════════════════════════════\n")
cat("✅ Created 3 demo published datasets:\n")
cat("   • DEMO_IDF_2023: 5 plots (Okanagan)\n")
cat("   • DEMO_ESSF_2022: 4 plots (Revelstoke)\n")
cat("   • DEMO_CWH_2021: 3 plots (Whistler)\n\n")
cat("Total: 12 plots spanning IDF, ESSF, and CWH zones\n\n")
cat("To view in BEC Map Explorer:\n")
cat("  1. Launch the Shiny app\n")
cat("  2. Navigate to 'BEC Map Explorer' tab\n")
cat("  3. Map will show all 12 plots\n")
cat("  4. Try filtering by zone, clicking markers, and exporting CSV\n")
cat("════════════════════════════════════════════════════════\n")
