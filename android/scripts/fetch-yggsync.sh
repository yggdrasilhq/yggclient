#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

VERSION="${1:-v0.1.3}"
OUT="${OUT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/yggsync}"
URL="https://g.gour.top/yggdrasilhq/yggsync/releases/download/${VERSION}/yggsync-android-arm64"

log(){ printf "[%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }

mkdir -p "$(dirname "$OUT")"
tmp="${OUT}.download"

log "Downloading yggsync ${VERSION} from ${URL}"
curl -L --fail --silent --show-error "$URL" -o "$tmp"
chmod +x "$tmp"
mv "$tmp" "$OUT"
log "Installed to $OUT"
