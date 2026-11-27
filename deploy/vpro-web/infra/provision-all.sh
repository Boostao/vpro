#!/usr/bin/env bash
set -euo pipefail

# End-to-end idempotent infrastructure orchestrator for vpro-web (devl or prod):
#   1. Provision DigitalOcean Projects (vpro-devl & vpro-prod), Droplet, and Firewall
#   2. Configure Cloudflare DNS A record (DNS-only by default for Caddy TLS + HTTP/3)
#   3. Generate ephemeral Ed25519 deploy keypair (shredded on exit)
#   4. Bootstrap Ubuntu 24.04 Droplet (Docker, deploy user, SSH hardening, /srv/vpro/*, .env)
#   5. Configure GitHub Environment (dev or prod) and all 6 deployment secrets
#   6. Optionally sync PMTiles archives and/or seed an initial verified snapshot bundle
#   7. Optionally dispatch .github/workflows/web-deploy.yml

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VPRO_INFRA_SCRIPT_NAME="provision-all.sh"
# shellcheck source=env.defaults.sh
source "${SCRIPT_DIR}/env.defaults.sh"

ENV_ARG="devl"
OVERRIDE_CONTEXT=""
OVERRIDE_REGION=""
OVERRIDE_SIZE=""
OVERRIDE_VPC_UUID=""
OVERRIDE_SSH_KEYS=""
SSH_CIDR=""
OVERRIDE_ZONE=""
OVERRIDE_DOMAIN=""
PROXIED=""
TTL=""
ADMIN_USER="root"
ADMIN_SSH_KEY=""
OVERRIDE_IMAGE=""
OVERRIDE_DEPLOY_DIR=""
OVERRIDE_REPO=""
OVERWRITE_ENV=0
PMTILES_DIR=""
SNAPSHOT_BUNDLE=""
VPRO_SNAPSHOT_BIN=""
TRIGGER_DEPLOY=0

usage() {
  cat <<'EOF'
Usage:
  provision-all.sh [--env devl|prod] [options]

End-to-end idempotent DigitalOcean + Cloudflare + GitHub Environment provisioner
for VPro 2.0 read-only web hosting (`vpro-web`).

Options:
  --env <devl|prod>            Target environment (default: devl; accepts 'dev' alias)
  --context <ctx>              doctl authentication context (default: vpro)
  --region <slug>              DigitalOcean region slug (default: tor1)
  --size <slug>                Droplet size slug (default: s-2vcpu-4gb)
  --vpc-uuid <uuid>            DigitalOcean VPC UUID (default: default-tor1 VPC)
  --ssh-keys <ids>             Comma-separated DO SSH key IDs or fingerprints
  --ssh-cidr <cidrs>           Comma-separated allowed SSH CIDRs (default: 0.0.0.0/0,::/0)
  --zone <zone>                Cloudflare DNS zone (default: boostao.ca)
  --domain <fqdn>              Override VPRO_DOMAIN
  --proxied <true|false>       Cloudflare proxy mode (default: false)
  --ttl <int>                  Cloudflare DNS TTL (default: 300)
  --admin-user <user>          SSH bootstrap admin user (default: root)
  --admin-ssh-key <path>       Optional SSH private key path for admin bootstrap
  --image <ref>                Override VPRO_IMAGE written to .env
  --deploy-dir <dir>           Remote deploy directory (default: /srv/vpro/deploy)
  --repo <owner/repo>          GitHub repository (default: Boostao/vpro)
  --overwrite-env              Overwrite existing remote .env during bootstrap
  --pmtiles-dir <dir>          Optional local directory of *.pmtiles to rsync to /srv/vpro/pmtiles/
  --snapshot-bundle <dir>      Optional local snapshot bundle dir to verify & seed
  --vpro-snapshot-bin <path>   Optional path to local vpro-snapshot binary
  --trigger-deploy             Dispatch web-deploy.yml workflow after provisioning
  -h, --help                   Show this help message
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --env)
      [ $# -ge 2 ] || vpro_infra_die "--env requires a value"
      ENV_ARG="$2"
      shift 2
      ;;
    --context)
      [ $# -ge 2 ] || vpro_infra_die "--context requires a value"
      OVERRIDE_CONTEXT="$2"
      shift 2
      ;;
    --region)
      [ $# -ge 2 ] || vpro_infra_die "--region requires a value"
      OVERRIDE_REGION="$2"
      shift 2
      ;;
    --size)
      [ $# -ge 2 ] || vpro_infra_die "--size requires a value"
      OVERRIDE_SIZE="$2"
      shift 2
      ;;
    --vpc-uuid)
      [ $# -ge 2 ] || vpro_infra_die "--vpc-uuid requires a value"
      OVERRIDE_VPC_UUID="$2"
      shift 2
      ;;
    --ssh-keys)
      [ $# -ge 2 ] || vpro_infra_die "--ssh-keys requires a value"
      OVERRIDE_SSH_KEYS="$2"
      shift 2
      ;;
    --ssh-cidr)
      [ $# -ge 2 ] || vpro_infra_die "--ssh-cidr requires a value"
      SSH_CIDR="$2"
      shift 2
      ;;
    --zone)
      [ $# -ge 2 ] || vpro_infra_die "--zone requires a value"
      OVERRIDE_ZONE="$2"
      shift 2
      ;;
    --domain)
      [ $# -ge 2 ] || vpro_infra_die "--domain requires a value"
      OVERRIDE_DOMAIN="$2"
      shift 2
      ;;
    --proxied)
      [ $# -ge 2 ] || vpro_infra_die "--proxied requires true or false"
      PROXIED="$2"
      shift 2
      ;;
    --ttl)
      [ $# -ge 2 ] || vpro_infra_die "--ttl requires an integer"
      TTL="$2"
      shift 2
      ;;
    --admin-user)
      [ $# -ge 2 ] || vpro_infra_die "--admin-user requires a value"
      ADMIN_USER="$2"
      shift 2
      ;;
    --admin-ssh-key)
      [ $# -ge 2 ] || vpro_infra_die "--admin-ssh-key requires a path"
      ADMIN_SSH_KEY="$2"
      shift 2
      ;;
    --image)
      [ $# -ge 2 ] || vpro_infra_die "--image requires a value"
      OVERRIDE_IMAGE="$2"
      shift 2
      ;;
    --deploy-dir)
      [ $# -ge 2 ] || vpro_infra_die "--deploy-dir requires a value"
      OVERRIDE_DEPLOY_DIR="$2"
      shift 2
      ;;
    --repo)
      [ $# -ge 2 ] || vpro_infra_die "--repo requires owner/repo"
      OVERRIDE_REPO="$2"
      shift 2
      ;;
    --overwrite-env)
      OVERWRITE_ENV=1
      shift
      ;;
    --pmtiles-dir)
      [ $# -ge 2 ] || vpro_infra_die "--pmtiles-dir requires a directory path"
      PMTILES_DIR="$2"
      shift 2
      ;;
    --snapshot-bundle)
      [ $# -ge 2 ] || vpro_infra_die "--snapshot-bundle requires a directory path"
      SNAPSHOT_BUNDLE="$2"
      shift 2
      ;;
    --vpro-snapshot-bin)
      [ $# -ge 2 ] || vpro_infra_die "--vpro-snapshot-bin requires a path"
      VPRO_SNAPSHOT_BIN="$2"
      shift 2
      ;;
    --trigger-deploy)
      TRIGGER_DEPLOY=1
      shift
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

vpro_infra_require_cmd doctl cf gh jq ssh scp ssh-keygen ssh-keyscan
if [ -n "${PMTILES_DIR}" ]; then
  vpro_infra_require_cmd rsync
  [ -d "${PMTILES_DIR}" ] || vpro_infra_die "--pmtiles-dir does not exist: ${PMTILES_DIR}"
fi
if [ -n "${SNAPSHOT_BUNDLE}" ]; then
  [ -d "${SNAPSHOT_BUNDLE}" ] || vpro_infra_die "--snapshot-bundle does not exist: ${SNAPSHOT_BUNDLE}"
fi

resolve_vpro_env_defaults "${ENV_ARG}"
[ -n "${OVERRIDE_DOMAIN}" ] && VPRO_DOMAIN="${OVERRIDE_DOMAIN}"
[ -n "${OVERRIDE_DEPLOY_DIR}" ] && VPRO_DEPLOY_DIR="${OVERRIDE_DEPLOY_DIR}"
[ -n "${OVERRIDE_REPO}" ] && GH_REPO="${OVERRIDE_REPO}"

# Step 1: Provision DigitalOcean Projects, Droplet, and Cloud Firewall
vpro_infra_log "Step 1/5: Provisioning DigitalOcean resources for env='${TARGET_ENV}'..."
DO_ARGS=(--env "${TARGET_ENV}" --json)
[ -n "${OVERRIDE_CONTEXT}" ] && DO_ARGS+=(--context "${OVERRIDE_CONTEXT}")
[ -n "${OVERRIDE_REGION}" ] && DO_ARGS+=(--region "${OVERRIDE_REGION}")
[ -n "${OVERRIDE_SIZE}" ] && DO_ARGS+=(--size "${OVERRIDE_SIZE}")
[ -n "${OVERRIDE_VPC_UUID}" ] && DO_ARGS+=(--vpc-uuid "${OVERRIDE_VPC_UUID}")
[ -n "${OVERRIDE_SSH_KEYS}" ] && DO_ARGS+=(--ssh-keys "${OVERRIDE_SSH_KEYS}")
[ -n "${SSH_CIDR}" ] && DO_ARGS+=(--ssh-cidr "${SSH_CIDR}")

DO_JSON="$("${SCRIPT_DIR}/provision-do.sh" "${DO_ARGS[@]}")"
DROPLET_ID="$(printf '%s' "${DO_JSON}" | jq -er '.DROPLET_ID')"
DROPLET_IP="$(printf '%s' "${DO_JSON}" | jq -er '.DROPLET_IP')"
FIREWALL_ID="$(printf '%s' "${DO_JSON}" | jq -er '.FIREWALL_ID')"
TARGET_PROJECT_ID="$(printf '%s' "${DO_JSON}" | jq -er '.TARGET_PROJECT_ID')"

# Step 2: Configure Cloudflare DNS
vpro_infra_log "Step 2/5: Configuring Cloudflare DNS for '${VPRO_DOMAIN}' -> ${DROPLET_IP}..."
DNS_ARGS=(--env "${TARGET_ENV}" --ip "${DROPLET_IP}")
[ -n "${OVERRIDE_ZONE}" ] && DNS_ARGS+=(--zone "${OVERRIDE_ZONE}")
[ -n "${OVERRIDE_DOMAIN}" ] && DNS_ARGS+=(--domain "${OVERRIDE_DOMAIN}")
[ -n "${PROXIED}" ] && DNS_ARGS+=(--proxied "${PROXIED}")
[ -n "${TTL}" ] && DNS_ARGS+=(--ttl "${TTL}")
"${SCRIPT_DIR}/configure-dns.sh" "${DNS_ARGS[@]}"

# Step 3: Generate ephemeral Ed25519 deploy keypair (shredded & removed on exit)
vpro_infra_log "Step 3/5: Generating ephemeral Ed25519 CI deploy keypair..."
TMP_KEY_DIR="$(mktemp -d)"
chmod 0700 "${TMP_KEY_DIR}"
cleanup() {
  if [ -n "${TMP_KEY_DIR:-}" ] && [ -d "${TMP_KEY_DIR}" ]; then
    if [ -f "${TMP_KEY_DIR}/id_deploy" ] && command -v shred >/dev/null 2>&1; then
      shred -u "${TMP_KEY_DIR}/id_deploy" 2>/dev/null || true
    fi
    rm -rf "${TMP_KEY_DIR}" || true
  fi
}
trap cleanup EXIT

ssh-keygen -t ed25519 -N "" \
  -C "vpro-web-${TARGET_ENV}-deploy-$(date -u +%Y%m%dT%H%M%SZ)" \
  -f "${TMP_KEY_DIR}/id_deploy" >/dev/null
chmod 0600 "${TMP_KEY_DIR}/id_deploy"

# Step 4: Bootstrap Droplet
vpro_infra_log "Step 4/5: Bootstrapping Droplet ${DROPLET_IP}..."
BOOT_ARGS=(
  --env "${TARGET_ENV}"
  --host "${DROPLET_IP}"
  --deploy-pubkey "${TMP_KEY_DIR}/id_deploy.pub"
  --admin-user "${ADMIN_USER}"
  --deploy-dir "${VPRO_DEPLOY_DIR}"
)
[ -n "${ADMIN_SSH_KEY}" ] && BOOT_ARGS+=(--admin-ssh-key "${ADMIN_SSH_KEY}")
[ -n "${OVERRIDE_DOMAIN}" ] && BOOT_ARGS+=(--domain "${OVERRIDE_DOMAIN}")
[ -n "${OVERRIDE_IMAGE}" ] && BOOT_ARGS+=(--image "${OVERRIDE_IMAGE}")
[ "${OVERWRITE_ENV}" -eq 1 ] && BOOT_ARGS+=(--overwrite-env)
"${SCRIPT_DIR}/bootstrap-droplet.sh" "${BOOT_ARGS[@]}"

# Step 5: Configure GitHub Environment & Secrets
vpro_infra_log "Step 5/5: Configuring GitHub Environment '${GH_ENV}' on '${GH_REPO}'..."
GH_ARGS=(
  --env "${TARGET_ENV}"
  --host "${DROPLET_IP}"
  --ssh-key-file "${TMP_KEY_DIR}/id_deploy"
  --repo "${GH_REPO}"
  --user "${VPRO_DEPLOY_USER}"
  --deploy-dir "${VPRO_DEPLOY_DIR}"
)
[ -n "${OVERRIDE_DOMAIN}" ] && GH_ARGS+=(--domain "${OVERRIDE_DOMAIN}")
"${SCRIPT_DIR}/configure-github-env.sh" "${GH_ARGS[@]}"

# Optional Step 6a: Sync PMTiles archives
if [ -n "${PMTILES_DIR}" ]; then
  vpro_infra_log "Syncing *.pmtiles from '${PMTILES_DIR}' to ${VPRO_DEPLOY_USER}@${DROPLET_IP}:/srv/vpro/pmtiles/..."
  rsync -av --chmod=F0444 --include='*.pmtiles' --exclude='*' \
    -e "ssh -i '${TMP_KEY_DIR}/id_deploy' -o BatchMode=yes -o ConnectTimeout=15 -o StrictHostKeyChecking=accept-new" \
    "${PMTILES_DIR%/}/" "${VPRO_DEPLOY_USER}@${DROPLET_IP}:/srv/vpro/pmtiles/"
fi

# Optional Step 6b: Seed initial verified snapshot bundle
if [ -n "${SNAPSHOT_BUNDLE}" ]; then
  vpro_infra_log "Seeding verified snapshot bundle '${SNAPSHOT_BUNDLE}' onto ${DROPLET_IP}..."
  SEED_ARGS=(
    --host "${DROPLET_IP}"
    --bundle "${SNAPSHOT_BUNDLE}"
    --user "${VPRO_DEPLOY_USER}"
    --ssh-key "${TMP_KEY_DIR}/id_deploy"
    --deploy-dir "${VPRO_DEPLOY_DIR}"
  )
  [ -n "${VPRO_SNAPSHOT_BIN}" ] && SEED_ARGS+=(--vpro-snapshot-bin "${VPRO_SNAPSHOT_BIN}")
  "${SCRIPT_DIR}/seed-initial-snapshot.sh" "${SEED_ARGS[@]}"
fi

# Optional Step 7: Trigger GitHub Actions web-deploy workflow
if [ "${TRIGGER_DEPLOY}" -eq 1 ]; then
  vpro_infra_log "Dispatching web-deploy.yml for GitHub Environment '${GH_ENV}' on '${GH_REPO}'..."
  gh workflow run web-deploy.yml --repo "${GH_REPO}" -f "environment=${GH_ENV}"
fi

cat <<EOF
Provisioning complete:
  TARGET_ENV=${TARGET_ENV}
  GH_ENV=${GH_ENV}
  DO_PROJECT_ID=${TARGET_PROJECT_ID}
  DROPLET_ID=${DROPLET_ID}
  DROPLET_IP=${DROPLET_IP}
  FIREWALL_ID=${FIREWALL_ID}
  VPRO_DOMAIN=${VPRO_DOMAIN}
  VPRO_DEPLOY_DIR=${VPRO_DEPLOY_DIR}
  VPRO_HEALTHCHECK_URL=https://${VPRO_DOMAIN}/readyz
EOF
