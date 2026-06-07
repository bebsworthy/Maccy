import AppKit
import Defaults
import XCTest
@testable import Maccy

@MainActor
class PasteBarResultProviderTests: XCTestCase {
  private let savedSearchMode = Defaults[.searchMode]

  override func tearDown() {
    Defaults[.searchMode] = savedSearchMode
    super.tearDown()
  }

  func testResultsSortByLastCopiedAtDescending() {
    let older = decorator("older", lastCopiedAt: -20)
    let newer = decorator("newer", lastCopiedAt: -10)
    let newest = decorator("newest", lastCopiedAt: -1)

    let results = PasteBarResultProvider().results(from: [newer, older, newest], query: "")

    XCTAssertEqual(results.map(\.summary), ["newest", "newer", "older"])
  }

  func testSearchResultsPreserveLastCopiedAtDescendingInFuzzyMode() {
    Defaults[.searchMode] = .fuzzy
    let olderBetterMatch = decorator("abc", lastCopiedAt: -20)
    let newerWeakerMatch = decorator("axxxbxxc", lastCopiedAt: -1)

    let results = PasteBarResultProvider().results(
      from: [olderBetterMatch, newerWeakerMatch],
      query: "abc"
    )

    XCTAssertEqual(results.map(\.summary), ["axxxbxxc", "abc"])
  }

  func testSearchUsesComputedProviderText() {
    Defaults[.searchMode] = .exact
    let link = decorator("Example", text: "https://docs.example.com/paste-bar")
    let file = decorator(URL(fileURLWithPath: "/tmp/Maccy/backup.zip"))
    let app = decorator("From iCloud", universalClipboard: true)
    let provider = PasteBarResultProvider()

    XCTAssertEqual(provider.results(from: [link, file, app], query: "docs.example.com").map(\.summary), ["Example"])
    XCTAssertEqual(provider.results(from: [link, file, app], query: "Archive").map(\.displayKind), [.archive])
    XCTAssertEqual(provider.results(from: [link, file, app], query: "iCloud").map(\.summary), ["From iCloud"])
    XCTAssertEqual(provider.results(from: [link, file, app], query: "backup.zip").map(\.displayKind), [.archive])
  }

  func testFiltersIncludeAllPinnedUnpinnedSourceAppsAndDisplayKinds() {
    let pinned = decorator("Pinned")
    pinned.item.pin = "b"
    let unpinned = decorator("Unpinned", universalClipboard: true)
    let file = decorator(URL(fileURLWithPath: "/tmp/archive.zip"))

    let filters = PasteBarResultProvider().filters(from: [pinned, unpinned, file])

    XCTAssertTrue(filters.contains(.all))
    XCTAssertTrue(filters.contains(.pinned))
    XCTAssertTrue(filters.contains(.unpinned))
    XCTAssertTrue(filters.contains(.sourceApp("iCloud")))
    XCTAssertTrue(filters.contains(.displayKind(.plainText)))
    XCTAssertTrue(filters.contains(.displayKind(.archive)))
  }

  func testActiveFiltersApplyBeforeSearch() {
    Defaults[.searchMode] = .exact
    let pinned = decorator("shared title")
    pinned.item.pin = "b"
    let unpinned = decorator("shared title")

    let results = PasteBarResultProvider().results(
      from: [pinned, unpinned],
      query: "shared",
      filter: .unpinned
    )

    XCTAssertEqual(results.count, 1)
    XCTAssertFalse(results[0].isPinned)
  }

  private func decorator(
    _ title: String,
    text: String? = nil,
    lastCopiedAt: TimeInterval = 0,
    universalClipboard: Bool = false
  ) -> HistoryItemDecorator {
    var contents = [
      HistoryItemContent(type: NSPasteboard.PasteboardType.string.rawValue, value: (text ?? title).data(using: .utf8))
    ]
    if universalClipboard {
      contents.append(HistoryItemContent(type: NSPasteboard.PasteboardType.universalClipboard.rawValue, value: Data()))
    }

    let item = HistoryItem(contents: contents)
    item.title = title
    item.lastCopiedAt = Date(timeIntervalSinceNow: lastCopiedAt)

    return HistoryItemDecorator(item)
  }

  private func decorator(_ url: URL) -> HistoryItemDecorator {
    let item = HistoryItem(contents: [
      HistoryItemContent(type: NSPasteboard.PasteboardType.fileURL.rawValue, value: url.dataRepresentation),
      HistoryItemContent(type: NSPasteboard.PasteboardType.string.rawValue, value: url.lastPathComponent.data(using: .utf8))
    ])
    item.title = item.generateTitle()

    return HistoryItemDecorator(item)
  }
}
