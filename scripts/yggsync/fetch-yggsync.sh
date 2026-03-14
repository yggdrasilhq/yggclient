#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-${YGGSYNC_VERSION:-v0.1.3}}"
ARCH="${ARCH:-amd64}"
OS="${OS:-linux}"
OUT="${OUT:-${HOME}/.local/bin/yggsync}"
SRC_DIR="${SRC_DIR:-${HOME}/gh/yggsync}"
URL="https://g.gour.top/yggdrasilhq/yggsync/releases/download/${VERSION}/yggsync-${OS}-${ARCH}"
ALLOW_BUILD_FALLBACK="${ALLOW_BUILD_FALLBACK:-0}"

log() { printf "[%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }

mkdir -p "$(dirname "$OUT")"
tmp="${OUT}.download"

log "Downloading yggsync ${VERSION} (${OS}/${ARCH}) from ${URL}"
if curl -L --fail --silent --show-error "$URL" -o "$tmp"; then
  chmod +x "$tmp"
  mv "$tmp" "$OUT"
  log "Installed to $OUT"
  exit 0
fi

if [[ "$ALLOW_BUILD_FALLBACK" -eq 1 ]]; then
  log "Release not found; attempting local build from ${SRC_DIR}"
  if [[ ! -d "$SRC_DIR" ]]; then
    echo "Source dir ${SRC_DIR} not found; cannot build fallback." >&2
    exit 1
  fi
  pushd "$SRC_DIR" >/dev/null
  if GOOS="$OS" GOARCH="$ARCH" CGO_ENABLED=0 go build -o "$tmp" ./cmd/yggsync; then
    popd >/dev/null
    chmod +x "$tmp"
    mv "$tmp" "$OUT"
    log "Built and installed to $OUT"
    exit 0
  fi
  popd >/dev/null
  echo "Failed to build yggsync from ${SRC_DIR}" >&2
  exit 1
fi

echo "Release asset yggsync-${OS}-${ARCH} not found for tag ${VERSION}. Publish a release to g.gour.top/yggdrasilhq/yggsync or set ALLOW_BUILD_FALLBACK=1 on a build host." >&2
exit 1
