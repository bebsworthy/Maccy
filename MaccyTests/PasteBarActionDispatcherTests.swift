import AppKit
import XCTest
@testable import Maccy

@MainActor
class PasteBarActionDispatcherTests: XCTestCase {
  func testTrustedPasteCopiesRestoresTargetClosesAndPastes() {
    let writer = FakeClipboardWriter()
    let restorer = FakePasteTargetRestorer()
    let paster = FakeDirectPaster()
    var closeCount = 0
    let dispatcher = PasteBarActionDispatcher(
      accessibility: FakeAccessibility(isTrusted: true),
      clipboardWriter: writer,
      directPaster: paster,
      pasteTargetRestorer: restorer,
      closePasteBar: { closeCount += 1 }
    )

    let result = dispatcher.perform(.paste, on: adapter("hello"), pasteTarget: PasteBarPasteTarget(application: nil))

    XCTAssertEqual(result, .pasted)
    XCTAssertEqual(writer.copies.map(\.removeFormatting), [false])
    XCTAssertEqual(restorer.restoreCount, 1)
    XCTAssertEqual(paster.pasteCount, 1)
    XCTAssertEqual(closeCount, 1)
  }

  func testUntrustedPasteCopiesFallbackWithoutDirectPaste() {
    let writer = FakeClipboardWriter()
    let restorer = FakePasteTargetRestorer()
    let paster = FakeDirectPaster()
    var closeCount = 0
    let dispatcher = PasteBarActionDispatcher(
      accessibility: FakeAccessibility(isTrusted: false),
      clipboardWriter: writer,
      directPaster: paster,
      pasteTargetRestorer: restorer,
      closePasteBar: { closeCount += 1 }
    )

    let result = dispatcher.perform(.paste, on: adapter("hello"), pasteTarget: PasteBarPasteTarget(application: nil))

    if case .copiedFallback = result {
      // Expected.
    } else {
      XCTFail("Expected copied fallback, got \(result)")
    }
    XCTAssertEqual(writer.copies.map(\.removeFormatting), [false])
    XCTAssertEqual(restorer.restoreCount, 0)
    XCTAssertEqual(paster.pasteCount, 0)
    XCTAssertEqual(closeCount, 0)
  }

  func testRestoreFailureCopiesFallbackWithoutClosingOrPasting() {
    let writer = FakeClipboardWriter()
    let restorer = FakePasteTargetRestorer()
    restorer.restoreResult = false
    let paster = FakeDirectPaster()
    var closeCount = 0
    let dispatcher = PasteBarActionDispatcher(
      accessibility: FakeAccessibility(isTrusted: true),
      clipboardWriter: writer,
      directPaster: paster,
      pasteTargetRestorer: restorer,
      closePasteBar: { closeCount += 1 }
    )

    let result = dispatcher.perform(.paste, on: adapter("hello"), pasteTarget: PasteBarPasteTarget(application: nil))

    if case .copiedFallback = result {
      // Expected.
    } else {
      XCTFail("Expected copied fallback, got \(result)")
    }
    XCTAssertEqual(writer.copies.map(\.removeFormatting), [false])
    XCTAssertEqual(restorer.restoreCount, 1)
    XCTAssertEqual(paster.pasteCount, 0)
    XCTAssertEqual(closeCount, 0)
  }

  func testPasteWithoutFormattingUsesRemoveFormattingCopy() {
    let writer = FakeClipboardWriter()
    let dispatcher = PasteBarActionDispatcher(
      accessibility: FakeAccessibility(isTrusted: true),
      clipboardWriter: writer,
      directPaster: FakeDirectPaster(),
      pasteTargetRestorer: FakePasteTargetRestorer()
    )

    let result = dispatcher.perform(
      .pasteWithoutFormatting,
      on: adapter("hello"),
      pasteTarget: PasteBarPasteTarget(application: nil)
    )

    XCTAssertEqual(result, .pasted)
    XCTAssertEqual(writer.copies.map(\.removeFormatting), [true])
  }

  func testCopyFailureDoesNotCloseOrPaste() {
    let writer = FakeClipboardWriter(result: .failure(FakeError.copyFailed))
    let paster = FakeDirectPaster()
    var closeCount = 0
    let dispatcher = PasteBarActionDispatcher(
      accessibility: FakeAccessibility(isTrusted: true),
      clipboardWriter: writer,
      directPaster: paster,
      pasteTargetRestorer: FakePasteTargetRestorer(),
      closePasteBar: { closeCount += 1 }
    )

    let result = dispatcher.perform(.paste, on: adapter("hello"), pasteTarget: PasteBarPasteTarget(application: nil))

    XCTAssertEqual(result, .failed("copy failed"))
    XCTAssertEqual(closeCount, 0)
    XCTAssertEqual(paster.pasteCount, 0)
  }

  func testDeleteUpdatesPasteBarHistoryWithoutSelectingItem() {
    let history = History()
    let decorator = adapter("delete me").decorator
    history.all = [decorator]
    history.items = [decorator]
    let dispatcher = PasteBarActionDispatcher(history: history)

    let result = dispatcher.perform(.delete, on: PasteBarHistoryItemAdapter(decorator: decorator))

    XCTAssertEqual(result, .deleted)
    XCTAssertTrue(history.all.isEmpty)
    XCTAssertTrue(history.items.isEmpty)
  }

  func testTogglePinUpdatesItemAndReturnsState() {
    let history = History()
    let decorator = adapter("pin me").decorator
    history.all = [decorator]
    history.items = [decorator]
    let dispatcher = PasteBarActionDispatcher(history: history)

    XCTAssertEqual(dispatcher.perform(.togglePin, on: PasteBarHistoryItemAdapter(decorator: decorator)), .pinned)
    XCTAssertNotNil(decorator.item.pin)
    XCTAssertEqual(dispatcher.perform(.togglePin, on: PasteBarHistoryItemAdapter(decorator: decorator)), .unpinned)
    XCTAssertNil(decorator.item.pin)
  }

  private func adapter(_ title: String) -> PasteBarHistoryItemAdapter {
    let item = HistoryItem(contents: [
      HistoryItemContent(type: NSPasteboard.PasteboardType.string.rawValue, value: title.data(using: .utf8))
    ])
    item.title = item.generateTitle()
    return PasteBarHistoryItemAdapter(decorator: HistoryItemDecorator(item))
  }
}

private struct FakeAccessibility: AccessibilityTrustChecking {
  let isTrusted: Bool
}

@MainActor
private final class FakeClipboardWriter: PasteBarClipboardWriting {
  struct Copy: Equatable {
    let item: HistoryItem
    let removeFormatting: Bool
  }

  var copies: [Copy] = []
  var result: Result<Void, Error>

  init(result: Result<Void, Error> = .success(())) {
    self.result = result
  }

  func copy(item: HistoryItem, removeFormatting: Bool) -> Result<Void, Error> {
    copies.append(Copy(item: item, removeFormatting: removeFormatting))
    return result
  }
}

private final class FakeDirectPaster: PasteBarDirectPasting {
  var pasteCount = 0

  func paste() {
    pasteCount += 1
  }
}

private final class FakePasteTargetRestorer: PasteBarPasteTargetRestoring {
  var restoreCount = 0
  var restoreResult = true

  func capture() -> PasteBarPasteTarget? {
    return PasteBarPasteTarget(application: nil)
  }

  func restore(_ target: PasteBarPasteTarget) -> Bool {
    restoreCount += 1
    return restoreResult
  }
}

private enum FakeError: LocalizedError {
  case copyFailed

  var errorDescription: String? {
    return "copy failed"
  }
}
