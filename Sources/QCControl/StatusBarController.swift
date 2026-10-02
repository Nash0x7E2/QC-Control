import AppKit
import SwiftUI
import Combine
import QuartzCore

/// Keep animation out of SwiftUI's menu-label rendering graph. Core Animation
/// composites the existing icon; it never redraws the image or publishes state.
@MainActor final class StatusBarController: NSObject {
 private let headphones: Headphones
 private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
 private let popover = NSPopover()
 private var changes: AnyCancellable?
 private var accessibilityObserver: NSObjectProtocol?
 private var lastIconKey = ""
 private var animated = false
 private var animationStyle: BatteryStyle?

 init(headphones: Headphones, onShowSetup: @escaping () -> Void = {}) {
  self.headphones = headphones
  super.init()
  popover.behavior = .transient
  popover.contentViewController = NSHostingController(rootView: ControlPanel(headphones: headphones, onShowSetup: { [weak self] in
   self?.popover.performClose(nil)
   onShowSetup()
  }))
  if let button = item.button {
   button.target = self
   button.action = #selector(togglePanel)
   button.imagePosition = .imageLeading
   button.wantsLayer = true
   button.setAccessibilityLabel("QC Control")
  }
  // objectWillChange fires before values change. Coalesce and deliver after the
  // current event finishes, including a style selection in an open settings menu.
  changes = headphones.objectWillChange
   .debounce(for: .milliseconds(30), scheduler: RunLoop.main)
   .sink { [weak self] _ in self?.refresh() }
  accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
   forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
   object: nil, queue: .main
  ) { [weak self] _ in Task { @MainActor in self?.refresh() } }
  refresh()
 }

 @objc private func togglePanel() {
  guard let button = item.button else { return }
  if popover.isShown { popover.performClose(nil) }
  else {
   NSApp.activate(ignoringOtherApps: true)
   popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
  }
 }
 func showPanel() {
  guard !popover.isShown, let button = item.button else { return }
  NSApp.activate(ignoringOtherApps: true)
  popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
 }

 private func refresh() {
  guard let button = item.button else { return }
  let battery = headphones.showBattery ? headphones.battery : nil
  let style = headphones.batteryStyle
  let key = "\(style.rawValue):\(battery ?? -1)"
  if key != lastIconKey {
   lastIconKey = key
   if style == .spitz {
    button.image = BatteryArtwork.mascot
    button.title = ""
   } else if let battery, style != .percentage {
    // Materialize the vector drawing once per level/style change. Never allocate
    // NSImages on animation frames or re-enter SwiftUI menu label layout.
    let artwork = BatteryArtwork.image(level: battery, style: style)
    if let tiff = artwork.tiffRepresentation, let bitmap = NSImage(data: tiff) {
     bitmap.isTemplate = true
     button.image = bitmap
    } else { button.image = artwork }
    button.title = ""
   } else {
    button.image = NSImage(systemSymbolName: "headphones", accessibilityDescription: "QC Control")
    button.title = battery.map { " \($0)%" } ?? ""
   }
  }
  button.toolTip = headphones.battery.map { "QC Control · Battery \($0)%" } ?? "QC Control · \(headphones.status)"
  button.setAccessibilityLabel(button.toolTip)
  let shouldAnimate = (style == .spitz || (battery != nil && style != .percentage)) && headphones.animateBattery &&
   !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
  if shouldAnimate != animated || animationStyle != style {
   animated = shouldAnimate
   animationStyle = style
   button.layer?.removeAnimation(forKey: "batteryBreathing")
   if shouldAnimate {
    if style == .spitz {
     let bounce = CAKeyframeAnimation(keyPath: "transform.translation.y")
     bounce.values = [0, 1.2, 0, 0]
     bounce.keyTimes = [0, 0.2, 0.4, 1]
     bounce.duration = 3
     bounce.repeatCount = .infinity
     bounce.calculationMode = .cubic
     button.layer?.add(bounce, forKey: "batteryBreathing")
    } else {
    let animation = CABasicAnimation(keyPath: "opacity")
    animation.fromValue = 1.0
    animation.toValue = 0.72
    animation.duration = 2
    animation.autoreverses = true
    animation.repeatCount = .infinity
    animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    button.layer?.add(animation, forKey: "batteryBreathing")
    }
   }
  }
 }

 func close() {
  changes?.cancel()
  if let accessibilityObserver { NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver) }
  item.button?.layer?.removeAnimation(forKey: "batteryBreathing")
  popover.close()
  NSStatusBar.system.removeStatusItem(item)
 }

 /// Opt-in live regression check: keep the real panel open through polling and
 /// one control-channel reconnect. Never changes listening modes or noise levels.
 func runConnectionSmokeTest() {
  Task { @MainActor in
   for _ in 0..<60 {
    if headphones.connected { break }
    try? await Task.sleep(nanoseconds: 500_000_000)
   }
   guard headphones.connected else {
    try? "INCOMPLETE: Headphones not connected. \(headphones.status)\n\(headphones.error ?? "")".write(toFile: "/tmp/qc-control-connection-test.txt", atomically: true, encoding: .utf8)
    return
   }
   togglePanel()
   var lastTick = ProcessInfo.processInfo.systemUptime
   var longestGap: TimeInterval = 0
   var ticks = 0
   var busyTransitions = 0
   let busy = headphones.$busy.dropFirst().sink { if $0 { busyTransitions += 1 } }
   let heartbeat = Timer(timeInterval: 0.02, repeats: true) { _ in
    let now = ProcessInfo.processInfo.systemUptime
    longestGap = max(longestGap, now - lastTick)
    lastTick = now; ticks += 1
   }
   RunLoop.main.add(heartbeat, forMode: .common)
   try? await Task.sleep(nanoseconds: 10_000_000_000)
   headphones.startConnection()
   try? await Task.sleep(nanoseconds: 20_000_000_000)
   heartbeat.invalidate(); busy.cancel()
   let passed = headphones.connected && longestGap < 0.2 && ticks > 1000 && busyTransitions == 0
   let report = "\(passed ? "PASS" : "FAIL"): 30-second live polling/reconnect check; connected=\(headphones.connected); main-loop ticks=\(ticks); longest gap=\(Int(longestGap * 1000))ms; control-disabling transitions=\(busyTransitions).\n"
   try? report.write(toFile: "/tmp/qc-control-connection-test.txt", atomically: true, encoding: .utf8)
  }
 }

 /// An opt-in integration check, using the same preference setters as the menu.
 /// No Bluetooth commands; restore all preferences before exiting.
 func runAppearanceSmokeTest() {
  Task { @MainActor in
   let saved = (headphones.showBattery, headphones.batteryStyle, headphones.animateBattery)
   defer {
    headphones.showBattery = saved.0
    headphones.batteryStyle = saved.1
    headphones.animateBattery = saved.2
   }
   headphones.showBattery = true
   headphones.battery = 90
   var ticks = 0
   let heartbeat = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in ticks += 1 }
   for style in [BatteryStyle.ring, .dots, .spitz, .percentage, .ring] {
    headphones.batteryStyle = style
    for enabled in [true, false, true] {
     headphones.animateBattery = enabled
     try? await Task.sleep(nanoseconds: 300_000_000)
     refresh()
    }
   }
   headphones.battery = nil
   refresh()
   let stoppedWhenUnknown = !animated
   headphones.battery = 50
   headphones.batteryStyle = .ring
   headphones.animateBattery = true
   refresh()
   let animationInstalled = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ||
    item.button?.layer?.animation(forKey: "batteryBreathing") != nil
   try? await Task.sleep(nanoseconds: 5_000_000_000)
   heartbeat.invalidate()
   let passed = ticks >= 100 && stoppedWhenUnknown && animationInstalled && item.button?.image != nil
   let report = "\(passed ? "PASS" : "FAIL"): ring/dots/percentage, animation toggles, unknown battery; native animation installed=\(animationInstalled); main-loop heartbeats=\(ticks).\n"
   try? report.write(toFile: "/tmp/qc-control-appearance-test.txt", atomically: true, encoding: .utf8)
   // Let defer restore preferences before terminating on the next event turn.
   DispatchQueue.main.async { NSApp.terminate(nil) }
  }
 }
}
