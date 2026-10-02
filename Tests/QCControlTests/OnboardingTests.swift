import XCTest
import AppKit
@testable import QCControl

final class OnboardingTests: XCTestCase {
 @MainActor func testPermissionResponseRestoresHiddenSetupOnlyOnce() async throws {
  _ = NSApplication.shared
  let name = "QCControl-Focus-\(UUID())"
  let defaults = UserDefaults(suiteName: name)!
  defer { defaults.removePersistentDomain(forName: name) }
  let model = Headphones(connectAutomatically: false, transport: SlowTransport())
  defer { model.shutdown() }
  var presentations = 0
  var window: NSWindow?
  let controller = OnboardingController(headphones: model, defaults: defaults, presentWindow: {
   window = $0
   $0.orderOut(nil) // Permission prompt obscures setup; visibility must not mean closed.
   presentations += 1
  }, onFinish: {})
  defer { window?.close() }
  controller.show()
  XCTAssertTrue(controller.isOpen)
  XCTAssertFalse(controller.isVisible)
  model.bluetoothPermissionPending = true
  model.bluetoothPermissionPending = false
  try await Task.sleep(nanoseconds: 400_000_000)
  XCTAssertEqual(presentations, 2)
  model.bluetoothAvailability = .ready
  model.bluetoothPermissionPending = false
  try await Task.sleep(nanoseconds: 400_000_000)
  XCTAssertEqual(presentations, 2, "Normal Bluetooth updates must not steal focus")
 }
 @MainActor func testClosingSetupPreventsPermissionResponseFromReopeningIt() async throws {
  _ = NSApplication.shared
  for closeBeforeResponse in [true, false] {
   let name = "QCControl-Close-\(UUID())"
   let defaults = UserDefaults(suiteName: name)!
   defer { defaults.removePersistentDomain(forName: name) }
   let model = Headphones(connectAutomatically: false, transport: SlowTransport())
   defer { model.shutdown() }
   var presentations = 0
   var window: NSWindow?
   let controller = OnboardingController(headphones: model, defaults: defaults, presentWindow: {
    window = $0; presentations += 1
   }, onFinish: {})
   controller.show()
   model.bluetoothPermissionPending = true
   if closeBeforeResponse { window?.close() }
   model.bluetoothPermissionPending = false
   if !closeBeforeResponse { window?.close() }
   try await Task.sleep(nanoseconds: 400_000_000)
   XCTAssertFalse(controller.isOpen)
   XCTAssertEqual(presentations, 1, "Explicitly closed setup must stay closed")
  }
 }
 @MainActor func testWelcomeDoesNotRequestBluetoothOrStartDiscovery() async throws {
  let transport = SlowTransport()
  let headphones = Headphones(connectAutomatically: false, transport: transport)
  defer { headphones.shutdown() }
  try await Task.sleep(nanoseconds: 200_000_000)
  XCTAssertEqual(transport.count, 0)
  XCTAssertEqual(transport.discoveryCount, 0)
  XCTAssertEqual(headphones.bluetoothAvailability, .idle)
  XCTAssertFalse(headphones.connecting)
 }
 @MainActor func testDeferringSetupPersistsWithoutOptingIntoBluetooth() {
  let name = "QCControl-Onboarding-\(UUID())"
  let defaults = UserDefaults(suiteName: name)!
  defer { defaults.removePersistentDomain(forName: name) }
  let flow = OnboardingFlow(defaults: defaults)
  XCTAssertTrue(flow.needsWelcome)
  flow.finish()
  let nextLaunch = OnboardingFlow(defaults: defaults)
  XCTAssertFalse(nextLaunch.needsWelcome)
  XCTAssertFalse(nextLaunch.shouldAutoConnect)
 }
 @MainActor func testReadyRequiresConnectionAndCompletionIsExplicit() {
  let name = "QCControl-Onboarding-\(UUID())"
  let defaults = UserDefaults(suiteName: name)!
  defer { defaults.removePersistentDomain(forName: name) }
  let flow = OnboardingFlow(defaults: defaults)
  flow.continueToSetup()
  flow.startSearch()
  XCTAssertTrue(flow.shouldAutoConnect)
  XCTAssertEqual(flow.stage, .connect)
  flow.connectionChanged(true)
  XCTAssertEqual(flow.stage, .ready)
  XCTAssertTrue(flow.needsWelcome)
  flow.connectionChanged(false)
  XCTAssertEqual(flow.stage, .connect)
  flow.connectionChanged(true)
  flow.finish()
  XCTAssertFalse(OnboardingFlow(defaults: defaults).needsWelcome)
 }
 @MainActor func testDeferredMonitoringCanBeStartedOnceAndConnects() async throws {
  let transport = SlowTransport()
  let headphones = Headphones(connectAutomatically: false, transport: transport)
  defer { headphones.shutdown() }
  headphones.startConnection()
  headphones.startMonitoring()
  for _ in 0..<60 {
   if headphones.connected { break }
   try await Task.sleep(nanoseconds: 50_000_000)
  }
  XCTAssertTrue(headphones.connected)
  XCTAssertEqual(transport.discoveryCount, 1)
 }
}
