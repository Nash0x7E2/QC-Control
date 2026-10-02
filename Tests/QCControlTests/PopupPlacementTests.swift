import AppKit
import XCTest
@testable import QCControl

final class PopupPlacementTests: XCTestCase {
 func testGrowingPopupKeepsTopBelowMenuBar() {
  let screen = NSRect(x: 0, y: 61, width: 3200, height: 1709)
  let anchor = NSRect(x: 2600, y: 1770.5, width: 33, height: 29)
  for height in [CGFloat(171), 516, 560, 171] {
   let size = NSSize(width: 376, height: height)
   let origin = PopupPlacement.origin(anchor: anchor, size: size, currentX: 2400, visibleFrame: screen)
   let frame = NSRect(origin: origin, size: size)
   XCTAssertEqual(frame.maxY, 1764)
   XCTAssertTrue(screen.contains(frame))
  }
 }
 func testUsesNegativeCoordinateDisplayInsteadOfPrimaryScreen() {
  let screen = NSRect(x: -3200, y: 61, width: 3200, height: 1709)
  let anchor = NSRect(x: -585, y: 1770.5, width: 33, height: 29)
  let size = NSSize(width: 376, height: 516)
  let origin = PopupPlacement.origin(anchor: anchor, size: size, currentX: 2500, visibleFrame: screen)
  let frame = NSRect(origin: origin, size: size)
  XCTAssertTrue(screen.contains(frame))
  XCTAssertEqual(frame.midX, anchor.midX)
  XCTAssertEqual(frame.maxY, 1764)
 }
 func testPanelNearDisplayEdgeStaysWithinScreen() {
  let screen = NSRect(x: -3200, y: 61, width: 3200, height: 1709)
  let anchor = NSRect(x: -40, y: 1770.5, width: 33, height: 29)
  let size = NSSize(width: 376, height: 516)
  let origin = PopupPlacement.origin(anchor: anchor, size: size, currentX: -200, visibleFrame: screen)
  let frame = NSRect(origin: origin, size: size)
  XCTAssertEqual(frame.maxX, -6)
  XCTAssertTrue(screen.contains(frame))
 }
}
