parity_families <- c("Forms", "Modules", "Queries", "Reports", "Macros", "Tables_Def", "Relationships", "Tables_Design")
parity_empty <- function(cols) as.data.frame(setNames(replicate(length(cols), character(), simplify = FALSE), cols), stringsAsFactors = FALSE)
parity_bind <- function(xs) {
  xs <- Filter(function(x) is.data.frame(x) && nrow(x), xs)
  if (!length(xs)) {
    return(data.frame())
  }
  names_all <- sort(unique(unlist(lapply(xs, names))))
  xs <- lapply(xs, function(x) {
    for (n in setdiff(names_all, names(x))) {
      x[[n]] <- NA
    }
    x[names_all]
  })
  do.call(rbind, xs)
}
parity_discover_source <- function(source_root) {
  files <- unlist(lapply(parity_families, function(f) list.files(file.path(source_root, f), recursive = TRUE, full.names = TRUE, all.files = FALSE)), use.names = FALSE)
  files <- files[file.exists(files) & !grepl("(^|/)(FORM_IMPL_SPEC_.*\\.md|ui_.*\\.R)$", files, ignore.case = TRUE, perl = TRUE)]
  data.frame(file = sort(files), stringsAsFactors = FALSE)
}
parity_inventory_source <- function(source_root) {
  files <- parity_discover_source(source_root)$file
  manifests <- list()
  items <- list()
  query_rows <- list()
  for (i in seq_along(files)) {
    f <- files[i]
    rel <- parity_relpath(f, source_root)
    family <- strsplit(rel, "/", fixed = TRUE)[[1]][1]
    obj <- parity_object_name(f)
    r <- parity_read_text(f)
    manifests[[i]] <- data.frame(
      id = parity_id("object", family, obj),
      relative_path = rel,
      family = family,
      object_name = obj,
      object_type = tolower(sub("s$", "", family)),
      bytes = as.numeric(file.info(f)$size),
      encoding = r$encoding,
      hash_algorithm = "md5",
      hash = unname(tools::md5sum(f)),
      stringsAsFactors = FALSE
    )
    items[[length(items) + 1L]] <- data.frame(
      id = parity_id("object", family, obj),
      source_object = obj,
      family = family,
      type = "object",
      name = obj,
      path = rel,
      line_start = NA_integer_,
      line_end = NA_integer_,
      stringsAsFactors = FALSE
    )
    if (family %in% c("Forms", "Reports", "Modules")) {
      items[[length(items) + 1L]] <- parity_vba_procedures(r$lines, obj, family, rel)
    }
    if (family %in% c("Forms", "Reports")) {
      items[[length(items) + 1L]] <- parity_events(r$lines, obj, family, rel)
    }
    if (family == "Macros") {
      items[[length(items) + 1L]] <- parity_macro_actions(r$lines, obj, rel)
    }
    if (family == "Queries") {
      query_rows[[length(query_rows) + 1L]] <- data.frame(
        id = parity_id("query_sql", obj),
        source_object = obj,
        path = rel,
        sql = parity_query_sql(r$lines),
        stringsAsFactors = FALSE
      )
    }
  }
  list(manifest = parity_bind(manifests), items = parity_bind(items), queries = parity_bind(query_rows))
}
parity_inventory_target <- function(target_root) {
  roots <- file.path(target_root, c("R", "inst/app", "tests/testthat"))
  rfiles <- unlist(
    lapply(roots[dir.exists(roots)], function(root) {
      list.files(root, pattern = "\\.[Rr]$", recursive = TRUE, full.names = TRUE)
    }),
    use.names = FALSE
  )
  rfiles <- sort(unique(rfiles[!grepl("(^|/)ui_.*\\.R$", rfiles, ignore.case = TRUE)]))
  tests <- rfiles[grepl("(^|/)tests/testthat/", rfiles)]
  parity_bind(c(
    lapply(rfiles, parity_r_functions, root = target_root),
    lapply(tests, parity_test_declarations, root = target_root)
  ))
}
parity_write_tree <- function(parity, output_root) {
  counts <- aggregate(
    list(discrepancies = parity$id),
    list(domain = parity$domain, classification = parity$classification),
    length
  )
  counts <- counts[order(counts$domain, counts$classification), , drop = FALSE]
  mmd <- c("flowchart TD", "  root[VPRO parity discrepancies]")
  domains <- unique(counts$domain)
  for (i in seq_along(domains)) {
    rows <- counts[counts$domain == domains[i], , drop = FALSE]
    mmd <- c(mmd, sprintf("  root --> d%d[%s: %d]", i, domains[i], sum(rows$discrepancies)))
    for (j in seq_len(nrow(rows))) {
      mmd <- c(mmd, sprintf("  d%d --> d%dc%d[%s: %d]", i, i, j, rows$classification[j], rows$discrepancies[j]))
    }
  }
  writeLines(mmd, file.path(output_root, "discrepancy-tree.mmd"), useBytes = TRUE)
  writeLines(c("# VPRO parity discrepancy tree", "", "```mermaid", mmd, "```"), file.path(output_root, "discrepancy-tree.md"), useBytes = TRUE)

  tree_dir <- file.path(output_root, "trees")
  dir.create(tree_dir, recursive = TRUE, showWarnings = FALSE)
  old <- list.files(tree_dir, full.names = TRUE)
  if (length(old)) {
    unlink(old)
  }
  groups <- split(parity, paste(parity$family, parity$source_object, sep = "::"))
  index <- lapply(groups, function(rows) {
    object <- rows$source_object[1]
    family <- rows$family[1]
    file <- paste0(gsub("[^A-Za-z0-9._-]+", "-", tolower(paste(family, object, sep = "-"))), ".mmd")
    children <- rows[rows$type != "object", , drop = FALSE]
    lines <- c("flowchart TD", paste0("  root[", gsub("[^A-Za-z0-9 _.:/-]", "", paste(family, object, sep = ": ")), "]"))
    if (!nrow(children)) {
      lines <- c(lines, "  root --> n1[object-level review required]")
    } else {
      children <- children[order(children$type, children$name, children$line_start), , drop = FALSE]
      for (i in seq_len(nrow(children))) {
        label <- gsub("[^A-Za-z0-9 _.:/-]", "", paste(children$type[i], children$name[i], children$status[i], sep = ": "))
        lines <- c(lines, sprintf("  root --> n%d[%s]", i, label))
      }
    }
    writeLines(lines, file.path(tree_dir, file), useBytes = TRUE)
    data.frame(family = family, source_object = object, discrepancy_count = nrow(rows), tree = file.path("trees", file), stringsAsFactors = FALSE)
  })
  parity_bind(index)
}
parity_apply_overrides <- function(parity, target, path) {
  if (!file.exists(path)) {
    return(parity)
  }
  overrides <- read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
  required <- c("source_id", "target_id", "status", "notes")
  if (!identical(names(overrides), required)) {
    stop("Parity overrides must contain: ", paste(required, collapse = ", "))
  }
  if (anyDuplicated(overrides$source_id)) {
    stop("Parity override source IDs must be unique.")
  }
  missing_source <- setdiff(overrides$source_id, parity$id)
  missing_target <- setdiff(overrides$target_id, target$id)
  if (length(missing_source)) {
    stop("Unknown parity override source IDs: ", paste(missing_source, collapse = ", "))
  }
  if (length(missing_target)) {
    stop("Unknown parity override target IDs: ", paste(missing_target, collapse = ", "))
  }
  index <- match(overrides$source_id, parity$id)
  parity$status[index] <- overrides$status
  parity$target_id[index] <- overrides$target_id
  parity$notes[index] <- overrides$notes
  parity
}

parity_run_inventory <- function(source_root, target_root, output_root) {
  dir.create(output_root, recursive = TRUE, showWarnings = FALSE)
  src <- parity_inventory_source(source_root)
  target <- parity_inventory_target(target_root)
  if (!nrow(src$items)) {
    stop("No canonical Access objects found under source root: ", source_root)
  }
  cls <- t(vapply(seq_len(nrow(src$items)), function(i) parity_classify(src$items$name[i], src$items$family[i]), c(domain = "", classification = "")))
  parity <- cbind(
    src$items,
    domain = cls[, "domain"],
    classification = cls[, "classification"],
    status = "unmapped",
    target_id = "",
    notes = "initial deterministic inventory",
    stringsAsFactors = FALSE
  )
  target_names <- split(target$id, tolower(target$name))
  for (i in seq_len(nrow(parity))) {
    matches <- unique(target_names[[tolower(parity$name[i])]])
    if (length(matches) == 1L) {
      parity$status[i] <- "candidate"
      parity$target_id[i] <- matches
      parity$notes[i] <- "exact symbol match; manual review required"
    }
  }
  parity <- parity_apply_overrides(
    parity,
    target,
    file.path(dirname(output_root), "reviewed-overrides.csv")
  )
  unresolved <- parity[!grepl("^reviewed_", parity$status), , drop = FALSE]
  parity_write_csv(src$manifest, file.path(output_root, "manifest.csv"))
  parity_write_csv(src$items, file.path(output_root, "source-items.csv"))
  parity_write_csv(src$queries, file.path(output_root, "query-sql.csv"))
  parity_write_csv(target, file.path(output_root, "target-items.csv"))
  parity_write_csv(parity, file.path(output_root, "parity.csv"))
  parity_write_csv(unresolved, file.path(output_root, "unresolved.csv"))
  tree_index <- parity_write_tree(parity, output_root)
  parity_write_csv(tree_index, file.path(output_root, "tree-index.csv"))
  summary <- list(
    source_objects = nrow(src$manifest),
    source_items = nrow(src$items),
    target_items = nrow(target),
    candidates = sum(parity$status == "candidate"),
    reviewed = sum(grepl("^reviewed_", parity$status)),
    unresolved = nrow(unresolved),
    object_trees = nrow(tree_index),
    hash_algorithm = "md5",
    source_root = normalizePath(source_root, winslash = "/"),
    target_root = normalizePath(target_root, winslash = "/")
  )
  writeLines(parity_json(summary), file.path(output_root, "summary.json"), useBytes = TRUE)
  invisible(summary)
}
