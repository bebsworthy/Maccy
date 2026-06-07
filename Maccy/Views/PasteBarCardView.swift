import AppKit
import Sauce
import SwiftHEXColors
import SwiftUI

private let pasteBarRelativeTimeFormatter = PasteBarRelativeTimeFormatter()

enum PasteBarCardMetrics {
  static let width: CGFloat = 214
  static let height: CGFloat = 170
  static let previewHeight: CGFloat = 104
  static let padding: CGFloat = 10
  static let cornerRadius: CGFloat = 10
}

struct PasteBarCardView: View {
  let item: PasteBarHistoryItemAdapter
  let index: Int
  let isSelected: Bool
  let isHovered: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      header
      preview
      metadataLine
    }
    .padding(PasteBarCardMetrics.padding)
    .frame(width: PasteBarCardMetrics.width, height: PasteBarCardMetrics.height, alignment: .topLeading)
    .background(
      backgroundStyle,
      in: RoundedRectangle(cornerRadius: PasteBarCardMetrics.cornerRadius, style: .continuous)
    )
    .clipShape(RoundedRectangle(cornerRadius: PasteBarCardMetrics.cornerRadius, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: PasteBarCardMetrics.cornerRadius, style: .continuous)
        .stroke(isSelected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: isSelected ? 2 : 1)
    }
    .shadow(color: Color.black.opacity(isSelected ? 0.12 : 0.06), radius: isSelected ? 6 : 3, y: 2)
    .contentShape(RoundedRectangle(cornerRadius: PasteBarCardMetrics.cornerRadius, style: .continuous))
    .clipped()
    .accessibilityElement(children: .combine)
    .accessibilityLabel(accessibilityLabel)
    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    .onAppear {
      item.decorator.ensureThumbnailImage()
    }
  }

  private var backgroundStyle: AnyShapeStyle {
    if isSelected {
      return AnyShapeStyle(.regularMaterial)
    }

    if isHovered {
      return AnyShapeStyle(.regularMaterial)
    }

    return AnyShapeStyle(.thinMaterial)
  }

  private var header: some View {
    HStack(spacing: 6) {
      Text(item.displayKind.cardLabel)
        .font(.subheadline)
        .fontWeight(.semibold)
        .lineLimit(1)
        .truncationMode(.tail)
        .fixedSize(horizontal: false, vertical: false)

      Text(pasteBarRelativeTimeFormatter.string(for: item.copiedAt))
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.85)
        .fixedSize(horizontal: false, vertical: false)

      Spacer(minLength: 0)

      sourceAppBadge

      if index < 9 {
        KeyboardShortcutView(shortcut: quickShortcut(for: index))
          .font(.caption)
          .foregroundStyle(.secondary)
          .frame(minWidth: 18, alignment: .trailing)
          .minimumScaleFactor(0.85)
          .fixedSize(horizontal: false, vertical: false)
          .accessibilityLabel("Command \(index + 1)")
      }
    }
    .frame(height: 20)
    .clipped()
  }

  @ViewBuilder
  private var preview: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(Color.secondary.opacity(0.08))

      switch item.displayKind {
      case .image, .imageFile:
        imagePreview
      case .file, .folder, .pdf, .archive, .multipleFiles:
        filePreview
      case .color:
        colorPreview
      case .html, .richText:
        richTextPreview
      case .emoji:
        emojiPreview
      case .code:
        codePreview
      case .table:
        textPreview(monospaced: true)
      case .link:
        linkPreview
      case .emailAddress, .phoneNumber, .plainText:
        textPreview(monospaced: false)
      case .unknown:
        unknownPreview
      }
    }
    .frame(maxWidth: .infinity)
    .frame(height: PasteBarCardMetrics.previewHeight)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    .clipped()
  }

  private var metadataLine: some View {
    Text(PasteBarCardMetadataFormatter.string(for: item))
      .font(.caption)
      .foregroundStyle(.secondary)
      .lineLimit(1)
      .truncationMode(.middle)
      .minimumScaleFactor(0.85)
      .fixedSize(horizontal: false, vertical: false)
      .frame(maxWidth: .infinity, minHeight: 14, maxHeight: 14, alignment: .leading)
    .clipped()
  }

  @ViewBuilder
  private var sourceAppBadge: some View {
    if item.isPinned {
      Image(systemName: "pin.fill")
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityLabel("Pinned")
    }

    AppImageView(appImage: item.sourceAppImage, size: CGSize(width: 16, height: 16))
      .accessibilityLabel(item.sourceAppName ?? "Unknown App")
  }

  @ViewBuilder
  private var imagePreview: some View {
    if let image = item.image ?? item.decorator.thumbnailImage {
      Image(nsImage: image)
        .resizable()
        .scaledToFill()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    } else if let url = item.fileURLs.first {
      fileIcon(url)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
      Image(systemName: "photo")
        .font(.title)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  private var filePreview: some View {
    VStack(spacing: 6) {
      if let firstURL = item.fileURLs.first {
        fileIcon(firstURL)
      } else {
        Image(systemName: "doc")
          .font(.largeTitle)
          .foregroundStyle(.secondary)
      }

      Text(filePreviewTitle)
        .font(.subheadline)
        .lineLimit(1)
        .truncationMode(.middle)
        .padding(.horizontal, 8)
        .fixedSize(horizontal: false, vertical: false)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .clipped()
  }

  @ViewBuilder
  private var colorPreview: some View {
    if let color = colorFromText {
      color
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .overlay {
          Text(item.text ?? item.summary)
            .font(.callout)
            .lineLimit(1)
            .truncationMode(.middle)
            .fixedSize(horizontal: false, vertical: false)
            .foregroundStyle(.primary)
            .padding(6)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    } else {
      textPreview(monospaced: false)
    }
  }

  @ViewBuilder
  private var richTextPreview: some View {
    if let attributed = attributedPreview {
      Text(attributed.string)
        .font(.callout)
        .lineLimit(5)
        .truncationMode(.tail)
        .fixedSize(horizontal: false, vertical: false)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(9)
        .clipped()
    } else {
      textPreview(monospaced: false)
    }
  }

  private var codePreview: some View {
    Text(item.previewText.isEmpty ? item.summary : item.previewText)
      .font(.system(.caption, design: .monospaced))
      .foregroundStyle(Color(nsColor: .textBackgroundColor))
      .lineLimit(6)
      .truncationMode(.tail)
      .fixedSize(horizontal: false, vertical: false)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .padding(10)
      .background(Color(nsColor: .textColor).opacity(0.88))
      .clipped()
  }

  private var linkPreview: some View {
    VStack(alignment: .leading, spacing: 7) {
      Image(systemName: "link.circle.fill")
        .font(.title2)
        .foregroundStyle(.secondary)

      Text(item.summary)
        .font(.callout)
        .fontWeight(.regular)
        .lineLimit(2)
        .truncationMode(.tail)
        .fixedSize(horizontal: false, vertical: false)

      Text(linkHost ?? item.text ?? "")
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .truncationMode(.middle)
        .fixedSize(horizontal: false, vertical: false)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    .padding(10)
    .clipped()
  }

  private var emojiPreview: some View {
    Text(item.text ?? item.summary)
      .font(.system(size: 44))
      .lineLimit(1)
      .minimumScaleFactor(0.5)
      .padding(8)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .clipped()
  }

  private func textPreview(monospaced: Bool) -> some View {
    Text(item.previewText.isEmpty ? item.summary : item.previewText)
      .font(monospaced ? .system(.caption, design: .monospaced) : .callout)
      .lineLimit(6)
      .truncationMode(.tail)
      .fixedSize(horizontal: false, vertical: false)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .padding(10)
      .clipped()
  }

  private var unknownPreview: some View {
    VStack(spacing: 6) {
      Image(systemName: "questionmark.square.dashed")
        .font(.title)
        .foregroundStyle(.secondary)
      Text("Unsupported Preview")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .clipped()
  }

  private func fileIcon(_ url: URL) -> some View {
    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
      .resizable()
      .scaledToFit()
      .frame(width: 42, height: 42)
      .clipped()
  }

  private var attributedPreview: NSAttributedString? {
    item.rtf ?? item.html
  }

  private var colorFromText: Color? {
    guard let text = item.text?.trimmingCharacters(in: .whitespacesAndNewlines),
          let nsColor = NSColor(hexString: text.hasPrefix("#") ? text : "#\(text)")
    else {
      return nil
    }

    return Color(nsColor: nsColor)
  }

  private var filePreviewTitle: String {
    item.fileURLs.count > 1 ? "\(item.fileURLs.count) items" : (item.fileURLs.first?.lastPathComponent ?? "File")
  }

  private var linkHost: String? {
    guard let text = item.text,
          let url = URL(string: text)
    else {
      return nil
    }

    return url.host
  }

  private var accessibilityLabel: String {
    var parts = [item.displayKind.label, item.summary]
    if let sourceAppName = item.sourceAppName {
      parts.append(sourceAppName)
    }
    parts.append(PasteBarCardMetadataFormatter.string(for: item))
    return parts.joined(separator: ", ")
  }

  private func quickShortcut(for index: Int) -> KeyShortcut? {
    let keys: [Key] = [.one, .two, .three, .four, .five, .six, .seven, .eight, .nine]
    guard keys.indices.contains(index) else {
      return nil
    }

    return KeyShortcut(key: keys[index], modifierFlags: [.command])
  }
}

enum PasteBarCardMetadataFormatter {
  static func string(for item: PasteBarHistoryItemAdapter) -> String {
    switch item.displayKind {
    case .image, .imageFile:
      return "Image"
    case .multipleFiles:
      return "\(item.fileURLs.count) files"
    case .file, .folder, .pdf, .archive:
      return item.fileURLs.first?.lastPathComponent ?? item.displayKind.label
    case .link:
      return linkHost(for: item) ?? "Link"
    case .emailAddress:
      return "Email"
    case .phoneNumber:
      return "Phone"
    case .color:
      return "Color"
    case .emoji:
      return "Emoji"
    case .html:
      return "HTML"
    case .richText:
      return "Rich Text"
    case .code:
      return "Code"
    case .table:
      return "Table"
    case .plainText:
      return characterCount(for: item)
    case .unknown:
      return item.displayKind.label
    }
  }

  private static func characterCount(for item: PasteBarHistoryItemAdapter) -> String {
    guard let text = item.text, !text.isEmpty else {
      return item.displayKind.label
    }

    return "\(text.count) characters"
  }

  private static func linkHost(for item: PasteBarHistoryItemAdapter) -> String? {
    guard let text = item.text,
          let url = URL(string: text)
    else {
      return nil
    }

    return url.host
  }
}

private extension PasteBarDisplayKind {
  var cardLabel: String {
    switch self {
    case .emailAddress:
      return "Email"
    case .multipleFiles:
      return "Files"
    case .phoneNumber:
      return "Phone"
    case .plainText, .richText:
      return "Text"
    default:
      return label
    }
  }
}
