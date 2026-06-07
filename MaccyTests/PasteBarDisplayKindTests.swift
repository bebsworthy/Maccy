import AppKit
import XCTest
@testable import Maccy

@MainActor
class PasteBarDisplayKindTests: XCTestCase {
  func testClassifiesPlainText() {
    XCTAssertEqual(PasteBarDisplayKind.classify(historyItem("hello")), .plainText)
  }

  func testClassifiesRichText() {
    let rtf = NSAttributedString(string: "hello").rtf(
      from: NSRange(location: 0, length: 5),
      documentAttributes: [:]
    )

    XCTAssertEqual(PasteBarDisplayKind.classify(historyItem(rtf, .rtf)), .richText)
  }

  func testClassifiesHTML() {
    XCTAssertEqual(
      PasteBarDisplayKind.classify(historyItem("<p>hello</p>".data(using: .utf8), .html)),
      .html
    )
  }

  func testClassifiesImageData() {
    let image = NSImage(named: "NSBluetoothTemplate")!
    XCTAssertEqual(PasteBarDisplayKind.classify(historyItem(image.tiffRepresentation, .tiff)), .image)
  }

  func testClassifiesColorText() {
    XCTAssertEqual(PasteBarDisplayKind.classify(historyItem("#ff7979")), .color)
  }

  func testClassifiesLinkText() {
    XCTAssertEqual(PasteBarDisplayKind.classify(historyItem("https://pasteapp.io/help/paste-on-mac")), .link)
  }

  func testClassifiesEmailAddress() {
    XCTAssertEqual(PasteBarDisplayKind.classify(historyItem("hello@example.com")), .emailAddress)
  }

  func testClassifiesPhoneNumber() {
    XCTAssertEqual(PasteBarDisplayKind.classify(historyItem("+1 (415) 555-1212")), .phoneNumber)
  }

  func testClassifiesTableText() {
    XCTAssertEqual(PasteBarDisplayKind.classify(historyItem("Name,Role\nAda,Engineer")), .table)
  }

  func testClassifiesCodeLikeText() {
    XCTAssertEqual(PasteBarDisplayKind.classify(historyItem("func paste() {\n  return true\n}")), .code)
  }

  func testClassifiesEmojiText() {
    XCTAssertEqual(PasteBarDisplayKind.classify(historyItem("😀 🚀")), .emoji)
  }

  func testClassifiesFileURL() {
    XCTAssertEqual(PasteBarDisplayKind.classify(historyItem(URL(fileURLWithPath: "/tmp/readme.txt"))), .file)
  }

  func testClassifiesFolderURL() {
    XCTAssertEqual(
      PasteBarDisplayKind.classify(historyItem(URL(fileURLWithPath: "/tmp/folder", isDirectory: true))),
      .folder
    )
  }

  func testClassifiesPDFFileURL() {
    XCTAssertEqual(PasteBarDisplayKind.classify(historyItem(URL(fileURLWithPath: "/tmp/guide.pdf"))), .pdf)
  }

  func testClassifiesArchiveFileURL() {
    XCTAssertEqual(PasteBarDisplayKind.classify(historyItem(URL(fileURLWithPath: "/tmp/archive.zip"))), .archive)
  }

  func testClassifiesImageFileURL() {
    XCTAssertEqual(PasteBarDisplayKind.classify(historyItem(URL(fileURLWithPath: "/tmp/photo.png"))), .imageFile)
  }

  func testClassifiesSourceCodeFileURL() {
    XCTAssertEqual(PasteBarDisplayKind.classify(historyItem(URL(fileURLWithPath: "/tmp/App.swift"))), .code)
  }

  func testClassifiesMultipleFileURLs() {
    XCTAssertEqual(
      PasteBarDisplayKind.classify(historyItem([
        URL(fileURLWithPath: "/tmp/one.txt"),
        URL(fileURLWithPath: "/tmp/two.txt")
      ])),
      .multipleFiles
    )
  }

  func testClassifiesUnknownFallback() {
    let item = HistoryItem(contents: [
      HistoryItemContent(type: "com.example.custom", value: Data("custom".utf8))
    ])

    XCTAssertEqual(PasteBarDisplayKind.classify(item), .unknown)
  }

  private func historyItem(_ value: String) -> HistoryItem {
    let item = HistoryItem(contents: [
      HistoryItemContent(type: NSPasteboard.PasteboardType.string.rawValue, value: value.data(using: .utf8))
    ])
    item.title = item.generateTitle()
    return item
  }

  private func historyItem(_ data: Data?, _ type: NSPasteboard.PasteboardType) -> HistoryItem {
    let item = HistoryItem(contents: [
      HistoryItemContent(type: type.rawValue, value: data)
    ])
    item.title = item.generateTitle()
    return item
  }

  private func historyItem(_ url: URL) -> HistoryItem {
    return historyItem([url])
  }

  private func historyItem(_ urls: [URL]) -> HistoryItem {
    let item = HistoryItem(contents: [
      HistoryItemContent(
        type: NSPasteboard.PasteboardType.string.rawValue,
        value: urls.map(\.lastPathComponent).joined(separator: "\n").data(using: .utf8)
      )
    ] + urls.map {
      HistoryItemContent(type: NSPasteboard.PasteboardType.fileURL.rawValue, value: $0.dataRepresentation)
    })
    item.title = item.generateTitle()
    return item
  }
}
