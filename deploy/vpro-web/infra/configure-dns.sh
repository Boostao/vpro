#!/usr/bin/env bash
set -euo pipefail

# Idempotently configure Cloudflare DNS A record for vpro-web (DNS-only by default
# so Caddy performs automatic Let's Encrypt ACME + HTTP/3 + PMTiles Range cleanly).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VPRO_INFRA_SCRIPT_NAME="configure-dns.sh"
# shellcheck source=env.defaults.sh
source "${SCRIPT_DIR}/env.defaults.sh"

ENV_ARG="devl"
IP_ADDR=""
OVERRIDE_ZONE=""
OVERRIDE_DOMAIN=""
PROXIED="false"
TTL=300

usage() {
  cat <<'EOF'
Usage:
  configure-dns.sh --ip <ipv4> [options]

Idempotently creates or updates the Cloudflare DNS A record for vpro-web.

Options:
  --env <devl|prod>     Target environment (default: devl; accepts 'dev' alias)
  --ip <ipv4>           Required Droplet public IPv4 address
  --zone <zone>         Cloudflare zone name or ID (default: boostao.ca)
  --domain <fqdn>       Override FQDN (default: vpro.devl.boostao.ca or vpro.boostao.ca)
  --proxied <true|false> Cloudflare proxy mode (default: false for Caddy TLS + H3)
  --ttl <int>           DNS record TTL in seconds (default: 300; 1 = Auto)
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
    --ip)
      [ $# -ge 2 ] || vpro_infra_die "--ip requires an IPv4 address"
      IP_ADDR="$2"
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
    -h|--help)
      usage
      exit 0
      ;;
    *)
      vpro_infra_die "unknown option: $1"
      ;;
  esac
done

vpro_infra_require_cmd cf jq

resolve_vpro_env_defaults "${ENV_ARG}"
[ -n "${OVERRIDE_ZONE}" ] && CF_ZONE="${OVERRIDE_ZONE}"
[ -n "${OVERRIDE_DOMAIN}" ] && VPRO_DOMAIN="${OVERRIDE_DOMAIN}"

[ -n "${IP_ADDR}" ] || vpro_infra_die "--ip is required"
if ! printf '%s' "${IP_ADDR}" | grep -Eq '^([0-9]{1,3}\.){3}[0-9]{1,3}$'; then
  vpro_infra_die "invalid IPv4 address: ${IP_ADDR}"
fi

case "${PROXIED}" in
  true|false) ;;
  *) vpro_infra_die "--proxied must be 'true' or 'false' (got '${PROXIED}')" ;;
esac

case "${TTL}" in
  ''|*[!0-9]*) vpro_infra_die "--ttl must be a positive integer (got '${TTL}')" ;;
esac
if [ "${TTL}" -ne 1 ] && [ "${TTL}" -lt 60 ]; then
  vpro_infra_die "--ttl must be 1 (Auto) or >= 60 (got '${TTL}')"
fi

PAYLOAD="$(jq -cn \
  --arg type "A" \
  --arg name "${VPRO_DOMAIN}" \
  --arg content "${IP_ADDR}" \
  --argjson proxied "${PROXIED}" \
  --argjson ttl "${TTL}" \
  --arg comment "Managed by vpro deploy/vpro-web/infra/configure-dns.sh (${TARGET_ENV})" \
  '{type: $type, name: $name, content: $content, proxied: $proxied, ttl: $ttl, comment: $comment}')"

vpro_infra_log "Checking Cloudflare DNS A record '${VPRO_DOMAIN}' in zone '${CF_ZONE}'..."
RECORDS_JSON="$(cf dns records list --zone "${CF_ZONE}" --name "${VPRO_DOMAIN}" --type A -q 2>/dev/null)"
EXISTING_RECORD="$(printf '%s' "${RECORDS_JSON}" | jq -c --arg name "${VPRO_DOMAIN}" \
  '(. // []) | map(select(.type == "A" and ((.name | ascii_downcase) == ($name | ascii_downcase)))) | .[0] // empty')"

if [ -z "${EXISTING_RECORD}" ]; then
  vpro_infra_log "Creating A record ${VPRO_DOMAIN} -> ${IP_ADDR} (proxied=${PROXIED}, ttl=${TTL})..."
  cf dns records create --zone "${CF_ZONE}" --body "${PAYLOAD}" -q >/dev/null
  vpro_infra_log "Created A record ${VPRO_DOMAIN} -> ${IP_ADDR}."
  exit 0
fi

RECORD_ID="$(printf '%s' "${EXISTING_RECORD}" | jq -r '.id // empty')"
[ -n "${RECORD_ID}" ] || vpro_infra_die "existing DNS record for '${VPRO_DOMAIN}' is missing id"

NEEDS_UPDATE="$(printf '%s' "${EXISTING_RECORD}" | jq -r \
  --arg ip "${IP_ADDR}" \
  --argjson proxied "${PROXIED}" \
  --argjson ttl "${TTL}" \
  '(.content != $ip) or (.proxied != $proxied) or (.ttl != $ttl)')"

if [ "${NEEDS_UPDATE}" = "true" ]; then
  vpro_infra_log "Updating A record ${VPRO_DOMAIN} (${RECORD_ID}) -> ${IP_ADDR} (proxied=${PROXIED}, ttl=${TTL})..."
  cf dns records update "${RECORD_ID}" --zone "${CF_ZONE}" --body "${PAYLOAD}" -q >/dev/null
  vpro_infra_log "Updated A record ${VPRO_DOMAIN} -> ${IP_ADDR}."
else
  vpro_infra_log "A record ${VPRO_DOMAIN} -> ${IP_ADDR} (proxied=${PROXIED}, ttl=${TTL}) is already up to date."
fi
