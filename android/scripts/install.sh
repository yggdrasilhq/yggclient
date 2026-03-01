#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

SCRIPT_DIR_SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
YGG_DIR_DEFAULT="$(cd "$SCRIPT_DIR_SELF/../.." && pwd)"
YGG_DIR="${YGG_CLIENT_DIR:-$YGG_DIR_DEFAULT}"
if [ ! -d "$YGG_DIR" ] && [ -d "$HOME/git/ygg_client" ]; then
  YGG_DIR="$HOME/git/ygg_client"
fi
BOOT_SCRIPT_DIR="$HOME/.termux/boot"
STATE_DIR="$HOME/.local/state/ygg_client"
RCLONE_CONFIG="$HOME/.config/rclone/rclone.conf"
ANDROID_DIR="$YGG_DIR/android"
ANDROID_BIN="$ANDROID_DIR/bin/yggsync"
LOCAL_BIN="$HOME/.local/bin"
SCRIPT_DIR="$ANDROID_DIR/scripts"
BOOT_SCRIPT_NAME="ygg-start-sync-jobs"
BOOT_SCRIPT_PATH="$BOOT_SCRIPT_DIR/$BOOT_SCRIPT_NAME"
TERMUX_BOOT_SCRIPT="$SCRIPT_DIR/termux-boot-sync-jobs.sh"
SYNC_SCRIPT="$SCRIPT_DIR/sync-obsidian.sh"
SHORTCUTS_SRC="$ANDROID_DIR/shortcuts"
SHORTCUTS_WIDGET="$HOME/.shortcuts/tasks"
DYNAMIC_SHORTCUTS="$HOME/.termux/widget/dynamic_shortcuts"

log(){ printf "[%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }
prompt_yes(){
  read -r -p "$1 [y/N]: " ans
  [[ $ans =~ ^[Yy]$ ]]
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

ensure_alias(){
  alias_line=$1
  rc="$HOME/.bashrc"
  if ! grep -Fq "$alias_line" "$rc" 2>/dev/null; then
    echo "$alias_line" >> "$rc"
  fi
}

log "Checking prerequisites..."
ensure_pkg termux-api
ensure_pkg termux-tools
ensure_pkg termux-boot
ensure_pkg termux-widget
ensure_pkg rclone

log "Ensuring directories..."
mkdir -p "$STATE_DIR" "$BOOT_SCRIPT_DIR" "$SHORTCUTS_WIDGET" "$DYNAMIC_SHORTCUTS" "$LOCAL_BIN"

log "Making scripts executable..."
chmod +x "$SCRIPT_DIR"/*.sh "$ANDROID_DIR/shortcuts"/*

if [ -x "$ANDROID_BIN" ]; then
  log "Installing yggsync binary..."
  install -m 0755 "$ANDROID_BIN" "$LOCAL_BIN/yggsync"
else
  log "yggsync binary not found at $ANDROID_BIN; run android/scripts/fetch-yggsync.sh to download from release or build from ~/git/yggsync."
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

log "Ensuring bash aliases (ll, hh)..."
ensure_alias "alias ll='ls -alF'"
ensure_alias "alias hh=\"cat ~/.bash_history | grep\""

log "Rclone config check..."
if [ ! -f "$RCLONE_CONFIG" ]; then
  log "rclone config not found at $RCLONE_CONFIG"
  if prompt_yes "Run rclone config now?"; then
    rclone config
  else
    log "Skip rclone config; remember to create $RCLONE_CONFIG with remote 'smb0' pointing to smb://<NAS>/smbfs"
  fi
fi

log "Initial job scheduling..."
bash "$TERMUX_BOOT_SCRIPT" || log "Warning: job scheduling script returned non-zero"

log "Done. Paths expect obsidian at remote path 'data/obsidian' on remote 'smb0' (pointing to smbfs/dada/obsidian)."
