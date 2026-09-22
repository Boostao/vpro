# Static target inventory; no target code is evaluated.
parity_r_functions <- function(path, root) {
  parsed <- tryCatch(parse(path, keep.source = TRUE), error = function(e) NULL)
  if (is.null(parsed)) {
    return(data.frame())
  }
  rel <- parity_relpath(path, root)
  references <- attr(parsed, "srcref")
  rows <- lapply(seq_along(parsed), function(i) {
    expression <- parsed[[i]]
    operator <- if (is.call(expression)) expression[[1]] else NULL
    is_assignment <- is.symbol(operator) &&
      (identical(operator, as.name("<-")) || identical(operator, as.name("=")))
    if (!is_assignment || !is.symbol(expression[[2]]) || !is.call(expression[[3]]) || !identical(as.character(expression[[3]][[1]]), "function")) {
      return(NULL)
    }
    name <- as.character(expression[[2]])
    reference <- references[[i]]
    data.frame(
      id = parity_id("r_function", rel, name),
      target_type = "r_function",
      name = name,
      path = rel,
      line_start = as.integer(reference[[1]]),
      line_end = as.integer(reference[[3]]),
      stringsAsFactors = FALSE
    )
  })
  out <- Filter(Negate(is.null), rows)
  if (!length(out)) data.frame() else do.call(rbind, out)
}
parity_test_declarations <- function(path, root) {
  x <- tryCatch(parity_read_text(path)$lines, error = function(e) character())
  ix <- grep("test_that\\s*\\(", x, perl = TRUE)
  if (!length(ix)) {
    return(data.frame())
  }
  data.frame(
    id = vapply(ix, function(i) parity_id("test", parity_relpath(path, root), i), ""),
    target_type = "test_that",
    name = sub('.*test_that\\s*\\(\\s*["\\\']([^"\\\']+).*', "\\1", x[ix], perl = TRUE),
    path = parity_relpath(path, root),
    line_start = ix,
    line_end = ix,
    stringsAsFactors = FALSE
  )
}
