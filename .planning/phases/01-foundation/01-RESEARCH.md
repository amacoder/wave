# Phase 1: Foundation - Research

**Researched:** 2026-03-26
**Domain:** SwiftUI macOS / AppKit — state modeling, design tokens, CGEventTap reliability, animation lifecycle
**Confidence:** HIGH (all findings derived from direct source-code inspection + Apple platform patterns)

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| FNDTN-01 | App uses a RecordingPhase enum (idle/recording/transcribing/done) instead of dual booleans | Codebase audit shows all 4 boolean sites; enum design and migration path documented below |
| FNDTN-02 | App has centralized blue design tokens (deep navy, vibrant blue, soft blue-white) | 14 hardcoded hex call sites identified; DesignSystem.swift pattern documented |
| FNDTN-03 | CGEventTap health is verified periodically and re-enabled if silently disabled | CGEventTap disable vector + `CGEvent.tapIsEnabled` + Timer pattern documented |
| FNDTN-04 | SwiftUI animations stop when overlay window is hidden | `NSWindow.isVisible` guard pattern + `.onChange(of:)` documented |
</phase_requirements>

---

## Summary

Phase 1 is a pure refactoring and hardening phase with zero net-new features. All four requirements touch the existing codebase in surgical ways: one data-model change (FNDTN-01), one file extraction (FNDTN-02), one health-check loop added to `HotkeyManager` (FNDTN-03), and one animation guard added to `RecordingOverlayView` (FNDTN-04).

The codebase is small (11 Swift files) and well-structured. The dual boolean pattern (`isRecording`/`isTranscribing`) currently lives in `AppState` (FlowSpeechApp.swift), with consumers in `AppDelegate`, `RecordingOverlayView`, `MenuBarPopoverView`, `CompactMenuBarView`, and the two status-view branches in `MenuBarPopoverView`. A `RecordingPhase` enum eliminates the impossible combined state (both true simultaneously) and prepares the ground for Phase 3's 4-state animated overlay.

The `Color(hex:)` extension currently lives in `SettingsView.swift` — a poor home for a shared utility. Fourteen call sites scatter the same two hex values (`2563EB`, `0D9488`) across four files. A `DesignSystem.swift` file centralises tokens and also needs to carry the three new palette values (deep navy, vibrant blue, soft blue-white) that the v1.1 design requires.

CGEventTap silent-disable is a real macOS behaviour: the OS kills the tap when the process loses Accessibility trust without being notified. The existing `HotkeyManager.start()` has no health-check loop. Adding a 2-second `Timer` that calls `CGEvent.tapIsEnabled(tap:)` and attempts re-enable (or updates a published `isTapHealthy` flag) fully satisfies FNDTN-03.

SwiftUI's `.repeatForever` animations continue to pump the render thread even when the hosting window is hidden. The fix is to pause animations in `.onAppear`/`.onDisappear` of the overlay's root view, or to observe `NSWindow.isVisible` via a Combine publisher and gate the animation state booleans.

**Primary recommendation:** Implement all four requirements as four focused tasks in sequence — they do not depend on each other and can be reviewed independently.

---

## Standard Stack

### Core (already in project — no new dependencies)

| Component | Version | Purpose | Notes |
|-----------|---------|---------|-------|
| SwiftUI | macOS 13+ | UI framework | Already used throughout |
| AppKit (NSWindow, NSStatusItem) | macOS 13+ | Menu bar, overlay window | Already used |
| CoreGraphics (CGEventTap) | macOS 10.4+ | Global event interception | Already in HotkeyManager |
| Foundation (Timer) | — | 2-second health-check loop | Standard library |
| Combine (via @Published) | — | State propagation to UI | Already used via ObservableObject |

### No New Dependencies Required

All four requirements are achievable with APIs already imported. Do not introduce new SPM packages for this phase.

---

## Architecture Patterns

### Recommended File Layout After Phase 1

```
FlowSpeech/
├── FlowSpeechApp.swift       # AppState with RecordingPhase enum (FNDTN-01)
├── AppDelegate.swift         # Uses phase enum, drives menu bar icon
├── DesignSystem.swift        # NEW: color tokens + Color(hex:) extension (FNDTN-02)
├── Services/
│   ├── HotkeyManager.swift   # + health-check timer + isTapHealthy flag (FNDTN-03)
│   ├── AudioRecorder.swift
│   ├── WhisperService.swift
│   ├── TextInserter.swift
│   └── KeychainManager.swift
└── Views/
    ├── RecordingOverlayView.swift  # + animation guard (FNDTN-04)
    ├── MenuBarPopoverView.swift
    ├── SettingsView.swift          # Color(hex:) extension removed (moved to DesignSystem)
    ├── OnboardingView.swift
    └── ...
```

---

### Pattern 1: RecordingPhase Enum (FNDTN-01)

**What:** Replace `isRecording: Bool` + `isTranscribing: Bool` in `AppState` with a single `phase: RecordingPhase` property.

**Current dual-boolean call sites (all must be migrated):**

| File | Line | Current code |
|------|------|-------------|
| FlowSpeechApp.swift | 25-26 | `@Published var isRecording = false` / `@Published var isTranscribing = false` |
| AppDelegate.swift | 112 | `if event.keyCode == 53 && appState.isRecording` |
| AppDelegate.swift | 136, 159, etc. | `appState.isRecording = true/false`, `appState.isTranscribing = true/false` |
| RecordingOverlayView.swift | 17 | `if appState.isTranscribing` |
| RecordingOverlayView.swift | 36 | `appState.isRecording ? Color.red...` |
| MenuBarPopoverView.swift | 33-38 | `if appState.isRecording` / `else if appState.isTranscribing` |
| CompactMenuBarView.swift | 244-248 | `statusColor` and `statusText` computed properties |

**Enum design:**
```swift
// In FlowSpeechApp.swift, inside AppState or at file scope
enum RecordingPhase: Equatable {
    case idle
    case recording
    case transcribing
    case done  // brief "success" state before returning to idle
}
```

`done` is included now so Phase 3's animated overlay has it available without another model change. It represents the brief window after transcription succeeds and before `idle` — AppDelegate can set `.done` then return to `.idle` after ~1.5 s.

**AppState migration:**
```swift
// Replace:
@Published var isRecording = false
@Published var isTranscribing = false

// With:
@Published var phase: RecordingPhase = .idle

// Convenience accessors (optional, eases migration at call sites):
var isRecording: Bool { phase == .recording }
var isTranscribing: Bool { phase == .transcribing }
```

Using the convenience accessors means most read-only call sites need zero changes; only the write sites (`appState.isRecording = true`) must be updated to `appState.phase = .recording`.

**Write sites to update in AppDelegate:**
- `startRecording()`: set `appState.phase = .recording`
- `stopRecordingAndTranscribe()`: set `appState.phase = .transcribing`
- `cancelRecording()`: set `appState.phase = .idle`
- Inside `transcribe()` on success: set `appState.phase = .done`, then after delay set `.idle`
- Inside `transcribe()` on error: set `appState.phase = .idle`
- `toggleRecording()`: branch on `appState.phase == .recording`

**Menu bar icon:** Drive from `phase` via a switch, replacing the `updateMenuBarIcon(recording:)` boolean parameter:
```swift
private func updateMenuBarIcon() {
    DispatchQueue.main.async {
        guard let button = self.statusItem.button else { return }
        switch self.appState.phase {
        case .idle, .done:
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Flow Speech")
            button.contentTintColor = nil
        case .recording:
            button.image = NSImage(systemSymbolName: "mic.badge.plus", accessibilityDescription: "Recording")
            button.contentTintColor = .systemRed
        case .transcribing:
            button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Transcribing")
            button.contentTintColor = .systemBlue
        }
    }
}
```

---

### Pattern 2: DesignSystem.swift (FNDTN-02)

**What:** A new file that owns the palette constants and the `Color(hex:)` extension.

**Palette (from STATE.md decisions):**
- Deep navy: background / container color
- Vibrant blue: primary accent / interactive elements
- Soft blue-white: text / highlight on dark backgrounds

**Suggested hex values** (consistent with Wispr Flow aesthetic and existing `#2563EB` vibrant blue):
- Deep navy: `#0F172A` (Tailwind slate-900 — very dark blue)
- Vibrant blue: `#2563EB` (existing — retain this, already in codebase)
- Soft blue-white: `#E0F2FE` (Tailwind sky-100 — pale blue-white)

These are design recommendations. The planner should carry these as defaults; the implementer can adjust if the user specifies different values.

**DesignSystem.swift structure:**
```swift
// DesignSystem.swift
import SwiftUI

enum DesignSystem {
    enum Colors {
        /// #0F172A — darkest background, overlays, menu bar popover
        static let deepNavy = Color(hex: "0F172A")
        /// #2563EB — primary accent, recording indicator, gradients
        static let vibrantBlue = Color(hex: "2563EB")
        /// #E0F2FE — light text on dark backgrounds, highlights
        static let softBlueWhite = Color(hex: "E0F2FE")

        // Semantic aliases
        static let recordingAccent = vibrantBlue
        static let overlayBackground = deepNavy
    }
}

// Color(hex:) extension — moved here from SettingsView.swift
extension Color {
    init(hex: String) {
        // ... existing implementation from SettingsView.swift line 396-415
    }
}
```

**Files requiring `Color(hex:)` import removal after move:**
- `SettingsView.swift` — remove the `extension Color` block (lines 393-416)
- All `Color(hex: "2563EB")` and `Color(hex: "0D9488")` references should migrate to `DesignSystem.Colors.*`

Note: The teal `#0D9488` is not in the new palette. During Phase 1, the task is only to add the three new tokens and migrate hex calls to the new constants. Whether to keep teal in the design system as a legacy alias is an implementation decision — recommend including it to keep existing views compilable without breaking changes.

---

### Pattern 3: CGEventTap Health Check (FNDTN-03)

**What:** macOS silently disables CGEventTaps when Accessibility permission is revoked or when the system determines the process is misbehaving. The current `HotkeyManager` has no detection or recovery.

**How CGEventTap disable happens:** The OS calls the tap callback with `CGEventType.tapDisabledByTimeout` or `CGEventType.tapDisabledByUserInput` (raw values 0xFFFFFFFE and 0xFFFFFFFF). The existing callback in `HotkeyManager.start()` does not handle these types — it falls through the `switch` to `return nil`, silently dropping the tap without re-enabling.

**Two-part fix:**

Part A — Handle disable events in the existing callback:
```swift
// Inside the callback closure in HotkeyManager.start():
case CGEventType(rawValue: 0xFFFFFFFE)!, // tapDisabledByTimeout
     CGEventType(rawValue: 0xFFFFFFFF)!: // tapDisabledByUserInput
    if let tap = manager.eventTap {
        CGEvent.tapEnable(tap: tap, enable: true)
    }
    return nil
```

Part B — Periodic health check (satisfies FNDTN-03's "every 2 seconds" requirement):
```swift
// In HotkeyManager
@Published var isTapHealthy: Bool = true
private var healthTimer: Timer?

func startHealthCheck() {
    healthTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
        self?.checkTapHealth()
    }
}

private func checkTapHealth() {
    guard let tap = eventTap else {
        isTapHealthy = false
        return
    }
    let enabled = CGEvent.tapIsEnabled(tap: tap)
    if !enabled {
        CGEvent.tapEnable(tap: tap, enable: true)
        // Re-check after attempt
        isTapHealthy = CGEvent.tapIsEnabled(tap: tap)
    } else {
        isTapHealthy = true
    }
}

func stopHealthCheck() {
    healthTimer?.invalidate()
    healthTimer = nil
}
```

**Menu bar icon degraded state (from FNDTN-03 success criteria):** `AppDelegate` observes `hotkeyManager.$isTapHealthy` (or AppState carries the flag) and updates the menu bar icon to a warning symbol when `false`:
```swift
// In AppDelegate, after setting up HotkeyManager:
hotkeyManager.$isTapHealthy
    .receive(on: DispatchQueue.main)
    .sink { [weak self] healthy in
        self?.updateMenuBarIcon(healthy: healthy)
    }
    .store(in: &cancellables)
```

Requires `import Combine` in AppDelegate and a `private var cancellables = Set<AnyCancellable>()`.

**Where to call `startHealthCheck()`:** At end of `HotkeyManager.start()`. Call `stopHealthCheck()` in `stop()` and `deinit`.

---

### Pattern 4: Animation Guard (FNDTN-04)

**What:** SwiftUI's `.repeatForever` animations run even when the window is not visible. In `RecordingOverlayView`, `pulseAnimation` is driven by `withAnimation(.easeInOut.repeatForever)` in `.onAppear`. The window is hidden via `orderOut(nil)`, but the SwiftUI render tree stays alive inside the `NSHostingView`. This causes constant CPU activity between sessions.

**Root cause:** `NSHostingView` keeps the SwiftUI view hierarchy alive even when the window is hidden with `orderOut`. The animations continue because `.onAppear` fires once when the hosting view is first embedded, and the `repeatForever` loop never stops.

**Fix — gate animations on visibility:**

Option A (recommended): Stop animation on `.onDisappear` and restart on `.onAppear`. The `RecordingOverlayView` root uses `.onAppear`/`.onDisappear` because the window calls `orderFront`/`orderOut` each time, which does trigger appear/disappear on the root view.

```swift
// In RecordingOverlayView
.onAppear {
    withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
        pulseAnimation = true
    }
}
.onDisappear {
    // Stop all animations
    withAnimation(.linear(duration: 0)) {
        pulseAnimation = false
    }
}
```

For `TranscribingView`'s rotation animation and `RecordingStatusView`'s pulse, apply the same `.onDisappear` pattern to each sub-view.

Option B: Recreate the window each session (destroy/create rather than orderOut/orderFront). This is heavier than necessary; Option A is preferred.

**Verification:** After implementing, confirm CPU usage in Activity Monitor is <1% between recording sessions. The spinning `TranscribingView` rotation is the most egregious offender — it runs at 360°/sec continuously.

---

### Anti-Patterns to Avoid

- **Don't add `idle/done` conditional logic to RecordingOverlayView in Phase 1.** The overlay's visual states are Phase 3 work. Phase 1 only adds the enum to the model.
- **Don't rename `Color(hex:)` to something else** when moving it. All existing call sites use the exact initializer signature.
- **Don't invalidate and recreate the CGEventTap in the health check.** Re-enabling is sufficient; recreation would lose the run loop source attachment.
- **Don't use `DispatchQueue.main.asyncAfter` for the 2-second health interval.** Use `Timer.scheduledTimer` — it's cancellable and ties cleanly to the run loop.
- **Don't add `isTapHealthy` to AppState.** It belongs on `HotkeyManager` as a `@Published` property; AppDelegate can forward it to the icon update as needed.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| CGEventTap enabled check | Custom polling with `CFMachPort` introspection | `CGEvent.tapIsEnabled(tap:)` | Direct API, one line |
| Color token system | Custom theme manager with protocol | `enum DesignSystem` namespace with static `Color` properties | Zero runtime cost, autocomplete, Swift-native |
| Animation pause/resume | Complex state machine with multiple flags | `.onAppear`/`.onDisappear` on the overlay root | SwiftUI already delivers these events when `orderFront`/`orderOut` changes visibility |
| Combine observation in AppDelegate | Polling `isTapHealthy` on a timer | `sink` on `@Published` property | Reactive, no polling overhead |

---

## Common Pitfalls

### Pitfall 1: Dual Bool to Enum — Missed Write Sites

**What goes wrong:** The convenience `isRecording`/`isTranscribing` computed vars on AppState make read sites look correct, but write sites still compile if you accidentally leave `appState.isRecording = false` (the stored property is gone — this would be a compile error). The risk is forgetting `appState.phase = .done` before returning to `.idle`.

**How to avoid:** After deleting the stored booleans, let the compiler catch all remaining write sites. Fix each one. Search for `appState.phase` vs `appState.isRecording =` to confirm all writes are gone.

**Warning signs:** App gets stuck in `.transcribing` or `.recording` phase after error conditions.

---

### Pitfall 2: Color Extension Duplication

**What goes wrong:** Moving `Color(hex:)` to `DesignSystem.swift` but leaving the old extension in `SettingsView.swift` causes a "redeclaration" compile error.

**How to avoid:** Delete lines 393–416 from `SettingsView.swift` as part of the same task that creates `DesignSystem.swift`. Do not split these into separate tasks.

---

### Pitfall 3: CGEventTap Health Timer on Wrong Run Loop

**What goes wrong:** `Timer.scheduledTimer` requires the calling thread's run loop to be running. If `startHealthCheck()` is called from a background thread, the timer silently never fires.

**How to avoid:** Call `startHealthCheck()` on the main thread (or schedule explicitly on `RunLoop.main`):
```swift
RunLoop.main.add(healthTimer!, forMode: .common)
```
Or use `Timer.scheduledTimer` from the main thread (AppDelegate's `applicationDidFinishLaunching` is fine).

---

### Pitfall 4: onAppear Not Firing on Hidden Window

**What goes wrong:** If the overlay window is created once and reused (current approach: created lazily then `orderOut`/`orderFront`), `.onAppear` fires only on first creation, not on each `orderFront`. This means Option A for the animation guard would stop animations on first `orderOut` but never restart them.

**Investigation:** In the current `AppDelegate`, `showRecordingOverlay()` calls `window.orderFront(nil)` each time but only creates the window once. The SwiftUI view is embedded in `NSHostingView` which is set as `contentView` once. `.onAppear` fires when the view is first inserted into the hierarchy — not on `orderFront`.

**Correct fix:** Use `NSWindow.isVisible` observer pattern, or drive animation state from `AppState.phase` directly:
```swift
// In RecordingOverlayView body, gate animation on phase:
.onChange(of: appState.phase) { newPhase in
    if newPhase == .recording {
        withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
            pulseAnimation = true
        }
    } else {
        // Cancel animation immediately
        withAnimation(.linear(duration: 0)) {
            pulseAnimation = false
        }
    }
}
.onAppear {
    // Handle case where view appears already in recording phase
    if appState.phase == .recording {
        withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
            pulseAnimation = true
        }
    }
}
```

This is the correct implementation for FNDTN-04. It depends on FNDTN-01 (the enum) being in place first, making FNDTN-01 a prerequisite for FNDTN-04.

**Warning signs:** Activity Monitor still shows >1% CPU between sessions after implementing the fix — indicates animations are not actually stopping.

---

### Pitfall 5: CGEventTap tapDisabledBy* Types Not in Swift Enum

**What goes wrong:** `CGEventType.tapDisabledByTimeout` and `CGEventType.tapDisabledByUserInput` are not enumerated cases in Swift's `CGEventType` enum despite being defined in the C header. Switching on them without raw-value handling causes a compile error.

**How to avoid:** Use raw value comparison in the callback:
```swift
let tapDisabledByTimeout = CGEventType(rawValue: 0xFFFFFFFE)
let tapDisabledByUserInput = CGEventType(rawValue: 0xFFFFFFFF)
if type == tapDisabledByTimeout || type == tapDisabledByUserInput {
    // re-enable
}
```

---

## Code Examples

### RecordingPhase Enum (complete, ready to use)

```swift
// Source: direct design for FlowSpeech AppState
enum RecordingPhase: Equatable {
    case idle
    case recording
    case transcribing
    case done
}

// In AppState:
@Published var phase: RecordingPhase = .idle

// Compatibility shims (remove after all call sites migrated):
var isRecording: Bool { phase == .recording }
var isTranscribing: Bool { phase == .transcribing }
```

### DesignSystem.swift (complete skeleton)

```swift
// DesignSystem.swift
import SwiftUI

enum DesignSystem {
    enum Colors {
        static let deepNavy      = Color(hex: "0F172A")
        static let vibrantBlue   = Color(hex: "2563EB")
        static let softBlueWhite = Color(hex: "E0F2FE")
        // Legacy — keep for existing gradient uses, revisit in Phase 3
        static let teal          = Color(hex: "0D9488")
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:  (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:  (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:  (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 255, 255, 255)
        }
        self.init(.sRGB, red: Double(r)/255, green: Double(g)/255,
                  blue: Double(b)/255, opacity: Double(a)/255)
    }
}
```

### CGEventTap Health Check (HotkeyManager additions)

```swift
// Source: CGEvent API + Timer pattern for FlowSpeech HotkeyManager
@Published var isTapHealthy: Bool = true
private var healthTimer: Timer?

func startHealthCheck() {
    healthTimer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
        self?.checkTapHealth()
    }
    RunLoop.main.add(healthTimer!, forMode: .common)
}

private func checkTapHealth() {
    guard let tap = eventTap else {
        DispatchQueue.main.async { self.isTapHealthy = false }
        return
    }
    let enabled = CGEvent.tapIsEnabled(tap: tap)
    if !enabled {
        CGEvent.tapEnable(tap: tap, enable: true)
    }
    let nowHealthy = CGEvent.tapIsEnabled(tap: tap)
    DispatchQueue.main.async { self.isTapHealthy = nowHealthy }
}

func stopHealthCheck() {
    healthTimer?.invalidate()
    healthTimer = nil
}
```

### Animation Gate Pattern (RecordingOverlayView)

```swift
// Source: SwiftUI onChange + AppState.phase for animation control
.onChange(of: appState.phase) { newPhase in
    switch newPhase {
    case .recording:
        withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
            pulseAnimation = true
        }
    default:
        withAnimation(.linear(duration: 0)) {
            pulseAnimation = false
        }
    }
}
```

---

## State of the Art

| Old Approach | Current Approach | Impact for This Phase |
|--------------|-----------------|----------------------|
| Dual `isRecording`/`isTranscribing` booleans | Single `RecordingPhase` enum | Eliminates impossible combined states; enables Phase 3 4-state UI |
| Hardcoded hex strings scattered in views | `DesignSystem.Colors.*` static constants | Single change point for palette; Phase 3 UI can consume tokens directly |
| No CGEventTap health monitoring | Periodic health check + re-enable | Hotkey survives Accessibility revocation / OS timeout |
| Always-running SwiftUI animations | Phase-gated animation state | Eliminates idle CPU drain between recording sessions |

**Deprecated/outdated in this phase:**
- `AppState.isRecording` as stored property — replaced by `phase == .recording`
- `AppState.isTranscribing` as stored property — replaced by `phase == .transcribing`
- `updateMenuBarIcon(recording: Bool)` signature — replaced by `updateMenuBarIcon()` driven by `phase`
- `Color(hex:)` extension in `SettingsView.swift` — moved to `DesignSystem.swift`

---

## Open Questions

1. **`done` state duration — how long before returning to `idle`?**
   - What we know: `done` is needed for Phase 3's "success flash" animation
   - What's unclear: AppDelegate should auto-transition `.done` → `.idle` after N seconds; N is unspecified
   - Recommendation: Default to 1.5 seconds in Phase 1 implementation. Phase 3 can adjust.

2. **Deep navy hex value for Phase 1 token**
   - What we know: User specified "deep navy, vibrant blue, soft blue-white" as the palette (STATE.md)
   - What's unclear: No exact hex value was specified for deep navy or soft blue-white
   - Recommendation: Use `#0F172A` (Tailwind slate-900) for deep navy and `#E0F2FE` (Tailwind sky-100) for soft blue-white. These are standard Tailwind values that match the Wispr Flow aesthetic. The planner can include a note for the implementer to confirm with the user if needed.

3. **macOS minimum version**
   - What we know: STATE.md flags "macOS minimum version unspecified" as a blocker for Phase 3
   - What's unclear: `.onChange(of:)` with a single closure parameter requires macOS 14; the two-parameter form works on macOS 13
   - Recommendation: Use the two-parameter `.onChange(of:perform:)` form for FNDTN-04 to stay compatible with macOS 13. This is a safe default until the version decision is made.

---

## Validation Architecture

No automated test infrastructure exists in this project (no test files, no test targets visible in the Swift source tree). This is a SwiftUI/AppKit macOS app — unit testing AppState and HotkeyManager is feasible but not currently set up.

### Phase Gate (Manual Verification)

Since no test framework is configured, validation for each requirement is manual:

| Req ID | Behavior | Verification Method |
|--------|----------|-------------------|
| FNDTN-01 | App compiles and runs with RecordingPhase enum | Build succeeds; hold hotkey → record → release → transcribe; verify all 4 phase transitions occur without crash |
| FNDTN-02 | UI uses DesignSystem.Colors constants | Code review: `grep -r "Color(hex:" FlowSpeech/` returns zero results after migration |
| FNDTN-03 | Menu bar icon shows degraded state when tap disabled | Revoke Accessibility in System Settings, wait 2 seconds, observe icon change |
| FNDTN-04 | CPU <1% between sessions | Activity Monitor — run app, complete one recording session, observe CPU after transcription completes |

### Wave 0 Gaps

- No XCTest target — out of scope for Phase 1; flagged for future phases
- Manual verification protocol above is sufficient for Phase 1's structural changes

---

## Sources

### Primary (HIGH confidence)
- Direct source inspection: `FlowSpeechApp.swift` — AppState, dual boolean pattern, all 4 files using `isRecording`/`isTranscribing`
- Direct source inspection: `AppDelegate.swift` — all recording state transitions, `updateMenuBarIcon(recording:)`
- Direct source inspection: `HotkeyManager.swift` — CGEventTap setup, absence of health check
- Direct source inspection: `RecordingOverlayView.swift` — `pulseAnimation` in `.onAppear`, `TranscribingView` rotation, `WaveformBar` animation
- Direct source inspection: `SettingsView.swift` lines 393-416 — `Color(hex:)` extension location
- Direct source inspection: grep results — 14 `Color(hex:)` call sites across 4 files

### Secondary (MEDIUM confidence)
- Apple CGEvent documentation: `CGEvent.tapIsEnabled(tap:)` API — standard macOS API, stable since 10.4
- Apple CGEventType raw values for `tapDisabledByTimeout` (0xFFFFFFFE) / `tapDisabledByUserInput` (0xFFFFFFFF) — documented in `<CoreGraphics/CGEventTypes.h>`
- SwiftUI `.onChange(of:perform:)` two-parameter form — compatible macOS 12+; single-closure form requires macOS 14

### Tertiary (LOW confidence)
- Behavior of `.onAppear` on reused `NSHostingView` when window is `orderOut`/`orderFront` — inferred from SwiftUI lifecycle model; should be validated empirically during implementation

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no new dependencies; all APIs are present in the existing codebase
- Architecture: HIGH — derived from direct source inspection of all 11 Swift files
- Pitfalls: HIGH for compile-time issues (missing extension move, enum raw values); MEDIUM for runtime behavior (onAppear timing on reused NSHostingView)

**Research date:** 2026-03-26
**Valid until:** Stable — these are foundational platform APIs; no expected changes within 90 days
