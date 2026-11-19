# Tidy VP08 Soil Horizons, Other/Audit/Metadata & Hierarchy Conversions --------

# Strip a leading LMH25 lithologic-discontinuity marker (Arabic digits 2Of/3Ah
# or Roman numerals IIOf/IXAh/XAh), matching Go vprocore.stripSoilDiscontinuityPrefix.
vpro_strip_soil_discontinuity <- function(horizon) {
  h <- trimws(ifelse(is.na(horizon), "", as.character(horizon)))
  trimws(sub("^[0-9IVX ]+", "", toupper(h)))
}

# Canonical LMH25 (2023) soil horizon regime classifier shared across all R
# soil readers, pedological keys, and custodian 3-way merge checks, matching
# Go vprocore.ClassifySoilHorizon 1-to-1:
#   - "mineral": all Mineral-table rows
#   - "wetland": Humus O* (O, Oe, Op, Of, Om, Oh) + Hydric/Limno/Cumulo
#   - "upland" : Humus L/F/H
#   - ""       : blank or unrecognized Humus horizon
vpro_lmh25_horizon_regime <- function(horizon, kind = NULL) {
  n <- length(horizon)
  if (identical(kind, "Mineral")) {
    return(rep("mineral", n))
  }
  if (!is.null(kind) && !identical(kind, "Humus")) {
    return(rep("", n))
  }
  u <- vpro_strip_soil_discontinuity(horizon)
  out <- rep("", n)
  is_wet <- nzchar(u) & (
    startsWith(u, "HYDRIC") |
      startsWith(u, "LIMNO") |
      startsWith(u, "CUMULO") |
      startsWith(u, "O")
  )
  is_up <- !is_wet & nzchar(u) & (
    startsWith(u, "L") |
      startsWith(u, "F") |
      startsWith(u, "H")
  )
  out[is_wet] <- "wetland"
  out[is_up] <- "upland"
  out
}

# Canonical SQLite ORDER BY clause for VP08 Humus tables, matching Go
# vprocore.HumusOrderBySQL (stripping 0-9/I/V/X discontinuity prefixes so 2Of,
# IIOf, O, Oe, Op, Hydric, Limno, Cumulo sort ascending by UpperDepth after
# upland L/F/H descending, with NULL UpperDepth last).
vpro_humus_order_by_sql <- function(horizon_expr = '"Horizon"', upper_depth_expr = '"UpperDepth"') {
  norm <- paste0("LTRIM(UPPER(TRIM(COALESCE(", horizon_expr, ", ''))), '0123456789IVX ')")
  wetland <- paste0(
    "(",
    norm, " GLOB 'O*' OR ",
    norm, " GLOB 'HYDRIC*' OR ",
    norm, " GLOB 'LIMNO*' OR ",
    norm, " GLOB 'CUMULO*')"
  )
  paste0(
    "CASE WHEN ", wetland, " THEN 1 ELSE 0 END ASC, ",
    "CASE WHEN ", upper_depth_expr, " IS NULL THEN 1 ELSE 0 END ASC, ",
    "CASE WHEN ", wetland, " THEN ", upper_depth_expr, " ELSE -", upper_depth_expr, " END ASC"
  )
}

vpro_classify_horizon <- function(horizon, kind = NULL) {
  reg <- vpro_lmh25_horizon_regime(horizon, kind = kind)
  out <- rep("mineral", length(reg))
  out[reg == "wetland"] <- "wetland_organic"
  out[reg == "upland"] <- "upland_organic"
  out
}

vpro_order_soil_df <- function(df, kind = NULL) {
  if (nrow(df) == 0L) {
    return(tibble::as_tibble(df))
  }
  df$PlotNumber <- as.character(df$PlotNumber)
  if ("Flag" %in% names(df)) {
    df$Flag <- vpro_access_to_logical(df$Flag)
  }
  df$HorizonRegime <- vpro_classify_horizon(df$Horizon, kind = kind)
  # LMH25 (2023): upland organic L/F/H ordered UpperDepth DESC; wetland Of/Om/Oh & mineral A/B/C/R/W ordered UpperDepth ASC
  regime_rank <- match(df$HorizonRegime, c("upland_organic", "wetland_organic", "mineral"))
  depth_key <- ifelse(
    df$HorizonRegime == "upland_organic",
    -suppressWarnings(as.numeric(df$UpperDepth)),
    suppressWarnings(as.numeric(df$UpperDepth))
  )
  ord <- order(df$PlotNumber, regime_rank, depth_key, na.last = TRUE, method = "radix")
  df <- df[ord, , drop = FALSE]
  rownames(df) <- NULL
  tibble::as_tibble(df)
}

#' Read tidy `LMH25 (2023)`-ordered soil humus and mineral horizon records
#'
#' Extracts `<Project>_Humus` and/or `<Project>_Mineral`, preserves literal
#' character `PlotNumber`s, converts `Flag` to R `logical`, annotates
#' `HorizonRegime` (`"upland_organic"`, `"wetland_organic"`, `"mineral"`), and
#' orders horizons per `LMH25 (2023)` (`L/F/H` ordered `UpperDepth DESC`;
#' `Of/Om/Oh` and `A/B/C/R/W` ordered `UpperDepth ASC`).
#'
#' @param ws A `vpro_workspace` handle.
#' @param scope Either `"su"` or `"project"`.
#' @param type `"both"` (returns S3 `vpro_soil` bundle with `$humus` and
#'   `$mineral` tibbles), `"humus"`, or `"mineral"`.
#' @return A tibble (`type = "humus"` or `"mineral"`) or `vpro_soil` list (`type = "both"`).
#' @export
vpro_soil <- function(ws, scope = c("su", "project"), type = c("both", "humus", "mineral")) {
  vpro_assert_workspace(ws)
  scope <- match.arg(scope)
  type <- match.arg(type)

  su_df <- vpro_site_units(ws)
  scoped_plots <- if (identical(scope, "su") && !is.null(ws$su)) su_df$PlotNumber else NULL

  dbc <- vpro_sqlite_ro(ws$project_path)
  on.exit(DBI::dbDisconnect(dbc), add = TRUE)

  read_one <- function(suffix) {
    tbl <- paste0(ws$project, "_", suffix)
    flds <- DBI::dbListFields(dbc, tbl)
    sel <- paste(
      vapply(
        flds,
        function(f) {
          if (identical(f, "PlotNumber")) 'CAST("PlotNumber" AS TEXT) AS "PlotNumber"' else vpro_quote_ident(f)
        },
        character(1)
      ),
      collapse = ", "
    )
    raw <- vpro_query_scoped_plots(dbc, vpro_quote_ident(tbl), scoped_plots, select_cols = sel)
    vpro_order_soil_df(raw, kind = suffix)
  }

  if (type == "humus") {
    return(read_one("Humus"))
  }
  if (type == "mineral") {
    return(read_one("Mineral"))
  }

  structure(
    list(
      humus = read_one("Humus"),
      mineral = read_one("Mineral")
    ),
    class = "vpro_soil"
  )
}

#' @export
print.vpro_soil <- function(x, ...) {
  cli::cli_h3("vpro_soil (LMH25-ordered)")
  cli::cli_bullets(c(
    "*" = "Humus horizons: {nrow(x$humus)} rows ({length(unique(x$humus$PlotNumber))} plots)",
    "*" = "Mineral horizons: {nrow(x$mineral)} rows ({length(unique(x$mineral$PlotNumber))} plots)"
  ))
  invisible(x)
}

#' @export
as_tibble.vpro_soil <- function(x, ...) {
  h <- x$humus[, intersect(c("PlotNumber", "Horizon", "UpperDepth", "LowerDepth", "HorizonRegime"), names(x$humus)), drop = FALSE]
  h$SoilLayer <- rep("Humus", nrow(h))
  m <- x$mineral[, intersect(c("PlotNumber", "Horizon", "UpperDepth", "LowerDepth", "HorizonRegime"), names(x$mineral)), drop = FALSE]
  m$SoilLayer <- rep("Mineral", nrow(m))
  tibble::as_tibble(rbind(h, m))
}

#' Read `<Project>_Other` plot records
#'
#' @param ws A `vpro_workspace` handle.
#' @param scope Either `"su"` or `"project"`.
#' @return A tibble of `_Other` records.
#' @export
vpro_other <- function(ws, scope = c("su", "project")) {
  vpro_assert_workspace(ws)
  scope <- match.arg(scope)
  scoped_plots <- if (identical(scope, "su") && !is.null(ws$su)) vpro_site_units(ws)$PlotNumber else NULL
  dbc <- vpro_sqlite_ro(ws$project_path)
  on.exit(DBI::dbDisconnect(dbc), add = TRUE)
  tbl <- paste0(ws$project, "_Other")
  flds <- DBI::dbListFields(dbc, tbl)
  sel <- paste(
    vapply(
      flds,
      function(f) {
        if (identical(f, "PlotNumber")) 'CAST("PlotNumber" AS TEXT) AS "PlotNumber"' else vpro_quote_ident(f)
      },
      character(1)
    ),
    collapse = ", "
  )
  df <- vpro_query_scoped_plots(dbc, vpro_quote_ident(tbl), scoped_plots, select_cols = sel)
  df$PlotNumber <- as.character(df$PlotNumber)
  for (bc in intersect(c("UserFlag1", "UserFlag2", "UserFlag3", "Flag"), names(df))) {
    df[[bc]] <- vpro_access_to_logical(df[[bc]])
  }
  tibble::as_tibble(df)
}

#' Read `<Project>_Audit` trail records
#'
#' @param ws A `vpro_workspace` handle.
#' @return A tibble of `_Audit` records with normalized booleans.
#' @export
vpro_audit <- function(ws) {
  vpro_assert_workspace(ws)
  dbc <- vpro_sqlite_ro(ws$project_path)
  on.exit(DBI::dbDisconnect(dbc), add = TRUE)
  tbl <- paste0(ws$project, "_Audit")
  flds <- DBI::dbListFields(dbc, tbl)
  sel <- paste(
    vapply(
      flds,
      function(f) {
        if (identical(f, "PlotNumber")) 'CAST("PlotNumber" AS TEXT) AS "PlotNumber"' else vpro_quote_ident(f)
      },
      character(1)
    ),
    collapse = ", "
  )
  df <- DBI::dbGetQuery(dbc, paste("SELECT", sel, "FROM", vpro_quote_ident(tbl), "ORDER BY rowid"))
  if ("PlotNumber" %in% names(df)) {
    df$PlotNumber <- as.character(df$PlotNumber)
  }
  for (bc in intersect(c("Restore", "Flag"), names(df))) {
    df[[bc]] <- vpro_access_to_logical(df[[bc]])
  }
  tibble::as_tibble(df)
}

#' Read `<Project>_Metadata` records
#'
#' @param ws A `vpro_workspace` handle.
#' @return A tibble of project metadata rows.
#' @export
vpro_metadata <- function(ws) {
  vpro_assert_workspace(ws)
  dbc <- vpro_sqlite_ro(ws$project_path)
  on.exit(DBI::dbDisconnect(dbc), add = TRUE)
  tbl <- paste0(ws$project, "_Metadata")
  df <- DBI::dbGetQuery(dbc, paste("SELECT * FROM", vpro_quote_ident(tbl)))
  tibble::as_tibble(df)
}

.vpro_hierarchy_level_names <- c(
  "Formation",
  "Class",
  "Subclass",
  "Order",
  "Suborder",
  "Alliance",
  "Suball",
  "Assoc",
  "Subass",
  "Facies",
  "SiteUnit"
)

#' Convert a VPro `*_Hierarchy` node table to a flat 11-level BEC path table
#'
#' Pure `data.table` counterpart to MoF `treeToTable()`, handling `~` tilde
#' breakpoint prefixes, filling missing `Suborder`/`Suball`/`Subass` from their
#' parent level, and reporting `BreakpointUnit` (the lowest `~`-prefixed
#' ancestor along each branch) for dynamic hierarchy rollups.
#'
#' @param nodes_df Data frame containing `ID`, `Name`, `Parent`, and `Level`.
#' @param preserve_tilde Logical; if `TRUE`, retains leading `~` breakpoint
#'   prefixes in the 11 level columns for lossless round-tripping with
#'   [vpro_table_to_hierarchy()].
#' @return A tibble with leaf/terminal branch rows across the 11 BEC levels plus
#'   `LeafName`, `CleanLeafName`, and `BreakpointUnit`.
#' @export
vpro_hierarchy_to_table <- function(nodes_df, preserve_tilde = FALSE) {
  req <- c("ID", "Name", "Parent", "Level")
  if (!is.data.frame(nodes_df) || !all(req %in% names(nodes_df))) {
    rlang::abort("`nodes_df` must contain `ID`, `Name`, `Parent`, and `Level` columns.")
  }
  if (nrow(nodes_df) == 0L) {
    empty <- as.list(rep(list(character()), length(.vpro_hierarchy_level_names)))
    names(empty) <- .vpro_hierarchy_level_names
    empty$LeafName <- character()
    empty$CleanLeafName <- character()
    empty$BreakpointUnit <- character()
    return(tibble::as_tibble(empty))
  }

  id_chr <- as.character(nodes_df$ID)
  parent_chr <- ifelse(is.na(nodes_df$Parent), NA_character_, as.character(nodes_df$Parent))
  raw_name <- trimws(as.character(nodes_df$Name))
  is_brk <- startsWith(raw_name, "~")
  clean_name <- sub("^~+", "", raw_name)
  disp_name <- if (isTRUE(preserve_tilde)) raw_name else clean_name
  lvl <- suppressWarnings(as.integer(nodes_df$Level))
  lvl[is.na(lvl) | lvl < 1L] <- 11L
  lvl[lvl > 11L] <- 11L

  idx_by_id <- stats::setNames(seq_along(id_chr), id_chr)
  has_children <- id_chr %in% parent_chr[!is.na(parent_chr)]
  leaves <- which(!has_children)

  rows <- lapply(leaves, function(leaf_i) {
    chain <- integer()
    cur <- leaf_i
    visited <- integer()
    while (!is.na(cur) && !(cur %in% visited)) {
      chain <- c(cur, chain)
      visited <- c(visited, cur)
      p_id <- parent_chr[[cur]]
      if (is.na(p_id) || !(p_id %in% names(idx_by_id))) {
        break
      }
      nxt <- idx_by_id[[p_id]]
      if (identical(nxt, cur)) {
        break
      }
      cur <- nxt
    }
    vals <- rep(NA_character_, 11L)
    brk_unit <- NA_character_
    for (ci in chain) {
      lv <- lvl[[ci]]
      vals[[lv]] <- disp_name[[ci]]
      if (is_brk[[ci]]) {
        brk_unit <- clean_name[[ci]]
      }
    }
    # MoF HierarchyConversion.R convention: fill missing Suborder/Suball/Subass from parent
    if (is.na(vals[[5L]]) && !is.na(vals[[4L]])) {
      vals[[5L]] <- vals[[4L]]
    }
    if (is.na(vals[[7L]]) && !is.na(vals[[6L]])) {
      vals[[7L]] <- vals[[6L]]
    }
    if (is.na(vals[[9L]]) && !is.na(vals[[8L]])) {
      vals[[9L]] <- vals[[8L]]
    }
    if (is.na(vals[[11L]])) {
      vals[[11L]] <- disp_name[[leaf_i]]
    }

    rec <- as.list(vals)
    names(rec) <- .vpro_hierarchy_level_names
    rec$LeafName <- raw_name[[leaf_i]]
    rec$CleanLeafName <- clean_name[[leaf_i]]
    rec$BreakpointUnit <- brk_unit
    tibble::as_tibble(rec)
  })
  do.call(rbind, rows)
}

#' Convert a wide BEC hierarchy table into a VPro `*_Hierarchy` node table
#'
#' Pure R counterpart to MoF `tableToTree()`, generating deterministic integer
#' `ID`, `Name`, `Parent`, and `Level` rows ready for VPro `*_Hierarchy` storage.
#'
#' @param wide_df Data frame whose columns correspond to ordered hierarchy
#'   levels (defaults to intersecting `.vpro_hierarchy_level_names` or all columns).
#' @param level_names Optional character vector of level column names in
#'   top-to-bottom order.
#' @return A tibble with `ID`, `Name`, `Parent`, and `Level`.
#' @export
vpro_table_to_hierarchy <- function(wide_df, level_names = NULL) {
  if (!is.data.frame(wide_df) || ncol(wide_df) == 0L) {
    rlang::abort("`wide_df` must be a non-empty data frame of hierarchy level columns.")
  }
  if (is.null(level_names)) {
    std <- intersect(.vpro_hierarchy_level_names, names(wide_df))
    level_names <- if (length(std) >= 2L) std else names(wide_df)
  }
  lvl_nums <- match(level_names, .vpro_hierarchy_level_names)
  if (anyNA(lvl_nums)) {
    lvl_nums <- seq_along(level_names)
  }

  node_env <- new.env(hash = TRUE, parent = emptyenv())
  records <- list()
  next_id <- 0L

  for (r in seq_len(nrow(wide_df))) {
    parent_id <- NA_integer_
    path_key <- ""
    for (c_ix in seq_along(level_names)) {
      col <- level_names[[c_ix]]
      val <- wide_df[[col]][[r]]
      if (is.na(val) || !nzchar(trimws(as.character(val)))) {
        next
      }
      nm <- trimws(as.character(val))
      lv <- as.integer(lvl_nums[[c_ix]])
      # Collapse consecutive identical filled sublevels (e.g. Suborder == Order)
      key <- paste0(path_key, "/", lv, ":", nm)
      if (!is.na(parent_id) && length(records) >= parent_id && identical(records[[parent_id]]$Name, nm)) {
        next
      }
      if (exists(key, envir = node_env, inherits = FALSE)) {
        parent_id <- get(key, envir = node_env, inherits = FALSE)
      } else {
        next_id <- next_id + 1L
        records[[next_id]] <- list(
          ID = next_id,
          Name = nm,
          Parent = parent_id,
          Level = lv
        )
        assign(key, next_id, envir = node_env)
        parent_id <- next_id
      }
      path_key <- key
    }
  }
  if (length(records) == 0L) {
    return(tibble::tibble(ID = integer(), Name = character(), Parent = integer(), Level = integer()))
  }
  tibble::tibble(
    ID = vapply(records, `[[`, integer(1), "ID"),
    Name = vapply(records, `[[`, character(1), "Name"),
    Parent = vapply(records, `[[`, integer(1), "Parent"),
    Level = vapply(records, `[[`, integer(1), "Level")
  )
}

#' Read classification hierarchy (`*_Hierarchy`) as nodes and/or flat BEC paths
#'
#' Reads `<Name>_Hierarchy`, identifies `~Name` tilde breakpoints, and builds
#' both the parent-pointer `nodes` tibble (with `CleanName`, `IsBreakpoint`, and
#' `Path`) and the flat 11-level `paths` tibble (`Formation`..`SiteUnit` +
#' `BreakpointUnit`).
#'
#' @param ws A `vpro_workspace` handle.
#' @param hierarchy Optional `*_Hierarchy` table override (defaults to
#'   `ws$hierarchy`).
#' @param as Return shape: `"both"` (S3 `vpro_hierarchy` bundle with `$nodes` and
#'   `$paths`), `"nodes"`, or `"paths"`.
#' @return A `vpro_hierarchy` list (`as = "both"`) or tibble (`"nodes"` / `"paths"`).
#' @export
vpro_hierarchy <- function(ws, hierarchy = NULL, as = c("both", "nodes", "paths")) {
  vpro_assert_workspace(ws)
  as <- match.arg(as)
  h_tbl <- if (is.null(hierarchy)) {
    ws$hierarchy
  } else {
    tables <- vpro_sqlite_physical_tables(ws$hierarchy_path)
    vpro_resolve_table_suffix(tables, hierarchy, "Hierarchy", default_prefix = ws$project)
  }
  if (is.null(h_tbl)) {
    empty_nodes <- tibble::tibble(
      ID = integer(),
      Name = character(),
      CleanName = character(),
      Parent = integer(),
      Level = integer(),
      LevelName = character(),
      IsBreakpoint = logical(),
      Path = character()
    )
    empty_paths <- vpro_hierarchy_to_table(empty_nodes)
    if (as == "nodes") {
      return(empty_nodes)
    }
    if (as == "paths") {
      return(empty_paths)
    }
    return(structure(list(table = NA_character_, nodes = empty_nodes, paths = empty_paths), class = "vpro_hierarchy"))
  }

  dbc <- vpro_sqlite_ro(ws$hierarchy_path)
  on.exit(DBI::dbDisconnect(dbc), add = TRUE)
  raw <- DBI::dbGetQuery(dbc, paste("SELECT * FROM", vpro_quote_ident(h_tbl)))
  if ("Flag" %in% names(raw)) {
    raw$Flag <- vpro_access_to_logical(raw$Flag)
  }

  raw_nm <- trimws(ifelse(is.na(raw$Name), "", as.character(raw$Name)))
  raw$IsBreakpoint <- startsWith(raw_nm, "~")
  raw$CleanName <- sub("^~+", "", raw_nm)
  lvl_int <- suppressWarnings(as.integer(raw$Level))
  raw$LevelName <- ifelse(
    !is.na(lvl_int) & lvl_int >= 1L & lvl_int <= 11L,
    .vpro_hierarchy_level_names[lvl_int],
    NA_character_
  )

  # Build root-to-node "/" Path string
  id_chr <- as.character(raw$ID)
  par_chr <- ifelse(is.na(raw$Parent), NA_character_, as.character(raw$Parent))
  idx_map <- stats::setNames(seq_along(id_chr), id_chr)
  raw$Path <- vapply(
    seq_len(nrow(raw)),
    function(i) {
      parts <- character()
      cur <- i
      seen <- integer()
      while (!is.na(cur) && !(cur %in% seen)) {
        parts <- c(raw$CleanName[[cur]], parts)
        seen <- c(seen, cur)
        p <- par_chr[[cur]]
        if (is.na(p) || !(p %in% names(idx_map))) {
          break
        }
        nxt <- idx_map[[p]]
        if (identical(nxt, cur)) {
          break
        }
        cur <- nxt
      }
      paste(parts, collapse = " / ")
    },
    character(1)
  )

  nodes_tbl <- tibble::as_tibble(raw)
  paths_tbl <- vpro_hierarchy_to_table(nodes_tbl)

  if (as == "nodes") {
    return(nodes_tbl)
  }
  if (as == "paths") {
    return(paths_tbl)
  }
  structure(
    list(
      table = h_tbl,
      nodes = nodes_tbl,
      paths = paths_tbl
    ),
    class = "vpro_hierarchy"
  )
}

#' @export
print.vpro_hierarchy <- function(x, ...) {
  n_brk <- sum(x$nodes$IsBreakpoint, na.rm = TRUE)
  cli::cli_h3("vpro_hierarchy: {.val {if (is.na(x$table)) '<none>' else x$table}}")
  cli::cli_bullets(c(
    "*" = "Nodes: {nrow(x$nodes)} ({n_brk} `~` breakpoint{?s})",
    "*" = "Terminal site-unit paths: {nrow(x$paths)}"
  ))
  invisible(x)
}

#' @export
as_tibble.vpro_hierarchy <- function(x, ...) {
  x$paths
}
