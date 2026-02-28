#!/usr/bin/env bash
set -euo pipefail

log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }

contains() {
  local needle="$1"; shift || true
  local v
  for v in "$@"; do [[ "$v" == "$needle" ]] && return 0; done
  return 1
}

expand_identity() {
  local value="$1"
  printf '%s\n' "${value//\{identity\}/$IDENTITY}"
}

run_cmd() {
  if [[ "$DRY_RUN" == "1" ]]; then
    printf '[DRY-RUN] ' >&2
    printf '%q ' "$@" >&2
    printf '\n' >&2
    return 0
  fi
  "$@"
}

prune_local_dataset() {
  local dataset="$1" keep="$2"
  local -a snaps=()
  local s
  if ! zfs list -H -o name "$dataset" >/dev/null 2>&1; then
    log "Local ${dataset}: dataset missing, skipping"
    return 0
  fi
  mapfile -t snaps < <(zfs list -H -t snapshot -o name -s creation -r "$dataset" | awk -F'@' -v ds="$dataset" -v p="$SNAPSHOT_PREFIX" '$1==ds && index($2,p"-")==1 {print $2}')
  local count="${#snaps[@]}"
  if (( count <= keep )); then
    log "Local ${dataset}: ${count} snapshots <= keep(${keep}), nothing to prune"
    return 0
  fi
  local remove_count=$((count - keep))
  log "Local ${dataset}: pruning ${remove_count} old snapshots (keep ${keep})"
  local i
  for ((i=0; i<remove_count; i++)); do
    s="${snaps[$i]}"
    run_cmd zfs destroy "${dataset}@${s}"
  done
}

prune_remote_dataset() {
  local dataset="$1" keep="$2"
  local -a snaps=()
  local s
  if ! ssh -n "${SSH_ARGS[@]}" "$REMOTE" zfs list -H -o name "$dataset" >/dev/null 2>&1; then
    log "Remote ${dataset}: dataset missing, skipping"
    return 0
  fi
  mapfile -t snaps < <(ssh -n "${SSH_ARGS[@]}" "$REMOTE" zfs list -H -t snapshot -o name -s creation -r "$dataset" | awk -F'@' -v ds="$dataset" -v p="$SNAPSHOT_PREFIX" '$1==ds && index($2,p"-")==1 {print $2}')
  local count="${#snaps[@]}"
  if (( count <= keep )); then
    log "Remote ${dataset}: ${count} snapshots <= keep(${keep}), nothing to prune"
    return 0
  fi
  local remove_count=$((count - keep))
  log "Remote ${dataset}: pruning ${remove_count} old snapshots (keep ${keep})"
  local i
  for ((i=0; i<remove_count; i++)); do
    s="${snaps[$i]}"
    if [[ "$DRY_RUN" == "1" ]]; then
      printf '[DRY-RUN] ' >&2
      printf '%q ' ssh -n "${SSH_ARGS[@]}" "$REMOTE" zfs destroy "${dataset}@${s}" >&2
      printf '\n' >&2
    else
      ssh -n "${SSH_ARGS[@]}" "$REMOTE" zfs destroy "${dataset}@${s}"
    fi
  done
}

ACTION="${SHIFT_ACTION:-push}"
REMOTE="${SHIFT_REMOTE:-root@build-host.example}"
IDENTITY="${SHIFT_IDENTITY:-$(hostname -s)}"
DATASET_MAPS="${SHIFT_DATASET_MAPS:-}"
SRC_DATASET="${SHIFT_SRC_DATASET:-}"
DST_DATASET="${SHIFT_DST_DATASET:-}"
SNAPSHOT_PREFIX="${SHIFT_SNAPSHOT_PREFIX:-shift}"
SSH_OPTS="${SHIFT_SSH_OPTS:-}"
PRUNE_KEEP_LOCAL="${SHIFT_PRUNE_KEEP_LOCAL:-48}"
PRUNE_KEEP_REMOTE="${SHIFT_PRUNE_KEEP_REMOTE:-48}"
PRUNE_LOCAL="${SHIFT_PRUNE_LOCAL:-1}"
PRUNE_REMOTE="${SHIFT_PRUNE_REMOTE:-1}"
DRY_RUN="${SHIFT_DRY_RUN:-0}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    push|pull) ACTION="$1"; shift ;;
    --keep-local) PRUNE_KEEP_LOCAL="$2"; shift 2 ;;
    --keep-remote) PRUNE_KEEP_REMOTE="$2"; shift 2 ;;
    --no-local) PRUNE_LOCAL=0; shift ;;
    --no-remote) PRUNE_REMOTE=0; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    *) die "Unknown argument: $1" ;;
  esac
done

contains "$ACTION" push pull || die "Action must be push or pull"

if [[ -z "$DATASET_MAPS" ]]; then
  if [[ -n "$SRC_DATASET" && -n "$DST_DATASET" ]]; then
    DATASET_MAPS="${SRC_DATASET}=${DST_DATASET}"
  else
    die "Set SHIFT_DATASET_MAPS (or SHIFT_SRC_DATASET + SHIFT_DST_DATASET)"
  fi
fi

declare -a SSH_ARGS=()
if [[ -n "$SSH_OPTS" ]]; then
  read -r -a SSH_ARGS <<< "$SSH_OPTS"
fi

NL=$'\n'
MAP_INPUT=${DATASET_MAPS//,/$NL}
while IFS= read -r map_line; do
  map_line="${map_line#"${map_line%%[![:space:]]*}"}"
  map_line="${map_line%"${map_line##*[![:space:]]}"}"
  [[ -z "$map_line" ]] && continue
  [[ "$map_line" == \#* ]] && continue
  [[ "$map_line" == *"="* ]] || die "Invalid map entry '${map_line}'"

  src="${map_line%%=*}"
  dst="${map_line#*=}"
  src="$(expand_identity "$src")"
  dst="$(expand_identity "$dst")"

  if [[ "$ACTION" == "push" ]]; then
    local_ds="$src"
    remote_ds="$dst"
  else
    local_ds="$dst"
    remote_ds="$src"
  fi

  [[ "$PRUNE_LOCAL" == "1" ]] && prune_local_dataset "$local_ds" "$PRUNE_KEEP_LOCAL"
  [[ "$PRUNE_REMOTE" == "1" ]] && prune_remote_dataset "$remote_ds" "$PRUNE_KEEP_REMOTE"

done <<< "$MAP_INPUT"

log "Prune complete"
