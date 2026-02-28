#!/bin/bash
#
# upload-certs.sh - The Herald's Tool (Final, Corrected Form)
# Pushes the TRUE CONTENTS of certificate files into the Infisical vault.
#

set -euo pipefail

INFISICAL_PROJECT_ID=${INFISICAL_INFRA_PROJECT_ID}
INFISICAL_TOKEN=${INFISICAL_INFRA_TOKEN}

# --- Pre-flight Checks ---
if [[ -z "${INFISICAL_PROJECT_ID}" || -z "${INFISICAL_TOKEN}" ]]; then
  echo "Herald: FATAL - Required Infisical environment variables are not set." >&2
  exit 1
fi
if [ "$#" -ne 1 ]; then echo "Usage: $0 <domain>"; exit 1; fi

# --- Configuration ---
DOMAIN="$1"
LE_CERTS_PATH="/etc/letsencrypt/$DOMAIN/certificates"
INFISICAL_ENV="prod"

# --- Main Logic ---
echo "Herald: Starting TRUE certificate upload for $DOMAIN to project $INFISICAL_PROJECT_ID..."
DOMAIN_UPPER=$(echo "$DOMAIN" | tr '.-' '_' | tr '[:lower:]' '[:upper:]')
SECRET_NAME_PRIVKEY="LETSENCRYPT_${DOMAIN_UPPER}_PRIVKEY"
SECRET_NAME_FULLCHAIN="LETSENCRYPT_${DOMAIN_UPPER}_FULLCHAIN"

# --- Upload Private Key ---
PRIVKEY_FILE="$LE_CERTS_PATH/$DOMAIN.key"
if ! [ -f "$PRIVKEY_FILE" ]; then echo "Herald: FATAL - Private key file not found!" >&2; exit 1; fi
echo "Herald: Reading TRUE CONTENT from $PRIVKEY_FILE..."

# THE TRUE INCANTATION: Use command substitution to embed the file's content.
infisical secrets set --env="$INFISICAL_ENV" --projectId="$INFISICAL_PROJECT_ID" --token="$INFISICAL_TOKEN" "$SECRET_NAME_PRIVKEY=$(cat "$PRIVKEY_FILE")"
if [ $? -ne 0 ]; then echo "Herald: FATAL - Failed to upload private key." >&2; exit 1; fi
echo "Herald: Private key content uploaded successfully."

# --- Upload Full Chain Certificate ---
FULLCHAIN_FILE="$LE_CERTS_PATH/$DOMAIN.fullchain.pem"
if ! [ -f "$FULLCHAIN_FILE" ]; then echo "Herald: FATAL - Full chain file not found!" >&2; exit 1; fi
echo "Herald: Reading TRUE CONTENT from $FULLCHAIN_FILE..."

# THE TRUE INCANTATION:
infisical secrets set --env="$INFISICAL_ENV" --projectId="$INFISICAL_PROJECT_ID" --token="$INFISICAL_TOKEN" "$SECRET_NAME_FULLCHAIN=$(cat "$FULLCHAIN_FILE")"
if [ $? -ne 0 ]; then echo "Herald: FATAL - Failed to upload full chain." >&2; exit 1; fi
echo "Herald: Full chain content uploaded successfully."

echo "Herald: Certificate upload for $DOMAIN completed. The vault now holds the true secrets."
