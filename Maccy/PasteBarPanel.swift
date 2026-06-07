import AppKit
import Defaults
import SwiftUI

private let escapeKeyCode: UInt16 = 53

class PasteBarPanel<Content: View>: NSPanel, NSWindowDelegate {
  var isPresented = false
  private(set) var pasteTarget: PasteBarPasteTarget?

  private let onClose: () -> Void
  private let pasteTargetRestorer: PasteBarPasteTargetRestoring
  private let rootView: () -> Content

  init(
    contentRect: NSRect = NSRect(origin: .zero, size: PasteBarPanelMetrics.defaultSize),
    identifier: String = "",
    onClose: @escaping () -> Void,
    pasteTargetRestorer: PasteBarPasteTargetRestoring = SystemPasteBarPasteTargetRestorer(),
    view: @escaping () -> Content
  ) {
    self.onClose = onClose
    self.pasteTargetRestorer = pasteTargetRestorer
    self.rootView = view

    super.init(
      contentRect: contentRect,
      styleMask: [.nonactivatingPanel, .closable, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )

    self.identifier = NSUserInterfaceItemIdentifier(identifier)
    delegate = self

    animationBehavior = .none
    isFloatingPanel = true
    level = .statusBar
    collectionBehavior = [.auxiliary, .stationary, .moveToActiveSpace, .fullScreenAuxiliary]
    titleVisibility = .hidden
    titlebarAppearsTransparent = true
    hidesOnDeactivate = false
    backgroundColor = .clear
    titlebarSeparatorStyle = .none
    minSize = PasteBarPanelMetrics.minSize

    standardWindowButton(.closeButton)?.isHidden = true
    standardWindowButton(.miniaturizeButton)?.isHidden = true
    standardWindowButton(.zoomButton)?.isHidden = true

    contentView = NSHostingView(
      rootView: rootView()
        .ignoresSafeArea()
    )
    contentView?.layer?.cornerRadius = Popup.cornerRadius + Popup.horizontalPadding
  }

  func toggle(position: PasteBarPosition = Defaults[.pasteBarPosition]) {
    if isPresented {
      close()
    } else {
      open(position: position)
    }
  }

  func open(position: PasteBarPosition = Defaults[.pasteBarPosition]) {
    pasteTarget = pasteTargetRestorer.capture()

    let screen = NSScreen.forPopup ?? NSScreen.main
    let visibleFrame = screen?.visibleFrame ?? .zero
    let maxWidth = max(
      PasteBarPanelMetrics.minSize.width,
      visibleFrame.width - PasteBarPanelMetrics.edgePadding * 2
    )
    let maxHeight = max(
      PasteBarPanelMetrics.minSize.height,
      visibleFrame.height - PasteBarPanelMetrics.edgePadding * 2
    )
    let size = NSSize(
      width: maxWidth,
      height: min(PasteBarPanelMetrics.defaultSize.height, maxHeight)
    )

    setContentSize(size)
    setFrameOrigin(position.origin(size: frame.size, screen: screen))
    orderFrontRegardless()
    makeKey()
    isPresented = true
  }

  override func resignKey() {
    super.resignKey()

    if NSApp.alertWindow == nil {
      close()
    }
  }

  override func keyDown(with event: NSEvent) {
    guard event.keyCode != escapeKeyCode else {
      close()
      return
    }

    super.keyDown(with: event)
  }

  override func close() {
    super.close()
    isPresented = false
    onClose()
  }

  override var canBecomeKey: Bool {
    return true
  }
}
