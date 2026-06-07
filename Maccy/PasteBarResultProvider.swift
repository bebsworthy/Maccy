import Foundation

@MainActor
struct PasteBarHistorySnapshot {
  private(set) var adapters: [PasteBarHistoryItemAdapter] = []

  var items: [HistoryItemDecorator] {
    adapters.map(\.decorator)
  }

  mutating func refresh(from items: [HistoryItemDecorator]) {
    adapters = items
      .map(PasteBarHistoryItemAdapter.init(decorator:))
      .sorted { $0.copiedAt > $1.copiedAt }
  }

  mutating func refresh(from history: History) {
    refresh(from: history.all)
  }
}

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
    return results(
      from: decorators.map(PasteBarHistoryItemAdapter.init(decorator:)),
      query: query,
      filter: filter
    )
  }

  func results(
    from adapters: [PasteBarHistoryItemAdapter],
    query: String,
    filter: PasteBarFilter = .all
  ) -> [PasteBarHistoryItemAdapter] {
    let filteredAdapters = adapters
      .filter(filter.includes)
      .sorted { $0.copiedAt > $1.copiedAt }

    guard !query.isEmpty else {
      return filteredAdapters
    }

    return search.search(string: query, within: filteredAdapters)
      .map(\.object)
      .sorted { $0.copiedAt > $1.copiedAt }
  }

  func filters() -> [PasteBarFilter] {
    return filters(from: history.all)
  }

  func filters(from decorators: [HistoryItemDecorator]) -> [PasteBarFilter] {
    return filters(from: decorators.map(PasteBarHistoryItemAdapter.init(decorator:)))
  }

  func filters(from adapters: [PasteBarHistoryItemAdapter]) -> [PasteBarFilter] {
    let sourceAppFilters = Set(adapters.compactMap(\.sourceAppName))
      .sorted()
      .map(PasteBarFilter.sourceApp)
    let displayKindFilters = Set(adapters.map(\.displayKind))
      .sorted { $0.label < $1.label }
      .map(PasteBarFilter.displayKind)

    return [.all, .pinned, .unpinned] + sourceAppFilters + displayKindFilters
  }

  func counts(from adapters: [PasteBarHistoryItemAdapter]) -> [PasteBarFilter: Int] {
    let filters = filters(from: adapters)
    return Dictionary(uniqueKeysWithValues: filters.map { filter in
      (filter, adapters.filter(filter.includes).count)
    })
  }
}

struct PasteBarRelativeTimeFormatter {
  var now: () -> Date = Date.init

  func string(for date: Date) -> String {
    let elapsedSeconds = max(0, Int(now().timeIntervalSince(date)))

    if elapsedSeconds < 5 {
      return "now"
    }

    if elapsedSeconds < 60 {
      return "<1 min"
    }

    let elapsedMinutes = elapsedSeconds / 60
    if elapsedMinutes < 60 {
      return "\(elapsedMinutes) min"
    }

    let elapsedHours = elapsedMinutes / 60
    if elapsedHours < 24 {
      return "\(elapsedHours) hr"
    }

    return "\(elapsedHours / 24) d"
  }
}
