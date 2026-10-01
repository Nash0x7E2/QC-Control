#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${SIGNING_IDENTITY:?Set SIGNING_IDENTITY to your Developer ID Application identity name}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to your notarytool Keychain profile name}"
case "$SIGNING_IDENTITY" in
  'Developer ID Application: '*) ;;
  *) printf 'Public releases require Developer ID Application signing; development/ad-hoc signing is not accepted.\n' >&2; exit 1 ;;
esac
if [[ -n "$(git status --porcelain)" ]]; then
  printf 'Commit source changes before building a release.\n' >&2; exit 1
fi
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)
release_dir="$PWD/dist/release-${version}"
[[ ! -e "$release_dir" ]] || { printf 'Release directory already exists: %s\n' "$release_dir" >&2; exit 1; }
# Validate signing and notarization access before the expensive universal build.
security find-identity -v -p codesigning | grep -F -- "$SIGNING_IDENTITY" >/dev/null
xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" --output-format json >/dev/null
./scripts/build.sh --universal --identity "$SIGNING_IDENTITY"
app="$PWD/dist/QC Control.app"
work=$(mktemp -d "${TMPDIR:-/tmp}/qc-control-release.XXXXXX")
trap 'rm -rf "$work"' EXIT
ditto -c -k --sequesterRsrc --keepParent "$app" "$work/submission.zip"
xcrun notarytool submit "$work/submission.zip" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json > "$work/notarization.json"
status=$(plutil -extract status raw "$work/notarization.json")
if [[ "$status" != Accepted ]]; then
  cat "$work/notarization.json" >&2
  printf 'Notarization failed. No public release package was created.\n' >&2
  exit 1
fi
xcrun stapler staple "$app"
xcrun stapler validate "$app"
codesign --verify --strict --verbose=2 "$app"
spctl --assess --type execute --verbose=2 "$app"
# Archive AFTER stapling, and check the extracted deliverable, not just the build.
archive="QC-Control-${version}-universal.zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$work/$archive"
mkdir "$work/verify"
ditto -x -k "$work/$archive" "$work/verify"
codesign --verify --strict "$work/verify/QC Control.app"
xcrun stapler validate "$work/verify/QC Control.app"
spctl --assess --type execute "$work/verify/QC Control.app"
mkdir "$release_dir"
cp "$work/$archive" "$release_dir/$archive"
cp "$work/notarization.json" "$release_dir/notarization.json"
cp "docs/releases/v${version}.md" "$release_dir/RELEASE_NOTES.md"
(
  cd "$release_dir"
  shasum -a 256 "$archive" > SHA256SUMS.txt
)
printf 'Verified public release files: %s\n' "$release_dir"
