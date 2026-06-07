import AppKit
import Defaults
import XCTest
@testable import Maccy

@MainActor
class PasteBarResultProviderTests: XCTestCase {
  private let savedSearchMode = Defaults[.searchMode]
  private let savedSortBy = Defaults[.sortBy]

  override func tearDown() {
    Defaults[.searchMode] = savedSearchMode
    Defaults[.sortBy] = savedSortBy
    super.tearDown()
  }

  func testResultsSortByLastCopiedAtDescending() {
    Defaults[.sortBy] = .numberOfCopies
    let older = decorator("older", lastCopiedAt: -20)
    let newer = decorator("newer", lastCopiedAt: -10)
    let newest = decorator("newest", lastCopiedAt: -1)

    let results = PasteBarResultProvider().results(from: [newer, older, newest], query: "")

    XCTAssertEqual(results.map(\.summary), ["newest", "newer", "older"])
  }

  func testCountsUseCachedAdaptersForEachFilter() {
    let pinned = decorator("Pinned")
    pinned.item.pin = "b"
    let plain = decorator("Plain")
    let file = decorator(URL(fileURLWithPath: "/tmp/archive.zip"))
    var snapshot = PasteBarHistorySnapshot()
    snapshot.refresh(from: [pinned, plain, file])

    let counts = PasteBarResultProvider().counts(from: snapshot.adapters)

    XCTAssertEqual(counts[.all], 3)
    XCTAssertEqual(counts[.pinned], 1)
    XCTAssertEqual(counts[.unpinned], 2)
    XCTAssertEqual(counts[.displayKind(.plainText)], 2)
    XCTAssertEqual(counts[.displayKind(.archive)], 1)
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

  func testSnapshotRefreshReplacesVisibleHistorySource() {
    let older = decorator("older", lastCopiedAt: -20)
    let newer = decorator("newer", lastCopiedAt: -1)
    var snapshot = PasteBarHistorySnapshot()

    snapshot.refresh(from: [older])
    XCTAssertEqual(snapshot.items.map(\.title), ["older"])

    snapshot.refresh(from: [newer, older])
    let results = PasteBarResultProvider().results(from: snapshot.items, query: "")

    XCTAssertEqual(results.map(\.summary), ["newer", "older"])
  }

  func testRelativeTimeFormatterUsesMinuteGranularity() {
    let now = Date(timeIntervalSince1970: 1_000)
    let formatter = PasteBarRelativeTimeFormatter(now: { now })

    XCTAssertEqual(formatter.string(for: now), "now")
    XCTAssertEqual(formatter.string(for: now.addingTimeInterval(-20)), "<1 min")
    XCTAssertEqual(formatter.string(for: now.addingTimeInterval(-7 * 60 - 11)), "7 min")
    XCTAssertEqual(formatter.string(for: now.addingTimeInterval(-2 * 60 * 60 - 30)), "2 hr")
    XCTAssertEqual(formatter.string(for: now.addingTimeInterval(-3 * 24 * 60 * 60 - 30)), "3 d")
  }

  func testCardMetadataFormatterUsesCompactNonRedundantLabels() {
    let image = adapter(imageDecorator())
    let text = adapter(decorator("foo"))
    let file = adapter(decorator(URL(fileURLWithPath: "/tmp/Maccy/backup.zip")))
    let files = adapter(filesDecorator([
      URL(fileURLWithPath: "/tmp/Maccy/one.txt"),
      URL(fileURLWithPath: "/tmp/Maccy/two.txt")
    ]))
    let link = adapter(decorator("Example", text: "https://docs.example.com/paste-bar"))
    let unknown = adapter(unknownDecorator())

    XCTAssertEqual(PasteBarCardMetadataFormatter.string(for: image), "Image")
    XCTAssertEqual(PasteBarCardMetadataFormatter.string(for: text), "3 characters")
    XCTAssertEqual(PasteBarCardMetadataFormatter.string(for: file), "backup.zip")
    XCTAssertEqual(PasteBarCardMetadataFormatter.string(for: files), "2 files")
    XCTAssertEqual(PasteBarCardMetadataFormatter.string(for: link), "docs.example.com")
    XCTAssertEqual(PasteBarCardMetadataFormatter.string(for: unknown), "Unknown")
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
      HistoryItemContent(
        type: NSPasteboard.PasteboardType.string.rawValue,
        value: url.lastPathComponent.data(using: .utf8)
      )
    ])
    item.title = item.generateTitle()

    return HistoryItemDecorator(item)
  }

  private func filesDecorator(_ urls: [URL]) -> HistoryItemDecorator {
    let item = HistoryItem(contents: urls.map {
      HistoryItemContent(type: NSPasteboard.PasteboardType.fileURL.rawValue, value: $0.dataRepresentation)
    })
    item.title = item.generateTitle()

    return HistoryItemDecorator(item)
  }

  private func imageDecorator() -> HistoryItemDecorator {
    let image = NSImage(named: "NSInfo")!
    let item = HistoryItem(contents: [
      HistoryItemContent(type: NSPasteboard.PasteboardType.tiff.rawValue, value: image.tiffRepresentation)
    ])
    item.title = "Clipboard screenshot text"

    return HistoryItemDecorator(item)
  }

  private func unknownDecorator() -> HistoryItemDecorator {
    let item = HistoryItem(contents: [
      HistoryItemContent(type: "org.maccy.unknown-test-type", value: Data())
    ])
    item.title = "Unknown"

    return HistoryItemDecorator(item)
  }

  private func adapter(_ decorator: HistoryItemDecorator) -> PasteBarHistoryItemAdapter {
    PasteBarHistoryItemAdapter(decorator: decorator)
  }
}
