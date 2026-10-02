<p align="center"><img src="Assets/AppIcon.png" width="160" alt="A smiling Japanese Spitz wearing headphones"></p>
<h1 align="center">QC Control</h1>
<p align="center">A little more quiet. A little more joy.</p>

A native macOS menu bar app for Bose QuietComfort Ultra Headphones, with a smiling Japanese Spitz mascot. Control listening modes and noise cancellation directly over Bluetooth—no account or cloud service.

## Features

- Quiet, Aware, Immersion, and your configured custom modes.
- A 0–10 noise cancellation slider with verified device readback.
- Battery percentage, circular ring, dotted ring, or a cute Spitz menu bar icon.
- Optional gentle icon animation, respecting Reduce Motion.
- A short, animated first-launch welcome with headphone setup and Bluetooth permission guidance.
- Automatic reconnect, launch at login, and device selection.
- Bluetooth work runs on its own thread; status refreshes leave controls usable.

The slider creates or updates a dedicated **QC Control** mode in an unused slot. It also recognizes the **BoseBar** mode from earlier local versions. Existing modes are preserved. Level 0 means maximum outside sound; level 10 means maximum cancellation.

**Aware is transparency, not ANC off.** The first-generation QC Ultra on firmware 1.6.7 does not advertise a separate ANC-off switch. Headphone power control is not included.

## Compatibility

- macOS 13 or later; release configuration targets Apple silicon and Intel.
- Hardware-tested protocol: Bose QuietComfort Ultra Headphones (first generation), firmware 1.6.7.
- Other headphone models and generations are not yet verified.

The application icon is static. Select **gear → Menu bar style → Smiling Spitz**, then **Animate icon**, for a gentle menu bar bounce. Ring styles use a soft pulse. Animation uses native Core Animation, with no per-frame SwiftUI redraws.

## Open in Xcode

Open **QCControl.xcodeproj** and select the **QC Control** scheme. In the target's **Signing & Capabilities** tab, choose your personal development team and confirm the bundle identifier `com.neevash.qccontrol`.

Copy `Config/Signing.local.xcconfig.example` to `Config/Signing.local.xcconfig` and enter your developer team ID. The local override is ignored by Git. Forks should also choose their own bundle identifier. The project includes the app icon, Bluetooth usage descriptions, hardened runtime, and a shared Archive scheme. The protocol library is a local Swift package; no external package downloads are required.

Use **Run** for local development. For a public release, choose **Product → Archive**, then **Distribute App → Developer ID** in Organizer and complete signing and notarization. See [the release guide](docs/RELEASING.md).

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

## Using the app

Open QC Control and follow the three-step welcome. Turn your headphones on and choose **Find my headphones** to request Bluetooth permission. If they have never been paired with your Mac, use the Bluetooth Settings link to pair them. **Set up later** dismisses setup without requesting access; reopen it from **gear → Headphone setup…**. Click the menu bar icon for controls. For launch at login, move the app to Applications first, then enable the setting in the gear menu.

The app stores preferences locally and sends no telemetry. **Copy diagnostics** includes device and mode names; review it before sharing.

## Testing and limitations

The test suite covers packet framing, field preservation, queued commands, responsiveness during slow Bluetooth operations, onboarding, and popup placement. Bose QuietComfort Ultra Headphones (first generation, firmware 1.6.7) are the hardware-verified model.

Intel runtime behavior, sleep/wake, and launch-at-login behavior need further verification. Other Bose models are not yet supported or verified.

## Source layout

- `Sources/BoseProtocol`: packet framing and device data formats.
- `Sources/QCControl`: Bluetooth worker, application state, SwiftUI panel, native menu bar and animation.
- `Tests`: protocol and responsiveness regression tests.
- `Assets`: Spitz artwork and macOS icon.
- `scripts`: icon generation, local builds, and gated notarized release packaging.

## References

Independent Swift implementation informed by [bozo's BMAP documentation](https://github.com/NerdySouth/bozo/blob/main/docs/BMAP.md), [bosectl](https://github.com/aaronsb/bosectl), and [ANChor](https://github.com/JimmyCalhoun/ANChor).

QC Control is an unofficial utility, not affiliated with Bose. Bose and QuietComfort are trademarks of their respective owner.
