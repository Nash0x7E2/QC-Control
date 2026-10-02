#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Uses the personal account already configured in Xcode, including cloud signing.
# Resume exports an already submitted archive; it never rebuilds or resubmits it.
resume=false
if [[ "${1:-}" == --resume && $# == 1 ]]; then
  resume=true
elif [[ $# != 0 ]]; then
  printf 'Usage: %s [--resume]\n' "$0" >&2; exit 1
fi
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)
release_dir="$PWD/dist/release-${version}"
archive="$PWD/dist/QC-Control.xcarchive"
export_dir="$PWD/dist/notarized"
[[ ! -e "$release_dir" ]] || { printf 'Release directory already exists: %s\n' "$release_dir" >&2; exit 1; }
if ! $resume; then
  [[ -z "$(git status --porcelain)" ]] || { printf 'Commit source changes before building a release.\n' >&2; exit 1; }
  mkdir -p dist
  git rev-parse HEAD > dist/release-commit.txt
  xcodebuild -project QCControl.xcodeproj -scheme 'QC Control' -configuration Release \
    -destination 'generic/platform=macOS' -archivePath "$archive" \
    -derivedDataPath .build/xcode -allowProvisioningUpdates archive
  # Developer ID + upload submits to Apple's notary service, not the App Store.
  xcodebuild -exportArchive -archivePath "$archive" -exportOptionsPlist scripts/ExportOptions.plist \
    -exportPath dist/notarization-upload -allowProvisioningUpdates
fi
if ! xcodebuild -exportNotarizedApp -archivePath "$archive" -exportPath "$export_dir" -allowProvisioningUpdates; then
  printf 'Notarized export is not ready. Check Xcode Organizer, then run %s --resume.\n' "$0" >&2
  exit 1
fi
app="$export_dir/QC Control.app"
signature=$(codesign -dvv "$app" 2>&1)
[[ "$signature" == *'Authority=Developer ID Application: YOUR NAME (YOUR_TEAM_ID)'* ]] || {
  printf 'Unexpected signing identity; refusing to package.\n' >&2; exit 1;
}
architectures=$(lipo -archs "$app/Contents/MacOS/QCControl")
[[ "$architectures" == *arm64* && "$architectures" == *x86_64* ]] || {
  printf 'Both Mac architectures are required.\n' >&2; exit 1;
}
xcrun stapler validate "$app"
codesign --verify --strict --verbose=2 "$app"
spctl --assess --type execute --verbose=2 "$app"
work=$(mktemp -d "${TMPDIR:-/tmp}/qc-control-release.XXXXXX")
trap 'rm -rf "$work"' EXIT
zip="QC-Control-${version}-universal.zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$work/$zip"
mkdir "$work/verify"
ditto -x -k "$work/$zip" "$work/verify"
codesign --verify --strict "$work/verify/QC Control.app"
xcrun stapler validate "$work/verify/QC Control.app"
spctl --assess --type execute "$work/verify/QC Control.app"
mkdir "$release_dir"
cp "$work/$zip" "$release_dir/$zip"
cp "docs/releases/v${version}.md" "$release_dir/RELEASE_NOTES.md"
cp dist/release-commit.txt "$release_dir/SOURCE_COMMIT.txt"
(cd "$release_dir" && shasum -a 256 "$zip" > SHA256SUMS.txt)
printf 'Verified public release files: %s\n' "$release_dir"
