#!/usr/bin/env bash

# Exit on error, undefined variables, and prevent pipe errors
set -euo pipefail

# --- Script Constants ---
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
readonly TEMPLATES_DIR="${REPO_ROOT}/templates"
readonly SERVICE_TEMPLATES_DIR="${TEMPLATES_DIR}/services"
readonly TIMER_TEMPLATES_DIR="${TEMPLATES_DIR}/timers"
readonly SYSTEMD_SYSTEM_DIR="/etc/systemd/system"
readonly SYSTEMD_USER_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
readonly KMONAD_PATH="${HOME}/.local/bin/kmonad"
readonly KMONAD_VERSION="${KMONAD_VERSION:-0.4.2}"
readonly KMONAD_URL="https://github.com/kmonad/kmonad/releases/download/${KMONAD_VERSION}/kmonad-linux"
readonly YGGSYNC_DEFAULT_BIN="${HOME}/.local/bin/yggsync"
readonly YGGSYNC_FETCH_SCRIPT="${REPO_ROOT}/scripts/yggsync/fetch-yggsync.sh"
readonly YGGSYNC_RENDER_SCRIPT="${REPO_ROOT}/scripts/yggsync/render-config.sh"
readonly YGGSYNC_DEFAULT_VERSION="${YGGSYNC_VERSION:-v0.3.0}"

# --- Color Definitions ---
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly BLUE='\033[0;34m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m' # No Color

# --- Globals ---
declare -a TEMP_FILES=()
NON_INTERACTIVE=0
AUTO_SELECTION=""
AUTO_ENABLE=0
LIST_ONLY=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        -y|--yes|--enable-now)
            AUTO_ENABLE=1
            shift
            ;;
        -n|--non-interactive)
            NON_INTERACTIVE=1
            shift
            ;;
        -s|--select)
            AUTO_SELECTION="$2"
            shift 2
            ;;
        --ls|--list)
            LIST_ONLY=1
            shift
            ;;
        *)
            error "Unknown option: $1"
            ;;
    esac
done

# --- Utility Functions ---
log() { echo -e "${BLUE}[INFO]${NC} $1" >&2; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; exit 1; }
warning() { echo -e "${YELLOW}[WARNING]${NC} $1" >&2; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1" >&2; }

compute_samba_user() {
    if [[ -n "${SAMBA_USER:-}" ]]; then
        echo "$SAMBA_USER"
        return
    fi
    case "$USER" in
        pi) echo "dada" ;;
        bon) echo "bon" ;;
        maa) echo "maa" ;;
        *) echo "$USER" ;;
    esac
}

compute_screencasts_remote() {
    local samba_user="$1"
    if [[ "$samba_user" == "dada" ]]; then
        echo "immich01/Screencasts"
    else
        echo "immich02/${samba_user}/desktop/Screencasts"
    fi
}

# --- Core Logic ---

# Cleanup function to remove temporary files on exit
cleanup() {
    local exit_code=$?
    for temp_file in "${TEMP_FILES[@]}"; do
        [[ -f "$temp_file" ]] && rm -f "$temp_file"
    done
    exit $exit_code
}
trap cleanup EXIT

# Ensure required directories exist
ensure_directories() {
    if [[ ! -d "$TEMPLATES_DIR" ]]; then
        error "Templates directory not found at: $TEMPLATES_DIR"
    fi
    mkdir -p "$SYSTEMD_USER_DIR"
}

# Validate template file existence and readability
validate_template() {
    if [[ ! -f "$1" ]]; then error "Template file not found: $1"; fi
    if [[ ! -r "$1" ]]; then error "Cannot read template file: $1"; fi
}

# Analyzes a systemd template to determine if it's a system or user unit.
# For timers, it intelligently inspects the corresponding service file.
analyze_unit_type() {
    local template_path="$1"
    local analysis_path="$template_path"

    validate_template "$template_path"

    # If it's a timer, find the corresponding service to determine its context
    if [[ "$template_path" == *".timer.template" ]]; then
        local service_name
        service_name=$(basename "$template_path" .timer.template)
        analysis_path="${SERVICE_TEMPLATES_DIR}/${service_name}.service.template"
        if [[ ! -f "$analysis_path" ]]; then
            error "Cannot determine type for timer '${service_name}.timer'. Corresponding service template not found at '${analysis_path}'."
        fi
        log "Timer detected. Analyzing corresponding service: ${analysis_path}"
    fi

    # Default to user service unless specific directives are found
    local unit_type="user"
    if grep -q -E '^(User|Group)=root' "$analysis_path" || \
       grep -q -E '^ExecStart=.*(/sbin/|/usr/sbin/|/sys/|/dev/|/proc/)' "$analysis_path" || \
       grep -q -E '^(AmbientCapabilities|CapabilityBoundingSet)=' "$analysis_path"; then
        unit_type="system"
    fi
    
    echo "$unit_type"
}

# Process template variables using envsubst
process_template() {
    local template="$1"
    local output_file="$2"
    
    validate_template "$template"
    
    local samba_user
    samba_user="$(compute_samba_user)"
    export REPO_ROOT KMONAD_PATH USER_HOME="$HOME" USER_NAME="$USER" SAMBA_USER="$samba_user" SCREENCASTS_REMOTE="$(compute_screencasts_remote "$samba_user")"
    
    local temp_file
    temp_file="$(mktemp)"
    TEMP_FILES+=("$temp_file")
    
    envsubst < "$template" > "$temp_file"
    mv "$temp_file" "$output_file"
}

ensure_dependencies() {
    local unit_name="$1"

    # yggsync desktop units need the binary + config; fetch/copy automatically.
    if [[ "$unit_name" == "ygg-yggsync-desktop.service" || "$unit_name" == "ygg-yggsync-desktop.timer" ]]; then
        if [[ ! -x "$YGGSYNC_DEFAULT_BIN" ]]; then
            if [[ -x "$YGGSYNC_FETCH_SCRIPT" ]]; then
                log "Fetching yggsync ${YGGSYNC_DEFAULT_VERSION} to ${YGGSYNC_DEFAULT_BIN}"
                if ! ALLOW_BUILD_FALLBACK=0 bash "$YGGSYNC_FETCH_SCRIPT" "$YGGSYNC_DEFAULT_VERSION"; then
                    warning "yggsync release missing; publish yggsync-${OS:-linux}-${ARCH:-amd64} for ${YGGSYNC_DEFAULT_VERSION} or rerun with ALLOW_BUILD_FALLBACK=1."
                fi
            else
                warning "Fetch script not found at ${YGGSYNC_FETCH_SCRIPT}; install yggsync manually."
            fi
        fi
        local ygg_cfg="${HOME}/.config/ygg_sync.toml"
        local tmpl="${REPO_ROOT}/config/yggsync/desktop/ygg_sync.toml.template"
        if [[ ! -f "$ygg_cfg" ]]; then
            if [[ -f "$tmpl" ]]; then
                if [[ "$NON_INTERACTIVE" -eq 1 ]]; then
                    resp="y"
                else
                    read -rp "--> yggsync config not found. Copy desktop template to ${ygg_cfg}? [Y/n] " resp
                fi
                if [[ ! "$resp" =~ ^[Nn]$ ]]; then
                    mkdir -p "$(dirname "$ygg_cfg")"
                    if [[ -x "$YGGSYNC_RENDER_SCRIPT" ]]; then
                        OUT="$ygg_cfg" bash "$YGGSYNC_RENDER_SCRIPT" desktop >/dev/null
                        log "Rendered yggsync config to ${ygg_cfg}. Review remote paths before first run."
                    else
                        cp "$tmpl" "$ygg_cfg"
                        log "Copied template. Please edit ${ygg_cfg} to match your remotes/paths."
                    fi
                else
                    warning "yggsync config missing; units may fail until ${ygg_cfg} exists."
                fi
            else
                warning "Config template missing at ${tmpl}; create ${ygg_cfg} manually."
            fi
        fi
    fi

    # kmonad units need kmonad installed at the configured path; fetch release via wget.
    if [[ "$unit_name" == ygg-kmonad-* ]]; then
        if [[ ! -x "$KMONAD_PATH" ]]; then
            if ! command -v wget >/dev/null 2>&1; then
                warning "wget is required to fetch kmonad binary."
                if [[ "$NON_INTERACTIVE" -eq 1 ]]; then
                    resp="y"
                else
                    read -rp "--> Install wget via apt now? [y/N] " resp
                fi
                if [[ "$resp" =~ ^[Yy]$ ]]; then
                    sudo apt-get update && sudo apt-get install -y wget
                else
                    warning "Skipping kmonad install; install wget then rerun."
                    return
                fi
            fi
            mkdir -p "$(dirname "$KMONAD_PATH")"
            log "Downloading kmonad ${KMONAD_VERSION} to ${KMONAD_PATH}"
            if wget -qO "$KMONAD_PATH" "$KMONAD_URL"; then
                chmod +x "$KMONAD_PATH"
                success "kmonad installed to ${KMONAD_PATH}"
            else
                warning "Failed to download kmonad from ${KMONAD_URL}; install manually."
            fi
        fi
    fi
}

# Install a unit to the correct systemd directory (system or user)
install_unit() {
    local template_path="$1"
    local unit_type="$2"
    local unit_name
    unit_name=$(basename "${template_path}" .template)
    
    local dest_dir
    dest_dir=$([[ "$unit_type" == "system" ]] && echo "$SYSTEMD_SYSTEM_DIR" || echo "$SYSTEMD_USER_DIR")
    
    log "Installing '${unit_name}' as a ${unit_type} unit..."

    local temp_file
    temp_file="$(mktemp)"
    TEMP_FILES+=("$temp_file")
    
    process_template "$template_path" "$temp_file"
    
    if [[ "$unit_type" == "system" ]]; then
        if ! sudo -v; then error "Sudo access is required to install system units."; fi
        sudo mv "$temp_file" "${dest_dir}/${unit_name}"
        sudo chmod 644 "${dest_dir}/${unit_name}"
        sudo systemctl daemon-reload
    else
        mv "$temp_file" "${dest_dir}/${unit_name}"
        chmod 644 "${dest_dir}/${unit_name}"
        systemctl --user daemon-reload
    fi

    ensure_dependencies "$unit_name"
    
    success "Installed ${unit_type} unit: ${unit_name}"
    
    local response
    if [[ "$AUTO_ENABLE" -eq 1 || "$NON_INTERACTIVE" -eq 1 ]]; then
        response="y"
    else
        read -rp "--> Would you like to enable and start '${unit_name}' now? [y/N] " response
    fi
    if [[ "$response" =~ ^[Yy]$ ]]; then
        if [[ "$unit_type" == "system" ]]; then
            sudo systemctl enable --now "$unit_name"
        else
            systemctl --user enable --now "$unit_name"
        fi
        success "Unit '${unit_name}' enabled and started."
    fi
}

# Get a sorted list of available templates
get_available_templates() {
    local templates=()
    while IFS= read -r template; do
        templates+=("$(basename "$template")")
    done < <(find "$SERVICE_TEMPLATES_DIR" "$TIMER_TEMPLATES_DIR" -name "*.template" -type f 2>/dev/null | sort)
    
    if [[ ${#templates[@]} -eq 0 ]]; then
        error "No templates found in $TEMPLATES_DIR"
    fi
    
    printf '%s\n' "${templates[@]}"
}

# --- Main Execution ---
main() {
    ensure_directories
    
    local templates
    mapfile -t templates < <(get_available_templates)
    
    echo "Available templates to install:"
    for i in "${!templates[@]}"; do
        local template_name="${templates[i]%.template}"
        local template_path
        if [[ ${templates[i]} == *.service.template ]]; then
            template_path="${SERVICE_TEMPLATES_DIR}/${templates[i]}"
        else
            template_path="${TIMER_TEMPLATES_DIR}/${templates[i]}"
        fi
        
        local unit_type
        unit_type=$(analyze_unit_type "$template_path")
        
        printf "  %2d) %-45s (%s)\n" "$((i+1))" "$template_name" "$unit_type"
    done
    
    if [[ "$LIST_ONLY" -eq 1 ]]; then
        exit 0
    fi
    
    echo
    local selection_input="${AUTO_SELECTION}"
    if [[ -z "$selection_input" ]]; then
        if [[ "$NON_INTERACTIVE" -eq 1 ]]; then
            error "Selection is required in non-interactive mode (use --select or --select all)."
        fi
        read -rp "Select template(s) to install (e.g., '1 3 5', 'all', or press Enter to quit): " selection_input
    fi

    if [[ -z "$selection_input" ]]; then
        log "No selection made. Exiting."
        exit 0
    fi
    
    local selections_to_install=()
    if [[ "$selection_input" == "all" ]]; then
        for i in "${!templates[@]}"; do
            selections_to_install+=("$((i+1))")
        done
    else
        # Validate input: must be numbers and spaces only
        if ! [[ "$selection_input" =~ ^[0-9\ ]+$ ]]; then
            error "Invalid input. Please enter numbers separated by spaces, or 'all'."
        fi
        read -ra selections_to_install <<< "$selection_input"
    fi
    
    for index in "${selections_to_install[@]}"; do
        if [[ "$index" -lt 1 || "$index" -gt "${#templates[@]}" ]]; then
            warning "Invalid selection '$index'. Skipping."
            continue
        fi
        
        local template_file="${templates[$((index-1))]}"
        local template_path
        if [[ $template_file == *.service.template ]]; then
            template_path="${SERVICE_TEMPLATES_DIR}/${template_file}"
        else
            template_path="${TIMER_TEMPLATES_DIR}/${template_file}"
        fi
        
        local unit_type
        unit_type=$(analyze_unit_type "$template_path")
        install_unit "$template_path" "$unit_type"
        echo # Add a newline for better readability between installations
    done
    
    success "All selected installations are complete."
}

main "$@"
