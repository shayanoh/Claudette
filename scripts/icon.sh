#!/bin/bash
# Build art/icon/AppIcon.icns from the committed master art/icon/icon_1024.png.
# Regenerate the master first with `python3 art/icon.py` if the icon art changes.
set -euo pipefail
cd "$(dirname "$0")/.."

SRC=art/icon/icon_1024.png
OUT=art/icon/AppIcon.icns
[ -f "$SRC" ] || { echo "$SRC missing (run python3 art/icon.py)" >&2; exit 1; }
[ "$(sips -g pixelWidth -g pixelHeight "$SRC" | awk '/pixel/ {print $2}' | sort -u)" = 1024 ] ||
  { echo "$SRC must be 1024x1024" >&2; exit 1; }

SET="$(mktemp -d)/AppIcon.iconset"
trap 'rm -rf "$(dirname "$SET")"' EXIT
mkdir "$SET"
for s in 16 32 128 256 512; do
  sips -z "$s" "$s" "$SRC" --out "$SET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s * 2)) $((s * 2)) "$SRC" --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o "$OUT"
echo "Built $OUT"
