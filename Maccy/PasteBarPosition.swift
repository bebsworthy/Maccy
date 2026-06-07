import AppKit
import Defaults
import Foundation

enum PasteBarPosition: String, CaseIterable, Identifiable, CustomStringConvertible, Defaults.Serializable {
  case bottom
  case top

  var id: Self { self }

  var description: String {
    switch self {
    case .bottom:
      return "Bottom"
    case .top:
      return "Top"
    }
  }

  func origin(size: NSSize, screen: NSScreen? = NSScreen.forPopup) -> NSPoint {
    let frame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
    let centeredX = frame.midX - size.width / 2
    let minX = frame.minX + PasteBarPanelMetrics.edgePadding
    let maxX = frame.maxX - size.width - PasteBarPanelMetrics.edgePadding
    let x = max(minX, min(centeredX, maxX))

    switch self {
    case .bottom:
      return NSPoint(x: x, y: frame.minY + PasteBarPanelMetrics.edgePadding)
    case .top:
      return NSPoint(x: x, y: frame.maxY - size.height - PasteBarPanelMetrics.edgePadding)
    }
  }
}

enum PasteBarPanelMetrics {
  static let defaultSize = NSSize(width: 900, height: 220)
  static let minSize = NSSize(width: 520, height: 160)
  static let edgePadding: CGFloat = 18
}
