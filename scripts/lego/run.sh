#!/usr/bin/bash
set -e # Exit immediately if a command exits with a non-zero status.
set -u # Treat unset variables as an error when substituting.
set -o pipefail # The return value of a pipeline is the status of the last command to exit with a non-zero status.

# --- Configuration ---
LEGO_INSTALL_DIR="/etc/letsencrypt/gour.top/lego" # Directory to install/find the lego binary
LEGO_EXEC_NAME="lego"
LEGO_EXEC_PATH="${LEGO_INSTALL_DIR}/${LEGO_EXEC_NAME}"

LEGO_ACCOUNT_EMAIL="avikalpa@yahoo.com"
DOMAINS_TO_CERTIFY=("gour.top" "*.gour.top") # Array of domains
LEGO_KEY_TYPE="rsa2048"
LEGO_STORAGE_PATH="/etc/letsencrypt/gour.top" # Lego's --path, stores account & certs
DNS_RESOLVERS="1.1.1.1:53,8.8.8.8:53"

# --- Debugging ---
export LEGO_DEBUG_CLIENT_VERBOSE_ERROR=true
export LEGO_DEBUG_ACME_HTTP_CLIENT=true

# Porkbun API Credentials
# For better security with systemd, consider using an EnvironmentFile in the .service unit
export PORKBUN_SECRET_API_KEY="sk1_184ee84e0c2fc3e1fac8d13026c55d13c9fb6f7105385856f7a5b549e06ba4d9"
export PORKBUN_API_KEY="pk1_a898ff2faf8ba7b358fffca7aea5decdac1242e86738b0f0ffb9e4a44942a584"

NGINX_RELOAD_COMMAND="systemctl reload nginx" # Command to run if certs are renewed
#POSTFIX_RELOAD_COMMAND="systemctl reload postfix" # Optional: Command to reload postfix

# --- Logging ---
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# --- Functions ---
ensure_latest_lego() {
    log_message "Checking for lego updates..."

    if ! command -v jq &> /dev/null; then
        log_message "ERROR: jq is not installed. Please install jq (e.g., sudo apt install jq)."
        exit 1
    fi
    if ! command -v curl &> /dev/null; then
        log_message "ERROR: curl is not installed. Please install curl (e.g., sudo apt install curl)."
        exit 1
    fi

    local latest_release_info raw_latest_version latest_version latest_release_url
    latest_release_info=$(curl --silent --show-error --location https://api.github.com/repos/go-acme/lego/releases/latest)

    if [ -z "$latest_release_info" ]; then
        log_message "ERROR: Could not fetch latest release info from GitHub API. Will try to use existing lego if present."
        if [ ! -x "${LEGO_EXEC_PATH}" ]; then
            log_message "ERROR: Existing lego not found at ${LEGO_EXEC_PATH} and cannot fetch update. Aborting."
            exit 1
        fi
        log_message "WARNING: Proceeding with potentially outdated lego found at ${LEGO_EXEC_PATH}."
        return 0 # Proceed with existing
    fi

    raw_latest_version=$(echo "$latest_release_info" | jq -r '.tag_name')
    # Strip leading 'v' if present from the GitHub tag
    latest_version="${raw_latest_version#v}"

    latest_release_url=$(echo "$latest_release_info" | jq -r '.assets[] | select(.name | test("linux_amd64.tar.gz$")) | .browser_download_url')

    if [ -z "$latest_version" ] || [ "$latest_version" == "null" ] || [ "$latest_version" == "" ]; then
        log_message "ERROR: Could not determine the latest lego version from GitHub API (tag: '$raw_latest_version')."
        exit 1
    fi
    if [ -z "$latest_release_url" ] || [ "$latest_release_url" == "null" ]; then
        log_message "ERROR: Could not determine the latest lego download URL from GitHub API."
        exit 1
    fi

    local current_version="none"
    local raw_current_version="unknown"
    if [ -x "${LEGO_EXEC_PATH}" ]; then
        raw_current_version=$("${LEGO_EXEC_PATH}" --version 2>&1 | head -n 1 | grep -oP 'version \K[^ ]+' || echo "unknown")
        if [ "$raw_current_version" != "unknown" ] && [ "$raw_current_version" != "" ]; then
            current_version="${raw_current_version#v}"
        else
            current_version="unknown"
        fi
    fi

    log_message "Current lego version (normalized): '$current_version' (raw: '$raw_current_version'). Latest available (normalized): '$latest_version' (raw tag: '$raw_latest_version')."

    if [ "$current_version" == "$latest_version" ] && [ "$current_version" != "unknown" ] && [ "$current_version" != "none" ]; then
        log_message "Lego is up to date (${current_version}). No download needed."
        return 0
    fi

    log_message "Lego needs update (current normalized: '$current_version', latest normalized: '$latest_version') or is not installed/version unknown. Downloading..."
    log_message "Latest lego download URL: $latest_release_url"

    local temp_dir
    temp_dir=$(mktemp -d -p "/tmp" lego_download_XXXXXX)
    local downloaded_tarball="${temp_dir}/lego.tar.gz"

    log_message "Downloading latest lego to $downloaded_tarball..."
    if ! curl --silent --show-error --location -o "$downloaded_tarball" "$latest_release_url"; then
        log_message "ERROR: Failed to download lego tarball."
        rm -rf "$temp_dir"
        exit 1
    fi

    log_message "Extracting lego binary from $downloaded_tarball to $temp_dir..."
    if ! tar xzf "$downloaded_tarball" -C "$temp_dir" "$LEGO_EXEC_NAME"; then
        log_message "WARN: Could not extract '$LEGO_EXEC_NAME' directly. Searching tarball contents..."
        local extracted_lego_path_candidate
        extracted_lego_path_candidate=$(tar tzf "$downloaded_tarball" | grep -E "/${LEGO_EXEC_NAME}$" | head -n 1)
        if [ -n "$extracted_lego_path_candidate" ]; then
            log_message "Found potential lego binary at '$extracted_lego_path_candidate' in tarball. Extracting..."
            if ! tar xzf "$downloaded_tarball" -C "$temp_dir" "$extracted_lego_path_candidate"; then
                 log_message "ERROR: Failed to extract '$extracted_lego_path_candidate'."
                 rm -rf "$temp_dir"; exit 1;
            fi
            if ! mv "${temp_dir}/${extracted_lego_path_candidate}" "${temp_dir}/${LEGO_EXEC_NAME}"; then
                log_message "ERROR: Failed to move extracted lego binary to expected temp location."
                rm -rf "$temp_dir"; exit 1;
            fi
        else
            log_message "ERROR: Failed to extract lego binary. '$LEGO_EXEC_NAME' not found in tarball."
            rm -rf "$temp_dir"; exit 1;
        fi
    fi

    local final_extracted_binary_path="${temp_dir}/${LEGO_EXEC_NAME}"
    if [ ! -f "$final_extracted_binary_path" ]; then
        log_message "ERROR: Extracted lego binary not found at $final_extracted_binary_path."
        rm -rf "$temp_dir"; exit 1;
    fi

    log_message "Ensuring installation directory ${LEGO_INSTALL_DIR} exists..."
    if ! mkdir -p "${LEGO_INSTALL_DIR}"; then
        log_message "ERROR: Could not create installation directory ${LEGO_INSTALL_DIR}."
        rm -rf "$temp_dir"; exit 1;
    fi

    log_message "Moving lego binary to ${LEGO_EXEC_PATH}..."
    if ! install -m 0755 "$final_extracted_binary_path" "${LEGO_EXEC_PATH}"; then
        log_message "ERROR: Failed to install lego binary to ${LEGO_EXEC_PATH}."
        rm -rf "$temp_dir"; exit 1;
    fi

    log_message "Lego binary successfully installed/updated to ${LEGO_EXEC_PATH}."
    rm -rf "$temp_dir"
}

# --- Main Script ---
log_message "Starting certificate management script for domains: ${DOMAINS_TO_CERTIFY[*]}."

# Download/Update lego binary if needed
ensure_latest_lego

# Ensure storage path for lego exists
if ! mkdir -p "${LEGO_STORAGE_PATH}"; then
    log_message "ERROR: Could not create lego storage directory ${LEGO_STORAGE_PATH}."
    exit 1
fi

log_message "Preparing to run lego..."
lego_args=(
    "--accept-tos"
    "--email=${LEGO_ACCOUNT_EMAIL}"
    "--dns=porkbun"
    "--key-type=${LEGO_KEY_TYPE}"
    "--path=${LEGO_STORAGE_PATH}"
    "--dns.resolvers=${DNS_RESOLVERS}"
)

for domain in "${DOMAINS_TO_CERTIFY[@]}"; do
    lego_args+=("--domains=${domain}")
done

# Store the current directory to return to it later if needed,
# though for this script, it's the last major operation.
# pushd / popd is safer if there were more complex operations after.
original_dir=$(pwd)

log_message "Executing: ${LEGO_EXEC_PATH} ${lego_args[*]} run"

if ! "${LEGO_EXEC_PATH}" "${lego_args[@]}" run; then
    log_message "ERROR: Lego 'run' command failed."
    # cd "$original_dir" # Optional: return to original dir on error
    exit 1
fi

log_message "Lego 'run' command completed successfully."
log_message "Attempting to reload Nginx..."
if ! ${NGINX_RELOAD_COMMAND}; then
    log_message "WARN: Nginx reload command ('${NGINX_RELOAD_COMMAND}') failed. Manual reload may be required."
else
    log_message "Nginx reloaded successfully."
fi

# --- Postfix Fullchain Creation ---
log_message "Creating fullchain.pem for Postfix..."
CERT_DIR="${LEGO_STORAGE_PATH}/certificates"
PRIMARY_DOMAIN_CERT_NAME="gour.top" # Lego names files after the first non-wildcard domain or the primary cert name.

if [ -d "${CERT_DIR}" ]; then
    # Using a subshell for the cd and cat operations to avoid changing the script's PWD
    (
        cd "${CERT_DIR}"
        if [ -f "${PRIMARY_DOMAIN_CERT_NAME}.crt" ] && [ -f "${PRIMARY_DOMAIN_CERT_NAME}.issuer.crt" ]; then
            cat "${PRIMARY_DOMAIN_CERT_NAME}.crt" "${PRIMARY_DOMAIN_CERT_NAME}.issuer.crt" > "${PRIMARY_DOMAIN_CERT_NAME}.fullchain.pem"
            log_message "Successfully created ${PRIMARY_DOMAIN_CERT_NAME}.fullchain.pem in ${CERT_DIR}."
            # Optionally, set permissions for the fullchain.pem if needed
            # chmod 640 "${PRIMARY_DOMAIN_CERT_NAME}.fullchain.pem" # Example
            # chown root:mail "${PRIMARY_DOMAIN_CERT_NAME}.fullchain.pem" # Example if postfix runs as 'mail' user/group

            # Optionally, reload Postfix if you want it to pick up the new cert immediately
            if [ -n "${POSTFIX_RELOAD_COMMAND:-}" ]; then # Check if POSTFIX_RELOAD_COMMAND is set and not empty
                log_message "Attempting to reload Postfix..."
                if ! ${POSTFIX_RELOAD_COMMAND}; then
                    log_message "WARN: Postfix reload command ('${POSTFIX_RELOAD_COMMAND}') failed. Manual reload may be required."
                else
                    log_message "Postfix reloaded successfully."
                fi
            fi
        else
            log_message "WARN: Could not create fullchain.pem. Required .crt or .issuer.crt missing in ${CERT_DIR} for ${PRIMARY_DOMAIN_CERT_NAME}."
        fi
    )
else
    log_message "WARN: Certificates directory ${CERT_DIR} not found. Skipping fullchain.pem creation."
fi
# cd "$original_dir" # If not using subshell and wanted to return to original PWD

log_message "Certificate management script finished."

# After a successful renewal, upload the new certificates to Infisical.
/usr/local/bin/upload-certs.sh gour.top

exit 0
