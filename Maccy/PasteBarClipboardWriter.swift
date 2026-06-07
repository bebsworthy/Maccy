import Foundation

protocol PasteBarClipboardWriting {
  @MainActor
  func copy(item: HistoryItem, removeFormatting: Bool) -> Result<Void, Error>
}

struct MaccyPasteBarClipboardWriter: PasteBarClipboardWriting {
  @MainActor
  func copy(item: HistoryItem, removeFormatting: Bool = false) -> Result<Void, Error> {
    Clipboard.shared.copy(item, removeFormatting: removeFormatting)
    return .success(())
  }
}
