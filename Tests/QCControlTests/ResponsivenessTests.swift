import XCTest
import Combine
import BoseProtocol
@testable import QCControl

@MainActor final class SlowTransport: HeadphoneTransport {
 var onClose: (() -> Void)?
 var onPacket: ((Packet) -> Void)?
 var onLog: ((String) -> Void)?
 var count = 0
 var mode: UInt8 = 0
 var generation = 0
 var onModeRead: (() -> Void)?
 var writes: [UInt8] = []
 func devices() async -> [DeviceChoice] {
  [DeviceChoice(id: UserDefaults.standard.string(forKey: "headphone") ?? "test", name: "Test headphones", connected: true)]
 }
 func connect(_ address: String) async throws { try await Task.sleep(nanoseconds: 300_000_000) }
 func close() { generation += 1 }
 func request(_ p: Packet) async throws -> Packet {
  let session = generation
  count += 1
  if p.block == 31 && p.function == 3 && p.operation == 1 { onModeRead?() }
  try await Task.sleep(nanoseconds: 100_000_000)
  guard session == generation else { throw BluetoothFailure.message("Disconnected") }
  switch (p.block, p.function) {
  case (31, 2): return Packet(31, 2, 3, [2, 0, 0, 0, 0, 1])
  case (31, 3):
   if p.operation == 5 { mode = p.payload[0]; writes.append(mode) }
   return Packet(31, 3, p.operation == 5 ? 6 : 3, [mode])
  case (31, 6):
   var raw = [UInt8](repeating: 0, count: 47)
   raw[0] = p.payload[0]; raw[2] = raw[0] + 1; raw[42] = raw[0] == 0 ? 0 : 10
   return Packet(31, 6, 3, raw)
  case (31, 10): throw BluetoothFailure.message("Unsupported")
  case (2, 2): return Packet(2, 2, 3, [90, 255, 255, 0])
  default: throw BluetoothFailure.message("Unexpected request")
  }
 }
}

final class ResponsivenessTests: XCTestCase {
 @MainActor private func ready(_ model: Headphones) async throws {
  for _ in 0..<100 {
   if model.connected && !model.connecting { return }
   try await Task.sleep(nanoseconds: 50_000_000)
  }
  XCTFail("Connection did not complete")
 }

 @MainActor func testSlowWorkerDoesNotBlockMainRunLoop() async throws {
  let worker = BluetoothWorker()
  defer { worker.enqueue { worker.shutdown() } }
  var ticks = 0
  let timer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { _ in ticks += 1 }
  defer { timer.invalidate() }
  let background = await withCheckedContinuation { continuation in
   worker.enqueue {
    let offMain = !Thread.isMainThread
    Thread.sleep(forTimeInterval: 0.7) // Deliberately block exactly the real I/O executor.
    continuation.resume(returning: offMain)
   }
  }
  XCTAssertTrue(background)
  XCTAssertGreaterThan(ticks, 15, "Main run loop stalled behind the Bluetooth worker")
 }

 @MainActor func testUnchangedPollingDoesNotDisableOrRepublishUI() async throws {
  let transport = SlowTransport()
  let model = Headphones(transport: transport)
  defer { model.shutdown() }
  try await ready(model)
  let startingReads = transport.count
  var changes = 0
  var busyTransitions = 0
  let observation = model.objectWillChange.sink { changes += 1 }
  let busy = model.$busy.dropFirst().sink { if $0 { busyTransitions += 1 } }
  defer { observation.cancel(); busy.cancel() }
  try await Task.sleep(nanoseconds: 5_800_000_000)
  XCTAssertGreaterThan(transport.count, startingReads, "The test must include a real poll")
  XCTAssertEqual(busyTransitions, 0, "Background refresh must never disable controls")
  XCTAssertEqual(changes, 0, "Identical device snapshots must not invalidate the UI")
 }

 @MainActor func testCommandDuringSlowPollIsQueuedInsteadOfDropped() async throws {
  let transport = SlowTransport()
  let model = Headphones(transport: transport)
  defer { model.shutdown() }
  try await ready(model)
  var submitted = false
  transport.onModeRead = {
   guard !submitted else { return }
   submitted = true
   model.switchMode(1)
  }
  try await Task.sleep(nanoseconds: 6_400_000_000)
  XCTAssertTrue(submitted)
  XCTAssertEqual(transport.writes, [1])
  XCTAssertEqual(model.currentMode, 1)
  XCTAssertNil(model.error)
 }

 @MainActor func testPollingYieldsToSliderAndReconnectRemainsResponsive() async throws {
  let transport = SlowTransport()
  let model = Headphones(transport: transport)
  defer { model.shutdown() }
  try await ready(model)
  model.isEditingLevel = true
  let count = transport.count
  try await Task.sleep(nanoseconds: 5_600_000_000)
  XCTAssertEqual(transport.count, count, "Do not poll while the slider is being dragged")
  model.isEditingLevel = false
  var ticks = 0
  let timer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { _ in ticks += 1 }
  defer { timer.invalidate() }
  model.startConnection()
  try await ready(model)
  XCTAssertGreaterThan(ticks, 15)
  XCTAssertFalse(model.busy)
  XCTAssertTrue(model.connected)
 }
}
