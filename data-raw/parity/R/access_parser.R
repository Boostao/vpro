# Parsers for text exports produced by Access SaveAsText.
parity_object_name <- function(path) tools::file_path_sans_ext(basename(path))
parity_classify <- function(name, family, text = "") {
  x <- tolower(paste(name, family, text))
  domain <- if (grepl("plot|site|sample", x)) {
    "survey"
  } else if (grepl("species|veg|flora", x)) {
    "vegetation"
  } else if (grepl("user|auth|login", x)) {
    "administration"
  } else if (grepl("report|print", x)) {
    "reporting"
  } else {
    "general"
  }
  classification <- if (family %in% c("Forms", "Reports")) {
    "ui"
  } else if (family == "Queries") {
    "data_query"
  } else if (family == "Macros") {
    "automation"
  } else if (grepl("table|relationship", family, ignore.case = TRUE)) {
    "schema"
  } else {
    "business_logic"
  }
  c(domain = domain, classification = classification)
}
parity_vba_procedures <- function(lines, object_name, family, path) {
  start_rx <- "^\\s*(?:(Public|Private|Friend)\\s+)?(?:(Static)\\s+)?(Sub|Function|Property\\s+(?:Get|Let|Set))\\s+([A-Za-z_][A-Za-z0-9_]*)\\b"
  starts <- grep(start_rx, lines, ignore.case = TRUE, perl = TRUE)
  if (!length(starts)) {
    return(data.frame())
  }
  out <- lapply(seq_along(starts), function(i) {
    from <- starts[i]
    to <- if (i < length(starts)) starts[i + 1L] - 1L else length(lines)
    ends <- grep("^\\s*End\\s+(Sub|Function|Property)\\b", lines[from:to], ignore.case = TRUE, perl = TRUE)
    if (length(ends)) {
      to <- from + ends[1L] - 1L
    }
    m <- regexec(start_rx, lines[from], ignore.case = TRUE, perl = TRUE)
    z <- regmatches(lines[from], m)[[1]]
    body <- paste(lines[from:to], collapse = "\n")
    meaningful <- lines[from:to]
    meaningful <- meaningful[
      !grepl(
        "^\\s*(?:'|$|Attribute\\b|(?:Public|Private|Friend|Static|\\s)*(?:Sub|Function|Property)\\b|End\\s+(?:Sub|Function|Property)\\b)",
        meaningful,
        ignore.case = TRUE,
        perl = TRUE
      )
    ]
    data.frame(
      id = parity_id("procedure", object_name, z[5]),
      source_object = object_name,
      family = family,
      type = "procedure",
      name = z[5],
      path = path,
      line_start = from,
      line_end = to,
      visibility = ifelse(nzchar(z[2]), tolower(z[2]), "public"),
      declaration_kind = gsub("\\s+", "_", tolower(z[4])),
      empty = !length(meaningful),
      dynamic_sql = parity_flag(body, "\\b(CurrentDb|OpenRecordset|DoCmd\\.OpenQuery|SELECT |INSERT |UPDATE |DELETE )"),
      error_suppression = parity_flag(body, "On\\s+Error\\s+(Resume\\s+Next|GoTo)"),
      filesystem = parity_flag(body, "\\b(Dir|FileSystemObject|Open |Kill |MkDir|FileCopy|Shell)\\b"),
      registry = parity_flag(body, "\\b(GetSetting|SaveSetting|Reg(Read|Write)|Registry)\\b"),
      com_or_shell = parity_flag(body, "\\b(CreateObject|GetObject|Shell|FollowHyperlink)\\b"),
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, out)
}
parity_events <- function(lines, object_name, family, path) {
  # Name is tracked from nearest Access Begin control section; root is the form/report.
  begin <- "^(\\s*)Begin\\s+(?:[A-Za-z]+)"
  control <- object_name
  rows <- list()
  n <- 0L
  for (i in seq_along(lines)) {
    if (grepl(begin, lines[i], perl = TRUE)) {
      control <- object_name
    }
    nm <- regexec('^\\s*Name\\s*=\\s*"([^"]+)"', lines[i], perl = TRUE)
    hit <- regmatches(lines[i], nm)[[1]]
    if (length(hit)) {
      control <- hit[2]
    }
    ev <- regexec('^\\s*(On[A-Za-z0-9_]+)\\s*=\\s*"\\[Event Procedure\\]"', lines[i], perl = TRUE)
    hit <- regmatches(lines[i], ev)[[1]]
    if (length(hit)) {
      n <- n + 1L
      handler <- paste0(control, "_", sub("^On", "", hit[2]))
      rows[[n]] <- data.frame(
        id = parity_id("event", object_name, control, hit[2]),
        source_object = object_name,
        family = family,
        type = "event",
        name = hit[2],
        control = control,
        expected_handler = handler,
        path = path,
        line_start = i,
        line_end = i,
        stringsAsFactors = FALSE
      )
    }
  }
  if (!length(rows)) data.frame() else do.call(rbind, rows)
}
parity_query_sql <- function(lines) {
  first <- grep('^\\s*dbMemo "SQL"', lines)
  if (!length(first)) {
    return("")
  }
  # SQL starts after the property label and continues through indented quoted fragments.
  selected <- lines[first[1]]
  j <- first[1] + 1L
  while (j <= length(lines) && grepl('^\\s+"', lines[j])) {
    selected <- c(selected, lines[j])
    j <- j + 1L
  }
  selected[1] <- sub('^\\s*dbMemo "SQL"\\s*=', '', selected[1])
  quoted <- unlist(lapply(selected, function(line) regmatches(line, gregexpr('"[^"]*"', line, perl = TRUE))[[1]]), use.names = FALSE)
  if (!length(quoted)) {
    return("")
  }
  quoted <- sub('^"', '', quoted)
  quoted <- sub('"$', '', quoted)
  sql <- paste(quoted, collapse = "")
  sql <- gsub('""', '"', sql, fixed = TRUE)
  sql <- gsub("\\\\015", "\r", sql)
  gsub("\\\\012", "\n", sql)
}
parity_macro_actions <- function(lines, object_name, path) {
  ix <- grep('^\\s*Action\\s*=\\s*"', lines)
  if (!length(ix)) {
    return(data.frame())
  }
  out <- lapply(ix, function(i) {
    a <- sub('^\\s*Action\\s*=\\s*"([^"]+)".*$', "\\1", lines[i])
    nearby <- paste(lines[i:min(length(lines), i + 4L)], collapse = " ")
    code <- sub('.*Argument\\s*=\\s*"=?([^"(]+).*', "\\1", nearby)
    data.frame(
      id = parity_id("macro", object_name, i),
      source_object = object_name,
      family = "Macros",
      type = "macro_action",
      name = a,
      action = a,
      run_code = ifelse(identical(tolower(a), "runcode"), code, ""),
      path = path,
      line_start = i,
      line_end = i,
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, out)
}
