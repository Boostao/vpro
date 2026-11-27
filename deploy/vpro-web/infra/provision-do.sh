#!/usr/bin/env bash
set -euo pipefail

# Idempotently provision DigitalOcean Projects (vpro-devl & vpro-prod),
# target Droplet, project assignment, and Cloud Firewall for vpro-web.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VPRO_INFRA_SCRIPT_NAME="provision-do.sh"
# shellcheck source=env.defaults.sh
source "${SCRIPT_DIR}/env.defaults.sh"

ENV_ARG="devl"
OVERRIDE_CONTEXT=""
OVERRIDE_REGION=""
OVERRIDE_SIZE=""
OVERRIDE_VPC_UUID=""
OVERRIDE_SSH_KEYS=""
SSH_CIDR="0.0.0.0/0,::/0"
PROJECTS_ONLY=0
EMIT_JSON=0

usage() {
  cat <<'EOF'
Usage:
  provision-do.sh [options]

Idempotently ensures both DigitalOcean Projects (vpro-devl and vpro-prod) exist
in the configured doctl context, then provisions the target Droplet, assigns it
to its DO Project, and attaches a minimal-exposure Cloud Firewall.

Options:
  --env <devl|prod>     Target environment (default: devl; accepts 'dev' alias)
  --context <ctx>       doctl authentication context (default: vpro)
  --region <slug>       DigitalOcean region slug (default: tor1)
  --size <slug>         Droplet size slug (default: s-2vcpu-4gb)
  --vpc-uuid <uuid>     DigitalOcean VPC UUID (default: default-tor1 VPC)
  --ssh-keys <ids>      Comma-separated DO SSH key IDs or fingerprints
  --ssh-cidr <cidrs>    Comma-separated allowed SSH CIDRs (default: 0.0.0.0/0,::/0)
  --projects-only       Only ensure DO projects exist; skip Droplet and firewall
  --json                Emit final JSON summary on stdout (progress logs go to stderr)
  -h, --help            Show this help message
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
    --projects-only)
      PROJECTS_ONLY=1
      shift
      ;;
    --json)
      EMIT_JSON=1
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

vpro_infra_require_cmd doctl jq

resolve_vpro_env_defaults "${ENV_ARG}"
[ -n "${OVERRIDE_CONTEXT}" ] && DO_CONTEXT="${OVERRIDE_CONTEXT}"
[ -n "${OVERRIDE_REGION}" ] && DO_REGION="${OVERRIDE_REGION}"
[ -n "${OVERRIDE_SIZE}" ] && DROPLET_SIZE="${OVERRIDE_SIZE}"
[ -n "${OVERRIDE_VPC_UUID}" ] && DO_VPC_UUID="${OVERRIDE_VPC_UUID}"
[ -n "${OVERRIDE_SSH_KEYS}" ] && DO_SSH_KEY_IDS="${OVERRIDE_SSH_KEYS}"

doctl_cmd() {
  doctl --context "${DO_CONTEXT}" "$@"
}

ensure_project() {
  local name="$1"
  local environment="$2"
  local description="$3"
  local projects_json="$4"
  local project_id

  project_id="$(printf '%s' "${projects_json}" | jq -r --arg name "${name}" \
    '(. // []) | map(select(.name == $name)) | .[0].id // empty')"

  if [ -n "${project_id}" ]; then
    vpro_infra_log "DO Project '${name}' already exists (${project_id})."
    printf '%s' "${project_id}"
    return 0
  fi

  vpro_infra_log "Creating DO Project '${name}' (${environment})..."
  local created_json
  created_json="$(doctl_cmd projects create \
    --name "${name}" \
    --purpose "Web Application" \
    --environment "${environment}" \
    --description "${description}" \
    -o json)"
  project_id="$(printf '%s' "${created_json}" | jq -r '(if type == "array" then .[0] else . end) | .id // empty')"
  [ -n "${project_id}" ] || vpro_infra_die "failed to extract project ID after creating '${name}'"
  vpro_infra_log "Created DO Project '${name}' (${project_id})."
  printf '%s' "${project_id}"
}

vpro_infra_log "Ensuring DigitalOcean projects in context '${DO_CONTEXT}'..."
PROJECTS_JSON="$(doctl_cmd projects list -o json)"

DEVL_PROJECT_ID="$(ensure_project \
  "vpro-devl" \
  "Development" \
  "VPro 2.0 read-only BECMaster web server (devl)" \
  "${PROJECTS_JSON}")"

PROD_PROJECT_ID="$(ensure_project \
  "vpro-prod" \
  "Production" \
  "VPro 2.0 read-only BECMaster web server (prod)" \
  "${PROJECTS_JSON}")"

if [ "${TARGET_ENV}" = "prod" ]; then
  TARGET_PROJECT_ID="${PROD_PROJECT_ID}"
else
  TARGET_PROJECT_ID="${DEVL_PROJECT_ID}"
fi

DROPLET_ID=""
DROPLET_IP=""
FIREWALL_ID=""

if [ "${PROJECTS_ONLY}" -eq 0 ]; then
  vpro_infra_log "Checking Droplet '${DROPLET_NAME}'..."
  DROPLETS_JSON="$(doctl_cmd compute droplet list -o json)"
  DROPLET_OBJ="$(printf '%s' "${DROPLETS_JSON}" | jq -c --arg name "${DROPLET_NAME}" \
    '(. // []) | map(select(.name == $name)) | .[0] // empty')"

  if [ -n "${DROPLET_OBJ}" ]; then
    DROPLET_ID="$(printf '%s' "${DROPLET_OBJ}" | jq -r '.id // empty')"
    DROPLET_IP="$(printf '%s' "${DROPLET_OBJ}" | jq -r '(.networks.v4 // []) | map(select(.type == "public")) | .[0].ip_address // empty')"
    vpro_infra_log "Droplet '${DROPLET_NAME}' already exists (id=${DROPLET_ID}, ip=${DROPLET_IP})."
  else
    vpro_infra_log "Creating Droplet '${DROPLET_NAME}' (${DROPLET_SIZE} in ${DO_REGION}, VPC ${DO_VPC_UUID})..."
    CREATED_DROPLET_JSON="$(doctl_cmd compute droplet create "${DROPLET_NAME}" \
      --region "${DO_REGION}" \
      --image "${DO_IMAGE}" \
      --size "${DROPLET_SIZE}" \
      --vpc-uuid "${DO_VPC_UUID}" \
      --ssh-keys "${DO_SSH_KEY_IDS}" \
      --tag-names "${DROPLET_TAGS}" \
      --project-id "${TARGET_PROJECT_ID}" \
      --enable-monitoring \
      --wait \
      -o json)"
    DROPLET_OBJ="$(printf '%s' "${CREATED_DROPLET_JSON}" | jq -c '(if type == "array" then .[0] else . end)')"
    DROPLET_ID="$(printf '%s' "${DROPLET_OBJ}" | jq -r '.id // empty')"
    DROPLET_IP="$(printf '%s' "${DROPLET_OBJ}" | jq -r '(.networks.v4 // []) | map(select(.type == "public")) | .[0].ip_address // empty')"
    [ -n "${DROPLET_ID}" ] || vpro_infra_die "failed to extract Droplet ID after create"
    if [ -z "${DROPLET_IP}" ]; then
      DROPLET_IP="$(doctl_cmd compute droplet get "${DROPLET_ID}" -o json \
        | jq -r '(if type == "array" then .[0] else . end) | (.networks.v4 // []) | map(select(.type == "public")) | .[0].ip_address // empty')"
    fi
    vpro_infra_log "Created Droplet '${DROPLET_NAME}' (id=${DROPLET_ID}, ip=${DROPLET_IP})."
  fi

  [ -n "${DROPLET_ID}" ] || vpro_infra_die "missing Droplet ID for '${DROPLET_NAME}'"
  [ -n "${DROPLET_IP}" ] || vpro_infra_die "missing public IPv4 address for Droplet '${DROPLET_NAME}' (id=${DROPLET_ID})"

  vpro_infra_log "Ensuring Droplet ${DROPLET_ID} is assigned to project '${DO_PROJECT_NAME}' (${TARGET_PROJECT_ID})..."
  doctl_cmd projects resources assign "${TARGET_PROJECT_ID}" \
    --resource="do:droplet:${DROPLET_ID}" >/dev/null

  # Build inbound rules: SSH (customizable CIDR) + HTTP 80 + HTTPS 443 TCP/UDP only
  SSH_INBOUND_RULES=""
  IFS=',' read -r -a ssh_cidr_list <<< "${SSH_CIDR}"
  for raw_cidr in "${ssh_cidr_list[@]}"; do
    cidr="$(printf '%s' "${raw_cidr}" | tr -d '[:space:]')"
    [ -n "${cidr}" ] || continue
    if [ -n "${SSH_INBOUND_RULES}" ]; then
      SSH_INBOUND_RULES="${SSH_INBOUND_RULES} "
    fi
    SSH_INBOUND_RULES="${SSH_INBOUND_RULES}protocol:tcp,ports:22,address:${cidr}"
  done
  [ -n "${SSH_INBOUND_RULES}" ] || vpro_infra_die "--ssh-cidr yielded no valid CIDR entries"

  INBOUND_RULES="${SSH_INBOUND_RULES} protocol:tcp,ports:80,address:0.0.0.0/0 protocol:tcp,ports:80,address:::/0 protocol:tcp,ports:443,address:0.0.0.0/0 protocol:tcp,ports:443,address:::/0 protocol:udp,ports:443,address:0.0.0.0/0 protocol:udp,ports:443,address:::/0"
  OUTBOUND_RULES="protocol:tcp,ports:0,address:0.0.0.0/0 protocol:tcp,ports:0,address:::/0 protocol:udp,ports:0,address:0.0.0.0/0 protocol:udp,ports:0,address:::/0 protocol:icmp,address:0.0.0.0/0 protocol:icmp,address:::/0"

  vpro_infra_log "Checking Cloud Firewall '${FIREWALL_NAME}'..."
  FIREWALLS_JSON="$(doctl_cmd compute firewall list -o json)"
  FIREWALL_OBJ="$(printf '%s' "${FIREWALLS_JSON}" | jq -c --arg name "${FIREWALL_NAME}" \
    '(. // []) | map(select(.name == $name)) | .[0] // empty')"

  if [ -z "${FIREWALL_OBJ}" ]; then
    vpro_infra_log "Creating Cloud Firewall '${FIREWALL_NAME}' and attaching Droplet ${DROPLET_ID}..."
    CREATED_FW_JSON="$(doctl_cmd compute firewall create \
      --name "${FIREWALL_NAME}" \
      --inbound-rules "${INBOUND_RULES}" \
      --outbound-rules "${OUTBOUND_RULES}" \
      --droplet-ids "${DROPLET_ID}" \
      -o json)"
    FIREWALL_ID="$(printf '%s' "${CREATED_FW_JSON}" | jq -r '(if type == "array" then .[0] else . end) | .id // empty')"
    [ -n "${FIREWALL_ID}" ] || vpro_infra_die "failed to extract firewall ID after create"
    vpro_infra_log "Created Cloud Firewall '${FIREWALL_NAME}' (${FIREWALL_ID})."
  else
    FIREWALL_ID="$(printf '%s' "${FIREWALL_OBJ}" | jq -r '.id // empty')"
    [ -n "${FIREWALL_ID}" ] || vpro_infra_die "failed to read firewall ID for '${FIREWALL_NAME}'"
    ATTACHED="$(printf '%s' "${FIREWALL_OBJ}" | jq -r --arg id "${DROPLET_ID}" \
      '((.droplet_ids // []) | map(tostring) | index($id)) != null')"
    if [ "${ATTACHED}" = "true" ]; then
      vpro_infra_log "Cloud Firewall '${FIREWALL_NAME}' (${FIREWALL_ID}) already protects Droplet ${DROPLET_ID}."
    else
      vpro_infra_log "Attaching Droplet ${DROPLET_ID} to Cloud Firewall '${FIREWALL_NAME}' (${FIREWALL_ID})..."
      doctl_cmd compute firewall add-droplets "${FIREWALL_ID}" --droplet-ids "${DROPLET_ID}" >/dev/null
    fi
  fi
fi

if [ "${EMIT_JSON}" -eq 1 ]; then
  jq -n \
    --arg target_env "${TARGET_ENV}" \
    --arg devl_project_id "${DEVL_PROJECT_ID}" \
    --arg prod_project_id "${PROD_PROJECT_ID}" \
    --arg target_project_id "${TARGET_PROJECT_ID}" \
    --arg droplet_id "${DROPLET_ID}" \
    --arg droplet_ip "${DROPLET_IP}" \
    --arg firewall_id "${FIREWALL_ID}" \
    '{
      TARGET_ENV: $target_env,
      DEVL_PROJECT_ID: $devl_project_id,
      PROD_PROJECT_ID: $prod_project_id,
      TARGET_PROJECT_ID: $target_project_id,
      DROPLET_ID: $droplet_id,
      DROPLET_IP: $droplet_ip,
      FIREWALL_ID: $firewall_id
    }'
else
  cat <<EOF
TARGET_ENV=${TARGET_ENV}
DEVL_PROJECT_ID=${DEVL_PROJECT_ID}
PROD_PROJECT_ID=${PROD_PROJECT_ID}
TARGET_PROJECT_ID=${TARGET_PROJECT_ID}
DROPLET_ID=${DROPLET_ID}
DROPLET_IP=${DROPLET_IP}
FIREWALL_ID=${FIREWALL_ID}
EOF
fi
