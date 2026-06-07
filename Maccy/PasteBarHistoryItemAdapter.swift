import AppKit

struct PasteBarHistoryItemAdapter: Identifiable, Equatable, Search.SearchableText {
  let decorator: HistoryItemDecorator

  var id: UUID { decorator.id }
  var item: HistoryItem { decorator.item }
  var summary: String { decorator.title }
  var copiedAt: Date { item.lastCopiedAt }
  var firstCopiedAt: Date { item.firstCopiedAt }
  var numberOfCopies: Int { item.numberOfCopies }
  var isPinned: Bool { decorator.isPinned }
  var sourceAppName: String? { decorator.application }
  var sourceAppImage: ApplicationImage { decorator.applicationImage }
  var displayKind: PasteBarDisplayKind { PasteBarDisplayKind.classify(item) }
  var text: String? { item.text }
  var previewText: String { decorator.text }
  var fileURLs: [URL] { item.fileURLs }
  var image: NSImage? { item.image }
  var rtf: NSAttributedString? { item.rtf }
  var html: NSAttributedString? { item.html }

  var searchableText: String {
    var parts = [summary, displayKind.label]

    if let sourceAppName {
      parts.append(sourceAppName)
    }

    parts.append(contentsOf: fileURLs.flatMap { url in
      [
        url.lastPathComponent,
        url.deletingLastPathComponent().path,
        url.pathExtension
      ]
    })

    if displayKind == .link, let text {
      parts.append(text)
      if let url = URL(string: text), let host = url.host {
        parts.append(host)
      }
    }

    return parts
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .joined(separator: "\n")
  }

  static func == (lhs: Self, rhs: Self) -> Bool {
    return lhs.id == rhs.id
  }
}
