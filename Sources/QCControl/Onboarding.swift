import AppKit
import SwiftUI

@MainActor final class OnboardingFlow: ObservableObject {
 enum Stage: Int { case welcome, connect, ready }
 static let completedKey = "onboardingCompleted"
 static let startedKey = "headphoneSetupStarted"
 @Published var stage: Stage = .welcome
 @Published var searching = false
 private let defaults: UserDefaults
 init(defaults: UserDefaults = .standard) { self.defaults = defaults }
 var needsWelcome: Bool { !defaults.bool(forKey: Self.completedKey) }
 var shouldAutoConnect: Bool { defaults.bool(forKey: Self.startedKey) }
 func continueToSetup() { stage = .connect }
 func startSearch() { searching = true; defaults.set(true, forKey: Self.startedKey) }
 func connectionChanged(_ connected: Bool) {
  if connected && stage == .connect { stage = .ready }
  else if !connected && stage == .ready { stage = .connect }
 }
 func finish() { defaults.set(true, forKey: Self.completedKey) }
}

@MainActor final class OnboardingController: NSObject, NSWindowDelegate {
 private let window: NSWindow
 private let flow: OnboardingFlow
 private let onFinish: () -> Void
 private var completing = false
 var isVisible: Bool { window.isVisible }
 init(headphones: Headphones, onFinish: @escaping () -> Void) {
  self.flow = OnboardingFlow()
  self.onFinish = onFinish
  window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 590),
                    styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
  super.init()
  window.title = "Welcome to QC Control"
  window.titleVisibility = .hidden
  window.titlebarAppearsTransparent = true
  window.isMovableByWindowBackground = true
  window.isReleasedWhenClosed = false
  window.isRestorable = false
  window.delegate = self
  window.contentViewController = NSHostingController(rootView: OnboardingView(
   headphones: headphones, flow: flow,
   onDone: { [weak self] in self?.complete(revealControls: true) },
   onLater: { [weak self] in self?.complete(revealControls: false) }
  ))
  window.center()
 }
 func show() { NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil) }
 private func complete(revealControls: Bool) {
  guard !completing else { return }
  completing = true
  flow.finish()
  window.close()
  if revealControls { onFinish() }
 }
 func windowWillClose(_ notification: Notification) {
  flow.finish() // Closing means “set up later”; it never requests Bluetooth access.
 }
}

private enum WelcomeColors {
 static let ink = Color(red: 0.13, green: 0.20, blue: 0.29)
 static let secondary = Color(red: 0.37, green: 0.44, blue: 0.53)
 static let periwinkle = Color(red: 0.40, green: 0.46, blue: 0.82)
 static let mint = Color(red: 0.75, green: 0.94, blue: 0.87)
}

struct OnboardingView: View {
 @ObservedObject var headphones: Headphones
 @ObservedObject var flow: OnboardingFlow
 let onDone: () -> Void
 let onLater: () -> Void
 @Environment(\.accessibilityReduceMotion) private var reduceMotion
 private var hasIssue: Bool {
  headphones.bluetoothAvailability == .denied || headphones.bluetoothAvailability == .poweredOff ||
  (flow.searching && !headphones.connecting && headphones.error != nil)
 }
 var body: some View {
  ZStack {
   LinearGradient(colors: [Color(red: 0.94, green: 0.98, blue: 0.96), .white, Color(red: 0.94, green: 0.94, blue: 1)], startPoint: .topLeading, endPoint: .bottomTrailing)
   VStack(spacing: 0) {
    HStack(spacing: 7) {
     ForEach(0..<3) { index in
      Capsule().fill(index <= flow.stage.rawValue ? WelcomeColors.periwinkle : WelcomeColors.periwinkle.opacity(0.13))
       .frame(width: index == flow.stage.rawValue ? 26 : 7, height: 5)
     }
    }.accessibilityElement(children: .ignore)
     .accessibilityLabel("Setup step \(flow.stage.rawValue + 1) of 3")
     .padding(.top, 38)

    ZStack(alignment: .bottomTrailing) {
     Circle().fill(WelcomeColors.mint.opacity(0.38)).frame(width: 185, height: 185).blur(radius: 13)
     WelcomeMascot(animated: !reduceMotion).frame(width: 186, height: 186)
     if flow.stage == .ready {
      Image(systemName: "checkmark").font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
       .frame(width: 38, height: 38).background(Color(red: 0.22, green: 0.64, blue: 0.46), in: Circle())
       .overlay(Circle().stroke(.white, lineWidth: 4)).offset(x: -8, y: -8)
     }
    }.padding(.top, 18).padding(.bottom, 14)

    VStack(spacing: 10) {
     Text(title).font(.system(size: 29, weight: .bold, design: .rounded)).tracking(-0.7)
     Text(subtitle).font(.system(size: 14)).foregroundStyle(WelcomeColors.secondary)
      .multilineTextAlignment(.center).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
    }.padding(.horizontal, 36)

    Group {
     switch flow.stage {
     case .welcome:
      HStack(spacing: 20) {
       feature("Less noise", symbol: "waveform")
       feature("More focus", symbol: "leaf")
       feature("One click", symbol: "cursorarrow.click")
      }.padding(.vertical, 22)
     case .connect:
      connectionCard.padding(.top, 20)
     case .ready:
      HStack(spacing: 12) {
       Image(systemName: "headphones").font(.system(size: 22)).foregroundStyle(WelcomeColors.periwinkle)
       VStack(alignment: .leading, spacing: 4) {
        Text(headphones.name).font(.system(size: 13, weight: .semibold))
        Text(headphones.battery.map { "Connected · \($0)% battery" } ?? "Connected and ready")
         .font(.caption).foregroundStyle(WelcomeColors.secondary)
       }
       Spacer(minLength: 0)
      }.padding(17).background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 16)).padding(.top, 22)
     }
    }.padding(.horizontal, 36)
    Spacer(minLength: 14)
    VStack(spacing: 12) {
     Button(action: primaryAction) {
      HStack(spacing: 9) {
       Text(primaryTitle)
       Image(systemName: flow.stage == .ready ? "arrow.up.right" : "arrow.right")
      }.font(.system(size: 14, weight: .semibold)).frame(maxWidth: .infinity).frame(height: 44)
       .foregroundStyle(.white).background(WelcomeColors.periwinkle, in: RoundedRectangle(cornerRadius: 13))
     }.buttonStyle(.plain).keyboardShortcut(.defaultAction)
      .disabled(flow.stage == .connect && flow.searching && headphones.connecting)
      .opacity(flow.stage == .connect && flow.searching && headphones.connecting ? 0.6 : 1)
     if flow.stage == .ready {
      Text("Look for your little Spitz in the menu bar.").font(.caption).foregroundStyle(WelcomeColors.secondary)
     } else {
      Button("Set up later", action: onLater).buttonStyle(.plain).font(.caption).foregroundStyle(WelcomeColors.secondary)
     }
    }.padding(.horizontal, 36).padding(.bottom, 27)
   }
  }.frame(width: 500, height: 590).foregroundStyle(WelcomeColors.ink).preferredColorScheme(.light)
   .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: flow.stage)
   .onChange(of: headphones.connected) { flow.connectionChanged($0) }
 }
 private var title: String {
  switch flow.stage {
  case .welcome: return "A little more quiet."
  case .connect: return "Headphones on. World off."
  case .ready: return "Your quiet is ready."
  }
 }
 private var subtitle: String {
  switch flow.stage {
  case .welcome: return "Meet QC Control. Your tiny companion for\ncalmer listening, right in your menu bar."
  case .connect: return "Turn on your Bose QC Ultra headphones\nand keep them close to your Mac."
  case .ready: return "Find your focus with Quiet, let the world in\nwith Aware, or make the quiet your own."
  }
 }
 private func feature(_ title: String, symbol: String) -> some View {
  VStack(spacing: 8) {
   Image(systemName: symbol).font(.system(size: 17)).foregroundStyle(WelcomeColors.periwinkle)
   Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(WelcomeColors.secondary)
  }.frame(maxWidth: .infinity)
 }
 private var connectionCard: some View {
  VStack(alignment: .leading, spacing: 10) {
   HStack(spacing: 10) {
    if flow.searching && headphones.connecting { ProgressView().controlSize(.small) }
    else { Image(systemName: hasIssue ? "info.circle" : "antenna.radiowaves.left.and.right").foregroundStyle(WelcomeColors.periwinkle) }
    Text(connectionMessage).font(.system(size: 12, weight: .medium)).fixedSize(horizontal: false, vertical: true)
   }
   if headphones.devices.count > 1 {
    Picker("Headphones", selection: Binding(get: { headphones.selected }, set: headphones.selectDevice)) {
     ForEach(headphones.devices) { device in Text(device.name).tag(device.id) }
    }.font(.caption).disabled(headphones.connecting)
   }
   Button(headphones.bluetoothAvailability == .denied ? "Allow access in Privacy Settings ↗" : "First time on this Mac? Open Bluetooth Settings ↗") {
    if headphones.bluetoothAvailability == .denied { headphones.privacySettings() } else { headphones.settings() }
   }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(WelcomeColors.periwinkle)
  }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
   .background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 16))
 }
 private var connectionMessage: String {
  if !flow.searching { return "We’ll ask for Bluetooth access when you’re ready." }
  switch headphones.bluetoothAvailability {
  case .denied: return "Allow Bluetooth access for QC Control, then try again."
  case .poweredOff: return "Bluetooth is off. Turn it on in your Mac’s settings."
  case .waitingForPermission: return "Choose Allow in the macOS Bluetooth prompt."
  case .unavailable: return "Bluetooth isn’t available on this Mac right now."
  default:
   if headphones.connecting { return "Looking for your headphones…" }
   if headphones.devices.isEmpty { return "Not found yet. Make sure they’re paired with this Mac." }
   return "Not connected yet. Check they’re on and nearby, then try again."
  }
 }
 private var primaryTitle: String {
  switch flow.stage {
  case .welcome: return "Get started"
  case .connect:
   if flow.searching && headphones.connecting { return "Finding your headphones…" }
   return flow.searching ? "Try again" : "Find my headphones"
  case .ready: return "Open QC Control"
  }
 }
 private func primaryAction() {
  switch flow.stage {
  case .welcome: flow.continueToSetup(); flow.connectionChanged(headphones.connected)
  case .connect: flow.startSearch(); headphones.startConnection(); flow.connectionChanged(headphones.connected)
  case .ready: flow.finish(); onDone()
  }
 }
}

/// Animate an existing native layer; no timeline, polling, or SwiftUI redraw loop.
private struct WelcomeMascot: NSViewRepresentable {
 let animated: Bool
 func makeNSView(context: Context) -> NSImageView {
  let view = NSImageView()
  view.image = BatteryArtwork.mascot
  view.imageScaling = .scaleProportionallyUpOrDown
  view.wantsLayer = true
  view.setAccessibilityLabel("Smiling Japanese Spitz wearing headphones")
  return view
 }
 func updateNSView(_ view: NSImageView, context: Context) {
  if animated && view.layer?.animation(forKey: "welcomeFloat") == nil {
   let float = CABasicAnimation(keyPath: "transform.translation.y")
   float.fromValue = 0; float.toValue = 5; float.duration = 2.4
   float.autoreverses = true; float.repeatCount = .infinity
   float.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
   view.layer?.add(float, forKey: "welcomeFloat")
  } else if !animated { view.layer?.removeAnimation(forKey: "welcomeFloat") }
 }
}
