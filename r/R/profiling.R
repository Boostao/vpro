# Plot Profiling Ordered Set-Algebra Engine -----------------------------------

.vpro_normalize_operation <- function(op) {
  if (is.null(op) || length(op) == 0L || is.na(op[[1L]])) {
    rlang::abort("Profile rule `operation` must be one of 'Common', 'Add', or 'Subtract'.")
  }
  raw <- tolower(trimws(as.character(op[[1L]])))
  if (raw %in% c("common", "common plots", "intersect", "intersection")) {
    return("Common")
  }
  if (raw %in% c("add", "add plots", "union")) {
    return("Add")
  }
  if (raw %in% c("subtract", "subtract plots", "remove", "difference", "diff")) {
    return("Subtract")
  }
  rlang::abort(paste0("Unsupported profile operation `", op[[1L]], "`. Expected 'Common', 'Add', or 'Subtract'."))
}

.vpro_normalize_operator <- function(operator, value) {
  if (is.null(operator) || length(operator) == 0L || is.na(operator[[1L]]) || !nzchar(trimws(as.character(operator[[1L]])))) {
    rlang::abort("Profile rule `operator` must be a non-empty string.")
  }
  op_up <- toupper(gsub("[[:space:]]+", " ", trimws(as.character(operator[[1L]]))))
  val_is_null_token <- is.null(value) ||
    length(value) == 0L ||
    (length(value) == 1L && (is.na(value[[1L]]) || identical(toupper(trimws(as.character(value[[1L]]))), "NULL")))

  if (op_up %in% c("=", "==")) {
    return(if (val_is_null_token) "IS NULL" else "=")
  }
  if (op_up %in% c("<>", "!=")) {
    return(if (val_is_null_token) "IS NOT NULL" else "!=")
  }
  if (op_up %in% c(">", ">=", "<", "<=", "LIKE", "NOT LIKE", "IS NULL", "IS NOT NULL")) {
    return(op_up)
  }
  rlang::abort(paste0("Unsupported profile operator `", operator[[1L]], "`."))
}

#' Construct a tidy plot-profiling rule
#'
#' Creates a single declarative plot-profiling criterion for [vpro_profile()],
#' supporting `Veg` (or `Lump`), `Env` (including joined `Admin` columns),
#' `Humus`, and `Mineral` tables and ordered set-algebra operations
#' (`"Common"` = \eqn{\cap}, `"Add"` = \eqn{\cup}, `"Subtract"` = \eqn{\setminus}).
#'
#' @param table Target table domain: `"Veg"`, `"Lump"`, `"Env"`, `"Humus"`,
#'   `"Mineral"`, or `"Admin"`.
#' @param field Column name for `"Env"`, `"Admin"`, `"Humus"`, or `"Mineral"`
#'   rules (optional for `"Veg"` / `"Lump"` rules).
#' @param operator Comparison operator: `"="`, `"!="` / `"<>"`, `">"`, `">="`,
#'   `"<"`, `"<="`, `"LIKE"`, `"NOT LIKE"`, `"IS NULL"`, or `"IS NOT NULL"`.
#' @param value Scalar comparison threshold or pattern (`NULL` for `"IS NULL"` /
#'   `"IS NOT NULL"`).
#' @param species Species (or lump) code for `"Veg"` / `"Lump"` rules (e.g.
#'   `"TSUGHET"`, `"VACCMEM"`).
#' @param layer Optional vegetation layer or aggregate selector for `"Veg"` /
#'   `"Lump"` rules: `"Any"` (default maximum across layers), `"SumAll"`,
#'   `"SumA"` / `"A"`, `"SumB"` / `"B"`, `"C"`, `"D"`, or an individual layer
#'   code (`"1".."10"`, `"5a".."5c"`, `"TotalA"`, `"TotalB"`).
#' @param operation Ordered set-algebra operation: `"Common"` (intersection),
#'   `"Add"` (union), or `"Subtract"` (set difference).
#' @return An S3 object of class `vpro_profile_rule`.
#' @export
vpro_profile_rule <- function(
  table = c("Veg", "Lump", "Env", "Humus", "Mineral", "Admin"),
  field = NULL,
  operator = "=",
  value = NULL,
  species = NULL,
  layer = NULL,
  operation = c("Common", "Add", "Subtract")
) {
  .vpro_register_wave2b_s3()
  if (length(table) > 1L) {
    table <- table[[1L]]
  }
  if (!is.character(table) || length(table) != 1L || is.na(table)) {
    rlang::abort("`table` must be one of 'Veg', 'Lump', 'Env', 'Humus', 'Mineral', or 'Admin'.")
  }
  tbl_low <- tolower(trimws(table))
  tbl_map <- c(
    "veg" = "Veg",
    "lump" = "Lump",
    "env" = "Env",
    "admin" = "Admin",
    "humus" = "Humus",
    "mineral" = "Mineral"
  )
  if (!(tbl_low %in% names(tbl_map))) {
    rlang::abort(paste0("Unsupported `table` value `", table, "`."))
  }
  norm_table <- unname(tbl_map[[tbl_low]])

  if (length(operation) > 1L) {
    operation <- operation[[1L]]
  }
  norm_op <- .vpro_normalize_operation(operation)
  norm_operator <- .vpro_normalize_operator(operator, value)

  norm_val <- if (norm_operator %in% c("IS NULL", "IS NOT NULL")) {
    NULL
  } else {
    value[[1L]]
  }

  if (norm_table %in% c("Veg", "Lump")) {
    if (is.null(species) || length(species) != 1L || is.na(species) || !nzchar(trimws(as.character(species)))) {
      rlang::abort("`species` must be a non-empty species code for `Veg` / `Lump` profiling rules.")
    }
    norm_species <- toupper(trimws(as.character(species)))
    norm_layer <- if (is.null(layer) || length(layer) == 0L || is.na(layer[[1L]]) || !nzchar(trimws(as.character(layer[[1L]])))) {
      "Any"
    } else {
      trimws(as.character(layer[[1L]]))
    }
    norm_field <- if (is.null(field) || length(field) == 0L || is.na(field[[1L]]) || !nzchar(trimws(as.character(field[[1L]])))) {
      if (identical(norm_table, "Lump")) "LumpCode" else "Species"
    } else {
      trimws(as.character(field[[1L]]))
    }
  } else {
    if (is.null(field) || length(field) != 1L || is.na(field) || !nzchar(trimws(as.character(field)))) {
      rlang::abort(paste0("`field` must be a non-empty column name for `", norm_table, "` profiling rules."))
    }
    norm_field <- trimws(as.character(field))
    norm_species <- NA_character_
    norm_layer <- NA_character_
  }

  structure(
    list(
      table = norm_table,
      field = norm_field,
      operator = norm_operator,
      value = norm_val,
      species = norm_species,
      layer = norm_layer,
      operation = norm_op
    ),
    class = "vpro_profile_rule"
  )
}

#' Print a `vpro_profile_rule` specification
#'
#' @param x A `vpro_profile_rule` object.
#' @param ... Unused; included for S3 method compatibility.
#' @return `x`, invisibly.
#' @export
print.vpro_profile_rule <- function(x, ...) {
  desc <- .vpro_describe_rule(x)
  cli::cli_text("<vpro_profile_rule [{x$operation}] {.field {desc}}>")
  invisible(x)
}

.vpro_describe_rule <- function(r) {
  rhs <- if (r$operator %in% c("IS NULL", "IS NOT NULL")) {
    r$operator
  } else {
    paste(r$operator, r$value)
  }
  if (r$table %in% c("Veg", "Lump")) {
    paste0(r$table, ":", r$species, "[", r$layer, "] ", rhs)
  } else {
    paste0(r$table, ".", r$field, " ", rhs)
  }
}

.vpro_like_to_regex <- function(pattern) {
  pat <- as.character(pattern)
  chars <- strsplit(enc2utf8(pat), "", fixed = TRUE)[[1L]]
  meta <- c(".", "+", "^", "$", "(", ")", "[", "]", "{", "}", "|", "\\")
  out <- character(length(chars))
  for (i in seq_along(chars)) {
    ch <- chars[[i]]
    if (ch %in% c("*", "%")) {
      out[[i]] <- ".*"
    } else if (ch == "?") {
      out[[i]] <- "."
    } else if (ch %in% meta) {
      out[[i]] <- paste0("\\", ch)
    } else {
      out[[i]] <- ch
    }
  }
  paste0("^", paste(out, collapse = ""), "$")
}

.vpro_eval_field_predicate <- function(vec, operator, value) {
  n <- length(vec)
  if (n == 0L) return(logical(0))

  is_miss <- is.na(vec) | (is.character(vec) & !nzchar(trimws(vec)))
  if (identical(operator, "IS NULL")) {
    return(is_miss)
  }
  if (identical(operator, "IS NOT NULL")) {
    return(!is_miss)
  }

  if (operator %in% c("LIKE", "NOT LIKE")) {
    rx <- .vpro_like_to_regex(value)
    chr <- ifelse(is_miss, "", trimws(as.character(vec)))
    hit <- !is_miss & grepl(rx, chr, ignore.case = TRUE, perl = TRUE)
    return(if (identical(operator, "LIKE")) hit else (!is_miss & !hit))
  }

  if (is.logical(vec)) {
    target_lgl <- vpro_access_to_logical(value)
    if (is.na(target_lgl)) return(rep(FALSE, n))
    if (identical(operator, "=")) return(!is.na(vec) & (vec == target_lgl))
    if (identical(operator, "!=")) return(!is.na(vec) & (vec != target_lgl))
    rlang::abort(paste0("Operator `", operator, "` is not valid for logical column."))
  }

  val_num <- suppressWarnings(as.numeric(value))
  vec_num <- if (is.numeric(vec)) {
    as.numeric(vec)
  } else {
    suppressWarnings(as.numeric(trimws(as.character(vec))))
  }
  non_miss_numeric <- all(is.na(vec[!is_miss]) == is.na(vec_num[!is_miss]))

  if (!is.na(val_num) && (is.numeric(vec) || operator %in% c(">", ">=", "<", "<=") || (any(!is_miss) && non_miss_numeric))) {
    ok <- !is.na(vec_num)
    res <- switch(
      operator,
      "=" = ok & (vec_num == val_num),
      "!=" = ok & (vec_num != val_num),
      ">" = ok & (vec_num > val_num),
      ">=" = ok & (vec_num >= val_num),
      "<" = ok & (vec_num < val_num),
      "<=" = ok & (vec_num <= val_num),
      rep(FALSE, n)
    )
    return(res)
  }

  val_low <- tolower(trimws(as.character(value)))
  chr_low <- tolower(trimws(ifelse(is_miss, "", as.character(vec))))
  switch(
    operator,
    "=" = !is_miss & (chr_low == val_low),
    "!=" = !is_miss & (chr_low != val_low),
    ">" = !is_miss & (chr_low > val_low),
    ">=" = !is_miss & (chr_low >= val_low),
    "<" = !is_miss & (chr_low < val_low),
    "<=" = !is_miss & (chr_low <= val_low),
    rep(FALSE, n)
  )
}

.vpro_coerce_rules <- function(rules) {
  if (inherits(rules, "vpro_profile_rule")) {
    return(list(rules))
  }
  if (is.data.frame(rules)) {
    if (nrow(rules) == 0L) return(list())
    nms <- tolower(names(rules))
    pick_col <- function(cands, default = NULL) {
      ix <- match(cands, nms)
      ix <- ix[!is.na(ix)]
      if (length(ix) > 0L) rules[[ix[[1L]]]] else default
    }
    ord_col <- pick_col("order", seq_len(nrow(rules)))
    ord_ix <- order(suppressWarnings(as.numeric(ord_col)), seq_len(nrow(rules)))
    rules <- rules[ord_ix, , drop = FALSE]
    nms <- tolower(names(rules))

    tbl_c <- pick_col("table")
    fld_c <- pick_col("field")
    opr_c <- pick_col("operator")
    val_c <- pick_col(c("value", "criteria"))
    spp_c <- pick_col("species")
    lyr_c <- pick_col("layer")
    opn_c <- pick_col("operation", rep("Common", nrow(rules)))

    out <- vector("list", nrow(rules))
    for (i in seq_len(nrow(rules))) {
      out[[i]] <- vpro_profile_rule(
        table = if (is.null(tbl_c)) "Veg" else tbl_c[[i]],
        field = if (is.null(fld_c)) NULL else fld_c[[i]],
        operator = if (is.null(opr_c)) "=" else opr_c[[i]],
        value = if (is.null(val_c)) NULL else val_c[[i]],
        species = if (is.null(spp_c)) NULL else spp_c[[i]],
        layer = if (is.null(lyr_c)) NULL else lyr_c[[i]],
        operation = opn_c[[i]]
      )
    }
    return(out)
  }
  if (is.list(rules)) {
    return(lapply(rules, function(item) {
      if (inherits(item, "vpro_profile_rule")) return(item)
      if (is.list(item)) return(do.call(vpro_profile_rule, item))
      rlang::abort("Each element of `rules` must be a `vpro_profile_rule` object.")
    }))
  }
  rlang::abort("`rules` must be a `vpro_profile_rule`, a list of `vpro_profile_rule` objects, or a rule `data.frame`.")
}

.vpro_eval_veg_rule <- function(rule, universe_plots, raw_veg_dt, lump_map_vec) {
  target_spp <- rule$species
  dt <- data.table::copy(raw_veg_dt)

  if (nrow(dt) > 0L && length(lump_map_vec) > 0L) {
    if (identical(rule$table, "Lump")) {
      # Strict Lump rule: match species mapped into LumpCode via *_Lump (matching V7mdlPlotProfiling)
      m <- lump_map_vec[dt[["Species"]]]
      keep_l <- !is.na(m) & (unname(m) == target_spp)
      dt <- dt[keep_l]
      if (nrow(dt) > 0L) {
        data.table::set(dt, j = "Species", value = rep(target_spp, nrow(dt)))
      }
    } else {
      m <- lump_map_vec[dt[["Species"]]]
      hit <- !is.na(m)
      if (any(hit)) {
        spp_new <- dt[["Species"]]
        spp_new[hit] <- unname(m[hit])
        data.table::set(dt, j = "Species", value = spp_new)
      }
      dt <- dt[dt[["Species"]] == target_spp]
    }
  } else if (nrow(dt) > 0L) {
    if (identical(rule$table, "Lump") && length(lump_map_vec) == 0L) {
      dt <- dt[0L]
    } else {
      dt <- dt[dt[["Species"]] == target_spp]
    }
  }

  cov_cols <- setdiff(names(dt), c("PlotNumber", "Species"))
  lyr <- tolower(trimws(rule$layer))

  resolve_cols <- function(l_key) {
    if (l_key %in% c("any", "sumall", "total", "all")) {
      return(intersect(
        c("Cover1", "Cover2", "Cover3", "TotalA", "Cover4", "Cover5", "Cover5a", "Cover5b", "Cover5c", "TotalB", "Cover6", "Cover7", "Cover8", "Cover9", "Cover10"),
        cov_cols
      ))
    }
    if (l_key %in% c("suma", "a")) {
      return(intersect(c("Cover1", "Cover2", "Cover3", "TotalA"), cov_cols))
    }
    if (l_key %in% c("sumb", "b")) {
      return(intersect(c("Cover4", "Cover5", "Cover5a", "Cover5b", "Cover5c", "TotalB"), cov_cols))
    }
    if (l_key == "c") {
      return(intersect("Cover6", cov_cols))
    }
    if (l_key %in% c("sumd", "d")) {
      return(intersect(c("Cover7", "Cover8", "Cover9", "Cover10"), cov_cols))
    }
    cand <- if (startsWith(l_key, "cover") || startsWith(l_key, "total")) l_key else paste0("cover", l_key)
    hit <- cov_cols[tolower(cov_cols) == cand]
    if (length(hit) == 0L) {
      rlang::abort(paste0("Unknown vegetation profiling layer `", rule$layer, "`."))
    }
    hit
  }

  sel_cols <- resolve_cols(lyr)
  plot_cov <- stats::setNames(rep(NA_real_, length(universe_plots)), universe_plots)

  if (nrow(dt) > 0L && length(sel_cols) > 0L) {
    # Collapse lumped/multiple rows per plot by summing each cover column with VPro's 99% lumped cap
    sum_na <- function(x) {
      ok <- x[!is.na(x)]
      if (length(ok) == 0L) NA_real_ else if (length(ok) == 1L) ok else min(sum(ok), 99.0)
    }
    by_plot <- dt[, lapply(.SD, sum_na), by = "PlotNumber", .SDcols = sel_cols]

    # Prefer Cover1..3 over TotalA and Cover4..5c over TotalB when summing
    if (lyr %in% c("sumall", "total", "all", "suma", "a") && "TotalA" %in% sel_cols) {
      sa <- intersect(c("Cover1", "Cover2", "Cover3"), sel_cols)
      if (length(sa) > 0L) {
        has_sa <- rowSums(!is.na(as.matrix(by_plot[, sa, with = FALSE]))) > 0L
        ta <- by_plot[["TotalA"]]
        ta[has_sa] <- NA_real_
        data.table::set(by_plot, j = "TotalA", value = ta)
      }
    }
    if (lyr %in% c("sumall", "total", "all", "sumb", "b") && "TotalB" %in% sel_cols) {
      sb <- intersect(c("Cover4", "Cover5", "Cover5a", "Cover5b", "Cover5c"), sel_cols)
      if (length(sb) > 0L) {
        has_sb <- rowSums(!is.na(as.matrix(by_plot[, sb, with = FALSE]))) > 0L
        tb <- by_plot[["TotalB"]]
        tb[has_sb] <- NA_real_
        data.table::set(by_plot, j = "TotalB", value = tb)
      }
    }

    mat <- as.matrix(by_plot[, sel_cols, with = FALSE])
    has_val <- rowSums(!is.na(mat)) > 0L
    if (any(has_val)) {
      m_sub <- mat[has_val, , drop = FALSE]
      agg_vals <- if (identical(lyr, "any")) {
        apply(m_sub, 1L, max, na.rm = TRUE)
      } else {
        rowSums(m_sub, na.rm = TRUE)
      }
      p_sub <- by_plot[["PlotNumber"]][has_val]
      in_u <- p_sub %in% names(plot_cov)
      plot_cov[p_sub[in_u]] <- agg_vals[in_u]
    }
  }

  op <- rule$operator
  if (identical(op, "IS NULL")) {
    return(universe_plots[is.na(plot_cov) | plot_cov <= 0])
  }
  if (identical(op, "IS NOT NULL")) {
    return(universe_plots[!is.na(plot_cov) & plot_cov > 0])
  }

  thr <- suppressWarnings(as.numeric(rule$value))
  if (is.na(thr)) {
    rlang::abort(paste0("Vegetation cover criterion must be numeric (got `", rule$value, "`)."))
  }

  if (identical(op, "=") && thr == 0) {
    return(universe_plots[is.na(plot_cov) | plot_cov == 0])
  }
  if (identical(op, "!=") && thr == 0) {
    return(universe_plots[!is.na(plot_cov) & plot_cov != 0])
  }

  if (op %in% c("<", "<=")) {
    cov_zero <- ifelse(is.na(plot_cov), 0.0, plot_cov)
    keep <- if (identical(op, "<")) cov_zero < thr else cov_zero <= thr
    return(universe_plots[keep])
  }

  present <- !is.na(plot_cov)
  keep <- switch(
    op,
    "=" = present & (abs(plot_cov - thr) < 1e-6),
    "!=" = present & (abs(plot_cov - thr) >= 1e-6),
    ">" = present & (plot_cov > thr),
    ">=" = present & (plot_cov >= thr),
    rep(FALSE, length(plot_cov))
  )
  universe_plots[keep]
}

#' Filter plots via ordered VPro Plot Profiling set algebra
#'
#' Evaluates either a tidy sequence of [vpro_profile_rule()] specifications (or rule
#' `data.frame`) or a stored `*_Profile` SQLite table (such as `Sample_Profile`)
#' using VPro's ordered set algebra (`Add` = \eqn{\cup}, `Common` = \eqn{\cap},
#' `Subtract` = \eqn{\setminus}) across `Env`, `Admin`, `Humus`, `Mineral`,
#' `Veg`, and `Lump` criteria (including species absence via `IS NULL` or `= 0`).
#' In alignment with VPro's Plot Profiling engine, `Table == "Lump"` rules
#' apply taxonomic lumping (`*_Lump`) while `Table == "Veg"` rules match raw
#' `Species` codes directly.
#'
#' @param ws A `vpro_workspace` handle.
#' @param rules Optional [vpro_profile_rule()], list of [vpro_profile_rule()]
#'   objects, or rule `data.frame`. When `NULL`, reads `profile_table` (or the
#'   default `<Project>_Profile` table in `ws`).
#' @param profile_table Optional `*_Profile` table name inside `ws$project_path`
#'   (with or without `_Profile` suffix).
#' @param scope Plot universe: `"project"` (all `<Project>_Env` plots, default)
#'   or `"su"` (active `ws$su` plots).
#' @param lump Logical (`TRUE` uses active `ws$lump`), `FALSE` (default), a
#'   `*_Lump` table name, or a two-column `data.frame(SppCode, LumpCode)`,
#'   applied to `Table == "Lump"` rules (falling back to active `ws$lump` when
#'   `lump = FALSE` on explicit `"Lump"` rules). `Table == "Veg"` rules always
#'   match raw unlumped `Species` codes.
#' @return An S3 object of class `vpro_profile_result` containing `$plots`
#'   (retained literal character `PlotNumber` vector), `$env` (retained
#'   [vpro_env()] tibble), and `$steps` (step-by-step diagnostic tibble).
#' @export
vpro_profile <- function(
  ws,
  rules = NULL,
  profile_table = NULL,
  scope = c("project", "su"),
  lump = FALSE
) {
  vpro_assert_workspace(ws)
  .vpro_register_wave2b_s3()
  scope <- match.arg(scope)

  if (is.null(rules)) {
    tables <- vpro_sqlite_physical_tables(ws$project_path)
    prof_tbl <- vpro_resolve_table_suffix(tables, profile_table, "Profile", default_prefix = ws$project)
    if (is.null(prof_tbl)) {
      rlang::abort("No `rules` supplied and no `*_Profile` table found in workspace.")
    }
    dbc_prof <- vpro_sqlite_ro(ws$project_path)
    prof_df <- tryCatch(
      DBI::dbGetQuery(
        dbc_prof,
        paste0("SELECT * FROM ", vpro_quote_ident(prof_tbl), ' ORDER BY "Order", rowid')
      ),
      finally = DBI::dbDisconnect(dbc_prof)
    )
    rule_list <- .vpro_coerce_rules(prof_df)
  } else {
    rule_list <- .vpro_coerce_rules(rules)
  }

  env_all <- vpro_env(ws, scope = scope, include_admin = TRUE, exclude_modifiers = FALSE)
  universe_plots <- as.character(env_all$PlotNumber)

  if (length(rule_list) == 0L || length(universe_plots) == 0L) {
    empty_steps <- tibble::tibble(
      step = integer(),
      operation = character(),
      description = character(),
      matched_n = integer(),
      retained_n = integer()
    )
    return(structure(
      list(
        plots = character(),
        env = env_all[0L, , drop = FALSE],
        steps = empty_steps,
        scope = scope
      ),
      class = "vpro_profile_result"
    ))
  }

  # Lazy-load Veg / Lump / Soil tables only when needed by at least one rule
  rule_tables <- vapply(rule_list, `[[`, character(1), "table")
  raw_veg_dt <- NULL
  veg_lump_vec <- character()
  table_lump_vec <- character()

  if (any(rule_tables %in% c("Veg", "Lump"))) {
    dbc_veg <- vpro_sqlite_ro(ws$project_path)
    on.exit(DBI::dbDisconnect(dbc_veg), add = TRUE)
    veg_tbl <- paste0(ws$project, "_Veg")
    vf <- DBI::dbListFields(dbc_veg, veg_tbl)
    layer_cols <- intersect(
      c("Cover1", "Cover2", "Cover3", "TotalA", "Cover4", "Cover5", "Cover5a", "Cover5b", "Cover5c", "TotalB", "Cover6", "Cover7", "Cover8", "Cover9", "Cover10"),
      vf
    )
    sel_sql <- paste(
      c(
        'CAST("PlotNumber" AS TEXT) AS "PlotNumber"',
        'UPPER(TRIM(CAST("Species" AS TEXT))) AS "Species"',
        vapply(layer_cols, function(cc) paste0("CAST(", vpro_quote_ident(cc), " AS REAL) AS ", vpro_quote_ident(cc)), character(1))
      ),
      collapse = ", "
    )
    v_raw <- vpro_query_scoped_plots(
      dbc_veg,
      vpro_quote_ident(veg_tbl),
      universe_plots,
      select_cols = sel_sql,
      where_extra = '"Species" IS NOT NULL AND TRIM(CAST("Species" AS TEXT)) <> \'\''
    )
    raw_veg_dt <- data.table::as.data.table(v_raw)
    if (nrow(raw_veg_dt) > 0L) {
      data.table::set(raw_veg_dt, j = "PlotNumber", value = as.character(raw_veg_dt[["PlotNumber"]]))
      data.table::set(raw_veg_dt, j = "Species", value = toupper(trimws(as.character(raw_veg_dt[["Species"]]))))
      for (cc in layer_cols) {
        data.table::set(raw_veg_dt, j = cc, value = vpro_narrow_float32(as.numeric(raw_veg_dt[[cc]])))
      }
    }
    if (any(rule_tables == "Lump")) {
      lt_explicit <- vpro_lump_map(ws, lump = if (identical(lump, FALSE) || is.null(lump)) TRUE else lump)
      if (nrow(lt_explicit) > 0L) table_lump_vec <- stats::setNames(lt_explicit$LumpCode, lt_explicit$SppCode)
    }
  }

  humus_df <- if (any(rule_tables == "Humus")) vpro_soil(ws, scope = scope, type = "humus") else NULL
  mineral_df <- if (any(rule_tables == "Mineral")) vpro_soil(ws, scope = scope, type = "mineral") else NULL

  eval_soil <- function(soil_tbl, rule) {
    col_ix <- match(tolower(rule$field), tolower(names(soil_tbl)))
    if (is.na(col_ix)) {
      rlang::abort(paste0("Column `", rule$field, "` not found in `<Project>_", rule$table, "`."))
    }
    if (identical(rule$operator, "IS NULL")) {
      non_null_plots <- unique(soil_tbl$PlotNumber[.vpro_eval_field_predicate(soil_tbl[[col_ix]], "IS NOT NULL", NULL)])
      return(setdiff(universe_plots, non_null_plots))
    }
    hits <- .vpro_eval_field_predicate(soil_tbl[[col_ix]], rule$operator, rule$value)
    matched_p <- unique(as.character(soil_tbl$PlotNumber[hits]))
    universe_plots[universe_plots %in% matched_p]
  }

  retained <- character()
  step_rows <- vector("list", length(rule_list))

  for (s_i in seq_along(rule_list)) {
    r <- rule_list[[s_i]]
    matched <- if (r$table %in% c("Env", "Admin")) {
      col_ix <- match(tolower(r$field), tolower(names(env_all)))
      if (is.na(col_ix)) {
        rlang::abort(paste0("Column `", r$field, "` not found in `<Project>_Env` / `<Project>_Admin`."))
      }
      hits <- .vpro_eval_field_predicate(env_all[[col_ix]], r$operator, r$value)
      universe_plots[hits]
    } else if (identical(r$table, "Humus")) {
      eval_soil(humus_df, r)
    } else if (identical(r$table, "Mineral")) {
      eval_soil(mineral_df, r)
    } else {
      lvec <- if (identical(r$table, "Lump")) table_lump_vec else veg_lump_vec
      .vpro_eval_veg_rule(r, universe_plots, raw_veg_dt, lvec)
    }

    if (s_i == 1L) {
      retained <- switch(
        r$operation,
        "Add" = universe_plots[universe_plots %in% matched],
        "Common" = universe_plots[universe_plots %in% matched],
        "Subtract" = universe_plots[!(universe_plots %in% matched)]
      )
    } else {
      retained <- switch(
        r$operation,
        "Add" = universe_plots[universe_plots %in% c(retained, matched)],
        "Common" = retained[retained %in% matched],
        "Subtract" = retained[!(retained %in% matched)]
      )
    }

    step_rows[[s_i]] <- tibble::tibble(
      step = as.integer(s_i),
      operation = r$operation,
      description = .vpro_describe_rule(r),
      matched_n = as.integer(length(matched)),
      retained_n = as.integer(length(retained))
    )
  }

  steps_tbl <- do.call(rbind, step_rows)
  env_ret <- env_all[match(retained, env_all$PlotNumber), , drop = FALSE]

  structure(
    list(
      plots = as.character(retained),
      env = tibble::as_tibble(env_ret),
      steps = steps_tbl,
      scope = scope
    ),
    class = "vpro_profile_result"
  )
}

#' Print a `vpro_profile_result` summary
#'
#' @param x A `vpro_profile_result` object.
#' @param ... Unused; included for S3 method compatibility.
#' @return `x`, invisibly.
#' @export
print.vpro_profile_result <- function(x, ...) {
  cli::cli_h3("vpro_profile_result ({length(x$plots)} retained plot{?s} across {nrow(x$steps)} step{?s})")
  for (i in seq_len(nrow(x$steps))) {
    st <- x$steps[i, ]
    cli::cli_bullets(c(
      "*" = "Step {st$step} [{st$operation}] {st$description} -> matched {st$matched_n}, retained {st$retained_n}"
    ))
  }
  invisible(x)
}

#' Coerce `vpro_profile_result` to a tibble
#'
#' @param x A `vpro_profile_result` object.
#' @param ... Unused; included for S3 method compatibility.
#' @return The `$env` tibble of retained plots.
#' @export
as_tibble.vpro_profile_result <- function(x, ...) {
  x$env
}
