import Foundation

@MainActor
struct PasteBarResultProvider {
  var history: History
  var search: Search

  init(history: History = .shared, search: Search = Search()) {
    self.history = history
    self.search = search
  }

  func results(query: String, filter: PasteBarFilter = .all) -> [PasteBarHistoryItemAdapter] {
    return results(from: history.all, query: query, filter: filter)
  }

  func results(
    from decorators: [HistoryItemDecorator],
    query: String,
    filter: PasteBarFilter = .all
  ) -> [PasteBarHistoryItemAdapter] {
    let adapters = decorators
      .map(PasteBarHistoryItemAdapter.init)
      .filter(filter.includes)
      .sorted { $0.copiedAt > $1.copiedAt }

    guard !query.isEmpty else {
      return adapters
    }

    return search.search(string: query, within: adapters)
      .map(\.object)
      .sorted { $0.copiedAt > $1.copiedAt }
  }

  func filters() -> [PasteBarFilter] {
    return filters(from: history.all)
  }

  func filters(from decorators: [HistoryItemDecorator]) -> [PasteBarFilter] {
    let adapters = decorators.map(PasteBarHistoryItemAdapter.init)
    let sourceAppFilters = Set(adapters.compactMap(\.sourceAppName))
      .sorted()
      .map(PasteBarFilter.sourceApp)
    let displayKindFilters = Set(adapters.map(\.displayKind))
      .sorted { $0.label < $1.label }
      .map(PasteBarFilter.displayKind)

    return [.all, .pinned, .unpinned] + sourceAppFilters + displayKindFilters
  }
}
