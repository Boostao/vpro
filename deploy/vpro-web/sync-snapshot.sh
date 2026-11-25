#!/usr/bin/env bash
set -euo pipefail

# Atomically stage, verify, activate, reload, and prune immutable VPro 2.0 web snapshots.
#
# Usage:
#   ./sync-snapshot.sh <staged-bundle-dir-or-tarball> [options]
#
# Options:
#   --snapshot-id <id>     Override snapshotId from manifest.json
#   --data-root <dir>      Snapshot root directory (default: $VPRO_DATA_ROOT or /srv/vpro/data)
#   --compose-dir <dir>    Directory containing docker-compose.yml (default: script directory)
#   --keep <N>             Number of recent releases to retain (default: 3)
#   --force                Replace an existing non-active release directory with the same snapshotId
#   -h, --help             Show usage

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_DIR="${VPRO_COMPOSE_DIR:-${SCRIPT_DIR}}"
DATA_ROOT="${VPRO_DATA_ROOT:-}"
INTERNAL_PORT="${VPRO_INTERNAL_PORT:-}"
KEEP_RELEASES=3
OVERRIDE_SNAPSHOT_ID=""
FORCE=0
SOURCE_PATH=""

usage() {
  cat <<'EOF'
Usage:
  sync-snapshot.sh <staged-bundle-dir-or-tarball> [options]

Options:
  --snapshot-id <id>     Override snapshotId read from manifest.json
  --data-root <dir>      Snapshot root directory (default: VPRO_DATA_ROOT or /srv/vpro/data)
  --compose-dir <dir>    Directory containing docker-compose.yml (default: script directory)
  --keep <N>             Number of most recent releases to retain (default: 3)
  --force                Replace an existing non-active release with the same snapshotId
  -h, --help             Show this help message
EOF
}

die() {
  printf 'sync-snapshot: ERROR: %s\n' "$*" >&2
  exit 1
}

log() {
  printf 'sync-snapshot: %s\n' "$*"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --snapshot-id)
      [ $# -ge 2 ] || die "--snapshot-id requires a value"
      OVERRIDE_SNAPSHOT_ID="$2"
      shift 2
      ;;
    --data-root)
      [ $# -ge 2 ] || die "--data-root requires a value"
      DATA_ROOT="$2"
      shift 2
      ;;
    --compose-dir)
      [ $# -ge 2 ] || die "--compose-dir requires a value"
      COMPOSE_DIR="$2"
      shift 2
      ;;
    --keep)
      [ $# -ge 2 ] || die "--keep requires a positive integer"
      KEEP_RELEASES="$2"
      shift 2
      ;;
    --force)
      FORCE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      die "unknown option: $1"
      ;;
    *)
      if [ -n "${SOURCE_PATH}" ]; then
        die "unexpected extra argument: $1"
      fi
      SOURCE_PATH="$1"
      shift
      ;;
  esac
done

[ -n "${SOURCE_PATH}" ] || { usage >&2; die "missing required <staged-bundle-dir-or-tarball> argument"; }
[ -e "${SOURCE_PATH}" ] || die "source path does not exist: ${SOURCE_PATH}"

case "${KEEP_RELEASES}" in
  ''|*[!0-9]*) die "--keep must be a positive integer (got '${KEEP_RELEASES}')" ;;
esac
[ "${KEEP_RELEASES}" -ge 1 ] || die "--keep must be >= 1"

# Load defaults from compose .env without clobbering explicit CLI/environment overrides
ENV_FILE="${COMPOSE_DIR}/.env"
COMPOSE_DATA_ROOT=""
if [ -f "${ENV_FILE}" ]; then
  while IFS='=' read -r raw_key raw_val; do
    key="$(printf '%s' "${raw_key}" | tr -d '[:space:]')"
    case "${key}" in
      ''|'#'*) continue ;;
    esac
    val="${raw_val%$'\r'}"
    val="${val#\"}"
    val="${val%\"}"
    val="${val#\'}"
    val="${val%\'}"
    if [ "${key}" = "VPRO_DATA_ROOT" ]; then
      COMPOSE_DATA_ROOT="${val}"
      if [ -z "${DATA_ROOT}" ]; then
        DATA_ROOT="${val}"
      fi
    elif [ "${key}" = "VPRO_INTERNAL_PORT" ] && [ -z "${INTERNAL_PORT}" ]; then
      INTERNAL_PORT="${val}"
    fi
  done < "${ENV_FILE}"
fi

COMPOSE_DATA_ROOT="${COMPOSE_DATA_ROOT:-/srv/vpro/data}"
DATA_ROOT="${DATA_ROOT:-/srv/vpro/data}"
INTERNAL_PORT="${INTERNAL_PORT:-9090}"
RELEASES_DIR="${DATA_ROOT}/releases"
CURRENT_LINK="${DATA_ROOT}/current"

mkdir -p "${RELEASES_DIR}"

STAGING_DIR="$(mktemp -d "${RELEASES_DIR}/.staging-XXXXXX")"
TMP_LINK=""

cleanup() {
  if [ -n "${TMP_LINK}" ] && [ -L "${TMP_LINK}" ]; then
    rm -f "${TMP_LINK}" || true
  fi
  if [ -n "${STAGING_DIR}" ] && [ -d "${STAGING_DIR}" ]; then
    chmod -R u+w "${STAGING_DIR}" 2>/dev/null || true
    rm -rf "${STAGING_DIR}" || true
  fi
}
trap cleanup EXIT

extract_manifest_snapshot_id() {
  local manifest_file="$1"
  if command -v python3 >/dev/null 2>&1; then
    python3 - "${manifest_file}" <<'PY'
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as fh:
    data = json.load(fh)
sid = str(data.get("snapshotId", "")).strip()
if not sid:
    raise SystemExit(1)
print(sid)
PY
  elif command -v jq >/dev/null 2>&1; then
    jq -er '.snapshotId' "${manifest_file}"
  else
    sed -n 's/.*"snapshotId"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "${manifest_file}" | head -n 1
  fi
}

# Stage snapshot into ${STAGING_DIR}/bundle
BUNDLE_STAGE="${STAGING_DIR}/bundle"
mkdir -p "${BUNDLE_STAGE}"

if [ -d "${SOURCE_PATH}" ]; then
  log "Staging snapshot directory ${SOURCE_PATH}..."
  cp -a "${SOURCE_PATH}/." "${BUNDLE_STAGE}/"
elif [ -f "${SOURCE_PATH}" ]; then
  log "Extracting snapshot tarball ${SOURCE_PATH}..."
  EXTRACT_DIR="${STAGING_DIR}/extract"
  mkdir -p "${EXTRACT_DIR}"
  case "${SOURCE_PATH}" in
    *.tar.gz|*.tgz)
      tar_list_flags=(-tzf)
      tar_extract_flags=(-xzf)
      ;;
    *.tar)
      tar_list_flags=(-tf)
      tar_extract_flags=(-xf)
      ;;
    *)
      die "unsupported archive format (expected directory, .tar.gz, .tgz, or .tar): ${SOURCE_PATH}"
      ;;
  esac

  # Reject archives with absolute paths or '..' path traversal components before extraction
  if tar "${tar_list_flags[@]}" "${SOURCE_PATH}" | grep -Eq '(^/|(^|/)\.\.(/|$))'; then
    die "archive contains unsafe absolute or parent-traversal path entries: ${SOURCE_PATH}"
  fi
  tar "${tar_extract_flags[@]}" "${SOURCE_PATH}" -C "${EXTRACT_DIR}"

  if [ -f "${EXTRACT_DIR}/manifest.json" ]; then
    rmdir "${BUNDLE_STAGE}"
    mv "${EXTRACT_DIR}" "${BUNDLE_STAGE}"
  else
    mapfile -t top_entries < <(find "${EXTRACT_DIR}" -mindepth 1 -maxdepth 1 -type d)
    if [ "${#top_entries[@]}" -eq 1 ] && [ -f "${top_entries[0]}/manifest.json" ]; then
      rmdir "${BUNDLE_STAGE}"
      mv "${top_entries[0]}" "${BUNDLE_STAGE}"
    else
      die "extracted archive does not contain manifest.json at root or single top-level directory"
    fi
  fi
else
  die "source path is neither a regular file nor a directory: ${SOURCE_PATH}"
fi

MANIFEST_PATH="${BUNDLE_STAGE}/manifest.json"
[ -f "${MANIFEST_PATH}" ] || die "staged bundle is missing manifest.json"

SNAPSHOT_ID="${OVERRIDE_SNAPSHOT_ID}"
if [ -z "${SNAPSHOT_ID}" ]; then
  SNAPSHOT_ID="$(extract_manifest_snapshot_id "${MANIFEST_PATH}")" || die "could not read snapshotId from manifest.json"
fi

if ! printf '%s' "${SNAPSHOT_ID}" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$'; then
  die "invalid snapshotId '${SNAPSHOT_ID}' (must match ^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$)"
fi

TARGET_RELEASE_DIR="${RELEASES_DIR}/${SNAPSHOT_ID}"
PREVIOUS_LINK_TARGET=""
ACTIVE_RELEASE_NAME=""
if [ -L "${CURRENT_LINK}" ]; then
  PREVIOUS_LINK_TARGET="$(readlink "${CURRENT_LINK}")"
  ACTIVE_RELEASE_NAME="$(basename "${PREVIOUS_LINK_TARGET}")"
fi

if [ -e "${TARGET_RELEASE_DIR}" ]; then
  if [ "${SNAPSHOT_ID}" = "${ACTIVE_RELEASE_NAME}" ]; then
    die "target release '${SNAPSHOT_ID}' is already the active snapshot; publish a new snapshotId instead"
  fi
  if [ "${FORCE}" -ne 1 ]; then
    die "release directory already exists: ${TARGET_RELEASE_DIR} (pass --force to replace)"
  fi
  log "Removing existing inactive release ${TARGET_RELEASE_DIR} (--force)..."
  chmod -R u+w "${TARGET_RELEASE_DIR}" 2>/dev/null || true
  rm -rf "${TARGET_RELEASE_DIR}"
fi

# Enforce read-only immutable permissions matching vpro-snapshot before verification
find "${BUNDLE_STAGE}" -type f -exec chmod 0444 {} +
find "${BUNDLE_STAGE}" -type d -exec chmod 0555 {} +

mv "${BUNDLE_STAGE}" "${TARGET_RELEASE_DIR}"

# Clean up staging parent early now that TARGET_RELEASE_DIR is in place
chmod -R u+w "${STAGING_DIR}" 2>/dev/null || true
rm -rf "${STAGING_DIR}"
STAGING_DIR=""

COMPOSE_CMD=(docker compose --project-directory "${COMPOSE_DIR}" -f "${COMPOSE_DIR}/docker-compose.yml")
CONTAINER_BUNDLE_PATH="/srv/vpro/data/releases/${SNAPSHOT_ID}"

vpro_web_running() {
  "${COMPOSE_CMD[@]}" ps --status running --services 2>/dev/null | grep -qx 'vpro-web'
}

log "Verifying snapshot bundle '${SNAPSHOT_ID}' with vpro-snapshot verify..."
verify_ok=0
if vpro_web_running && [ "${DATA_ROOT}" = "${COMPOSE_DATA_ROOT}" ]; then
  if "${COMPOSE_CMD[@]}" exec -T vpro-web /usr/local/bin/vpro-snapshot verify --bundle "${CONTAINER_BUNDLE_PATH}"; then
    verify_ok=1
  fi
else
  if "${COMPOSE_CMD[@]}" run --rm --no-deps --entrypoint /usr/local/bin/vpro-snapshot \
      -v "${TARGET_RELEASE_DIR}:/verify-bundle:ro" \
      vpro-web verify --bundle /verify-bundle; then
    verify_ok=1
  fi
fi

if [ "${verify_ok}" -ne 1 ]; then
  log "Verification FAILED for '${SNAPSHOT_ID}'; removing staged release without changing current symlink."
  chmod -R u+w "${TARGET_RELEASE_DIR}" 2>/dev/null || true
  rm -rf "${TARGET_RELEASE_DIR}"
  exit 1
fi

# Atomically flip /srv/vpro/data/current -> releases/<snapshotId> (relative symlink works on host + container)
flip_symlink() {
  local rel_target="$1"
  TMP_LINK="${DATA_ROOT}/.current.next.$$"
  rm -f "${TMP_LINK}"
  ln -s "${rel_target}" "${TMP_LINK}"
  mv -Tf "${TMP_LINK}" "${CURRENT_LINK}"
  TMP_LINK=""
}

check_readyz() {
  if curl -fsS --max-time 10 "http://127.0.0.1:${INTERNAL_PORT}/readyz" >/dev/null 2>&1; then
    return 0
  fi
  if vpro_web_running; then
    "${COMPOSE_CMD[@]}" exec -T vpro-web curl -fsS --max-time 10 "http://127.0.0.1:8080/readyz" >/dev/null 2>&1
    return $?
  fi
  return 1
}

log "Atomically switching ${CURRENT_LINK} -> releases/${SNAPSHOT_ID}..."
flip_symlink "releases/${SNAPSHOT_ID}"

if vpro_web_running; then
  log "Triggering live snapshot reload on http://127.0.0.1:${INTERNAL_PORT}/internal/reload..."
  reload_ok=0
  if curl -fsS --max-time 30 -X POST "http://127.0.0.1:${INTERNAL_PORT}/internal/reload"; then
    printf '\n'
    # Poll /readyz briefly to confirm the reloaded pool is serving cleanly
    for _attempt in 1 2 3 4 5 6 7 8 9 10; do
      if check_readyz; then
        reload_ok=1
        break
      fi
      sleep 1
    done
  fi

  if [ "${reload_ok}" -ne 1 ]; then
    log "Reload or /readyz verification FAILED for '${SNAPSHOT_ID}'!"
    if [ -n "${PREVIOUS_LINK_TARGET}" ]; then
      log "Rolling back ${CURRENT_LINK} -> ${PREVIOUS_LINK_TARGET}..."
      flip_symlink "${PREVIOUS_LINK_TARGET}"
      curl -fsS --max-time 30 -X POST "http://127.0.0.1:${INTERNAL_PORT}/internal/reload" || true
      printf '\n'
    fi
    exit 1
  fi
  log "Live reload succeeded and /readyz is healthy."
else
  log "vpro-web container is not running yet; symlink activated for next 'docker compose up -d'."
fi

# Prune releases older than the last ${KEEP_RELEASES} while always retaining the active release
CURRENT_ACTIVE_NAME="$(basename "$(readlink "${CURRENT_LINK}")")"
mapfile -t release_dirs < <(
  find "${RELEASES_DIR}" -mindepth 1 -maxdepth 1 -type d ! -name '.*' -printf '%T@ %f\n' \
    | sort -rn \
    | awk '{print $2}'
)

kept=0
for rel_name in "${release_dirs[@]}"; do
  if [ "${rel_name}" = "${CURRENT_ACTIVE_NAME}" ]; then
    kept=$((kept + 1))
    continue
  fi
  if [ "${kept}" -lt "${KEEP_RELEASES}" ]; then
    kept=$((kept + 1))
    continue
  fi
  old_path="${RELEASES_DIR}/${rel_name}"
  log "Pruning old snapshot release: ${old_path}"
  chmod -R u+w "${old_path}" 2>/dev/null || true
  rm -rf "${old_path}"
done

log "Snapshot '${SNAPSHOT_ID}' is active at ${CURRENT_LINK} (retaining last ${KEEP_RELEASES} releases)."
