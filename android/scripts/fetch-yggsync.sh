#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

VERSION="${1:-${YGGSYNC_VERSION:-v0.2.1}}"
OUT="${OUT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/yggsync}"
YGGSYNC_REPO="${YGGSYNC_REPO:-https://github.com/yggdrasilhq/yggsync}"
URL="${YGGSYNC_REPO%/}/releases/download/${VERSION}/yggsync-android-arm64"

log(){ printf "[%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }

mkdir -p "$(dirname "$OUT")"
tmp="${OUT}.download"

log "Downloading yggsync ${VERSION} from ${URL}"
curl -L --fail --silent --show-error "$URL" -o "$tmp"
chmod +x "$tmp"
mv "$tmp" "$OUT"
log "Installed to $OUT"
