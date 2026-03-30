---
phase: 05-companion-shell
verified: 2026-03-30T10:26:09Z
status: human_needed
score: 6/7 must-haves verified
human_verification:
  - test: "Open companion window via 'Open Wave' menu item, click the red close button, then click 'Open Wave' again"
    expected: "Window closes, dock icon disappears within ~100ms, then reopens when 'Open Wave' is clicked (via SwiftUI openWindow — slightly slower than hide/show but functionally equivalent)"
    why_human: "windowShouldClose returns true (window is destroyed, not hidden via orderOut). Reopen depends on the openCompanionWindow closure being populated from onAppear — if that closure was never captured (e.g., window closed before onAppear fired), reopening silently fails. Cannot verify closure capture timing programmatically."
  - test: "After closing the companion window, click the dock icon"
    expected: "Companion window reopens via applicationShouldHandleReopen -> openCompanion() -> openCompanionWindow?()"
    why_human: "openCompanionWindow? closure is populated by .captureOpenWindow modifier's onAppear. If window is closed before that fires, dock click will call an empty closure and do nothing. Needs runtime verification."
  - test: "Settings sidebar tab"
    expected: "Clicking 'Settings' in the sidebar shows CompanionSettingsView inline in the detail pane (not a separate window)"
    why_human: "Settings is now a sidebar tab (post-fix change) rather than opening the standalone SettingsView panel. Visual quality and functional correctness need human eyes."
---

# Phase 5: Companion Shell Verification Report

**Phase Goal:** The companion app shell exists: WindowGroup with NavigationSplitView, SwiftData ModelContainer, sidebar navigation (Home/Dictionary/Snippets), dock icon toggle, and window lifecycle (hide on close, reopen from menu/dock).
**Verified:** 2026-03-30T10:26:09Z
**Status:** human_needed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|---------|
| 1 | App compiles and runs with SwiftData ModelContainer initialized for all three model types | VERIFIED | xcodebuild BUILD SUCCEEDED; ModelContainer(for: TranscriptionEntry.self, DictionaryWord.self, Snippet.self) in FlowSpeechApp.init() |
| 2 | WindowGroup scene with id 'companion' is declared in FlowSpeechApp.body | VERIFIED | FlowSpeechApp.swift:31 `WindowGroup(id: "companion")` |
| 3 | Companion window shows NavigationSplitView with Home, Dictionary, and Snippets sidebar items | VERIFIED | CompanionWindowView.swift has NavigationSplitView; SidebarView.swift has SidebarItem enum with home/dictionary/snippets/settings cases; mainItems = [.home, .dictionary, .snippets] |
| 4 | Each tab shows a welcoming empty state placeholder with SF Symbol, title, and body text | VERIFIED | HomeView, DictionaryView, SnippetsView all use EmptyStateView with symbol/title/message. EmptyStateView renders 48pt SF Symbol + title2.bold + body text |
| 5 | ModelContainer is shared with AppDelegate — no second container created | VERIFIED | Single ModelContainer in FlowSpeechApp.init(); appDelegate.modelContainer = modelContainer; no second ModelContainer(for: call anywhere |
| 6 | Dock icon appears/disappears with companion window; menu bar has 'Open Wave' item | VERIFIED | enableDockIcon()/disableDockIcon() use setActivationPolicy(.regular/.accessory); 100ms async delay on hide; 'Open Wave' is first menu item; applicationShouldHandleReopen calls openCompanion() |
| 7 | Red close button hides window instead of destroying it — reopening is instant | PARTIAL | windowShouldClose returns true (window destroyed, not hidden via orderOut). Reopen works via openCompanionWindow closure (SwiftUI openWindow), but requires the closure to have been captured. Not the same as instant hide/show but the goal of reopening is functionally achievable. |

**Score:** 6/7 truths verified (1 partial — window lifecycle changed from hide to close+reopen)

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `FlowSpeech/Models/TranscriptionEntry.swift` | @Model class with all fields | VERIFIED | Has @Model, all required fields including audioFilePath and sourceAppBundleID optionals |
| `FlowSpeech/Models/DictionaryWord.swift` | @Model class with id, term, replacement, isAbbreviation, createdAt | VERIFIED | Has @Model, all fields present |
| `FlowSpeech/Models/Snippet.swift` | @Model class with id, trigger, expansion, createdAt | VERIFIED | Has @Model, all fields present |
| `FlowSpeech/FlowSpeechApp.swift` | ModelContainer init + WindowGroup scene | VERIFIED | Has import SwiftData, let modelContainer, WindowGroup(id: "companion"), .modelContainer(modelContainer), .defaultSize(width: 800, height: 600) |
| `FlowSpeech/Views/CompanionWindow/CompanionWindowView.swift` | Root NavigationSplitView with sidebar and detail | VERIFIED | NavigationSplitView with SidebarView + detail Group switching on selectedItem; WindowAccessor wired as .background; CaptureOpenWindowModifier defined here |
| `FlowSpeech/Views/CompanionWindow/SidebarView.swift` | Sidebar List with SidebarItem enum | VERIFIED | SidebarItem enum has home/dictionary/snippets/settings; List with .listStyle(.sidebar); Settings pinned at bottom via .safeAreaInset |
| `FlowSpeech/Views/CompanionWindow/HomeView.swift` | Empty state placeholder | VERIFIED | EmptyStateView(symbol: "waveform.and.mic", title: "No transcriptions yet", ...) |
| `FlowSpeech/Views/CompanionWindow/DictionaryView.swift` | Empty state placeholder | VERIFIED | EmptyStateView(symbol: "character.book.closed", title: "Your dictionary is empty", ...) |
| `FlowSpeech/Views/CompanionWindow/SnippetsView.swift` | Empty state placeholder | VERIFIED | EmptyStateView(symbol: "sparkles", title: "No snippets yet", ...) |
| `FlowSpeech/Views/Shared/EmptyStateView.swift` | Reusable empty state with SF Symbol + title + message | VERIFIED | Exists with correct structure; note: uses .secondary foreground instead of DesignSystem.Colors.vibrantBlue/softBlueWhite/deepNavy — colors are system defaults (post-fix simplification) |
| `FlowSpeech/Views/Shared/WindowAccessor.swift` | NSViewRepresentable capturing NSWindow | VERIFIED | NSViewRepresentable with DispatchQueue.main.async { view.window } pattern |
| `FlowSpeech/Views/CompanionWindow/CompanionSettingsView.swift` | Settings embedded as sidebar tab | VERIFIED | Exists as post-fix addition; Settings tab in SidebarItem navigates to CompanionSettingsView detail pane |
| `FlowSpeech/AppDelegate.swift` | Dock toggle, window lifecycle, menu bar item | VERIFIED | enableDockIcon, disableDockIcon, openCompanion, applicationShouldHandleReopen, NSWindowDelegate extension, "Open Wave" first menu item |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| FlowSpeechApp.swift | TranscriptionEntry/DictionaryWord/Snippet | ModelContainer(for:) | VERIFIED | Line 20-22: all three types in ModelContainer init |
| FlowSpeechApp.swift | CompanionWindowView | WindowGroup(id: "companion") content | VERIFIED | Line 31-36: WindowGroup wraps CompanionWindowView with .modelContainer, .captureOpenWindow |
| AppDelegate.swift | NSApp.setActivationPolicy | enableDockIcon/disableDockIcon | VERIFIED | Both methods exist and call setActivationPolicy(.regular/.accessory) |
| AppDelegate.swift | companionWindow | windowShouldClose returns false + orderOut | PARTIAL | windowShouldClose returns true (not false); uses close rather than orderOut/hide. Dock icon disable still fires. Reopen via openCompanionWindow? closure instead of makeKeyAndOrderFront |
| AppDelegate.swift | companionWindow | applicationShouldHandleReopen triggers openCompanion | VERIFIED | Line 492-495: applicationShouldHandleReopen calls openCompanion() |
| CompanionWindowView.swift | AppDelegate.openCompanionWindow | CaptureOpenWindowModifier captures openWindow env value | VERIFIED | captureOpenWindow modifier applied in FlowSpeechApp.swift:35; stores openWindow(id: "companion") closure on AppDelegate |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|---------|
| SHELL-01 | 05-01-PLAN.md | User can open a companion window with sidebar navigation (Home, Dictionary, Snippets) | SATISFIED | WindowGroup declared; CompanionWindowView with NavigationSplitView; SidebarView with home/dictionary/snippets items; "Open Wave" menu item triggers openCompanion() |
| SHELL-02 | 05-02-PLAN.md | App shows dock icon when companion window is open and hides it when closed | SATISFIED | enableDockIcon()/disableDockIcon() wired; dock toggling confirmed in AppDelegate; applicationShouldHandleReopen and windowWillClose both call disableDockIcon() |
| SHELL-03 | 05-01-PLAN.md | Companion window uses SwiftUI WindowGroup with SwiftData ModelContainer shared across app | SATISFIED | WindowGroup(id: "companion") confirmed; single ModelContainer in FlowSpeechApp.init() shared with AppDelegate; no second container; no NSHostingView for companion |

Note: REQUIREMENTS.md shows SHELL-01 and SHELL-03 as unchecked (`[ ]`) but the implementations are present and substantive. This is a tracking inconsistency in REQUIREMENTS.md, not a code gap.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| FlowSpeech/Views/Shared/EmptyStateView.swift | 19, 22 | Uses `.secondary` and no explicit background instead of DesignSystem.Colors.vibrantBlue/softBlueWhite/deepNavy | Warning | Visual: amber palette from spec not applied; colors use system defaults. Functional goal (empty states exist) achieved but design spec deviated. |
| FlowSpeech/AppDelegate.swift | 617 | `windowShouldClose` returns `true` (closes window) instead of `false` (hides via orderOut) | Warning | Behavior change from plan: "hide on close — reopening is instant" is no longer true. Reopen now recreates window via SwiftUI openWindow. First reopen after window close depends on openCompanionWindow closure being populated from a prior onAppear. |

### Human Verification Required

#### 1. Window Close and Reopen Cycle

**Test:** Launch app, click "Open Wave", wait for companion window to appear fully, then click the red close button. Wait 200ms for dock icon to disappear. Then click "Open Wave" from menu bar again.
**Expected:** Companion window reopens. If it does not reopen, the openCompanionWindow closure was never captured or was lost when the window closed.
**Why human:** The closure is stored on AppDelegate and populated via SwiftUI's `.onAppear` in `CaptureOpenWindowModifier`. There is a race: if the window is dismissed before `.onAppear` fires, the closure is nil. Cannot verify timing programmatically.

#### 2. Dock Icon Click After Close

**Test:** Close the companion window (red button). Observe dock icon disappears. Click the dock icon.
**Expected:** Companion window reopens via `applicationShouldHandleReopen` -> `openCompanion()` -> `openCompanionWindow?()`.
**Why human:** Same closure dependency as above. Also, `applicationShouldHandleReopen` returns `false` to prevent macOS auto-reopening, so if the closure fails, nothing opens.

#### 3. Settings Sidebar Tab

**Test:** Open companion window, click "Settings" at the bottom of the sidebar.
**Expected:** Settings UI appears in the detail pane inline (not a separate panel window). All settings tabs (General, API Key, etc.) should be accessible.
**Why human:** CompanionSettingsView is a post-fix addition that reuses SettingsView tab views. The @EnvironmentObject dependencies (AppState, AppExclusionService) are passed in FlowSpeechApp but visual quality, tab switching, and form functionality need eyes.

## Gaps Summary

No hard blockers preventing goal achievement. The phase delivers a working companion app shell. Two behavioral deviations from the original plan were intentionally applied as fixes:

1. **Window lifecycle changed from hide-on-close to close-and-reopen:** The plan specified `windowShouldClose` returning `false` with `orderOut` (hide). The actual implementation returns `true` (allow close) and reopens via SwiftUI's `openWindow(id: "companion")` environment action captured in a closure. This achieves the same user-facing goal but is not "instant" on reopen. Needs human verification that the closure-based reopen actually works in practice.

2. **EmptyStateView uses system colors instead of DesignSystem amber palette:** The spec called for vibrantBlue/softBlueWhite/deepNavy. The implementation uses `.secondary` and no explicit background. The empty states are functionally present but visually deviate from the Wave design system. This is a cosmetic gap, not a blocker.

3. **Settings is now a sidebar tab:** The original plan had gear opening the standalone `openSettings()` panel. The fix integrated settings as a `CompanionSettingsView` detail pane within the companion window itself. This is an improvement aligned with the companion-first vision.

---

_Verified: 2026-03-30T10:26:09Z_
_Verifier: Claude (gsd-verifier)_
