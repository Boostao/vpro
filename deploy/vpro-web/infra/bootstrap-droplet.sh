#!/usr/bin/env bash
set -euo pipefail

# Idempotently bootstrap an Ubuntu 24.04 DigitalOcean Droplet for vpro-web:
# installs Docker Engine + Compose v2, hardens SSH, creates non-root deploy user,
# provisions /srv/vpro/* + /etc/vpro directories, uploads compose/Caddy/sync files,
# and initializes .env (preserving existing .env unless --overwrite-env is set).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VPRO_WEB_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
VPRO_INFRA_SCRIPT_NAME="bootstrap-droplet.sh"
# shellcheck source=env.defaults.sh
source "${SCRIPT_DIR}/env.defaults.sh"

ENV_ARG="devl"
HOST=""
DEPLOY_PUBKEY_FILE=""
ADMIN_USER="root"
ADMIN_SSH_KEY=""
OVERRIDE_DOMAIN=""
OVERRIDE_IMAGE=""
OVERRIDE_DEPLOY_DIR=""
OVERWRITE_ENV=0

usage() {
  cat <<'EOF'
Usage:
  bootstrap-droplet.sh --host <ip> --deploy-pubkey <path> [options]

Bootstraps a DigitalOcean Droplet for VPro 2.0 read-only web hosting.

Options:
  --env <devl|prod>         Target environment (default: devl; accepts 'dev' alias)
  --host <ip>               Required Droplet public IPv4 or hostname
  --deploy-pubkey <path>    Required path to SSH public key for the deploy user
  --admin-user <user>       SSH bootstrap admin user (default: root)
  --admin-ssh-key <path>    Optional SSH private key path for admin login
  --domain <fqdn>           Override VPRO_DOMAIN
  --image <ref>             Override VPRO_IMAGE
  --deploy-dir <dir>        Remote deploy directory (default: /srv/vpro/deploy)
  --overwrite-env           Overwrite existing remote .env file
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
    --deploy-pubkey)
      [ $# -ge 2 ] || vpro_infra_die "--deploy-pubkey requires a path"
      DEPLOY_PUBKEY_FILE="$2"
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
    --domain)
      [ $# -ge 2 ] || vpro_infra_die "--domain requires a value"
      OVERRIDE_DOMAIN="$2"
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
    --overwrite-env)
      OVERWRITE_ENV=1
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

vpro_infra_require_cmd ssh scp

resolve_vpro_env_defaults "${ENV_ARG}"
[ -n "${OVERRIDE_DOMAIN}" ] && VPRO_DOMAIN="${OVERRIDE_DOMAIN}"
[ -n "${OVERRIDE_IMAGE}" ] && VPRO_IMAGE="${OVERRIDE_IMAGE}"
[ -n "${OVERRIDE_DEPLOY_DIR}" ] && VPRO_DEPLOY_DIR="${OVERRIDE_DEPLOY_DIR}"

[ -n "${HOST}" ] || vpro_infra_die "--host is required"
[ -n "${DEPLOY_PUBKEY_FILE}" ] || vpro_infra_die "--deploy-pubkey is required"
[ -r "${DEPLOY_PUBKEY_FILE}" ] || vpro_infra_die "cannot read deploy public key: ${DEPLOY_PUBKEY_FILE}"

DEPLOY_PUBKEY="$(tr -d '\r\n' < "${DEPLOY_PUBKEY_FILE}")"
[ -n "${DEPLOY_PUBKEY}" ] || vpro_infra_die "deploy public key file is empty: ${DEPLOY_PUBKEY_FILE}"
DEPLOY_PUBKEY_B64="$(printf '%s' "${DEPLOY_PUBKEY}" | base64 | tr -d '\r\n')"

for req_file in docker-compose.yml Caddyfile sync-snapshot.sh; do
  [ -r "${VPRO_WEB_DIR}/${req_file}" ] || vpro_infra_die "missing deployment artifact: ${VPRO_WEB_DIR}/${req_file}"
done

SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new)
if [ -n "${ADMIN_SSH_KEY}" ]; then
  [ -r "${ADMIN_SSH_KEY}" ] || vpro_infra_die "cannot read admin SSH key: ${ADMIN_SSH_KEY}"
  SSH_OPTS+=(-i "${ADMIN_SSH_KEY}")
fi

REMOTE="${ADMIN_USER}@${HOST}"

vpro_infra_log "Waiting up to 120s for SSH readiness on ${REMOTE}..."
ssh_ready=0
deadline=$((SECONDS + 120))
while [ "${SECONDS}" -lt "${deadline}" ]; do
  if ssh "${SSH_OPTS[@]}" "${REMOTE}" true >/dev/null 2>&1; then
    ssh_ready=1
    break
  fi
  sleep 3
done
[ "${ssh_ready}" -eq 1 ] || vpro_infra_die "SSH did not become ready on ${REMOTE} within 120s"
vpro_infra_log "SSH is reachable on ${REMOTE}."

vpro_infra_log "Running idempotent host bootstrap on ${HOST} (env=${TARGET_ENV}, deploy_user=${VPRO_DEPLOY_USER})..."
ssh "${SSH_OPTS[@]}" "${REMOTE}" \
  bash -s -- "${VPRO_DEPLOY_USER}" "${VPRO_DEPLOY_DIR}" "${DEPLOY_PUBKEY_B64}" <<'REMOTE_BOOTSTRAP'
set -euo pipefail

DEPLOY_USER="$1"
DEPLOY_DIR="$2"
DEPLOY_PUBKEY_B64="$3"
DEPLOY_PUBKEY="$(printf '%s' "${DEPLOY_PUBKEY_B64}" | base64 -d | tr -d '\r\n')"
[ -n "${DEPLOY_PUBKEY}" ] || { echo "ERROR: decoded deploy public key is empty" >&2; exit 1; }

SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  SUDO="sudo"
fi

export DEBIAN_FRONTEND=noninteractive

# On freshly provisioned Ubuntu 24.04 Droplets, cloud-init / unattended-upgrades
# may briefly hold the apt/dpkg lock right after SSH becomes reachable.
if command -v cloud-init >/dev/null 2>&1; then
  ${SUDO} cloud-init status --wait >/dev/null 2>&1 || true
fi

wait_for_apt_lock() {
  local waited=0
  while ${SUDO} fuser /var/lib/dpkg/lock-frontend /var/lib/apt/lists/lock /var/cache/apt/archives/lock >/dev/null 2>&1; do
    if [ "${waited}" -ge 180 ]; then
      echo "ERROR: timed out waiting for apt/dpkg lock" >&2
      exit 1
    fi
    sleep 3
    waited=$((waited + 3))
  done
}

# Install base operational packages
wait_for_apt_lock
${SUDO} apt-get -o DPkg::Lock::Timeout=120 update -qq
${SUDO} apt-get -o DPkg::Lock::Timeout=120 install -y -qq ca-certificates curl jq rsync unattended-upgrades

# Install Docker Engine + Compose v2 plugin if not already present
if ! command -v docker >/dev/null 2>&1; then
  wait_for_apt_lock
  curl -fsSL https://get.docker.com | ${SUDO} sh
fi
${SUDO} systemctl enable --now docker
docker compose version >/dev/null

# Ensure non-root deploy user exists, password disabled for key-only auth, in docker group
if ! id -u "${DEPLOY_USER}" >/dev/null 2>&1; then
  ${SUDO} useradd --create-home --shell /bin/bash "${DEPLOY_USER}"
fi
${SUDO} usermod -p '*' "${DEPLOY_USER}" >/dev/null 2>&1 || true
${SUDO} usermod -aG docker "${DEPLOY_USER}"

DEPLOY_HOME="$(getent passwd "${DEPLOY_USER}" | cut -d: -f6)"
[ -n "${DEPLOY_HOME}" ] || { echo "ERROR: failed to resolve home directory for ${DEPLOY_USER}" >&2; exit 1; }

${SUDO} install -d -m 0700 -o "${DEPLOY_USER}" -g "${DEPLOY_USER}" "${DEPLOY_HOME}/.ssh"
AUTH_KEYS="${DEPLOY_HOME}/.ssh/authorized_keys"
if ! ${SUDO} test -f "${AUTH_KEYS}"; then
  ${SUDO} install -m 0600 -o "${DEPLOY_USER}" -g "${DEPLOY_USER}" /dev/null "${AUTH_KEYS}"
fi
if ! ${SUDO} grep -Fxq -- "${DEPLOY_PUBKEY}" "${AUTH_KEYS}"; then
  printf '%s\n' "${DEPLOY_PUBKEY}" | ${SUDO} tee -a "${AUTH_KEYS}" >/dev/null
fi
${SUDO} chmod 0600 "${AUTH_KEYS}"
${SUDO} chown "${DEPLOY_USER}:${DEPLOY_USER}" "${AUTH_KEYS}"

# Harden SSH daemon configuration (validate before reloading)
HARDENING_CONF="/etc/ssh/sshd_config.d/99-vpro-hardening.conf"
${SUDO} install -d -m 0755 /etc/ssh/sshd_config.d
${SUDO} tee "${HARDENING_CONF}" >/dev/null <<'EOF'
# Managed by vpro deploy/vpro-web/infra/bootstrap-droplet.sh
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin prohibit-password
EOF
${SUDO} chmod 0644 "${HARDENING_CONF}"

if ${SUDO} sshd -t; then
  if systemctl list-unit-files ssh.service >/dev/null 2>&1 && systemctl is-active --quiet ssh.service; then
    ${SUDO} systemctl reload ssh.service
  elif systemctl list-unit-files sshd.service >/dev/null 2>&1 && systemctl is-active --quiet sshd.service; then
    ${SUDO} systemctl reload sshd.service
  fi
else
  ${SUDO} rm -f "${HARDENING_CONF}"
  echo "ERROR: sshd -t validation failed; removed ${HARDENING_CONF}" >&2
  exit 1
fi

# Create canonical host directories:
# - ${DEPLOY_DIR}: deploy:deploy (0755)
# - /srv/vpro/{data,data/releases,pmtiles,pictures}: deploy:10001 (0755)
#   so deploy manages snapshots/PMTiles without root while container UID 10001 reads them
# - /etc/vpro: root:root (0700) reserved for optional future host-side snapshot-builder PG env
${SUDO} mkdir -p "${DEPLOY_DIR}" /srv/vpro/data/releases /srv/vpro/pmtiles /srv/vpro/pictures /etc/vpro
${SUDO} chown "${DEPLOY_USER}:${DEPLOY_USER}" "${DEPLOY_DIR}"
${SUDO} chmod 0755 "${DEPLOY_DIR}"

${SUDO} chown root:root /srv/vpro
${SUDO} chmod 0755 /srv/vpro
for data_dir in /srv/vpro/data /srv/vpro/data/releases /srv/vpro/pmtiles /srv/vpro/pictures; do
  ${SUDO} chown "${DEPLOY_USER}:10001" "${data_dir}"
  ${SUDO} chmod 0755 "${data_dir}"
done

${SUDO} chown root:root /etc/vpro
${SUDO} chmod 0700 /etc/vpro
REMOTE_BOOTSTRAP

vpro_infra_log "Uploading docker-compose.yml, Caddyfile, and sync-snapshot.sh to ${VPRO_DEPLOY_DIR}..."
REMOTE_STAGE="$(ssh "${SSH_OPTS[@]}" "${REMOTE}" "mktemp -d /tmp/vpro-bootstrap-XXXXXX")"
cleanup_remote_stage() {
  if [ -n "${REMOTE_STAGE:-}" ]; then
    ssh "${SSH_OPTS[@]}" "${REMOTE}" "rm -rf '${REMOTE_STAGE}'" >/dev/null 2>&1 || true
  fi
}
trap cleanup_remote_stage EXIT

scp "${SSH_OPTS[@]}" \
  "${VPRO_WEB_DIR}/docker-compose.yml" \
  "${VPRO_WEB_DIR}/Caddyfile" \
  "${VPRO_WEB_DIR}/sync-snapshot.sh" \
  "${REMOTE}:${REMOTE_STAGE}/"

ssh "${SSH_OPTS[@]}" "${REMOTE}" \
  bash -s -- \
    "${REMOTE_STAGE}" \
    "${VPRO_DEPLOY_USER}" \
    "${VPRO_DEPLOY_DIR}" \
    "${OVERWRITE_ENV}" \
    "${VPRO_ENV_LABEL}" \
    "${VPRO_DOMAIN}" \
    "${VPRO_IMAGE}" \
    "${VPRO_MEM_LIMIT}" \
    "${VPRO_CPUS}" <<'REMOTE_CONFIG'
set -euo pipefail

REMOTE_STAGE="$1"
DEPLOY_USER="$2"
DEPLOY_DIR="$3"
OVERWRITE_ENV="$4"
VPRO_ENV_LABEL="$5"
VPRO_DOMAIN="$6"
VPRO_IMAGE="$7"
VPRO_MEM_LIMIT="$8"
VPRO_CPUS="$9"

SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  SUDO="sudo"
fi

${SUDO} install -m 0644 -o "${DEPLOY_USER}" -g "${DEPLOY_USER}" "${REMOTE_STAGE}/docker-compose.yml" "${DEPLOY_DIR}/docker-compose.yml"
${SUDO} install -m 0644 -o "${DEPLOY_USER}" -g "${DEPLOY_USER}" "${REMOTE_STAGE}/Caddyfile" "${DEPLOY_DIR}/Caddyfile"
${SUDO} install -m 0755 -o "${DEPLOY_USER}" -g "${DEPLOY_USER}" "${REMOTE_STAGE}/sync-snapshot.sh" "${DEPLOY_DIR}/sync-snapshot.sh"
rm -rf "${REMOTE_STAGE}"

ENV_FILE="${DEPLOY_DIR}/.env"
if [ "${OVERWRITE_ENV}" -eq 1 ] || ! ${SUDO} test -f "${ENV_FILE}"; then
  TMP_ENV="$(mktemp /tmp/vpro-env-XXXXXX)"
  cat > "${TMP_ENV}" <<EOF
# Managed by deploy/vpro-web/infra/bootstrap-droplet.sh
VPRO_ENV=${VPRO_ENV_LABEL}
VPRO_DOMAIN=${VPRO_DOMAIN}
VPRO_IMAGE=${VPRO_IMAGE}
VPRO_DATA_DIR=/srv/vpro/data/current
VPRO_DATA_ROOT=/srv/vpro/data
VPRO_WEB_DATA_DIR=/srv/vpro/data/current
VPRO_PMTILES_DIR=/srv/vpro/pmtiles
VPRO_PICTURES_DIR=/srv/vpro/pictures
VPRO_MEM_LIMIT=${VPRO_MEM_LIMIT}
VPRO_CPUS=${VPRO_CPUS}
VPRO_INTERNAL_PORT=9090
VPRO_WEB_R_CONCURRENCY=2
VPRO_WEB_EXPORT_CONCURRENCY=3
VPRO_WEB_CACHE_MAX_MB=256
EOF
  ${SUDO} install -m 0600 -o "${DEPLOY_USER}" -g "${DEPLOY_USER}" "${TMP_ENV}" "${ENV_FILE}"
  rm -f "${TMP_ENV}"
  echo "Wrote ${ENV_FILE} (0600 ${DEPLOY_USER}:${DEPLOY_USER})."
else
  echo "Preserved existing ${ENV_FILE} (pass --overwrite-env to replace)."
fi
REMOTE_CONFIG
REMOTE_STAGE=""

vpro_infra_log "Droplet bootstrap complete on ${HOST}."
