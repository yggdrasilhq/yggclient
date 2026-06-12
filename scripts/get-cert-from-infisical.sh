#!/bin/bash
#
# deploy-certs.sh - The Keeper's Ritual (Final, Corrected Form)
# Fetches the TRUE certificate content from Infisical using the --plain flag.
#

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

load_local_env() {
  local explicit="${YGG_CERTS_ENV_FILE:-}"
  local candidates=(
    "$explicit"
    "$SCRIPT_DIR/../config/certs.local.env"
    "$SCRIPT_DIR/../scripts/lego/lego.local.env"
  )
  local candidate
  for candidate in "${candidates[@]}"; do
    [[ -n "$candidate" && -f "$candidate" ]] || continue
    # shellcheck disable=SC1090
    source "$candidate"
    export YGG_CERTS_ENV_FILE="$candidate"
    return 0
  done
  return 1
}

load_local_env || true

INFISICAL_PROJECT_ID="${INFISICAL_INFRA_PROJECT_ID:-${INFISICAL_PROJECT_ID:-}}"
INFISICAL_TOKEN="${INFISICAL_INFRA_TOKEN:-${INFISICAL_TOKEN:-}}"
INFISICAL_API_URL="${INFISICAL_API_URL:-}"

# --- Arguments ---
if [ "$#" -ne 4 ]; then echo "Usage: $0 <domain> <privkey_path> <fullchain_path> <reload_command>"; exit 1; fi
DOMAIN="$1"
PRIVKEY_PATH="$2"
FULLCHAIN_PATH="$3"
RELOAD_CMD="$4"

# --- Pre-flight Checks ---
if [[ -z "${INFISICAL_PROJECT_ID}" || -z "${INFISICAL_TOKEN}" ]]; then echo "Keeper: FATAL - Required Infisical env vars not set." >&2; exit 1; fi

# --- Configuration ---
INFISICAL_ENV="${INFISICAL_ENV:-prod}"
INFISICAL_DOMAIN_ARGS=()
if [[ -n "${INFISICAL_API_URL}" ]]; then
    INFISICAL_DOMAIN_ARGS+=("--domain=${INFISICAL_API_URL}")
fi

# --- Logic ---
echo "Keeper: Starting certificate deployment for $DOMAIN."
TMP_DIR=$(mktemp -d); trap 'rm -rf -- "$TMP_DIR"' EXIT
TMP_PRIVKEY="$TMP_DIR/privkey.pem"; TMP_FULLCHAIN="$TMP_DIR/fullchain.pem"

DOMAIN_UPPER=$(echo "$DOMAIN" | tr '.-' '_' | tr '[:lower:]' '[:upper:]')
SECRET_NAME_PRIVKEY="LETSENCRYPT_${DOMAIN_UPPER}_PRIVKEY"
SECRET_NAME_FULLCHAIN="LETSENCRYPT_${DOMAIN_UPPER}_FULLCHAIN"

echo "Keeper: Fetching TRUE secrets from vault using --plain..."

# YOUR DISCOVERY: The correct use of the --plain flag.
/usr/bin/infisical "${INFISICAL_DOMAIN_ARGS[@]}" secrets get --env="$INFISICAL_ENV" --projectId="$INFISICAL_PROJECT_ID" --token="$INFISICAL_TOKEN" --plain "$SECRET_NAME_PRIVKEY" > "$TMP_PRIVKEY"
/usr/bin/infisical "${INFISICAL_DOMAIN_ARGS[@]}" secrets get --env="$INFISICAL_ENV" --projectId="$INFISICAL_PROJECT_ID" --token="$INFISICAL_TOKEN" --plain "$SECRET_NAME_FULLCHAIN" > "$TMP_FULLCHAIN"
echo "Keeper: True secrets fetched."

validate_pem_file() {
    local file="$1"
    local label="$2"
    local expected_header="$3"

    if [[ ! -s "$file" ]]; then
        echo "Keeper: FATAL - $label fetch returned empty content. Refusing to deploy blank certificate material." >&2
        exit 1
    fi

    if ! grep -q "^$expected_header" "$file"; then
        echo "Keeper: FATAL - $label fetch did not return a valid PEM payload. Refusing deployment." >&2
        echo "Keeper: First lines of invalid $label payload:" >&2
        sed -n '1,10p' "$file" >&2 || true
        exit 1
    fi
}

validate_pem_file "$TMP_PRIVKEY" "private key" "-----BEGIN .*PRIVATE KEY-----"
validate_pem_file "$TMP_FULLCHAIN" "full chain" "-----BEGIN CERTIFICATE-----"

# --- Pair & validity verification (fail closed) ---
# 2026-06-12 incident: the vault briefly held a fullchain from an older renewal
# than the privkey. Both payloads were valid PEM, so the format check above
# passed, the mismatched pair was deployed, and every TLS handshake failed
# with a bad CertificateVerify signature (took gour.top mail down). Never
# deploy material whose public keys don't match or whose leaf is expired.
KEY_PUB=$(openssl pkey -in "$TMP_PRIVKEY" -pubout 2>/dev/null) || {
    echo "Keeper: FATAL - private key payload is not parseable by openssl. Refusing deployment." >&2
    exit 1
}
CERT_PUB=$(openssl x509 -in "$TMP_FULLCHAIN" -pubkey -noout 2>/dev/null) || {
    echo "Keeper: FATAL - full chain payload is not parseable by openssl. Refusing deployment." >&2
    exit 1
}
if [[ "$KEY_PUB" != "$CERT_PUB" ]]; then
    echo "Keeper: FATAL - private key does not match the certificate in the vault (key/cert from different renewals?). Refusing deployment." >&2
    openssl x509 -in "$TMP_FULLCHAIN" -noout -subject -dates >&2 || true
    exit 1
fi
if ! openssl x509 -in "$TMP_FULLCHAIN" -checkend 86400 >/dev/null; then
    echo "Keeper: FATAL - vault certificate is expired or expires within 24h. Refusing to deploy stale material." >&2
    openssl x509 -in "$TMP_FULLCHAIN" -noout -dates >&2 || true
    exit 1
fi
echo "Keeper: Key/certificate pair verified (public keys match, cert valid)."

# --- Idempotency Check & Deployment (This logic remains sound) ---
NEEDS_UPDATE=0
if ! [ -f "$PRIVKEY_PATH" ] || ! diff -q "$PRIVKEY_PATH" "$TMP_PRIVKEY" >/dev/null; then NEEDS_UPDATE=1; fi
if ! [ -f "$FULLCHAIN_PATH" ] || ! diff -q "$FULLCHAIN_PATH" "$TMP_FULLCHAIN" >/dev/null; then NEEDS_UPDATE=1; fi

if [ "$NEEDS_UPDATE" -eq 0 ]; then
    echo "Keeper: Certificates are already up-to-date. No action needed."
    exit 0
fi

echo "Keeper: Certificates have changed. Deploying new files..."
chmod 600 "$TMP_PRIVKEY"; chmod 644 "$TMP_FULLCHAIN"

mkdir -p "$(dirname "$PRIVKEY_PATH")" "$(dirname "$FULLCHAIN_PATH")"
mv "$TMP_PRIVKEY" "$PRIVKEY_PATH"
mv "$TMP_FULLCHAIN" "$FULLCHAIN_PATH"
echo "Keeper: New certificates deployed successfully."

echo "Keeper: Executing reload command: '$RELOAD_CMD'"; eval "$RELOAD_CMD"
echo "Keeper: Ritual complete."
