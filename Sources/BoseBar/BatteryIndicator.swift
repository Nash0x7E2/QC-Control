import AppKit
import SwiftUI

enum BatteryStyle: String, CaseIterable, Identifiable {
 case percentage, ring, dots
 var id: String { rawValue }
 var title: String {
  switch self {
  case .percentage: return "Percentage"
  case .ring: return "Circular ring"
  case .dots: return "Ring of dots"
  }
 }
}

/// A template image keeps every style legible on light and dark menu bars.
enum BatteryArtwork {
 static func image(level: Int, style: BatteryStyle, brightness: Double = 1) -> NSImage {
  let fraction = CGFloat(min(100, max(0, level))) / 100
  let image = NSImage(size: NSSize(width: 22, height: 22), flipped: false) { bounds in
   let center = NSPoint(x: bounds.midX, y: bounds.midY)
   let radius: CGFloat = 9
   if style == .dots {
    let lit = Int((fraction * 12).rounded())
    for index in 0..<12 {
     let angle = CGFloat.pi / 2 - CGFloat(index) * .pi / 6
     let point = NSPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
     NSColor.black.withAlphaComponent(index < lit ? brightness : 0.18).setFill()
     NSBezierPath(ovalIn: NSRect(x: point.x - 1.05, y: point.y - 1.05, width: 2.1, height: 2.1)).fill()
    }
   } else {
    let track = NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    track.lineWidth = 1.65
    NSColor.black.withAlphaComponent(0.18).setStroke()
    track.stroke()
    if fraction > 0 {
     let arc = NSBezierPath()
     arc.lineWidth = 1.65
     arc.lineCapStyle = .round
     arc.appendArc(withCenter: center, radius: radius, startAngle: 90, endAngle: 90 - fraction * 360, clockwise: true)
     NSColor.black.withAlphaComponent(brightness).setStroke()
     arc.stroke()
    }
   }
   // Draw the familiar headphone glyph inside the battery ring: one compact icon.
   let glyph = NSImage(systemSymbolName: "headphones", accessibilityDescription: nil)?
    .withSymbolConfiguration(.init(pointSize: 10, weight: .medium))
   glyph?.draw(in: NSRect(x: center.x - 5, y: center.y - 5, width: 10, height: 10))
   return true
  }
  image.isTemplate = true
  return image
 }
}

