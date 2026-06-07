import Foundation

@MainActor
final class PasteBarActionDispatcher {
  private let accessibility: AccessibilityTrustChecking
  private let clipboardWriter: PasteBarClipboardWriting
  private let directPaster: PasteBarDirectPasting
  private let history: History
  private let pasteTargetRestorer: PasteBarPasteTargetRestoring
  private let closePasteBar: () -> Void

  init(
    accessibility: AccessibilityTrustChecking = SystemAccessibilityTrustChecker(),
    clipboardWriter: PasteBarClipboardWriting = MaccyPasteBarClipboardWriter(),
    directPaster: PasteBarDirectPasting = MaccyPasteBarDirectPaster(),
    history: History = .shared,
    pasteTargetRestorer: PasteBarPasteTargetRestoring = SystemPasteBarPasteTargetRestorer(),
    closePasteBar: @escaping () -> Void = {}
  ) {
    self.accessibility = accessibility
    self.clipboardWriter = clipboardWriter
    self.directPaster = directPaster
    self.history = history
    self.pasteTargetRestorer = pasteTargetRestorer
    self.closePasteBar = closePasteBar
  }

  func perform(
    _ action: PasteBarAction,
    on adapter: PasteBarHistoryItemAdapter,
    pasteTarget: PasteBarPasteTarget? = nil
  ) -> PasteBarActionResult {
    switch action {
    case .copy:
      return copy(adapter: adapter, removeFormatting: false)
    case .paste:
      return paste(adapter: adapter, removeFormatting: false, pasteTarget: pasteTarget)
    case .pasteWithoutFormatting:
      return paste(adapter: adapter, removeFormatting: true, pasteTarget: pasteTarget)
    case .delete:
      history.deleteFromPasteBar(adapter.decorator)
      return .deleted
    case .togglePin:
      history.togglePinFromPasteBar(adapter.decorator)
      return adapter.isPinned ? .pinned : .unpinned
    case .preview:
      return .preview(adapter.id)
    }
  }

  private func copy(adapter: PasteBarHistoryItemAdapter, removeFormatting: Bool) -> PasteBarActionResult {
    switch clipboardWriter.copy(item: adapter.item, removeFormatting: removeFormatting) {
    case .success:
      closePasteBar()
      return .copied
    case .failure(let error):
      return .failed(error.localizedDescription)
    }
  }

  private func paste(
    adapter: PasteBarHistoryItemAdapter,
    removeFormatting: Bool,
    pasteTarget: PasteBarPasteTarget?
  ) -> PasteBarActionResult {
    switch clipboardWriter.copy(item: adapter.item, removeFormatting: removeFormatting) {
    case .success:
      break
    case .failure(let error):
      return .failed(error.localizedDescription)
    }

    guard accessibility.isTrusted else {
      return .copiedFallback("Direct paste requires Accessibility permission. The item was copied instead.")
    }

    guard let pasteTarget, pasteTargetRestorer.restore(pasteTarget) else {
      return .copiedFallback("Could not restore the previous app. The item was copied instead.")
    }

    closePasteBar()
    directPaster.paste()
    return .pasted
  }
}
