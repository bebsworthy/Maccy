struct PasteBarContextMenuActionAvailability: Equatable {
  var canCopy = true
  var canPaste = true
  var canPasteWithoutFormatting = true
  var canPreview = true
  var canDelete = true
  var canTogglePin = true

  static func availability(for adapter: PasteBarHistoryItemAdapter) -> Self {
    return Self()
  }
}
