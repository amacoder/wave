# Architecture Research

**Domain:** macOS menu bar dictation app — v1.1 UI/feature milestone
**Researched:** 2026-03-26
**Confidence:** HIGH (codebase read directly; macOS API patterns verified against official docs)

---

## Current Architecture (Baseline)

The existing app has a clean service-oriented structure. Understanding what exists is the prerequisite for knowing what to add vs. modify.

```
┌─────────────────────────────────────────────────────────────────┐
│                        Entry Point                              │
│  FlowSpeechApp (@main) → @NSApplicationDelegateAdaptor          │
├─────────────────────────────────────────────────────────────────┤
│                        AppDelegate                              │
│  ┌───────────┐  ┌─────────────┐  ┌──────────────────────────┐  │
│  │ MenuBar   │  │ Hotkey      │  │ Recording Orchestration   │  │
│  │ Setup     │  │ NSEvent     │  │ start/stop/cancel/        │  │
│  │ statusItem│  │ flagsChanged│  │ transcribe + overlay mgmt │  │
│  └───────────┘  └─────────────┘  └──────────────────────────┘  │
├─────────────────────────────────────────────────────────────────┤
│                        Services                                 │
│  ┌───────────────┐  ┌───────────────┐  ┌───────────────────┐   │
│  │ AudioRecorder │  │ WhisperService│  │ TextInserter      │   │
│  │ AVFoundation  │  │ URLSession    │  │ NSPasteboard +    │   │
│  │ audio capture │  │ Whisper API   │  │ CGEvent Cmd+V     │   │
│  └───────────────┘  └───────────────┘  └───────────────────┘   │
│  ┌───────────────┐  ┌───────────────┐                           │
│  │ HotkeyManager │  │KeychainManager│                           │
│  │ CGEventTap    │  │ SecItem API   │                           │
│  └───────────────┘  └───────────────┘                           │
├─────────────────────────────────────────────────────────────────┤
│                        State                                    │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │ AppState: ObservableObject                              │    │
│  │ isRecording, isTranscribing, audioLevels, settings      │    │
│  └─────────────────────────────────────────────────────────┘    │
├─────────────────────────────────────────────────────────────────┤
│                        Views                                    │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐  │
│  │RecordingOver-│  │ SettingsView │  │ OnboardingView       │  │
│  │layView (NSW) │  │ TabView 5tab │  │ 5-step wizard        │  │
│  └──────────────┘  └──────────────┘  └──────────────────────┘  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │ MenuBarPopoverView                                       │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

---

## New Feature Integration Map

This answers the core question: what changes vs. what is added new.

### Feature 1: Flow Bar Overlay Redesign (UI Revamp)

**What changes:** `RecordingOverlayView` is a full redesign — same file, new implementation.

**What changes in AppDelegate:** The `showRecordingOverlay()` window positioning logic needs updating. Current position is `screenFrame.maxY - height - 100` (100px from top). The new "Flow Bar" should appear at the **bottom-center** of screen, approximately 40px from the bottom edge, matching Wispr Flow's pill position. This is a 2-line change in `AppDelegate.showRecordingOverlay()`.

**Window size:** Current is 200×80. Flow Bar pill is wider and shorter — approximately 340×56. The NSWindow `contentRect` in `showRecordingOverlay()` must match.

**New state needed in AppState:** A `recordingPhase` enum to drive state-machine animations.

```swift
enum RecordingPhase {
    case idle       // overlay hidden
    case recording  // mic active, waveform animating
    case transcribing // spinner, "Transcribing..."
    case done       // brief "Done" flash before hiding
}
```

`AppState.isRecording` + `AppState.isTranscribing` booleans already map to 3 of these phases; a `done` phase just needs a brief display window (0.8s) before `hideRecordingOverlay()` is called. This `done` flash replaces immediately hiding the overlay on transcription success.

**Integration point:** AppDelegate calls `hideRecordingOverlay()` immediately on transcription success today. Add a `showCompletionBriefly()` helper that sets `appState.recordingPhase = .done`, waits 0.8s via `DispatchQueue.main.asyncAfter`, then hides.

---

### Feature 2: App Exclusion (Game/Fullscreen Suppression)

**Where it lives:** `AppDelegate.handleFlagsChanged()` — the hotkey handler. This is the single right place: before calling `startRecording()`, check whether the frontmost app is excluded.

**API approach (MEDIUM confidence — verified against Apple docs):**

```swift
// Check frontmost app at hotkey-down moment
func isFrontmostAppExcluded() -> Bool {
    guard let app = NSWorkspace.shared.frontmostApplication else { return false }
    let bundleID = app.bundleIdentifier ?? ""
    let name = app.localizedName ?? ""
    // Check user exclusion list (bundle IDs stored in UserDefaults)
    let excludedIDs = UserDefaults.standard.stringArray(forKey: "excludedBundleIDs") ?? []
    if excludedIDs.contains(bundleID) { return true }
    // Auto-exclude fullscreen apps if setting enabled
    if appState.excludeFullscreenApps {
        return isAppFullscreen(app)
    }
    return false
}

func isAppFullscreen(_ app: NSRunningApplication) -> Bool {
    // CGWindowListCopyWindowInfo approach: check if any window of this app
    // fills the main screen completely (kCGWindowBounds matches screen bounds)
    let screenBounds = NSScreen.main?.frame ?? .zero
    let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    return windowList.contains { info in
        guard let ownerPID = info[kCGWindowOwnerPID as String] as? Int32,
              ownerPID == app.processIdentifier,
              let bounds = info[kCGWindowBounds as String] as? [String: CGFloat] else { return false }
        let w = bounds["Width"] ?? 0
        let h = bounds["Height"] ?? 0
        return w >= screenBounds.width && h >= screenBounds.height
    }
}
```

**Caveats:** CGWindowListCopyWindowInfo requires no special entitlements for window metadata (only screen recording permission is needed for content capture, not metadata). Window bounds check is a reliable proxy for fullscreen games — games that go exclusive fullscreen create a window exactly matching display dimensions.

**New AppState fields needed:**
```swift
@Published var excludedAppBundleIDs: [String] = []   // user's exclusion list
@Published var excludeFullscreenApps: Bool = true     // auto-exclude fullscreen
```

**New Settings tab:** Add an "Exclusions" tab to SettingsView (6th tab, or replace the sparse "About" tab with a combined About + Exclusions, or add it inline on General tab). Recommend: add as a 6th tab since SettingsView already uses TabView.

**No HotkeyManager changes needed.** The CGEventTap in HotkeyManager fires the callback regardless — the exclusion check happens in AppDelegate's callback, not in HotkeyManager itself. This keeps HotkeyManager focused on event detection only.

---

### Feature 3: Clipboard Persistence

**What changes:** `TextInserter.insertText()` — a 5-line change removing the restore block.

**Current flow:**
```
Save oldContent → Set transcription to clipboard → Cmd+V → Restore oldContent after 0.5s
```

**New flow:**
```
Save oldContent (optional — for user display only) → Set transcription to clipboard → Cmd+V → DO NOT restore
```

The clipboard restore DispatchQueue block at line 38-43 of TextInserter.swift is deleted outright. The transcription remains on the clipboard indefinitely (until the user copies something else), enabling manual Cmd+V if auto-insert failed or if no text field was focused.

**Edge case to handle:** If `autoInsertText` is OFF, the transcription should still be placed on the clipboard (so the user can paste manually). Current code only sets clipboard as a precursor to Cmd+V insertion. The clipboard-write step should be separated from the paste step.

**Revised TextInserter structure:**
```swift
func insertText(_ text: String) {
    // Always put text on clipboard (user can re-paste if needed)
    placeOnClipboard(text)

    guard appState would want to auto-insert else { return }
    clearModifierKeys()
    usleep(50000)
    simulatePaste()
    // No restore. Transcription persists on clipboard.
}

func placeOnClipboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}
```

**AppState integration:** `AppState.lastTranscription` already stores the transcription text for display in the menu bar popover. No new state needed for clipboard persistence — the NSPasteboard IS the persistence.

---

### Feature 4: Animation Polish

**What changes:** `RecordingOverlayView` internals only. No AppDelegate or service changes.

**Pattern:** Use SwiftUI `.transition()` + `withAnimation(.spring(duration: 0.4, bounce: 0.15))` for state phase transitions. The overlay window itself appears/disappears via `NSWindow.orderFront/orderOut` (AppKit calls from AppDelegate) — for the window-level appear/disappear animation, use `NSWindow.animator()` with alpha.

**Window appear animation:**
```swift
// In showRecordingOverlay():
recordingWindow?.alphaValue = 0
recordingWindow?.orderFront(nil)
NSAnimationContext.runAnimationGroup { context in
    context.duration = 0.25
    recordingWindow?.animator().alphaValue = 1.0
}

// In hideRecordingOverlay():
NSAnimationContext.runAnimationGroup({ context in
    context.duration = 0.2
    recordingWindow?.animator().alphaValue = 0.0
}) { [weak self] in
    self?.recordingWindow?.orderOut(nil)
    self?.recordingWindow?.alphaValue = 1.0 // reset for next show
}
```

**State transition animations inside the view:** Use `RecordingPhase` from AppState and SwiftUI's conditional rendering with `.transition(.opacity.combined(with: .scale(scale: 0.95)))`.

---

## Modified vs. New Component Summary

| Component | Action | Scope of Change |
|-----------|--------|-----------------|
| `AppDelegate.showRecordingOverlay()` | Modify | Window position (top → bottom), window size, alpha animation |
| `AppDelegate.handleFlagsChanged()` | Modify | Add exclusion check before `startRecording()` |
| `AppDelegate.transcribe()` | Modify | Replace `hideRecordingOverlay()` with `showCompletionBriefly()` |
| `AppState` | Modify | Add `recordingPhase`, `excludedAppBundleIDs`, `excludeFullscreenApps` |
| `TextInserter.insertText()` | Modify | Remove clipboard restore block; separate clipboard-write from paste |
| `RecordingOverlayView` | Redesign | Full blue palette redesign, pill shape, phase-driven animation |
| `SettingsView` | Modify | Add Exclusions tab (new tab or expand General tab) |
| `AppExclusionService` | New | Encapsulates `isFrontmostAppExcluded()` and `isAppFullscreen()` logic |
| `DesignSystem.swift` | New | Color constants, typography, shared style values for blue palette |

---

## Recommended File Structure Changes

```
FlowSpeech/
├── AppDelegate.swift            (modify — overlay positioning, exclusion check, done phase)
├── FlowSpeechApp.swift          (modify — add recordingPhase to AppState)
├── DesignSystem.swift           (NEW — color palette, spacing, typography constants)
├── Services/
│   ├── AudioRecorder.swift      (no change)
│   ├── WhisperService.swift     (no change)
│   ├── TextInserter.swift       (modify — remove clipboard restore)
│   ├── HotkeyManager.swift      (no change)
│   ├── KeychainManager.swift    (no change)
│   └── AppExclusionService.swift  (NEW — fullscreen detection + exclusion list logic)
└── Views/
    ├── RecordingOverlayView.swift  (redesign — new pill UI, phase animations)
    ├── SettingsView.swift          (modify — add Exclusions tab)
    ├── MenuBarPopoverView.swift    (modify — blue palette)
    ├── OnboardingView.swift        (modify — blue palette)
    └── ExclusionListView.swift     (NEW — UI for managing excluded apps)
```

---

## Data Flow

### Recording Flow (with new features)

```
User holds Fn key
    ↓
AppDelegate.handleFlagsChanged()
    ↓
AppExclusionService.isFrontmostAppExcluded()
    ├─ YES → return (hotkey suppressed, no recording)
    └─ NO  → startRecording()
                ↓
            AppState.recordingPhase = .recording
            showRecordingOverlay() [with alpha fade-in]
            AudioRecorder.startRecording()

User releases Fn key
    ↓
AppDelegate.stopRecordingAndTranscribe()
    ↓
AppState.recordingPhase = .transcribing
AudioRecorder.stopRecording() → audioURL
WhisperService.transcribe(audioURL) [async]
    ↓
TextInserter.placeOnClipboard(transcription)  ← clipboard persistence
TextInserter.simulatePaste()                   ← if autoInsert on
    ↓
AppState.recordingPhase = .done               ← new "done" flash
DispatchQueue.asyncAfter(0.8s) {
    hideRecordingOverlay() [with alpha fade-out]
    AppState.recordingPhase = .idle
}
```

### App Exclusion Data Flow

```
UserDefaults["excludedBundleIDs"] ← persisted list
    ↓ (loaded at startup)
AppState.excludedAppBundleIDs: [String]
    ↓ (read at hotkey-down)
AppExclusionService.isFrontmostAppExcluded()
    → NSWorkspace.shared.frontmostApplication
    → CGWindowListCopyWindowInfo (for fullscreen check)
    → returns Bool
```

---

## Architectural Patterns

### Pattern 1: Phase-Driven Overlay State Machine

**What:** Replace dual `isRecording` + `isTranscribing` booleans with a single `RecordingPhase` enum in AppState.

**When to use:** When a UI element needs to render different visual states that transition in a defined sequence (idle → recording → transcribing → done → idle).

**Trade-offs:**
- Pro: Single source of truth for all overlay rendering; eliminates impossible boolean combos (`isRecording=true` AND `isTranscribing=true`)
- Pro: Enables clean `switch` in SwiftUI view for phase-driven rendering
- Con: Requires updating all existing callers of `isRecording` and `isTranscribing` (only ~6 call sites in AppDelegate + SettingsView)

```swift
// AppState addition
@Published var recordingPhase: RecordingPhase = .idle

// RecordingOverlayView body
switch appState.recordingPhase {
case .idle: EmptyView()
case .recording: RecordingPillView(levels: appState.audioLevels)
case .transcribing: TranscribingPillView()
case .done: DonePillView(text: appState.lastTranscription ?? "Done")
}
```

The existing `isRecording` and `isTranscribing` booleans can remain for backward compatibility with SettingsView and menu bar icon code — derive them from `recordingPhase`:
```swift
var isRecording: Bool { recordingPhase == .recording }
var isTranscribing: Bool { recordingPhase == .transcribing }
```

### Pattern 2: Service Extraction for Exclusion Logic

**What:** Pull app exclusion logic into `AppExclusionService` rather than embedding it in AppDelegate.

**When to use:** When a concern has its own state (the exclusion list), its own persistence (UserDefaults), and its own macOS API calls (NSWorkspace, CGWindowListCopyWindowInfo).

**Trade-offs:**
- Pro: AppDelegate stays focused on orchestration; exclusion logic is testable in isolation
- Pro: ExclusionListView can be injected with `AppExclusionService` directly for live preview
- Con: One more object to pass around (minor at this app scale)

### Pattern 3: Separation of Clipboard-Write from Paste

**What:** TextInserter currently conflates "put text on clipboard" with "simulate paste." Split into two operations.

**When to use:** When the same data-write has multiple downstream consumers (clipboard persistence for manual re-paste vs. auto-paste for cursor insertion).

**Trade-offs:**
- Pro: Clipboard persistence falls out naturally — write always happens; paste is conditional
- Pro: If paste fails (no focused field), user can still manually Cmd+V the transcription
- Con: None — this is strictly a loosening of coupling

---

## Integration Points

### Internal Component Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| AppDelegate ↔ AppExclusionService | Direct method call | Synchronous check at hotkey-down; must be fast (<1ms) |
| AppDelegate ↔ RecordingOverlayView | Via AppState (ObservableObject) | No direct coupling; overlay reacts to `recordingPhase` |
| AppDelegate ↔ TextInserter | Direct method call | `insertText()` or `placeOnClipboard()` separately |
| ExclusionListView ↔ AppExclusionService | Shared reference or via AppState | View modifies `excludedBundleIDs` list |
| SettingsView ↔ AppState | @EnvironmentObject | Existing pattern, no change needed |

### External API Boundaries

| API | Used By | Notes |
|-----|---------|-------|
| `NSWorkspace.shared.frontmostApplication` | AppExclusionService | Returns `NSRunningApplication`; always available, no permission required |
| `CGWindowListCopyWindowInfo` | AppExclusionService | Returns window metadata; no screen recording permission required for bounds/owner only |
| `NSWorkspace.shared.runningApplications` | ExclusionListView | For "pick from running apps" exclusion UI |
| `NSPasteboard.general` | TextInserter | Existing usage; remove the restore block |
| `NSAnimationContext` | AppDelegate | Window alpha animation for overlay appear/disappear |

---

## Build Order (Dependency-Aware)

The four features have dependencies between them. Build in this order:

**Phase 1 — Foundation (no user-visible change)**
1. Add `DesignSystem.swift` with color constants (all other UI work depends on this)
2. Add `RecordingPhase` enum to AppState, derive `isRecording`/`isTranscribing` from it
3. Update AppDelegate to drive `recordingPhase` through all transitions

**Phase 2 — Clipboard Persistence (small, high-value, isolated)**
4. Modify `TextInserter.insertText()` to remove restore block and separate clipboard-write from paste
5. Verify: transcription stays on clipboard after successful paste; manual Cmd+V still works

**Phase 3 — Overlay Redesign + Animations**
6. Redesign `RecordingOverlayView` with blue palette, pill shape, phase-driven rendering
7. Update AppDelegate `showRecordingOverlay()` for bottom positioning and alpha fade animations
8. Add "done" flash phase with 0.8s auto-hide

**Phase 4 — App Exclusion**
9. Create `AppExclusionService.swift`
10. Add exclusion check to `AppDelegate.handleFlagsChanged()`
11. Add `ExclusionListView.swift` and wire into SettingsView as new tab

**Rationale for order:**
- DesignSystem first because both overlay redesign and settings updates reference the same colors
- RecordingPhase enum before overlay redesign because the view's structure depends on it
- Clipboard persistence is independent and low-risk; ship it early
- App exclusion last because it requires a new Settings tab (more UI surface) and the CGWindowListCopyWindowInfo path needs testing

---

## Anti-Patterns to Avoid

### Anti-Pattern 1: Fullscreen Detection via Accessibility Attributes

**What people do:** Use `AXUIElementCopyAttributeValue` with `kAXFullScreenAttribute` on the frontmost app's window to detect fullscreen mode.

**Why it's wrong:** Requires Accessibility permission, which the app already requests for text insertion. However, checking another app's AX attributes at high frequency (every hotkey event) is slower than CGWindowListCopyWindowInfo and has more edge cases with games that use exclusive fullscreen (not macOS Space fullscreen).

**Do this instead:** Use CGWindowListCopyWindowInfo with bounds comparison against `NSScreen.main.frame`. This is a pure CoreGraphics call, fast, and works for both Space-based fullscreen and exclusive fullscreen games.

### Anti-Pattern 2: Storing Exclusion List in AppState Instead of UserDefaults

**What people do:** Store `excludedBundleIDs: [String]` as a `@Published` var on AppState and persist it on every change via `saveSettings()`.

**Why it's wrong:** AppState.saveSettings() already handles multiple keys; the exclusion list is a separate concern and can grow large. More importantly, the exclusion check happens outside the main thread in the CGEventTap callback — reading from AppState requires main thread.

**Do this instead:** `AppExclusionService` reads directly from `UserDefaults` at hotkey-down time (UserDefaults is thread-safe for reads). Cache the result in a property that refreshes when the Settings view saves. This avoids any threading issues.

### Anti-Pattern 3: Animating RecordingPhase Transitions with Timer-Based Polling

**What people do:** Use `Timer.scheduledTimer` to poll `appState.recordingPhase` and trigger animations.

**Why it's wrong:** Unnecessary complexity. AppState is `@Published`; SwiftUI views automatically re-render on phase changes. Wrap phase changes in `withAnimation` at the AppDelegate call site.

**Do this instead:**
```swift
// AppDelegate — wrap phase changes in withAnimation
withAnimation(.spring(duration: 0.3, bounce: 0.1)) {
    appState.recordingPhase = .recording
}
```

### Anti-Pattern 4: Creating a New NSWindow Instance Each Time the Overlay Shows

**What current code does:** `recordingWindow` is lazily created on first `showRecordingOverlay()` call (correct), but the guard `if recordingWindow == nil` means the window is never re-created if it gets deallocated.

**Current code is already OK** — but when adding alpha animations, be careful to reset `alphaValue` back to 1.0 after the hide animation completes. If the window is hidden at `alphaValue = 0`, the next `orderFront()` call will show a transparent window.

---

## Scaling Considerations

This is a single-user local app; traditional scaling doesn't apply. The relevant "scaling" concern is:

| Concern | At 1 user (now) | If exclusion list grows large |
|---------|-----------------|------------------------------|
| Exclusion check latency | <0.1ms for 10 entries | Still <1ms for 1000 entries — Set lookup is O(1) |
| CGWindowListCopyWindowInfo | ~1-5ms per call | Only called when `excludeFullscreenApps` is true; acceptable |
| NSWindow for overlay | Single persistent window (correct) | No concern |

Use a `Set<String>` for the in-memory exclusion list lookup, not an `Array`, even though the stored format is an array.

---

## Sources

- [NSWorkspace.frontmostApplication — Apple Developer Documentation](https://developer.apple.com/documentation/appkit/nsworkspace/frontmostapplication)
- [CGWindowListCopyWindowInfo — Apple Developer Documentation](https://developer.apple.com/documentation/coregraphics/1455137-cgwindowlistcopywindowwindowinfo)
- [NSWindow.StyleMask.fullScreen — Apple Developer Documentation](https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct/fullscreen)
- [NSPasteboard — Apple Developer Documentation](https://developer.apple.com/documentation/appkit/nspasteboard)
- [Fullscreen Detection — Apple Developer Forums](https://developer.apple.com/forums/thread/792917)
- [Querying Running Applications in macOS (Gertrude App)](https://gertrude.app/blog/querying-running-applications-in-macos)
- Direct codebase analysis: AppDelegate.swift, TextInserter.swift, HotkeyManager.swift, RecordingOverlayView.swift, FlowSpeechApp.swift (all read 2026-03-26)

---

*Architecture research for: SpeechFlow v1.1 — UI revamp, app exclusion, clipboard persistence*
*Researched: 2026-03-26*
