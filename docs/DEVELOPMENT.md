# Development

## Open in Xcode

Open **QCControl.xcodeproj** and select the **QC Control** scheme. In the target's **Signing & Capabilities** tab, choose your personal development team and confirm the bundle identifier `com.neevash.qccontrol`.

Copy `Config/Signing.local.xcconfig.example` to `Config/Signing.local.xcconfig` and enter your developer team ID. The local override is ignored by Git. Forks should also choose their own bundle identifier. The project includes the app icon, Bluetooth usage descriptions, hardened runtime, and a shared Archive scheme. The protocol library is a local Swift package; no external package downloads are required.

Use **Run** for local development. For a public release, choose **Product → Archive**, then **Distribute App → Developer ID** in Organizer and complete signing and notarization. See [the release guide](RELEASING.md).

## Command-line development

```sh
./scripts/build.sh
open 'dist/QC Control.app'
```

The default CLI build is ad-hoc signed for local use. To use a specific certificate:

```sh
./scripts/build.sh --universal --identity 'Developer ID Application: YOUR NAME (TEAMID)'
```

This builds and signs, but does not notarize. Public releases must also complete notarization.

Run the twenty protocol, onboarding, and responsiveness regression tests:

```sh
CLANG_MODULE_CACHE_PATH=/tmp/qc-control-module-cache swift test --disable-sandbox
```

`--disable-sandbox` is a SwiftPM build-tool setting; the project has no package plugins. On restricted development hosts, Apple's icon and release tools may need normal host access.

## Testing and limitations

The test suite covers packet framing, field preservation, queued commands, responsiveness during slow Bluetooth operations, onboarding, and popup placement. Bose QuietComfort Ultra Headphones (first generation, firmware 1.6.7) are the hardware-verified model.

Intel runtime behavior, sleep/wake, and launch-at-login behavior need further verification. Other Bose models are not yet supported or verified.

## Source layout

- `Sources/BoseProtocol`: packet framing and device data formats.
- `Sources/QCControl`: Bluetooth worker, application state, SwiftUI panel, native menu bar and animation.
- `Tests`: protocol and responsiveness regression tests.
- `Assets`: Spitz artwork and macOS icon.
- `scripts`: icon generation, local builds, and gated notarized release packaging.

