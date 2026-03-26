# Stack Research

**Domain:** macOS menu bar utility app — UI animation polish, app exclusion, clipboard management
**Researched:** 2026-03-26
**Confidence:** HIGH (all core APIs are native Apple frameworks, verified against official documentation and cross-referenced sources)

---

## Context: What Already Exists

This is a v1.1 milestone — the stack additions are **incremental**, not greenfield. The existing app already uses:
- SwiftUI + AppDelegate hybrid (NSHostingView inside NSWindow)
- AppKit (NSStatusBar, NSWindow, NSEvent, CGEvent)
- NSPasteboard for clipboard write + restore
- NSWorkspace.shared.frontmostApplication (already called in TextInserter.swift)

The four new capability areas each map to native Apple APIs only. **No third-party dependencies are needed.**

---

## Recommended Stack

### Core Technologies — New Capabilities Only

| Technology | Version/Availability | Purpose | Why Recommended |
|------------|---------------------|---------|-----------------|
| SwiftUI `withAnimation(.spring)` | macOS 12+ (spring presets macOS 14+) | State transition animations | Native, declarative, integrates directly with existing SwiftUI views |
| SwiftUI `PhaseAnimator` | macOS 14+ (Sonoma) | Multi-phase idle→recording→transcribing→done cycle | Handles sequential animation phases without manual state machine; introduced WWDC23 |
| SwiftUI `TimelineView` + `Canvas` | macOS 12+ | High-performance waveform redraw at 60fps | `Canvas` provides immediate-mode drawing; `TimelineView` drives time-based updates without per-frame state mutations that trigger full view re-renders |
| SwiftUI `Capsule` shape + `matchedGeometryEffect` | macOS 11+ | Flow Bar pill overlay shape and size transitions | `Capsule` is the canonical pill shape; `matchedGeometryEffect` handles smooth geometry transitions between recording/transcribing states |
| `NSWorkspace.shared.frontmostApplication` | macOS 10.6+ | Frontmost app detection | Already imported in codebase; returns `NSRunningApplication` with `bundleIdentifier`, `localizedName`, `activationPolicy` |
| `NSWorkspace.shared.notificationCenter` — `didActivateApplicationNotification` | macOS 10.6+ | Real-time frontmost app change observation | Push-based; fires whenever user switches apps; extract app via `userInfo[NSWorkspace.applicationUserInfoKey]` |
| `CGWindowListCopyWindowInfo` + `kCGWindowBounds` | macOS 10.5+ | Fullscreen state detection for frontmost app | Only reliable cross-process fullscreen signal available; compare window bounds against `NSScreen.main?.frame` |
| `NSRunningApplication.activationPolicy` | macOS 10.6+ | Filter out background/agent processes | `.regular` means visible in Dock; useful to skip background processes when checking exclusion list |
| `NSPasteboard.general` (no-restore variant) | macOS 10.0+ | Clipboard persistence after paste | Already used; change: skip the `DispatchQueue.asyncAfter` restore block when transcription mode is active |

### Supporting Patterns — No New Libraries

| Pattern | Purpose | Integration Point |
|---------|---------|-------------------|
| `@AppStorage("excludedBundleIDs")` with JSON-encoded `[String]` | Persist user's excluded app list | `AppState` or `UserDefaults` — consistent with existing `UserDefaults` usage in the app |
| `NSWorkspace.shared.notificationCenter.publisher(for:)` + Combine | Reactive frontmost app updates | `AppDelegate` or new `AppExclusionManager` service; feeds `AppState.isSuppressed` bool |
| `NSScreen.main?.frame` vs window bounds comparison | Fullscreen approximation | Called inside frontmost app change handler; not polled |
| `NSWindow.level = .statusBar` + `.collectionBehavior = [.canJoinAllSpaces, .transient]` | Overlay window above fullscreen apps | Already set to `.floating` in `AppDelegate.showRecordingOverlay()`; upgrade to `.statusBar` level so it appears over Mission Control spaces |

---

## Installation

No package manager changes required. All APIs are in Apple system frameworks already imported:

```swift
// Already imported in existing files — no additions needed
import AppKit       // NSWorkspace, NSRunningApplication, NSPasteboard, NSWindow
import SwiftUI      // withAnimation, PhaseAnimator, TimelineView, Canvas, Capsule
import CoreGraphics // CGWindowListCopyWindowInfo
```

---

## Feature-to-API Mapping

### 1. Polished Animations and Overlay Redesign

**Use:** `withAnimation(.spring(response: 0.4, dampingFraction: 0.75))` for state transitions.

The `.spring(response:dampingFraction:)` API is available from macOS 12+. For macOS 14+ targets, the shorthand presets `.snappy`, `.smooth`, and `.bouncy` are available — use `.snappy` for UI appearing/disappearing (fast entry, no overshoot) and `.spring` for waveform scaling (subtle bounce acceptable).

**Use:** `PhaseAnimator` (macOS 14+) for the idle→recording→transcribing→done state machine. It automatically cycles through phases and calls `animation(phase:)` so each state gets its own curve.

**Use:** `TimelineView(.animation(minimumInterval: 1/30))` wrapping a `Canvas` for the waveform. The existing `WaveformView` uses `ForEach` over `WaveformBar` structs — this causes SwiftUI diffing overhead at audio-level update rates. `Canvas` draws all bars imperatively inside a single draw pass, which is far more efficient at 20-30fps updates.

**Avoid:** `matchedGeometryEffect` for the recording→transcribing state swap inside the pill. It requires both source and destination views to exist simultaneously, which conflicts with the `if/else` branch structure in `RecordingOverlayView`. Use `AnyTransition.asymmetric(insertion: .scale.combined(with: .opacity), removal: .opacity)` on the conditional content instead.

### 2. Game/Fullscreen App Exclusion

**Primary signal:** `NSWorkspace.didActivateApplicationNotification`

Subscribe in `AppDelegate.applicationDidFinishLaunching` via Combine:

```swift
NSWorkspace.shared.notificationCenter
    .publisher(for: NSWorkspace.didActivateApplicationNotification)
    .compactMap { $0.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication }
    .receive(on: DispatchQueue.main)
    .sink { [weak self] app in self?.evaluateExclusion(for: app) }
    .store(in: &cancellables)
```

**Exclusion check logic (in priority order):**

1. **Bundle ID list match** — check `app.bundleIdentifier` against user-defined exclusion list stored in `UserDefaults`. Most reliable; League of Legends bundle ID is `com.riotgames.LeagueofLegends`. Pre-populate a default list of common gaming launchers.

2. **Fullscreen geometry check** — call `CGWindowListCopyWindowInfo([.excludeDesktopElements, .optionOnScreenOnly], kCGNullWindowID)` and find windows owned by `app.processIdentifier`. If the window's `kCGWindowBounds` matches `NSScreen.main?.frame` (within 1pt tolerance), treat as fullscreen.

**Important limitation:** `CGWindowListCopyWindowInfo` requires Screen Recording permission on macOS 10.15+ if you need window titles. For bounds-only detection (no title), it works with just the existing Accessibility permission. The `kCGWindowBounds` key is always available.

**Do not use:** `NSWorkspace.activeSpaceDidChange` notification for this purpose — it fires on Space switches, not app focus changes, and doesn't give you the active app object directly.

**Suppress mechanism:** Set `appState.isHotkeySupprressed = true` when exclusion triggers. Gate `startRecording()` in `AppDelegate.handleFlagsChanged` on `!appState.isHotkeySupressed`.

### 3. Clipboard Persistence

**Current behavior** in `TextInserter.insertText()`: saves old clipboard, writes transcription, pastes, restores old clipboard after 0.5s.

**New behavior:** Conditional on a `UserDefaults` flag `persistClipboardAfterTranscription` (default: `true`).

When `true`, simply skip the restore block:

```swift
// Existing code to REMOVE when persistence is enabled:
if let old = oldContent {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        pasteboard.clearContents()
        pasteboard.setString(old, forType: .string)
    }
}
```

No new API needed. `NSPasteboard.general` already holds the transcription until overwritten. This is the correct approach — `NSPasteboard.clearContents()` + `setString(_:forType:)` is already atomic from other apps' perspective.

**NSPasteboard change count:** Read `NSPasteboard.general.changeCount` before paste, then after the optional restore. This lets the app detect if another app wrote to clipboard in the 0.5s window, and skip the restore even when persistence is off (safety measure).

### 4. "Flow Bar" Pill Overlay Design

**Shape:** Replace `RoundedRectangle(cornerRadius: 16)` in `RecordingOverlayView` with `Capsule()`. Capsule automatically produces pill geometry regardless of content size changes.

**Window sizing:** The current fixed `NSRect(x: 0, y: 0, width: 200, height: 80)` must become dynamic. Use `NSHostingView`'s `intrinsicContentSize` or set `recordingWindow?.setContentSize(hostingView.fittingSize)` after content updates.

**Material:** Keep `.ultraThinMaterial` — it is the correct choice for floating overlays. Deep navy background with `.ultraThinMaterial` overlay produces the desired "frosted blue pill" look without custom tinting.

**Window positioning:** Move from top-center (current: `screenFrame.maxY - 100`) to bottom-center or near-cursor. Wispr Flow positions its bar at screen bottom-center. Implement by reading `NSScreen.main?.visibleFrame` and placing at `midX - width/2, minY + 80`.

**Window level:** Upgrade from `.floating` to `.statusBar` (`NSWindow.Level.statusBar`) so the overlay appears above fullscreen spaces when the user is NOT in an excluded app. Use `.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]`.

---

## Alternatives Considered

| Recommended | Alternative | Why Not |
|-------------|-------------|---------|
| `CGWindowListCopyWindowInfo` for fullscreen detection | `NSRunningApplication.isFinishedLaunching` / `.activationPolicy` only | Neither property encodes fullscreen state; activation policy only distinguishes regular/agent/prohibited categories |
| Native SwiftUI `PhaseAnimator` | Third-party animation library (Lottie, Motion) | Adds dependency for functionality built into the SDK since macOS 14; Lottie requires JSON animation assets for every state |
| `NSWorkspace.didActivateApplicationNotification` | Polling `NSWorkspace.shared.frontmostApplication` on a timer | Polling wastes CPU; push notification is zero-cost when no app switch occurs |
| Conditional no-restore for clipboard persistence | Separate `NSPasteboard` named pasteboard | Named pasteboards are not accessible by other apps via Cmd+V; general pasteboard is the only paste target |
| `TimelineView` + `Canvas` for waveform | `withAnimation` on `ForEach` bars | `ForEach` triggers SwiftUI diffing 20-30x/second during recording; `Canvas` is a single draw call and does not participate in SwiftUI layout engine |

---

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| `NSRunningApplication.isFullScreen` | This property does not exist on `NSRunningApplication` — the API only exposes `isActive`, `isHidden`, `isFinishedLaunching`, `activationPolicy`, etc. | `CGWindowListCopyWindowInfo` bounds comparison |
| `NSWorkspace.activeSpaceDidChange` notification for app tracking | Fires on Space switch, not app focus change; doesn't include which app became frontmost | `NSWorkspace.didActivateApplicationNotification` |
| Third-party animation libraries (Lottie, PopBoy, etc.) | No macOS-specific optimizations; adds binary size; PhaseAnimator + spring curves cover all required animations | Native SwiftUI animation APIs |
| `AXUIElement` to detect frontmost app fullscreen | AXUIElement's `kAXFullscreenAttribute` is unreliable and app-dependent; some games don't report it | CGWindow bounds comparison |
| `.collectionBehavior = .fullScreenAuxiliary` on overlay window | This makes the window visible *inside* fullscreen apps (not wanted for excluded games) | Keep `.canJoinAllSpaces` + gate visibility via `isHotkeySupressed` flag |
| Hardcoded bundle ID list only (no geometry fallback) | Games like League of Legends may run via launcher wrapper with different bundle IDs depending on region | Bundle ID list as primary + CGWindow geometry as fallback |

---

## Stack Patterns by Variant

**If targeting macOS 14+ only (Sonoma minimum):**
- Use `PhaseAnimator` directly — clean multi-phase API
- Use `.snappy`, `.smooth`, `.bouncy` spring presets — more readable than manual `response/dampingFraction` params
- Use `KeyframeAnimator` if waveform needs keyframe-precise control (overkill for this use case; `TimelineView` is sufficient)

**If supporting macOS 12-13:**
- Replace `PhaseAnimator` with manual `@State var animationPhase: RecordingPhase` + `withAnimation` on phase transitions
- Use explicit `.spring(response: 0.4, dampingFraction: 0.75)` instead of `.snappy`
- `TimelineView` and `Canvas` are available from macOS 12, so waveform approach is unchanged

**Given PROJECT.md does not specify a minimum macOS version**, assume macOS 13+ (Ventura) as a safe baseline — most users are on Ventura or Sonoma. This excludes `PhaseAnimator` (macOS 14 only). Implement manual phase state machine as fallback unless you confirm macOS 14 minimum.

---

## Version Compatibility

| Component | Minimum macOS | Notes |
|-----------|---------------|-------|
| `PhaseAnimator` | 14.0 (Sonoma) | WWDC23 addition; not available on Ventura |
| `KeyframeAnimator` | 17.0 iOS / 14.0 macOS | Same release as PhaseAnimator |
| `TimelineView` + `Canvas` | 12.0 (Monterey) | Safe to use unconditionally if targeting 12+ |
| `withAnimation(.spring(response:dampingFraction:))` | 10.15+ | Long-standing API |
| `.snappy`, `.smooth`, `.bouncy` presets | 17.0 iOS / 14.0 macOS | Shorthand for common spring configs |
| `NSWorkspace.didActivateApplicationNotification` | 10.6+ | Fully stable |
| `CGWindowListCopyWindowInfo` | 10.5+ | Screen Recording permission required for window titles on 10.15+; bounds work without it |
| `NSPasteboard.general.changeCount` | 10.0+ | Reliable change detection |

---

## Sources

- Apple Developer Documentation — `NSWorkspace.frontmostApplication`: https://developer.apple.com/documentation/appkit/nsworkspace/frontmostapplication
- Apple Developer Documentation — `NSWorkspace.didActivateApplicationNotification`: https://developer.apple.com/documentation/appkit/nsworkspace/didactivateapplicationnotification
- Apple Developer Documentation — `NSRunningApplication`: https://developer.apple.com/documentation/appkit/nsrunningapplication
- Apple Developer Documentation — `CGWindowListCopyWindowInfo`: https://developer.apple.com/documentation/coregraphics/cgwindowlistcopywindowinfo(_:_:)
- Apple Developer Documentation — `NSPasteboard`: https://developer.apple.com/documentation/appkit/nspasteboard
- Apple Developer Forums — Fullscreen Detection (thread/792917): https://developer.apple.com/forums/thread/792917 — confirms no `isFullScreen` on NSRunningApplication, CGWindow bounds is the right approach
- Apple Developer Documentation — `PhaseAnimator`: https://developer.apple.com/documentation/swiftui/phaseanimator — macOS 14.0+ confirmed
- WWDC23 Session 10157 "Wind your way through advanced animations in SwiftUI": https://developer.apple.com/videos/play/wwdc2023/10157/ — PhaseAnimator and KeyframeAnimator introduction
- SwiftUI Lab — PhaseAnimator deep dive: https://swiftui-lab.com/swiftui-animations-part7/ — MEDIUM confidence (third-party blog, consistent with official docs)
- Existing codebase — `TextInserter.swift`, `HotkeyManager.swift`, `AppDelegate.swift`, `RecordingOverlayView.swift` — confirmed current API usage patterns

---

*Stack research for: SpeechFlow v1.1 — UI revamp, app exclusion, clipboard persistence*
*Researched: 2026-03-26*
