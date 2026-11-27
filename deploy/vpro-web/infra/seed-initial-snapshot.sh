#!/usr/bin/env bash
set -euo pipefail

# Verify a local immutable VP08 snapshot bundle with vpro-snapshot (fail-closed)
# and seed or live-reload it onto a vpro-web DigitalOcean Droplet.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VPRO_INFRA_SCRIPT_NAME="seed-initial-snapshot.sh"
# shellcheck source=env.defaults.sh
source "${SCRIPT_DIR}/env.defaults.sh"

HOST=""
BUNDLE_DIR=""
DEPLOY_USER="${VPRO_DEPLOY_USER}"
SSH_KEY=""
DATA_ROOT="/srv/vpro/data"
DEPLOY_DIR="${VPRO_DEPLOY_DIR}"
VPRO_SNAPSHOT_BIN=""

usage() {
  cat <<'EOF'
Usage:
  seed-initial-snapshot.sh --host <ip> --bundle <local-bundle-dir> [options]

Verifies a local snapshot bundle fail-closed via `vpro-snapshot verify` and
transfers it to the target Droplet:
  - If `vpro-web` is already running: streams a tarball and runs `sync-snapshot.sh`
    for zero-downtime live reload.
  - If `vpro-web` is not running yet (cold start): stages into
    `<data-root>/releases/<snapshotId>` (0444/0555) and atomically flips
    `<data-root>/current -> releases/<snapshotId>` so Docker bind mounts are ready.

Options:
  --host <ip>                  Required Droplet public IPv4 or hostname
  --bundle <dir>               Required local verified snapshot bundle directory
  --user <deploy-user>         Droplet SSH user (default: deploy)
  --ssh-key <path>             Optional SSH private key path
  --data-root <dir>            Remote snapshot data root (default: /srv/vpro/data)
  --deploy-dir <dir>           Remote deploy directory (default: /srv/vpro/deploy)
  --vpro-snapshot-bin <path>   Path to local vpro-snapshot binary (default: lookup on PATH)
  -h, --help                   Show this help message
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --host)
      [ $# -ge 2 ] || vpro_infra_die "--host requires a value"
      HOST="$2"
      shift 2
      ;;
    --bundle)
      [ $# -ge 2 ] || vpro_infra_die "--bundle requires a directory path"
      BUNDLE_DIR="$2"
      shift 2
      ;;
    --user)
      [ $# -ge 2 ] || vpro_infra_die "--user requires a value"
      DEPLOY_USER="$2"
      shift 2
      ;;
    --ssh-key)
      [ $# -ge 2 ] || vpro_infra_die "--ssh-key requires a path"
      SSH_KEY="$2"
      shift 2
      ;;
    --data-root)
      [ $# -ge 2 ] || vpro_infra_die "--data-root requires a value"
      DATA_ROOT="$2"
      shift 2
      ;;
    --deploy-dir)
      [ $# -ge 2 ] || vpro_infra_die "--deploy-dir requires a value"
      DEPLOY_DIR="$2"
      shift 2
      ;;
    --vpro-snapshot-bin)
      [ $# -ge 2 ] || vpro_infra_die "--vpro-snapshot-bin requires a path"
      VPRO_SNAPSHOT_BIN="$2"
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

vpro_infra_require_cmd ssh scp tar jq

[ -n "${HOST}" ] || vpro_infra_die "--host is required"
[ -n "${BUNDLE_DIR}" ] || vpro_infra_die "--bundle is required"
[ -d "${BUNDLE_DIR}" ] || vpro_infra_die "bundle directory does not exist: ${BUNDLE_DIR}"
[ -f "${BUNDLE_DIR}/manifest.json" ] || vpro_infra_die "bundle is missing manifest.json: ${BUNDLE_DIR}/manifest.json"

if [ -n "${VPRO_SNAPSHOT_BIN}" ]; then
  [ -x "${VPRO_SNAPSHOT_BIN}" ] || vpro_infra_die "vpro-snapshot binary is not executable: ${VPRO_SNAPSHOT_BIN}"
else
  vpro_infra_require_cmd vpro-snapshot
  VPRO_SNAPSHOT_BIN="$(command -v vpro-snapshot)"
fi

vpro_infra_log "Verifying local snapshot bundle '${BUNDLE_DIR}' via ${VPRO_SNAPSHOT_BIN}..."
"${VPRO_SNAPSHOT_BIN}" verify --bundle "${BUNDLE_DIR}"

SNAPSHOT_ID="$(jq -er '.snapshotId' "${BUNDLE_DIR}/manifest.json")" \
  || vpro_infra_die "could not read snapshotId from ${BUNDLE_DIR}/manifest.json"
if ! printf '%s' "${SNAPSHOT_ID}" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$'; then
  vpro_infra_die "invalid snapshotId '${SNAPSHOT_ID}'"
fi

SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=15 -o StrictHostKeyChecking=accept-new)
if [ -n "${SSH_KEY}" ]; then
  [ -r "${SSH_KEY}" ] || vpro_infra_die "cannot read SSH key: ${SSH_KEY}"
  SSH_OPTS+=(-i "${SSH_KEY}")
fi

REMOTE="${DEPLOY_USER}@${HOST}"

vpro_infra_log "Checking whether vpro-web container is running on ${REMOTE}..."
VPRO_RUNNING="false"
if ssh "${SSH_OPTS[@]}" "${REMOTE}" \
  bash -s -- "${DEPLOY_DIR}" <<'CHECK_RUNNING'
set -euo pipefail
DEPLOY_DIR="$1"
[ -f "${DEPLOY_DIR}/docker-compose.yml" ] || exit 1
docker compose --project-directory "${DEPLOY_DIR}" -f "${DEPLOY_DIR}/docker-compose.yml" \
  ps --status running --services 2>/dev/null | grep -qx 'vpro-web'
CHECK_RUNNING
then
  VPRO_RUNNING="true"
fi

LOCAL_TARBALL="$(mktemp /tmp/vpro-seed-XXXXXX.tar.gz)"
cleanup_local() {
  rm -f "${LOCAL_TARBALL}" || true
}
trap cleanup_local EXIT

vpro_infra_log "Packaging verified snapshot '${SNAPSHOT_ID}'..."
tar -C "${BUNDLE_DIR}" -czf "${LOCAL_TARBALL}" .

REMOTE_TARBALL="/tmp/vpro-seed-${SNAPSHOT_ID}-$$.tar.gz"
vpro_infra_log "Uploading snapshot archive to ${REMOTE}:${REMOTE_TARBALL}..."
scp "${SSH_OPTS[@]}" "${LOCAL_TARBALL}" "${REMOTE}:${REMOTE_TARBALL}"

if [ "${VPRO_RUNNING}" = "true" ]; then
  vpro_infra_log "vpro-web is running on ${HOST}; activating verified snapshot '${SNAPSHOT_ID}' via sync-snapshot.sh..."
  ssh "${SSH_OPTS[@]}" "${REMOTE}" \
    bash -s -- "${REMOTE_TARBALL}" "${DEPLOY_DIR}" "${DATA_ROOT}" <<'REMOTE_LIVE_SYNC'
set -euo pipefail
REMOTE_TARBALL="$1"
DEPLOY_DIR="$2"
DATA_ROOT="$3"

cleanup() {
  rm -f "${REMOTE_TARBALL}" || true
}
trap cleanup EXIT

"${DEPLOY_DIR}/sync-snapshot.sh" "${REMOTE_TARBALL}" \
  --compose-dir "${DEPLOY_DIR}" \
  --data-root "${DATA_ROOT}"
REMOTE_LIVE_SYNC
  vpro_infra_log "Live snapshot reload complete for '${SNAPSHOT_ID}' on ${HOST}."
else
  vpro_infra_log "vpro-web is not running yet on ${HOST}; cold-seeding verified snapshot '${SNAPSHOT_ID}' into ${DATA_ROOT}..."
  ssh "${SSH_OPTS[@]}" "${REMOTE}" \
    bash -s -- "${REMOTE_TARBALL}" "${DATA_ROOT}" "${SNAPSHOT_ID}" <<'REMOTE_COLD_SEED'
set -euo pipefail
REMOTE_TARBALL="$1"
DATA_ROOT="$2"
SNAPSHOT_ID="$3"
RELEASES_DIR="${DATA_ROOT}/releases"
CURRENT_LINK="${DATA_ROOT}/current"
TARGET_DIR="${RELEASES_DIR}/${SNAPSHOT_ID}"

mkdir -p "${RELEASES_DIR}"
STAGE_DIR="$(mktemp -d "${RELEASES_DIR}/.seed-${SNAPSHOT_ID}-XXXXXX")"
TMP_LINK=""

cleanup() {
  rm -f "${REMOTE_TARBALL}" || true
  if [ -n "${TMP_LINK}" ] && [ -L "${TMP_LINK}" ]; then
    rm -f "${TMP_LINK}" || true
  fi
  if [ -n "${STAGE_DIR}" ] && [ -d "${STAGE_DIR}" ]; then
    chmod -R u+w "${STAGE_DIR}" 2>/dev/null || true
    rm -rf "${STAGE_DIR}" || true
  fi
}
trap cleanup EXIT

tar -xzf "${REMOTE_TARBALL}" -C "${STAGE_DIR}"
[ -f "${STAGE_DIR}/manifest.json" ] || { echo "ERROR: extracted bundle missing manifest.json" >&2; exit 1; }

find "${STAGE_DIR}" -type f -exec chmod 0444 {} +
find "${STAGE_DIR}" -type d -exec chmod 0555 {} +

if [ -e "${TARGET_DIR}" ]; then
  chmod -R u+w "${TARGET_DIR}" 2>/dev/null || true
  rm -rf "${TARGET_DIR}"
fi

mv "${STAGE_DIR}" "${TARGET_DIR}"
STAGE_DIR=""

TMP_LINK="${DATA_ROOT}/.current.seed.$$"
rm -f "${TMP_LINK}"
ln -s "releases/${SNAPSHOT_ID}" "${TMP_LINK}"
mv -Tf "${TMP_LINK}" "${CURRENT_LINK}"
TMP_LINK=""

echo "Cold-seeded ${CURRENT_LINK} -> releases/${SNAPSHOT_ID} (0444/0555)."
REMOTE_COLD_SEED
  vpro_infra_log "Cold-start snapshot '${SNAPSHOT_ID}' seeded at ${DATA_ROOT}/current on ${HOST}."
fi
