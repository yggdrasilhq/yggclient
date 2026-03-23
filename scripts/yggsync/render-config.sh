#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PROFILE_ENV="${PROFILE_ENV:-${REPO_ROOT}/config/profiles.local.env}"
PLATFORM="${1:-${YGGSYNC_PLATFORM:-desktop}}"
OUT="${OUT:-${HOME}/.config/ygg_sync.toml}"

compute_samba_user() {
  if [[ -n "${SAMBA_USER:-}" ]]; then
    echo "$SAMBA_USER"
    return
  fi
  case "${USER:-}" in
    pi) echo "dada" ;;
    bon) echo "bon" ;;
    maa) echo "maa" ;;
    *) echo "${USER:-user}" ;;
  esac
}

compute_screencasts_remote() {
  local samba_user="$1"
  if [[ -n "${SCREENCASTS_REMOTE:-}" ]]; then
    echo "$SCREENCASTS_REMOTE"
    return
  fi
  if [[ "$samba_user" == "dada" ]]; then
    echo "immich01/Screencasts"
  else
    echo "immich02/${samba_user}/desktop/Screencasts"
  fi
}

case "$PLATFORM" in
  desktop)
    TEMPLATE="${TEMPLATE:-${REPO_ROOT}/config/yggsync/desktop/ygg_sync.toml.template}"
    ;;
  android)
    TEMPLATE="${TEMPLATE:-${REPO_ROOT}/android/config/ygg_sync.toml.template}"
    ;;
  *)
    echo "Unsupported platform: ${PLATFORM}" >&2
    exit 1
    ;;
esac

if [[ -f "$PROFILE_ENV" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$PROFILE_ENV"
  set +a
fi

SAMBA_USER="${SAMBA_USER:-$(compute_samba_user)}"
SAMBA_USERNAME="${SAMBA_USERNAME:-$SAMBA_USER}"
SAMBA_HOST="${SAMBA_HOST:-nas.lan}"
SAMBA_SHARE="${SAMBA_SHARE:-data}"
SAMBA_PASSWORD_ENV="${SAMBA_PASSWORD_ENV:-SAMBA_PASSWORD}"
SCREENCASTS_REMOTE="${SCREENCASTS_REMOTE:-$(compute_screencasts_remote "$SAMBA_USER")}"

export REPO_ROOT USER_HOME="${HOME}" USER_NAME="${USER}" SAMBA_HOST SAMBA_SHARE SAMBA_USER SAMBA_USERNAME SAMBA_PASSWORD_ENV SCREENCASTS_REMOTE

mkdir -p "$(dirname "$OUT")"
envsubst <"$TEMPLATE" >"$OUT"
printf 'Rendered %s from %s\n' "$OUT" "$TEMPLATE"
