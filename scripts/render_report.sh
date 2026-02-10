#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/render_report.sh <template.qmd> [options]

Options:
  --format <html|pdf>         Output format (default: html)
  --plot <plot_number>        Plot number (default: 00000)
  --plots <plot_numbers>      Plot list (default: empty)
  --site-unit <site_unit>     Site unit filter (default: empty)
  --project-id <project_id>   Project ID filter (default: empty)
  --display <display_value>   Display value (default: standard)
  --constancy                Enable constancy format

Examples:
  scripts/render_report.sh short_veg_hierarchy.qmd --display presence_mean
  scripts/render_report.sh short_veg_hierarchy --constancy --plot 10001
EOF
}

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

template="$1"
shift

if [[ "$template" != *.qmd ]]; then
  template="${template}.qmd"
fi

format="html"
plot_number="00000"
plot_numbers=""
site_unit=""
project_id=""
display_value="standard"
constancy="FALSE"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --format)
      format="$2"
      shift 2
      ;;
    --plot)
      plot_number="$2"
      shift 2
      ;;
    --plots)
      plot_numbers="$2"
      shift 2
      ;;
    --site-unit)
      site_unit="$2"
      shift 2
      ;;
    --project-id)
      project_id="$2"
      shift 2
      ;;
    --display)
      display_value="$2"
      shift 2
      ;;
    --constancy)
      constancy="TRUE"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
 done

export REPORT_TEMPLATE="$template"
export REPORT_FORMAT="$format"
export REPORT_PLOT_NUMBER="$plot_number"
export REPORT_PLOT_NUMBERS="$plot_numbers"
export REPORT_SITE_UNIT="$site_unit"
export REPORT_PROJECT_ID="$project_id"
export REPORT_DISPLAY_VALUE="$display_value"
export REPORT_CONSTANCY="$constancy"

Rscript -e "db_path <- normalizePath('data/vpro.duckdb', winslash='/', mustWork=TRUE); template <- Sys.getenv('REPORT_TEMPLATE'); if (!nzchar(template)) stop('Missing REPORT_TEMPLATE'); output_format <- Sys.getenv('REPORT_FORMAT', 'html'); params <- list(plot_number=Sys.getenv('REPORT_PLOT_NUMBER', '00000'), plot_numbers=Sys.getenv('REPORT_PLOT_NUMBERS', ''), site_unit=Sys.getenv('REPORT_SITE_UNIT', ''), project_id=Sys.getenv('REPORT_PROJECT_ID', ''), display_value=Sys.getenv('REPORT_DISPLAY_VALUE', 'standard'), constancy_format=as.logical(Sys.getenv('REPORT_CONSTANCY', 'FALSE')), db_path=db_path, project_root=getwd()); quarto::quarto_render(file.path('reports', template), output_format=output_format, execute_params=params)"
