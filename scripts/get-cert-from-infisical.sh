#!/bin/bash
#
# deploy-certs.sh - The Keeper's Ritual (Final, Corrected Form)
# Fetches the TRUE certificate content from Infisical using the --plain flag.
#

set -euo pipefail

INFISICAL_PROJECT_ID=${INFISICAL_INFRA_PROJECT_ID}
INFISICAL_TOKEN=${INFISICAL_INFRA_TOKEN}

# --- Arguments ---
if [ "$#" -ne 4 ]; then echo "Usage: $0 <domain> <privkey_path> <fullchain_path> <reload_command>"; exit 1; fi
DOMAIN="$1"
PRIVKEY_PATH="$2"
FULLCHAIN_PATH="$3"
RELOAD_CMD="$4"

# --- Pre-flight Checks ---
if [[ -z "${INFISICAL_PROJECT_ID}" || -z "${INFISICAL_TOKEN}" ]]; then echo "Keeper: FATAL - Required Infisical env vars not set." >&2; exit 1; fi

# --- Configuration ---
INFISICAL_ENV="prod"

# --- Logic ---
echo "Keeper: Starting certificate deployment for $DOMAIN."
TMP_DIR=$(mktemp -d); trap 'rm -rf -- "$TMP_DIR"' EXIT
TMP_PRIVKEY="$TMP_DIR/privkey.pem"; TMP_FULLCHAIN="$TMP_DIR/fullchain.pem"

DOMAIN_UPPER=$(echo "$DOMAIN" | tr '.-' '_' | tr '[:lower:]' '[:upper:]')
SECRET_NAME_PRIVKEY="LETSENCRYPT_${DOMAIN_UPPER}_PRIVKEY"
SECRET_NAME_FULLCHAIN="LETSENCRYPT_${DOMAIN_UPPER}_FULLCHAIN"

echo "Keeper: Fetching TRUE secrets from vault using --plain..."

# YOUR DISCOVERY: The correct use of the --plain flag.
/usr/bin/infisical secrets get --env="$INFISICAL_ENV" --projectId="$INFISICAL_PROJECT_ID" --token="$INFISICAL_TOKEN" --plain "$SECRET_NAME_PRIVKEY" > "$TMP_PRIVKEY"
/usr/bin/infisical secrets get --env="$INFISICAL_ENV" --projectId="$INFISICAL_PROJECT_ID" --token="$INFISICAL_TOKEN" --plain "$SECRET_NAME_FULLCHAIN" > "$TMP_FULLCHAIN"
echo "Keeper: True secrets fetched."

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
