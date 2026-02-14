#!/usr/bin/env Rscript

# Convert Microsoft Access form exports (Application.SaveAsText) to Shiny UI R code.
# Usage:
#   Rscript scripts/Tools/access_form_to_shiny.R <path/to/form.txt> [path/to/ui_form.R]
#   Rscript scripts/Tools/access_form_to_shiny.R <path/to/Forms_directory>

new_node <- local({
  counter <- 0L
  function(type) {
    counter <<- counter + 1L
    e <- new.env(parent = emptyenv())
    e$id <- counter
    e$type <- type
    e$props <- list()
    e$children <- list()
    e
  }
})

trim_ws <- function(x) gsub("^\\s+|\\s+$", "", x)

read_lines_auto <- function(path) {
  con_raw <- file(path, open = "rb")
  on.exit(close(con_raw), add = TRUE)
  bom <- readBin(con_raw, what = "raw", n = 3L)

  if (length(bom) >= 2L && identical(as.integer(bom[1:2]), c(255L, 254L))) {
    con <- file(path, open = "r", encoding = "UTF-16LE")
    on.exit(close(con), add = TRUE)
    return(suppressWarnings(readLines(con, warn = FALSE)))
  }
  if (length(bom) >= 2L && identical(as.integer(bom[1:2]), c(254L, 255L))) {
    con <- file(path, open = "r", encoding = "UTF-16BE")
    on.exit(close(con), add = TRUE)
    return(suppressWarnings(readLines(con, warn = FALSE)))
  }

  con <- file(path, open = "r", encoding = "UTF-8")
  on.exit(close(con), add = TRUE)
  out <- tryCatch(suppressWarnings(readLines(con, warn = FALSE)), error = function(e) NULL)
  if (!is.null(out)) return(out)

  con_l1 <- file(path, open = "r", encoding = "latin1")
  on.exit(close(con_l1), add = TRUE)
  suppressWarnings(readLines(con_l1, warn = FALSE))
}

strip_quotes <- function(x) {
  x <- trim_ws(x)
  if (grepl('^".*"$', x)) {
    x <- substring(x, 2L, nchar(x) - 1L)
  }
  x <- gsub('""', '"', x, fixed = TRUE)
  x <- gsub('\\\\+"', '"', x, perl = TRUE)
  x <- gsub('\\015\\012', '\n', x, fixed = TRUE)
  x <- gsub('\\013\\010', '\n', x, fixed = TRUE)
  x <- gsub('\\n', '\n', x, fixed = TRUE)
  x
}

decode_access_caption <- function(x) {
  if (is.null(x) || length(x) == 0L) return("")
  out <- as.character(x)[1]
  if (!nzchar(out)) return("")
  out <- gsub("&&", "[[AMP]]", out, fixed = TRUE)
  out <- gsub("&", "", out, fixed = TRUE)
  out <- gsub("[[AMP]]", "&", out, fixed = TRUE)
  out
}

escape_html_text <- function(x) {
  x <- gsub("&", "&amp;", x, fixed = TRUE)
  x <- gsub("<", "&lt;", x, fixed = TRUE)
  x <- gsub(">", "&gt;", x, fixed = TRUE)
  x <- gsub('"', "&quot;", x, fixed = TRUE)
  x
}

access_caption_to_html <- function(x) {
  if (is.null(x) || length(x) == 0L) return("")
  s <- as.character(x)[1]
  if (!nzchar(s)) return("")

  chars <- strsplit(s, "", fixed = TRUE)[[1]]
  out <- character(0)
  i <- 1L
  n <- length(chars)

  while (i <= n) {
    ch <- chars[i]
    if (identical(ch, "&")) {
      if (i < n && identical(chars[i + 1L], "&")) {
        out <- c(out, "&amp;")
        i <- i + 2L
        next
      }
      if (i < n) {
        out <- c(out, paste0("<u>", escape_html_text(chars[i + 1L]), "</u>"))
        i <- i + 2L
        next
      }
      out <- c(out, "&amp;")
      i <- i + 1L
      next
    }

    if (identical(ch, "\r")) {
      i <- i + 1L
      next
    }
    if (identical(ch, "\n")) {
      out <- c(out, "<br/>")
      i <- i + 1L
      next
    }

    out <- c(out, escape_html_text(ch))
    i <- i + 1L
  }

  paste(out, collapse = "")
}

caption_html_expr <- function(x) {
  sprintf('shiny::HTML("%s")', escape_r_string(access_caption_to_html(x)))
}

escape_r_string <- function(x) {
  x <- gsub("\n", " ", x, fixed = TRUE)
  encoded <- encodeString(x, quote = '"', na.encode = FALSE)
  if (nchar(encoded) >= 2L && startsWith(encoded, '"') && substr(encoded, nchar(encoded), nchar(encoded)) == '"') {
    encoded <- substr(encoded, 2L, nchar(encoded) - 1L)
  }
  encoded
}

parse_num <- function(x) {
  if (is.null(x) || length(x) == 0L) return(NA_real_)
  x <- trim_ws(as.character(x)[1])
  if (identical(x, "") || identical(tolower(x), "notdefault")) return(NA_real_)
  out <- suppressWarnings(as.numeric(x))
  ifelse(is.na(out), NA_real_, out)
}

twips_to_px <- function(x) {
  if (is.na(x)) return(NA_integer_)
  as.integer(round(x / 15))
}

scale_px <- function(px, scale = 1.8) {
  if (is.na(px)) return(NA_integer_)
  as.integer(round(px * scale))
}

access_color_to_css <- function(x) {
  n <- parse_num(x)
  if (is.na(n)) return(NULL)

  if (n < 0) {
    sys_colors <- list(
      `-2147483643` = "#000000",
      `-2147483642` = "#808080",
      `-2147483640` = "#C0C0C0",
      `-2147483638` = "#000080",
      `-2147483636` = "#008080",
      `-2147483635` = "#E0E0E0",
      `-2147483633` = "#F0F0F0",
      `-2147483630` = "#000000",
      `-2147483629` = "#FFFFFF",
      `-2147483626` = "#3399FF"
    )
    key <- as.character(as.integer(n))
    return(if (!is.null(sys_colors[[key]])) sys_colors[[key]] else NULL)
  }

  n <- as.integer(n)
  r <- bitwAnd(n, 255L)
  g <- bitwAnd(bitwShiftR(n, 8L), 255L)
  b <- bitwAnd(bitwShiftR(n, 16L), 255L)
  sprintf("#%02X%02X%02X", r, g, b)
}

text_align_css <- function(x) {
  n <- parse_num(x)
  if (is.na(n)) return(NULL)
  if (n == 1) return("left")
  if (n == 2) return("center")
  if (n == 3) return("right")
  NULL
}

find_first_descendant_by_type <- function(node, target_type) {
  if (identical(node$type, target_type)) return(node)
  if (length(node$children) == 0L) return(NULL)
  for (ch in node$children) {
    got <- find_first_descendant_by_type(ch, target_type)
    if (!is.null(got)) return(got)
  }
  NULL
}

resolve_form_back_color <- function(form_node) {
  direct <- access_color_to_css(form_node$props$BackColor)
  if (!is.null(direct)) return(direct)

  section_types <- c("FormHeader", "Section", "FormFooter", "PageHeader", "PageFooter")
  sections <- list()

  walk <- function(node) {
    for (ch in node$children) {
      if (ch$type %in% section_types) {
        nm <- if (!is.null(ch$props$Name)) tolower(trim_ws(ch$props$Name)) else ""
        sections[[length(sections) + 1L]] <<- list(type = ch$type, name = nm, color = access_color_to_css(ch$props$BackColor))
      }
      walk(ch)
    }
  }
  walk(form_node)

  pick <- function(pred) {
    idx <- which(vapply(sections, pred, logical(1)))
    if (length(idx) == 0L) return(NULL)
    for (i in idx) {
      cval <- sections[[i]]$color
      if (!is.null(cval)) return(cval)
    }
    NULL
  }

  detail <- pick(function(s) identical(s$type, "Section") && grepl("detail", s$name, fixed = TRUE))
  if (!is.null(detail)) return(detail)

  section_any <- pick(function(s) identical(s$type, "Section"))
  if (!is.null(section_any)) return(section_any)

  header <- pick(function(s) grepl("header", s$name, fixed = TRUE) || s$type %in% c("FormHeader", "PageHeader"))
  if (!is.null(header)) return(header)

  NULL
}

font_size_to_em <- function(x) {
  pt <- parse_num(x)
  if (is.na(pt) || pt <= 0) return(NULL)
  sprintf("%.3fem", pt / 12)
}

parse_access_form_text <- function(input_file) {
  lines <- read_lines_auto(input_file)
  root <- new_node("__ROOT__")
  stack <- list(root)

  i <- 1L
  n <- length(lines)
  while (i <= n) {
    ln <- lines[i]
    t <- trim_ws(ln)
    if (!nzchar(t)) {
      i <- i + 1L
      next
    }

    if (grepl("^Begin\\s+", t)) {
      typ <- sub("^Begin\\s+", "", t)
      node <- new_node(typ)
      parent <- stack[[length(stack)]]
      parent$children[[length(parent$children) + 1L]] <- node
      stack[[length(stack) + 1L]] <- node
      i <- i + 1L
      next
    }

    if (identical(t, "End")) {
      if (length(stack) > 1L) stack <- stack[-length(stack)]
      i <- i + 1L
      next
    }

    if (grepl("=", t, fixed = TRUE)) {
      kv <- strsplit(t, "=", fixed = TRUE)[[1]]
      key <- trim_ws(kv[1])
      val <- trim_ws(paste(kv[-1], collapse = "="))
      val <- strip_quotes(val)
      cur <- stack[[length(stack)]]
      cur$props[[key]] <- val
    }

    i <- i + 1L
  }

  root
}

find_first_by_type <- function(node, target_type) {
  if (identical(node$type, target_type)) return(node)
  for (ch in node$children) {
    got <- find_first_by_type(ch, target_type)
    if (!is.null(got)) return(got)
  }
  NULL
}

control_bounds <- function(node, scale = 1.8) {
  l <- scale_px(twips_to_px(parse_num(node$props$Left)), scale = scale)
  t <- scale_px(twips_to_px(parse_num(node$props$Top)), scale = scale)
  w <- scale_px(twips_to_px(parse_num(node$props$Width)), scale = scale)
  h <- scale_px(twips_to_px(parse_num(node$props$Height)), scale = scale)
  list(left = l, top = t, width = w, height = h)
}

style_from_node <- function(node, scale = 1.8, z_index = NULL) {
  b <- control_bounds(node, scale = scale)
  parts <- c("position:absolute")
  if (!is.na(b$left)) parts <- c(parts, sprintf("left:%dpx", b$left))
  if (!is.na(b$top)) parts <- c(parts, sprintf("top:%dpx", b$top))
  if (!is.na(b$width)) parts <- c(parts, sprintf("width:%dpx", b$width))
  if (!is.na(b$height)) parts <- c(parts, sprintf("height:%dpx", b$height))
  if (!is.null(z_index)) parts <- c(parts, sprintf("z-index:%d", as.integer(z_index)))

  fore <- access_color_to_css(node$props$ForeColor)
  back <- access_color_to_css(node$props$BackColor)
  if (!is.null(fore)) parts <- c(parts, sprintf("color:%s", fore))
  if (!is.null(back)) parts <- c(parts, sprintf("background-color:%s", back))

  fs <- font_size_to_em(node$props$FontSize)
  if (!is.null(fs)) parts <- c(parts, sprintf("font-size:%s", fs))
  fw <- parse_num(node$props$FontWeight)
  if (!is.na(fw) && fw >= 700) parts <- c(parts, "font-weight:bold")
  fn <- trim_ws(node$props$FontName)
  if (nzchar(fn)) parts <- c(parts, sprintf("font-family:'%s'", escape_r_string(fn)))

  ta <- text_align_css(node$props$TextAlign)
  if (!is.null(ta)) parts <- c(parts, sprintf("text-align:%s", ta))

  paste(parts, collapse = ";")
}

control_name <- function(node, fallback = NULL) {
  raw_name <- node$props$Name
  if (!is.null(raw_name) && length(raw_name) > 0L) {
    nm <- trim_ws(as.character(raw_name)[1])
    if (nzchar(nm)) return(nm)
  }
  if (!is.null(fallback)) return(fallback)
  paste0("ctrl_", node$id)
}

is_event_bound <- function(node) {
  ev_props <- grep("^On", names(node$props), value = TRUE)
  if (length(ev_props) == 0L) return(FALSE)
  any(vapply(ev_props, function(k) identical(trim_ws(node$props[[k]]), "[Event Procedure]"), logical(1)))
}

emit_caption_node <- function(node) {
  caption <- decode_access_caption(node$props$Caption)
  if (!nzchar(caption)) caption <- control_name(node)
  caption_html_expr(caption)
}

emit_control <- function(node, scale = 1.8, z_index = NULL) {
  typ <- tolower(node$type)
  nm <- control_name(node)
  style <- style_from_node(node, scale = scale, z_index = z_index)
  caption_expr <- emit_caption_node(node)
  access_name_attr <- sprintf("`data-access-name` = \"%s\"", escape_r_string(nm))
  base_wrap <- function(inner) sprintf("tags$div(%s, style=\"%s\", %s)", inner, style, access_name_attr)

  if (typ %in% c("label", "text", "rectangle", "line")) {
    return(base_wrap(sprintf("tags$span(%s)", caption_expr)))
  }

  if (typ %in% c("textbox", "combobox", "listbox") && is_event_bound(node)) {
    input_id <- nm
    if (typ == "textbox") {
      return(base_wrap(sprintf("textInput(\"%s\", label = NULL, value = \"\", width = \"100%%\")", escape_r_string(input_id))))
    }
    if (typ == "combobox") {
      return(base_wrap(sprintf("selectInput(\"%s\", label = NULL, choices = character(0), width = \"100%%\")", escape_r_string(input_id))))
    }
    return(base_wrap(sprintf("selectInput(\"%s\", label = NULL, choices = character(0), multiple = TRUE, width = \"100%%\")", escape_r_string(input_id))))
  }

  if (typ %in% c("checkbox", "togglebutton") && is_event_bound(node)) {
    return(base_wrap(sprintf("checkboxInput(\"%s\", label = %s, value = FALSE)", escape_r_string(nm), caption_expr)))
  }

  if (typ %in% c("commandbutton", "button") && is_event_bound(node)) {
    return(base_wrap(sprintf("actionButton(\"%s\", label = %s)", escape_r_string(nm), caption_expr)))
  }

  if (typ == "optiongroup") {
    return(emit_option_group(node, scale = scale, z_index = z_index))
  }

  if (typ == "tab") {
    return(emit_tab_control(node, scale = scale, z_index = z_index))
  }

  if (typ == "subform") {
    return(emit_subform(node, scale = scale, z_index = z_index))
  }

  placeholder <- sprintf("tags$div('Unsupported %s: %s')", escape_r_string(node$type), escape_r_string(nm))
  base_wrap(placeholder)
}

emit_option_group <- function(node, scale = 1.8, z_index = NULL) {
  style <- style_from_node(node, scale = scale, z_index = z_index)
  nm <- control_name(node)
  group_caption <- decode_access_caption(node$props$Caption)
  if (!nzchar(group_caption)) group_caption <- nm

  options <- Filter(function(ch) tolower(ch$type) %in% c("optionbutton", "radiobutton"), node$children)
  if (length(options) > 0L) {
    labels <- vapply(options, function(ch) {
      cap <- decode_access_caption(ch$props$Caption)
      if (!nzchar(cap)) control_name(ch)
      else cap
    }, character(1))
    values <- vapply(options, function(ch) {
      ov <- trim_ws(ch$props$OptionValue)
      if (!nzchar(ov)) control_name(ch) else ov
    }, character(1))
    choices_expr <- sprintf(
      "setNames(c(%s), c(%s))",
      paste(sprintf('"%s"', escape_r_string(values)), collapse = ", "),
      paste(sprintf('"%s"', escape_r_string(labels)), collapse = ", ")
    )

    return(sprintf(
      "tags$fieldset(style=\"%s\", `data-access-name`=\"%s\", tags$legend(%s), radioButtons(\"%s\", label=NULL, choices=%s, selected=character(0)))",
      style,
      escape_r_string(nm),
      caption_html_expr(group_caption),
      escape_r_string(nm),
      choices_expr
    ))
  }

  sprintf(
    "tags$fieldset(style=\"%s\", `data-access-name`=\"%s\", tags$legend(%s), tags$div('OptionGroup placeholder'))",
    style,
    escape_r_string(nm),
    caption_html_expr(group_caption)
  )
}

emit_tab_control <- function(node, scale = 1.8, z_index = NULL) {
  style <- style_from_node(node, scale = scale, z_index = z_index)
  nm <- control_name(node)
  pages <- Filter(function(ch) tolower(ch$type) == "page", node$children)

  if (length(pages) == 0L) {
    return(sprintf(
      "tags$div(style=\"%s\", `data-access-name`=\"%s\", tags$div('Tab control with no pages'))",
      style,
      escape_r_string(nm)
    ))
  }

  panels <- character(0)
  for (pg in pages) {
    pg_name <- control_name(pg)
    pg_caption <- decode_access_caption(pg$props$Caption)
    if (!nzchar(pg_caption)) pg_caption <- pg_name

    child_controls <- Filter(function(ch) {
      !tolower(ch$type) %in% c("label", "text", "rectangle", "line") || length(ch$children) > 0L
    }, pg$children)
    child_lines <- character(0)
    for (idx in seq_along(child_controls)) {
      child_lines <- c(child_lines, emit_control(child_controls[[idx]], scale = scale, z_index = idx))
    }
    inner <- if (length(child_lines) > 0L) paste(child_lines, collapse = ",\n        ") else "tags$div('Empty page')"

    panels <- c(
      panels,
      sprintf(
        "tabPanel(%s, value=\"%s\", tags$div(style=\"position:relative; min-height:200px;\", %s))",
        caption_html_expr(pg_caption),
        escape_r_string(pg_name),
        inner
      )
    )
  }

  sprintf(
    "tags$div(style=\"%s\", `data-access-name`=\"%s\", tabsetPanel(id=\"%s\", %s))",
    style,
    escape_r_string(nm),
    escape_r_string(nm),
    paste(panels, collapse = ",\n      ")
  )
}

emit_subform <- function(node, scale = 1.8, z_index = NULL) {
  style <- style_from_node(node, scale = scale, z_index = z_index)
  nm <- control_name(node)
  src <- trim_ws(node$props$SourceObject)
  if (!nzchar(src)) {
    return(sprintf(
      "tags$div(style=\"%s\", `data-access-name`=\"%s\", tags$div('Subform placeholder (no SourceObject)'))",
      style,
      escape_r_string(nm)
    ))
  }

  src_clean <- gsub('^"|"$', "", src)
  src_parts <- strsplit(src_clean, "\\.")[[1]]
  base <- src_parts[length(src_parts)]
  candidate <- file.path(dirname(getOption("access_form_input_file", ".")), paste0(base, ".txt"))

  if (!file.exists(candidate)) {
    return(sprintf(
      "tags$div(style=\"%s\", `data-access-name`=\"%s\", tags$div('Subform placeholder: missing %s'))",
      style,
      escape_r_string(nm),
      escape_r_string(basename(candidate))
    ))
  }

  stack <- getOption("access_form_stack", character(0))
  norm <- normalizePath(candidate, winslash = "/", mustWork = FALSE)
  if (norm %in% stack) {
    return(sprintf(
      "tags$div(style=\"%s\", `data-access-name`=\"%s\", tags$div('Subform recursion detected: %s'))",
      style,
      escape_r_string(nm),
      escape_r_string(base)
    ))
  }

  ui_text <- tryCatch(
    {
      old_stack <- getOption("access_form_stack", character(0))
      on.exit(options(access_form_stack = old_stack), add = TRUE)
      options(access_form_stack = c(old_stack, norm))
      render_form_ui(candidate, scale = scale, z_mode = getOption("access_form_z_mode", "natural"), embedded = TRUE)
    },
    error = function(e) NULL
  )

  if (is.null(ui_text) || !nzchar(ui_text)) {
    return(sprintf(
      "tags$div(style=\"%s\", `data-access-name`=\"%s\", tags$div('Subform placeholder: failed to render %s'))",
      style,
      escape_r_string(nm),
      escape_r_string(base)
    ))
  }

  sprintf(
    "tags$div(style=\"%s\", `data-access-name`=\"%s\", %s)",
    style,
    escape_r_string(nm),
    ui_text
  )
}

collect_controls <- function(node) {
  out <- list()
  walk <- function(n) {
    for (ch in n$children) {
      t <- tolower(ch$type)
      if (startsWith(ch$type, "__") || t %in% c("property", "command") || identical(ch$type, "__BEGIN__")) {
        next
      }
      if (!t %in% c("form", "section", "formheader", "formfooter", "pageheader", "pagefooter")) {
        out[[length(out) + 1L]] <<- ch
      }
      walk(ch)
    }
  }
  walk(node)
  out
}

render_form_ui <- function(input_file, scale = 1.8, z_mode = "natural", embedded = FALSE) {
  root <- parse_access_form_text(input_file)
  form <- find_first_by_type(root, "Form")
  if (is.null(form)) stop(sprintf("No Form found in %s", input_file))

  old_input <- getOption("access_form_input_file")
  old_stack <- getOption("access_form_stack")
  old_z <- getOption("access_form_z_mode")
  on.exit({
    options(access_form_input_file = old_input)
    options(access_form_stack = old_stack)
    options(access_form_z_mode = old_z)
  }, add = TRUE)
  options(access_form_input_file = input_file)
  options(access_form_z_mode = z_mode)
  if (is.null(old_stack)) options(access_form_stack = character(0))

  controls <- collect_controls(form)

  n <- length(controls)
  idx <- seq_len(n)
  z_indices <- if (identical(z_mode, "reverse")) rev(idx) else idx

  control_lines <- character(0)
  for (i in seq_along(controls)) {
    control_lines <- c(control_lines, emit_control(controls[[i]], scale = scale, z_index = z_indices[i]))
  }

  form_name <- control_name(form, fallback = tools::file_path_sans_ext(basename(input_file)))
  caption <- decode_access_caption(form$props$Caption)
  back_color <- resolve_form_back_color(form)

  width <- scale_px(twips_to_px(parse_num(form$props$Width)), scale = scale)
  inside_w <- if (is.na(width)) 1400L else width
  inside_h <- if (length(control_lines) > 0L) {
    max(vapply(controls, function(cc) {
      b <- control_bounds(cc, scale = scale)
      if (is.na(b$top) || is.na(b$height)) return(0L)
      as.integer(b$top + b$height)
    }, integer(1)), na.rm = TRUE) + 24L
  } else {
    400L
  }

  scroll_mode <- parse_num(form$props$ScrollBars)
  overflow <- if (is.na(scroll_mode) || scroll_mode == 0) "overflow:hidden" else "overflow:auto"
  bg_css <- if (!is.null(back_color)) sprintf("background-color:%s", back_color) else ""

  inner_style <- paste(c(
    "position:relative",
    sprintf("width:%dpx", inside_w),
    sprintf("min-height:%dpx", inside_h),
    bg_css
  ), collapse = ";")

  root_style <- paste(c(
    "position:relative",
    "width:100%",
    overflow,
    "border:1px solid #d9d9d9",
    "padding:8px"
  ), collapse = ";")

  title_line <- if (nzchar(caption)) sprintf("tags$h4(%s)", caption_html_expr(caption)) else NULL

  block <- c(
    sprintf("tags$div(id=\"%s\", class=\"access-form-root\", `data-access-name`=\"%s\", style=\"%s\",",
            escape_r_string(form_name), escape_r_string(form_name), root_style),
    if (!is.null(title_line)) paste0("  ", title_line, ","),
    sprintf("  tags$div(style=\"%s\",", inner_style),
    if (length(control_lines) > 0L) paste0("    ", paste(control_lines, collapse = ",\n    ")) else "    tags$div('No controls parsed')",
    "  )",
    ")"
  )

  if (embedded) {
    return(paste(block, collapse = "\n"))
  }

  ui_lines <- c(
    sprintf("# Auto-generated from Access form export: %s", basename(input_file)),
    "# Generated by scripts/Tools/access_form_to_shiny.R",
    "# NOTE: VBA/event logic is not migrated automatically.",
    "",
    "library(shiny)",
    "",
    "ui <- fluidPage(",
    paste0("  ", paste(block, collapse = "\n  ")),
    ")",
    "",
    "server <- function(input, output, session) {",
    "  # TODO: wire server logic and event handlers.",
    "}",
    "",
    "# shinyApp(ui, server)",
    ""
  )

  paste(ui_lines, collapse = "\n")
}

generate_ui_file <- function(input_file, output_file = NULL, scale = 1.8, z_mode = "natural") {
  generated <- render_form_ui(input_file, scale = scale, z_mode = z_mode, embedded = FALSE)

  if (is.null(output_file) || !nzchar(output_file)) {
    base <- tools::file_path_sans_ext(basename(input_file))
    output_file <- file.path(dirname(input_file), paste0("ui_", base, ".R"))
  }

  writeLines(generated, output_file, useBytes = TRUE)
  output_file
}

convert_forms_dir <- function(forms_dir, scale = 1.8, z_mode = "natural") {
  files <- list.files(forms_dir, pattern = "\\.txt$", full.names = TRUE)
  if (length(files) == 0L) {
    stop(sprintf("No .txt files found in %s", forms_dir))
  }

  outputs <- character(0)
  for (f in files) {
    out <- tryCatch(
      generate_ui_file(f, scale = scale, z_mode = z_mode),
      error = function(e) {
        message(sprintf("[ERROR] %s: %s", basename(f), e$message))
        NA_character_
      }
    )
    if (!is.na(out)) {
      message(sprintf("[OK] %s -> %s", basename(f), basename(out)))
      outputs <- c(outputs, out)
    }
  }
  outputs
}

main <- function() {
  args <- commandArgs(trailingOnly = TRUE)

  if (length(args) == 0L) {
    cat(
      "Access form to Shiny UI generator\n\n",
      "Usage:\n",
      "  Rscript scripts/Tools/access_form_to_shiny.R [--scale=1.8] [--zorder=natural|reverse] <path/to/form.txt> [path/to/ui_form.R]\n",
      "  Rscript scripts/Tools/access_form_to_shiny.R [--scale=1.8] [--zorder=natural|reverse] <path/to/Forms_directory>\n",
      sep = ""
    )
    quit(status = 1)
  }

  scale <- 1.8
  z_mode <- "natural"
  while (length(args) > 0L && grepl("^--", args[1])) {
    if (grepl("^--scale=", args[1])) {
      scale <- suppressWarnings(as.numeric(sub("^--scale=", "", args[1])))
      if (is.na(scale) || scale <= 0) stop("--scale must be a positive number")
      args <- args[-1]
      next
    }
    if (grepl("^--zorder=", args[1])) {
      z_mode <- tolower(trim_ws(sub("^--zorder=", "", args[1])))
      if (!z_mode %in% c("natural", "reverse")) stop("--zorder must be 'natural' or 'reverse'")
      args <- args[-1]
      next
    }
    break
  }

  if (length(args) == 0L) stop("Missing input path")

  in_path <- args[1]
  if (!file.exists(in_path)) {
    stop(sprintf("Input path does not exist: %s", in_path))
  }

  if (dir.exists(in_path)) {
    outs <- convert_forms_dir(in_path, scale = scale, z_mode = z_mode)
    message(sprintf("Generated %d UI file(s).", length(outs)))
  } else {
    out_path <- if (length(args) >= 2L) args[2] else NULL
    generated <- generate_ui_file(in_path, out_path, scale = scale, z_mode = z_mode)
    message(sprintf("Generated: %s", generated))
  }
}

if (identical(environment(), globalenv())) {
  main()
}
