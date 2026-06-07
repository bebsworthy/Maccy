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
          .imageScale(.small)

        Text(displayLabel)
          .lineLimit(1)
      }
      .font(.callout)
      .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
      .frame(minWidth: 0)
    }
    .buttonStyle(.bordered)
    .buttonBorderShape(.roundedRectangle(radius: 7))
    .controlSize(.small)
    .tint(isSelected ? .accentColor : .primary.opacity(0.20))
    .accessibilityLabel("\(filter.label), \(count) items")
  }

  private var displayLabel: String {
    switch filter {
    case .all:
      return "Clipboard"
    default:
      return filter.label
    }
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
