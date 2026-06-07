import AppKit
import Sauce
import SwiftUI

private let pasteBarSearchHeight: CGFloat = 26

struct PasteBarView: View {
  let close: () -> Void
  let actionDispatcher: () -> PasteBarActionDispatcher?
  let pasteTarget: () -> PasteBarPasteTarget?

  @State private var appState = AppState.shared
  @State private var selection = PasteBarSelection()
  @State private var activeFilter: PasteBarFilter = .all
  @State private var feedback: PasteBarFeedback?
  @State private var hoveredItemId: PasteBarHistoryItemAdapter.ID?
  @State private var query = ""
  @FocusState private var searchFocused: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var provider: PasteBarResultProvider {
    PasteBarResultProvider(history: appState.history)
  }

  private var results: [PasteBarHistoryItemAdapter] {
    provider.results(query: query, filter: activeFilter)
  }

  private var filters: [PasteBarFilter] {
    provider.filters()
  }

  private var selectedItem: PasteBarHistoryItemAdapter? {
    guard let id = selection.selectedItemId else {
      return nil
    }

    return results.first { $0.id == id }
  }

  private var previewedItem: PasteBarHistoryItemAdapter? {
    guard let id = selection.previewedItemId else {
      return nil
    }

    return results.first { $0.id == id }
  }

  private var resultIds: [PasteBarHistoryItemAdapter.ID] {
    results.map(\.id)
  }

  init(
    close: @escaping () -> Void,
    actionDispatcher: @escaping () -> PasteBarActionDispatcher? = { nil },
    pasteTarget: @escaping () -> PasteBarPasteTarget? = { nil }
  ) {
    self.close = close
    self.actionDispatcher = actionDispatcher
    self.pasteTarget = pasteTarget
  }

  var body: some View {
    ZStack {
      if #available(macOS 26.0, *) {
        GlassEffectView()
      } else {
        VisualEffectView()
      }

      VStack(spacing: 12) {
        header
        filterStrip
        timeline
        feedbackView
      }
      .padding(16)

      if let previewedItem {
        PasteBarExpandedPreview(item: previewedItem) {
          selection.previewedItemId = nil
        }
        .padding(16)
        .transition(.opacity.combined(with: .scale(scale: reduceMotion ? 1 : 0.98)))
      }
    }
    .onAppear {
      query = appState.history.searchQuery
      searchFocused = true
      updateSelection(for: results)
      Task {
        try? await appState.history.loadForPasteBar()
      }
    }
    .onDisappear {
      appState.history.searchQuery = query
    }
    .onChange(of: query) {
      appState.history.setPasteBarSearchQuery(query)
    }
    .onChange(of: resultIds) {
      updateSelection(for: results)
    }
    .onChange(of: activeFilter) {
      feedback = nil
      updateSelection(for: results)
    }
    .onKeyPress { _ in
      handleKeyPress()
    }
    .animation(reduceMotion ? nil : .easeInOut(duration: 0.12), value: feedback)
    .animation(reduceMotion ? nil : .easeInOut(duration: 0.12), value: selection.previewedItemId)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Paste Bar")
  }

  private var header: some View {
    HStack(spacing: 12) {
      HStack(spacing: 6) {
        Image(systemName: "doc.on.clipboard")
          .imageScale(.medium)
        Text("Clipboard")
          .font(.headline)
      }
      .accessibilityElement(children: .combine)

      searchField

      Button {
        close()
      } label: {
        Image(systemName: "xmark.circle.fill")
          .imageScale(.large)
      }
      .buttonStyle(.borderless)
      .help("Close")
      .accessibilityLabel("Close Paste Bar")
    }
  }

  private var searchField: some View {
    HStack(spacing: 6) {
      Image(systemName: "magnifyingglass")
        .frame(width: 12, height: 12)
        .foregroundStyle(.secondary)

      TextField("Search Clipboard", text: $query)
        .disableAutocorrection(true)
        .lineLimit(1)
        .textFieldStyle(.plain)
        .focused($searchFocused)
        .onSubmit {
          perform(.paste)
        }

      if !query.isEmpty {
        Button {
          query = ""
          feedback = nil
        } label: {
          Image(systemName: "xmark.circle.fill")
            .frame(width: 12, height: 12)
        }
        .buttonStyle(.plain)
        .help("Clear Search")
        .accessibilityLabel("Clear Search")
      }
    }
    .padding(.horizontal, 8)
    .frame(height: pasteBarSearchHeight)
    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
  }

  private var filterStrip: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        ForEach(filters) { filter in
          PasteBarFilterChip(
            filter: filter,
            isSelected: filter == activeFilter,
            count: count(for: filter)
          ) {
            activeFilter = filter
          }
        }
      }
    }
    .accessibilityLabel("Paste Bar Filters")
  }

  private var timeline: some View {
    Group {
      if appState.history.all.isEmpty {
        PasteBarEmptyState(
          icon: "clipboard",
          title: "No Clipboard History",
          message: "Copied items stored by Maccy will appear here."
        )
      } else if results.isEmpty {
        PasteBarEmptyState(
          icon: activeFilter == .all ? "magnifyingglass" : "line.3.horizontal.decrease.circle",
          title: activeFilter == .all ? "No Search Results" : "No Items in Filter",
          message: activeFilter == .all ? "Try a different search." : "Choose another filter or clear search."
        )
      } else {
        ScrollViewReader { proxy in
          ScrollView(.horizontal, showsIndicators: true) {
            LazyHStack(spacing: 12) {
              ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
                PasteBarCardView(
                  item: item,
                  index: index,
                  isSelected: selection.selectedItemId == item.id,
                  isHovered: hoveredItemId == item.id
                )
                .id(item.id)
                .onHover { isHovered in
                  hoveredItemId = isHovered ? item.id : nil
                }
                .onTapGesture {
                  select(item)
                }
                .onTapGesture(count: 2) {
                  select(item)
                  perform(.paste)
                }
                .contextMenu {
                  contextMenu(for: item)
                }
              }
            }
            .padding(.vertical, 2)
          }
          .onChange(of: selection.selectedItemId) {
            if let selectedItemId = selection.selectedItemId {
              withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.12)) {
                proxy.scrollTo(selectedItemId, anchor: .center)
              }
            }
          }
        }
      }
    }
    .frame(maxHeight: .infinity)
  }

  @ViewBuilder
  private var feedbackView: some View {
    if let feedback {
      HStack(spacing: 8) {
        Image(systemName: feedback.iconName)
          .foregroundStyle(feedback.tint)

        Text(feedback.message)
          .font(.caption)
          .lineLimit(1)
          .truncationMode(.tail)

        Spacer(minLength: 0)

        Button {
          self.feedback = nil
        } label: {
          Image(systemName: "xmark")
            .imageScale(.small)
        }
        .buttonStyle(.borderless)
        .help("Dismiss")
        .accessibilityLabel("Dismiss Feedback")
      }
      .padding(.horizontal, 10)
      .frame(height: 24)
      .background(feedback.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
      .accessibilityElement(children: .combine)
    } else {
      Color.clear
        .frame(height: 24)
    }
  }

  @ViewBuilder
  private func contextMenu(for item: PasteBarHistoryItemAdapter) -> some View {
    let availability = PasteBarContextMenuActionAvailability.availability(for: item)

    if availability.canCopy {
      Button("Copy") {
        select(item)
        perform(.copy)
      }
    }

    if availability.canPaste {
      Button("Paste") {
        select(item)
        perform(.paste)
      }
    }

    if availability.canPasteWithoutFormatting {
      Button("Paste Without Formatting") {
        select(item)
        perform(.pasteWithoutFormatting)
      }
    }

    if availability.canPreview {
      Button("Preview") {
        select(item)
        perform(.preview)
      }
    }

    Divider()

    if availability.canTogglePin {
      Button(item.isPinned ? "Unpin" : "Pin") {
        select(item)
        perform(.togglePin)
      }
    }

    if availability.canDelete {
      Button("Delete") {
        select(item)
        perform(.delete)
      }
    }
  }

  private func handleKeyPress() -> KeyPress.Result {
    guard NSApp.characterPickerWindow == nil else {
      return .ignored
    }

    if handleQuickPasteShortcut() {
      return .handled
    }

    switch KeyChord(NSApp.currentEvent) {
    case .close:
      close()
      return .handled
    case .clearSearch:
      query = ""
      feedback = nil
      return .handled
    case .deleteCurrentItem:
      perform(.delete)
      return .handled
    case .pinOrUnpin:
      perform(.togglePin)
      return .handled
    case .selectCurrentItem:
      if NSEvent.modifierFlags.contains(.shift) {
        perform(.pasteWithoutFormatting)
      } else {
        perform(.paste)
      }
      return .handled
    case .togglePreview:
      togglePreview()
      return .handled
    case .moveToNext:
      moveSelection(by: 1)
      return .handled
    case .moveToPrevious:
      moveSelection(by: -1)
      return .handled
    default:
      break
    }

    guard let event = NSApp.currentEvent else {
      return .ignored
    }

    let modifierFlags = event.modifierFlags
      .intersection(.deviceIndependentFlagsMask)
      .subtracting([.capsLock, .numericPad, .function])

    if modifierFlags == [.command],
       Sauce.shared.key(for: Int(event.keyCode)) == .f {
      searchFocused = true
      return .handled
    }

    guard modifierFlags.isEmpty,
          let key = Sauce.shared.key(for: Int(event.keyCode))
    else {
      return .ignored
    }

    switch key {
    case .rightArrow:
      moveSelection(by: 1)
      return .handled
    case .leftArrow:
      moveSelection(by: -1)
      return .handled
    default:
      return .ignored
    }
  }

  private func handleQuickPasteShortcut() -> Bool {
    guard let event = NSApp.currentEvent else {
      return false
    }

    let modifierFlags = event.modifierFlags
      .intersection(.deviceIndependentFlagsMask)
      .subtracting([.capsLock, .numericPad, .function])
    guard modifierFlags == [.command],
          let character = Sauce.shared.character(for: Int(event.keyCode), cocoaModifiers: [])
    else {
      return false
    }

    guard let number = Int(character), number > 0, number <= min(9, results.count) else {
      return false
    }

    select(results[number - 1])
    perform(.paste)
    return true
  }

  private func updateSelection(for items: [PasteBarHistoryItemAdapter]) {
    guard !items.isEmpty else {
      selection.selectedItemId = nil
      selection.previewedItemId = nil
      return
    }

    if let selectedItemId = selection.selectedItemId,
       items.contains(where: { $0.id == selectedItemId }) {
      if let previewedItemId = selection.previewedItemId,
         !items.contains(where: { $0.id == previewedItemId }) {
        selection.previewedItemId = nil
      }
      return
    }

    selection.selectFirst(from: items)
    selection.previewedItemId = nil
  }

  private func select(_ item: PasteBarHistoryItemAdapter) {
    selection.selectedItemId = item.id
    feedback = nil
  }

  private func moveSelection(by delta: Int) {
    guard !results.isEmpty else {
      return
    }

    let currentIndex = selection.selectedItemId.flatMap { selectedItemId in
      results.firstIndex { $0.id == selectedItemId }
    } ?? 0
    let nextIndex = min(max(currentIndex + delta, 0), results.count - 1)
    selection.selectedItemId = results[nextIndex].id
    feedback = nil
  }

  private func togglePreview() {
    guard let selectedItem else {
      return
    }

    selection.previewedItemId = selection.previewedItemId == selectedItem.id ? nil : selectedItem.id
    feedback = nil
  }

  private func perform(_ action: PasteBarAction) {
    guard let selectedItem else {
      feedback = .warning("No item selected.")
      return
    }

    guard let dispatcher = actionDispatcher() else {
      feedback = .failure("Paste bar actions are unavailable.")
      return
    }

    let result = dispatcher.perform(action, on: selectedItem, pasteTarget: pasteTarget())
    apply(result, selectedItem: selectedItem)
  }

  private func apply(_ result: PasteBarActionResult, selectedItem: PasteBarHistoryItemAdapter) {
    switch result {
    case .copied:
      feedback = .success("Copied.")
    case .pasted:
      feedback = nil
    case .copiedFallback(let message):
      feedback = .warning(message)
    case .deleted:
      feedback = .success("Deleted.")
      updateSelection(for: results)
    case .pinned:
      feedback = .success("Pinned.")
    case .unpinned:
      feedback = .success("Unpinned.")
    case .preview(let id):
      selection.previewedItemId = id
      feedback = nil
    case .failed(let message):
      feedback = .failure(message.isEmpty ? "Action failed." : message)
    }
  }

  private func count(for filter: PasteBarFilter) -> Int {
    provider.results(query: "", filter: filter).count
  }
}

private struct PasteBarFeedback: Equatable {
  let message: String
  let iconName: String
  let tint: Color

  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.message == rhs.message && lhs.iconName == rhs.iconName
  }

  static func success(_ message: String) -> Self {
    Self(message: message, iconName: "checkmark.circle.fill", tint: .green)
  }

  static func warning(_ message: String) -> Self {
    Self(message: message, iconName: "exclamationmark.triangle.fill", tint: .orange)
  }

  static func failure(_ message: String) -> Self {
    Self(message: message, iconName: "xmark.octagon.fill", tint: .red)
  }
}

#Preview {
  PasteBarView(close: {})
    .frame(width: PasteBarPanelMetrics.defaultSize.width, height: PasteBarPanelMetrics.defaultSize.height)
}
