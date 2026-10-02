import XCTest
@testable import QCControl

final class OnboardingTests: XCTestCase {
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
