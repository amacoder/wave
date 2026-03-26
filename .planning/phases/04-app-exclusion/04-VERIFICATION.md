---
phase: 04-app-exclusion
verified: 2026-03-26T00:00:00Z
status: human_needed
score: 9/9 must-haves verified
re_verification: false
human_verification:
  - test: "Open Settings, navigate to Exclusion tab, verify window height expands to ~520pt"
    expected: "Tab appears with hand.raised icon; window grows taller than other tabs"
    why_human: "Dynamic .frame(height: selectedTab == .exclusion ? 520 : 400) cannot be measured programmatically without a running UI"
  - test: "Check an app checkbox, quit the app, relaunch, confirm checkbox is still checked"
    expected: "UserDefaults-persisted excludedBundleIDs restores the selection after cold relaunch"
    why_human: "UserDefaults round-trip through app relaunch requires live execution"
  - test: "Focus the excluded app, hold the configured hotkey, verify recording does NOT start (no overlay, no sound)"
    expected: "shouldSuppressHotkey() returns true; startRecording() silently returns without audio, overlay, or Tink sound"
    why_human: "Hotkey suppression path requires the running app responding to real hardware events"
  - test: "Uncheck the previously excluded app, focus it, hold hotkey, verify recording DOES start"
    expected: "Overlay appears, recording begins normally"
    why_human: "Toggle persistence and runtime suppression-gate state change need live execution"
  - test: "Open a fullscreen app (e.g., Finder full-screened via green button), hold hotkey, verify suppression"
    expected: "When auto-suppress toggle is ON, recording is suppressed for the fullscreen app"
    why_human: "CGWindowListCopyWindowInfo geometry detection requires live windows on real display"
  - test: "Disable the auto-suppress toggle, open a fullscreen app, hold hotkey, verify recording DOES start"
    expected: "autoSuppressFullscreen=false short-circuits the fullscreen check; recording proceeds"
    why_human: "Toggle state affecting runtime suppression logic requires live execution"
  - test: "Type a partial app name in the search field, verify list filters in real time"
    expected: "filteredApps updates and the List re-renders showing only matching apps"
    why_human: "Real-time UI filtering requires the running SwiftUI app"
---

# Phase 4: App Exclusion Verification Report

**Phase Goal:** Users can explicitly exclude apps from triggering dictation, and the hotkey is automatically suppressed when a fullscreen or borderless-windowed app is focused
**Verified:** 2026-03-26
**Status:** human_needed (all automated checks passed; runtime behavior needs live confirmation)
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | AppExclusionService exists and owns the exclusion set, installed-apps query, and fullscreen detection | VERIFIED | `FlowSpeech/Services/AppExclusionService.swift` exists, 169 lines, contains all three subsystems |
| 2 | Holding the hotkey while a manually excluded app is frontmost does not start recording | VERIFIED (automated) / needs human (runtime) | `shouldSuppressHotkey()` checks `excludedBundleIDs.contains(bundleID)` and returns true; guard fires before audio, overlay, or sound |
| 3 | Holding the hotkey while a fullscreen/borderless app is focused does not start recording when auto-suppress is enabled | VERIFIED (automated) / needs human (runtime) | `frontmostAppIsFullscreenOrBorderless()` implemented with CGWindowListCopyWindowInfo + kCGWindowOwnerPID + 99%/95% geometry tolerance; wired through `shouldSuppressHotkey()` |
| 4 | Excluded bundle IDs persist across app restarts via UserDefaults | VERIFIED | `excludedBundleIDs` has `didSet { persist() }` and `persist()` calls `UserDefaults.standard.set(Array(excludedBundleIDs), forKey: "excludedBundleIDs")`; `init()` reloads via `stringArray(forKey: "excludedBundleIDs")` |
| 5 | Default exclusion list seeds on first launch with League of Legends bundle IDs | VERIFIED | `defaultExcludedBundleIDs` contains both `com.riotgames.LeagueofLegends` and `com.riotgames.LeagueofLegends.LeagueClientUx`; `init()` seeds only when `UserDefaults.standard.object(forKey: "excludedBundleIDs") == nil` |
| 6 | User can open Settings and see an Exclusion tab | VERIFIED | `SettingsView.swift` has `case exclusion = "Exclusion"` in `SettingsTab` enum; `ExclusionSettingsTab()` in TabView with `Label("Exclusion", systemImage: "hand.raised")` |
| 7 | Exclusion tab shows a searchable list of installed apps with icons and checkboxes | VERIFIED | `ExclusionSettingsTab.swift` has `List(filteredApps)`, `Image(nsImage: app.icon)` at 24x24, `.toggleStyle(.checkbox)`, `.searchable(text: $searchText, prompt: "Search apps...")` |
| 8 | User can toggle app exclusion via checkboxes and changes persist immediately | VERIFIED | Toggle `Binding` directly mutates `exclusionService.excludedBundleIDs`; `didSet { persist() }` fires synchronously |
| 9 | User can toggle auto-suppress fullscreen apps on/off | VERIFIED | `Toggle("Auto-suppress in fullscreen apps", isOn: $exclusionService.autoSuppressFullscreen)` bound to `@Published var autoSuppressFullscreen` with `didSet` UserDefaults write |

**Score:** 9/9 truths verified by static analysis

---

## Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `FlowSpeech/Services/AppExclusionService.swift` | Exclusion service with NSMetadataQuery, shouldSuppressHotkey(), fullscreen detection | VERIFIED | 169 lines; all required symbols present; no stubs |
| `FlowSpeech/AppDelegate.swift` | Suppression guard in startRecording() and exclusionService instance | VERIFIED | `let exclusionService = AppExclusionService()` at line 23; guard at lines 148–151 |
| `FlowSpeech/Views/ExclusionSettingsTab.swift` | Exclusion settings UI with app list, search, checkboxes, auto-suppress toggle | VERIFIED | 72 lines; all acceptance criteria symbols present; not a stub |
| `FlowSpeech/Views/SettingsView.swift` | Updated SettingsView with .exclusion tab case and dynamic window height | VERIFIED | `case exclusion = "Exclusion"` line 25; `ExclusionSettingsTab()` line 47; dynamic height line 56 |

---

## Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `FlowSpeech/AppDelegate.swift` | `FlowSpeech/Services/AppExclusionService.swift` | `exclusionService.shouldSuppressHotkey()` guard in `startRecording()` | WIRED | Lines 148–151: guard fires before any audio/overlay/sound code |
| `FlowSpeech/Services/AppExclusionService.swift` | UserDefaults | `persist()` writes `excludedBundleIDs`; `init()` reads via `stringArray(forKey:)` | WIRED | `persist()` at line 166; init reads at line 59 |
| `FlowSpeech/Views/ExclusionSettingsTab.swift` | `FlowSpeech/Services/AppExclusionService.swift` | `@EnvironmentObject var exclusionService: AppExclusionService` | WIRED | Line 11 in ExclusionSettingsTab; `exclusionService` used throughout body |
| `FlowSpeech/Views/SettingsView.swift` | `FlowSpeech/Views/ExclusionSettingsTab.swift` | `ExclusionSettingsTab()` in TabView | WIRED | Line 47; `.environmentObject(exclusionService)` propagated via TabView on line 58 |
| `FlowSpeech/AppDelegate.swift` | `FlowSpeech/Views/SettingsView.swift` | `.environmentObject(exclusionService)` in `openSettings()` | WIRED | Line 363: chained on SettingsView before window creation |

---

## Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| EXCL-01 | 04-01-PLAN, 04-02-PLAN | User can select apps to exclude from an installed apps picker (no manual bundle ID entry) | SATISFIED | NSMetadataQuery populates `installedApps`; ExclusionSettingsTab shows checkboxes with app icons; no text field for bundle IDs anywhere |
| EXCL-02 | 04-01-PLAN | Hotkey is auto-suppressed when frontmost app is in fullscreen or borderless-windowed mode | SATISFIED | `frontmostAppIsFullscreenOrBorderless()` uses CGWindowListCopyWindowInfo with 2pt exact and 99%/95% near-coverage geometry check; controlled by `autoSuppressFullscreen` toggle |
| EXCL-03 | 04-02-PLAN | Settings includes an Exclusion tab with installed apps list, search, and checkboxes | SATISFIED | ExclusionSettingsTab has `List(filteredApps)`, `.searchable`, `.toggleStyle(.checkbox)` — all three specified elements present |

No orphaned requirements: all Phase 4 requirements (EXCL-01, EXCL-02, EXCL-03) are claimed by plans and have implementation evidence.

---

## Anti-Patterns Found

None. Scanned all four modified files for TODOs, FIXMEs, placeholder comments, empty returns, and console-log-only implementations. Zero hits.

---

## Commit Verification

All commits documented in SUMMARY files confirmed real and in history:

| Commit | Summary Claim | Confirmed |
|--------|--------------|-----------|
| `baae0ac` | Create AppExclusionService | Yes — present in `git log` |
| `f3478db` | Wire suppression guard into AppDelegate | Yes — present in `git log` |
| `b93a74e` | Create ExclusionSettingsTab + SettingsView edits | Yes — present in `git log` |

---

## Human Verification Required

Phase 04 Plan 02 included a blocking `checkpoint:human-verify` task that was approved by the user on 2026-03-26 (documented in 04-02-SUMMARY.md). The approval covered visual appearance, app list population, search, persistence, and hotkey suppression. The items below are retained as a formal record for this verification report.

### 1. Exclusion Tab Window Height Expansion

**Test:** Open Settings, click the Exclusion tab
**Expected:** Window height grows visibly compared to other tabs (~520pt vs 400pt)
**Why human:** `.frame(height: selectedTab == .exclusion ? 520 : 400)` is a runtime SwiftUI layout; cannot measure pixel height from static analysis

### 2. Exclusion Persistence Across Relaunch

**Test:** Check an app in the Exclusion tab, quit and relaunch, verify checkbox is still checked
**Expected:** UserDefaults survives cold relaunch; `init()` restores the saved `excludedBundleIDs` Set
**Why human:** UserDefaults round-trip through process termination and restart requires live execution

### 3. Manual Exclusion Hotkey Suppression

**Test:** Exclude an app (e.g. Safari), focus it, hold the hotkey
**Expected:** No recording overlay appears, no Tink sound plays — silent suppression
**Why human:** Global hotkey event dispatch and `startRecording()` guard path require running hardware event loop

### 4. Manual Exclusion Suppression Reversal

**Test:** Uncheck the previously excluded app, focus it, hold hotkey
**Expected:** Recording overlay appears normally; transcription proceeds
**Why human:** State change at runtime affecting suppression gate requires live execution

### 5. Fullscreen Auto-Suppress

**Test:** Full-screen any app via green button, hold hotkey while auto-suppress is ON
**Expected:** Recording suppressed; no overlay, no sound
**Why human:** CGWindowListCopyWindowInfo geometry matching requires real windows on display

### 6. Auto-Suppress Toggle Disable

**Test:** Turn auto-suppress OFF in the Exclusion tab, full-screen an app, hold hotkey
**Expected:** Recording starts normally even though the app is fullscreen
**Why human:** Runtime toggle state affects the `shouldSuppressHotkey()` branch; requires live testing

### 7. Real-Time Search Filtering

**Test:** Type a partial app name in the search field
**Expected:** List narrows to matching app names with each keystroke
**Why human:** SwiftUI `.searchable` + `filteredApps` computed property update requires live UI

---

## Summary

All nine observable truths verified by static analysis. Every artifact exists, is substantive (no stubs), and is wired into the live call chain. All three requirements (EXCL-01, EXCL-02, EXCL-03) are fully satisfied. No anti-patterns detected. The three phase commits are confirmed in git history.

The `human_needed` status reflects that the core runtime behaviors — hotkey suppression firing, CGWindowListCopyWindowInfo geometry detection, UserDefaults persistence after cold relaunch, and SwiftUI UI rendering — cannot be confirmed without running the app. The Plan 02 blocking checkpoint was already approved by the user on 2026-03-26, providing prior human confirmation. These items are retained as formal verification completeness items.

---

_Verified: 2026-03-26_
_Verifier: Claude (gsd-verifier)_
