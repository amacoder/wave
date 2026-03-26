---
phase: 04-app-exclusion
plan: 02
subsystem: exclusion-ui
tags: [swift, swiftui, form, list, searchable, nsmetadataquery, togglestyle, environmentobject]
dependency_graph:
  requires: [AppExclusionService, InstalledApp, shouldSuppressHotkey, startInstalledAppsQuery]
  provides: [ExclusionSettingsTab, SettingsTab.exclusion]
  affects: [FlowSpeech/Views/SettingsView.swift]
tech_stack:
  added: []
  patterns:
    - SwiftUI Form with .formStyle(.grouped) matching all other settings tabs
    - .searchable modifier on List for real-time app filtering
    - Binding-based checkbox toggle that directly mutates @Published Set<String> in service
    - @EnvironmentObject propagation of AppExclusionService through SettingsView into ExclusionSettingsTab
    - Dynamic window height via selectedTab == .exclusion ? 520 : 400 ternary in .frame
key_files:
  created:
    - FlowSpeech/Views/ExclusionSettingsTab.swift
  modified:
    - FlowSpeech/Views/SettingsView.swift
    - FlowSpeech.xcodeproj/project.pbxproj
decisions:
  - "ExclusionSettingsTab added to project.pbxproj manually (file reference A10000020000000000000017, build file A10000010000000000000017, Views group) — xcodebuild confirmed BUILD SUCCEEDED"
  - "Empty state shown only when search is non-empty and filteredApps is empty — avoids flash during NSMetadataQuery population"
metrics:
  duration: 1 min
  completed: "2026-03-26"
  tasks: 1
  files_changed: 3
---

# Phase 4 Plan 02: ExclusionSettingsTab UI Summary

**One-liner:** ExclusionSettingsTab SwiftUI view with grouped Form, auto-suppress fullscreen toggle, NSMetadataQuery-backed searchable installed-apps List with 24x24 icons and native checkboxes — wired as a new tab in SettingsView with dynamic 520pt window height.

## What Was Built

### Task 1 — ExclusionSettingsTab.swift (new file) + SettingsView.swift (modified)

**`FlowSpeech/Views/ExclusionSettingsTab.swift`** — new file, 68 lines:

- `@EnvironmentObject var exclusionService: AppExclusionService` — consumes the service from Plan 01
- `filteredApps` computed property — `localizedCaseInsensitiveContains` filter on `installedApps`
- **Section 1 — Automatic Suppression:** `Toggle("Auto-suppress in fullscreen apps", isOn: $exclusionService.autoSuppressFullscreen)` with `.caption` footer text per UI-SPEC copywriting contract
- **Section 2 — Excluded Apps:** `List(filteredApps)` with 24x24 `NSImage` icons (`.accessibilityHidden(true)`), `Text(app.name)`, `Spacer()`, and inline `Toggle` with `.toggleStyle(.checkbox).labelsHidden()`
- `.searchable(text: $searchText, prompt: "Search apps...")` on the List
- `.frame(minHeight: 200)` on the List
- Empty state (`Text("No Apps Found")` + body copy) shown when search is non-empty and results are empty
- `.formStyle(.grouped)` matching all other settings tabs
- `.onAppear { exclusionService.startInstalledAppsQuery() }` triggers NSMetadataQuery on tab open

**`FlowSpeech/Views/SettingsView.swift`** — four targeted edits:

1. `@EnvironmentObject var exclusionService: AppExclusionService` property added after `appState`
2. `case exclusion = "Exclusion"` added to `SettingsTab` enum between `.api` and `.about`
3. `ExclusionSettingsTab()` tab added with `Label("Exclusion", systemImage: "hand.raised")` before About tab
4. `.frame(width: 500, height: selectedTab == .exclusion ? 520 : 400)` — dynamic height
5. `.environmentObject(exclusionService)` chained on the TabView
6. `#Preview` updated to include `.environmentObject(AppExclusionService())`

**`FlowSpeech.xcodeproj/project.pbxproj`** — three additions to register the new file:
- PBXBuildFile entry for `ExclusionSettingsTab.swift in Sources`
- PBXFileReference entry for `ExclusionSettingsTab.swift`
- File added to the Views PBXGroup children

Commit: `b93a74e`

## Verification

- `xcodebuild build -scheme FlowSpeech -destination 'platform=macOS'` returned **BUILD SUCCEEDED**
- All acceptance criteria confirmed (file exists, all required symbols present, build passes)

## Checkpoint Pending

Task 2 is a `checkpoint:human-verify` — the user must build and run the app to verify the Exclusion tab UI, installed-apps list, search filtering, checkbox persistence, and hotkey suppression behavior.

**How to verify:**
1. Build and run (Cmd+R in Xcode or via xcodebuild)
2. Open Settings > Exclusion tab — verify hand.raised icon appears
3. Verify window height expands for the Exclusion tab
4. Verify "Automatic Suppression" section with toggle defaulting to ON
5. Verify footer text: "Prevents hotkey activation in games and full-screen video players. Disable if you use fullscreen Xcode or Terminal."
6. Verify "Excluded Apps" section shows installed apps with icons and checkboxes
7. Type in search field — verify list filters in real time
8. Check an app, quit and relaunch — verify checkbox persists
9. Check an app, focus that app, hold hotkey — verify recording does NOT start
10. Uncheck the app, focus it, hold hotkey — verify recording DOES start
11. If League of Legends is installed, verify it appears pre-checked

## Deviations from Plan

None — plan executed exactly as written. Implementation matches the reference code in the plan action section and UI-SPEC contracts precisely.

## Self-Check: PASSED

- FlowSpeech/Views/ExclusionSettingsTab.swift: FOUND
- FlowSpeech/Views/SettingsView.swift: FOUND (modified)
- FlowSpeech.xcodeproj/project.pbxproj: FOUND (modified)
- Commit b93a74e (Task 1): FOUND
