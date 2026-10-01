#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/qc-control-module-cache"
identity="${SIGNING_IDENTITY:--}"
universal=false
app="$PWD/dist/QC Control.app"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --universal) universal=true; shift ;;
    --identity) identity="${2:?Missing signing identity}"; shift 2 ;;
    --output) app="${2:?Missing app output path}"; shift 2 ;;
    *) printf 'Unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done
if [[ "$identity" != '-' ]]; then
  identities=$(security find-identity -v -p codesigning)
  if ! printf '%s\n' "$identities" | grep -F -- "$identity" >/dev/null; then
    printf 'Signing identity not available: %s\n' "$identity" >&2
    exit 1
  fi
fi
./scripts/make-icon.sh
stage=$(mktemp -d "${TMPDIR:-/tmp}/qc-control-build.XXXXXX")
trap 'rm -rf "$stage"' EXIT
bundle="$stage/QC Control.app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
if $universal; then
  for arch in arm64 x86_64; do
    build_args=(--build-system native --configuration release --disable-sandbox --triple "${arch}-apple-macosx13.0" --scratch-path ".build/release-${arch}")
    swift build "${build_args[@]}"
    bin=$(swift build "${build_args[@]}" --show-bin-path)
    cp "$bin/QCControl" "$stage/QCControl-${arch}"
  done
  lipo -create "$stage/QCControl-arm64" "$stage/QCControl-x86_64" -output "$bundle/Contents/MacOS/QCControl"
else
  swift build -c release --disable-sandbox
  bin=$(swift build -c release --show-bin-path --disable-sandbox)
  cp "$bin/QCControl" "$bundle/Contents/MacOS/QCControl"
fi
cp Info.plist "$bundle/Contents/Info.plist"
cp Assets/AppIcon.icns "$bundle/Contents/Resources/AppIcon.icns"
# Exclude local extended attributes; never ship machine-specific Finder metadata.
xattr -cr "$bundle"
if [[ "$identity" == '-' ]]; then
  codesign --force --sign - "$bundle"
else
  codesign --force --options runtime --timestamp --sign "$identity" "$bundle"
fi
codesign --verify --strict --verbose=2 "$bundle"
mkdir -p "$(dirname "$app")"
# Only replace the requested app after a complete build and successful signing.
if [[ -e "$app" ]]; then
  [[ "$app" == *.app && -f "$app/Contents/Info.plist" ]] || { printf 'Refusing to replace a non-app path.\n' >&2; exit 1; }
  rm -rf "$app"
fi
ditto "$bundle" "$app"
printf 'Built %s\n' "$app"
