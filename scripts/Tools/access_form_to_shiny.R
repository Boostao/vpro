#!/usr/bin/env Rscript

# Convert Microsoft Access form exports (Application.SaveAsText) to Shiny UI R code.
# Usage:
#   Rscript Tools/access_form_to_shiny.R <path/to/form.txt> [path/to/ui_form.R]
#   Rscript Tools/access_form_to_shiny.R <path/to/Forms_directory>

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

map_scrollbars <- function(x) {
  n <- parse_num(x)
  if (is.na(n)) return(list(x = "auto", y = "auto"))
  if (n == 0) return(list(x = "hidden", y = "hidden"))
  if (n == 1) return(list(x = "auto", y = "hidden"))
  if (n == 2) return(list(x = "hidden", y = "auto"))
  list(x = "auto", y = "auto")
}

as_bool <- function(x) {
  if (is.null(x) || length(x) == 0L) return(NA)
  x <- tolower(trim_ws(as.character(x)[1]))
  if (x %in% c("true", "yes", "-1")) return(TRUE)
  if (x %in% c("false", "no", "0")) return(FALSE)
  NA
}

has_event_procedure <- function(props) {
  if (is.null(props) || length(props) == 0L) return(FALSE)
  nms <- names(props)
  if (is.null(nms) || length(nms) == 0L) return(FALSE)
  on_idx <- grepl("^On", nms)
  if (!any(on_idx)) return(FALSE)
  vals <- vapply(props[on_idx], function(v) if (length(v) == 0L || is.null(v)) "" else as.character(v)[1], character(1))
  any(trim_ws(vals) == "[Event Procedure]")
}

append_child <- function(parent, child) {
  parent$children[[length(parent$children) + 1L]] <- child
}

read_access_lines <- function(input_file) {
  con_raw <- file(input_file, open = "rb")
  on.exit(close(con_raw), add = TRUE)
  bom <- readBin(con_raw, what = "raw", n = 3L)

  if (length(bom) >= 2L && identical(as.integer(bom[1:2]), c(255L, 254L))) {
    con <- file(input_file, open = "r", encoding = "UTF-16LE")
    on.exit(close(con), add = TRUE)
    return(readLines(con, warn = FALSE))
  }

  if (length(bom) >= 2L && identical(as.integer(bom[1:2]), c(254L, 255L))) {
    con <- file(input_file, open = "r", encoding = "UTF-16BE")
    on.exit(close(con), add = TRUE)
    return(readLines(con, warn = FALSE))
  }

  con <- file(input_file, open = "r", encoding = "UTF-8")
  on.exit(close(con), add = TRUE)
  lines <- tryCatch(readLines(con, warn = FALSE), error = function(e) NULL)
  if (!is.null(lines)) return(lines)

  con_l1 <- file(input_file, open = "r", encoding = "latin1")
  on.exit(close(con_l1), add = TRUE)
  readLines(con_l1, warn = FALSE)
}

parse_access_form_text <- function(input_file) {
  lines <- read_access_lines(input_file)

  root <- new_node("__ROOT__")
  stack <- list(root)

  last_prop_name <- NULL
  last_prop_node <- NULL

  for (line in lines) {
    if (grepl('^\\s*".*"\\s*$', line) && !is.null(last_prop_name) && !is.null(last_prop_node)) {
      cont <- strip_quotes(line)
      prev <- last_prop_node$props[[last_prop_name]]
      if (is.null(prev) || identical(prev, "")) {
        last_prop_node$props[[last_prop_name]] <- cont
      } else {
        last_prop_node$props[[last_prop_name]] <- paste0(prev, cont)
      }
      next
    }

    if (grepl('^\\s*End\\s*$', line)) {
      if (length(stack) > 1L) {
        stack <- stack[seq_len(length(stack) - 1L)]
      }
      last_prop_name <- NULL
      last_prop_node <- NULL
      next
    }

    m_prop_begin <- regexec('^\\s*([A-Za-z0-9_]+)\\s*=\\s*Begin\\s*$', line)
    r_prop_begin <- regmatches(line, m_prop_begin)[[1]]
    if (length(r_prop_begin) > 0L) {
      key <- r_prop_begin[2]
      cur <- stack[[length(stack)]]
      cur$props[[key]] <- "<BeginBlock>"
      child <- new_node(paste0("__PROP__", key))
      append_child(cur, child)
      stack[[length(stack) + 1L]] <- child
      last_prop_name <- NULL
      last_prop_node <- NULL
      next
    }

    m_begin <- regexec('^\\s*Begin(?:\\s+(.+?))?\\s*$', line)
    r_begin <- regmatches(line, m_begin)[[1]]
    if (length(r_begin) > 0L) {
      node_type <- ifelse(length(r_begin) >= 2L && nzchar(r_begin[2]), trim_ws(r_begin[2]), "__BEGIN__")
      child <- new_node(node_type)
      append_child(stack[[length(stack)]], child)
      stack[[length(stack) + 1L]] <- child
      last_prop_name <- NULL
      last_prop_node <- NULL
      next
    }

    m_prop <- regexec('^\\s*([A-Za-z0-9_]+)\\s*=\\s*(.*?)\\s*$', line)
    r_prop <- regmatches(line, m_prop)[[1]]
    if (length(r_prop) > 0L) {
      key <- r_prop[2]
      val_raw <- r_prop[3]
      val <- if (grepl('^".*"$', trim_ws(val_raw))) strip_quotes(val_raw) else trim_ws(val_raw)
      cur <- stack[[length(stack)]]
      cur$props[[key]] <- val
      last_prop_name <- key
      last_prop_node <- cur
      next
    }

    last_prop_name <- NULL
    last_prop_node <- NULL
  }

  root
}

find_first_by_type <- function(node, target_type) {
  if (identical(node$type, target_type)) return(node)
  if (length(node$children) == 0L) return(NULL)
  for (ch in node$children) {
    f <- find_first_by_type(ch, target_type)
    if (!is.null(f)) return(f)
  }
  NULL
}

compute_section_offsets <- function(form_node) {
  section_types <- c("FormHeader", "Section", "FormFooter", "PageHeader", "PageFooter")
  offsets <- new.env(parent = emptyenv())
  sections <- list()
  seq_idx <- 0L

  section_bucket <- function(node) {
    t <- tolower(node$type)
    n <- if (!is.null(node$props$Name)) tolower(trim_ws(node$props$Name)) else ""

    if (t %in% c("formheader", "pageheader") || grepl("header", n, fixed = TRUE)) return(1L)
    if (t %in% c("formfooter", "pagefooter") || grepl("footer", n, fixed = TRUE)) return(3L)
    if (t == "section") {
      if (grepl("header", n, fixed = TRUE)) return(1L)
      if (grepl("footer", n, fixed = TRUE)) return(3L)
      return(2L)
    }
    2L
  }

  walk <- function(node) {
    for (ch in node$children) {
      if (ch$type %in% section_types) {
        seq_idx <<- seq_idx + 1L
        sections[[length(sections) + 1L]] <<- list(
          id = ch$id,
          height = {
            h <- twips_to_px(parse_num(ch$props$Height))
            if (is.na(h)) 0L else h
          },
          bucket = section_bucket(ch),
          seq = seq_idx
        )
      }
      walk(ch)
    }
  }

  walk(form_node)

  if (length(sections) == 0L) return(offsets)

  ord <- order(
    vapply(sections, function(s) s$bucket, integer(1)),
    vapply(sections, function(s) s$seq, integer(1))
  )
  cumulative <- 0L
  for (idx in ord) {
    sec <- sections[[idx]]
    offsets[[as.character(sec$id)]] <- cumulative
    cumulative <- cumulative + sec$height
  }

  offsets
}

is_control_type <- function(type) {
  type %in% c(
    "Label", "TextBox", "ComboBox", "ListBox", "CommandButton", "CheckBox",
    "OptionButton", "ToggleButton", "OptionGroup", "Rectangle", "Line", "Image", "Subform",
    "Attachment", "BoundObjectFrame"
  )
}

extract_controls <- function(form_node, scale = 1.8) {
  section_offsets <- compute_section_offsets(form_node)
  controls <- list()
  z_counter <- 0L
  tabs <- list()
  pages <- list()
  suppress_label_ids <- integer(0)

  add_tab <- function(tab_obj) {
    tabs[[length(tabs) + 1L]] <<- tab_obj
  }

  add_page <- function(page_obj) {
    pages[[length(pages) + 1L]] <<- page_obj
  }

  find_tab_idx <- function(tab_id) {
    idx <- which(vapply(tabs, function(t) identical(t$id, tab_id), logical(1)))
    if (length(idx) == 0L) return(NA_integer_)
    idx[1]
  }

  walk <- function(node, section_offset = 0L, section_name = "Detail", current_tab_id = NA_integer_, current_page_id = NA_integer_, current_option_group_id = NA_integer_) {
    if (node$type %in% c("FormHeader", "Section", "FormFooter", "PageHeader", "PageFooter")) {
      key <- as.character(node$id)
      if (!is.null(section_offsets[[key]])) {
        section_offset <- section_offsets[[key]]
      }
      section_name <- if (!is.null(node$props$Name) && nzchar(node$props$Name)) node$props$Name else node$type
    }

    if (identical(node$type, "Tab")) {
      left_px <- twips_to_px(parse_num(node$props$Left))
      top_px <- twips_to_px(parse_num(node$props$Top))
      width_px <- twips_to_px(parse_num(node$props$Width))
      height_px <- twips_to_px(parse_num(node$props$Height))

      tab_obj <- list(
        id = node$id,
        name = if (!is.null(node$props$Name)) node$props$Name else paste0("Tab", node$id),
        caption = decode_access_caption(if (!is.null(node$props$Caption)) node$props$Caption else if (!is.null(node$props$Name)) node$props$Name else paste0("Tab", node$id)),
        left = scale_px(ifelse(is.na(left_px), 0L, left_px), scale),
        top = scale_px(ifelse(is.na(top_px), section_offset, top_px + section_offset), scale),
        width = scale_px(ifelse(is.na(width_px), 600L, width_px), scale),
        height = scale_px(ifelse(is.na(height_px), 420L, height_px), scale),
        section = section_name,
        page_ids = list()
      )
      add_tab(tab_obj)
      current_tab_id <- node$id
    }

    if (identical(node$type, "Page")) {
      page_obj <- list(
        id = node$id,
        tab_id = current_tab_id,
        name = if (!is.null(node$props$Name)) node$props$Name else paste0("Page", node$id),
        caption = decode_access_caption(if (!is.null(node$props$Caption) && nzchar(node$props$Caption)) node$props$Caption else if (!is.null(node$props$Name)) node$props$Name else paste0("Page", node$id))
      )
      add_page(page_obj)
      current_page_id <- node$id

      tab_idx <- find_tab_idx(current_tab_id)
      if (!is.na(tab_idx)) {
        tabs[[tab_idx]]$page_ids[[length(tabs[[tab_idx]]$page_ids) + 1L]] <<- node$id
      }
    }

    if (is_control_type(node$type)) {
      if (identical(node$type, "Label") && node$id %in% suppress_label_ids) {
        return(invisible(NULL))
      }

      has_geometry <- !is.null(node$props$Left) || !is.null(node$props$Top) || !is.null(node$props$Width) || !is.null(node$props$Height)
      if (!has_geometry) {
        for (ch in node$children) {
          walk(ch, section_offset, section_name, current_tab_id, current_page_id, current_option_group_id)
        }
        return(invisible(NULL))
      }

      left_px <- twips_to_px(parse_num(node$props$Left))
      top_px <- twips_to_px(parse_num(node$props$Top))
      width_px <- twips_to_px(parse_num(node$props$Width))
      height_px <- twips_to_px(parse_num(node$props$Height))
      tab_index <- parse_num(node$props$TabIndex)
      tab_stop <- as_bool(node$props$TabStop)
      attached_label <- NULL

      if (node$type %in% c("CheckBox", "OptionButton", "ToggleButton")) {
        lbl <- find_first_descendant_by_type(node, "Label")
        if (!is.null(lbl)) {
          suppress_label_ids <<- unique(c(suppress_label_ids, lbl$id))
          attached_label <- list(
            raw_caption = if (!is.null(lbl$props$Caption)) lbl$props$Caption else "",
            caption = decode_access_caption(if (!is.null(lbl$props$Caption)) lbl$props$Caption else ""),
            text_align = text_align_css(lbl$props$TextAlign),
            fore_color = access_color_to_css(lbl$props$ForeColor),
            font_size_em = font_size_to_em(lbl$props$FontSize),
            font_weight = parse_num(lbl$props$FontWeight),
            font_name = if (!is.null(lbl$props$FontName)) lbl$props$FontName else NULL
          )
        }
      }

      z_counter <<- z_counter + 1L

      controls[[length(controls) + 1L]] <<- list(
        id = node$id,
        type = node$type,
        name = if (!is.null(node$props$Name)) node$props$Name else paste0(node$type, node$id),
        caption = decode_access_caption(if (!is.null(node$props$Caption)) node$props$Caption else ""),
        raw_caption = if (!is.null(node$props$Caption)) node$props$Caption else "",
        left = scale_px(ifelse(is.na(left_px), 0L, left_px), scale),
        top = scale_px(ifelse(is.na(top_px), section_offset, top_px + section_offset), scale),
        width = scale_px(ifelse(is.na(width_px), 120L, width_px), scale),
        height = scale_px(ifelse(is.na(height_px), 24L, height_px), scale),
        tab_index = ifelse(is.na(tab_index), NA_real_, tab_index),
        tab_stop = tab_stop,
        z_index = z_counter,
        back_color = access_color_to_css(node$props$BackColor),
        fore_color = access_color_to_css(node$props$ForeColor),
        border_color = access_color_to_css(node$props$BorderColor),
        back_style = parse_num(node$props$BackStyle),
        text_align = text_align_css(node$props$TextAlign),
        font_size_em = font_size_to_em(node$props$FontSize),
        font_weight = parse_num(node$props$FontWeight),
        font_name = if (!is.null(node$props$FontName)) node$props$FontName else NULL,
        attached_label = attached_label,
        visible = ifelse(isTRUE(as_bool(node$props$Visible)), TRUE, ifelse(isFALSE(as_bool(node$props$Visible)), FALSE, TRUE)),
        enabled = ifelse(isTRUE(as_bool(node$props$Enabled)), TRUE, ifelse(isFALSE(as_bool(node$props$Enabled)), FALSE, TRUE)),
        event_bound = has_event_procedure(node$props),
        scrollbars = parse_num(node$props$ScrollBars),
        source_object = if (!is.null(node$props$SourceObject)) node$props$SourceObject else NULL,
        option_value = parse_num(node$props$OptionValue),
        default_value = if (!is.null(node$props$DefaultValue)) trim_ws(node$props$DefaultValue) else NULL,
        option_group_id = ifelse(is.na(current_option_group_id), NA_integer_, as.integer(current_option_group_id)),
        section = section_name,
        tab_id = current_tab_id,
        page_id = current_page_id
      )
    }

    child_option_group_id <- current_option_group_id
    if (identical(node$type, "OptionGroup")) {
      child_option_group_id <- node$id
    }

    for (ch in node$children) {
      walk(ch, section_offset, section_name, current_tab_id, current_page_id, child_option_group_id)
    }
  }

  walk(form_node)
  list(controls = controls, tabs = tabs, pages = pages)
}

make_html_id <- function(name, fallback_prefix = "control") {
  raw <- ifelse(is.null(name) || !nzchar(name), "", name)
  id <- gsub("[^A-Za-z0-9_:.\\-]", "_", raw)
  if (!nzchar(id)) id <- paste0(fallback_prefix, "_", as.integer(runif(1, 1, 1e6)))
  if (!grepl("^[A-Za-z]", id)) id <- paste0("c_", id)
  id
}

control_style_string <- function(ctrl, z_mode = "natural") {
  z_raw <- if (!is.null(ctrl$z_index) && !is.na(ctrl$z_index)) as.integer(ctrl$z_index) else 0L
  z <- if (identical(z_mode, "reverse")) -z_raw else z_raw
  style_parts <- c(
    sprintf("position:absolute; left:%dpx; top:%dpx; width:%dpx; height:%dpx; z-index:%d; box-sizing:border-box;",
            ctrl$left, ctrl$top, ctrl$width, ctrl$height, z)
  )

  if (!isTRUE(ctrl$visible)) style_parts <- c(style_parts, "display:none;")
  has_opaque_back <- isTRUE(!is.na(ctrl$back_style) && ctrl$back_style == 1)
  if (!is.null(ctrl$back_color) && (ctrl$type %in% c("Rectangle", "OptionGroup") || (ctrl$type == "Label" && has_opaque_back))) {
    style_parts <- c(style_parts, sprintf("background-color:%s;", ctrl$back_color))
  }
  if (!is.null(ctrl$fore_color)) style_parts <- c(style_parts, sprintf("color:%s;", ctrl$fore_color))
  if (!is.null(ctrl$border_color) && ctrl$type %in% c("Rectangle", "OptionGroup")) style_parts <- c(style_parts, sprintf("border-color:%s;", ctrl$border_color))
  if (!is.null(ctrl$text_align)) style_parts <- c(style_parts, sprintf("text-align:%s;", ctrl$text_align))
  if (!is.null(ctrl$font_size_em)) style_parts <- c(style_parts, sprintf("font-size:%s;", ctrl$font_size_em))
  if (!is.null(ctrl$font_weight) && !is.na(ctrl$font_weight)) style_parts <- c(style_parts, sprintf("font-weight:%d;", as.integer(ctrl$font_weight)))
  if (!is.null(ctrl$font_name) && nzchar(ctrl$font_name)) style_parts <- c(style_parts, sprintf("font-family:%s;", escape_r_string(ctrl$font_name)))
  if (ctrl$type %in% c("CheckBox", "OptionButton") && !is.null(ctrl$attached_label) && !is.null(ctrl$attached_label$caption) && nzchar(ctrl$attached_label$caption)) {
    style_parts <- c(style_parts, "overflow:visible;")
  }

  paste(style_parts, collapse = " ")
}

escape_js_single <- function(x) {
  x <- gsub("\\\\", "\\\\\\\\", x)
  x <- gsub("'", "\\\\'", x, fixed = TRUE)
  x
}

resolve_subform_basename <- function(ctrl) {
  candidates <- character(0)

  if (!is.null(ctrl$name) && nzchar(ctrl$name)) {
    candidates <- c(candidates, ctrl$name)
  }

  src <- if (!is.null(ctrl$source_object)) trim_ws(ctrl$source_object) else ""
  if (nzchar(src)) {
    src <- gsub('^"|"$', '', src)
    parts <- strsplit(src, "\\.", fixed = FALSE)[[1]]
    if (length(parts) > 0L) {
      candidates <- c(candidates, parts[length(parts)])
    }
  }

  candidates <- trim_ws(candidates)
  candidates <- candidates[nzchar(candidates)]
  unique(candidates)
}

build_form_ui_spec <- function(input_file, scale = 1.8, visited = character(0), z_mode = "natural") {
  norm_input <- normalizePath(input_file, winslash = "/", mustWork = FALSE)
  if (norm_input %in% visited) {
    return(list(
      form_name = tools::file_path_sans_ext(basename(input_file)),
      form_caption = tools::file_path_sans_ext(basename(input_file)),
      root_style = "width:100%; height:100%; overflow:auto;",
      root_items = c(
        sprintf(
          'shiny::tags$div(class = "access-form-control access-placeholder", style = "position:absolute; left:0px; top:0px; width:100%%;", "[Recursive subform omitted: %s]")',
          escape_r_string(basename(input_file))
        )
      )
    ))
  }
  visited <- c(visited, norm_input)

  parsed <- parse_access_form_text(input_file)
  form_node <- find_first_by_type(parsed, "Form")
  if (is.null(form_node)) {
    stop(sprintf("No 'Begin Form' block found in %s", input_file))
  }

  form_name_raw <- if (!is.null(form_node$props$Name)) form_node$props$Name else NULL
  form_name <- if (!is.null(form_name_raw) && nzchar(form_name_raw) && !identical(form_name_raw, "<BeginBlock>")) {
    form_name_raw
  } else {
    tools::file_path_sans_ext(basename(input_file))
  }
  form_caption <- decode_access_caption(if (!is.null(form_node$props$Caption)) form_node$props$Caption else form_name)

  form_width <- twips_to_px(parse_num(form_node$props$Width))
  if (is.na(form_width) || form_width <= 0L) form_width <- 1000L
  form_width <- scale_px(form_width, scale)

  form_back_color <- resolve_form_back_color(form_node)
  form_scroll <- map_scrollbars(form_node$props$ScrollBars)

  extracted <- extract_controls(form_node, scale = scale)
  controls <- extracted$controls
  tabs <- extracted$tabs
  pages <- extracted$pages

  option_groups <- controls[vapply(controls, function(cn) identical(cn$type, "OptionGroup"), logical(1))]
  option_group_choices <- list()
  option_group_layouts <- list()
  if (length(option_groups) > 0L) {
    for (grp in option_groups) {
      key <- as.character(grp$id)
      members <- controls[vapply(
        controls,
        function(cn) {
          identical(cn$type, "OptionButton") &&
            !is.na(cn$option_group_id) &&
            identical(as.integer(cn$option_group_id), as.integer(grp$id))
        },
        logical(1)
      )]
      if (length(members) > 0L) {
        members <- members[order(
          vapply(members, function(m) ifelse(is.na(m$top), 0L, m$top), numeric(1)),
          vapply(members, function(m) ifelse(is.na(m$left), 0L, m$left), numeric(1))
        )]

        first <- members[[1]]
        min_left <- min(vapply(members, function(m) m$left, numeric(1)))
        min_top <- min(vapply(members, function(m) m$top, numeric(1)))
        max_right <- max(vapply(members, function(m) m$left + m$width, numeric(1)))
        max_bottom <- max(vapply(members, function(m) m$top + m$height, numeric(1)))

        option_group_layouts[[key]] <- list(
          left = first$left,
          top = first$top,
          width = max(60L, as.integer(round(max_right - min_left))),
          height = max(20L, as.integer(round(max_bottom - min_top + 6L)))
        )
      }
      option_group_choices[[key]] <- members
    }
  }

  grouped_option_ids <- integer(0)
  if (length(option_group_choices) > 0L) {
    grouped_option_ids <- unlist(
      lapply(option_group_choices, function(members) vapply(members, function(m) as.integer(m$id), integer(1))),
      use.names = FALSE
    )
    grouped_option_ids <- unique(grouped_option_ids)
  }

  if (length(controls) == 0L) {
    warning(sprintf("No controls extracted from %s", input_file))
  }

  max_bottom <- 0L
  for (ctrl in controls) {
    bottom <- ctrl$top + ctrl$height
    if (bottom > max_bottom) max_bottom <- bottom
  }
  form_height <- max(scale_px(200L, scale), max_bottom + scale_px(20L, scale))

  root_style_parts <- c(
    sprintf("width:%dpx; height:%dpx;", form_width, form_height),
    sprintf("overflow-x:%s; overflow-y:%s;", form_scroll$x, form_scroll$y)
  )
  if (!is.null(form_back_color)) root_style_parts <- c(root_style_parts, sprintf("background-color:%s;", form_back_color))
  root_style <- paste(root_style_parts, collapse = " ")

  page_ids_with_controls <- unique(vapply(controls, function(cn) ifelse(is.na(cn$page_id), NA_integer_, as.integer(cn$page_id)), numeric(1)))
  page_ids_with_controls <- page_ids_with_controls[!is.na(page_ids_with_controls)]

  tab_selector_lines <- character(0)
  page_panel_lines <- character(0)

  if (length(tabs) > 0L && length(pages) > 0L) {
    for (tab in tabs) {
      page_ids <- unlist(tab$page_ids)
      page_ids <- page_ids[page_ids %in% page_ids_with_controls]
      if (length(page_ids) == 0L) next

      input_id <- make_html_id(paste0("tab_", tab$name), "tab")

      page_objs <- pages[vapply(pages, function(pg) pg$id %in% page_ids && identical(pg$tab_id, tab$id), logical(1))]
      if (length(page_objs) == 0L) next

      tab_panel_values <- vapply(page_objs, function(pg) paste0("p_", pg$id), character(1))
      tab_panel_titles <- vapply(page_objs, function(pg) ifelse(nzchar(pg$caption), pg$caption, pg$name), character(1))

      tab_panels <- character(0)
      for (i in seq_along(tab_panel_values)) {
        tab_panels <- c(tab_panels, sprintf('shiny::tabPanel(title = "%s", value = "%s")',
                                            escape_r_string(tab_panel_titles[i]), escape_r_string(tab_panel_values[i])))
      }

      tab_style <- sprintf("position:absolute; left:%dpx; top:%dpx; width:%dpx; height:auto; z-index:5000; box-sizing:border-box;",
                           tab$left, tab$top, tab$width)

      tab_selector_lines <- c(tab_selector_lines, sprintf(
        'shiny::tags$div(class = "access-form-control access-tab-selector", style = "%s", shiny::tabsetPanel(id = "%s", type = "tabs", selected = "%s", %s))',
        escape_r_string(tab_style),
        escape_r_string(input_id),
        escape_r_string(tab_panel_values[1]),
        paste(tab_panels, collapse = ", ")
      ))

      for (i in seq_along(page_objs)) {
        pg <- page_objs[[i]]
        pg_value <- tab_panel_values[i]
        pg_controls <- controls[vapply(controls, function(cn) identical(cn$page_id, pg$id) && identical(cn$tab_id, tab$id), logical(1))]
        pg_lines <- if (length(pg_controls) > 0L) {
          pg_controls <- pg_controls[!vapply(pg_controls, function(cn) cn$id %in% grouped_option_ids, logical(1))]
          vapply(
            pg_controls,
            function(cn) control_expr(cn, form_dir = dirname(input_file), scale = scale, visited = visited, z_mode = z_mode, option_group_choices = option_group_choices, option_group_layouts = option_group_layouts),
            FUN.VALUE = character(1),
            USE.NAMES = FALSE
          )
        } else {
          character(0)
        }
        pg_block <- if (length(pg_lines) > 0L) paste(pg_lines, collapse = ", ") else ""

        page_panel_lines <- c(page_panel_lines, sprintf(
          'shiny::conditionalPanel(condition = "input.%s == \'%s\'", shiny::tagList(%s))',
          escape_js_single(input_id),
          escape_js_single(pg_value),
          pg_block
        ))
      }
    }
  }

  always_controls <- controls[vapply(controls, function(cn) is.na(cn$page_id) && !(cn$id %in% grouped_option_ids), logical(1))]
  always_control_lines <- if (length(always_controls) > 0L) {
    vapply(
      always_controls,
      function(cn) control_expr(cn, form_dir = dirname(input_file), scale = scale, visited = visited, z_mode = z_mode, option_group_choices = option_group_choices, option_group_layouts = option_group_layouts),
      FUN.VALUE = character(1),
      USE.NAMES = FALSE
    )
  } else {
    character(0)
  }

  root_items <- c(tab_selector_lines, always_control_lines, page_panel_lines)
  list(
    form_name = form_name,
    form_caption = form_caption,
    root_style = root_style,
    root_items = root_items
  )
}

control_expr <- function(ctrl, form_dir = NULL, scale = 1.8, visited = character(0), z_mode = "natural", option_group_choices = list(), option_group_layouts = list()) {
  style <- control_style_string(ctrl, z_mode = z_mode)

  tabindex_str <- NULL
  if (!is.na(ctrl$tab_index)) {
    tabindex_str <- as.character(as.integer(ctrl$tab_index))
  } else if (isFALSE(ctrl$tab_stop)) {
    tabindex_str <- "-1"
  }

  name_safe <- make_html_id(ctrl$name, fallback_prefix = tolower(ctrl$type))
  data_name <- escape_r_string(ctrl$name)
  raw_caption <- if (!is.null(ctrl$raw_caption)) ctrl$raw_caption else ctrl$caption
  caption_html <- caption_html_expr(raw_caption)
  input_text_align <- if (!is.null(ctrl$text_align)) sprintf(" text-align:%s;", ctrl$text_align) else ""

  input_attr <- if (!is.null(tabindex_str)) sprintf(', tabindex = "%s"', escape_r_string(tabindex_str)) else ""

  if (ctrl$type == "Label") {
    return(sprintf(
      'shiny::tags$div(id = "%s", class = "access-form-control access-label", `data-access-name` = "%s", style = "%s", %s)',
      name_safe, data_name, escape_r_string(style), caption_html
    ))
  }

  if (ctrl$type == "TextBox") {
    if (isTRUE(ctrl$event_bound)) {
      inner <- sprintf('shiny::textInput(inputId = "%s", label = NULL, value = "", width = "100%%")', name_safe)
      return(sprintf('shiny::tags$div(class = "access-form-control", `data-access-name` = "%s", style = "%s", %s)',
                     data_name, escape_r_string(style), inner))
    }
    inner <- sprintf('shiny::tags$input(id = "%s", type = "text", class = "access-input", value = ""%s, style = "width:100%%; height:100%%;%s")',
                     name_safe, input_attr, input_text_align)
    return(sprintf('shiny::tags$div(class = "access-form-control", `data-access-name` = "%s", style = "%s", %s)',
                   data_name, escape_r_string(style), inner))
  }

  if (ctrl$type %in% c("ComboBox", "ListBox")) {
    if (isTRUE(ctrl$event_bound)) {
      multiple_flag <- if (ctrl$type == "ListBox") "TRUE" else "FALSE"
      inner <- sprintf(
        'shiny::selectInput(inputId = "%s", label = NULL, choices = character(0), selected = NULL, multiple = %s, width = "100%%")',
        name_safe, multiple_flag
      )
      return(sprintf('shiny::tags$div(class = "access-form-control", `data-access-name` = "%s", style = "%s", %s)',
                     data_name, escape_r_string(style), inner))
    }
    multiple <- if (ctrl$type == "ListBox") ", multiple = \"multiple\"" else ""
    inner <- sprintf(
      'shiny::tags$select(id = "%s", class = "access-select"%s%s, style = "width:100%%; height:100%%;%s")',
      name_safe, multiple, input_attr, input_text_align
    )
    return(sprintf('shiny::tags$div(class = "access-form-control", `data-access-name` = "%s", style = "%s", %s)',
                   data_name, escape_r_string(style), inner))
  }

  if (ctrl$type == "CommandButton") {
    if (isTRUE(ctrl$event_bound)) {
      inner <- sprintf('shiny::actionButton(inputId = "%s", label = %s, width = "100%%")',
                       name_safe, caption_html)
      return(sprintf('shiny::tags$div(class = "access-form-control", `data-access-name` = "%s", style = "%s", %s)',
                     data_name, escape_r_string(style), inner))
    }
    inner <- sprintf(
      'shiny::tags$button(id = "%s", type = "button", class = "access-btn"%s, style = "width:100%%; height:100%%;%s", %s)',
      name_safe, input_attr, input_text_align, caption_html
    )
    return(sprintf('shiny::tags$div(class = "access-form-control", `data-access-name` = "%s", style = "%s", %s)',
                   data_name, escape_r_string(style), inner))
  }

  if (ctrl$type %in% c("CheckBox", "OptionButton")) {
    attached_raw_caption <- ""
    if (!is.null(ctrl$attached_label) && !is.null(ctrl$attached_label$caption) && nzchar(ctrl$attached_label$caption)) {
      attached_raw_caption <- if (!is.null(ctrl$attached_label$raw_caption)) ctrl$attached_label$raw_caption else ctrl$attached_label$caption
    }
    label_html <- if (nzchar(attached_raw_caption)) caption_html_expr(attached_raw_caption) else caption_html
    if (isTRUE(ctrl$event_bound)) {
      inner <- sprintf(
        'shiny::checkboxInput(inputId = "%s", label = %s, value = FALSE, width = "100%%")',
        name_safe, label_html
      )
      return(sprintf('shiny::tags$div(class = "access-form-control", `data-access-name` = "%s", style = "%s", %s)',
                     data_name, escape_r_string(style), inner))
    }
    inner <- sprintf(
      'shiny::tags$label(class = "access-check-label", shiny::tags$input(id = "%s", type = "checkbox"%s), shiny::tags$span(%s))',
      name_safe, input_attr, label_html
    )
    return(sprintf('shiny::tags$div(class = "access-form-control", `data-access-name` = "%s", style = "%s", %s)',
                   data_name, escape_r_string(style), inner))
  }

  if (ctrl$type == "ToggleButton") {
    if (isTRUE(ctrl$event_bound)) {
      inner <- sprintf('shiny::actionButton(inputId = "%s", label = %s, width = "100%%")',
                       name_safe, caption_html)
      return(sprintf('shiny::tags$div(class = "access-form-control", `data-access-name` = "%s", style = "%s", %s)',
                     data_name, escape_r_string(style), inner))
    }
    inner <- sprintf(
      'shiny::tags$button(id = "%s", type = "button", class = "access-btn access-toggle-btn"%s, style = "width:100%%; height:100%%;%s", %s)',
      name_safe, input_attr, input_text_align, caption_html
    )
    return(sprintf('shiny::tags$div(class = "access-form-control", `data-access-name` = "%s", style = "%s", %s)',
                   data_name, escape_r_string(style), inner))
  }

  if (ctrl$type == "Rectangle") {
    return(sprintf(
      'shiny::tags$div(class = "access-form-control", `data-access-name` = "%s", style = "%s border:1px solid #777;")',
      data_name, escape_r_string(style)
    ))
  }

  if (ctrl$type == "OptionGroup") {
    group_key <- as.character(ctrl$id)
    members <- option_group_choices[[group_key]]
    layout <- option_group_layouts[[group_key]]

    ctrl_render <- ctrl
    if (!is.null(layout)) {
      ctrl_render$left <- layout$left
      ctrl_render$top <- layout$top
      ctrl_render$width <- layout$width
      ctrl_render$height <- layout$height
    }
    style_group <- control_style_string(ctrl_render, z_mode = z_mode)

    if (is.null(members) || length(members) == 0L) {
      return(sprintf(
        'shiny::tags$fieldset(class = "access-form-control access-option-group", `data-access-name` = "%s", style = "%s border:1px solid #777;")',
        data_name, escape_r_string(style_group)
      ))
    }

    member_labels <- vapply(members, function(m) {
      if (!is.null(m$attached_label) && !is.null(m$attached_label$caption) && nzchar(m$attached_label$caption)) {
        return(m$attached_label$caption)
      }
      if (!is.null(m$caption) && nzchar(m$caption)) return(m$caption)
      if (!is.null(m$name) && nzchar(m$name)) return(m$name)
      "Option"
    }, character(1), USE.NAMES = FALSE)

    member_values <- vapply(seq_along(members), function(i) {
      m <- members[[i]]
      if (!is.null(m$option_value) && !is.na(m$option_value)) {
        as.character(as.integer(m$option_value))
      } else {
        as.character(i)
      }
    }, character(1), USE.NAMES = FALSE)

    choices_parts <- vapply(seq_along(member_values), function(i) {
      sprintf('"%s" = "%s"',
              escape_r_string(member_labels[i]),
              escape_r_string(member_values[i]))
    }, character(1), USE.NAMES = FALSE)
    choices_expr <- sprintf("c(%s)", paste(choices_parts, collapse = ", "))

    selected_value <- member_values[1]
    if (!is.null(ctrl$default_value) && nzchar(ctrl$default_value)) {
      candidate <- trim_ws(ctrl$default_value)
      if (candidate %in% member_values) selected_value <- candidate
    }

    inner <- sprintf(
      'shiny::radioButtons(inputId = "%s", label = NULL, choices = %s, selected = "%s", width = "100%%", inline = TRUE)',
      name_safe,
      choices_expr,
      escape_r_string(selected_value)
    )

    return(sprintf('shiny::tags$div(class = "access-form-control access-option-group", `data-access-name` = "%s", style = "%s", %s)',
                   data_name, escape_r_string(style_group), inner))
  }

  if (ctrl$type == "Line") {
    return(sprintf(
      'shiny::tags$div(class = "access-form-control", `data-access-name` = "%s", style = "%s border-top:1px solid #777; height:1px;")',
      data_name, escape_r_string(style)
    ))
  }

  if (ctrl$type == "Subform") {
    basenames <- resolve_subform_basename(ctrl)
    subform_file <- NULL
    if (!is.null(form_dir) && nzchar(form_dir) && length(basenames) > 0L) {
      for (b in basenames) {
        candidate <- file.path(form_dir, paste0(b, ".txt"))
        if (file.exists(candidate)) {
          subform_file <- candidate
          break
        }
      }
    }

    if (!is.null(subform_file)) {
      sub_spec <- tryCatch(
        build_form_ui_spec(subform_file, scale = scale, visited = visited, z_mode = z_mode),
        error = function(e) NULL
      )
      if (!is.null(sub_spec)) {
        sub_items <- if (length(sub_spec$root_items) > 0L) paste(sub_spec$root_items, collapse = ", ") else ""
        inner <- sprintf(
          'shiny::tags$div(class = "access-form-root access-subform-root", `data-access-form-name` = "%s", style = "%s", %s)',
          escape_r_string(sub_spec$form_name),
          escape_r_string(sub_spec$root_style),
          sub_items
        )
        return(sprintf(
          'shiny::tags$div(class = "access-form-control access-subform", `data-access-name` = "%s", style = "%s overflow:auto; border:1px solid #777;", %s)',
          data_name, escape_r_string(style), inner
        ))
      }
    }

    placeholder <- sprintf("[Subform: %s]", ifelse(length(basenames) > 0L, basenames[1], ctrl$name))
    return(sprintf(
      'shiny::tags$div(class = "access-form-control access-placeholder", `data-access-name` = "%s", style = "%s", "%s")',
      data_name, escape_r_string(style), escape_r_string(placeholder)
    ))
  }

  if (ctrl$type %in% c("Image", "Attachment", "BoundObjectFrame")) {
    placeholder <- sprintf("[%s]", ctrl$type)
    return(sprintf(
      'shiny::tags$div(class = "access-form-control access-placeholder", `data-access-name` = "%s", style = "%s", "%s")',
      data_name, escape_r_string(style), placeholder
    ))
  }

  sprintf(
    'shiny::tags$div(class = "access-form-control access-placeholder", `data-access-name` = "%s", style = "%s", "[%s]")',
    data_name, escape_r_string(style), escape_r_string(ctrl$type)
  )
}

generate_ui_file <- function(input_file, output_file = NULL, scale = 1.8, z_mode = "natural") {
  spec <- build_form_ui_spec(input_file, scale = scale, z_mode = z_mode)
  form_name <- spec$form_name
  form_caption <- spec$form_caption
  root_style <- spec$root_style
  root_items <- spec$root_items
  control_block <- if (length(root_items)) paste0("    ", paste(root_items, collapse = ",\n    ")) else ""

  generated <- paste0(
    "# Auto-generated from Access form export: ", basename(input_file), "\n",
    "# Source form name: ", form_name, "\n",
    "# This file replicates visual layout and control names, not VBA/event logic.\n\n",
    "library(shiny)\n\n",
    "ui <- fluidPage(\n",
    "  tags$head(\n",
    "    tags$style(HTML(\"\n",
    ".access-form-root { position: relative; }\n",
    ".access-form-control { box-sizing: border-box; overflow: hidden; }\n",
    ".access-form-control .form-group { margin-bottom: 0; }\n",
    ".access-form-control .shiny-input-container { width: 100%; }\n",
    ".access-label { white-space: pre-wrap; overflow: hidden; }\n",
    ".access-input, .access-select, .access-btn { box-sizing: border-box; margin:0; padding:1px 3px; border:1px solid #777; background:#fff; color:inherit; font:inherit; line-height:1.1; }\n",
    ".access-check-label { margin:0; font-weight:normal; display:flex; align-items:center; gap:2px; white-space:nowrap; }\n",
    ".access-check-label > span { display:inline-block; line-height:1; }\n",
    ".access-toggle-btn { border:1px solid #666; background:#e9e9e9; font-weight:600; }\n",
    ".access-option-group { padding: 2px; }\n",
    ".access-option-group .form-group { margin:0; }\n",
    ".access-option-group .radio { margin:0 8px 0 0; }\n",
    ".access-option-group .radio-inline { margin:0 8px 0 0; padding-left:18px; }\n",
    ".access-option-group .shiny-options-group { white-space:nowrap; }\n",
    ".access-tab-selector .tab-content { display:none; }\n",
    ".access-tab-selector .nav { margin-bottom: 0; }\n",
    ".access-placeholder { border: 1px dashed #999; color: #666; font-size: 12px; padding: 2px 4px; }\n",
    "\"))\n",
    "  ),\n",
    "  tags$div(\n",
    "    id = \"", escape_r_string(make_html_id(form_name, "form")), "\",\n",
    "    class = \"access-form-root\",\n",
    "    `data-access-form-name` = \"", escape_r_string(form_name), "\",\n",
    "    `data-access-caption` = \"", escape_r_string(form_caption), "\",\n",
    "    style = \"", escape_r_string(root_style), "\",\n",
    control_block,
    if (length(root_items)) "\n" else "",
    "  )\n",
    ")\n\n",
    "# Optional server scaffold:\n",
    "server <- function(input, output, session) {}\n",
    "# shinyApp(ui, server)\n"
  )

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
      "  Rscript Tools/access_form_to_shiny.R [--scale=1.8] [--zorder=natural|reverse] <path/to/form.txt> [path/to/ui_form.R]\n",
      "  Rscript Tools/access_form_to_shiny.R [--scale=1.8] [--zorder=natural|reverse] <path/to/Forms_directory>\n",
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
