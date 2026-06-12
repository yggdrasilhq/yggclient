#!/bin/bash
#
# upload-certs.sh - The Herald's Tool (Final, Corrected Form)
# Pushes the TRUE CONTENTS of certificate files into the Infisical vault.
#

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

load_local_env() {
  local explicit="${YGG_CERTS_ENV_FILE:-}"
  local candidates=(
    "$explicit"
    "$SCRIPT_DIR/lego.local.env"
    "$SCRIPT_DIR/../../config/certs.local.env"
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

INFISICAL_PROJECT_ID="${INFISICAL_PROJECT_ID:-${INFISICAL_INFRA_PROJECT_ID:-}}"
INFISICAL_TOKEN="${INFISICAL_TOKEN:-${INFISICAL_INFRA_TOKEN:-}}"
INFISICAL_API_URL="${INFISICAL_API_URL:-}"

# --- Pre-flight Checks ---
if [[ -z "${INFISICAL_PROJECT_ID}" || -z "${INFISICAL_TOKEN}" ]]; then
  echo "Herald: FATAL - Required Infisical environment variables are not set." >&2
  exit 1
fi
if [ "$#" -ne 1 ]; then echo "Usage: $0 <domain>"; exit 1; fi

# --- Configuration ---
DOMAIN="$1"
LE_CERTS_PATH="/etc/letsencrypt/$DOMAIN/certificates"
INFISICAL_ENV="${INFISICAL_ENV:-prod}"
INFISICAL_DOMAIN_ARGS=()
if [[ -n "${INFISICAL_API_URL}" ]]; then
    INFISICAL_DOMAIN_ARGS+=("--domain=${INFISICAL_API_URL}")
fi

# --- Main Logic ---
echo "Herald: Starting TRUE certificate upload for $DOMAIN to project $INFISICAL_PROJECT_ID..."
DOMAIN_UPPER=$(echo "$DOMAIN" | tr '.-' '_' | tr '[:lower:]' '[:upper:]')
SECRET_NAME_PRIVKEY="LETSENCRYPT_${DOMAIN_UPPER}_PRIVKEY"
SECRET_NAME_FULLCHAIN="LETSENCRYPT_${DOMAIN_UPPER}_FULLCHAIN"

# --- Pair & validity verification (fail closed) ---
# 2026-06-12 incident: the vault ended up holding a fullchain and privkey from
# different renewals; the consumer deployed the mismatched pair and gour.top
# mail TLS broke. The vault must only ever receive a verified matching pair,
# so verify BEFORE the first write — the two `secrets set` calls below are not
# atomic, and aborting between them is what leaves the vault mixed.
PRIVKEY_FILE="$LE_CERTS_PATH/$DOMAIN.key"
FULLCHAIN_FILE="$LE_CERTS_PATH/$DOMAIN.fullchain.pem"
if ! [ -f "$PRIVKEY_FILE" ]; then echo "Herald: FATAL - Private key file not found!" >&2; exit 1; fi
if ! [ -f "$FULLCHAIN_FILE" ]; then echo "Herald: FATAL - Full chain file not found!" >&2; exit 1; fi
KEY_PUB=$(openssl pkey -in "$PRIVKEY_FILE" -pubout 2>/dev/null) || {
    echo "Herald: FATAL - $PRIVKEY_FILE is not a parseable private key. Refusing upload." >&2
    exit 1
}
CERT_PUB=$(openssl x509 -in "$FULLCHAIN_FILE" -pubkey -noout 2>/dev/null) || {
    echo "Herald: FATAL - $FULLCHAIN_FILE is not a parseable certificate. Refusing upload." >&2
    exit 1
}
if [[ "$KEY_PUB" != "$CERT_PUB" ]]; then
    echo "Herald: FATAL - $PRIVKEY_FILE does not match $FULLCHAIN_FILE (different renewals?). Refusing to poison the vault." >&2
    openssl x509 -in "$FULLCHAIN_FILE" -noout -subject -dates >&2 || true
    exit 1
fi
if ! openssl x509 -in "$FULLCHAIN_FILE" -checkend 86400 >/dev/null; then
    echo "Herald: FATAL - $FULLCHAIN_FILE is expired or expires within 24h. Refusing to upload stale material." >&2
    openssl x509 -in "$FULLCHAIN_FILE" -noout -dates >&2 || true
    exit 1
fi
echo "Herald: Key/certificate pair verified (public keys match, cert valid)."

# --- Upload Private Key ---
echo "Herald: Reading TRUE CONTENT from $PRIVKEY_FILE..."

# THE TRUE INCANTATION: Use command substitution to embed the file's content.
infisical "${INFISICAL_DOMAIN_ARGS[@]}" secrets set --env="$INFISICAL_ENV" --projectId="$INFISICAL_PROJECT_ID" --token="$INFISICAL_TOKEN" "$SECRET_NAME_PRIVKEY=$(cat "$PRIVKEY_FILE")" >/dev/null
if [ $? -ne 0 ]; then echo "Herald: FATAL - Failed to upload private key." >&2; exit 1; fi
echo "Herald: Private key content uploaded successfully."

# --- Upload Full Chain Certificate ---
echo "Herald: Reading TRUE CONTENT from $FULLCHAIN_FILE..."

# THE TRUE INCANTATION:
infisical "${INFISICAL_DOMAIN_ARGS[@]}" secrets set --env="$INFISICAL_ENV" --projectId="$INFISICAL_PROJECT_ID" --token="$INFISICAL_TOKEN" "$SECRET_NAME_FULLCHAIN=$(cat "$FULLCHAIN_FILE")" >/dev/null
if [ $? -ne 0 ]; then echo "Herald: FATAL - Failed to upload full chain." >&2; exit 1; fi
echo "Herald: Full chain content uploaded successfully."

echo "Herald: Certificate upload for $DOMAIN completed. The vault now holds the true secrets."
