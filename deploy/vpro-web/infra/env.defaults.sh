#!/usr/bin/env bash
set -euo pipefail

# Shared DigitalOcean, Cloudflare, and GitHub Environment defaults for VPro 2.0
# read-only web server provisioning (`deploy/vpro-web/infra/`).
#
# Intended to be sourced by sibling scripts:
#   source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/env.defaults.sh"
#   resolve_vpro_env_defaults devl

DO_CONTEXT="${DO_CONTEXT:-vpro}"
DO_REGION="${DO_REGION:-tor1}"
DO_VPC_UUID="${DO_VPC_UUID:-22f458d9-5654-4aee-95e0-4401bd4a2c8f}"
DO_IMAGE="${DO_IMAGE:-ubuntu-24-04-x64}"
DO_SSH_KEY_IDS="${DO_SSH_KEY_IDS:-45140884}"
CF_ZONE="${CF_ZONE:-boostao.ca}"
GH_REPO="${GH_REPO:-Boostao/vpro}"
VPRO_DEPLOY_DIR="${VPRO_DEPLOY_DIR:-/srv/vpro/deploy}"
VPRO_DEPLOY_USER="${VPRO_DEPLOY_USER:-deploy}"

vpro_infra_log() {
  local prefix="${VPRO_INFRA_SCRIPT_NAME:-vpro-infra}"
  printf '[%s] %s\n' "${prefix}" "$*" >&2
}

vpro_infra_die() {
  local prefix="${VPRO_INFRA_SCRIPT_NAME:-vpro-infra}"
  printf '[%s] ERROR: %s\n' "${prefix}" "$*" >&2
  exit 1
}

vpro_infra_require_cmd() {
  local missing=0
  local cmd
  for cmd in "$@"; do
    if ! command -v "${cmd}" >/dev/null 2>&1; then
      printf '[%s] ERROR: required prerequisite command not found on PATH: %s\n' \
        "${VPRO_INFRA_SCRIPT_NAME:-vpro-infra}" "${cmd}" >&2
      missing=1
    fi
  done
  if [ "${missing}" -ne 0 ]; then
    exit 1
  fi
}

resolve_vpro_env_defaults() {
  local raw_env="${1:-devl}"
  case "${raw_env}" in
    devl|dev)
      TARGET_ENV="devl"
      DO_PROJECT_NAME="vpro-devl"
      DO_PROJECT_ENV="Development"
      DROPLET_NAME="vpro-web-devl"
      FIREWALL_NAME="vpro-web-devl-fw"
      DROPLET_SIZE="${DROPLET_SIZE:-s-2vcpu-4gb}"
      DROPLET_TAGS="vpro,vpro-devl"
      VPRO_ENV_LABEL="dev"
      VPRO_DOMAIN="${VPRO_DOMAIN:-vpro.devl.boostao.ca}"
      VPRO_IMAGE="${VPRO_IMAGE:-ghcr.io/boostao/vpro/vpro-web:dev}"
      VPRO_MEM_LIMIT="${VPRO_MEM_LIMIT:-2g}"
      VPRO_CPUS="${VPRO_CPUS:-1.5}"
      GH_ENV="dev"
      ;;
    prod)
      TARGET_ENV="prod"
      DO_PROJECT_NAME="vpro-prod"
      DO_PROJECT_ENV="Production"
      DROPLET_NAME="vpro-web-prod"
      FIREWALL_NAME="vpro-web-prod-fw"
      DROPLET_SIZE="${DROPLET_SIZE:-s-2vcpu-4gb}"
      DROPLET_TAGS="vpro,vpro-prod"
      VPRO_ENV_LABEL="prod"
      VPRO_DOMAIN="${VPRO_DOMAIN:-vpro.boostao.ca}"
      VPRO_IMAGE="${VPRO_IMAGE:-ghcr.io/boostao/vpro/vpro-web:latest}"
      VPRO_MEM_LIMIT="${VPRO_MEM_LIMIT:-3g}"
      VPRO_CPUS="${VPRO_CPUS:-1.75}"
      GH_ENV="prod"
      ;;
    *)
      printf '[%s] ERROR: unsupported environment %q (expected devl, dev, or prod)\n' \
        "${VPRO_INFRA_SCRIPT_NAME:-env.defaults}" "${raw_env}" >&2
      return 1
      ;;
  esac
}

_env_defaults_usage() {
  cat <<'EOF'
Usage:
  source deploy/vpro-web/infra/env.defaults.sh
  resolve_vpro_env_defaults <devl|prod>

Or print resolved environment defaults:
  deploy/vpro-web/infra/env.defaults.sh [--env devl|prod]

Options:
  --env <devl|prod>   Print resolved defaults for the given environment (default: devl)
  -h, --help          Show this help message
EOF
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  VPRO_INFRA_SCRIPT_NAME="env.defaults.sh"
  vpro_infra_require_cmd printf
  REQ_ENV="devl"
  while [ $# -gt 0 ]; do
    case "$1" in
      --env)
        [ $# -ge 2 ] || vpro_infra_die "--env requires a value"
        REQ_ENV="$2"
        shift 2
        ;;
      -h|--help)
        _env_defaults_usage
        exit 0
        ;;
      *)
        vpro_infra_die "unknown argument: $1"
        ;;
    esac
  done
  resolve_vpro_env_defaults "${REQ_ENV}"
  cat <<EOF
DO_CONTEXT=${DO_CONTEXT}
DO_REGION=${DO_REGION}
DO_VPC_UUID=${DO_VPC_UUID}
DO_IMAGE=${DO_IMAGE}
DO_SSH_KEY_IDS=${DO_SSH_KEY_IDS}
CF_ZONE=${CF_ZONE}
GH_REPO=${GH_REPO}
VPRO_DEPLOY_DIR=${VPRO_DEPLOY_DIR}
VPRO_DEPLOY_USER=${VPRO_DEPLOY_USER}
TARGET_ENV=${TARGET_ENV}
DO_PROJECT_NAME=${DO_PROJECT_NAME}
DO_PROJECT_ENV=${DO_PROJECT_ENV}
DROPLET_NAME=${DROPLET_NAME}
FIREWALL_NAME=${FIREWALL_NAME}
DROPLET_SIZE=${DROPLET_SIZE}
DROPLET_TAGS=${DROPLET_TAGS}
VPRO_ENV_LABEL=${VPRO_ENV_LABEL}
VPRO_DOMAIN=${VPRO_DOMAIN}
VPRO_IMAGE=${VPRO_IMAGE}
VPRO_MEM_LIMIT=${VPRO_MEM_LIMIT}
VPRO_CPUS=${VPRO_CPUS}
GH_ENV=${GH_ENV}
EOF
fi
