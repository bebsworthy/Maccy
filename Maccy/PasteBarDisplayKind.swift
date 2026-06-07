import AppKit
import UniformTypeIdentifiers

enum PasteBarDisplayKind: String, CaseIterable, Identifiable {
  case multipleFiles
  case folder
  case pdf
  case archive
  case imageFile
  case file
  case image
  case color
  case link
  case emailAddress
  case phoneNumber
  case table
  case html
  case code
  case richText
  case emoji
  case plainText
  case unknown

  var id: Self { self }

  var label: String {
    switch self {
    case .multipleFiles:
      return "Multiple Files"
    case .folder:
      return "Folder"
    case .pdf:
      return "PDF"
    case .archive:
      return "Archive"
    case .imageFile:
      return "Image File"
    case .file:
      return "File"
    case .image:
      return "Image"
    case .color:
      return "Color"
    case .link:
      return "Link"
    case .emailAddress:
      return "Email Address"
    case .phoneNumber:
      return "Phone Number"
    case .table:
      return "Table"
    case .html:
      return "HTML"
    case .code:
      return "Code"
    case .richText:
      return "Rich Text"
    case .emoji:
      return "Emoji"
    case .plainText:
      return "Plain Text"
    case .unknown:
      return "Unknown"
    }
  }

  static func classify(_ item: HistoryItem) -> Self {
    if let fileKind = classifyFiles(item.fileURLs) {
      return fileKind
    }

    if item.containsPasteboardType(.tiff, .png, .jpeg, .heic) {
      return .image
    }

    if let text = item.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
      if text.isPasteBarColorLiteral {
        return .color
      }

      if text.isPasteBarLink {
        return .link
      }

      if text.isPasteBarEmailAddress {
        return .emailAddress
      }

      if text.isPasteBarPhoneNumber {
        return .phoneNumber
      }

      if text.isPasteBarTable {
        return .table
      }

      if text.isPasteBarCodeLike {
        return .code
      }

      if text.isPasteBarEmoji {
        return .emoji
      }
    }

    if item.containsPasteboardType(.html), item.htmlSource?.isPasteBarTable == true {
      return .table
    }

    if item.containsPasteboardType(.html), item.htmlSource?.isPasteBarCodeLike == true {
      return .code
    }

    if item.containsPasteboardType(.html) {
      return .html
    }

    if item.containsPasteboardType(.rtf) {
      return .richText
    }

    if item.containsPasteboardType(.string) {
      return .plainText
    }

    return .unknown
  }

  private static func classifyFiles(_ urls: [URL]) -> Self? {
    guard let firstURL = urls.first else {
      return nil
    }

    if urls.count > 1 {
      return .multipleFiles
    }

    if urls.contains(where: \.hasDirectoryPath) {
      return .folder
    }

    let extensions = urls.map { $0.pathExtension.lowercased() }
    if extensions.allSatisfy({ $0 == "pdf" }) {
      return .pdf
    }

    if extensions.allSatisfy(Self.isArchiveExtension) {
      return .archive
    }

    if urls.allSatisfy(Self.isImageFile) {
      return .imageFile
    }

    if urls.allSatisfy(Self.isSourceCodeFile) {
      return .code
    }

    if firstURL.isFileURL {
      return .file
    }

    return nil
  }

  private static func isArchiveExtension(_ pathExtension: String) -> Bool {
    return [
      "7z", "bz2", "dmg", "gz", "pkg", "rar", "tar", "tgz", "xip", "xz", "zip"
    ].contains(pathExtension)
  }

  private static func isImageFile(_ url: URL) -> Bool {
    guard let type = UTType(filenameExtension: url.pathExtension) else {
      return false
    }

    return type.conforms(to: .image)
  }

  private static func isSourceCodeFile(_ url: URL) -> Bool {
    return [
      "c", "cc", "cpp", "css", "go", "h", "hpp", "html", "java", "js", "json",
      "kt", "m", "mm", "php", "py", "rb", "rs", "sh", "swift", "ts", "tsx",
      "xml", "yaml", "yml"
    ].contains(url.pathExtension.lowercased())
  }
}

private extension HistoryItem {
  func containsPasteboardType(_ types: NSPasteboard.PasteboardType...) -> Bool {
    let rawTypes = Set(types.map(\.rawValue))
    return contents.contains { rawTypes.contains($0.type) }
  }

  var htmlSource: String? {
    guard let htmlData else {
      return nil
    }

    return String(data: htmlData, encoding: .utf8)
  }
}

private extension String {
  var isPasteBarColorLiteral: Bool {
    let pattern = #"^#?(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$"#
    return range(of: pattern, options: .regularExpression) != nil
  }

  var isPasteBarLink: Bool {
    guard let url = URL(string: self), let scheme = url.scheme?.lowercased() else {
      return false
    }

    return ["http", "https", "mailto"].contains(scheme)
  }

  var isPasteBarEmailAddress: Bool {
    let pattern = #"^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$"#
    return range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
  }

  var isPasteBarPhoneNumber: Bool {
    let pattern = #"^\+?[0-9][0-9\s().-]{5,}[0-9]$"#
    let digitCount = filter(\.isNumber).count
    return digitCount >= 7 &&
      digitCount <= 15 &&
      range(of: pattern, options: .regularExpression) != nil
  }

  var isPasteBarTable: Bool {
    if range(of: #"<table[\s>]"#, options: [.regularExpression, .caseInsensitive]) != nil {
      return true
    }

    let rows = split(whereSeparator: \.isNewline)
      .map(String.init)
      .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    guard rows.count > 1 else {
      return false
    }

    return [",", "\t"].contains { delimiter in
      let columnCounts = rows.map { $0.components(separatedBy: delimiter).count }
      return columnCounts.allSatisfy { $0 > 1 } && Set(columnCounts).count == 1
    }
  }

  var isPasteBarCodeLike: Bool {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return false
    }

    if trimmed.hasPrefix("```") {
      return true
    }

    let codePatterns = [
      #"(?m)^\s*(import|class|struct|enum|func|let|var|const|function)\b"#,
      #"[{};]"#,
      #"(?m)^\s{2,}\S+"#
    ]

    return codePatterns.filter { pattern in
      trimmed.range(of: pattern, options: .regularExpression) != nil
    }.count >= 2
  }

  var isPasteBarEmoji: Bool {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return false
    }
    guard trimmed.rangeOfCharacter(from: .letters.union(.decimalDigits)) == nil else {
      return false
    }

    let meaningfulScalars = trimmed.unicodeScalars.filter { scalar in
      scalar.value != 0x200D &&
        scalar.value != 0xFE0F &&
        !CharacterSet.whitespacesAndNewlines.contains(scalar)
    }

    return !meaningfulScalars.isEmpty &&
      meaningfulScalars.allSatisfy { $0.properties.isEmoji || $0.properties.isEmojiPresentation }
  }
}
