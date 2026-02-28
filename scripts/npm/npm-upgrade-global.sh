#!/usr/bin/env bash
set -euo pipefail

npm_bin="${NPM_BIN:-/usr/bin/npm}"
if [[ ! -x "$npm_bin" ]]; then
  if command -v npm >/dev/null 2>&1; then
    npm_bin="$(command -v npm)"
  else
    echo "npm not found in PATH and NPM_BIN is not executable." >&2
    exit 1
  fi
fi

root="$("$npm_bin" root -g)"
if [[ -z "$root" || "$root" == "/" ]]; then
  echo "Invalid npm global root: '$root'" >&2
  exit 1
fi

if [[ ! -d "$root" ]]; then
  echo "npm global root not found: '$root'" >&2
  exit 1
fi

mapfile -d '' dot_dirs < <(
  {
    find "$root" -mindepth 1 -maxdepth 1 -type d -name '.*' ! -name '.bin' -print0
    find "$root" -mindepth 2 -maxdepth 2 -type d -path "$root/@*/.*" ! -name '.bin' -print0
  } | sort -zu
)
if (( ${#dot_dirs[@]} )); then
  echo "Removing invalid global package dirs:"
  printf ' - %s\n' "${dot_dirs[@]}"
  rm -rf -- "${dot_dirs[@]}"
fi

exec "$npm_bin" up -g
