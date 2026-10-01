import Foundation

public struct Packet: Equatable {
 public let block: UInt8
 public let function: UInt8
 public let operation: UInt8
 public let payload: [UInt8]
 public init(_ block: UInt8, _ function: UInt8, _ operation: UInt8 = 1, _ payload: [UInt8] = []) {
  precondition(payload.count <= 255)
  self.block = block; self.function = function; self.operation = operation; self.payload = payload
 }
 public var bytes: [UInt8] { [block, function, operation, UInt8(payload.count)] + payload }
}

/// RFCOMM is a byte stream: one callback can contain part of a packet or several packets.
public struct PacketDecoder {
 private var buffer: [UInt8] = []
 public init() {}
 public mutating func append(_ bytes: [UInt8]) -> [Packet] {
  buffer += bytes
  var packets: [Packet] = []
  while buffer.count >= 4 {
   let length = 4 + Int(buffer[3])
   guard buffer.count >= length else { break }
   packets.append(Packet(buffer[0], buffer[1], buffer[2] & 15, Array(buffer[4..<length])))
   buffer.removeFirst(length)
  }
  return packets
 }
}

public struct AudioSettings: Equatable {
 public var raw: [UInt8]
 public init?(_ payload: [UInt8]) {
  guard payload.count == 5, payload[0] <= 10 else { return nil }
  raw = payload
 }
 public var cancellation: Int { 10 - Int(raw[0]) }
 public var enabled: Bool { raw[4] != 0 }
 public func changing(level: Int? = nil, enabled: Bool? = nil) -> AudioSettings {
  var result = self
  if let level {
   result.raw[0] = UInt8(10 - min(10, max(0, level)))
   result.raw[1] = 0 // Disable automatic variation when explicitly setting a level.
   result.raw[3] = 0 // Wind reduction overrides manual CNC.
   result.raw[4] = 1
  }
  if let enabled { result.raw[4] = enabled ? 1 : 0 }
  return result
 }
}

public struct ListeningMode: Identifiable, Equatable {
 public let id: UInt8
 public let name: String
 public let raw: [UInt8]
 public var editable: Bool { raw[3] != 0 }
 public var configured: Bool { raw[4] != 0 }
 public var allowsLevel: Bool { editable && raw[41] & 1 != 0 }
 public var audioSettings: AudioSettings? {
  AudioSettings([raw[42], raw[43], raw[44], raw[46], raw.count == 48 ? raw[47] : 1])
 }
 public func writePayload(level: Int, newName: String? = nil) -> [UInt8] {
  var bytes = Array(raw[0..<3])
  if let newName {
   let nameBytes = Array(newName.utf8.prefix(31))
   bytes += nameBytes + [UInt8](repeating: 0, count: 32 - nameBytes.count)
  } else { bytes += raw[6..<38] }
  bytes += [UInt8(10 - min(10, max(0, level))), 0, raw[44], 0]
  if raw.count == 48 { bytes.append(raw[47]) }
  return bytes
 }
 public init?(_ payload: [UInt8]) {
  guard payload.count == 47 || payload.count == 48 else { return nil }
  raw = payload; id = payload[0]
  let custom = String(decoding: payload[6..<38].prefix(while: { $0 != 0 }), as: UTF8.self)
  let names: [UInt8: String] = [1:"Quiet", 2:"Aware", 7:"Commute", 8:"Outdoor", 9:"Workout", 10:"Home", 11:"Work", 12:"Music", 13:"Focus", 14:"Relax", 15:"Flight", 34:"Immersion", 36:"Cinema"]
  name = custom.isEmpty ? (names[payload[2]] ?? "Mode \(payload[0] + 1)") : custom
 }
}
