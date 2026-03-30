---
phase: 05-companion-shell
plan: 01
subsystem: companion-window
tags: [swiftdata, swiftui, windowgroup, navigation, models]
dependency_graph:
  requires: []
  provides: [TranscriptionEntry-model, DictionaryWord-model, Snippet-model, ModelContainer, CompanionWindowView, SidebarView, EmptyStateView, WindowAccessor]
  affects: [FlowSpeechApp, AppDelegate]
tech_stack:
  added: [SwiftData]
  patterns: [WindowGroup-scene, NavigationSplitView, NSViewRepresentable-window-capture, SwiftData-ModelContainer-sharing]
key_files:
  created:
    - FlowSpeech/Models/TranscriptionEntry.swift
    - FlowSpeech/Models/DictionaryWord.swift
    - FlowSpeech/Models/Snippet.swift
    - FlowSpeech/Views/CompanionWindow/CompanionWindowView.swift
    - FlowSpeech/Views/CompanionWindow/SidebarView.swift
    - FlowSpeech/Views/CompanionWindow/HomeView.swift
    - FlowSpeech/Views/CompanionWindow/DictionaryView.swift
    - FlowSpeech/Views/CompanionWindow/SnippetsView.swift
    - FlowSpeech/Views/Shared/EmptyStateView.swift
    - FlowSpeech/Views/Shared/WindowAccessor.swift
  modified:
    - FlowSpeech/FlowSpeechApp.swift
    - FlowSpeech/AppDelegate.swift
    - FlowSpeech.xcodeproj/project.pbxproj
decisions:
  - "Single ModelContainer initialized in FlowSpeechApp.init() and shared with AppDelegate via @NSApplicationDelegateAdaptor — no second container anywhere"
  - "WindowGroup scene (not NSHostingView) for companion window — required for @Query to work in Phase 6"
  - "NSWindowDelegate extension on AppDelegate with windowShouldClose returning false + 0.1s delay for setActivationPolicy — hides window instead of destroying it"
  - "WindowAccessor NSViewRepresentable captures NSWindow and stores on AppDelegate with original delegate chaining"
  - "TranscriptionEntry includes v1.3 forward fields (audioFilePath, sourceAppBundleID) as optionals to avoid VersionedSchema migration"
metrics:
  duration_minutes: 4
  completed_date: "2026-03-30"
  tasks_completed: 2
  files_created: 10
  files_modified: 3
---

# Phase 5 Plan 1: Companion Shell Foundation Summary

**One-liner:** SwiftData models (TranscriptionEntry/DictionaryWord/Snippet) + single ModelContainer + WindowGroup companion scene with NavigationSplitView sidebar and amber-palette empty states.

## What Was Built

### Task 1: SwiftData Models + ModelContainer + WindowGroup

Three `@Model` classes created in `FlowSpeech/Models/`:

- **TranscriptionEntry** — id, rawText, cleanedText, timestamp, durationSeconds, wordCount, sourceAppName, plus v1.3 forward-compatible optional fields (audioFilePath, sourceAppBundleID)
- **DictionaryWord** — id, term, replacement (nil for vocab hints), isAbbreviation, createdAt
- **Snippet** — id, trigger, expansion, createdAt

`FlowSpeechApp` updated with:
- `import SwiftData` + `let modelContainer: ModelContainer` property
- `init()` that creates single `ModelContainer(for: TranscriptionEntry.self, DictionaryWord.self, Snippet.self)` with fatalError on failure
- Shares container with AppDelegate: `appDelegate.modelContainer = modelContainer`
- `WindowGroup(id: "companion")` scene with `.modelContainer(modelContainer)`, `.defaultSize(width: 800, height: 600)`, `.windowResizability(.contentMinSize)`

`AppDelegate` updated with:
- `var modelContainer: ModelContainer?`
- `var companionWindow: NSWindow?`
- `var originalWindowDelegate: NSWindowDelegate?`
- `import SwiftData`
- `NSWindowDelegate` extension with `windowShouldClose` that hides instead of closes (returns false, calls orderOut, then deferred setActivationPolicy(.accessory))

### Task 2: Companion Window Views

Seven new view files:

- **CompanionWindowView** — root `NavigationSplitView` with `SidebarView` (180pt column) and detail switching on selectedItem; uses `WindowAccessor` as background to capture NSWindow and assign delegate
- **SidebarView** — `List` with `.listStyle(.sidebar)`, `SidebarItem.allCases`, pinned gear button below Divider
- **SidebarItem** enum — home/dictionary/snippets with title and SF Symbol icon properties
- **HomeView** — `EmptyStateView(symbol: "waveform.and.mic", title: "No transcriptions yet", ...)`
- **DictionaryView** — `EmptyStateView(symbol: "character.book.closed", title: "Your dictionary is empty", ...)`
- **SnippetsView** — `EmptyStateView(symbol: "text.insert", title: "No snippets yet", ...)`
- **EmptyStateView** — reusable SF Symbol (48pt, vibrantBlue) + title (title2.bold, softBlueWhite) + body (secondary, max 280pt) with deepNavy background
- **WindowAccessor** — `NSViewRepresentable` using `DispatchQueue.main.async { view.window }` pattern

All files registered in `project.pbxproj` with new groups: `Models`, `CompanionWindow` (subgroup of Views), `Shared` (subgroup of Views).

## Decisions Made

- **Single ModelContainer pattern:** Initialized in `FlowSpeechApp.init()` and passed to AppDelegate via `appDelegate.modelContainer = modelContainer`. The `@NSApplicationDelegateAdaptor` ensures AppDelegate exists before App.init() body runs, making this assignment safe.
- **WindowGroup over NSHostingView:** Per RESEARCH.md locked decision — `@Query` macro silently returns empty arrays in NSHostingView; WindowGroup is the only supported scene for SwiftData.
- **NSWindowDelegate chaining:** WindowAccessor stores `window.delegate` as `originalWindowDelegate` before overriding with AppDelegate. `windowDidBecomeKey` and `windowDidResignKey` forwarded to original delegate to preserve SwiftUI internal tracking.
- **0.1s activation policy delay:** `setActivationPolicy(.accessory)` deferred 100ms on window close to prevent focus-stealing artifact in the previously active app (documented pattern per RESEARCH.md Pitfall 3).
- **v1.3 forward fields:** `audioFilePath` and `sourceAppBundleID` added as optional `String?` on TranscriptionEntry to avoid future VersionedSchema migration when audio recording is added.

## Deviations from Plan

None — plan executed exactly as written. The plan correctly anticipated the `appDelegate.modelContainer = modelContainer` assignment in init() working via the adaptor property wrapper. No architectural surprises encountered.

## Verification

- `xcodebuild` BUILD SUCCEEDED — no errors, no warnings
- All 12 new/modified files exist at specified paths
- `@Model` confirmed in all 3 model files via grep
- `WindowGroup` confirmed in FlowSpeechApp.swift
- `NavigationSplitView` confirmed in CompanionWindowView.swift
- No second `ModelContainer(for:` call exists anywhere (only in FlowSpeechApp.swift)
- No `NSHostingView` in CompanionWindow views

## Self-Check: PASSED

Files verified present:
- FlowSpeech/Models/TranscriptionEntry.swift: FOUND
- FlowSpeech/Models/DictionaryWord.swift: FOUND
- FlowSpeech/Models/Snippet.swift: FOUND
- FlowSpeech/Views/CompanionWindow/CompanionWindowView.swift: FOUND
- FlowSpeech/Views/CompanionWindow/SidebarView.swift: FOUND
- FlowSpeech/Views/CompanionWindow/HomeView.swift: FOUND
- FlowSpeech/Views/CompanionWindow/DictionaryView.swift: FOUND
- FlowSpeech/Views/CompanionWindow/SnippetsView.swift: FOUND
- FlowSpeech/Views/Shared/EmptyStateView.swift: FOUND
- FlowSpeech/Views/Shared/WindowAccessor.swift: FOUND

Commits verified:
- 17bf8ae: feat(05-01): create SwiftData models and wire ModelContainer into FlowSpeechApp
- 6cc4a75: feat(05-01): add companion window views — NavigationSplitView, sidebar, placeholders, WindowAccessor
