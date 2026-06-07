import AppKit
import Defaults
import Fuse

class Search {
  protocol SearchableText {
    var searchableText: String { get }
  }

  enum Mode: String, CaseIterable, Identifiable, CustomStringConvertible, Defaults.Serializable {
    case exact
    case fuzzy
    case regexp
    case mixed

    var id: Self { self }

    var description: String {
      switch self {
      case .exact:
        return NSLocalizedString("Exact", tableName: "GeneralSettings", comment: "")
      case .fuzzy:
        return NSLocalizedString("Fuzzy", tableName: "GeneralSettings", comment: "")
      case .regexp:
        return NSLocalizedString("Regex", tableName: "GeneralSettings", comment: "")
      case .mixed:
        return NSLocalizedString("Mixed", tableName: "GeneralSettings", comment: "")
      }
    }
  }

  struct Result<Object: SearchableText & Equatable>: Equatable {
    var score: Double?
    var object: Object
    var ranges: [Range<String.Index>] = []
  }

  typealias Searchable = HistoryItemDecorator
  typealias SearchResult = Result<HistoryItemDecorator>

  private let fuse = Fuse(threshold: 0.7) // threshold found by trial-and-error
  private let fuzzySearchLimit = 5_000

  func search<Object: SearchableText & Equatable>(string: String, within: [Object]) -> [Result<Object>] {
    guard !string.isEmpty else {
      return within.map { Result(object: $0) }
    }

    switch Defaults[.searchMode] {
    case .mixed:
      return mixedSearch(string: string, within: within)
    case .regexp:
      return simpleSearch(string: string, within: within, options: .regularExpression)
    case .fuzzy:
      return fuzzySearch(string: string, within: within)
    default:
      return simpleSearch(string: string, within: within, options: .caseInsensitive)
    }
  }

  private func fuzzySearch<Object: SearchableText & Equatable>(
    string: String,
    within: [Object]
  ) -> [Result<Object>] {
    let pattern = fuse.createPattern(from: string)
    let searchResults: [Result<Object>] = within.compactMap { item in
      fuzzySearch(for: pattern, in: item.searchableText, of: item)
    }
    let sortedResults = searchResults.sorted(by: { ($0.score ?? 0) < ($1.score ?? 0) })
    return sortedResults
  }

  private func fuzzySearch<Object: SearchableText & Equatable>(
    for pattern: Fuse.Pattern?,
    in searchString: String,
    of item: Object
  ) -> Result<Object>? {
    var searchString = searchString
    if searchString.count > fuzzySearchLimit {
      // shortcut to avoid slow search
      let stopIndex = searchString.index(searchString.startIndex, offsetBy: fuzzySearchLimit)
      searchString = "\(searchString[...stopIndex])"
    }

    if let fuzzyResult = fuse.search(pattern, in: searchString) {
      return Result(
        score: fuzzyResult.score,
        object: item,
        ranges: fuzzyResult.ranges.map {
          let startIndex = searchString.startIndex
          let lowerBound = searchString.index(startIndex, offsetBy: $0.lowerBound)
          let upperBound = searchString.index(startIndex, offsetBy: $0.upperBound + 1)

          return lowerBound..<upperBound
        }
      )
    } else {
      return nil
    }
  }

  private func simpleSearch<Object: SearchableText & Equatable>(
    string: String,
    within: [Object],
    options: NSString.CompareOptions
  ) -> [Result<Object>] {
    return within.compactMap { simpleSearch(for: string, in: $0.searchableText, of: $0, options: options) }
  }

  private func simpleSearch<Object: SearchableText & Equatable>(
    for string: String,
    in searchString: String,
    of item: Object,
    options: NSString.CompareOptions
  ) -> Result<Object>? {
    if let range = searchString.range(of: string, options: options, range: nil, locale: nil) {
      return Result(object: item, ranges: [range])
    } else {
      return nil
    }
  }

  private func mixedSearch<Object: SearchableText & Equatable>(
    string: String,
    within: [Object]
  ) -> [Result<Object>] {
    var results = simpleSearch(string: string, within: within, options: .caseInsensitive)
    guard results.isEmpty else {
      return results
    }

    results = simpleSearch(string: string, within: within, options: .regularExpression)
    guard results.isEmpty else {
      return results
    }

    results = fuzzySearch(string: string, within: within)
    guard results.isEmpty else {
      return results
    }

    return []
  }
}

extension HistoryItemDecorator: Search.SearchableText {
  var searchableText: String { title }
}
