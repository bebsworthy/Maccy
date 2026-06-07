struct PasteBarSelection: Equatable {
  var selectedItemId: PasteBarHistoryItemAdapter.ID?
  var previewedItemId: PasteBarHistoryItemAdapter.ID?

  mutating func selectFirst(from items: [PasteBarHistoryItemAdapter]) {
    selectedItemId = items.first?.id
  }
}
