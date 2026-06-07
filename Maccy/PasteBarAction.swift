import Foundation

enum PasteBarAction {
  case copy
  case paste
  case pasteWithoutFormatting
  case delete
  case togglePin
  case preview
}

enum PasteBarActionResult: Equatable {
  case copied
  case pasted
  case copiedFallback(String)
  case deleted
  case pinned
  case unpinned
  case preview(PasteBarHistoryItemAdapter.ID)
  case failed(String)
}
