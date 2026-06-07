import SwiftUI

struct PasteBarView: View {
  let close: () -> Void

  var body: some View {
    ZStack {
      if #available(macOS 26.0, *) {
        GlassEffectView()
      } else {
        VisualEffectView()
      }

      VStack(spacing: 12) {
        HStack {
          Text("Paste Bar")
            .font(.headline)

          Spacer()

          Button(action: close) {
            Image(systemName: "xmark.circle.fill")
              .imageScale(.large)
          }
          .buttonStyle(.borderless)
          .help("Close")
          .accessibilityLabel("Close")
        }

        RoundedRectangle(cornerRadius: 8)
          .fill(.quaternary)
          .overlay {
            Text("Clipboard history will appear here")
              .foregroundStyle(.secondary)
          }
      }
      .padding(16)
    }
  }
}

#Preview {
  PasteBarView(close: {})
    .frame(width: PasteBarPanelMetrics.defaultSize.width, height: PasteBarPanelMetrics.defaultSize.height)
}
