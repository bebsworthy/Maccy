# Maccy Architecture

This document describes the current architecture of Maccy, a macOS menu bar clipboard manager written in Swift and SwiftUI.

## Overview

Maccy is a sandboxed macOS `LSUIElement` app. It does not present a normal application window at launch. Instead, it installs a status bar item, watches the system pasteboard, stores clipboard history, and shows a custom floating panel when the user activates the app.

The application is organized around a small set of singleton runtime services:

- `AppDelegate` owns application lifecycle, the status item, and the floating panel.
- `AppState` is the shared observable state container for UI workflows.
- `Clipboard` watches and writes `NSPasteboard` content.
- `History` owns clipboard history state and coordinates persistence.
- `Storage` owns the SwiftData model container.

The primary popup UI is SwiftUI hosted inside a custom `NSPanel` subclass rather than a normal SwiftUI scene. The paste bar is a second SwiftUI/AppKit panel surface for visual clipboard-history navigation.

## Project Shape

Primary targets:

- `Maccy`: the macOS application.
- `MaccyTests`: unit tests for clipboard handling, history, search, sorting, decorators, and models.
- `MaccyUITests`: UI automation tests for popup and clipboard workflows.

Important directories:

- `Maccy/`: application source.
- `Maccy/Views/`: SwiftUI views for the popup, list, footer, preview, and interaction wrappers.
- `Maccy/Observables/`: observable runtime state models used by the UI.
- `Maccy/Models/`: SwiftData models for stored clipboard history.
- `Maccy/Settings/`: SwiftUI settings panes.
- `Maccy/Intents/`: App Intents integration.
- `Maccy/Extensions/`: platform and dependency extensions.
- `MaccyTests/` and `MaccyUITests/`: test suites.

## Runtime Startup

The SwiftUI entry point is `MaccyApp`. Because the app is effectively sceneless, it creates a hidden `MenuBarExtra` and delegates the real startup work to `AppDelegate`.

Startup sequence:

1. `MaccyApp` installs `AppDelegate` through `@NSApplicationDelegateAdaptor`.
2. `applicationWillFinishLaunching` wires `AppState.shared.appDelegate`.
3. `Clipboard.shared` registers a hook that forwards new copies to `History.shared.add`.
4. `Clipboard.shared.start()` begins polling `NSPasteboard`.
5. Defaults observers keep clipboard polling, status item visibility, menu icon, and disabled state synchronized with settings.
6. `applicationDidFinishLaunching` migrates defaults, disables unused global hotkeys, and creates the `FloatingPanel<ContentView>` popup.
7. `AppDelegate` also creates `PasteBarPanel<PasteBarView>` and registers `KeyboardShortcuts.Name.pasteBar`, defaulting to Shift-Command-V.

The status bar item is created lazily by `AppDelegate`. Normal clicks toggle the popup. Option-click toggles event ignoring, and Option-Shift-click ignores only the next clipboard event.

## State Model

`AppState` is the root shared UI state object. It owns:

- `popup`: popup sizing, keyboard activation mode, and hotkey event monitoring.
- `history`: clipboard history and search state.
- `footer`: footer command items.
- `navigator`: current selection, keyboard navigation, scrolling, and multi-selection state.
- `preview`: slideout preview state, placement, sizing, and auto-open behavior.

SwiftUI views receive `AppState` through the environment from `ContentView`.

`History` is also observable. It maintains two history collections:

- `all`: every loaded history item, regardless of current search visibility.
- `items`: the currently visible items after search filtering.

This split lets search change the displayed list without discarding the full loaded history.

The paste bar reads `History.all` through computed adapters and keeps its own local selection, active filter, expanded-preview state, and feedback state. It does not use `NavigationManager`, `History.items`, or the popup preview controller. While the paste bar is open, its local search text is mirrored to `History.searchQuery` without running popup search side effects; when the paste bar closes, the query is committed through the normal `History.searchQuery` path so the shared search field remains consistent.

## Clipboard Data Flow

Maccy uses polling rather than pasteboard notifications. `Clipboard` stores the current `NSPasteboard.changeCount` and checks for changes on a repeating timer controlled by the `clipboardCheckInterval` default.

Copy ingestion flow:

1. Timer calls `Clipboard.checkForChangesInPasteboard`.
2. If `changeCount` is unchanged, nothing happens.
3. External copies interrupt any active paste stack.
4. Global ignore mode can drop the event, optionally resetting after one copy.
5. Pasteboard types are filtered against enabled, disabled, ignored, transient, dynamic, and known application-specific types.
6. Source application bundle ID is checked against ignored app settings.
7. Empty plain strings are ignored unless accompanied by rich text.
8. Remaining pasteboard item data is converted into `[HistoryItemContent]`.
9. A `HistoryItem` is created, assigned source app and title, and delivered to registered hooks.
10. The default hook calls `History.add`.

Copy selection flow:

1. User selects a `HistoryItemDecorator`.
2. `History.select` determines the action from current modifier flags.
3. `Clipboard.copy` writes the item contents back to `NSPasteboard`.
4. If paste is requested by settings or modifier action, `Clipboard.paste` synthesizes the paste key chord with `CGEvent`.

Maccy writes marker pasteboard types such as `.fromMaccy` and `.source` when restoring an item, allowing later clipboard checks to distinguish internal copies from external copies.

## History and Persistence

`Storage` creates a SwiftData `ModelContainer` for `HistoryItem`.

Default storage:

- URL: `Application Support/Maccy/Storage.sqlite`
- Main context: `Storage.shared.context`

Test storage:

- When the app is launched with `enable-testing` in debug builds, storage is in-memory.

The data model is centered on:

- `HistoryItem`: one logical clipboard entry, including timestamps, copy count, optional pin, source app, title, and contents.
- `HistoryItemContent`: one pasteboard type/value pair belonging to a history item.

`History.add` handles:

- Duplicate detection and replacement.
- Preserving pin, title, first-copy timestamp, copy count, and source app when appropriate.
- History size limits for unpinned items.
- Sorting by last copied, first copied, or number of copies.
- Pin placement at top or bottom.
- Shortcut assignment for visible and pinned items.

On macOS 14, newly created `HistoryItem`s are inserted into SwiftData immediately after creation in `Clipboard`. On newer systems, insertion happens in `History.add`.

## UI Architecture

The popup UI is hosted inside `FloatingPanel<ContentView>`, an `NSPanel` subclass configured as a non-activating, floating, resizable panel at status bar level.

`FloatingPanel` is responsible for:

- Opening, closing, and toggling the popup.
- Positioning the popup near the cursor, saved position, active screen, or status item.
- Persisting popup size and position through `Defaults`.
- Resizing the panel as content height changes.
- Coordinating preview slideout placement and resizing.
- Closing on focus loss unless an alert is open.

`ContentView` composes the popup:

- background visual effect or glass effect depending on OS availability
- `KeyHandlingView` for keyboard input routing
- `HeaderView`
- `HistoryListView`
- `FooterView`
- `SlideoutView` and `SlideoutContentView` for previews

Selection and keyboard navigation are centralized in `NavigationManager`. Views update selection through it instead of owning selection independently.

### Paste Bar UI

The paste bar is hosted in `PasteBarPanel<PasteBarView>`, a separate non-activating `NSPanel` owned by `AppDelegate`. It is independent from `FloatingPanel<ContentView>` so opening, closing, focus behavior, resizing, and placement do not interfere with the existing popup.

`PasteBarPanel` is responsible for:

- capturing the frontmost application before the panel opens
- positioning the panel at the configured top or bottom screen edge through `PasteBarPosition`
- closing on focus loss, Escape, outside click, or successful direct-paste actions
- preserving the target application long enough for direct paste restoration

`PasteBarView` composes the visual clipboard timeline:

- local search field and filter chips
- horizontally scrolling cards rendered by `PasteBarCardView`
- local `PasteBarSelection` for current and previewed items
- expanded preview overlay using `PreviewItemView`
- feedback and empty-state surfaces
- keyboard routing for left/right navigation, up/down aliases, Return, Shift-Return, Delete, pin/unpin, preview, Escape, Command-F, and Command-1 through Command-9 quick paste

Paste bar action handling is delegated to `PasteBarActionDispatcher`. The dispatcher copies through `Clipboard`, reuses `History.deleteFromPasteBar` and `History.togglePinFromPasteBar`, and restores the captured target before direct paste. If target restoration or direct paste is unavailable, the selected item is copied and the paste bar remains open to show fallback feedback.

## Search and Sorting

Search is implemented by `Search`.

Supported modes:

- exact, case-insensitive string matching
- fuzzy search using Fuse
- regular expression matching
- mixed mode, which tries exact, then regexp, then fuzzy

`History.searchQuery` throttles search updates to avoid excessive recomputation while typing. Search results update `History.items`, then navigation highlights the first appropriate item and requests popup resize.

Sorting is implemented by `Sorter` and controlled by defaults. Sorting first applies the selected sort strategy and then applies pin placement.

The paste bar uses `PasteBarResultProvider` for local filtering and searching over `History.all`. It reuses the existing `Search` implementation and a computed searchable string from `PasteBarHistoryItemAdapter` instead of creating a separate search index. Filters are computed from existing Maccy data: all history, pinned, unpinned, source applications, and `PasteBarDisplayKind` groups.

`PasteBarDisplayKind` is computed, not persisted. It classifies Maccy's stored pasteboard data and refinements such as file, folder, PDF, archive, image, rich text, HTML, color-like text, URL, email address, phone number, table-like text, code-like text, emoji, plain text, and unknown fallback. Adding new display kinds should be done by extending this classifier and the card rendering path, without changing the SwiftData model unless Maccy starts capturing new pasteboard types.

## Settings and Defaults

User preferences are stored with the `Defaults` package. Keys are declared in `Defaults.Keys+Names.swift`.

Settings cover:

- clipboard polling interval
- enabled pasteboard types
- ignored apps, pasteboard types, and regexps
- history size and clear behavior
- paste behavior and formatting behavior
- popup size, position, search visibility, and preview width
- paste bar shortcut and top/bottom placement
- menu bar icon behavior
- pin placement and sorting

Settings UI is created lazily in `AppState.openPreferences` using the `Settings` package. Each pane is a SwiftUI view under `Maccy/Settings/`.

Defaults observers are used throughout the app to keep long-lived runtime objects synchronized with settings changes.

## App Intents

The `Maccy/Intents/` module exposes clipboard history operations through App Intents.

Available intents include:

- get an item from history
- select an item
- clear history
- delete an item

The intents operate against `AppState.shared.history` and `AppState.shared.navigator`. `HistoryItemAppEntity` converts stored clipboard content into values App Intents can return, including text, HTML, rich text, image files, and file URLs.

## External Dependencies

Maccy uses Swift Package Manager dependencies through the Xcode project:

- `Defaults`: typed user defaults.
- `KeyboardShortcuts`: global keyboard shortcut registration.
- `Settings`: preferences window infrastructure.
- `Sparkle`: app updates.
- `LaunchAtLogin`: login item integration.
- `Fuse`: fuzzy search.
- `Sauce`: keyboard layout and key code handling.
- `SwiftHEXColors`: color parsing.
- `swift-log`: logging.

## Build and Test Notes

Typical local build:

```sh
xcodebuild build -project Maccy.xcodeproj -scheme Maccy -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

Unit tests:

```sh
xcodebuild test -project Maccy.xcodeproj -scheme Maccy -destination 'platform=macOS' -only-testing:MaccyTests CODE_SIGNING_ALLOWED=NO
```

The test plan uses `retryOnFailure`, so one logical failure can appear multiple times in raw `xcodebuild` output.

Some clipboard tests depend on the current frontmost application bundle ID because `Clipboard` uses `NSWorkspace.shared.frontmostApplication` as the source app. These tests can behave differently outside the expected foreground app environment.

UI tests launch the app with `enable-testing` and exercise menu bar, popup, and clipboard interactions. They may require a foreground desktop session and appropriate macOS automation/accessibility permissions.

Linting:

```sh
swiftlint lint --quiet
```

## Architectural Tradeoffs

- Clipboard monitoring is timer-based. This is simple and robust across pasteboard producers, but it means responsiveness and energy use depend on the polling interval.
- The app uses shared singletons for runtime services. This matches a small menu bar utility and keeps AppKit/SwiftUI bridging straightforward, but it makes isolated testing harder.
- The popup is an AppKit `NSPanel` hosting SwiftUI. This gives precise control over menu bar behavior, focus, floating level, and sizing, while keeping most UI implementation in SwiftUI.
- SwiftData stores pasteboard entries as typed content records. This keeps multi-type clipboard entries intact, but model operations must account for OS-specific SwiftData behavior.
