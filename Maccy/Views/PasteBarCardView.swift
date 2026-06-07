import AppKit
import Sauce
import SwiftHEXColors
import SwiftUI

private let pasteBarCardWidth: CGFloat = 190
private let pasteBarCardHeight: CGFloat = 148
private let pasteBarPreviewHeight: CGFloat = 82

struct PasteBarCardView: View {
  let item: PasteBarHistoryItemAdapter
  let index: Int
  let isSelected: Bool
  let isHovered: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      header
      preview
      footer
    }
    .padding(10)
    .frame(width: pasteBarCardWidth, height: pasteBarCardHeight, alignment: .topLeading)
    .background(backgroundStyle, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.18), lineWidth: isSelected ? 3 : 1)
    }
    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
      return AnyShapeStyle(Color.secondary.opacity(0.16))
    }

    return AnyShapeStyle(.regularMaterial)
  }

  private var header: some View {
    HStack(spacing: 6) {
      Text(item.displayKind.label)
        .font(.caption)
        .fontWeight(.semibold)
        .lineLimit(1)

      Text(item.copiedAt, style: .relative)
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)

      Spacer(minLength: 0)

      if item.isPinned {
        Image(systemName: "pin.fill")
          .font(.caption)
          .foregroundStyle(.secondary)
          .accessibilityLabel("Pinned")
      }

      if index < 9 {
        KeyboardShortcutView(shortcut: quickShortcut(for: index))
          .font(.caption)
          .frame(minWidth: 22, alignment: .trailing)
          .accessibilityLabel("Command \(index + 1)")
      }
    }
  }

  @ViewBuilder
  private var preview: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 6, style: .continuous)
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
      case .code, .table:
        textPreview(monospaced: true)
      case .link, .emailAddress, .phoneNumber, .plainText:
        textPreview(monospaced: false)
      case .unknown:
        unknownPreview
      }
    }
    .frame(height: pasteBarPreviewHeight)
    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
  }

  private var footer: some View {
    VStack(alignment: .leading, spacing: 3) {
      HStack(spacing: 4) {
        AppImageView(appImage: item.sourceAppImage, size: CGSize(width: 14, height: 14))

        Text(item.sourceAppName ?? "Unknown App")
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }

      Text(metadata)
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .truncationMode(.middle)
    }
  }

  @ViewBuilder
  private var imagePreview: some View {
    if let image = item.image ?? item.decorator.thumbnailImage {
      Image(nsImage: image)
        .resizable()
        .scaledToFill()
    } else if let url = item.fileURLs.first {
      fileIcon(url)
    } else {
      Image(systemName: "photo")
        .font(.title)
        .foregroundStyle(.secondary)
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

      Text(item.fileURLs.count > 1 ? "\(item.fileURLs.count) items" : (item.fileURLs.first?.lastPathComponent ?? "File"))
        .font(.caption)
        .lineLimit(1)
        .truncationMode(.middle)
        .padding(.horizontal, 8)
    }
  }

  @ViewBuilder
  private var colorPreview: some View {
    if let color = colorFromText {
      color
        .overlay {
          Text(item.text ?? item.summary)
            .font(.headline)
            .foregroundStyle(.primary)
            .padding(6)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
    } else {
      textPreview(monospaced: false)
    }
  }

  private var richTextPreview: some View {
    ScrollView {
      if let attributed = attributedPreview {
        Text(attributed.string)
          .font(.caption)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(8)
      } else {
        textPreview(monospaced: false)
      }
    }
  }

  private var emojiPreview: some View {
    Text(item.text ?? item.summary)
      .font(.system(size: 44))
      .lineLimit(1)
      .minimumScaleFactor(0.5)
      .padding(8)
  }

  private func textPreview(monospaced: Bool) -> some View {
    ScrollView {
      Text(item.previewText.isEmpty ? item.summary : item.previewText)
        .font(monospaced ? .system(.caption, design: .monospaced) : .caption)
        .lineLimit(5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
    }
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
  }

  private func fileIcon(_ url: URL) -> some View {
    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
      .resizable()
      .scaledToFit()
      .frame(width: 42, height: 42)
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

  private var metadata: String {
    if !item.fileURLs.isEmpty {
      return item.fileURLs.count == 1 ? item.fileURLs[0].deletingLastPathComponent().path : "\(item.fileURLs.count) files"
    }

    if let text = item.text, !text.isEmpty {
      return "\(text.count) characters"
    }

    if item.image != nil {
      return "Image data"
    }

    return item.displayKind.label
  }

  private var accessibilityLabel: String {
    var parts = [item.displayKind.label, item.summary]
    if let sourceAppName = item.sourceAppName {
      parts.append(sourceAppName)
    }
    parts.append(metadata)
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
