<p align="center">
  <img src="Assets/AppIcon.png" width="160" alt="A smiling Japanese Spitz wearing headphones">
</p>
<h1 align="center">QC Control</h1>
<p align="center">A little more quiet. A little more joy.</p>
<p align="center">
  Control your Bose QuietComfort Ultra headphones from your Mac’s menu bar.<br>
  Switch listening modes, adjust noise cancellation, and check your battery—with a happy little Spitz for company.
</p>
<p align="center">
  <a href="https://github.com/Nash0x7E2/QC-Control/releases"><strong>Download for macOS</strong></a>
</p>

Requires **macOS 13 or later**. Built for Apple silicon and Intel Macs. Tested with **Bose QuietComfort Ultra Headphones (first generation)**; other models are not yet verified.

The first public release is coming soon. Downloads will appear on the releases page above.

## Get started

1. Download the ZIP from the releases page and unzip it.
2. Move **QC Control.app** to **Applications**, then open it.
3. Turn on your headphones and follow the short welcome. Allow Bluetooth access when asked; pair your headphones in **System Settings → Bluetooth** if needed.
4. Click the Spitz in your menu bar to choose a listening mode or adjust noise cancellation.

Use the **gear menu** to choose a battery percentage, ring, dots, or the Spitz icon, turn on gentle animation, and enable launch at login.

Noise cancellation ranges from **0 (Aware)** to **10 (maximum)**. Adjusting it uses a dedicated QC Control mode and preserves your other modes. Aware lets outside sound in; this model has no separate ANC-off setting.

No account, cloud service, or telemetry. Your Mac talks directly to your headphones over Bluetooth.

## Build it yourself

Open `QCControl.xcodeproj` in Xcode, choose the **QC Control** scheme, and configure your signing team. See the [development guide](docs/DEVELOPMENT.md) for setup and command-line builds, or the [release guide](docs/RELEASING.md) for signing and notarization.

---

QC Control is an independent, unofficial utility and is not affiliated with Bose. Protocol work draws on [bozo](https://github.com/NerdySouth/bozo/blob/main/docs/BMAP.md), [bosectl](https://github.com/aaronsb/bosectl), and [ANChor](https://github.com/JimmyCalhoun/ANChor).
