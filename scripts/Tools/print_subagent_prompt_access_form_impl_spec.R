#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
target <- if (length(args) >= 1 && nzchar(args[[1]])) args[[1]] else "../VPRO_ACCESS/VPro64_forAI/Forms/<form>.txt"
recursive <- if (length(args) >= 2 && nzchar(args[[2]])) args[[2]] else "true"

run_cmd <- if (tolower(recursive) %in% c("false", "0", "no")) {
  sprintf('Rscript "scripts/Tools/access_form_impl_spec.R" --recursive=false "%s"', target)
} else {
  sprintf('Rscript "scripts/Tools/access_form_impl_spec.R" "%s"', target)
}

cat(sprintf(
'You are generating Access form implementation specs.\n\nTask:\n1) Run: %s\n2) Collect generated files named: ../VPRO_ACCESS/VPro64_forAI/Forms/FORM_IMPL_SPEC_<form>.md\n3) Summarize results with:\n   - Input target\n   - Generated spec files\n   - Recursive subforms covered\n   - Unresolved procedure references\n\nQuality checks:\n- Ensure event mappings use [Event Procedure] conventions:\n  - control event -> <ControlName>_<EventSuffix>\n  - form event -> Form_<EventSuffix>\n- Ensure report includes UI tree, event map, procedure graph, module links, and source dependencies.\n\nSuggested output block:\nInput: <target>\nGenerated specs:\n- ../VPRO_ACCESS/VPro64_forAI/Forms/FORM_IMPL_SPEC_<form1>.md\n- ../VPRO_ACCESS/VPro64_forAI/Forms/FORM_IMPL_SPEC_<form2>.md\nRecursive subforms: <included|excluded>\nUnresolved references:\n- <none|itemized list>\n',
run_cmd
))
