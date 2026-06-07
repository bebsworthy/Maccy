enum PasteBarFilter: Hashable, Identifiable {
  case all
  case pinned
  case unpinned
  case sourceApp(String)
  case displayKind(PasteBarDisplayKind)

  var id: String {
    switch self {
    case .all:
      return "all"
    case .pinned:
      return "pinned"
    case .unpinned:
      return "unpinned"
    case .sourceApp(let app):
      return "sourceApp:\(app)"
    case .displayKind(let kind):
      return "displayKind:\(kind.rawValue)"
    }
  }

  var label: String {
    switch self {
    case .all:
      return "All"
    case .pinned:
      return "Pinned"
    case .unpinned:
      return "Unpinned"
    case .sourceApp(let app):
      return app
    case .displayKind(let kind):
      return kind.label
    }
  }

  func includes(_ adapter: PasteBarHistoryItemAdapter) -> Bool {
    switch self {
    case .all:
      return true
    case .pinned:
      return adapter.isPinned
    case .unpinned:
      return !adapter.isPinned
    case .sourceApp(let app):
      return adapter.sourceAppName == app
    case .displayKind(let kind):
      return adapter.displayKind == kind
    }
  }
}
