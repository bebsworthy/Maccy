import SwiftUI

struct PasteBarFilterChip: View {
  let filter: PasteBarFilter
  let isSelected: Bool
  let count: Int
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 5) {
        Image(systemName: iconName)
          .font(.caption)

        Text(filter.label)
          .lineLimit(1)

        Text("\(count)")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
      .font(.caption)
      .padding(.horizontal, 9)
      .frame(height: 24)
      .background(
        isSelected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.10),
        in: Capsule()
      )
      .overlay {
        Capsule()
          .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.16), lineWidth: 1)
      }
    }
    .buttonStyle(.plain)
    .accessibilityLabel("\(filter.label), \(count) items")
  }

  private var iconName: String {
    switch filter {
    case .all:
      return "clock.arrow.circlepath"
    case .pinned:
      return "pin.fill"
    case .unpinned:
      return "pin.slash"
    case .sourceApp:
      return "app"
    case .displayKind(let kind):
      return kind.iconName
    }
  }
}

extension PasteBarDisplayKind {
  var iconName: String {
    switch self {
    case .multipleFiles:
      return "doc.on.doc"
    case .folder:
      return "folder"
    case .pdf:
      return "doc.richtext"
    case .archive:
      return "archivebox"
    case .imageFile, .image:
      return "photo"
    case .file:
      return "doc"
    case .color:
      return "paintpalette"
    case .link:
      return "link"
    case .emailAddress:
      return "envelope"
    case .phoneNumber:
      return "phone"
    case .table:
      return "tablecells"
    case .html:
      return "chevron.left.forwardslash.chevron.right"
    case .code:
      return "curlybraces"
    case .richText:
      return "textformat"
    case .emoji:
      return "face.smiling"
    case .plainText:
      return "text.alignleft"
    case .unknown:
      return "questionmark.square.dashed"
    }
  }
}
