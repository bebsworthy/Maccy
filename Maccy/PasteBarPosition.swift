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
      return NSLocalizedString("PasteBarAtBottom", tableName: "AppearanceSettings", comment: "")
    case .top:
      return NSLocalizedString("PasteBarAtTop", tableName: "AppearanceSettings", comment: "")
    }
  }

  func origin(size: NSSize, screen: NSScreen? = NSScreen.forPopup) -> NSPoint {
    let frame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
    let originX = frame.minX + PasteBarPanelMetrics.edgePadding

    switch self {
    case .bottom:
      return NSPoint(x: originX, y: frame.minY + PasteBarPanelMetrics.edgePadding)
    case .top:
      return NSPoint(x: originX, y: frame.maxY - size.height - PasteBarPanelMetrics.edgePadding)
    }
  }
}

enum PasteBarPanelMetrics {
  static let defaultSize = NSSize(width: 1180, height: 272)
  static let minSize = NSSize(width: 680, height: 240)
  static let edgePadding: CGFloat = 18
}
