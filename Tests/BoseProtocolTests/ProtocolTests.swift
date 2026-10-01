import XCTest
@testable import BoseProtocol
final class ProtocolTests: XCTestCase {
 func testEveryFragmentBoundary() {
  let packets = [Packet(31, 3, 3, [2]), Packet(31, 10, 3, [7, 0, 2, 0, 1]), Packet(2, 2, 3, [100, 255, 255, 0])]
  let wire = packets.flatMap(\.bytes)
  for boundary in 0...wire.count {
   var decoder = PacketDecoder()
   let first = decoder.append(Array(wire.prefix(boundary)))
   let second = decoder.append(Array(wire.dropFirst(boundary)))
   XCTAssertEqual(first + second, packets)
  }
 }
 func testBytewiseFramesAndOperatorBits() {
  var decoder = PacketDecoder()
  var result: [Packet] = []
  for byte: UInt8 in [31, 3, 0x43, 1, 2, 7, 4, 6, 0] { result += decoder.append([byte]) }
  XCTAssertEqual(result, [Packet(31, 3, 3, [2]), Packet(7, 4, 6)])
 }
 func testNoiseScaleAndPreservation() {
  let original = AudioSettings([0, 1, 2, 1, 0])!
  XCTAssertEqual(original.cancellation, 10)
  XCTAssertEqual(original.changing(level: 3).raw, [7, 0, 2, 0, 1])
  XCTAssertEqual(original.changing(enabled: true).raw, [0, 1, 2, 1, 1])
  XCTAssertEqual(original.changing(level: -4).cancellation, 0)
  XCTAssertEqual(original.changing(level: 100).cancellation, 10)
 }
 func testRejectUnknownFormats() {
  XCTAssertNil(AudioSettings([0, 1]))
  XCTAssertNil(AudioSettings([11, 0, 0, 0, 1]))
  XCTAssertNil(ListeningMode([0, 1, 2]))
 }
 func testModeNamesAndFlags() {
  var bytes = [UInt8](repeating: 0, count: 48)
  bytes[0] = 2; bytes[2] = 34
  XCTAssertEqual(ListeningMode(bytes)?.name, "Immersion")
  bytes[3] = 1; bytes[4] = 1
  bytes.replaceSubrange(6..<11, with: Array("Focus".utf8))
  let mode = ListeningMode(bytes)!
  XCTAssertEqual(mode.name, "Focus"); XCTAssertTrue(mode.editable); XCTAssertTrue(mode.configured)
 }
}

extension ProtocolTests {
 func testUltraFirstGenerationModeWrite() {
  var bytes = [UInt8](repeating: 0, count: 47)
  bytes[0] = 3; bytes[3] = 1; bytes[41] = 13; bytes[42] = 10; bytes[44] = 2
  let mode = ListeningMode(bytes)!
  XCTAssertTrue(mode.allowsLevel)
  XCTAssertEqual(mode.audioSettings?.cancellation, 0)
  let write = mode.writePayload(level: 7, newName: "BoseBar")
  XCTAssertEqual(write.count, 39)
  XCTAssertEqual(Array(write[3..<10]), Array("BoseBar".utf8))
  XCTAssertEqual(Array(write[35..<39]), [3, 0, 2, 0])
  XCTAssertEqual(bytes[42], 10)
 }
}
