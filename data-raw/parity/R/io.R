# Base-R input/output helpers for deterministic Access export inventory.
parity_read_text <- function(path) {
  raw <- readBin(path, "raw", n = file.info(path)$size)
  enc <- "latin1"
  decode_utf16 <- function(bytes, little = TRUE) {
    z <- as.integer(bytes)
    z <- z[seq_len(length(z) - length(z) %% 2L)]
    units <- if (little) z[c(TRUE, FALSE)] + 256L * z[c(FALSE, TRUE)] else 256L * z[c(TRUE, FALSE)] + z[c(FALSE, TRUE)]
    # Combine UTF-16 surrogate pairs before producing UTF-8.
    hi <- which(units >= 0xD800L & units <= 0xDBFFL)
    for (i in hi[hi < length(units)]) {
      if (units[i + 1L] >= 0xDC00L && units[i + 1L] <= 0xDFFFL) {
        units[i] <- 0x10000L + (units[i] - 0xD800L) * 0x400L + units[i + 1L] - 0xDC00L
        units[i + 1L] <- NA_integer_
      }
    }
    intToUtf8(units[!is.na(units)])
  }
  if (length(raw) >= 2L && identical(as.integer(raw[1:2]), c(255L, 254L))) {
    text <- decode_utf16(raw[-c(1, 2)], TRUE)
    enc <- "UTF-16LE BOM"
  } else if (length(raw) >= 2L && identical(as.integer(raw[1:2]), c(254L, 255L))) {
    text <- decode_utf16(raw[-c(1, 2)], FALSE)
    enc <- "UTF-16BE BOM"
  } else if (length(raw) >= 3L && identical(as.integer(raw[1:3]), c(239L, 187L, 191L))) {
    text <- rawToChar(raw[-c(1, 2, 3)])
    enc <- "UTF-8 BOM"
  } else {
    candidate <- rawToChar(raw)
    utf8 <- iconv(candidate, from = "UTF-8", to = "UTF-8", sub = NA)
    if (!is.na(utf8)) {
      text <- utf8
      enc <- "UTF-8"
    } else {
      text <- iconv(candidate, from = "latin1", to = "UTF-8")
    }
  }
  list(text = text, lines = strsplit(text, "\r\n|\n|\r", perl = TRUE)[[1]], encoding = enc)
}
parity_relpath <- function(path, root) {
  path <- normalizePath(path, winslash = "/", mustWork = FALSE)
  root <- paste0(sub("/$", "", normalizePath(root, winslash = "/", mustWork = FALSE)), "/")
  sub(paste0("^", gsub("([][{}()+*^$\\\\.|?])", "\\\\\\1", root)), "", path)
}
parity_id <- function(...) paste(..., sep = "::")
parity_flag <- function(text, pattern) as.integer(grepl(pattern, text, ignore.case = TRUE, perl = TRUE))
parity_write_csv <- function(x, path) {
  if (is.null(x) || !length(x)) {
    x <- data.frame()
  }
  if (nrow(x) && ncol(x)) {
    x <- x[do.call(order, c(unname(x), list(na.last = TRUE))), , drop = FALSE]
  }
  write.csv(x, path, row.names = FALSE, na = "", quote = TRUE, fileEncoding = "UTF-8")
}
parity_json <- function(x) {
  esc <- function(s) paste0('"', gsub('"', '\\\\"', gsub('\\\\', '\\\\\\\\', as.character(s))), '"')
  if (is.null(x)) {
    return("null")
  }
  if (is.list(x)) {
    return(paste0("{", paste(paste0(esc(names(x)), ":", vapply(x, parity_json, "")), collapse = ","), "}"))
  }
  if (is.numeric(x)) {
    return(as.character(x))
  }
  if (is.logical(x)) {
    return(tolower(as.character(x)))
  }
  esc(x)
}
