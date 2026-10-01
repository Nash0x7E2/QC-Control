import Foundation
import IOBluetooth
import BoseProtocol

struct DeviceChoice: Identifiable, Equatable {
 let id: String
 let name: String
 let connected: Bool
}
enum BluetoothFailure: LocalizedError {
 case message(String)
 var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

@MainActor protocol HeadphoneTransport: AnyObject {
 var onClose: (() -> Void)? { get set }
 var onPacket: ((Packet) -> Void)? { get set }
 var onLog: ((String) -> Void)? { get set }
 func devices() async -> [DeviceChoice]
 func connect(_ address: String) async throws
 func request(_ packet: Packet) async throws -> Packet
 func close()
}

/// Only value snapshots and continuations cross this boundary. No IOBluetooth
/// object or synchronous driver call is ever accessed on the UI thread.
@MainActor final class BluetoothTransport: HeadphoneTransport {
 var onClose: (() -> Void)?
 var onPacket: ((Packet) -> Void)?
 var onLog: ((String) -> Void)?
 private let worker = BluetoothWorker()
 init() {
  worker.onClose = { [weak self] in DispatchQueue.main.async { self?.onClose?() } }
  worker.onPacket = { [weak self] packet in DispatchQueue.main.async { self?.onPacket?(packet) } }
  worker.onLog = { [weak self] line in DispatchQueue.main.async { self?.onLog?(line) } }
 }
 deinit { worker.enqueue { [worker] in worker.shutdown() } }
 func devices() async -> [DeviceChoice] {
  await withCheckedContinuation { continuation in
   worker.enqueue { [worker] in continuation.resume(returning: worker.discover()) }
  }
 }
 func connect(_ address: String) async throws {
  try await withCheckedThrowingContinuation { continuation in
   worker.enqueue { [worker] in worker.connect(address, continuation: continuation) }
  }
 }
 func request(_ packet: Packet) async throws -> Packet {
  try await withCheckedThrowingContinuation { continuation in
   worker.enqueue { [worker] in worker.request(packet, continuation: continuation) }
  }
 }
 func close() { worker.enqueue { [worker] in worker.close() } }
}

private final class BluetoothWork: NSObject {
 let run: () -> Void
 init(_ run: @escaping () -> Void) { self.run = run }
}

/// A serial run-loop thread is required for RFCOMM delegate delivery. Using a
/// generic concurrent Task or a dispatch queue alone does not provide that loop.
final class BluetoothWorker: NSObject, IOBluetoothRFCOMMChannelDelegate {
 private let thread: Thread
 private var channel: IOBluetoothRFCOMMChannel?
 private var decoder = PacketDecoder()
 private var pending: (Packet, CheckedContinuation<Packet, Error>)?
 private var opening: CheckedContinuation<Void, Error>?
 private var timeout: Timer?
 var onClose: (() -> Void)?
 var onPacket: ((Packet) -> Void)?
 var onLog: ((String) -> Void)?
 override init() {
  thread = Thread {
   let port = Port()
   RunLoop.current.add(port, forMode: .default)
   while !Thread.current.isCancelled {
    RunLoop.current.run(mode: .default, before: .distantFuture)
   }
  }
  thread.name = "QC Control Bluetooth"
  thread.qualityOfService = .utility
  super.init()
  thread.start()
 }
 func enqueue(_ work: @escaping () -> Void) {
  perform(#selector(execute(_:)), on: thread, with: BluetoothWork(work), waitUntilDone: false)
 }
 @objc private func execute(_ work: BluetoothWork) {
  precondition(!Thread.isMainThread)
  work.run()
 }
 func shutdown() {
  close()
  thread.cancel()
  CFRunLoopStop(CFRunLoopGetCurrent())
 }
 func discover() -> [DeviceChoice] {
  precondition(!Thread.isMainThread)
  var seen = Set<String>()
  return (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []).compactMap { device in
   let name = device.name ?? ""
   let n = name.lowercased()
   guard (n.contains("qc ultra") || n.contains("quietcomfort ultra")), n.contains("headphones"),
         let address = device.addressString, seen.insert(address).inserted else { return nil }
   return DeviceChoice(id: address, name: name, connected: device.isConnected())
  }.sorted { $0.connected && !$1.connected }
 }
 func connect(_ address: String, continuation: CheckedContinuation<Void, Error>) {
  precondition(!Thread.isMainThread)
  close()
  guard let device = IOBluetoothDevice(addressString: address) else {
   continuation.resume(throwing: BluetoothFailure.message("Headphones are no longer paired. Open Bluetooth Settings.")); return
  }
  opening = continuation
  let result = device.openRFCOMMChannelAsync(&channel, withChannelID: 2, delegate: self)
  guard result == kIOReturnSuccess else {
   failConnection("Could not connect (\(result)). Connect your headphones in Bluetooth Settings, then retry."); return
  }
  // The callback is the authority; no repeated isOpen()/IPC polling on the UI.
  if opening != nil {
   timeout = Timer.scheduledTimer(withTimeInterval: 8, repeats: false) { [weak self] _ in
    self?.failConnection("Connection timed out. Check that your headphones are on and nearby.")
   }
  }
 }
 private func failConnection(_ message: String) {
  let continuation = opening; opening = nil
  close()
  continuation?.resume(throwing: BluetoothFailure.message(message))
 }
 func close() {
  precondition(!Thread.isMainThread)
  timeout?.invalidate(); timeout = nil
  let old = channel; channel = nil
  old?.setDelegate(nil); _ = old?.close()
  decoder = PacketDecoder()
  let connection = opening; opening = nil
  connection?.resume(throwing: BluetoothFailure.message("Connection cancelled."))
  if let (_, continuation) = pending {
   pending = nil; continuation.resume(throwing: BluetoothFailure.message("Headphones disconnected."))
  }
 }
 func request(_ packet: Packet, continuation: CheckedContinuation<Packet, Error>) {
  precondition(!Thread.isMainThread)
  guard let channel, opening == nil else {
   continuation.resume(throwing: BluetoothFailure.message("Headphones are not connected.")); return
  }
  guard pending == nil else {
   continuation.resume(throwing: BluetoothFailure.message("A headphone command is already in progress.")); return
  }
  pending = (packet, continuation)
  onLog?("TX " + packet.bytes.map { String(format: "%02x", $0) }.joined(separator: " "))
  var bytes = packet.bytes
  let result = bytes.withUnsafeMutableBytes { channel.writeSync($0.baseAddress!, length: UInt16($0.count)) }
  guard result == kIOReturnSuccess else {
   finish(.failure(BluetoothFailure.message("Bluetooth write failed (\(result)).")))
   close(); onClose?(); return
  }
  if pending != nil {
   timeout = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in
    self?.finish(.failure(BluetoothFailure.message("Headphones did not respond. Retrying the connection.")))
    self?.close(); self?.onClose?()
   }
  }
 }
 private func finish(_ result: Result<Packet, Error>) {
  timeout?.invalidate(); timeout = nil
  guard let (_, continuation) = pending else { return }
  pending = nil; continuation.resume(with: result)
 }
 func rfcommChannelOpenComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
  enqueue { [self] in
   guard rfcommChannel === channel, let continuation = opening else { return }
   if error != kIOReturnSuccess { failConnection("Could not open the headphone connection (\(error))."); return }
   timeout?.invalidate(); timeout = nil; opening = nil
   continuation.resume()
  }
 }
 func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
  enqueue { [self] in
   guard rfcommChannel === channel else { return }
   close(); onClose?()
  }
 }
 func rfcommChannelData(_ rfcommChannel: IOBluetoothRFCOMMChannel!, data pointer: UnsafeMutableRawPointer!, length: Int) {
  guard let pointer, length > 0 else { return }
  let bytes = Array(UnsafeBufferPointer(start: pointer.assumingMemoryBound(to: UInt8.self), count: length))
  enqueue { [self] in
   guard rfcommChannel === channel else { return }
   for packet in decoder.append(bytes) {
    onLog?("RX " + packet.bytes.map { String(format: "%02x", $0) }.joined(separator: " "))
    onPacket?(packet)
    guard let (request, _) = pending, request.block == packet.block, request.function == packet.function else { continue }
    if packet.operation == 4 {
     finish(.failure(BluetoothFailure.message("Headphones rejected this control (code \(packet.payload.first.map(String.init) ?? "unknown")).")))
    } else if packet.operation == 3 || packet.operation == 6 {
     if request.block == 31 && request.function == 6 && request.payload.first != packet.payload.first { continue }
     finish(.success(packet))
    }
   }
  }
 }
}
