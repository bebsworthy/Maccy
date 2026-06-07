import AppKit
import Sauce
import SwiftUI

private let pasteBarFeedbackHeight: CGFloat = 24
private let pasteBarTimelineHeight = PasteBarCardMetrics.height + 8

struct PasteBarView: View {
  let close: () -> Void
  let actionDispatcher: () -> PasteBarActionDispatcher?
  let pasteTarget: () -> PasteBarPasteTarget?

  @State private var appState = AppState.shared
  @State private var historySnapshot = PasteBarHistorySnapshot()
  @State private var visibleResults: [PasteBarHistoryItemAdapter] = []
  @State private var availableFilters: [PasteBarFilter] = [.all, .pinned, .unpinned]
  @State private var filterCounts: [PasteBarFilter: Int] = [:]
  @State private var selection = PasteBarSelection()
  @State private var activeFilter: PasteBarFilter = .all
  @State private var feedback: PasteBarFeedback?
  @State private var hoveredItemId: PasteBarHistoryItemAdapter.ID?
  @State private var isLoading = false
  @State private var query = ""
  @State private var newCopyHookToken: Clipboard.OnNewCopyHookToken?
  @State private var scrollTargetId: PasteBarHistoryItemAdapter.ID?
  @FocusState private var searchFocused: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var provider: PasteBarResultProvider {
    PasteBarResultProvider(history: appState.history)
  }

  private var selectedItem: PasteBarHistoryItemAdapter? {
    guard let id = selection.selectedItemId else {
      return nil
    }

    return visibleResults.first { $0.id == id }
  }

  private var previewedItem: PasteBarHistoryItemAdapter? {
    guard let id = selection.previewedItemId else {
      return nil
    }

    return visibleResults.first { $0.id == id }
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
      PasteBarMaterialBackground()

      VStack(spacing: 14) {
        PasteBarControlRail(
          query: $query,
          searchFocused: $searchFocused,
          filters: availableFilters,
          activeFilter: $activeFilter,
          count: { filterCounts[$0, default: 0] },
          clearFeedback: { feedback = nil },
          submitSearch: { perform(.paste) },
          close: close
        )

        PasteBarTimelineView(
          isLoading: isLoading,
          hasHistory: !historySnapshot.adapters.isEmpty,
          activeFilter: activeFilter,
          results: visibleResults,
          selectedItemId: selection.selectedItemId,
          hoveredItemId: $hoveredItemId,
          scrollTargetId: $scrollTargetId,
          select: select(_:),
          paste: paste(_:),
          perform: perform(_:on:)
        )
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 16)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .clipped()

      if let feedback {
        PasteBarFeedbackView(feedback: feedback) {
          self.feedback = nil
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
      }

      if let previewedItem {
        PasteBarExpandedPreview(item: previewedItem) {
          selection.previewedItemId = nil
        }
        .padding(16)
        .transition(.opacity.combined(with: .scale(scale: reduceMotion ? 1 : 0.98)))
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    .clipped()
    .overlay {
      RoundedRectangle(cornerRadius: 28, style: .continuous)
        .stroke(Color.primary.opacity(0.10), lineWidth: 1)
    }
    .onAppear {
      query = appState.history.searchQuery
      historySnapshot.refresh(from: appState.history)
      rebuildVisibleState(scrollToLeadingItem: true)
      installNewCopyHook()
      searchFocused = true
      Task {
        await reloadPasteBarHistory()
      }
    }
    .onDisappear {
      appState.history.searchQuery = query
      uninstallNewCopyHook()
    }
    .onChange(of: query) {
      appState.history.setPasteBarSearchQuery(query)
      rebuildVisibleState(scrollToLeadingItem: true)
    }
    .onChange(of: activeFilter) {
      feedback = nil
      rebuildVisibleState(scrollToLeadingItem: true)
    }
    .onKeyPress { _ in
      handleKeyPress()
    }
    .animation(reduceMotion ? nil : .easeInOut(duration: 0.12), value: feedback)
    .animation(reduceMotion ? nil : .easeInOut(duration: 0.12), value: selection.previewedItemId)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Paste Bar")
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
      perform(NSEvent.modifierFlags.contains(.shift) ? .pasteWithoutFormatting : .paste)
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
    case .rightArrow, .downArrow:
      moveSelection(by: 1)
      return .handled
    case .leftArrow, .upArrow:
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

    guard let number = Int(character), number > 0, number <= min(9, visibleResults.count) else {
      return false
    }

    select(visibleResults[number - 1])
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
    var transaction = Transaction()
    transaction.animation = nil

    withTransaction(transaction) {
      selection.selectedItemId = item.id
    }
    feedback = nil
  }

  private func paste(_ item: PasteBarHistoryItemAdapter) {
    select(item)
    perform(.paste)
  }

  private func perform(_ action: PasteBarAction, on item: PasteBarHistoryItemAdapter) {
    select(item)
    perform(action)
  }

  private func moveSelection(by delta: Int) {
    guard !visibleResults.isEmpty else {
      return
    }

    let currentIndex = selection.selectedItemId.flatMap { selectedItemId in
      visibleResults.firstIndex { $0.id == selectedItemId }
    } ?? 0
    let nextIndex = min(max(currentIndex + delta, 0), visibleResults.count - 1)
    selection.selectedItemId = visibleResults[nextIndex].id
    scrollTargetId = visibleResults[nextIndex].id
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
    apply(result)
  }

  private func apply(_ result: PasteBarActionResult) {
    switch result {
    case .copied:
      feedback = .success("Copied.")
    case .pasted:
      feedback = nil
    case .copiedFallback(let message):
      feedback = .warning(message)
    case .deleted:
      feedback = .success("Deleted.")
      refreshFromHistory()
    case .pinned:
      feedback = .success("Pinned.")
      refreshFromHistory()
    case .unpinned:
      feedback = .success("Unpinned.")
      refreshFromHistory()
    case .preview(let id):
      selection.previewedItemId = id
      feedback = nil
    case .failed(let message):
      feedback = .failure(message.isEmpty ? "Action failed." : message)
    }
  }

  private func rebuildVisibleState(scrollToLeadingItem: Bool) {
    let filters = provider.filters(from: historySnapshot.adapters)
    let resolvedFilter = filters.contains(activeFilter) ? activeFilter : .all

    availableFilters = filters
    filterCounts = provider.counts(from: historySnapshot.adapters)

    if resolvedFilter != activeFilter {
      activeFilter = resolvedFilter
    }

    visibleResults = provider.results(
      from: historySnapshot.adapters,
      query: query,
      filter: resolvedFilter
    )
    updateSelection(for: visibleResults)

    if scrollToLeadingItem {
      scrollTargetId = visibleResults.first?.id
    }
  }

  private func refreshFromHistory() {
    historySnapshot.refresh(from: appState.history)
    rebuildVisibleState(scrollToLeadingItem: false)
  }

  private func installNewCopyHook() {
    guard newCopyHookToken == nil else {
      return
    }

    newCopyHookToken = Clipboard.shared.onNewCopy { _ in
      Task { @MainActor in
        refreshFromHistory()
      }
    }
  }

  private func uninstallNewCopyHook() {
    Clipboard.shared.removeNewCopyHook(newCopyHookToken)
    newCopyHookToken = nil
  }

  private func reloadPasteBarHistory() async {
    isLoading = true
    defer { isLoading = false }

    do {
      try await appState.history.loadForPasteBar()
      refreshFromHistory()
    } catch {
      feedback = .failure(error.localizedDescription)
    }
  }
}

private struct PasteBarTimelineView: View {
  let isLoading: Bool
  let hasHistory: Bool
  let activeFilter: PasteBarFilter
  let results: [PasteBarHistoryItemAdapter]
  let selectedItemId: PasteBarHistoryItemAdapter.ID?
  @Binding var hoveredItemId: PasteBarHistoryItemAdapter.ID?
  @Binding var scrollTargetId: PasteBarHistoryItemAdapter.ID?
  let select: (PasteBarHistoryItemAdapter) -> Void
  let paste: (PasteBarHistoryItemAdapter) -> Void
  let perform: (PasteBarAction, PasteBarHistoryItemAdapter) -> Void

  var body: some View {
    Group {
      if !hasHistory {
        PasteBarEmptyState(
          icon: isLoading ? "clock" : "clipboard",
          title: isLoading ? "Loading Clipboard History" : "No Clipboard History",
          message: isLoading
            ? "Recent copied items will appear here."
            : "Copied items stored by Maccy will appear here."
        )
      } else if results.isEmpty {
        PasteBarEmptyState(
          icon: activeFilter == .all ? "magnifyingglass" : "line.3.horizontal.decrease.circle",
          title: activeFilter == .all ? "No Search Results" : "No Items in Filter",
          message: activeFilter == .all ? "Try a different search." : "Choose another filter or clear search."
        )
      } else {
        timeline
      }
    }
    .frame(height: pasteBarTimelineHeight)
    .clipped()
  }

  private var timeline: some View {
    ScrollViewReader { proxy in
      ScrollView(.horizontal, showsIndicators: true) {
        LazyHStack(spacing: 14) {
          ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
            Button {
              select(item)
            } label: {
              PasteBarCardView(
                item: item,
                index: index,
                isSelected: selectedItemId == item.id,
                isHovered: hoveredItemId == item.id
              )
            }
            .buttonStyle(.plain)
            .transaction { transaction in
              transaction.animation = nil
            }
            .simultaneousGesture(
              TapGesture(count: 2).onEnded {
                paste(item)
              }
            )
            .onHover { isHovered in
              hoveredItemId = isHovered ? item.id : nil
            }
            .contextMenu {
              PasteBarItemContextMenu(item: item, perform: perform)
            }
            .id(item.id)
          }
        }
        .padding(.vertical, 4)
        .frame(height: pasteBarTimelineHeight)
        .clipped()
      }
      .frame(height: pasteBarTimelineHeight)
      .clipped()
      .onChange(of: selectedItemId) {
        if selectedItemId == nil {
          scrollTargetId = nil
        }
      }
      .onChange(of: scrollTargetId) {
        if let scrollTargetId {
          proxy.scrollTo(scrollTargetId, anchor: .leading)
          self.scrollTargetId = nil
        }
      }
    }
  }
}

private struct PasteBarItemContextMenu: View {
  let item: PasteBarHistoryItemAdapter
  let perform: (PasteBarAction, PasteBarHistoryItemAdapter) -> Void

  var body: some View {
    let availability = PasteBarContextMenuActionAvailability.availability(for: item)

    if availability.canCopy {
      Button("Copy") {
        perform(.copy, item)
      }
    }

    if availability.canPaste {
      Button("Paste") {
        perform(.paste, item)
      }
    }

    if availability.canPasteWithoutFormatting {
      Button("Paste Without Formatting") {
        perform(.pasteWithoutFormatting, item)
      }
    }

    if availability.canPreview {
      Button("Preview") {
        perform(.preview, item)
      }
    }

    Divider()

    if availability.canTogglePin {
      Button(item.isPinned ? "Unpin" : "Pin") {
        perform(.togglePin, item)
      }
    }

    if availability.canDelete {
      Button("Delete") {
        perform(.delete, item)
      }
    }
  }
}

private struct PasteBarControlRail: View {
  @Binding var query: String
  let searchFocused: FocusState<Bool>.Binding
  let filters: [PasteBarFilter]
  @Binding var activeFilter: PasteBarFilter
  let count: (PasteBarFilter) -> Int
  let clearFeedback: () -> Void
  let submitSearch: () -> Void
  let close: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      PasteBarFilterStrip(
        filters: filters,
        activeFilter: $activeFilter,
        count: count
      )

      Spacer(minLength: 12)

      searchAndClose
    }
    .frame(height: 30)
    .frame(maxWidth: .infinity)
    .clipped()
    .controlSize(.small)
  }

  private var searchAndClose: some View {
    HStack(spacing: 8) {
      PasteBarSearchControl(
        query: $query,
        searchFocused: searchFocused,
        clearFeedback: clearFeedback,
        submitSearch: submitSearch
      )

      Button(action: close) {
        Image(systemName: "xmark")
          .imageScale(.small)
      }
      .buttonStyle(.bordered)
      .buttonBorderShape(.circle)
      .controlSize(.small)
      .help("Close")
      .accessibilityLabel("Close Paste Bar")
    }
  }
}

private struct PasteBarSearchControl: View {
  @Binding var query: String
  let searchFocused: FocusState<Bool>.Binding
  let clearFeedback: () -> Void
  let submitSearch: () -> Void

  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: "magnifyingglass")
        .imageScale(.small)
        .foregroundStyle(.secondary)

      TextField("Search", text: $query)
        .disableAutocorrection(true)
        .lineLimit(1)
        .font(.callout)
        .textFieldStyle(.plain)
        .focused(searchFocused)
        .onSubmit(submitSearch)

      if !query.isEmpty {
        Button {
          query = ""
          clearFeedback()
        } label: {
          Image(systemName: "xmark.circle.fill")
            .imageScale(.small)
        }
        .buttonStyle(.plain)
        .help("Clear Search")
        .accessibilityLabel("Clear Search")
      }
    }
    .padding(.horizontal, 10)
    .frame(minWidth: 200, idealWidth: 260, maxWidth: 260, minHeight: 28, maxHeight: 28)
    .background(.regularMaterial, in: Capsule())
    .overlay {
      Capsule()
        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
    }
  }
}

private struct PasteBarFilterStrip: View {
  let filters: [PasteBarFilter]
  @Binding var activeFilter: PasteBarFilter
  let count: (PasteBarFilter) -> Int

  private var coreFilters: [PasteBarFilter] {
    [.all, .pinned, .unpinned].filter(filters.contains)
  }

  private var sourceAppFilters: [PasteBarFilter] {
    filters.filter {
      if case .sourceApp = $0 { return true }
      return false
    }
  }

  private var displayKindFilters: [PasteBarFilter] {
    filters.filter {
      if case .displayKind = $0 { return true }
      return false
    }
  }

  var body: some View {
    HStack(spacing: 8) {
      ForEach(coreFilters) { filter in
        PasteBarFilterChip(
          filter: filter,
          isSelected: filter == activeFilter,
          count: count(filter)
        ) {
          activeFilter = filter
        }
      }

      PasteBarFilterMenu(
        title: "Apps",
        iconName: "app",
        filters: sourceAppFilters,
        activeFilter: $activeFilter,
        count: count
      )

      PasteBarFilterMenu(
        title: "Types",
        iconName: "line.3.horizontal.decrease",
        filters: displayKindFilters,
        activeFilter: $activeFilter,
        count: count
      )
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .clipped()
    .accessibilityLabel("Paste Bar Filters")
  }
}

private struct PasteBarFilterMenu: View {
  let title: String
  let iconName: String
  let filters: [PasteBarFilter]
  @Binding var activeFilter: PasteBarFilter
  let count: (PasteBarFilter) -> Int

  private var activeMenuFilter: PasteBarFilter? {
    filters.first { $0 == activeFilter }
  }

  var body: some View {
    Menu {
      if filters.isEmpty {
        Text("No \(title)")
      } else {
        ForEach(filters) { filter in
          Button {
            activeFilter = filter
          } label: {
            Label {
              Text("\(filter.label) (\(count(filter)))")
            } icon: {
              if filter == activeFilter {
                Image(systemName: "checkmark")
              }
            }
          }
        }
      }
    } label: {
      HStack(spacing: 5) {
        Label(activeMenuFilter?.label ?? title, systemImage: activeMenuFilter?.iconName ?? iconName)
          .labelStyle(.titleAndIcon)
          .lineLimit(1)
          .truncationMode(.tail)

        Image(systemName: "chevron.down")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
      .font(.callout)
      .frame(width: 96, alignment: .leading)
      .clipped()
    }
    .menuStyle(.button)
    .buttonStyle(.bordered)
    .buttonBorderShape(.roundedRectangle(radius: 7))
    .controlSize(.small)
    .disabled(filters.isEmpty)
    .accessibilityLabel("\(title) Filters")
  }
}

private struct PasteBarFeedbackView: View {
  let feedback: PasteBarFeedback
  let dismiss: () -> Void

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: feedback.iconName)
        .foregroundStyle(feedback.tint)

      Text(feedback.message)
        .font(.caption)
        .lineLimit(1)
        .truncationMode(.tail)

      Button(action: dismiss) {
        Image(systemName: "xmark")
          .imageScale(.small)
      }
      .buttonStyle(.borderless)
      .help("Dismiss")
      .accessibilityLabel("Dismiss Feedback")
    }
    .padding(.horizontal, 10)
    .frame(maxWidth: 360, minHeight: pasteBarFeedbackHeight, maxHeight: pasteBarFeedbackHeight)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .stroke(feedback.tint.opacity(0.35), lineWidth: 1)
    }
    .accessibilityElement(children: .combine)
  }
}

private struct PasteBarMaterialBackground: View {
  var body: some View {
    ZStack {
      if #available(macOS 26.0, *) {
        GlassEffectView()
      } else {
        VisualEffectView(
          material: .popover,
          blendingMode: .behindWindow
        )
      }

      Color(nsColor: .windowBackgroundColor)
        .opacity(0.18)
    }
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

private extension PasteBarFilter {
  var iconName: String {
    switch self {
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

#Preview {
  PasteBarView(close: {})
    .frame(width: PasteBarPanelMetrics.defaultSize.width, height: PasteBarPanelMetrics.defaultSize.height)
}
