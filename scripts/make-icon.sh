#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source_icon="$PWD/Assets/AppIcon.png"
icon_work=$(mktemp -d "${TMPDIR:-/tmp}/qc-control-icon.XXXXXX")
trap 'rm -rf "$icon_work"' EXIT
iconset="$icon_work/AppIcon.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$source_icon" --out "$iconset/icon_${size}x${size}.png" >/dev/null
  retina=$((size * 2))
  sips -z "$retina" "$retina" "$source_icon" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$PWD/Assets/AppIcon.icns"
printf 'Created Assets/AppIcon.icns\n'
