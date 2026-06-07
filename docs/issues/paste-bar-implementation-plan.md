# Plan: Paste Bar Implementation

artifact_type: plan
status: ready
plan_id: paste-bar-implementation-plan
last_updated: 2026-06-07
source_spec: paste-bar-functional-spec.md

## Summary

Implement the paste bar as an additive Maccy surface. The plan preserves the existing popup, storage model, `Shift-Command-C` shortcut, `FloatingPanel<ContentView>`, and vertical list workflow while adding paste-bar-specific invocation, panel placement, result adaptation, visual timeline UI, action dispatch, fallback feedback, settings, and tests.

## Assumptions

- The paste bar v1 is single-selection and does not enable Maccy's paste-stack UI.
- New Swift files may be grouped under `Maccy/PasteBar/` and added to `Maccy.xcodeproj`.
- The production paste-bar clipboard writer may either wrap current pasteboard writes with observable result handling or adjust `Clipboard.copy` to return a result without breaking existing callers.
- New settings strings should be added first in English; broader localization can follow the repository's normal translation workflow.
- Manual visual validation is acceptable for the transient AppKit panel and rich card layout because no screenshot test harness exists in the project.

## Dependencies And Ordering

Milestones are ordered to keep each change buildable and reviewable. `M-001` establishes invocation and panel boundaries, `M-002` adds computed data/query logic, `M-003` adds result-returning actions, `M-004` builds the user-facing surface, and `M-005` completes settings, docs, and regression validation.

## Risks

- The current `FloatingPanel` writes popup defaults and `AppState.shared.preview`; using it directly would regress popup behavior, so the paste bar needs its own panel/controller.
- `History.searchQuery`, `History.delete`, and `History.togglePin` currently mutate popup-visible state; paste-bar code must use local query state and side-effect-controlled mutation wrappers.
- `Clipboard.copy` currently returns `Void`; failure feedback depends on adding an observable clipboard-writing adapter.
- AppKit focus behavior for non-activating panels can be subtle, so keyboard-only and outside-click dismissal need manual validation.
- Rich card previews can become expensive; v1 should compute metadata lazily and avoid re-reading raw pasteboard content.

## Milestones

### M-001: Add paste-bar invocation and panel shell

Linked Spec: REQ-001, REQ-002, REQ-019, REQ-022, AC-001, AC-013

Goal:
Open and close an empty paste-bar panel from a separate customizable shortcut without touching the existing popup panel or status item behavior.

#### Tasks

- [ ] TASK-001: Add paste-bar shortcut and placement defaults
  - Evidence: `KeyboardShortcuts.Name.pasteBar` defaults to `Shift-Command-V`; new `PasteBarPosition` and `Defaults.Keys.pasteBarPosition` exist without changing `.popup`.

- [ ] TASK-002: Add `PasteBarPanel` and placement calculation
  - Evidence: a dedicated paste-bar AppKit panel/controller positions itself at the top or bottom active-screen edge and does not write `Defaults[.windowSize]`, `Defaults[.windowPosition]`, or `AppState.shared.preview`.

- [ ] TASK-003: Wire paste-bar controller into `AppDelegate`
  - Depends On: TASK-001, TASK-002
  - Evidence: `AppDelegate` owns the paste-bar controller alongside `panel: FloatingPanel<ContentView>` and toggles only the paste-bar panel for `.pasteBar`.

- [ ] TASK-004: Add a minimal `PasteBarView` shell
  - Depends On: TASK-002
  - Evidence: the panel renders a focusable SwiftUI shell with empty/loading content, escape dismissal, and no dependency on `ContentView`.

#### Validation

- [ ] VAL-001: Build the app
  - Evidence: `xcodebuild build -project Maccy.xcodeproj -scheme Maccy -destination 'platform=macOS'` passes.

- [ ] VAL-002: Verify shortcut isolation manually
  - Covers: T-002, T-008
  - Evidence: `Shift-Command-V` opens/dismisses the empty paste bar, `Shift-Command-C` still opens the existing popup, and status item click still toggles the popup.

#### Done When

- [ ] Paste-bar invocation is independently registered and customizable.
- [ ] The paste-bar panel opens at the configured top or bottom edge.
- [ ] The existing popup panel remains unchanged in manual validation.

### M-002: Build paste-bar data adapters, classifiers, filters, and search

Linked Spec: REQ-003, REQ-004, REQ-005, REQ-007, REQ-008, REQ-014, REQ-017, REQ-020, AC-002, AC-005, AC-006, AC-010
Depends On: M-001

Goal:
Produce paste-bar-ready card data from existing `History.all` without new SwiftData fields, popup search mutation, or popup sort leakage.

#### Tasks

- [ ] TASK-005: Generalize `Search` searchable input
  - Evidence: `Search` accepts a small searchable-text protocol or generic input; `HistoryItemDecorator` preserves title-only behavior and existing `SearchTests` still pass.

- [ ] TASK-006: Add paste-bar display contracts
  - Evidence: `PasteBarDisplayKind`, `PasteBarFilter`, `PasteBarHistoryItemAdapter`, and `PasteBarSelection` exist as computed/in-memory types with no SwiftData migration.

- [ ] TASK-007: Implement display-kind classification and metadata extraction
  - Depends On: TASK-006
  - Evidence: classifiers cover Maccy's stored `.fileURL`, `.html`, `.png`, `.rtf`, `.string`, `.tiff`, file refinements, link/text refinements, and `unknown` fallback using only stored history data.

- [ ] TASK-008: Implement paste-bar result provider
  - Depends On: TASK-005, TASK-006, TASK-007
  - Evidence: provider reads `History.all`, applies active filter and local query, sorts visible adapters by `HistoryItem.lastCopiedAt` descending, and does not mutate `History.items`, `History.searchQuery`, `AppState.shared.navigator`, or popup resize state.

- [ ] TASK-009: Add paste-bar filter generation
  - Depends On: TASK-008
  - Evidence: all, pinned, unpinned, source app, and display-kind filters are derived from visible stored history; collections/favorites/pinboards are absent.

#### Validation

- [ ] VAL-003: Run search and adapter unit tests
  - Covers: T-003, T-004, T-005
  - Evidence: `xcodebuild test -project Maccy.xcodeproj -scheme Maccy -testPlan Maccy -destination 'platform=macOS' -only-testing:MaccyTests/SearchTests -only-testing:MaccyTests/PasteBarDisplayKindTests -only-testing:MaccyTests/PasteBarResultProviderTests` passes.

- [ ] VAL-004: Review stored-history privacy boundary
  - Covers: AC-010
  - Evidence: paste-bar result code reads `History.all` and computed metadata only; it does not call raw pasteboard read APIs.

#### Done When

- [ ] Paste-bar adapters expose all card/search/filter data from existing Maccy history objects.
- [ ] Unit tests cover classification, ordering, search provider text, and filters.
- [ ] Existing `SearchTests` continue to pass after the searchable-input change.

### M-003: Add paste-bar action dispatcher and fallback seams

Linked Spec: REQ-009, REQ-010, REQ-015, REQ-016, AC-003, AC-004, AC-007, AC-012
Depends On: M-002

Goal:
Execute copy, paste, paste-without-formatting, delete, pin/unpin, and preview commands through paste-bar-specific result-returning actions without calling `History.select`.

#### Tasks

- [ ] TASK-010: Add accessibility trust status seam
  - Evidence: `Accessibility.isTrusted` exposes `AXIsProcessTrustedWithOptions(nil)` status, and `AccessibilityTrustChecking` can be injected in tests.

- [ ] TASK-011: Add paste-bar clipboard writer
  - Evidence: `PasteBarClipboardWriting.copy(item:removeFormatting:) -> Result<Void, Error>` reports success/failure and production writes through Maccy's clipboard-copy behavior.

- [ ] TASK-012: Add paste-bar action dispatcher
  - Depends On: TASK-010, TASK-011
  - Evidence: dispatcher returns `PasteBarActionResult`, checks trust before synthetic paste, supports copy/paste/plain-text paste, and leaves the bar recoverable on failure.

- [ ] TASK-013: Add side-effect-controlled history mutations
  - Depends On: TASK-012
  - Evidence: delete and pin/unpin update stored history and paste-bar-local results without clearing popup search, writing popup navigation, or requesting popup resize as part of paste-bar handling.

- [ ] TASK-014: Define context-menu action availability
  - Depends On: TASK-012, TASK-013
  - Evidence: availability covers Copy, Paste, Paste Without Formatting, Preview, Delete, and Pin/Unpin; future-only reveal/open-link actions are absent unless safe data exists.

#### Validation

- [ ] VAL-005: Run action dispatcher unit tests
  - Covers: T-009
  - Evidence: `xcodebuild test -project Maccy.xcodeproj -scheme Maccy -testPlan Maccy -destination 'platform=macOS' -only-testing:MaccyTests/PasteBarActionDispatcherTests` passes.

- [ ] VAL-006: Run clipboard regression tests
  - Evidence: `xcodebuild test -project Maccy.xcodeproj -scheme Maccy -testPlan Maccy -destination 'platform=macOS' -only-testing:MaccyTests/ClipboardTests -only-testing:MaccyTests/HistoryTests` passes.

#### Done When

- [ ] Paste-bar actions never call `History.select`.
- [ ] Missing accessibility permission returns copied-fallback behavior.
- [ ] Copy failure is testable through an injected failing clipboard writer.
- [ ] Delete and pin/unpin refresh paste-bar-local state without popup side effects.

### M-004: Build the visual timeline, navigation, preview, and feedback UI

Linked Spec: REQ-006, REQ-010, REQ-011, REQ-012, REQ-013, REQ-018, REQ-021, AC-007, AC-008, AC-009, AC-011, AC-014
Depends On: M-003

Goal:
Render the paste bar as a keyboard-first horizontal visual timeline with rich cards, local selection, search/filter controls, context menu, expanded preview, and recoverable feedback states.

#### Tasks

- [ ] TASK-015: Implement timeline and card views
  - Evidence: `PasteBarView` renders a horizontal scroll row of stable card dimensions with header, preview body, footer metadata, focus state, hover state, and quick shortcut labels.

- [ ] TASK-016: Implement keyboard and pointer navigation
  - Depends On: TASK-015
  - Evidence: local `PasteBarSelection` handles Left/Right, Up/Down aliases, Return, Shift-Return, Escape, mouse click, context-menu invocation, and selected-item visibility without writing `NavigationManager`.

- [ ] TASK-017: Implement search and filter controls
  - Depends On: TASK-015
  - Evidence: typing filters local results live, `Command-F` focuses search, filter chips update visible cards without closing the bar, and no collection/favorite UI is present.

- [ ] TASK-018: Implement card previews and expanded preview
  - Depends On: TASK-015
  - Evidence: text, rich text, HTML, code-like text, image, file/folder/PDF/archive, color, emoji, and unknown cards have graceful previews; expanded preview uses popup-independent local presentation state.

- [ ] TASK-019: Implement feedback and empty states
  - Depends On: TASK-012, TASK-015
  - Evidence: no history, no search results, empty filter, direct-paste fallback, copy failure, unavailable item, and preview unavailable states are visible and dismissible.

- [ ] TASK-020: Add accessibility labels and reduced-motion handling
  - Depends On: TASK-015
  - Evidence: cards and icon-only controls have accessible names; keyboard order follows visual order; animations honor reduce-motion.

#### Validation

- [ ] VAL-007: Run paste-bar UI unit tests where possible
  - Evidence: `xcodebuild test -project Maccy.xcodeproj -scheme Maccy -testPlan Maccy -destination 'platform=macOS' -only-testing:MaccyTests/PasteBarResultProviderTests -only-testing:MaccyTests/PasteBarActionDispatcherTests` passes after UI wiring.

- [ ] VAL-008: Manual visual design QA
  - Covers: T-001, T-006, T-007
  - Evidence: checklist passes for top/bottom placement, light/dark mode, reduced motion, keyboard-only navigation, horizontal overflow, card truncation, focus visibility, empty states, and failure feedback.

#### Done When

- [ ] Users can browse, search, filter, preview, and act on cards from the paste bar.
- [ ] The paste bar remains single-selection in v1.
- [ ] Visual and accessibility checks pass in manual QA.

### M-005: Expose settings, complete regression validation, and update docs

Linked Spec: REQ-019, REQ-021, REQ-022, AC-001, AC-013, AC-014
Depends On: M-004

Goal:
Make the feature configurable, verify it does not regress existing Maccy workflows, and document implementation details.

#### Tasks

- [ ] TASK-021: Add paste-bar shortcut setting
  - Evidence: `GeneralSettingsPane` includes a `KeyboardShortcuts.Recorder(for: .pasteBar)` with English strings and does not change `.popup` recorder behavior.

- [ ] TASK-022: Add paste-bar placement setting
  - Evidence: `AppearanceSettingsPane` exposes bottom/top `PasteBarPosition` with English strings and does not reuse `PopupPosition`.

- [ ] TASK-023: Update project membership and localized resource references
  - Evidence: new Swift files and English strings are included in `Maccy.xcodeproj`; build succeeds from a clean checkout.

- [ ] TASK-024: Update architecture documentation
  - Linked Spec: DOC-001, DOC-002, DOC-003, DOC-004
  - Evidence: docs describe paste-bar panel ownership, local search/action boundaries, settings, and known future extensions.

#### Validation

- [ ] VAL-009: Run full unit test plan
  - Evidence: `xcodebuild test -project Maccy.xcodeproj -scheme Maccy -testPlan Maccy -destination 'platform=macOS'` passes.

- [ ] VAL-010: Manual end-to-end workflow regression
  - Covers: T-002, T-008
  - Evidence: paste bar shortcut customization persists across restart; top/bottom placement works; existing popup shortcut, status item click, vertical navigation, preview slideout, and existing settings remain unchanged.

- [ ] VAL-011: Lint spec and plan artifacts
  - Trace Rationale: validates artifact readiness for the implementation docs, not an individual runtime requirement.
  - Evidence: `python3 /Users/boyd/.codex/plugins/cache/skills-marketplace/dev/0.1.0/scripts/pm.py artifact lint docs/issues/paste-bar-functional-spec.md --mode ready` and `python3 /Users/boyd/.codex/plugins/cache/skills-marketplace/dev/0.1.0/scripts/pm.py artifact lint docs/issues/paste-bar-implementation-plan.md --mode ready` pass.

#### Done When

- [ ] Paste-bar shortcut and placement are user-configurable.
- [ ] Full tests and manual regression validation pass.
- [ ] Documentation reflects the implemented architecture and known v1 boundaries.

## Open Questions

N/A: no implementation-blocking questions remain for a ready v1 plan.

## Documentation Updates

Documentation work is tracked in `TASK-024`. If implementation discovers spec-level changes, update `docs/issues/paste-bar-functional-spec.md` in the same milestone and preserve ready lint status.

## Implementation Log

N/A: implementation has not started.
