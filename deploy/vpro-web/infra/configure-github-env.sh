#!/usr/bin/env bash
set -euo pipefail

# Idempotently create/ensure the target GitHub Environment (dev or prod) and
# configure all 6 deployment secrets for .github/workflows/web-deploy.yml.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VPRO_INFRA_SCRIPT_NAME="configure-github-env.sh"
# shellcheck source=env.defaults.sh
source "${SCRIPT_DIR}/env.defaults.sh"

ENV_ARG="devl"
HOST=""
SSH_KEY_FILE=""
OVERRIDE_REPO=""
OVERRIDE_USER=""
OVERRIDE_DEPLOY_DIR=""
OVERRIDE_DOMAIN=""

usage() {
  cat <<'EOF'
Usage:
  configure-github-env.sh --host <ip> --ssh-key-file <private-key-path> [options]

Idempotently ensures the GitHub Environment (dev or prod) exists and sets the
6 deployment secrets required by .github/workflows/web-deploy.yml:
  DO_HOST, DO_USER, DO_SSH_KEY, DO_SSH_KNOWN_HOSTS, DO_DEPLOY_DIR, VPRO_HEALTHCHECK_URL

Options:
  --env <devl|prod>         Target environment (default: devl; maps to GH env dev|prod)
  --host <ip>               Required Droplet public IPv4 or hostname
  --ssh-key-file <path>     Required path to deploy user Ed25519 private key
  --repo <owner/repo>       GitHub repository (default: Boostao/vpro)
  --user <deploy-user>      Droplet SSH deploy user (default: deploy)
  --deploy-dir <dir>        Remote deploy directory (default: /srv/vpro/deploy)
  --domain <fqdn>           Override VPRO_DOMAIN for VPRO_HEALTHCHECK_URL
  -h, --help                Show this help message
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --env)
      [ $# -ge 2 ] || vpro_infra_die "--env requires a value"
      ENV_ARG="$2"
      shift 2
      ;;
    --host)
      [ $# -ge 2 ] || vpro_infra_die "--host requires a value"
      HOST="$2"
      shift 2
      ;;
    --ssh-key-file)
      [ $# -ge 2 ] || vpro_infra_die "--ssh-key-file requires a path"
      SSH_KEY_FILE="$2"
      shift 2
      ;;
    --repo)
      [ $# -ge 2 ] || vpro_infra_die "--repo requires owner/repo"
      OVERRIDE_REPO="$2"
      shift 2
      ;;
    --user)
      [ $# -ge 2 ] || vpro_infra_die "--user requires a value"
      OVERRIDE_USER="$2"
      shift 2
      ;;
    --deploy-dir)
      [ $# -ge 2 ] || vpro_infra_die "--deploy-dir requires a value"
      OVERRIDE_DEPLOY_DIR="$2"
      shift 2
      ;;
    --domain)
      [ $# -ge 2 ] || vpro_infra_die "--domain requires a value"
      OVERRIDE_DOMAIN="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      vpro_infra_die "unknown option: $1"
      ;;
  esac
done

vpro_infra_require_cmd gh ssh-keyscan

resolve_vpro_env_defaults "${ENV_ARG}"
[ -n "${OVERRIDE_REPO}" ] && GH_REPO="${OVERRIDE_REPO}"
[ -n "${OVERRIDE_USER}" ] && VPRO_DEPLOY_USER="${OVERRIDE_USER}"
[ -n "${OVERRIDE_DEPLOY_DIR}" ] && VPRO_DEPLOY_DIR="${OVERRIDE_DEPLOY_DIR}"
[ -n "${OVERRIDE_DOMAIN}" ] && VPRO_DOMAIN="${OVERRIDE_DOMAIN}"

[ -n "${HOST}" ] || vpro_infra_die "--host is required"
[ -n "${SSH_KEY_FILE}" ] || vpro_infra_die "--ssh-key-file is required"
[ -f "${SSH_KEY_FILE}" ] && [ -r "${SSH_KEY_FILE}" ] && [ -s "${SSH_KEY_FILE}" ] \
  || vpro_infra_die "SSH private key file is missing, unreadable, or empty: ${SSH_KEY_FILE}"

vpro_infra_log "Ensuring GitHub Environment '${GH_ENV}' exists on '${GH_REPO}'..."
gh api --method PUT "repos/${GH_REPO}/environments/${GH_ENV}" >/dev/null

vpro_infra_log "Scanning ED25519 SSH host key for '${HOST}'..."
KNOWN_HOSTS="$(ssh-keyscan -t ed25519 -T 10 "${HOST}" 2>/dev/null | grep -E ' ssh-ed25519 ' || true)"
[ -n "${KNOWN_HOSTS}" ] || vpro_infra_die "ssh-keyscan returned no ED25519 host key for '${HOST}'"

HEALTHCHECK_URL="https://${VPRO_DOMAIN}/readyz"

vpro_infra_log "Setting 6 secrets on GitHub Environment '${GH_ENV}' (${GH_REPO})..."
printf '%s' "${HOST}" | gh secret set DO_HOST --repo "${GH_REPO}" --env "${GH_ENV}"
printf '%s' "${VPRO_DEPLOY_USER}" | gh secret set DO_USER --repo "${GH_REPO}" --env "${GH_ENV}"
gh secret set DO_SSH_KEY --repo "${GH_REPO}" --env "${GH_ENV}" < "${SSH_KEY_FILE}"
printf '%s\n' "${KNOWN_HOSTS}" | gh secret set DO_SSH_KNOWN_HOSTS --repo "${GH_REPO}" --env "${GH_ENV}"
printf '%s' "${VPRO_DEPLOY_DIR}" | gh secret set DO_DEPLOY_DIR --repo "${GH_REPO}" --env "${GH_ENV}"
printf '%s' "${HEALTHCHECK_URL}" | gh secret set VPRO_HEALTHCHECK_URL --repo "${GH_REPO}" --env "${GH_ENV}"

vpro_infra_log "GitHub Environment '${GH_ENV}' configured (host=${HOST}, user=${VPRO_DEPLOY_USER}, deploy_dir=${VPRO_DEPLOY_DIR}, healthcheck=${HEALTHCHECK_URL})."
