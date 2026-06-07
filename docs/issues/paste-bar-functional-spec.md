# Spec: Paste Bar Functional Specification

artifact_type: spec
status: ready
spec_id: paste-bar-functional-spec
last_updated: 2026-06-07

## 1. Summary

Define a Maccy paste bar: a transient, keyboard-first horizontal clipboard-history surface opened by a separate customizable global shortcut. The paste bar lets users visually browse recent Maccy history items, search and filter them, inspect rich previews, and copy or paste a selected item.

This specification is now Maccy-integration-ready. It keeps the paste bar separate from the existing vertical popup and adapts the feature to Maccy's current SwiftData, `HistoryItem`, `HistoryItemDecorator`, `History`, `Search`, `Clipboard`, `KeyboardShortcuts`, and AppKit panel architecture.

## 2. Context

Paste documents a visual clipboard-history timeline opened by default with `Shift-Command-V`, with rich previews, source app metadata, search, filters, keyboard navigation, direct paste, and accessibility fallback behavior. PastePal documents an edge-positionable bar/side window with configurable shortcuts, item metadata, source app detection, collections, preview, context menu actions, quick mode, and rich content-type cards.

Maccy currently has a vertical popup opened by `KeyboardShortcuts.Name.popup`, defaulting to `Shift-Command-C`, hosted in `FloatingPanel<ContentView>`. Clipboard history is stored as SwiftData `HistoryItem` records with related `HistoryItemContent` pasteboard representations. Display/search state is exposed through `HistoryItemDecorator`, `History.all`, `History.items`, `History.searchQuery`, `Search`, and `NavigationManager`.

## 3. Problem

Maccy's existing popup is efficient and text-first, but it is optimized as a vertical utility list. A paste bar should add a separate visual scanning workflow for users who recognize clipboard items by card preview, source app, copied time, type, and visual content. The implementation must reuse Maccy's existing storage and action paths unless a concrete feature need requires a small adapter.

## 4. Goals

- Add a separate paste bar surface without replacing the existing vertical popup workflow.
- Favor visual recognition through rich horizontal cards over dense list scanning.
- Reuse Maccy's existing clipboard history, search, selection, preview, paste, and settings infrastructure.
- Avoid SwiftData schema changes and pasteboard capture changes for v1.
- Preserve privacy by relying on Maccy's existing capture-time ignore policies and stored-history boundaries.

## 5. Out Of Scope

- Replacing the existing popup, status item behavior, or `Shift-Command-C` workflow.
- SwiftData model migrations or new persisted clipboard item fields.
- Capturing new pasteboard types beyond Maccy's current supported types.
- Cross-device sync, shared pinboards, full collection management, item editing, history retention management, analytics, and telemetry.
- Quick Look integration in v1. Maccy's existing preview views are the v1 expanded-preview baseline.

## 6. Target Behavior

The paste bar appears as a wide horizontal overlay near the configured vertical edge of the active screen. Bottom edge is the default placement, and top edge is available as a user-configurable alternative. It shows Maccy history items newest first as rich cards, supports horizontal scrolling and keyboard focus, exposes search and Maccy-backed filters, and lets the user copy, paste, paste without formatting, preview, delete, or pin/unpin the selected item.

The paste bar is opened by a separate `KeyboardShortcuts.Name.pasteBar` shortcut. The default shortcut is `Shift-Command-V`. The existing `KeyboardShortcuts.Name.popup` shortcut remains `Shift-Command-C` by default and continues to open the existing popup.

If direct paste into the previously active app is unavailable, the paste bar copies the selected item to the system clipboard, keeps the item focused, and shows visible feedback so the user can paste manually.

## 7. Implementation Context

Maccy is a macOS menu bar app whose main UI is SwiftUI hosted in AppKit `NSPanel` infrastructure.

Current integration points:

- `Maccy/Models/HistoryItem.swift`: SwiftData history model with `application`, `firstCopiedAt`, `lastCopiedAt`, `numberOfCopies`, `pin`, `title`, and `contents`.
- `Maccy/Models/HistoryItemContent.swift`: stored pasteboard representation with `type` and optional raw `Data`.
- `Maccy/Observables/HistoryItemDecorator.swift`: current UI adapter for title, source app name/icon, shortcuts, selection, thumbnails, preview image cache, text, and pin state.
- `Maccy/Observables/History.swift`: loads, sorts, searches, deletes, pins, selects, and dispatches copy/paste actions for history items.
- `Maccy/Search.swift`: exact, fuzzy, regexp, and mixed search over `HistoryItemDecorator` titles.
- `Maccy/Clipboard.swift`: reads supported pasteboard types, applies capture-time ignore policy, writes selected items back to `NSPasteboard`, removes formatting, and triggers synthetic paste events.
- `Maccy/Observables/Popup.swift`, `Maccy/FloatingPanel.swift`, and `Maccy/AppDelegate.swift`: current shortcut, panel, close, focus, and sizing infrastructure.
- `Maccy/Settings/GeneralSettingsPane.swift` and `Maccy/Settings/AppearanceSettingsPane.swift`: current settings surfaces for shortcuts and popup placement.

The paste bar must be implemented as an additive surface over these components, not as a replacement of existing popup internals.

## 8. Target Architecture

The paste bar architecture has these Maccy-specific subsystems:

- Paste bar invocation controller: registers `KeyboardShortcuts.Name.pasteBar`, opens/closes the paste-bar panel, and leaves `KeyboardShortcuts.Name.popup` unchanged.
- Paste bar panel: a dedicated `PasteBarPanel<PasteBarView>` or paste-bar-specific AppKit panel/controller owned by `AppDelegate`, not a second instance of Maccy's current `FloatingPanel<ContentView>`.
- Paste bar positioner: computes top/bottom edge origins using a new `PasteBarPosition` default, not `PopupPosition`.
- Paste bar result provider: reads from `History.all`, applies paste-bar filters, local paste-bar search, and paste-bar-specific `lastCopiedAt` descending ordering.
- Paste bar item adapter: exposes card-ready data by reading `HistoryItemDecorator` and wrapped `HistoryItem`.
- Paste bar classifier: computes `PasteBarDisplayKind` from existing pasteboard contents and computed `HistoryItem` projections.
- Visual timeline: renders a single horizontal card row with search/filter controls in the same surface.
- Paste bar selection/navigation: uses paste-bar-local focus and selection state. It may copy concepts from `NavigationManager`, but it must not mutate `AppState.shared.navigator`, `HistoryItemDecorator.selectionIndex`, `NavigationManager.scrollTarget`, or `AppState.shared.preview`.
- Paste bar action dispatcher: wraps Maccy's copy, paste, paste-without-formatting, delete, pin/unpin, and preview actions through paste-bar-specific result-returning methods so the paste bar can show feedback before closing.
- Paste bar preview renderer: reuses `PreviewItemView` rendering data where possible, but owns paste-bar-local preview presentation state. It must not use `AppState.shared.preview` or `SlideoutController` state for v1.

## 9. Requirements

### REQ-001: Open and dismiss the paste bar

Scope: paste bar invocation controller
Rationale: The paste bar is a separate workflow from Maccy's existing popup.

The paste bar must open from `KeyboardShortcuts.Name.pasteBar`. The default shortcut must be `Shift-Command-V`, and the user must be able to customize it through Maccy's existing `KeyboardShortcuts.Recorder` pattern.

The paste bar must dismiss on `Escape`, successful paste/copy action, explicit close/collapse control, outside click or focus loss, and repeated paste-bar shortcut when configured as toggle. Dismissal must not alter the existing popup shortcut, popup panel, or status item click behavior.

### REQ-002: Render a horizontal visual timeline

Scope: visual timeline
Rationale: The supplied screenshots and Paste documentation emphasize visual timeline browsing with newest items first.

The default paste-bar layout must be a wide horizontal overlay near the bottom edge of the active screen. The user must be able to configure placement to either bottom edge or top edge through a new paste-bar placement setting. Both placements must contain one primary horizontal row of item cards and support horizontal overflow through scrolling and keyboard navigation.

### REQ-003: Order items by recency

Scope: paste bar result provider
Rationale: Recency-first ordering matches clipboard history expectations and the visible timestamp ordering in the screenshots.

Paste bar history items must appear newest first by default by sorting visible paste-bar results by `HistoryItem.lastCopiedAt` descending after paste-bar filters and search are applied. The paste bar must not rely on `History.all` order because Maccy's existing `Sorter` can honor `Defaults[.sortBy]` and `Defaults[.pinTo]` for the vertical popup. Pinned items must not be promoted in the all-history paste-bar filter; the pinned filter shows only pinned items, also ordered by `lastCopiedAt` descending. The card copied-time metadata must use `HistoryItem.lastCopiedAt`; expanded metadata may also show `firstCopiedAt` and `numberOfCopies`.

### REQ-004: Show identifying card metadata

Scope: visual timeline
Rationale: The paste bar is useful only if users can identify items quickly at a glance.

Each item card must show enough metadata to identify the item without opening a full preview. Required metadata includes computed display kind, source app icon/name when known, copied time, `HistoryItemDecorator.title`, and type-specific metadata such as filename, URL host, file count, image dimensions, character count, or color value when cheaply available.

Unknown metadata must degrade gracefully by hiding only the missing field, not the entire card.

### REQ-005: Render type-specific previews

Scope: paste bar classifier and preview renderer
Rationale: The core distinction of the paste bar is rich visual recognition across clipboard content types.

Cards must render type-specific previews for Maccy's v1 stored content: plain text, rich text, HTML, code-like text, links, images/screenshots, files, folders, multiple files, PDFs, archives, colors, emoji, and unknown/unsupported content. Type detection must be extensible through computed classifiers and preview renderers without adding persisted fields or changing selection/action behavior.

Calendar, contact, map-location, app-specific private pasteboard, and other unsupported kinds must remain future extensions unless Maccy first captures the required pasteboard types.

Fallback cards must still allow available copy, paste, delete, pin/unpin, and preview actions when content can be represented on the clipboard.

### REQ-006: Support keyboard and pointer navigation

Scope: paste bar selection/navigation
Rationale: Paste and PastePal both position the paste bar as a keyboard-first productivity surface.

The paste bar must be fully usable from the keyboard. Left and Right arrows move item focus in the horizontal row. Up and Down may alias to previous and next for compatibility with Maccy's existing navigation habits. Trackpad or mouse wheel scrolls the horizontal timeline. Clicking a card selects and activates it according to the chosen action. `Return` performs the primary paste action, `Shift-Return` performs paste without formatting when available, the existing preview shortcut opens expanded preview, and visible quick shortcut numbers select visible items.

Paste-bar navigation state must be isolated from the existing popup. It must not write `AppState.shared.navigator`, `HistoryItemDecorator.selectionIndex`, `NavigationManager.scrollTarget`, or `AppState.shared.preview`. Any visual selected/focused state required by paste-bar cards must live in `PasteBarSelection`.

### REQ-007: Search visible history

Scope: paste bar result provider
Rationale: Search is a primary way to reduce visual history to a useful result set.

Typing while the paste bar is open must begin search unless focus is already inside a non-search control. `Command-F` must focus or reveal search. Search must use paste-bar-local query state and run Maccy's existing search modes over `History.all` instead of adding a parallel index.

The paste bar may share the visible query value with `History.searchQuery`, but it must not mutate `History.items`, trigger `AppState.shared.popup.needsResize`, or change the existing popup's navigation state while the paste bar is open. Implementations that bridge to `History.searchQuery` must snapshot the previous popup query on open and restore or explicitly commit the paste-bar query on close.

Paste bar search must extend Maccy's current searchable text through a computed provider string that includes `HistoryItemDecorator.title`, display kind label, source app name, safe file/URL metadata, and type-specific metadata. To keep this concrete, `Search` must be generalized from the current `HistoryItemDecorator`-only `Search.Searchable` typealias to a small protocol or generic input that exposes searchable text. `HistoryItemDecorator` must keep existing behavior by returning `title` as its searchable text, and the paste-bar adapter must return the computed provider string. Search must not include values that Maccy's capture-time policy did not store.

Image OCR search is outside paste-bar v1 unless it uses Maccy's existing image title recognition.

### REQ-008: Switch Maccy-backed filters

Scope: paste bar result provider
Rationale: Reference screenshots show category/filter chips, but Maccy currently has pins and stored pasteboard-type groups rather than collections.

The paste bar must support visible filters backed by current Maccy data, including all history, pinned, unpinned, source app, and content type groups. It must not specify collections, favorites, or pinboards beyond Maccy's existing `pin` field.

The paste bar must allow switching filters without closing. Search must operate within the active filter by default, with an affordance to return to all history.

### REQ-009: Paste with fallback behavior

Scope: paste bar action dispatcher
Rationale: Direct paste depends on macOS accessibility permission, but users still need a reliable fallback path.

Primary paste action must copy the selected `HistoryItem` through `PasteBarClipboardWriting` and insert into the app that was active before the paste bar opened when direct paste is available. Paste-bar actions must not call `History.select` directly because that method closes the existing popup and derives action choice from the current event's modifier flags.

Delete and Pin/Unpin must use paste-bar-specific wrappers or side-effect-controlled history mutation helpers. Allowed shared mutations are deleting the stored item, changing `HistoryItem.pin`, updating `History.all`, saving SwiftData changes, and refreshing paste-bar-local results. These actions must not close the existing popup, mutate `History.searchQuery`, replace popup `History.items` for the current popup session, write `AppState.shared.navigator`, or request `AppState.shared.popup` resizing as part of paste-bar handling.

If direct paste is unavailable, the item must remain copied to the system clipboard, the bar must show feedback, and the user must be able to paste manually. The paste bar must not silently close before visible fallback feedback is available.

Paste without formatting must use `PasteBarClipboardWriting.copy(item:removeFormatting:)` with `removeFormatting` enabled and production behavior backed by Maccy's existing formatting-removal copy path. If plain-text extraction is unavailable, the action must be disabled or fall back to normal copy/paste with clear feedback.

### REQ-010: Provide an item context menu

Scope: paste bar action dispatcher
Rationale: The screenshots and PastePal documentation expose item-level actions through context menus.

Right-clicking or invoking the context menu key on an item must expose Maccy-backed item actions. Required v1 actions are Copy, Paste, Paste Without Formatting, Preview, Delete, and Pin/Unpin.

Reveal/open source file or link actions are future work unless they are backed by safe file URL or URL detection. Add to collection/favorite/pinboard actions are out of scope beyond Pin/Unpin.

Unavailable actions must be hidden or disabled with predictable behavior.

### REQ-011: Provide expanded preview

Scope: paste bar preview renderer
Rationale: Inline card previews are optimized for recognition; users still need a way to inspect an item before pasting.

The paste bar must provide an expanded preview action using Maccy's existing preview rendering data where possible. Preview behavior must support larger text/rich text view, image preview, file/PDF metadata or preview when available, link metadata or open-link future affordance, and metadata view for unsupported types.

Paste bar v1 must own paste-bar-local preview presentation state. It may reuse `PreviewItemView` rendering or extract a popup-independent preview content view, but it must not use `AppState.shared.preview`, `SlideoutController`, popup slideout placement, or popup window sizing defaults.

Quick Look is not required for v1.

### REQ-012: Define multi-selection behavior

Scope: paste bar selection/navigation
Rationale: Maccy has paste-stack and multi-selection infrastructure, but it is currently disabled.

Paste bar v1 is single-selection. Existing `NavigationManager` and paste-stack concepts may be reused internally, but the paste bar must not expose multi-select affordances while `AppState.multiSelectionEnabled` remains false.

If Maccy later enables multi-selection, users must be able to extend selection with `Shift` and toggle items with `Command`, and pasting multiple selected items must preserve visible order unless the existing paste-stack mode defines a different sequence.

### REQ-013: Handle empty and unavailable states

Scope: visual timeline
Rationale: The transient surface must remain predictable when there is no actionable item.

The paste bar must show clear empty states for no clipboard history, no search results, active filter has no items, direct paste unavailable, preview unavailable, and item unavailable/deleted. Empty states must preserve dismissal and search/filter navigation.

### REQ-014: Respect privacy and sensitive-content policy

Scope: paste bar result provider
Rationale: Clipboard history may contain sensitive data, so policy filtering must happen before display and search.

The paste bar must only read from Maccy's stored history and must never re-read raw pasteboard content for display. Maccy's capture-time ignored events, ignored apps, ignored pasteboard types, ignored regexps, transient/concealed/autogenerated pasteboard markers, and enabled pasteboard type policy remain owned by `Clipboard`.

The paste bar must consume the same capture-time filtered history that Maccy already stores. It must not add a separate secret/redacted-card filtering system in v1. If a future feature adds display-time filtering, it must be specified separately and must not delete stored history.

### REQ-015: Report action failures clearly

Scope: paste bar action dispatcher
Rationale: The user should not lose context when an action cannot complete.

Action failures must not silently close the bar unless the selected fallback behavior succeeds and feedback can be shown. Missing direct-paste permission must keep the copied item on the clipboard and show fallback feedback. Item data unavailable must keep the bar open and mark the item unavailable. Preview unavailable must show metadata-only preview. Paste without formatting unavailable must disable the action or explain fallback. Deleted item selected must remove the card and move focus to the nearest available item.

### REQ-016: Separate direct paste from copy-to-clipboard

Scope: paste bar action dispatcher
Rationale: Maccy's current `History.select` can close and paste immediately; the paste bar needs visible fallback behavior.

The paste bar must distinguish copy-to-clipboard from direct-paste actions. Copy must use a paste-bar clipboard-writing adapter backed by Maccy's clipboard service. Direct paste must use Maccy's existing synthetic paste path only when accessibility permission is available. Missing permission must not prevent selecting, previewing, or copying an item.

Maccy's current `Accessibility.check()` does not return a permission status, and `Clipboard.paste()` currently calls it before posting synthetic paste events. Paste-bar implementation must add `Accessibility.isTrusted` as a public read-only status that wraps `AXIsProcessTrustedWithOptions(nil)`. The paste-bar dispatcher must check `Accessibility.isTrusted` before calling `Clipboard.paste()`, show copy-fallback feedback when it is false, and call `Clipboard.paste()` only when it is true.

The accessibility status and clipboard write result must be testable without requiring real macOS permission changes or real pasteboard failures. The paste-bar action dispatcher must depend on injectable trust-checking and clipboard-writing seams whose production implementations read `Accessibility.isTrusted` and write through Maccy's clipboard service.

### REQ-017: Apply clipboard policies consistently

Scope: paste bar result provider
Rationale: The paste bar is a richer display surface over clipboard history and must not bypass Maccy's privacy controls.

The paste bar must respect Maccy's existing capture-time ignore lists, enabled pasteboard types, retention state, and pause/ignore-events state by reading only stored `History` results. It must not define additional secret filtering behavior in v1.

### REQ-018: Provide user-visible diagnostics

Scope: visual timeline
Rationale: User-visible diagnostics are required because this spec does not add developer telemetry.

The paste bar must provide user-visible feedback for direct paste permission missing, no results, preview unavailable, paste failed, and item unavailable/deleted.

### REQ-019: Customize the paste bar shortcut

Scope: paste bar invocation controller
Rationale: The paste bar shortcut must fit user workflows and avoid conflicts with existing system or app shortcuts.

The user must be able to customize `KeyboardShortcuts.Name.pasteBar` from the default `Shift-Command-V` to another valid key combination. The chosen shortcut must persist until changed or reset. If the requested shortcut cannot be registered or conflicts with a reserved shortcut, the previous working shortcut must remain active and the user must receive feedback.

This requirement must not change `KeyboardShortcuts.Name.popup`, whose current default remains `Shift-Command-C`.

### REQ-020: Classify copied content with extensible Maccy heuristics

Scope: paste bar classifier
Rationale: Users can copy many pasteboard representations, but Maccy v1 should classify only what it already stores.

The paste bar must classify each item through an ordered `PasteBarDisplayKind` heuristic list with deterministic precedence. Each classifier must read existing `HistoryItem.contents`, `HistoryItem` computed projections, file URL metadata, and `HistoryItemDecorator` display data. Explicit stored pasteboard types must take precedence over inferred string parsing. More specific classifiers must run before broader fallbacks.

The selected display kind must be computed at display/search time and must not be persisted in SwiftData for v1.

### REQ-021: Follow a visual design contract

Scope: visual timeline
Rationale: A paste bar succeeds through fast visual recognition, so layout, visual hierarchy, focus states, theming, and accessibility must be specified as functional requirements.

The paste bar must implement the visual design contract in Section 12. The design must keep item cards stable, scannable, and type-distinct while preserving keyboard focus visibility, readable metadata, and responsive behavior on different screen sizes.

### REQ-022: Preserve existing Maccy workflows

Scope: integration
Rationale: The paste bar is additive and must not regress current Maccy behavior.

The existing popup, status item click behavior, `FloatingPanel<ContentView>`, vertical list, `HistoryListView`, `HeaderView`, `FooterView`, preview slideout behavior, `KeyboardShortcuts.Name.popup`, and existing shortcut default must continue to work unless the user explicitly opens the paste bar.

## 10. Technical Contracts

This spec defines concrete Maccy-facing contracts. Names are stable for this specification, but implementation may use local Swift names that preserve the same responsibilities.

### PasteBarHistoryItemAdapter

Scope: `HistoryItemDecorator`/`HistoryItem` to visual timeline

The paste bar item contract is a read-only adapter over existing Maccy objects, not a persisted model.

Required fields:

- `id`: `HistoryItemDecorator.id`
- `source`: `HistoryItemDecorator`
- `item`: wrapped `HistoryItem`
- `displayKind`: computed `PasteBarDisplayKind`
- `summary`: `HistoryItemDecorator.title`
- `copiedAt`: `HistoryItem.lastCopiedAt`
- `firstCopiedAt`: `HistoryItem.firstCopiedAt`
- `numberOfCopies`: `HistoryItem.numberOfCopies`
- `sourceAppName`: `HistoryItemDecorator.application`
- `sourceAppIcon`: `HistoryItemDecorator.applicationImage`
- `isPinned`: `HistoryItemDecorator.isPinned`
- `previewText`: `HistoryItemDecorator.text`
- `previewImage`: existing thumbnail/preview image cache when available
- `fileURLs`: `HistoryItem.fileURLs`
- `metadata`: computed card metadata values
- `availableActions`: Maccy-backed action identifiers

### PasteBarDisplayKind

Scope: paste bar classifier to visual timeline/search

Initial values:

- `multipleFiles`
- `folder`
- `pdf`
- `image`
- `archive`
- `file`
- `color`
- `link`
- `emailAddress`
- `phoneNumber`
- `table`
- `html`
- `code`
- `richText`
- `emoji`
- `plainText`
- `unknown`

Future values require capture support or safe derivation from stored data. They must not require SwiftData schema changes unless a separate migration spec is approved.

### PasteBarFilter

Scope: paste bar result provider to visual timeline

Required fields:

- `id`: stable opaque filter identifier
- `label`: visible name
- `kind`: one of `all`, `pinned`, `unpinned`, `contentType`, `sourceApp`
- `displayKind`: optional `PasteBarDisplayKind` for content-type filters
- `sourceAppBundleIdentifier`: optional bundle id for source app filters
- `sourceAppName`: optional source app label
- `icon`: optional app or content-type icon
- `itemCount`: optional visible count after active paste-bar filtering

### PasteBarSelection

Scope: paste bar selection/navigation

Required fields:

- `focusedItemId`: optional `HistoryItemDecorator.id`
- `selectedItemIds`: ordered item ids; v1 contains at most one item
- `activeFilterId`: selected paste-bar filter id
- `searchQuery`: paste-bar-local query string, initialized from or explicitly committed to `History.searchQuery` without mutating existing popup results while the paste bar is open
- `isSearchFocused`: boolean
- `previewedItemId`: optional item id for paste-bar-local expanded preview state

`PasteBarSelection` must not be represented by `NavigationManager.selection` in v1.

### PasteBarAction

Scope: paste bar action dispatcher

Initial action identifiers:

- `copy`
- `paste`
- `pasteWithoutFormatting`
- `preview`
- `delete`
- `pin`
- `unpin`

Actions must call existing Maccy services where possible through paste-bar-specific wrappers that control side effects, feedback, permission checks, and close timing. They must not call `History.select`.

### PasteBarActionResult

Scope: paste bar action dispatcher to visual timeline

Required values:

- `completedAndClose`: action succeeded and the paste bar should close.
- `completedKeepOpen(message: String?)`: action succeeded and the paste bar should remain open with optional feedback.
- `copiedFallback(message: String)`: direct paste was unavailable, item was copied, and the user must paste manually.
- `failed(message: String)`: action failed and the paste bar must remain recoverable.
- `itemRemoved(nextFocusedItemId: UUID?)`: item was deleted or became unavailable and focus must move to the provided item if present.

### AccessibilityTrustChecking

Scope: paste bar action dispatcher

Required API:

- `isTrusted`: boolean permission status.

The production implementation must return `Accessibility.isTrusted`. Tests must be able to inject trusted and untrusted implementations.

### PasteBarClipboardWriting

Scope: paste bar action dispatcher

Required API:

- `copy(item: HistoryItem, removeFormatting: Bool) -> Result<Void, Error>`

The production implementation must be backed by Maccy's existing clipboard-copy behavior, but it must expose an observable result to the paste-bar dispatcher. Maccy's current `Clipboard.copy(_:, removeFormatting:)` returns `Void` and ignores pasteboard write return values, so the implementation plan must either add a result-returning wrapper around the pasteboard writes or change `Clipboard.copy` to return a result without breaking existing callers. Tests must inject success and failure clipboard writers.

## 11. Data Model

The paste bar must not add persisted SwiftData fields for v1. It reads the existing data model:

- `HistoryItem`: one logical clipboard entry with timestamps, copy count, optional pin, source app bundle id, title, and contents.
- `HistoryItemContent`: one stored pasteboard type/value pair.
- `HistoryItemDecorator`: UI-facing adapter with title, app display data, selection state, shortcut data, text preview, image thumbnail/preview cache, and pin state.

The paste bar may add computed adapter types, computed classifier functions, lightweight in-memory view state, and defaults for paste-bar placement. It must not add a storage migration.

### Content Detection Heuristics

The initial `PasteBarDisplayKind` catalog must be ordered from more specific classifiers to broader fallbacks. Classifiers must read only Maccy's stored history data, which has already passed capture-time filtering. The first high-confidence match wins; if multiple classifiers produce equal confidence, the earliest catalog entry wins.

- `multipleFiles`: Match multiple stored `.fileURL` values; render stacked file/folder preview, file count, representative icons, total size when cheaply available, and safe common path prefix.
- `folder`: Match a single copied directory URL or directory file type derived from `.fileURL`; render folder icon, folder name, safe path, and item count when cheap to compute.
- `pdf`: Match PDF file URL extension/UTType or PDF-like stored data if Maccy later captures it; render PDF icon/thumbnail and file metadata.
- `image`: Match stored `.png`, `.tiff`, existing image projections, or image file URL extension/UTType; render thumbnail, dimensions when available, and file format.
- `archive`: Match archive file extensions or UTTypes such as ZIP, TAR, GZIP, RAR, and 7Z derived from `.fileURL`; render archive icon, filename, size, and safe path.
- `file`: Match one file URL that is not better classified as folder, PDF, image, or archive; render file icon, filename, safe path, size, and extension.
- `color`: Match CSS/system color strings, hex color patterns, or single-color image payloads when safely detectable; render swatch and normalized color value.
- `link`: Match URL-like stored string or HTML source URL when safely detectable; render URL host, title when available from existing data, and safe URL preview text.
- `emailAddress`: Match text containing a single valid email address; render address and mail metadata.
- `phoneNumber`: Match text containing a single valid phone number; render normalized number and region when available.
- `table`: Match tab-separated, comma-separated, or HTML table structures in stored text/HTML; render row/column count and compact cell preview.
- `html`: Match stored `.html` that is not better classified as table, link, or code; render stripped title/snippet and source URL when present.
- `code`: Match stored text, HTML, or file URL metadata with strong code signals such as fenced code, language keywords, indentation structure, syntax-highlighted HTML, or source-code extension; render monospaced snippet and language label when confidently known.
- `richText`: Match stored `.rtf` or attributed HTML content that is not better classified as HTML/table/code; render formatted preview and plain-text fallback metadata.
- `emoji`: Match text composed primarily of one or more emoji scalars; render large emoji preview and count.
- `plainText`: Match stored `.string` data without stronger classifiers; render text excerpt, character count, line count, and whitespace markers when useful.
- `unknown`: Match any remaining stored item with representable pasteboard data; render generic card metadata and generic actions only.

### Search Provider Text

The paste bar must provide a computed searchable string for each visible adapter. It must include:

- `HistoryItemDecorator.title`
- display kind label
- source app name when known
- safe filename/path basename metadata
- URL host or safe URL summary
- type-specific metadata visible on the card

It must not include values that Maccy's existing capture-time policy would have ignored.

## 12. Visual Design Contract

The paste bar must be designed as a utility surface for rapid scanning, not as a landing page or full library manager.

### Container

- Default placement is bottom edge, horizontally centered on the active screen, floating above the active app.
- User-configurable placement must support bottom edge and top edge through `PasteBarPosition`.
- Top placement must respect menu bar, notch/safe-area, and active app content constraints.
- Bottom placement must avoid covering the Dock and must grow upward during content resizing.
- Default width should expose multiple full cards and a hint of additional horizontally scrollable content.
- The container must use Maccy's existing material/glass background approach where practical.
- The bar must avoid covering the active text insertion point when detectable.

### Layout

- The primary item area is a single horizontal timeline.
- Cards must use stable dimensions within a size class so metadata, hover states, and preview loading do not cause layout shift.
- The selected item must remain fully visible when navigating by keyboard.
- Overflow must be indicated by partial trailing/leading cards, scroll position, or equivalent affordance.
- Search and filters must be visible without opening a separate window.
- Utility controls such as settings, collapse, compact mode, and close must be visually secondary to card selection and paste actions.

### Card Anatomy

Each card must have consistent regions:

- Header: source app icon/name when known, display kind label, copied time, and optional quick shortcut number.
- Preview body: type-specific preview with visual priority over metadata.
- Footer: concise metadata such as character count, filename, path basename, URL host, size, item count, or classifier fallback label.
- Action affordance: context menu or more-actions affordance visible on hover/focus or consistently available through keyboard.

Long text, paths, URLs, and filenames must truncate gracefully without overlapping other regions. Preview body content must not hide header or footer metadata.

### Visual States

Cards and controls must distinguish:

- focused by keyboard
- selected
- hovered
- context-menu open
- disabled or unavailable
- loading preview
- failed preview/action

Keyboard focus and selection must use a strong visible outline or equivalent high-contrast treatment. Hover-only styling must not be the only way to identify the active item.

### Content Preview Style

- Text and rich text cards must prioritize the first meaningful lines and preserve enough whitespace cues to distinguish code, prose, and templates.
- Code cards must use monospaced typography and syntax/color cues only when available without harming contrast.
- Image and PDF cards must use aspect-fit previews and avoid destructive cropping.
- File, folder, archive, and multiple-file cards must emphasize icon, filename/count, and safe path/size metadata.
- Color cards must display a large swatch plus normalized value.
- Emoji cards must display emoji at large scale.
- Cards must not infer or expose content from pasteboard data that Maccy did not store.

### Theming And Motion

- Light and dark appearances must both be supported.
- Accent colors may identify selection, filters, or categories, but color must not be the only state indicator.
- Opening, closing, filtering, and selection movement may animate, but motion must be short, interruptible, and disabled or reduced when the system reduce-motion setting is active.

### Accessibility

- Every card must expose an accessibility label that includes display kind, summary, source app when known, copied time, and selection state.
- Every icon-only control must have an accessible name.
- Keyboard navigation order must match the visual order of cards and controls.
- The design must preserve readable contrast for text, focus outlines, disabled states, and unavailable states.

## 13. Integration Points

Maccy integration must use these existing components:

- `KeyboardShortcuts.Name`: add `pasteBar` defaulting to `Shift-Command-V`; do not change `popup`.
- `AppDelegate`: own or initialize the separate paste-bar panel/controller alongside the existing popup panel.
- `PasteBarPanel`: implement a paste-bar-specific AppKit panel or controller. It may reuse ideas from `FloatingPanel`, but it must use separate paste-bar size/position defaults and must not write `Defaults[.windowSize]`, `Defaults[.windowPosition]`, or `AppState.shared.preview`.
- `Defaults.Keys`: add paste-bar placement and any paste-bar-only view preference defaults; do not reuse `popupPosition` for top/bottom placement.
- `History`: provide visible items and actions; avoid duplicating storage queries.
- `HistoryItemDecorator`: serve as the primary display adapter source.
- `Search`: continue to execute search over paste-bar-local result sets; extend searchable content through a computed string/provider instead of a parallel index.
- `Clipboard`: provide the production backing for copy, paste, and paste-without-formatting writes through a paste-bar clipboard-writing adapter that reports success or failure.
- `PreviewItemView`: provide reusable preview rendering content where possible. Paste-bar preview presentation state must remain local to the paste bar and must not write `AppState.shared.preview`.
- `GeneralSettingsPane` and `AppearanceSettingsPane`: expose paste-bar shortcut and placement settings.

Concrete code implementation is out of scope for this spec, but the integration boundaries above are required for the implementation plan.

## 14. Error Semantics

Errors must leave the paste bar in a recoverable state.

- Failed direct paste: keep selected item copied to the clipboard, keep or briefly retain the bar, and show fallback feedback.
- Missing accessibility permission: determine permission through the new accessibility status contract before synthetic paste; show fallback copy feedback and leave manual paste possible.
- Failed copy: keep the bar open and show action failure feedback.
- Deleted/unavailable item: remove the card and move focus to the nearest visible item.
- Preview unavailable: show metadata-only preview.
- Paste without formatting unavailable: disable the action or explain normal-paste fallback.

## 15. Security And Policy

The paste bar must consume only stored Maccy history results and computed metadata. It must not independently reveal ignored, deleted, unavailable, or sensitive clipboard content.

Capture-time policy remains in `Clipboard`. Paste bar v1 must not add a separate secret/redacted-card filtering layer.

Future display-time privacy changes must be specified separately and must not delete stored items merely because UI policy hides them.

## 16. Observability And Operations

Developer telemetry/logging is not required for v1.

The paste bar must provide user-visible feedback for direct paste permission missing, copied fallback, no results, preview unavailable, paste failed, copy failed, and item unavailable or deleted.

## 17. Acceptance Criteria

### AC-001: Open and dismiss

Covers: REQ-001, REQ-002, REQ-019, REQ-022
Validation Signal: manual UI behavior

Given clipboard history exists, invoking the configured paste-bar shortcut shows the paste bar near the configured top or bottom edge of the active screen. On a fresh default configuration, `Shift-Command-V` opens the paste bar at the bottom edge. Pressing `Escape` dismisses the paste bar without changing clipboard contents. `Shift-Command-C` still opens the existing Maccy popup.

### AC-002: Visual timeline

Covers: REQ-002, REQ-003, REQ-004, REQ-005, REQ-020, REQ-021
Validation Signal: manual screenshot comparison

Cards render newest first by `lastCopiedAt` descending in a horizontal row in both top and bottom placements, regardless of Maccy's current vertical-popup `sortBy` or `pinTo` settings. Each visible card shows preview, copied time from `lastCopiedAt`, source app data when known, and type-specific metadata computed from existing Maccy history data.

### AC-003: Keyboard paste

Covers: REQ-006, REQ-009, REQ-016
Validation Signal: manual keyboard workflow

With an item focused, `Return` copies the selected item and direct-pastes into the previously active app when permission is available. Without permission, the item remains copied to clipboard and feedback is shown.

### AC-004: Paste without formatting

Covers: REQ-006, REQ-009
Validation Signal: manual keyboard workflow

With a text-compatible item focused, the paste-without-formatting shortcut uses Maccy's existing remove-formatting copy behavior and pastes or leaves the plain representation on the clipboard according to permission state.

### AC-005: Search

Covers: REQ-007
Validation Signal: unit tests and manual UI behavior

Typing while the paste bar is open filters cards live using paste-bar-local query state and `Search`. Search matches title, display kind label, source app name, and safe visible file/URL/type metadata. Sharing the visible query with `History.searchQuery` does not mutate existing popup results while the paste bar is open.

### AC-006: Filters

Covers: REQ-008
Validation Signal: unit tests and manual UI behavior

Selecting all, pinned, unpinned, source app, or content type filters changes the visible item set without closing the bar. Active filter state remains visible, and unsupported collection/favorite/pinboard concepts are not shown.

### AC-007: Context menu

Covers: REQ-010
Validation Signal: manual context menu review

Opening an item context menu exposes Copy, Paste, Paste Without Formatting, Preview, Delete, and Pin/Unpin when applicable. Future-only actions are absent unless backed by safe detected data.

### AC-008: Preview

Covers: REQ-005, REQ-011, REQ-020
Validation Signal: manual preview behavior

Opening expanded preview uses Maccy's existing preview data for text, rich text, image, file/PDF metadata, and unsupported metadata-only fallback. Quick Look is not required.

### AC-009: Empty states

Covers: REQ-013
Validation Signal: manual UI behavior

No history, no search results, and empty-filter states show distinct messages and keep dismissal/navigation behavior intact.

### AC-010: Privacy

Covers: REQ-014, REQ-017
Validation Signal: unit tests and manual policy review

Items excluded by Maccy's existing capture-time ignored app/type/regex policy do not appear in stored history or paste-bar results. The paste bar does not add a separate v1 secret/redacted filtering layer.

### AC-011: Single-selection v1

Covers: REQ-012
Validation Signal: manual selection behavior

Paste bar v1 selects only one item at a time and exposes no multi-select affordances while `AppState.multiSelectionEnabled` is false.

### AC-012: Failure feedback and diagnostics

Covers: REQ-015, REQ-018
Validation Signal: manual failure-state behavior

Missing direct-paste permission, copy failure, unavailable item data, unavailable preview, failed paste, and deleted selected item states all produce visible feedback and leave the paste bar recoverable.

### AC-013: Shortcut customization

Covers: REQ-019, REQ-022
Validation Signal: settings behavior and manual shortcut invocation

Changing the paste-bar shortcut replaces `Shift-Command-V` as the paste-bar invocation shortcut, persists across app restart, and opens the paste bar when pressed. Changing the paste-bar shortcut does not modify the existing popup shortcut.

### AC-014: Visual design contract

Covers: REQ-021
Validation Signal: visual QA and accessibility review

The paste bar matches the visual design contract, including stable horizontal card layout, visible keyboard focus, readable metadata, no card-region overlap, light/dark support, reduced-motion behavior, accessible icon controls, and no sensitive-content leakage from data Maccy did not store.

## 18. Test Requirements

### T-001: Manual screenshot comparison

Covers: AC-002, AC-014
Level: manual
Evidence: reference screenshot checklist passes

Compare the paste bar against reference screenshots for horizontal layout, card preview prominence, selected border, category/filter strip, search affordance, metadata density, and overflow behavior while preserving Maccy's visual language.

### T-002: Keyboard workflow test

Covers: AC-001, AC-003, AC-004, AC-005, AC-011, AC-013
Level: manual
Evidence: keyboard-only scenario completes

Run a keyboard-only scenario. Open the paste bar with `Shift-Command-V`, navigate with Left/Right, search by typing, paste with `Return`, reopen, paste without formatting, confirm single-selection behavior, dismiss with `Escape`, and verify `Shift-Command-C` still opens the existing popup.

### T-003: Display kind unit tests

Covers: AC-002, AC-008
Level: unit
Evidence: unit tests pass

Add or update unit tests for computed display kind classification using existing `HistoryItem` fixtures: plain text, rich text, HTML, code-like text, link, email address, phone number, image data, color string, file URL, folder URL, PDF file URL, archive file URL, multiple file URLs, emoji, table-like text, and unknown fallback.

### T-004: Paste-bar ordering tests

Covers: AC-002
Level: unit
Evidence: unit tests pass

Add unit tests verifying paste-bar result ordering applies `lastCopiedAt` descending after filters/search and does not inherit Maccy's vertical-popup `sortBy` or `pinTo` ordering. Include cases where Maccy is configured to sort by `firstCopiedAt`, sort by `numberOfCopies`, pin to top, and pin to bottom.

### T-005: Search provider tests

Covers: AC-005
Level: unit
Evidence: unit tests pass

Add or update unit tests verifying paste-bar search provider text matches title, display kind label, source app name, safe file metadata, URL host/summary, and visible type metadata without replacing `Search`.

### T-006: Permission fallback test

Covers: AC-003, AC-010, AC-012
Level: manual
Evidence: fallback behavior checklist passes

Disable direct paste permission, select an item, invoke paste, and verify the item is copied to clipboard while the paste bar shows fallback feedback and sensitive/ignored items remain hidden.

### T-007: Visual design QA

Covers: AC-014
Level: manual
Evidence: visual QA checklist passes in light mode, dark mode, reduced motion, and keyboard-only navigation

Verify top and bottom placement, placement-aware resizing, card anatomy, text truncation, selected/focused/hover/disabled/loading/error states, contrast, icon labels, horizontal overflow, and responsive behavior across small and large displays.

### T-008: Integration regression test

Covers: AC-001, AC-013
Level: manual
Evidence: existing popup workflow still works

Verify the existing Maccy popup opens with `KeyboardShortcuts.Name.popup`, status item click behavior still toggles the popup, vertical list navigation still works, and existing popup settings remain unchanged.

### T-009: Action dispatcher unit tests

Covers: AC-003, AC-004, AC-012
Level: unit
Evidence: unit tests pass

Add unit tests for paste-bar action dispatch using injectable trusted/untrusted `AccessibilityTrustChecking` implementations and success/failure `PasteBarClipboardWriting` implementations. Verify trusted paste copies then calls direct paste, untrusted paste copies and returns `copiedFallback`, paste without formatting uses remove-formatting copy behavior, copy-writer failure returns `failed`, and delete/pin actions return result values that let paste-bar-local result state refresh without using `History.select`.

## 19. Decisions

### ADR-001: Core scope is paste bar only

Status: accepted
Blocking: no
Context: the user chose paste bar core as the requested specification scope.
Decision: Specify the paste bar core only.
Rationale: This captures the requested surface while deferring broader clipboard-manager features.

Options:

- Specify the paste bar core only.
- Specify the full competitor clipboard-manager model.
- Specify a lean MVP only.

### ADR-002: Use a horizontal visual timeline

Status: accepted
Blocking: no
Context: the provided screenshots and Paste documentation emphasize visual horizontal browsing.
Decision: Use a horizontal visual timeline as the paste bar model.
Rationale: Reference products prioritize visual recognition over dense list scanning in the paste bar context.

Options:

- Horizontal visual timeline.
- Vertical list.
- Grid-first main window.

### ADR-003: Treat paste without formatting as first-class

Status: accepted
Blocking: no
Context: both reference products surface plain-text paste as a common item action, and Maccy already supports remove-formatting copy behavior.
Decision: Expose paste without formatting through keyboard and context menu interactions.
Rationale: This reuses existing Maccy behavior and supports a frequent clipboard-manager workflow.

Options:

- Hide paste without formatting in settings only.
- Expose paste without formatting in keyboard and context menu interactions.

### ADR-004: Use Maccy-backed filters only

Status: accepted
Blocking: no
Context: Maccy has pins, source app metadata, and pasteboard type data, but not collections, favorites, or pinboards.
Decision: Let the paste bar display and switch all, pinned, unpinned, source app, and content-type filters.
Rationale: This keeps v1 aligned with existing data and avoids inventing unsupported grouping concepts.

Options:

- Include competitor-style collection/pinboard management.
- Use Maccy-backed filters only.

### ADR-005: Add the paste bar as a separate surface

Status: accepted
Blocking: no
Context: the user chose a separate surface during Maccy integration review.
Decision: Add the paste bar alongside the existing popup instead of replacing or mode-switching the popup.
Rationale: This minimizes risk and preserves current Maccy workflows.

Options:

- Separate paste bar surface.
- Replace the existing popup.
- Add a single popup mode toggle.

### ADR-006: Use adapters over existing Maccy data

Status: accepted
Blocking: no
Context: Maccy already exposes history display data through `HistoryItemDecorator` over `HistoryItem`.
Decision: Represent paste-bar items as read-only adapters over existing Maccy objects.
Rationale: This avoids storage migrations and keeps the feature close to current data ownership.

Options:

- Add new persisted paste-bar item fields.
- Use read-only adapters over `HistoryItemDecorator` and `HistoryItem`.

### ADR-007: Add a separate paste-bar shortcut

Status: accepted
Blocking: no
Context: the user chose a new shortcut during Maccy integration review.
Decision: Add `KeyboardShortcuts.Name.pasteBar` defaulting to `Shift-Command-V` and leave `KeyboardShortcuts.Name.popup` unchanged.
Rationale: This gives paste bar direct access while preserving existing users' popup muscle memory.

Options:

- Add a new paste-bar shortcut.
- Reuse the popup shortcut.
- Change the existing popup shortcut default.

### ADR-008: Keep v1 single-selection

Status: accepted
Blocking: no
Context: Maccy's multi-selection and paste-stack infrastructure exists but is disabled.
Decision: Keep paste bar v1 single-selection.
Rationale: This matches current runtime behavior and avoids enabling broader paste-stack behavior inside a visual-surface spec.

Options:

- Enable multi-selection in paste bar v1.
- Keep paste bar v1 single-selection.

## 20. Documentation Impact

### DOC-001: Document paste bar usage

Covers: REQ-001, REQ-002, REQ-006, REQ-009, REQ-019, REQ-022
Target: user help

User documentation must explain opening the paste bar, customizing its separate shortcut, choosing top or bottom placement, navigating cards, searching, filtering, copying, pasting, paste without formatting, quick shortcut numbers, and dismissal.

### DOC-002: Document privacy and permission behavior

Covers: REQ-014, REQ-016, REQ-017
Target: user help

User documentation must explain direct paste permissions, copy fallback, ignored/private content behavior, and why some copied items may not appear in the paste bar because Maccy did not store them.

### DOC-003: Document visual and accessibility behavior

Covers: REQ-021, AC-014
Target: design documentation

Design documentation must describe paste bar layout, top and bottom placement behavior, card anatomy, visual states, theme behavior, motion behavior, and accessibility labels.

### DOC-004: Document implementation integration

Covers: REQ-005, REQ-007, REQ-008, REQ-020, REQ-022
Target: developer documentation

Developer documentation must describe the paste-bar adapter over `HistoryItemDecorator`, computed display kind classification, Maccy-backed filters, search provider text, and the rule that v1 adds no SwiftData migration.

## 21. Open Questions

N/A: No blocking questions. The user selected separate surface and separate paste-bar shortcut during Maccy integration review.

## 22. References

- PastePal product page: https://indiegoodies.com/pastepal
- Paste for Mac help: https://pasteapp.io/help/paste-on-mac
- PastePal Quick Mode: https://docs.indiegoodies.com/pastepal/Mac/features/quick-mode
- PastePal Command Number: https://docs.indiegoodies.com/pastepal/Mac/features/command-number
- Maccy architecture documentation: `docs/architecture.md`
- User-provided Paste and PastePal screenshots in this thread.
