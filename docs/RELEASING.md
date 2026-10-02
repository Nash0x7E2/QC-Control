# Building a release

Release builds target macOS 13 or later on Apple Silicon and Intel. Public downloads require Developer ID signing and Apple notarization.

## Local signing configuration

1. Sign in to your developer account in Xcode Settings → Accounts.
2. Copy `Config/Signing.local.xcconfig.example` to `Config/Signing.local.xcconfig` and set your Apple developer team ID. This local file is ignored by Git.
3. Open `QCControl.xcodeproj` and use the **QC Control** scheme. Forks should choose their own bundle identifier.

Keep credentials, certificates, private keys, provisioning profiles, and account-specific settings out of Git. Xcode archives use Apple Development signing; the Developer ID export signs the distributable app with the distribution certificate.

## Xcode release script

Run the tests and commit your changes, then run:

```sh
swift test
./scripts/release-xcode.sh
```

You can provide `QC_CONTROL_TEAM_ID` in the environment instead of the local configuration file. The script builds an optimized universal Release archive and submits it to Apple's notarization service using the account configured in Xcode. It supports Xcode cloud-managed Developer ID certificates.

If Apple is still processing, resume without rebuilding or resubmitting:

```sh
./scripts/release-xcode.sh --resume
```

The script verifies the expected signing team, both architectures, stapled notarization ticket, code signature, and Gatekeeper acceptance. It then verifies an extracted copy of the ZIP before creating `dist/release-VERSION/` with the download, checksum, source commit, and release notes. It does not publish to GitHub.

A release directory must not already exist. Preserve an earlier candidate elsewhere under `dist/` before producing another build of the same version.

## Other build options

For a local ad-hoc development build:

```sh
./scripts/build.sh
```

For a locally installed Developer ID certificate and a notarization Keychain profile:

```sh
export SIGNING_IDENTITY='Developer ID Application: YOUR NAME (TEAMID)'
export NOTARY_PROFILE='your-keychain-profile-name'
./scripts/release.sh
```

Alternatively, use Xcode's **Product → Archive → Distribute App → Developer ID** workflow and complete notarization.

## Before publication

- Run the test suite and test setup, Bluetooth permission, listening modes, reconnect, popup placement, and click-away dismissal.
- Test a fresh install, sleep/wake, launch at login, and each architecture you claim to support.
- Review the exact source history and release artifacts for private data.
- Publish only the verified ZIP, checksum, and public release notes. Keep archives, symbols, signing configuration, and local diagnostics private.
- Confirm the intended source license before publication.

Apple references: [Developer ID](https://developer.apple.com/developer-id/) and [notarizing macOS software](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).
