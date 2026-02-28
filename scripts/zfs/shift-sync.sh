#!/usr/bin/env bash
set -euo pipefail

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2
}

die() {
  log "ERROR: $*"
  exit 1
}

usage() {
  cat <<'USAGE'
Usage:
  shift-sync.sh [push|pull] [options]

Options:
  --remote HOST              Remote SSH target (default: SHIFT_REMOTE or root@build-host.example)
  --identity NAME            Host identity token used by {identity} placeholders
  --src DATASET              Source dataset path
  --dst DATASET              Destination dataset path
  --mode MODE                auto|full|incremental (default: auto)
  --snapshot-prefix PREFIX   Snapshot prefix (default: shift)
  --send-flags "..."         zfs send flags (default: -Rw)
  --recv-flags "..."         zfs recv flags (default: -uF)
  --ssh-opts "..."           Extra ssh options (example: -i /home/pi/.ssh/id_ed25519)
  --allow-live-recv          Allow pull recv into mounted local datasets
  --map SRC=DST              Replicate one dataset mapping; repeatable
  --no-recursive             Snapshot without -r
  --dry-run                  Print commands without executing
  -h, --help                 Show this help

Environment overrides:
  SHIFT_ACTION, SHIFT_REMOTE, SHIFT_IDENTITY, SHIFT_SRC_DATASET, SHIFT_DST_DATASET,
  SHIFT_DATASET_MAPS,
  SHIFT_SSH_OPTS,
  SHIFT_ALLOW_LIVE_RECV,
  SHIFT_MODE, SHIFT_SNAPSHOT_PREFIX, SHIFT_SEND_FLAGS, SHIFT_RECV_FLAGS,
  SHIFT_RECURSIVE, SHIFT_DRY_RUN

Examples:
  sudo scripts/zfs/shift-sync.sh push --identity client-a --src rpool/ROOT/debian --dst zfs/lxc/client-a/ROOT/debian
  sudo scripts/zfs/shift-sync.sh pull --identity client-a --src zfs/lxc/client-a/ROOT/debian --dst rpool/ROOT/debian
  sudo scripts/zfs/shift-sync.sh push --map zroot/ROOT/debian=zroot/lxc/client-a/ROOT/debian --map zroot/home/pi=zroot/lxc/client-a/ROOT/home/pi
USAGE
}

contains() {
  local needle="$1"
  shift || true
  local item
  for item in "$@"; do
    if [[ "$item" == "$needle" ]]; then
      return 0
    fi
  done
  return 1
}

dataset_exists_local() {
  local dataset="$1"
  zfs list -H -o name "$dataset" >/dev/null 2>&1
}

dataset_mounted_local() {
  local dataset="$1"
  zfs get -H -o value mounted "$dataset" 2>/dev/null | grep -qx yes
}

assert_safe_pull_destination() {
  local dataset="$1"
  if [[ "$ALLOW_LIVE_RECV" == "1" ]]; then
    return 0
  fi
  if dataset_exists_local "$dataset" && dataset_mounted_local "$dataset"; then
    die "Refusing live pull recv into mounted local dataset '${dataset}'. Run from rescue/live environment or set SHIFT_ALLOW_LIVE_RECV=1 explicitly."
  fi
}

expand_identity() {
  local value="$1"
  printf '%s\n' "${value//\{identity\}/$IDENTITY}"
}

list_snapshots_local() {
  local dataset="$1"
  zfs list -H -t snapshot -o name -s creation -r "$dataset" \
    | awk -F'@' -v ds="$dataset" '$1 == ds {print $2}'
}

list_snapshots_remote() {
  local dataset="$1"
  ssh -n "${SSH_ARGS[@]}" "$REMOTE" zfs list -H -t snapshot -o name -s creation -r "$dataset" \
    | awk -F'@' -v ds="$dataset" '$1 == ds {print $2}'
}

latest_common_snapshot() {
  local src_loc="$1"
  local src_dataset="$2"
  local dst_loc="$3"
  local dst_dataset="$4"
  local -a src_snaps=()
  local -a dst_snaps=()
  local snap

  if [[ "$src_loc" == "local" ]]; then
    mapfile -t src_snaps < <(list_snapshots_local "$src_dataset")
  else
    mapfile -t src_snaps < <(list_snapshots_remote "$src_dataset")
  fi

  if [[ "$dst_loc" == "local" ]]; then
    mapfile -t dst_snaps < <(list_snapshots_local "$dst_dataset")
  else
    mapfile -t dst_snaps < <(list_snapshots_remote "$dst_dataset")
  fi

  declare -A dst_map=()
  for snap in "${dst_snaps[@]}"; do
    dst_map["$snap"]=1
  done

  local i
  for ((i = ${#src_snaps[@]} - 1; i >= 0; i--)); do
    snap="${src_snaps[$i]}"
    if [[ "$snap" == "${SNAPSHOT_PREFIX}-"* ]] && [[ -n "${dst_map[$snap]:-}" ]]; then
      printf '%s\n' "$snap"
      return 0
    fi
  done

  return 1
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

run_pipe_push() {
  local snap_name="$1"
  local common="${2:-}"

  local -a send_arr=(zfs send)
  local -a recv_arr=(ssh "${SSH_ARGS[@]}" "$REMOTE" zfs recv)
  local -a tmp_arr=()

  read -r -a tmp_arr <<< "$SEND_FLAGS"
  send_arr+=("${tmp_arr[@]}")

  if [[ -n "$common" ]]; then
    send_arr+=(-I "@${common}" "${SRC_DATASET}@${snap_name}")
  else
    send_arr+=("${SRC_DATASET}@${snap_name}")
  fi

  read -r -a tmp_arr <<< "$RECV_FLAGS"
  recv_arr+=("${tmp_arr[@]}" "$DST_DATASET")

  if [[ "$DRY_RUN" == "1" ]]; then
    printf '[DRY-RUN] ' >&2
    printf '%q ' "${send_arr[@]}" >&2
    printf '| ' >&2
    printf '%q ' "${recv_arr[@]}" >&2
    printf '\n' >&2
    return 0
  fi

  "${send_arr[@]}" | "${recv_arr[@]}"
}

run_pipe_pull() {
  local snap_name="$1"
  local common="${2:-}"

  local -a send_arr=(ssh "${SSH_ARGS[@]}" "$REMOTE" zfs send)
  local -a recv_arr=(zfs recv)
  local -a tmp_arr=()

  read -r -a tmp_arr <<< "$SEND_FLAGS"
  send_arr+=("${tmp_arr[@]}")

  if [[ -n "$common" ]]; then
    send_arr+=(-I "@${common}" "${SRC_DATASET}@${snap_name}")
  else
    send_arr+=("${SRC_DATASET}@${snap_name}")
  fi

  read -r -a tmp_arr <<< "$RECV_FLAGS"
  recv_arr+=("${tmp_arr[@]}" "$DST_DATASET")

  if [[ "$DRY_RUN" == "1" ]]; then
    printf '[DRY-RUN] ' >&2
    printf '%q ' "${send_arr[@]}" >&2
    printf '| ' >&2
    printf '%q ' "${recv_arr[@]}" >&2
    printf '\n' >&2
    return 0
  fi

  "${send_arr[@]}" | "${recv_arr[@]}"
}

ACTION="${SHIFT_ACTION:-push}"
REMOTE="${SHIFT_REMOTE:-root@build-host.example}"
IDENTITY="${SHIFT_IDENTITY:-$(hostname -s)}"
SRC_DATASET="${SHIFT_SRC_DATASET:-}"
DST_DATASET="${SHIFT_DST_DATASET:-}"
DATASET_MAPS="${SHIFT_DATASET_MAPS:-}"
MODE="${SHIFT_MODE:-auto}"
SNAPSHOT_PREFIX="${SHIFT_SNAPSHOT_PREFIX:-shift}"
SEND_FLAGS="${SHIFT_SEND_FLAGS:--Rw}"
RECV_FLAGS="${SHIFT_RECV_FLAGS:--uF}"
SSH_OPTS="${SHIFT_SSH_OPTS:-}"
ALLOW_LIVE_RECV="${SHIFT_ALLOW_LIVE_RECV:-0}"
RECURSIVE="${SHIFT_RECURSIVE:-1}"
DRY_RUN="${SHIFT_DRY_RUN:-0}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    push|pull)
      ACTION="$1"
      shift
      ;;
    --remote)
      REMOTE="$2"
      shift 2
      ;;
    --identity)
      IDENTITY="$2"
      shift 2
      ;;
    --src)
      SRC_DATASET="$2"
      shift 2
      ;;
    --dst)
      DST_DATASET="$2"
      shift 2
      ;;
    --mode)
      MODE="$2"
      shift 2
      ;;
    --snapshot-prefix)
      SNAPSHOT_PREFIX="$2"
      shift 2
      ;;
    --send-flags)
      SEND_FLAGS="$2"
      shift 2
      ;;
    --recv-flags)
      RECV_FLAGS="$2"
      shift 2
      ;;
    --ssh-opts)
      SSH_OPTS="$2"
      shift 2
      ;;
    --allow-live-recv)
      ALLOW_LIVE_RECV="1"
      shift
      ;;
    --map)
      if [[ -n "$DATASET_MAPS" ]]; then
        DATASET_MAPS+=$'\n'
      fi
      DATASET_MAPS+="$2"
      shift 2
      ;;
    --no-recursive)
      RECURSIVE="0"
      shift
      ;;
    --dry-run)
      DRY_RUN="1"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
done

contains "$ACTION" push pull || die "Action must be push or pull"
contains "$MODE" auto full incremental || die "Mode must be auto, full, or incremental"

declare -a SSH_ARGS=()
if [[ -n "$SSH_OPTS" ]]; then
  read -r -a SSH_ARGS <<< "$SSH_OPTS"
fi

if [[ -z "$DATASET_MAPS" ]]; then
  if [[ -z "$SRC_DATASET" ]]; then
    if [[ "$ACTION" == "push" ]]; then
      SRC_DATASET="rpool/ROOT/debian"
    else
      SRC_DATASET="zfs/lxc/{identity}/ROOT/debian"
    fi
  fi

  if [[ -z "$DST_DATASET" ]]; then
    if [[ "$ACTION" == "push" ]]; then
      DST_DATASET="zfs/lxc/{identity}/ROOT/debian"
    else
      DST_DATASET="rpool/ROOT/debian"
    fi
  fi

  DATASET_MAPS="${SRC_DATASET}=${DST_DATASET}"
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
SNAP_NAME="${SNAPSHOT_PREFIX}-${STAMP}"
SNAP_RECURSE_FLAG=""
if [[ "$RECURSIVE" == "1" ]]; then
  SNAP_RECURSE_FLAG="-r"
fi

log "Action=${ACTION} identity=${IDENTITY} mode=${MODE} remote=${REMOTE}"

replicate_pair() {
  local src_raw="$1"
  local dst_raw="$2"
  SRC_DATASET="$(expand_identity "$src_raw")"
  DST_DATASET="$(expand_identity "$dst_raw")"
  local snap_arg="${SRC_DATASET}@${SNAP_NAME}"

  log "Source=${SRC_DATASET} Destination=${DST_DATASET} Snapshot=${SNAP_NAME}"

  if [[ "$ACTION" == "push" ]]; then
    run_cmd zfs snapshot ${SNAP_RECURSE_FLAG:+$SNAP_RECURSE_FLAG} "$snap_arg"

    local common=""
    if [[ "$DRY_RUN" == "1" && "$MODE" != "full" ]]; then
      log "Dry-run: skipping common snapshot discovery; previewing full send"
    elif [[ "$MODE" != "full" ]]; then
      if common="$(latest_common_snapshot local "$SRC_DATASET" remote "$DST_DATASET" 2>/dev/null)"; then
        log "Using incremental base snapshot: ${common}"
      else
        if [[ "$MODE" == "incremental" ]]; then
          die "No common ${SNAPSHOT_PREFIX}-* snapshot found for incremental send (${SRC_DATASET})"
        fi
        log "No common ${SNAPSHOT_PREFIX}-* snapshot found; falling back to full send"
      fi
    fi

    run_pipe_push "$SNAP_NAME" "$common"
    log "Push complete for ${SRC_DATASET}"
  else
    assert_safe_pull_destination "$DST_DATASET"
    run_cmd ssh -n "${SSH_ARGS[@]}" "$REMOTE" zfs snapshot ${SNAP_RECURSE_FLAG:+$SNAP_RECURSE_FLAG} "$snap_arg"

    local common=""
    if [[ "$DRY_RUN" == "1" && "$MODE" != "full" ]]; then
      log "Dry-run: skipping common snapshot discovery; previewing full send"
    elif [[ "$MODE" != "full" ]]; then
      if common="$(latest_common_snapshot remote "$SRC_DATASET" local "$DST_DATASET" 2>/dev/null)"; then
        log "Using incremental base snapshot: ${common}"
      else
        if [[ "$MODE" == "incremental" ]]; then
          die "No common ${SNAPSHOT_PREFIX}-* snapshot found for incremental receive (${SRC_DATASET})"
        fi
        log "No common ${SNAPSHOT_PREFIX}-* snapshot found; falling back to full send"
      fi
    fi

    run_pipe_pull "$SNAP_NAME" "$common"
    log "Pull complete for ${SRC_DATASET}"
  fi
}

NL=$'\n'
MAP_INPUT=${DATASET_MAPS//,/$NL}

while IFS= read -r map_line; do
  map_line="${map_line#"${map_line%%[![:space:]]*}"}"
  map_line="${map_line%"${map_line##*[![:space:]]}"}"
  [[ -z "$map_line" ]] && continue
  [[ "$map_line" == \#* ]] && continue

  if [[ "$map_line" != *"="* ]]; then
    die "Invalid map entry '${map_line}'. Expected SRC=DST"
  fi

  src_map="${map_line%%=*}"
  dst_map="${map_line#*=}"
  [[ -z "$src_map" || -z "$dst_map" ]] && die "Invalid map entry '${map_line}'. Expected SRC=DST"

  replicate_pair "$src_map" "$dst_map"
done <<< "$MAP_INPUT"
