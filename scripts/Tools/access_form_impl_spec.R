#!/usr/bin/env Rscript

trim_ws <- function(x) gsub("^\\s+|\\s+$", "", x)
`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0L && nzchar(as.character(a)[1])) as.character(a)[1] else b

escape_md <- function(x) {
  x <- as.character(x %||% "")
  x <- gsub("\\|", "\\\\|", x)
  x <- gsub("\\r", "", x)
  x <- gsub("\\n", " ", x)
  x
}

safe_name <- function(node, fallback = "") {
  nm <- node$props$Name %||% fallback
  trim_ws(nm)
}

read_lines_auto <- function(path) {
  con_raw <- file(path, open = "rb")
  on.exit(close(con_raw), add = TRUE)
  bom <- readBin(con_raw, what = "raw", n = 3L)

  if (length(bom) >= 2L && identical(as.integer(bom[1:2]), c(255L, 254L))) {
    con <- file(path, open = "r", encoding = "UTF-16LE")
    on.exit(close(con), add = TRUE)
    return(readLines(con, warn = FALSE))
  }
  if (length(bom) >= 2L && identical(as.integer(bom[1:2]), c(254L, 255L))) {
    con <- file(path, open = "r", encoding = "UTF-16BE")
    on.exit(close(con), add = TRUE)
    return(readLines(con, warn = FALSE))
  }

  con <- file(path, open = "r", encoding = "UTF-8")
  on.exit(close(con), add = TRUE)
  out <- tryCatch(readLines(con, warn = FALSE), error = function(e) NULL)
  if (!is.null(out)) return(out)

  con_l1 <- file(path, open = "r", encoding = "latin1")
  on.exit(close(con_l1), add = TRUE)
  readLines(con_l1, warn = FALSE)
}

split_form_and_code <- function(path) {
  lines <- read_lines_auto(path)
  idx <- grep("^\\s*CodeBehindForm\\s*$", lines, ignore.case = TRUE)
  if (length(idx) == 0L) {
    return(list(form_lines = lines, code_lines = character(0), code_start_line = NA_integer_))
  }
  i <- idx[1]
  list(
    form_lines = lines[seq_len(i - 1L)],
    code_lines = lines[(i + 1L):length(lines)],
    code_start_line = i + 1L
  )
}

extract_sql_objects <- function(sql_text) {
  if (is.null(sql_text) || !nzchar(sql_text)) return(character(0))
  s <- gsub("\\s+", " ", sql_text)
  patterns <- c(
    "\\bFROM\\s+([A-Za-z0-9_\\[\\]\\.]+)",
    "\\bJOIN\\s+([A-Za-z0-9_\\[\\]\\.]+)",
    "\\bINTO\\s+([A-Za-z0-9_\\[\\]\\.]+)",
    "\\bUPDATE\\s+([A-Za-z0-9_\\[\\]\\.]+)"
  )
  out <- character(0)
  for (p in patterns) {
    m <- gregexpr(p, s, ignore.case = TRUE, perl = TRUE)
    hits <- regmatches(s, m)[[1]]
    if (length(hits) == 0L) next
    for (h in hits) {
      g <- sub(p, "\\1", h, ignore.case = TRUE, perl = TRUE)
      g <- gsub("^\\[|\\]$", "", g)
      out <- c(out, trim_ws(g))
    }
  }
  unique(out[nzchar(out)])
}

get_event_suffix <- function(prop_name) {
  if (grepl("^On", prop_name)) return(sub("^On", "", prop_name))
  prop_name
}

collect_ui_tree <- function(form_node) {
  entries <- list()
  by_id <- new.env(parent = emptyenv())

  walk <- function(node, parent_id = NA_integer_, depth = 0L, path = "Form") {
    nm <- safe_name(node, fallback = node$type)
    this_path <- if (depth == 0L) "Form" else paste0(path, " > ", node$type, "[", nm, "]")

    event_props <- names(node$props)
    if (is.null(event_props)) event_props <- character(0)
    event_props <- event_props[vapply(event_props, function(nm2) {
      val <- node$props[[nm2]] %||% ""
      identical(trim_ws(val), "[Event Procedure]")
    }, logical(1))]

    source_props <- c("RecordSource", "ControlSource", "RowSource", "RowSourceType", "SourceObject", "LinkChildFields", "LinkMasterFields")
    source_vals <- list()
    for (sp in source_props) {
      if (!is.null(node$props[[sp]]) && nzchar(trim_ws(node$props[[sp]]))) {
        source_vals[[sp]] <- node$props[[sp]]
      }
    }

    entry <- list(
      id = node$id,
      type = node$type,
      name = safe_name(node, fallback = paste0(node$type, "_", node$id)),
      caption = node$props$Caption %||% "",
      parent_id = parent_id,
      depth = depth,
      path = this_path,
      left = node$props$Left %||% "",
      top = node$props$Top %||% "",
      width = node$props$Width %||% "",
      height = node$props$Height %||% "",
      event_props = event_props,
      source_vals = source_vals,
      node_ref = node
    )

    entries[[length(entries) + 1L]] <<- entry
    by_id[[as.character(node$id)]] <- entry

    for (ch in node$children) {
      if (startsWith(ch$type, "__PROP") || ch$type == "__BEGIN__") next
      walk(ch, parent_id = node$id, depth = depth + 1L, path = this_path)
    }
  }

  walk(form_node)
  list(entries = entries, by_id = by_id)
}

extract_procedures <- function(code_lines, code_start_line = NA_integer_) {
  procs <- list()
  n <- length(code_lines)
  i <- 1L

  start_pat <- "^\\s*(Private|Public|Friend)?\\s*(Sub|Function)\\s+([A-Za-z_][A-Za-z0-9_]*)\\s*\\("
  end_pat <- "^\\s*End\\s+(Sub|Function)\\b"

  while (i <= n) {
    ln <- code_lines[i]
    if (grepl(start_pat, ln, perl = TRUE, ignore.case = TRUE)) {
      name <- sub(start_pat, "\\3", ln, perl = TRUE, ignore.case = TRUE)
      kind <- sub(start_pat, "\\2", ln, perl = TRUE, ignore.case = TRUE)
      start_i <- i
      j <- i + 1L
      while (j <= n && !grepl(end_pat, code_lines[j], perl = TRUE, ignore.case = TRUE)) {
        j <- j + 1L
      }
      end_i <- if (j <= n) j else n
      body <- code_lines[start_i:end_i]

      procs[[length(procs) + 1L]] <- list(
        name = name,
        kind = kind,
        start_line = if (is.na(code_start_line)) start_i else (code_start_line + start_i - 1L),
        end_line = if (is.na(code_start_line)) end_i else (code_start_line + end_i - 1L),
        body = body
      )
      i <- end_i + 1L
      next
    }
    i <- i + 1L
  }

  procs
}

extract_called_functions <- function(proc_body) {
  lines <- gsub("'.*$", "", proc_body)
  txt <- paste(lines, collapse = "\n")
  m <- gregexpr("\\b([A-Za-z_][A-Za-z0-9_]*)\\s*\\(", txt, perl = TRUE)
  hits <- regmatches(txt, m)[[1]]
  if (length(hits) == 0L) return(character(0))
  toks <- sub("\\($", "", trim_ws(gsub("\\s+", "", hits)))

  skip <- c(
    "if", "for", "while", "select", "switch", "with", "msgbox", "nz", "trim", "lcase", "ucase",
    "len", "left", "right", "mid", "replace", "split", "instr", "isnull", "isnumeric", "cstr", "clng",
    "csng", "cdbl", "date", "time", "now", "array"
  )
  toks <- toks[!tolower(toks) %in% skip]
  unique(toks)
}

extract_me_control_refs <- function(proc_body) {
  txt <- paste(proc_body, collapse = "\n")
  m <- gregexpr("\\bMe\\.([A-Za-z_][A-Za-z0-9_]*)", txt, perl = TRUE)
  hits <- regmatches(txt, m)[[1]]
  if (length(hits) == 0L) return(character(0))
  unique(sub("^Me\\.", "", hits))
}

find_module_defs <- function(module_dir) {
  if (!dir.exists(module_dir)) return(list())
  files <- list.files(module_dir, pattern = "\\.txt$", full.names = TRUE)
  defs <- list()
  pat <- "^\\s*(Private|Public|Friend)?\\s*(Sub|Function)\\s+([A-Za-z_][A-Za-z0-9_]*)\\b"

  for (f in files) {
    lines <- tryCatch(read_lines_auto(f), error = function(e) character(0))
    if (length(lines) == 0L) next
    for (i in seq_along(lines)) {
      ln <- lines[i]
      if (grepl(pat, ln, perl = TRUE, ignore.case = TRUE)) {
        nm <- sub(pat, "\\3", ln, perl = TRUE, ignore.case = TRUE)
        defs[[tolower(nm)]] <- c(defs[[tolower(nm)]], sprintf("%s:%d", basename(f), i))
      }
    }
  }
  defs
}

infer_event_handlers <- function(tree_entries) {
  out <- list()
  for (e in tree_entries) {
    if (length(e$event_props) == 0L) next
    for (ep in e$event_props) {
      suffix <- get_event_suffix(ep)
      owner <- if (tolower(e$type) == "form") "Form" else e$name
      handler <- paste0(owner, "_", suffix)
      out[[length(out) + 1L]] <- list(
        control_name = e$name,
        control_type = e$type,
        event_property = ep,
        handler_name = handler,
        control_path = e$path
      )
    }
  }
  out
}

build_tree_markdown <- function(entries) {
  by_parent <- split(entries, vapply(entries, function(x) as.character(x$parent_id), character(1)))

  fmt_node <- function(e) {
    cap <- if (nzchar(e$caption)) paste0(" caption=\"", escape_md(e$caption), "\"") else ""
    src_keys <- names(e$source_vals)
    src_part <- if (length(src_keys) > 0L) paste0(" sources=", paste(src_keys, collapse = ",")) else ""
    ev_part <- if (length(e$event_props) > 0L) paste0(" events=", paste(e$event_props, collapse = ",")) else ""
    paste0("- ", e$type, " `", e$name, "`", cap, src_part, ev_part)
  }

  render_children <- function(parent_id, depth = 0L) {
    key <- as.character(parent_id)
    children <- by_parent[[key]]
    if (is.null(children) || length(children) == 0L) return(character(0))
    out <- character(0)
    for (ch in children) {
      out <- c(out, paste0(strrep("  ", depth), fmt_node(ch)))
      out <- c(out, render_children(ch$id, depth + 1L))
    }
    out
  }

  root <- entries[[1]]
  c(fmt_node(root), render_children(root$id, 1L))
}

write_spec <- function(form_file, spec_path, recursive = TRUE, visited = character(0), module_defs = NULL) {
  norm <- normalizePath(form_file, winslash = "/", mustWork = FALSE)
  if (norm %in% visited) return(character(0))
  visited <- c(visited, norm)

  parts <- split_form_and_code(form_file)

  parser_env <- new.env(parent = baseenv())
  sys.source(file.path("scripts", "Tools", "access_form_to_shiny.R"), envir = parser_env)

  parsed <- parser_env$parse_access_form_text(form_file)
  form_node <- parser_env$find_first_by_type(parsed, "Form")
  if (is.null(form_node)) stop(sprintf("No Form block found in %s", form_file))

  tree <- collect_ui_tree(form_node)
  entries <- tree$entries

  handlers <- infer_event_handlers(entries)
  procs <- extract_procedures(parts$code_lines, parts$code_start_line)
  proc_map <- setNames(procs, tolower(vapply(procs, function(p) p$name, character(1))))

  if (is.null(module_defs)) {
    module_defs <- find_module_defs(file.path(dirname(form_file), "..", "Modules"))
  }

  form_name <- form_node$props$Name %||% tools::file_path_sans_ext(basename(form_file))
  form_caption <- form_node$props$Caption %||% ""
  record_source <- form_node$props$RecordSource %||% ""

  source_rows <- list()
  data_objects <- character(0)
  for (e in entries) {
    if (length(e$source_vals) == 0L) next
    for (k in names(e$source_vals)) {
      v <- e$source_vals[[k]]
      source_rows[[length(source_rows) + 1L]] <- sprintf("| %s | %s | %s | %s |", escape_md(e$name), e$type, k, escape_md(v))
      if (grepl("Source$", k) || k %in% c("RecordSource", "RowSource")) {
        data_objects <- c(data_objects, extract_sql_objects(v))
      }
      if (k == "ControlSource" && nzchar(v)) data_objects <- c(data_objects, v)
    }
  }
  data_objects <- unique(data_objects[nzchar(data_objects)])

  event_rows <- list()
  for (h in handlers) {
    proc <- proc_map[[tolower(h$handler_name)]]
    found <- !is.null(proc)
    event_rows[[length(event_rows) + 1L]] <- sprintf(
      "| %s | %s | %s | %s | %s |",
      escape_md(h$control_name),
      h$control_type,
      h$event_property,
      h$handler_name,
      if (found) paste0("Yes (line ", proc$start_line, ")") else "No local handler"
    )
  }

  detected_event_props <- sort(unique(vapply(handlers, function(h) h$event_property, character(1))))
  event_rule_lines <- character(0)
  if (length(detected_event_props) > 0L) {
    for (ep in detected_event_props) {
      suffix <- get_event_suffix(ep)
      event_rule_lines <- c(
        event_rule_lines,
        paste0("- `", ep, "` -> control scope handler `", "<ControlName>_", suffix, "` ; form scope handler `Form_", suffix, "`")
      )
    }
  }

  event_trace_rows <- list()
  for (h in handlers) {
    proc <- proc_map[[tolower(h$handler_name)]]
    if (is.null(proc)) {
      event_trace_rows[[length(event_trace_rows) + 1L]] <- sprintf(
        "| %s | %s | %s | Missing local handler | None | None | None found |",
        escape_md(h$control_name),
        h$event_property,
        h$handler_name
      )
      next
    }

    calls <- extract_called_functions(proc$body)
    refs <- extract_me_control_refs(proc$body)
    local_proc_names <- vapply(procs, function(x) x$name, character(1))
    local_calls <- calls[tolower(calls) %in% tolower(local_proc_names)]
    external_calls <- setdiff(calls, local_calls)

    ext_locs <- character(0)
    for (fn in external_calls) {
      key <- tolower(fn)
      if (!is.null(module_defs[[key]])) {
        ext_locs <- c(ext_locs, paste0(fn, " -> ", paste(unique(module_defs[[key]]), collapse = "; ")))
      }
    }

    event_trace_rows[[length(event_trace_rows) + 1L]] <- sprintf(
      "| %s | %s | %s | lines %d-%d | %s | %s | %s |",
      escape_md(h$control_name),
      h$event_property,
      h$handler_name,
      proc$start_line,
      proc$end_line,
      if (length(local_calls) > 0L) escape_md(paste(unique(local_calls), collapse = ", ")) else "None",
      if (length(external_calls) > 0L) escape_md(paste(unique(external_calls), collapse = ", ")) else "None",
      if (length(ext_locs) > 0L) escape_md(paste(ext_locs, collapse = " | ")) else "None found"
    )
  }

  proc_sections <- character(0)
  for (p in procs) {
    calls <- extract_called_functions(p$body)
    refs <- extract_me_control_refs(p$body)

    local_calls <- calls[tolower(calls) %in% tolower(vapply(procs, function(x) x$name, character(1)))]
    external_calls <- setdiff(calls, local_calls)

    ext_locs <- character(0)
    for (fn in external_calls) {
      key <- tolower(fn)
      if (!is.null(module_defs[[key]])) {
        ext_locs <- c(ext_locs, paste0(fn, " -> ", paste(unique(module_defs[[key]]), collapse = "; ")))
      }
    }

    proc_sections <- c(
      proc_sections,
      paste0("### ", p$name, " (", p$kind, ")"),
      paste0("- Lines: ", p$start_line, "-", p$end_line),
      paste0("- Local calls: ", if (length(local_calls) > 0L) paste(unique(local_calls), collapse = ", ") else "None"),
      paste0("- External calls: ", if (length(external_calls) > 0L) paste(unique(external_calls), collapse = ", ") else "None"),
      paste0("- Module definitions: ", if (length(ext_locs) > 0L) paste(ext_locs, collapse = " | ") else "None found in Modules/"),
      paste0("- Me.<control> references: ", if (length(refs) > 0L) paste(unique(refs), collapse = ", ") else "None"),
      ""
    )
  }

  subforms <- Filter(function(e) identical(e$type, "Subform") && !is.null(e$source_vals$SourceObject), entries)
  sub_lines <- character(0)
  generated_sub_specs <- character(0)
  for (sf in subforms) {
    src <- sf$source_vals$SourceObject
    src_clean <- gsub('^"|"$', "", trim_ws(src))
    parts_src <- strsplit(src_clean, "\\.")[[1]]
    base <- parts_src[length(parts_src)]
    candidate <- file.path(dirname(form_file), paste0(base, ".txt"))
    exists <- file.exists(candidate)
    sub_lines <- c(sub_lines, sprintf("- %s (%s) -> %s", sf$name, src_clean, if (exists) basename(candidate) else "missing source file"))

    if (recursive && exists) {
      out <- file.path(dirname(candidate), paste0("FORM_IMPL_SPEC_", tools::file_path_sans_ext(basename(candidate)), ".md"))
      generated_sub_specs <- c(generated_sub_specs, write_spec(candidate, out, recursive = TRUE, visited = visited, module_defs = module_defs))
    }
  }

  tree_md <- build_tree_markdown(entries)

  lines <- c(
    paste0("# FORM_IMPL_SPEC_", tools::file_path_sans_ext(basename(form_file))),
    "",
    "## 1) Form Summary",
    paste0("- Source form file: `", form_file, "`"),
    paste0("- Form name: `", form_name, "`"),
    paste0("- Caption: ", if (nzchar(form_caption)) paste0("`", escape_md(form_caption), "`") else "(none)"),
    paste0("- RecordSource: ", if (nzchar(record_source)) paste0("`", escape_md(record_source), "`") else "(none)"),
    "",
    "## 2) Parent-Child UI Tree",
    "",
    tree_md,
    "",
    "## 3) Control Source Dependencies",
    "| Control | Type | Source Property | Value |",
    "|---|---|---|---|",
    if (length(source_rows) > 0L) unlist(source_rows) else "| (none) | - | - | - |",
    "",
    "## 4) Event Procedure Mappings",
    "| Control | Type | Event Property | Expected Handler | Local Procedure Found |",
    "|---|---|---|---|---|",
    if (length(event_rows) > 0L) unlist(event_rows) else "| (none) | - | - | - | - |",
    "",
    "## 4b) Event Resolution Rules",
    "- Access event properties with `[Event Procedure]` map by removing the `On` prefix and binding to VBA handlers.",
    if (length(event_rule_lines) > 0L) event_rule_lines else "- No `[Event Procedure]` bindings detected.",
    "",
    "## 4c) Event-to-Logic Trace",
    "| Control | Event Property | Handler | Local Handler Status | Local Calls | External Calls | Module Definitions |",
    "|---|---|---|---|---|---|---|",
    if (length(event_trace_rows) > 0L) unlist(event_trace_rows) else "| (none) | - | - | - | - | - | - |",
    "",
    "## 5) VBA Procedure Graph (Form Scope)",
    if (length(proc_sections) > 0L) proc_sections else "No local VBA procedures parsed.",
    "",
    "## 6) Data + VBA Dependencies",
    paste0("- Data objects inferred from SQL and source properties: ", if (length(data_objects) > 0L) paste(sort(unique(data_objects)), collapse = ", ") else "None detected"),
    "- Global/module calls should be resolved in `Modules/*.txt` using function/sub names listed above.",
    "",
    "## 7) Subforms (Recursive Architecture)",
    if (length(sub_lines) > 0L) sub_lines else "- None",
    "",
    "## 8) Reimplementation Guidance",
    "- Recreate this form as a component tree preserving parent-child relationships and absolute layout constraints.",
    "- Implement event handlers by mapping Access event property -> handler naming convention (`<Control>_<Event>` or `Form_<Event>`).",
    "- Port local procedures first; then resolve external calls in Modules to shared services/utilities.",
    "- Treat `RecordSource`, `ControlSource`, `RowSource` and related fields as data-binding contracts.",
    ""
  )

  writeLines(lines, spec_path, useBytes = TRUE)
  c(spec_path, generated_sub_specs)
}

convert_input <- function(input_path, recursive = TRUE) {
  if (dir.exists(input_path)) {
    forms <- list.files(input_path, pattern = "\\.txt$", full.names = TRUE)
    outputs <- character(0)
    for (f in forms) {
      out <- file.path(dirname(f), paste0("FORM_IMPL_SPEC_", tools::file_path_sans_ext(basename(f)), ".md"))
      generated <- tryCatch(
        write_spec(f, out, recursive = recursive),
        error = function(e) {
          message(sprintf("[ERROR] %s: %s", basename(f), e$message))
          character(0)
        }
      )
      if (length(generated) > 0L) {
        message(sprintf("[OK] %s -> %s", basename(f), basename(out)))
        outputs <- c(outputs, generated)
      }
    }
    return(unique(outputs))
  }

  out <- file.path(dirname(input_path), paste0("FORM_IMPL_SPEC_", tools::file_path_sans_ext(basename(input_path)), ".md"))
  generated <- write_spec(input_path, out, recursive = recursive)
  message(sprintf("Generated: %s", out))
  unique(generated)
}

main <- function() {
  args <- commandArgs(trailingOnly = TRUE)
  if (length(args) == 0L) {
    cat(
      "Access form implementation-spec generator\n\n",
      "Usage:\n",
      "  Rscript scripts/Tools/access_form_impl_spec.R [--recursive=true|false] <path/to/form.txt|Forms_dir>\n",
      sep = ""
    )
    quit(status = 1)
  }

  recursive <- TRUE
  while (length(args) > 0L && grepl("^--", args[1])) {
    if (grepl("^--recursive=", args[1])) {
      v <- tolower(trim_ws(sub("^--recursive=", "", args[1])))
      recursive <- v %in% c("true", "1", "yes", "y")
      args <- args[-1]
      next
    }
    break
  }

  if (length(args) == 0L) stop("Missing input path")
  input_path <- args[1]
  if (!file.exists(input_path)) stop(sprintf("Input path does not exist: %s", input_path))

  outs <- convert_input(input_path, recursive = recursive)
  message(sprintf("Generated %d spec file(s).", length(unique(outs))))
}

if (identical(environment(), globalenv())) {
  main()
}
