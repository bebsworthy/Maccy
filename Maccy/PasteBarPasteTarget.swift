import AppKit

struct PasteBarPasteTarget {
  let application: NSRunningApplication?
}

protocol PasteBarPasteTargetRestoring {
  func capture() -> PasteBarPasteTarget?
  func restore(_ target: PasteBarPasteTarget) -> Bool
}

struct SystemPasteBarPasteTargetRestorer: PasteBarPasteTargetRestoring {
  func capture() -> PasteBarPasteTarget? {
    guard let application = NSWorkspace.shared.frontmostApplication,
          application.bundleIdentifier != Bundle.main.bundleIdentifier else {
      return nil
    }

    return PasteBarPasteTarget(application: application)
  }

  func restore(_ target: PasteBarPasteTarget) -> Bool {
    guard let application = target.application else {
      return false
    }

    return application.activate(options: [.activateIgnoringOtherApps])
  }
}

protocol PasteBarDirectPasting {
  func paste()
}

struct MaccyPasteBarDirectPaster: PasteBarDirectPasting {
  func paste() {
    Clipboard.shared.paste()
  }
}
