#' @keywords internal
#' @importFrom rlang .data abort warn inform check_installed
#' @importFrom tibble tibble as_tibble
"_PACKAGE"

.datatable.aware <- TRUE

utils::globalVariables(c(".SD", ".N", ".I", ":="))
