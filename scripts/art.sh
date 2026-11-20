#!/bin/bash
# Regenerate the art export (art/export) from art/generate.py and validate it.
set -euo pipefail
cd "$(dirname "$0")/.."

command -v rsvg-convert >/dev/null || { echo "rsvg-convert not found (brew install librsvg)" >&2; exit 1; }
python3 art/generate.py
swift build >/dev/null
"$(swift build --show-bin-path)/ClaudetteApp" --validate-art art/export
