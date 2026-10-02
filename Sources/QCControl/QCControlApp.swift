import SwiftUI
import AppKit

@main enum QCControlApp {
 @MainActor static func main() {
  let app = NSApplication.shared
  app.setActivationPolicy(.accessory)
  let delegate = AppDelegate()
  app.delegate = delegate
  withExtendedLifetime(delegate) { app.run() }
 }
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
 private var headphones: Headphones?
 private var statusController: StatusBarController?
 private var onboarding: OnboardingController?
 func applicationDidFinishLaunching(_ notification: Notification) {
  let smokeTest = CommandLine.arguments.contains("--appearance-smoke-test")
  let positioningTest = CommandLine.arguments.contains("--positioning-smoke-test")
  let dismissalTest = CommandLine.arguments.contains("--dismissal-smoke-test")
  let diagnostic = CommandLine.arguments.contains { $0.hasSuffix("-smoke-test") }
  let firstLaunch = OnboardingFlow()
  let headphones = Headphones(connectAutomatically: !smokeTest && !positioningTest && !dismissalTest && (diagnostic || firstLaunch.shouldAutoConnect))
  self.headphones = headphones
  let controller = StatusBarController(headphones: headphones, onShowSetup: { [weak self] in self?.showOnboarding() }, onActivate: { [weak self] in
   guard let onboarding = self?.onboarding, onboarding.isOpen else { return false }
   onboarding.show()
   return true
  })
  statusController = controller
  if !diagnostic && (firstLaunch.needsWelcome || CommandLine.arguments.contains("--onboarding")) { showOnboarding() }
  if smokeTest { controller.runAppearanceSmokeTest() }
  if positioningTest { controller.runPositioningSmokeTest() }
  if dismissalTest { controller.runDismissalSmokeTest() }
  if CommandLine.arguments.contains("--connection-smoke-test") { controller.runConnectionSmokeTest() }
  if CommandLine.arguments.contains("--window-smoke-test") {
   Task { @MainActor in
    try? await Task.sleep(nanoseconds: 1_000_000_000)
    let unexpectedWindows = NSApp.windows.filter { $0.isVisible && $0 !== NSApp.mainWindow?.sheetParent && $0.styleMask.contains(.titled) }
    let report = "\(unexpectedWindows.isEmpty ? "PASS" : "FAIL"): visible titled windows=\(unexpectedWindows.count).\n"
    try? report.write(toFile: "/tmp/qc-control-window-test.txt", atomically: true, encoding: .utf8)
   }
  }
 }
 private func showOnboarding() {
  if let onboarding, onboarding.isOpen { onboarding.show(); return }
  guard let headphones else { return }
  onboarding = OnboardingController(headphones: headphones) { [weak self] in self?.statusController?.showPanel() }
  onboarding?.show()
 }
 func applicationWillTerminate(_ notification: Notification) {
  statusController?.close()
  headphones?.shutdown()
 }
}
struct ControlPanel: View {
 @ObservedObject var headphones: Headphones
 var onShowSetup: () -> Void = {}
 @State private var level: Double = 0
 @State private var editing = false
 var body: some View {
  VStack(alignment: .leading, spacing: 18) {
   HStack(spacing: 12) {
    Image(nsImage: BatteryArtwork.mascot).resizable().interpolation(.high)
     .frame(width: 48, height: 48).accessibilityLabel("QC Control Spitz mascot")
    VStack(alignment: .leading, spacing: 4) {
     Text(headphones.name).font(.system(size: 14, weight: .semibold))
     HStack(spacing: 5) {
      Circle().fill(headphones.connected ? Color.green : Color.secondary).frame(width: 5, height: 5)
      Text(headphones.status).font(.caption).foregroundStyle(.secondary)
     }
    }
    Spacer(minLength: 0)
    if let battery = headphones.battery { Text("\(battery)%").font(.caption.monospacedDigit()).foregroundStyle(.secondary).accessibilityLabel("Battery \(battery) percent") }
   }
   if headphones.connected {
    VStack(alignment: .leading, spacing: 10) {
     Text("LISTENING MODE").font(.system(size: 10, weight: .semibold)).tracking(1.1).foregroundStyle(.secondary)
     if headphones.modes.count <= 5 {
      modeButtons
     } else {
      ScrollView { modeButtons }.frame(height: 5 * 36 + 4 * 6)
     }
    }
    if let audio = headphones.audio {
     Divider()
     VStack(alignment: .leading, spacing: 10) {
      HStack {
       Text("Noise cancellation").font(.system(size: 13, weight: .medium))
       Spacer()
       Text("\(Int(level))/10").monospacedDigit().foregroundStyle(.secondary)
      }
      Slider(value: $level, in: 0...10, step: 1) { active in
       editing = active
       headphones.isEditingLevel = active
       if !active { headphones.changeAudio(level: Int(level)) }
      }.disabled(headphones.busy || !audio.enabled).accessibilityLabel("Noise cancellation level")
      HStack { Text("Aware"); Spacer(); Text("Maximum") }.font(.caption).foregroundStyle(.secondary)
      if headphones.supportsANCOff {
       Toggle("Enable noise cancellation", isOn: Binding(get: { audio.enabled }, set: { headphones.changeAudio(enabled: $0) })).disabled(headphones.busy)
      } else {
       Text("Adjusting the slider uses a QC Control custom mode. Aware lets outside sound in; this model has no separate ANC-off control.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      }
     }
    } else {
     Text("Use Quiet for full cancellation or Aware for outside sound. Adjustable levels are unavailable on this connection.").font(.caption).foregroundStyle(.secondary)
    }
   }
   if let error = headphones.error {
    Label(error, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
   }
   Divider()
   if headphones.devices.count > 1 {
    Picker("Headphones", selection: Binding(get: { headphones.selected }, set: headphones.selectDevice)) {
     ForEach(headphones.devices) { device in Text(device.name).tag(device.id) }
    }.disabled(headphones.busy)
   }
   HStack {
    Button(headphones.connected ? "Reconnect" : "Connect") { headphones.startConnection() }.disabled(headphones.busy || headphones.connecting)
    if headphones.busy || headphones.connecting { ProgressView().controlSize(.small).scaleEffect(0.8) }
    Spacer()
    Menu {
     Toggle("Show battery in menu bar", isOn: $headphones.showBattery)
     Menu("Menu bar style") {
      Picker("Style", selection: $headphones.batteryStyle) {
       ForEach(BatteryStyle.allCases) { style in Text(style.title).tag(style) }
      }
      Toggle("Animate icon", isOn: $headphones.animateBattery)
       .disabled(headphones.batteryStyle == .percentage)
     }
     Toggle("Launch at login", isOn: Binding(get: { headphones.loginEnabled }, set: headphones.setLogin))
     Button("Bluetooth Settings…", action: headphones.settings)
     Button("Headphone setup…", action: onShowSetup)
     Button("Copy diagnostics", action: headphones.copyDiagnostics)
     Divider()
     Button("Quit QC Control") { headphones.shutdown(); NSApp.terminate(nil) }.keyboardShortcut("q")
    } label: {
     Image(systemName: "gearshape").frame(width: 28, height: 28, alignment: .center)
    }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
     .accessibilityLabel("QC Control settings").help("Settings")
   }
  }.padding(20).frame(width: 350)
   .onDisappear { headphones.isEditingLevel = false }
   .onAppear { level = Double(headphones.audio?.cancellation ?? 0) }
   .onChange(of: headphones.busy) { busy in if !busy && !editing { level = Double(headphones.audio?.cancellation ?? 0) } }
   .onChange(of: headphones.audio) { audio in if !editing { level = Double(audio?.cancellation ?? 0) } }
 }
 private var modeButtons: some View {
  VStack(spacing: 6) {
   ForEach(headphones.modes) { mode in
    Button { headphones.switchMode(mode.id) } label: {
     HStack {
      Image(systemName: mode.name == "Aware" ? "ear" : "waveform").frame(width: 20)
      Text(mode.editable && mode.name == "BoseBar" ? "QC Control" : mode.name)
      Spacer()
      if headphones.currentMode == mode.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor) }
     }.padding(.horizontal, 10).frame(maxWidth: .infinity).frame(height: 36)
      .background(headphones.currentMode == mode.id ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
    }.buttonStyle(.plain).disabled(headphones.busy)
   }
  }
 }
}
