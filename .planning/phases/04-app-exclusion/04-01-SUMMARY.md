---
phase: 04-app-exclusion
plan: 01
subsystem: exclusion-service
tags: [swift, appkit, coregraphics, foundation, userdefaults, nsmetadataquery, cgwindowlist]
dependency_graph:
  requires: []
  provides: [AppExclusionService, InstalledApp, shouldSuppressHotkey, startInstalledAppsQuery]
  affects: [FlowSpeech/AppDelegate.swift, FlowSpeech/Views/SettingsView.swift]
tech_stack:
  added: []
  patterns:
    - ObservableObject service with @Published exclusion set and UserDefaults persistence
    - CGWindowListCopyWindowInfo with kCGWindowOwnerPID for geometry-based fullscreen detection
    - NSMetadataQuery with kMDItemContentType for Spotlight-based installed-apps discovery
    - Guard-chain pattern in startRecording() — phase check then suppression check
key_files:
  created:
    - FlowSpeech/Services/AppExclusionService.swift
  modified:
    - FlowSpeech/AppDelegate.swift
    - FlowSpeech.xcodeproj/project.pbxproj
decisions:
  - "Default seed list includes both League of Legends bundle IDs (com.riotgames.LeagueofLegends and LeagueClientUx) on first launch per STATE.md blocker resolution"
  - "kCGWindowOwnerPID used (not kCGWindowOwnerName) to avoid macOS 26 beta regression FB18327911"
  - "autoSuppressFullscreen defaults to true on first launch — consistent with EXCL-02 opt-in requirement"
metrics:
  duration: 2 min
  completed: "2026-03-26"
  tasks: 2
  files_changed: 3
---

# Phase 4 Plan 01: AppExclusionService Backend Summary

**One-liner:** AppExclusionService with manual bundle ID exclusion list, CGWindowListCopyWindowInfo fullscreen geometry detection, NSMetadataQuery installed-apps discovery, and UserDefaults persistence — wired as a silent suppression gate in AppDelegate.startRecording().

## What Was Built

### Task 1 — AppExclusionService.swift (new file)

`FlowSpeech/Services/AppExclusionService.swift` is an `ObservableObject` that owns all exclusion logic:

- **InstalledApp struct** — `Identifiable, Comparable` with id (bundle ID), name, icon; sorted by `localizedCaseInsensitiveCompare`
- **defaultExcludedBundleIDs** — static Set seeding `com.riotgames.LeagueofLegends` and `com.riotgames.LeagueofLegends.LeagueClientUx` on first launch
- **excludedBundleIDs** — `@Published Set<String>` with `didSet { persist() }` for automatic UserDefaults writes
- **autoSuppressFullscreen** — `@Published Bool` defaulting to `true`; persisted immediately on change
- **shouldSuppressHotkey()** — synchronous check: manual list first, then optional fullscreen geometry check
- **frontmostAppIsFullscreenOrBorderless(pid:)** — `CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)` filtered by `kCGWindowOwnerPID`; 2pt exact tolerance and 99%/95% near-coverage check
- **startInstalledAppsQuery()** — NSMetadataQuery on `/Applications` and `~/Applications` with `kMDItemContentType == 'com.apple.application-bundle'`
- **queryDidFinish(_:)** — stops query, builds InstalledApp array, dispatches sorted result to main
- **persist()** — `UserDefaults.standard.set(Array(excludedBundleIDs), forKey: "excludedBundleIDs")`

Commit: `baae0ac`

### Task 2 — AppDelegate.swift wiring

Three targeted changes to `FlowSpeech/AppDelegate.swift`:

1. `let exclusionService = AppExclusionService()` — property added alongside other services
2. Suppression guard in `startRecording()` as the second guard after `phase != .recording`:
   ```swift
   guard !exclusionService.shouldSuppressHotkey() else { return }
   ```
3. `.environmentObject(exclusionService)` chained on SettingsView in `openSettings()` so Plan 02's Exclusion tab can use `@EnvironmentObject var exclusionService: AppExclusionService`

Commit: `f3478db`

## Verification

- `xcodebuild build -scheme FlowSpeech -destination 'platform=macOS'` returned **BUILD SUCCEEDED** after both tasks
- All acceptance criteria confirmed: file exists, all required symbols present, UserDefaults persistence wired, CGWindowListCopyWindowInfo with kCGWindowOwnerPID

## Deviations from Plan

None — plan executed exactly as written. The reference implementation in RESEARCH.md Pattern 1 was followed faithfully with minor style preferences (explicit if/else for init rather than flatMap optional chain, which is functionally equivalent).

## Decisions Made

1. **kCGWindowOwnerPID over kCGWindowOwnerName** — avoids macOS 26 beta regression FB18327911 which affects status-item ownership attribution but not PID-based lookups. Per RESEARCH.md Pitfall 1.

2. **First-launch seed via `object(forKey:) == nil`** — matches the plan's exact specification; resolves STATE.md blocker about League of Legends bundle ID verification by including both IDs defensively.

3. **autoSuppressFullscreen default true** — aligns with EXCL-02 requirement that suppression is "enabled" by default; developers can disable in the Exclusion tab (Plan 02).

## Self-Check: PASSED

- FlowSpeech/Services/AppExclusionService.swift: FOUND
- FlowSpeech/AppDelegate.swift: FOUND
- Commit baae0ac (Task 1): FOUND
- Commit f3478db (Task 2): FOUND
