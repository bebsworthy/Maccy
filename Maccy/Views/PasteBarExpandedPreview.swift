import SwiftUI

struct PasteBarExpandedPreview: View {
  let item: PasteBarHistoryItemAdapter
  let close: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 8) {
        Image(systemName: item.displayKind.iconName)
          .foregroundStyle(.secondary)

        VStack(alignment: .leading, spacing: 2) {
          Text(item.summary.isEmpty ? item.displayKind.label : item.summary)
            .font(.headline)
            .lineLimit(1)
            .truncationMode(.middle)

          Text(item.displayKind.label)
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Spacer(minLength: 0)

        Button(action: close) {
          Image(systemName: "xmark.circle.fill")
            .imageScale(.large)
        }
        .buttonStyle(.borderless)
        .help("Close Preview")
        .accessibilityLabel("Close Preview")
      }

      Divider()

      PreviewItemView(item: item.decorator)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
    .padding(14)
    .frame(maxWidth: 420, maxHeight: .infinity)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .stroke(Color.secondary.opacity(0.22), lineWidth: 1)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Paste Bar Preview")
  }
}
