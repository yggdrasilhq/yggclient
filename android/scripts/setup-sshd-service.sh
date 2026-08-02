#!/data/data/com.termux/files/usr/bin/bash
# setup-sshd-service.sh - make Termux sshd boot-persistent and key-only.
#
# Run this ON THE PHONE, inside the Termux app (the first time; not over ssh):
#
#   bash android/scripts/setup-sshd-service.sh
#   bash android/scripts/setup-sshd-service.sh --persist-only
#
# Idempotent - safe to re-run. It:
#   1. installs openssh + termux-services (runit) and enables sshd as a service,
#   2. installs a persistence layer that RE-ASSERTS that state (see below),
#   3. authorizes the workstation key, restricted to the networks you name,
#   4. applies a managed hardening block to sshd_config, validated with
#      `sshd -t` and rolled back if it does not parse,
#   5. prints the identity block the workstation needs for its ~/.ssh/config.
#
# `--persist-only` runs step 2 alone: no package installs, no key changes, no
# sshd_config edits. That makes it safe to run over ssh on a phone that is
# already set up and only needs the persistence layer.
#
# Nothing here needs root. Every file it edits is backed up next to itself.
#
# --- WHY THE PERSISTENCE LAYER EXISTS ---------------------------------------
#
# `sv-enable sshd` works by deleting $PREFIX/var/service/sshd/down. But that
# file is shipped BY the openssh package and is NOT a dpkg conffile, so dpkg
# restores it on every upgrade. Enabling the service once is therefore not
# durable: after the next `pkg upgrade` touches openssh, every boot leaves sshd
# supervised-but-down - runsvdir comes up, runsv comes up, sees ./down, and
# parks the service - and the phone has no route in until somebody opens Termux
# and types `sshd` by hand.
#
# So the desired state is re-asserted by ONE routine, ygg-sshd-ensure, driven
# from three independent triggers:
#
#   Termux:Boot hook   ~/.termux/boot/00-start-services
#   apt post-invoke    $PREFIX/etc/apt/apt.conf.d/99-yggclient-sshd-ensure
#   job-scheduler      persisted periodic job (Android JobScheduler, not
#                      Termux:Boot, so it heals the phone even if the boot hook
#                      never fires or Android kills runsvdir mid-life)

set -uo pipefail

# --- Settings ---------------------------------------------------------------
#
# Site values are NOT baked into this repo. Put them in ~/.config/ygg_client.env
# (see android/config/ygg_client.env.example) or export them before running:
#
#   YGG_SSHD_AUTHORIZED_KEY   the workstation public key to authorize
#   YGG_SSHD_ALLOWED_SOURCES  comma-separated CIDRs that key may connect FROM,
#                             e.g. your VPN range plus your LAN. Empty means no
#                             source restriction (allowed, but say so out loud).
#   YGG_SSHD_PORT             listen port, default 8022
#   YGG_SSHD_WATCHDOG_JOB_ID  job-scheduler id for the watchdog, default 103
#   YGG_SSHD_WATCHDOG_PERIOD_MS  watchdog period, default 900000 (15 min, the
#                             Android minimum)

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
HOME="${HOME:-/data/data/com.termux/files/home}"

ENV_FILE="${YGG_CLIENT_ENV:-$HOME/.config/ygg_client.env}"
if [ -f "$ENV_FILE" ]; then
    # shellcheck disable=SC1090
    . "$ENV_FILE"
fi

WORKSTATION_KEY="${YGG_SSHD_AUTHORIZED_KEY:-}"
ALLOWED_SOURCES="${YGG_SSHD_ALLOWED_SOURCES:-}"
PORT="${YGG_SSHD_PORT:-8022}"
WATCHDOG_JOB_ID="${YGG_SSHD_WATCHDOG_JOB_ID:-103}"
WATCHDOG_PERIOD_MS="${YGG_SSHD_WATCHDOG_PERIOD_MS:-900000}"

SSHD_CONF="$PREFIX/etc/ssh/sshd_config"
STAMP="$(date +%Y%m%d-%H%M%S)"
MARK_BEGIN='# >>> yggclient managed sshd hardening >>>'
MARK_END='# <<< yggclient managed sshd hardening <<<'
ENSURE="$HOME/.local/bin/ygg-sshd-ensure"
JOBS_DIR="$HOME/.local/state/ygg_client/jobs"

PERSIST_ONLY=0
case "${1:-}" in
    --persist-only) PERSIST_ONLY=1 ;;
    "") ;;
    *) echo >&2 "usage: $0 [--persist-only]"; exit 2 ;;
esac

fail() { echo >&2 "ERROR: $*"; exit 1; }
warn() { echo >&2 "WARNING: $*"; }

case "$PREFIX" in
    *com.termux*) ;;
    *) fail "this script only runs inside Termux (PREFIX=$PREFIX)" ;;
esac

USER_NAME="$(whoami)"
echo "=== Termux sshd setup for user $USER_NAME ==="

if [ "$PERSIST_ONLY" -eq 1 ]; then
    echo "mode: --persist-only (no packages, no key changes, no sshd_config edits)"
fi

# --- 1. Packages ------------------------------------------------------------

if [ "$PERSIST_ONLY" -eq 0 ]; then
    pkg update -y >/dev/null 2>&1 || warn "pkg update failed (offline?), continuing"
    # procps supplies pgrep/pkill, which the persistence layer uses to hand the
    # listener over from a hand-started sshd to the supervised one.
    for p in openssh termux-services termux-api procps; do
        if pkg list-installed 2>/dev/null | grep -q "^$p/"; then
            echo "ok: $p already installed"
        else
            echo "installing $p ..."
            pkg install -y "$p" || fail "failed to install $p"
        fi
    done

    command -v sshd >/dev/null || fail "sshd not on PATH after installing openssh"

    # Host keys are generated on first sshd start; make sure they exist now so
    # the fingerprint printed at the end is the real one.
    if [ ! -f "$PREFIX/etc/ssh/ssh_host_ed25519_key" ]; then
        echo "generating host keys ..."
        ssh-keygen -A || warn "ssh-keygen -A failed; sshd will generate keys on first start"
    fi
fi

# --- 2. Authorized key ------------------------------------------------------

if [ "$PERSIST_ONLY" -eq 0 ]; then
    if [ -z "$WORKSTATION_KEY" ]; then
        warn "YGG_SSHD_AUTHORIZED_KEY is not set - skipping the authorized_keys step."
        warn "Set it in $ENV_FILE (see android/config/ygg_client.env.example)."
    else
        mkdir -p "$HOME/.ssh"
        chmod 700 "$HOME/.ssh"
        AK="$HOME/.ssh/authorized_keys"
        [ -f "$AK" ] || : > "$AK"
        cp "$AK" "$AK.bak-$STAMP"

        KEY_BODY="$(printf '%s\n' "$WORKSTATION_KEY" | awk '{print $2}')"
        if [ -n "$ALLOWED_SOURCES" ]; then
            KEY_LINE="from=\"$ALLOWED_SOURCES\" $WORKSTATION_KEY"
        else
            warn "YGG_SSHD_ALLOWED_SOURCES is empty - the key is authorized from ANY address"
            KEY_LINE="$WORKSTATION_KEY"
        fi

        if grep -qF "$KEY_BODY" "$AK"; then
            # Already present in some form - rewrite it with the restriction.
            grep -vF "$KEY_BODY" "$AK" > "$AK.new"
            printf '%s\n' "$KEY_LINE" >> "$AK.new"
            mv "$AK.new" "$AK"
            echo "ok: workstation key re-pinned"
        else
            printf '%s\n' "$KEY_LINE" >> "$AK"
            echo "ok: workstation key added"
        fi
        chmod 600 "$AK"

        # Report any OTHER authorized key. grep -F for the key body: it is
        # base64 and contains + and /, which are regex metacharacters.
        OTHERS="$(grep -vE '^[[:space:]]*(#|$)' "$AK" | grep -vF "$KEY_BODY" || true)"
        if [ -n "$OTHERS" ]; then
            warn "other key(s) are authorized on this device - review them:"
            printf '%s\n' "$OTHERS" | sed 's/^/         /'
        fi
    fi
fi

# --- 3. sshd_config hardening ----------------------------------------------

if [ "$PERSIST_ONLY" -eq 0 ]; then
    [ -f "$SSHD_CONF" ] || fail "missing $SSHD_CONF"
    cp "$SSHD_CONF" "$SSHD_CONF.bak-$STAMP"

    # Base = current config minus any block we wrote before.
    BASE="$SSHD_CONF.base.$$"
    awk -v b="$MARK_BEGIN" -v e="$MARK_END" '
        $0 == b { skip = 1 } skip != 1 { print } $0 == e { skip = 0 }
    ' "$SSHD_CONF" > "$BASE"

    # Core block: the part that actually matters (no password auth, one user,
    # modest DoS limits). Never contains an algorithm name, so it parses on any
    # openssh build.
    core_block() {
        cat <<EOF
$MARK_BEGIN
# Written by yggclient android/scripts/setup-sshd-service.sh on $STAMP.
# Rollback: delete this block, or restore $SSHD_CONF.bak-$STAMP
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitEmptyPasswords no
PubkeyAuthentication yes
AuthenticationMethods publickey
AllowUsers $USER_NAME
MaxAuthTries 3
LoginGraceTime 20
X11Forwarding no
AllowAgentForwarding no
AllowTcpForwarding local
GatewayPorts no
PermitTunnel no
PrintMotd no
EOF
    }

    # Full block: core + modern-crypto pinning. Tried first, dropped
    # automatically if this openssh build does not know an algorithm name.
    full_block() {
        core_block
        cat <<'EOF'
KexAlgorithms mlkem768x25519-sha256,sntrup761x25519-sha512@openssh.com,curve25519-sha256,curve25519-sha256@libssh.org
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,umac-128-etm@openssh.com
HostKeyAlgorithms ssh-ed25519,rsa-sha2-512,rsa-sha2-256
PubkeyAcceptedAlgorithms ssh-ed25519,rsa-sha2-512,rsa-sha2-256
EOF
        printf '%s\n' "$MARK_END"
    }

    core_only() {
        core_block
        printf '%s\n' "$MARK_END"
    }

    CAND="$SSHD_CONF.candidate.$$"
    install_if_valid() {
        # $1 = generator function name
        { cat "$BASE"; "$1"; } > "$CAND"
        if sshd -t -f "$CAND" 2>/dev/null; then
            cat "$CAND" > "$SSHD_CONF"
            rm -f "$CAND"
            return 0
        fi
        rm -f "$CAND"
        return 1
    }

    if install_if_valid full_block; then
        echo "ok: hardening applied (key-only auth + modern crypto pinning)"
    elif install_if_valid core_only; then
        warn "this openssh build rejected the crypto pinning - applied the core block only"
    else
        warn "generated config failed 'sshd -t' - leaving $SSHD_CONF unchanged"
        sshd -t -f "$SSHD_CONF" || warn "the EXISTING config also fails validation, look at it"
    fi
    rm -f "$BASE"
fi

# --- 4. The persistence layer ----------------------------------------------

mkdir -p "$HOME/.local/bin" "$HOME/.termux/boot" "$JOBS_DIR" \
         "$PREFIX/etc/apt/apt.conf.d"

# 4a. The one enforcement routine.
cat > "$ENSURE" <<'ENSURE_EOF'
#!/data/data/com.termux/files/usr/bin/bash
# ygg-sshd-ensure - assert that Termux sshd is listening, and that runit owns
# it. Installed by yggclient android/scripts/setup-sshd-service.sh.
#
#   ygg-sshd-ensure [trigger]      trigger: boot | apt | watchdog | manual
#
# ONE enforcement routine, three independent triggers: the Termux:Boot hook, an
# apt post-invoke hook, and a persisted job-scheduler watchdog. Idempotent,
# cheap, and safe to run while a session is connected through the sshd it is
# fixing.
#
# WHY: $PREFIX/var/service/sshd/down is shipped BY the openssh package and is
# NOT a dpkg conffile, so dpkg restores it on every upgrade and silently
# reverts `sv-enable sshd`. Enabling the service once is not durable - the
# state has to be RE-ASSERTED, which is this script's whole job.

set -uo pipefail

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
HOME="${HOME:-/data/data/com.termux/files/home}"
export PREFIX HOME
export PATH="$PREFIX/bin:$PREFIX/bin/applets:$PATH"
export SVDIR="$PREFIX/var/service"
export LOGDIR="$PREFIX/var/log"

PORT="${YGG_SSHD_PORT:-8022}"
SERVICE=sshd
TRIGGER="${1:-manual}"
LOG="$HOME/.local/state/ygg_client/sshd-ensure.log"

mkdir -p "$(dirname "$LOG")"
# Keep the log bounded; it is written from a watchdog that runs every 15 min.
if [ -f "$LOG" ] && [ "$(wc -c < "$LOG" 2>/dev/null || echo 0)" -gt 262144 ]; then
    tail -n 400 "$LOG" > "$LOG.trim" 2>/dev/null && mv "$LOG.trim" "$LOG"
fi
log() { printf '%s [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$TRIGGER" "$*" >> "$LOG"; }

# Triggers overlap in practice: the 15-minute watchdog fires while an apt run
# or a manual converge is already in flight. Two concurrent handovers race -
# one `pkill -x sshd` can kill the sshd the other just started. Observed live
# on a phone where [manual] and [watchdog] both handed the port over in the
# same second. Serialize them; a trigger that cannot take the lock has nothing
# to add, because the holder is asserting the very same state.
LOCK="$HOME/.local/state/ygg_client/sshd-ensure.lock"
if command -v flock >/dev/null 2>&1; then
    exec 9>"$LOCK" 2>/dev/null || true
    if ! flock -w 45 9 2>/dev/null; then
        log "another trigger holds the lock - it is asserting the same state, exiting"
        exit 0
    fi
fi

# ⛔ A TCP ACCEPT IS NOT A WORKING sshd, and the difference has already cost a
# remote phone. Since OpenSSH 9.8 the listener execs libexec/sshd-session for
# every connection. Upgrade openssh under a running listener and the old binary
# in memory starts exec'ing the NEW helper from disk: the port still accepts,
# and every connection dies at kex_exchange_identification. Measured on a phone
# in exactly that state - `exec 3<>/dev/tcp/host/8022` succeeded while the
# banner read returned nothing. So health means "sent me an SSH- banner", never
# "accepted my connection".
port_open() { timeout 3 bash -c "exec 3<>/dev/tcp/127.0.0.1/$PORT" 2>/dev/null; }

banner() {
    timeout 6 bash -c "
        exec 3<>/dev/tcp/127.0.0.1/$PORT 2>/dev/null || exit 1
        read -t 4 -r line <&3 || exit 1
        printf '%s' \"\$line\"
    " 2>/dev/null
}

healthy() { case "$(banner)" in SSH-*) return 0 ;; *) return 1 ;; esac; }

wait_healthy() {
    i=0
    while [ "$i" -lt "${1:-20}" ]; do
        healthy && return 0
        sleep 1
        i=$((i + 1))
    done
    return 1
}

# runsv is alive iff `sv status` answers with a real state line. When the
# supervisor is gone it answers "warning: ...: unable to open supervise/ok".
sv_state() { sv status "$SERVICE" 2>&1 | head -1; }
supervised() { sv_state | grep -qE '^(run|down):'; }
running_under_runit() { sv_state | grep -q '^run:'; }

# --- 1. the supervisor ------------------------------------------------------

if ! supervised; then
    log "runsvdir/runsv not answering - starting the service supervisor"
    if [ -f "$PREFIX/etc/profile.d/start-services.sh" ]; then
        # shellcheck disable=SC1091
        . "$PREFIX/etc/profile.d/start-services.sh"
    else
        (setsid runsvdir "$SVDIR" >/dev/null 2>&1 &)
    fi
    # runsv needs a moment to create supervise/ok before sv can talk to it.
    i=0
    while [ "$i" -lt 10 ] && ! supervised; do sleep 1; i=$((i + 1)); done
    supervised || log "WARNING: supervisor still not answering: $(sv_state)"
fi

# --- 2. re-assert the enabled state ----------------------------------------

if [ -e "$SVDIR/$SERVICE/down" ]; then
    if rm -f "$SVDIR/$SERVICE/down"; then
        log "removed $SVDIR/$SERVICE/down (a package upgrade had restored it)"
    fi
fi

# --- 3. a listener that accepts but does not speak SSH is broken -----------
# This is the apt case above all: at DPkg::Post-Invoke time the old listener is
# still in memory with a new sshd-session on disk, so catching it here is what
# stops an openssh upgrade from stranding a phone nobody can reach.

if port_open && ! healthy; then
    log "WARNING: port $PORT accepts but sends no SSH banner - the listener is broken"
    if running_under_runit; then
        log "restarting the supervised $SERVICE (its binary was probably replaced under it)"
        sv restart "$SERVICE" >/dev/null 2>&1
    else
        log "killing the broken unsupervised listener"
        command -v pkill >/dev/null 2>&1 && pkill -x sshd 2>/dev/null
        sv up "$SERVICE" >/dev/null 2>&1
    fi
    sleep 3
fi

# --- 4. bring it up ---------------------------------------------------------

if healthy; then
    if running_under_runit; then
        log "ok: runit owns $SERVICE, port $PORT healthy ($(banner))"
        exit 0
    fi
    # Something answers but runit is not it: an unsupervised sshd, hand-started
    # to work around this very bug. It does NOT come back after a reboot, so
    # hand the port over - except under apt, where the caller may be connected
    # through it and a package run is no place to juggle listeners.
    if [ "$TRIGGER" = apt ]; then
        log "note: port $PORT held by an unsupervised sshd; leaving it alone under apt"
        exit 0
    fi
    if command -v pkill >/dev/null 2>&1; then
        log "port $PORT held by an unsupervised sshd - handing over to runit"
        # -x matches the listener only. Per-connection children are named
        # sshd-session, so an ssh session running this script survives.
        pkill -x sshd 2>/dev/null
        sleep 1
    else
        log "WARNING: pkill missing (install procps) - cannot hand the port over"
        exit 0
    fi
fi

sv up "$SERVICE" >/dev/null 2>&1
if wait_healthy 20 && running_under_runit; then
    log "ok: $SERVICE up under runit, port $PORT healthy ($(banner))"
    exit 0
fi

# --- 5. last resort ---------------------------------------------------------
# Never leave the phone with no route in. A bare sshd is not boot-persistent,
# but it beats no sshd, and the next trigger will try runit again.

log "WARNING: runit did not deliver a healthy $PORT (state: $(sv_state)) - starting a bare sshd"
command -v pkill >/dev/null 2>&1 && pkill -x sshd 2>/dev/null
sleep 1
sshd >>"$LOG" 2>&1
if wait_healthy 15; then
    log "ok: bare sshd listening on $PORT - NOT supervised, see $LOGDIR/sv/$SERVICE/current"
    exit 0
fi
log "ERROR: nothing is listening on $PORT"
exit 1
ENSURE_EOF
chmod 700 "$ENSURE"
echo "ok: enforcement routine at $ENSURE"

# 4b. Trigger: Termux:Boot.
# The 00- prefix matters - Termux:Boot runs its hooks in alphabetical order and
# the yggsync hook sleeps 30s, so sshd must come up first.
cat > "$HOME/.termux/boot/00-start-services" <<'BOOT_EOF'
#!/data/data/com.termux/files/usr/bin/sh
# Installed by yggclient android/scripts/setup-sshd-service.sh.
# This hook does NOT merely start the supervisor and hope: `sv-enable sshd` is
# not durable, because the openssh package re-ships var/service/sshd/down on
# every upgrade. The desired state is re-asserted here, at every boot.
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
HOME="${HOME:-/data/data/com.termux/files/home}"
export PREFIX HOME
export PATH="$PREFIX/bin:$PATH"
termux-wake-lock
exec "$HOME/.local/bin/ygg-sshd-ensure" boot
BOOT_EOF
chmod 700 "$HOME/.termux/boot/00-start-services"
echo "ok: Termux:Boot hook at $HOME/.termux/boot/00-start-services"

if command -v pm >/dev/null && ! pm list packages 2>/dev/null | grep -q com.termux.boot; then
    warn "the Termux:Boot APP is not installed - install it from F-Droid, then open it once"
fi

# 4c. Trigger: apt. Reconverge the moment a package run finishes, instead of
# discovering the regression at the next reboot.
cat > "$PREFIX/etc/apt/apt.conf.d/99-yggclient-sshd-ensure" <<APT_EOF
// Installed by yggclient android/scripts/setup-sshd-service.sh.
// The openssh package ships \$PREFIX/var/service/sshd/down and it is NOT a dpkg
// conffile, so dpkg restores it on every upgrade and silently reverts
// \`sv-enable sshd\`. Re-assert the state as soon as the package run finishes.
DPkg::Post-Invoke { "HOME=$HOME $ENSURE apt >/dev/null 2>&1 || true"; };
APT_EOF
echo "ok: apt post-invoke hook at $PREFIX/etc/apt/apt.conf.d/99-yggclient-sshd-ensure"

# 4d. Trigger: a persisted job-scheduler watchdog. Android's JobScheduler is a
# different mechanism from Termux:Boot, so this heals the phone even if the boot
# hook never fires or Android kills runsvdir mid-life.
cat > "$JOBS_DIR/sshd-watchdog.sh" <<WATCHDOG_EOF
#!/data/data/com.termux/files/usr/bin/sh
# Installed by yggclient android/scripts/setup-sshd-service.sh.
exec $ENSURE watchdog
WATCHDOG_EOF
chmod 700 "$JOBS_DIR/sshd-watchdog.sh"

if command -v termux-job-scheduler >/dev/null 2>&1; then
    # --battery-not-low false on purpose: a phone on a low battery is exactly
    # when you still want a route in.
    if termux-job-scheduler --script "$JOBS_DIR/sshd-watchdog.sh" \
            --job-id "$WATCHDOG_JOB_ID" --period-ms "$WATCHDOG_PERIOD_MS" \
            --persisted true --battery-not-low false >/dev/null 2>&1; then
        echo "ok: watchdog registered as job $WATCHDOG_JOB_ID (every ${WATCHDOG_PERIOD_MS}ms, persisted)"
    else
        warn "could not register the watchdog job - is the Termux:API app installed and allowed?"
    fi
else
    warn "termux-job-scheduler missing (pkg install termux-api) - no watchdog registered"
fi

# --- 5. Converge now and verify --------------------------------------------

if [ -n "${SSH_CONNECTION:-}" ]; then
    # Over ssh the handover kills the listener this session arrived through.
    # OpenSSH keeps established sessions alive when the listener dies (children
    # are sshd-session, not sshd), but detach anyway so a dropped connection
    # cannot abort the handover half-done.
    echo "note: running over ssh - converging detached so a dropped session cannot abort it"
    setsid nohup "$ENSURE" manual >/dev/null 2>&1 </dev/null &
    sleep 8
else
    "$ENSURE" manual
fi

echo
echo "=== result ==="
SVDIR="$PREFIX/var/service" sv status sshd 2>&1 || warn "sv status sshd failed"
# Read the banner, not just the accept - see the note in ygg-sshd-ensure.
RESULT_BANNER="$(timeout 6 bash -c "
    exec 3<>/dev/tcp/127.0.0.1/$PORT 2>/dev/null || exit 1
    read -t 4 -r line <&3 || exit 1
    printf '%s' \"\$line\"" 2>/dev/null)"
case "$RESULT_BANNER" in
    SSH-*) echo "ok: sshd is healthy on $PORT ($RESULT_BANNER)" ;;
    "")    warn "nothing usable on $PORT - check $PREFIX/var/log/sv/sshd/current" ;;
    *)     warn "$PORT answered but not with an SSH banner: $RESULT_BANNER" ;;
esac
echo "--- last enforcement log lines ---"
tail -5 "$HOME/.local/state/ygg_client/sshd-ensure.log" 2>/dev/null

if [ "$PERSIST_ONLY" -eq 0 ]; then
    echo
    echo "=== identity (give this to the workstation) ==="
    echo "user:        $USER_NAME"
    echo "model:       $(getprop ro.product.model 2>/dev/null) / $(getprop ro.product.device 2>/dev/null)"
    echo "android:     $(getprop ro.build.version.release 2>/dev/null)  build $(getprop ro.build.display.id 2>/dev/null)"
    echo "openssh:     $(ssh -V 2>&1)"
    echo "host key:    $(ssh-keygen -lf "$PREFIX/etc/ssh/ssh_host_ed25519_key.pub" 2>/dev/null)"
fi

echo
echo "Reboot the phone once to prove the Termux:Boot hook works."
echo "Android Settings -> Apps -> Termux / Termux:API / Termux:Boot -> Battery -> Unrestricted"
echo "is required, or Android eventually kills the supervisor."
echo "If the phone must be reachable away from the LAN, its VPN app needs to be"
echo "always-on too - a boot-persistent sshd on an unreachable address is still"
echo "an unreachable phone."
