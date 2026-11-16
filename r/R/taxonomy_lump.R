# 2026 BCPlantTaxonomy v19, BECdb v13 & Non-Destructive Lump Folding ----------

#' Read harmonized `BCPlantTaxonomy v19` + user species catalogue
#'
#' Queries `USysAllSpecs` in `VLists.db` and optionally merges `USysUserSpp`
#' in `VUser.db` with harmonized integer `Lifeform` codes. By
#' default excludes synonym rows (`LOWER(Codetype) = 's'`) and attaches any
#' conflicting duplicate used-code definitions in `attr(result, "conflicts")`.
#'
#' @param ws Optional `vpro_workspace` handle. When `NULL`, queries the bundled
#'   2026 `VLists.db` and `VUser.db`.
#' @param include_synonyms Logical; if `TRUE`, retains `Codetype == "S"` rows.
#' @param include_user Logical; if `TRUE`, merges `VUser.db` `USysUserSpp` rows.
#' @return A tibble with `Code`, `OldCode`, `ScientificName`, `EnglishName`,
#'   `ShortenedGuideName`, `Lifeform` (`integer`), `Codetype`, `TaxonLevel`,
#'   `FamilyCode`, `Native`, and `SourceCatalog`.
#' @export
vpro_taxonomy <- function(ws = NULL, include_synonyms = FALSE, include_user = TRUE) {
  vlists_path <- if (is.null(ws)) {
    vpro_bundled_db("VLists.db")
  } else {
    vpro_assert_workspace(ws)
    ws$vlists_path
  }
  vuser_path <- if (is.null(ws)) vpro_bundled_db("VUser.db") else ws$vuser_path

  dbc <- vpro_sqlite_ro(vlists_path)
  on.exit(DBI::dbDisconnect(dbc), add = TRUE)

  specs <- DBI::dbGetQuery(
    dbc,
    paste(
      'SELECT UPPER(TRIM(CAST("Code" AS TEXT))) AS "Code",',
      'UPPER(TRIM(CAST("OldCode" AS TEXT))) AS "OldCode",',
      'CAST("ScientificName" AS TEXT) AS "ScientificName",',
      'CAST("EnglishName" AS TEXT) AS "EnglishName",',
      'CAST("ShortenedGuideName" AS TEXT) AS "ShortenedGuideName",',
      'CAST("Lifeform" AS INTEGER) AS "Lifeform",',
      'CAST("Codetype" AS TEXT) AS "Codetype",',
      'CAST("TaxonLevel" AS TEXT) AS "TaxonLevel",',
      'CAST("FamilyCode" AS TEXT) AS "FamilyCode",',
      'CAST("Native" AS TEXT) AS "Native"',
      'FROM "USysAllSpecs"',
      'WHERE "Code" IS NOT NULL AND TRIM("Code") <> \'\''
    )
  )
  specs$SourceCatalog <- rep("VLists", nrow(specs))

  if (isTRUE(include_user) && file.exists(vuser_path)) {
    dbu <- vpro_sqlite_ro(vuser_path)
    on.exit(DBI::dbDisconnect(dbu), add = TRUE)
    if (DBI::dbExistsTable(dbu, "USysUserSpp")) {
      usr <- DBI::dbGetQuery(
        dbu,
        paste(
          'SELECT UPPER(TRIM(CAST("Code" AS TEXT))) AS "Code",',
          'UPPER(TRIM(CAST("Code" AS TEXT))) AS "OldCode",',
          'CAST("ScientificName" AS TEXT) AS "ScientificName",',
          'CAST("EnglishName" AS TEXT) AS "EnglishName",',
          'CAST(NULL AS TEXT) AS "ShortenedGuideName",',
          'CAST("LifeForm" AS INTEGER) AS "Lifeform",',
          'CAST("Codetype" AS TEXT) AS "Codetype",',
          'CAST(NULL AS TEXT) AS "TaxonLevel",',
          'CAST(NULL AS TEXT) AS "FamilyCode",',
          'CAST(NULL AS TEXT) AS "Native"',
          'FROM "USysUserSpp"',
          'WHERE "Code" IS NOT NULL AND TRIM("Code") <> \'\''
        )
      )
      if (nrow(usr) > 0L) {
        usr$SourceCatalog <- rep("VUser", nrow(usr))
        specs <- rbind(specs, usr)
      }
    }
  }

  if (!isTRUE(include_synonyms)) {
    is_syn <- !is.na(specs$Codetype) & tolower(trimws(specs$Codetype)) == "s"
    specs <- specs[!is_syn, , drop = FALSE]
  }

  dt <- data.table::as.data.table(specs)
  conflicts_tbl <- tibble::tibble(
    Code = character(),
    ScientificName = character(),
    Lifeform = integer(),
    SourceCatalog = character()
  )
  if (!isTRUE(include_synonyms) && nrow(dt) > 0L) {
    # Detect conflicting used-code tuples rather than silently hiding disagreements
    uniq_tuples <- unique(dt[, list(
      Code = get("Code"),
      ScientificName = get("ScientificName"),
      Lifeform = get("Lifeform"),
      SourceCatalog = get("SourceCatalog")
    )])
    dup_codes <- uniq_tuples$Code[duplicated(uniq_tuples$Code)]
    if (length(dup_codes) > 0L) {
      conflicts_tbl <- tibble::as_tibble(uniq_tuples[uniq_tuples$Code %in% unique(dup_codes), ])
    }
    # Prefer VLists accepted ('U') rows first while preserving conflicts attribute
    ord <- order(
      dt$Code,
      ifelse(dt$SourceCatalog == "VLists", 0L, 1L),
      ifelse(!is.na(dt$Codetype) & toupper(dt$Codetype) == "U", 0L, 1L)
    )
    dt <- dt[ord]
    dt <- dt[!duplicated(dt$Code)]
  } else if (nrow(dt) > 0L) {
    dt <- dt[order(dt$Code, dt$OldCode)]
  }

  out <- tibble::as_tibble(dt)
  attr(out, "conflicts") <- conflicts_tbl
  out
}

vpro_synonym_map <- function(ws = NULL) {
  vlists_path <- if (is.null(ws)) vpro_bundled_db("VLists.db") else ws$vlists_path
  dbc <- vpro_sqlite_ro(vlists_path)
  on.exit(DBI::dbDisconnect(dbc), add = TRUE)
  syns <- DBI::dbGetQuery(
    dbc,
    paste(
      'SELECT UPPER(TRIM(CAST("OldCode" AS TEXT))) AS "OldCode",',
      'UPPER(TRIM(CAST("Code" AS TEXT))) AS "Code"',
      'FROM "USysAllSpecs"',
      'WHERE LOWER(TRIM(COALESCE("Codetype", \'\'))) = \'s\'',
      'AND "OldCode" IS NOT NULL AND TRIM("OldCode") <> \'\'',
      'AND "Code" IS NOT NULL AND TRIM("Code") <> \'\''
    )
  )
  syns <- syns[syns$OldCode != syns$Code, , drop = FALSE]
  syns <- syns[!duplicated(syns$OldCode), , drop = FALSE]
  stats::setNames(syns$Code, syns$OldCode)
}

#' Query 2026 `BECdb v13` Biogeoclimatic units and site series
#'
#' Reads `USysSiteSeriesNames` and `USysZoneList` from `VLists.db`.
#'
#' @param ws Optional `vpro_workspace` handle. When `NULL`, uses bundled 2026
#'   `VLists.db`.
#' @param zone Optional BGC zone filter (case-insensitive, e.g. `"CWH"`, `"SBS"`).
#' @param subzone Optional BGC subzone/variant filter (e.g. `"vm"`, `"dk"` or
#'   full `BGCName` like `"CWHvm1"`).
#' @return A tibble of BEC units and site series.
#' @export
vpro_bec_units <- function(ws = NULL, zone = NULL, subzone = NULL) {
  vlists_path <- if (is.null(ws)) {
    vpro_bundled_db("VLists.db")
  } else {
    vpro_assert_workspace(ws)
    ws$vlists_path
  }
  dbc <- vpro_sqlite_ro(vlists_path)
  on.exit(DBI::dbDisconnect(dbc), add = TRUE)

  ss <- DBI::dbGetQuery(
    dbc,
    paste(
      'SELECT CAST(s."SSCode" AS TEXT) AS "SSCode",',
      'CAST(s."BGCName" AS TEXT) AS "BGCName",',
      'CAST(s."BEC_Region" AS TEXT) AS "BEC_Region",',
      'CAST(s."BGC_Zone" AS TEXT) AS "BGC_Zone",',
      'CAST(s."BGC_Subzone" AS TEXT) AS "BGC_Subzone",',
      'CAST(s."BGC_Variant" AS TEXT) AS "BGC_Variant",',
      'CAST(s."BGC_Phase" AS TEXT) AS "BGC_Phase",',
      'CAST(s."SiteSeries" AS TEXT) AS "SiteSeries",',
      'CAST(s."Seral" AS TEXT) AS "Seral",',
      'CAST(s."SiteSeriesDescription" AS TEXT) AS "SiteSeriesDescription",',
      'CAST(s."PlantAssociation" AS TEXT) AS "PlantAssociation",',
      'CAST(z."ZoneDescription" AS TEXT) AS "ZoneDescription",',
      'CAST(z."SubZoneVarDescription" AS TEXT) AS "SubZoneVarDescription"',
      'FROM "USysSiteSeriesNames" AS s',
      'LEFT JOIN "USysZoneList" AS z',
      'ON s."BGC_Zone" = z."Zone" COLLATE NOCASE',
      'AND COALESCE(s."SubzVarPh", \'\') = COALESCE(z."SubZone", \'\') COLLATE NOCASE',
      'ORDER BY s."SSCode"'
    )
  )
  if (!is.null(zone) && length(zone) > 0L) {
    z_up <- toupper(trimws(as.character(zone)))
    ss <- ss[!is.na(ss$BGC_Zone) & toupper(trimws(ss$BGC_Zone)) %in% z_up, , drop = FALSE]
  }
  if (!is.null(subzone) && length(subzone) > 0L) {
    sub_up <- toupper(gsub("[[:space:]]+", "", as.character(subzone)))
    bgc_clean <- toupper(gsub("[[:space:]]+", "", ifelse(is.na(ss$BGCName), "", ss$BGCName)))
    sub_clean <- toupper(gsub("[[:space:]]+", "", ifelse(is.na(ss$BGC_Subzone), "", ss$BGC_Subzone)))
    ss <- ss[bgc_clean %in% sub_up | sub_clean %in% sub_up, , drop = FALSE]
  }
  tibble::as_tibble(ss)
}

#' Read or normalize a species lump mapping (`SppCode -> LumpCode`)
#'
#' Supports `lump = TRUE` (active `ws$lump` table where `Use != 0`),
#' `lump = FALSE` / `NULL` (empty tibble), `lump = "<TableName>"` (explicit
#' `*_Lump` table in `ws`), or a custom `data.frame` with `SppCode` and
#' `LumpCode` columns (and optional `Use` column).
#'
#' @param ws A `vpro_workspace` handle (optional when `lump` is a `data.frame`
#'   or `FALSE`).
#' @param lump Logical flag, lump table name, or `data.frame(SppCode, LumpCode)`.
#' @return A tibble with active `SppCode` and `LumpCode` mappings (uppercase,
#'   trimmed).
#' @export
vpro_lump_map <- function(ws = NULL, lump = TRUE) {
  empty <- tibble::tibble(SppCode = character(), LumpCode = character())
  if (is.null(lump) || identical(lump, FALSE)) {
    return(empty)
  }
  if (is.data.frame(lump)) {
    nms <- tolower(names(lump))
    s_ix <- match("sppcode", nms)
    l_ix <- match("lumpcode", nms)
    if (is.na(s_ix) || is.na(l_ix)) {
      rlang::abort("Custom `lump` data.frame must contain `SppCode` and `LumpCode` columns.")
    }
    u_ix <- match("use", nms)
    use_vec <- if (is.na(u_ix)) rep(TRUE, nrow(lump)) else vpro_access_to_logical(lump[[u_ix]])
    use_vec[is.na(use_vec)] <- FALSE
    spp <- toupper(trimws(as.character(lump[[s_ix]])))
    lmp <- toupper(trimws(as.character(lump[[l_ix]])))
    keep <- use_vec & !is.na(spp) & nzchar(spp) & !is.na(lmp) & nzchar(lmp)
    df <- tibble::tibble(SppCode = spp[keep], LumpCode = lmp[keep])
    return(df[!duplicated(df$SppCode), , drop = FALSE])
  }

  vpro_assert_workspace(ws)
  tbl_name <- if (isTRUE(lump)) {
    ws$lump
  } else if (is.character(lump) && length(lump) == 1L) {
    tables <- vpro_sqlite_physical_tables(ws$lump_path)
    vpro_resolve_table_suffix(tables, lump, "Lump", default_prefix = ws$project)
  } else {
    rlang::abort("`lump` must be TRUE, FALSE, a table name, or a two-column data.frame.")
  }
  if (is.null(tbl_name)) {
    return(empty)
  }

  dbc <- vpro_sqlite_ro(ws$lump_path)
  on.exit(DBI::dbDisconnect(dbc), add = TRUE)
  if (!DBI::dbExistsTable(dbc, tbl_name)) {
    return(empty)
  }
  raw <- DBI::dbGetQuery(
    dbc,
    paste0(
      'SELECT UPPER(TRIM(CAST("SppCode" AS TEXT))) AS "SppCode", ',
      'UPPER(TRIM(CAST("LumpCode" AS TEXT))) AS "LumpCode", ',
      '"Use" FROM ',
      vpro_quote_ident(tbl_name)
    )
  )
  use_ok <- vpro_access_to_logical(raw$Use)
  use_ok[is.na(use_ok)] <- FALSE
  keep <- use_ok & !is.na(raw$SppCode) & nzchar(raw$SppCode) & !is.na(raw$LumpCode) & nzchar(raw$LumpCode)
  out <- tibble::tibble(SppCode = raw$SppCode[keep], LumpCode = raw$LumpCode[keep])
  out[!duplicated(out$SppCode), , drop = FALSE]
}
