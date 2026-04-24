#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

SCRIPT_DIR_SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
YGG_DIR_DEFAULT="$(cd "$SCRIPT_DIR_SELF/../.." && pwd)"
YGG_DIR="${YGG_CLIENT_DIR:-$YGG_DIR_DEFAULT}"
BOOT_SCRIPT_DIR="$HOME/.termux/boot"
STATE_DIR="$HOME/.local/state/ygg_client"
ANDROID_DIR="$YGG_DIR/android"
ANDROID_BIN="$ANDROID_DIR/bin/yggsync"
ANDROID_CORE_BIN="$ANDROID_DIR/bin/yggsync-core"
LOCAL_BIN="$HOME/.local/bin"
SCRIPT_DIR="$ANDROID_DIR/scripts"
BOOT_SCRIPT_NAME="ygg-start-sync-jobs"
BOOT_SCRIPT_PATH="$BOOT_SCRIPT_DIR/$BOOT_SCRIPT_NAME"
TERMUX_BOOT_SCRIPT="$SCRIPT_DIR/termux-boot-sync-jobs.sh"
SHORTCUTS_SRC="$ANDROID_DIR/shortcuts"
SHORTCUTS_WIDGET="$HOME/.shortcuts/tasks"
DYNAMIC_SHORTCUTS="$HOME/.termux/widget/dynamic_shortcuts"
CONFIG_PATH="${YGG_SYNC_CONFIG:-$HOME/.config/ygg_sync.toml}"
RUNTIME_PATH="${YGG_SYNC_RUNTIME:-$HOME/.config/yggsync.runtime.toml}"
RUNTIME_TEMPLATE="$ANDROID_DIR/config/yggsync.runtime.toml.template"

log(){ printf "[%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }
prompt_yes(){
  read -r -p "$1 [y/N]: " ans
  [[ $ans =~ ^[Yy]$ ]]
}

install_if_needed(){
  src=$1
  dest=$2
  label=$3
  if [ -e "$dest" ] && [ "$(readlink -f "$src")" = "$(readlink -f "$dest")" ]; then
    log "$label already installed at $dest"
    return 0
  fi
  install -m 0755 "$src" "$dest"
}

ensure_pkg(){
  pkg=$1
  if ! command -v "$pkg" >/dev/null 2>&1; then
    log "Installing $pkg..."
    if ! pkg install -y "$pkg"; then
      log "Warning: failed to install $pkg (may require APK/manual install); continuing."
    fi
  fi
}

ensure_termux_api(){
  if command -v termux-job-scheduler >/dev/null 2>&1 && command -v termux-toast >/dev/null 2>&1; then
    return 0
  fi
  ensure_pkg termux-api
}

ensure_alias(){
  alias_line=$1
  rc="$HOME/.bashrc"
  if ! grep -Fq "$alias_line" "$rc" 2>/dev/null; then
    echo "$alias_line" >> "$rc"
  fi
}

log "Checking prerequisites..."
ensure_termux_api
log "Ensuring directories..."
mkdir -p "$STATE_DIR" "$BOOT_SCRIPT_DIR" "$SHORTCUTS_WIDGET" "$DYNAMIC_SHORTCUTS" "$LOCAL_BIN"
log "Reminder: install the Termux:Boot and Termux:Widget Android apps from F-Droid or GitHub."

log "Making scripts executable..."
chmod +x "$SCRIPT_DIR"/*.sh "$ANDROID_DIR/shortcuts"/*

if [ -x "$ANDROID_BIN" ]; then
  log "Installing yggsync wrapper binary..."
  install_if_needed "$ANDROID_BIN" "$LOCAL_BIN/yggsync" "yggsync wrapper"
else
  log "yggsync wrapper binary not found at $ANDROID_BIN; build or copy it first."
fi

if [ -x "$ANDROID_CORE_BIN" ]; then
  log "Installing yggsync-core worktree binary..."
  install_if_needed "$ANDROID_CORE_BIN" "$LOCAL_BIN/yggsync-core" "yggsync-core"
elif [ ! -x "$LOCAL_BIN/yggsync-core" ]; then
  log "Warning: yggsync-core is missing. Worktree jobs will not run until ~/.local/bin/yggsync-core exists."
fi

mkdir -p "$HOME/.config"
if [ ! -f "$RUNTIME_PATH" ] && [ -f "$RUNTIME_TEMPLATE" ]; then
  log "Installing default runtime policy..."
  install -m 0644 "$RUNTIME_TEMPLATE" "$RUNTIME_PATH"
fi

log "Installing Termux:Boot script..."
cat > "$BOOT_SCRIPT_PATH" <<EOS
#!/data/data/com.termux/files/usr/bin/bash
bash "$TERMUX_BOOT_SCRIPT"
EOS
chmod +x "$BOOT_SCRIPT_PATH"

log "Installing shortcuts (widget/dynamic)..."
for dir in "$SHORTCUTS_WIDGET" "$DYNAMIC_SHORTCUTS"; do
  mkdir -p "$dir"
  cp -f "$SHORTCUTS_SRC"/* "$dir" || true
  chmod +x "$dir"/* || true
done

log "Cleaning obsolete wrapper leftovers..."
rm -f \
  "$HOME/.local/bin/yggsync-legacy-prewrapper" \
  "$HOME/.local/state/yggsync/jobs/run-fast.sh" \
  "$SHORTCUTS_WIDGET/sync-yggsync-fast.sh" \
  "$SHORTCUTS_WIDGET/sync-yggsync-bulk.sh" \
  "$DYNAMIC_SHORTCUTS/sync-yggsync-fast.sh" \
  "$DYNAMIC_SHORTCUTS/sync-yggsync-bulk.sh"

log "Ensuring bash aliases (ll, hh)..."
ensure_alias "alias ll='ls -alF'"
ensure_alias "alias hh=\"cat ~/.bash_history | grep\""

log "Initial job scheduling..."
YGG_AUTO_UPDATE=0 bash "$TERMUX_BOOT_SCRIPT" || log "Warning: job scheduling script returned non-zero"

log "Done. Review $CONFIG_PATH, $RUNTIME_PATH, and ensure SAMBA_PASSWORD is exported in your Termux environment."
