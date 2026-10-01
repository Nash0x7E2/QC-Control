import AppKit
import Combine
import CoreBluetooth
import ServiceManagement
import BoseProtocol

@MainActor final class Headphones: ObservableObject {
 @Published var devices: [DeviceChoice] = []
 @Published var selected = UserDefaults.standard.string(forKey: "headphone") ?? ""
 @Published var name = "Bose QC Ultra Headphones"
 @Published var status = "Looking for headphones…"
 @Published var connected = false
 @Published var busy = false
 @Published var connecting = false
 var isEditingLevel = false
 @Published var battery: Int?
 @Published var modes: [ListeningMode] = []
 @Published var currentMode: UInt8?
 @Published var audio: AudioSettings?
 @Published var supportsANCOff = false
 @Published var error: String?
 @Published var loginEnabled = SMAppService.mainApp.status == .enabled
 @Published var showBattery = UserDefaults.standard.bool(forKey: "showBattery") {
  didSet { UserDefaults.standard.set(showBattery, forKey: "showBattery") }
 }
 @Published var batteryStyle = BatteryStyle(rawValue: UserDefaults.standard.string(forKey: "batteryStyle") ?? "") ?? .spitz {
  didSet { UserDefaults.standard.set(batteryStyle.rawValue, forKey: "batteryStyle") }
 }
 @Published var animateBattery = UserDefaults.standard.bool(forKey: "animateBattery") {
  didSet { UserDefaults.standard.set(animateBattery, forKey: "animateBattery") }
 }
 private let transport: HeadphoneTransport
 private let requiresBluetoothAuthorization: Bool
 private var operationRunning = false
 private var operationWaiters: [CheckedContinuation<Void, Never>] = []
 private var nextRetry = Date.distantPast
 private var retryDelay: TimeInterval = 5
 private var poll: Task<Void, Never>?
 private var observers: [NSObjectProtocol] = []
 private var paused = false
 private var lastBattery = Date.distantPast
 private var diagnostics: [String] = []
 private var permissionManager: CBCentralManager?
 private var session = 0
 private var allModes: [ListeningMode] = []
 private var liveSettings = false
 private var didHardwareTest = false
 @Published var hardwareTestResult: String?


 init(connectAutomatically: Bool = true, transport injectedTransport: HeadphoneTransport? = nil) {
  transport = injectedTransport ?? BluetoothTransport()
  requiresBluetoothAuthorization = injectedTransport == nil
  if connectAutomatically && requiresBluetoothAuthorization { permissionManager = CBCentralManager(delegate: nil, queue: .main) }
  transport.onLog = { [weak self] line in
   guard let self else { return }; self.diagnostics.append(line)
   if self.diagnostics.count > 250 { self.diagnostics.removeFirst(50) }
  }
  transport.onClose = { [weak self] in
   guard let self else { return }
   self.session += 1
   self.resetState()
   self.nextRetry = Date().addingTimeInterval(self.retryDelay)
   self.status = "Disconnected · retrying automatically"
  }
  transport.onPacket = { [weak self] packet in
   guard packet.operation == 3 || packet.operation == 6 else { return }
   if packet.block == 31 && packet.function == 3, let mode = packet.payload.first { if self?.currentMode != mode { self?.currentMode = mode } }
  }
  let nc = NSWorkspace.shared.notificationCenter
  observers.append(nc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
   Task { @MainActor in self?.paused = true; self?.disconnect() }
  })
  observers.append(nc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
   Task { @MainActor in self?.paused = false; self?.startConnection() }
  })
  if CommandLine.arguments.contains("--diagnose") {
   Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
    Task { @MainActor in
     try? self?.diagnosticText.write(toFile: "/tmp/qc-control-diagnostics.txt", atomically: true, encoding: .utf8)
    }
   }
  }
  guard connectAutomatically else { return }
  poll = Task { [weak self] in
   while !Task.isCancelled {
    guard let self else { return }
    if !self.paused && !self.operationRunning && !self.isEditingLevel {
     if self.connected { await self.perform(background: true) { try await self.refresh() } }
     else if Date() >= self.nextRetry { await self.connect() }
    }
    try? await Task.sleep(nanoseconds: 5_000_000_000)
   }
  }
 }
 private func resetState() {
  connected = false; battery = nil; audio = nil; currentMode = nil; modes = []; allModes = []; liveSettings = false; supportsANCOff = false
 }
 func disconnect() { session += 1; transport.close(); resetState() }
 func shutdown() { paused = true; poll?.cancel(); disconnect() }
 func startConnection() {
  guard !connecting else { return }
  nextRetry = .distantPast; retryDelay = 5
  disconnect()
  Task { await connect() }
 }
 func selectDevice(_ id: String) { selected = id; UserDefaults.standard.set(id, forKey: "headphone"); startConnection() }
 private func acquireOperation() async {
  if operationRunning { await withCheckedContinuation { operationWaiters.append($0) } }
  else { operationRunning = true }
 }
 private func releaseOperation() {
  if operationWaiters.isEmpty { operationRunning = false }
  else { operationWaiters.removeFirst().resume() }
 }
 private func perform(background: Bool = false, _ body: () async throws -> Void) async {
  // Background work yields to gestures and queued user commands, never disables UI.
  if background && (operationRunning || isEditingLevel) { return }
  let generation = session
  await acquireOperation()
  guard generation == session, !paused else { releaseOperation(); return }
  if !background { busy = true }
  defer { if !background { busy = false }; releaseOperation() }
  do {
   try await body()
   // A successful poll must not erase a user's actionable command error.
   if !background && error != nil { error = nil }
  } catch is CancellationError { }
  catch { if self.error != error.localizedDescription { self.error = error.localizedDescription } }
 }
 private func request(_ packet: Packet) async throws -> Packet {
  let generation = session
  let reply: Packet
  do { reply = try await transport.request(packet) }
  catch {
   guard generation == session, !paused else { throw CancellationError() }
   throw error
  }
  guard generation == session, !paused else { throw CancellationError() }
  return reply
 }
 private func connect() async {
  guard !connecting, !paused else { return }
  connecting = true
  defer {
   connecting = false
   if !connected {
    nextRetry = Date().addingTimeInterval(retryDelay)
    retryDelay = min(retryDelay * 2, 60)
   }
  }
  await perform(background: true) {
   if requiresBluetoothAuthorization && (CBCentralManager.authorization == .denied || CBCentralManager.authorization == .restricted) {
    throw BluetoothFailure.message("Allow QC Control in System Settings → Privacy & Security → Bluetooth, then reopen the app.")
   }
   if requiresBluetoothAuthorization && CBCentralManager.authorization == .notDetermined { status = "Waiting for Bluetooth permission…"; return }
   let generation = session
   let paired = await transport.devices()
   guard generation == session, !paused else { throw CancellationError() }
   if devices != paired { devices = paired }
   guard let device = paired.first(where: { $0.id == selected }) ?? paired.first else {
    if status != "Pair your QC Ultra headphones in Bluetooth Settings" { status = "Pair your QC Ultra headphones in Bluetooth Settings" }
    return
   }
   if selected != device.id { selected = device.id; UserDefaults.standard.set(selected, forKey: "headphone") }
   if name != device.name { name = device.name }
   status = "Connecting…"
   try await transport.connect(selected)
   guard generation == session, !paused else { throw CancellationError() }
   status = "Reading headphone controls…"
   let capabilities = try await request(Packet(31, 2))
   guard capabilities.payload.count >= 6 else { throw BluetoothFailure.message("The headphones returned an unrecognized capability format.") }
   supportsANCOff = capabilities.payload[5] & 32 != 0
   let count = min(Int(capabilities.payload[0]) + Int(capabilities.payload[1]), 32)
   modes = []; allModes = []
   for index in 0..<count {
    if let reply = try? await request(Packet(31, 6, 1, [UInt8(index)])), let mode = ListeningMode(reply.payload) { allModes.append(mode) }
    guard generation == session, !paused else { throw CancellationError() }
   }
   modes = allModes.filter { !$0.editable || $0.configured }.sorted { $0.id < $1.id }
   // Only enable the level slider when the live audio-settings register is readable.
   if let reply = try? await request(Packet(31, 10)), let settings = AudioSettings(reply.payload) { audio = settings; liveSettings = true }
   try await refresh()
   connected = true; status = "Connected"; retryDelay = 5
   if error != nil { error = nil }
   if CommandLine.arguments.contains("--hardware-test") && !didHardwareTest {
    didHardwareTest = true
    let originalMode = currentMode
    do {
     try await applyAudio(level: 4, enabled: nil)
     guard audio?.cancellation == 4 else { throw BluetoothFailure.message("Level 4 verification failed") }
     try await applyAudio(level: 7, enabled: nil)
     guard audio?.cancellation == 7 else { throw BluetoothFailure.message("Level 7 verification failed") }
     hardwareTestResult = "PASS: custom mode levels 4 and 7 read back correctly."
    } catch { hardwareTestResult = "FAIL: " + error.localizedDescription }
    if let originalMode {
     _ = try? await request(Packet(31, 3, 5, [originalMode, 0]))
     try? await refresh()
     hardwareTestResult = (hardwareTestResult ?? "") + (currentMode == originalMode ? " Original mode restored." : " Could not verify original mode restoration.")
    }
    try? diagnosticText.write(toFile: "/tmp/qc-control-hardware-test.txt", atomically: true, encoding: .utf8)
   }
  }
 }
 private func refresh() async throws {
  let reply = try await request(Packet(31, 3))
  if currentMode != reply.payload.first { currentMode = reply.payload.first }
  if liveSettings {
   let reply = try await request(Packet(31, 10))
   if audio != AudioSettings(reply.payload) { audio = AudioSettings(reply.payload) }
  } else if let currentMode {
   let reply = try await request(Packet(31, 6, 1, [currentMode]))
   if let mode = ListeningMode(reply.payload) {
    updateMode(mode)
    if audio != mode.audioSettings { audio = mode.audioSettings }
   }
  }
  if Date().timeIntervalSince(lastBattery) > 30 || battery == nil {
   let reply = try await request(Packet(2, 2))
   if let value = reply.payload.first, value <= 100, battery != Int(value) { battery = Int(value) }
   lastBattery = Date()
  }
 }
 func switchMode(_ id: UInt8) {
  Task { await perform {
   _ = try await request(Packet(31, 3, 5, [id, 0]))
   try await refresh()
   guard currentMode == id else { throw BluetoothFailure.message("The headphones have not applied that mode. Please try again.") }
  } }
 }
 private func updateMode(_ mode: ListeningMode) {
  allModes.removeAll { $0.id == mode.id }; allModes.append(mode)
  let updatedModes = allModes.filter { !$0.editable || $0.configured }.sorted { $0.id < $1.id }
  if modes != updatedModes { modes = updatedModes }
 }
 func changeAudio(level: Int? = nil, enabled: Bool? = nil) {
  Task { await perform { try await applyAudio(level: level, enabled: enabled) } }
 }
 private func applyAudio(level: Int?, enabled: Bool?) async throws {
  guard audio != nil else { return }
  if liveSettings {
   let latest = try await request(Packet(31, 10))
   guard let original = AudioSettings(latest.payload) else { throw BluetoothFailure.message("Unknown audio-settings format.") }
   let desired = original.changing(level: level, enabled: enabled)
   _ = try await request(Packet(31, 10, 2, desired.raw))
   let result = try await request(Packet(31, 10))
   audio = AudioSettings(result.payload)
   guard audio == desired else { throw BluetoothFailure.message("The headphones did not retain this setting.") }
  } else {
   guard let level else { throw BluetoothFailure.message("This model does not expose ANC on/off. Use Quiet or Aware.") }
   // Use our own profile, never overwrite a user's existing custom modes.
   guard let candidate = allModes.first(where: { $0.editable && ($0.name == "QC Control" || $0.name == "BoseBar") }) ?? allModes.first(where: { $0.allowsLevel && !$0.configured }) else {
    throw BluetoothFailure.message("No free custom-mode slot. Remove an unused mode in the Bose app, then reconnect.")
   }
   let latest = try await request(Packet(31, 6, 1, [candidate.id]))
   guard let original = ListeningMode(latest.payload), original.allowsLevel,
         !original.configured || original.name == "QC Control" || original.name == "BoseBar" else {
    throw BluetoothFailure.message("The custom mode changed. Reconnect to refresh available slots.")
   }
   _ = try await request(Packet(31, 6, 2, original.writePayload(level: level, newName: "QC Control")))
   let readback = try await request(Packet(31, 6, 1, [candidate.id]))
   guard let updated = ListeningMode(readback.payload), updated.audioSettings?.cancellation == level else {
    throw BluetoothFailure.message("The headphones did not retain the custom noise level.")
   }
   updateMode(updated)
   _ = try await request(Packet(31, 3, 5, [candidate.id, 0]))
   try await refresh()
   guard currentMode == candidate.id, audio?.cancellation == level else { throw BluetoothFailure.message("Could not verify the custom listening mode.") }
  }
 }
 func setLogin(_ enabled: Bool) {
  do {
   if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
   loginEnabled = SMAppService.mainApp.status == .enabled
   if enabled && !loginEnabled { error = "Approve QC Control in System Settings → General → Login Items." }
  } catch { self.error = error.localizedDescription }
 }
 func settings() { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings")!) }
 func copyDiagnostics() {
  NSPasteboard.general.clearContents()
  NSPasteboard.general.setString(diagnosticText, forType: .string)
 }
 var diagnosticText: String {
  "QC Control\nHardware test: \(hardwareTestResult ?? "not requested")\nDevice: \(name)\nStatus: \(status)\nBattery: \(battery.map(String.init) ?? "unknown")\nMode: \(currentMode.map(String.init) ?? "unknown")\nModes: \(modes.map(\.name).joined(separator: ", "))\nAudio: \(audio?.raw.description ?? "unavailable")\nANC off supported: \(supportsANCOff)\nError: \(error ?? "none")\n" + diagnostics.joined(separator: "\n")
 }
}
