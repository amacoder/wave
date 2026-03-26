# Phase 3: Overlay Redesign - Research

**Researched:** 2026-03-26
**Domain:** SwiftUI macOS — Capsule overlay, spring animations, Canvas drawing, NSWindow management
**Confidence:** HIGH

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| OVLAY-01 | Recording overlay is a pill shape positioned at bottom-center of screen | Capsule shape + NSWindow bottom-center positioning documented; existing window uses RoundedRectangle(cornerRadius:16) — must be replaced |
| OVLAY-02 | Overlay renders 4 distinct visual states (idle, recording, transcribing, done) | All 4 branches of RecordingPhase enum mapped to distinct visual designs; idle state is currently never shown (overlay hidden) — new design shows it |
| OVLAY-03 | State transitions use spring animations with subtle fades | `.spring(duration:bounce:)` + `.transition(.opacity.combined(with:.scale))` in ZStack pattern documented |
| OVLAY-04 | Waveform uses Canvas single-draw-pass instead of ForEach+bars | Canvas `{ context, size in ... context.fill(...) }` pattern replaces `ForEach(0..<barCount)` WaveformView |
</phase_requirements>

---

## Summary

Phase 3 is a focused UI rewrite of `RecordingOverlayView.swift` plus a targeted change to `AppDelegate.swift`. The overlay's visual shape, four-state rendering, animation style, and waveform implementation all need replacement. No new dependencies are required — SwiftUI, AppKit, and CoreGraphics are sufficient.

The most significant architectural change is in `AppDelegate.swift`: the current code calls `hideRecordingOverlay()` immediately when `phase = .done`, so the done state is never visible to the user. Phase 3 requires keeping the overlay visible during `.done` for 0.8s and hiding it after that flash. The `hideRecordingOverlay()` call must move from the done-transition block into a `DispatchQueue.main.asyncAfter(deadline: .now() + 0.8)` closure, and the existing `1.5s` idle transition can remain as-is (it fires at +1.5s after done, still longer than the 0.8s hide).

The overlay background switches from `RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial)` to `Capsule().fill(DesignSystem.Colors.deepNavy.opacity(0.92))` (or equivalent semi-transparent navy), styled per the v1.1 blue palette. The pill is positioned at bottom-center using existing `NSScreen.main.visibleFrame` math — only the `y` value and window width need adjustment to match a compact pill rather than the current tall rectangle.

The waveform replacement (OVLAY-04) is a drop-in Canvas substitution: remove the `WaveformView` struct (ForEach+WaveformBar pattern) and replace it with a single Canvas block that iterates `audioLevels` and calls `context.fill(Path(roundedRect:), with: .color(...))` for each bar in one pass.

**Primary recommendation:** Implement as two tasks: (1) the AppDelegate done-state timing fix + new pill window sizing, and (2) the full RecordingOverlayView rewrite with all four states and Canvas waveform.

---

## Standard Stack

### Core (no new dependencies)

| Component | Version | Purpose | Notes |
|-----------|---------|---------|-------|
| SwiftUI | macOS 14+ | All view rendering | Already in project |
| AppKit (NSWindow, NSScreen) | macOS 14+ | Window positioning, ordering | Already in AppDelegate |
| DesignSystem.Colors | project-local | Blue palette tokens | Already in DesignSystem.swift |
| Canvas (SwiftUI) | macOS 12+ | Single-pass waveform bars | Available; replaces ForEach+WaveformBar |

### No New Dependencies

All requirements are satisfiable with APIs already imported. Do not introduce new SPM packages for this phase.

**Verified:** macOS deployment target in `FlowSpeech.xcodeproj/project.pbxproj` is **14.6** for the app target. All SwiftUI APIs referenced below are available on macOS 14+.

---

## Architecture Patterns

### Recommended File Changes After Phase 3

```
FlowSpeech/
├── AppDelegate.swift              # CHANGED: done-state hide timing (0.8s delay)
└── Views/
    └── RecordingOverlayView.swift # REWRITTEN: pill shape, 4-state ZStack, Canvas waveform
```

No new files needed. No other files touched.

### Pattern 1: Capsule Pill Background

Replace `RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial)` with a navy-tinted Capsule. The `.background` modifier wraps the entire HStack content:

```swift
// Source: Apple Developer Documentation — Capsule shape
.background(
    Capsule()
        .fill(DesignSystem.Colors.deepNavy.opacity(0.92))
        .shadow(color: .black.opacity(0.35), radius: 12, x: 0, y: 6)
)
```

The Capsule shape automatically produces a pill (stadium) shape regardless of the aspect ratio. No corner radius arithmetic needed.

### Pattern 2: Bottom-Center NSWindow Positioning

The existing `showRecordingOverlay()` in AppDelegate already uses `NSScreen.main`. The window rect must be updated to match a compact pill:

```swift
// Source: existing AppDelegate.swift + NSScreen API
let pillWidth: CGFloat = 280
let pillHeight: CGFloat = 52

if let screen = NSScreen.main {
    let screenFrame = screen.visibleFrame
    let x = screenFrame.midX - pillWidth / 2
    let y = screenFrame.minY + 32   // 32pt above the Dock
    recordingWindow?.setFrame(
        NSRect(x: x, y: y, width: pillWidth, height: pillHeight),
        display: true
    )
}
```

The `y = screenFrame.minY + 32` positions the pill above the Dock with a comfortable margin. `screenFrame.minY` accounts for the Dock height on `NSScreen.visibleFrame`.

### Pattern 3: Four-State ZStack with Spring Transitions

Use a `ZStack` with `if/else if` branches for each state. Each branch applies `.transition()` so SwiftUI animates the crossfade. Wrap the state change with `withAnimation(.spring(duration: 0.35, bounce: 0.1))` at the call site (AppDelegate) or via `onChange`:

```swift
// Source: WWDC23 "Animate with Springs" session
ZStack {
    if appState.phase == .idle {
        IdleStateView()
            .transition(.opacity.combined(with: .scale(scale: 0.92)))
    } else if appState.phase == .recording {
        RecordingStateView(levels: appState.audioLevels)
            .transition(.opacity.combined(with: .scale(scale: 0.92)))
    } else if appState.phase == .transcribing {
        TranscribingStateView()
            .transition(.opacity.combined(with: .scale(scale: 0.92)))
    } else if appState.phase == .done {
        DoneStateView()
            .transition(.opacity.combined(with: .scale(scale: 0.92)))
    }
}
.animation(.spring(duration: 0.35, bounce: 0.1), value: appState.phase)
```

**Critical:** Attach `.animation(_:value:)` directly to the ZStack so all state-driven branch changes animate. Do NOT use `withAnimation` at every AppDelegate call site — the `value:` binding form is cleaner and ensures the overlay's own animations are self-contained.

**ZIndex pitfall:** When combining `.opacity` transitions inside a ZStack, SwiftUI can render both outgoing and incoming views simultaneously during the transition. Adding `.id(appState.phase)` to the ZStack's content or using explicit `zIndex` modifiers prevents drawing order artifacts during the crossfade.

### Pattern 4: Canvas Single-Pass Waveform

Replace the `WaveformView` (ForEach + WaveformBar structs) with a Canvas block:

```swift
// Source: swiftwithmajid.com/2023/04/11/mastering-canvas-in-swiftui/
Canvas { context, size in
    let count = levels.count
    guard count > 0 else { return }
    let gap: CGFloat = 2
    let barWidth: CGFloat = (size.width - gap * CGFloat(count - 1)) / CGFloat(count)

    for (i, level) in levels.enumerated() {
        let barHeight = max(3, CGFloat(level) * size.height)
        let x = CGFloat(i) * (barWidth + gap)
        let y = (size.height - barHeight) / 2   // center-aligned vertically
        let rect = CGRect(x: x, y: y, width: barWidth, height: barHeight)
        context.fill(
            Path(roundedRect: rect, cornerRadius: 2),
            with: .color(DesignSystem.Colors.vibrantBlue)
        )
    }
}
.frame(width: 80, height: 24)
```

This executes one redraw pass per frame — no individual view allocation per bar. For 30 bars at 60fps this is negligible load; the performance win is more visible at 100+ bars, but the explicit requirement (OVLAY-04) mandates Canvas regardless.

**Redraws:** Canvas redraws whenever its inputs change. Because `appState.audioLevels` is `@Published`, every `updateAudioLevel()` call triggers a redraw. This is correct behavior — no additional animation wiring is needed for the waveform to feel live.

### Pattern 5: AppDelegate Done-State Timing Fix

The current `transcribe()` function calls `hideRecordingOverlay()` at the same instant as `phase = .done`, making the done state invisible. Change to:

```swift
// AppDelegate.swift — inside transcribe() MainActor.run block
appState.phase = .done
// Do NOT call hideRecordingOverlay() immediately

// Show done flash for 0.8s, then hide
DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
    self?.hideRecordingOverlay()
}

// Idle transition still fires at 1.5s (longer than hide, no conflict)
DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
    if self?.appState.phase == .done {
        self?.appState.phase = .idle
    }
}
```

The overlay hides at t+0.8s; the phase returns to `.idle` at t+1.5s. No overlap because the window is already hidden before idle fires. The sequence is clean.

### Pattern 6: Four Visual State Designs

Each state must be visually distinct without labels being the only differentiator:

| State | Visual Signal | Color | Icon/Shape |
|-------|--------------|-------|------------|
| idle | Dim mic icon, low opacity | softBlueWhite @ 50% | SF Symbol: `mic` (not filled) |
| recording | Live waveform Canvas + pulsing dot | vibrantBlue | Waveform + red/blue dot |
| transcribing | Rotating arc spinner | vibrantBlue gradient | ProgressView or arc trim |
| done | Checkmark + brief green tint or full-blue pill | softBlueWhite | SF Symbol: `checkmark.circle.fill` |

**Idle state visibility:** The overlay window is currently shown only for recording/transcribing/done. Phase 3 can choose to hide idle (window orderOut) or show a dim idle pill. The success criteria say "overlay appears as a pill... positioned at bottom-center" and "each of the four states renders a distinct appearance." The most natural reading: the window is shown for all active states (recording, transcribing, done) and hidden at idle. The idle visual only needs to exist in the SwiftUI view for completeness/preview purposes. The `showRecordingOverlay()` is called at `startRecording()` so idle → recording transition occurs off-screen (window appears already in recording state). This is acceptable.

### Anti-Patterns to Avoid

- **ForEach inside Canvas:** Canvas is not a SwiftUI view container — you cannot place SwiftUI views inside the drawing closure with `ForEach`. Use a Swift `for` loop over an array.
- **repeatForever inside state branches:** The existing spinner and pulse use `.repeatForever`. If placed in the ZStack branch for `.transcribing`, they will continue when the branch is no longer active. Use the established phase-gated pattern from FNDTN-04: start animation in `onChange(of: appState.phase)` when the phase enters, stop when it exits.
- **Hardcoded window size:** The window `contentRect` is set once at creation time but `setFrame(_:display:)` is called on every `showRecordingOverlay()`. Use `setFrame` to reposition on every show, not just creation.
- **ultraThinMaterial on dark overlay:** `.ultraThinMaterial` looks great in light mode but washes out the blue palette in dark mode. Use `DesignSystem.Colors.deepNavy.opacity(0.92)` for consistent rendering across appearances.
- **ZStack transition artifacts:** Without `zIndex` modifiers, disappearing views in a ZStack can render above appearing views during a crossfade. Assign `zIndex(1)` to the active state's view.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Pill background shape | Custom path with large corner radius | `Capsule()` shape | Capsule is mathematically correct, resizes correctly |
| Spring animation from scratch | Custom easing functions | `.spring(duration:bounce:)` | Physics-based, interruption-safe, macOS 13+ |
| Bar chart waveform views | `ForEach` + separate `View` per bar | Canvas single-pass | 30 View instances vs 1 Canvas = less layout overhead |
| Gradient in Canvas | UIKit-style CGGradient setup | `context.fill(path, with: .linearGradient(...))` | Canvas GraphicsContext supports gradients natively |

---

## Common Pitfalls

### Pitfall 1: Done State Never Shown (Critical)
**What goes wrong:** `hideRecordingOverlay()` is called on line 231 of `AppDelegate.swift` simultaneously with `phase = .done`. The done state flash never renders.
**Why it happens:** Existing code treats done as "finished — clean up immediately."
**How to avoid:** Remove the `hideRecordingOverlay()` from the immediate done block; schedule it at +0.8s via `asyncAfter`. See Pattern 5.
**Warning signs:** If the overlay disappears the moment transcription completes with no checkmark/done visual, this was not fixed.

### Pitfall 2: Window Resize Not Triggered
**What goes wrong:** The `recordingWindow` is created once with a fixed `contentRect` and never resized. When the pill design is taller or shorter than the original 80pt rectangle, the window clips content.
**Why it happens:** `if recordingWindow == nil` guard means the window is created once with hardcoded dimensions.
**How to avoid:** Call `recordingWindow?.setFrame(...)` inside `showRecordingOverlay()` outside the `nil` guard, so it repositions and resizes on every activation.

### Pitfall 3: Spring Animation Not Applied to Transitions
**What goes wrong:** Adding `withAnimation(.spring(...))` in AppDelegate does not animate the view content — it only animates AppKit-level changes. SwiftUI spring transitions on ZStack branches require the `.animation(_:value:)` modifier on the view hierarchy.
**Why it happens:** Confusion between AppKit animation context and SwiftUI animation context.
**How to avoid:** Attach `.animation(.spring(duration: 0.35, bounce: 0.1), value: appState.phase)` to the ZStack in RecordingOverlayView. Do not rely on AppDelegate's `withAnimation`.

### Pitfall 4: repeatForever Leak on Transcribing Spinner
**What goes wrong:** If the spinner's `rotation` animation is started with `.repeatForever` in `onAppear` or `onChange`, it continues running after the transcribing branch is no longer visible (SwiftUI keeps the view in the rendering tree briefly during the exit transition).
**Why it happens:** SwiftUI holds the leaving branch alive during its exit transition.
**How to avoid:** Use the FNDTN-04 phase-gating pattern: stop the animation explicitly in `.onChange(of: appState.phase)` when the phase is no longer `.transcribing`. Use `withAnimation(.linear(duration: 0)) { rotation = 0 }` to snap-stop it.

### Pitfall 5: Multi-Monitor Positioning
**What goes wrong:** `NSScreen.main` is the screen with the menu bar, not the screen with the active window. On a dual-monitor setup, the overlay may appear on the wrong screen.
**Why it happens:** `NSScreen.main` is not always the "active" screen.
**How to avoid:** This is a known blocker from STATE.md. The decision for Phase 3 is to use `NSScreen.main` (simpler), accepting the limitation. Document this as a known limitation. Multi-monitor improvements are post-v1.1.

---

## Code Examples

Verified patterns from official and authoritative sources:

### Canvas Waveform Bar Pass
```swift
// Source: swiftwithmajid.com/2023/04/11/mastering-canvas-in-swiftui/ + Apple Canvas docs
Canvas { context, size in
    let count = levels.count
    guard count > 0 else { return }
    let gap: CGFloat = 2
    let barWidth = (size.width - gap * CGFloat(count - 1)) / CGFloat(count)

    for (i, level) in levels.enumerated() {
        let barHeight = max(3, CGFloat(level) * size.height)
        let x = CGFloat(i) * (barWidth + gap)
        let y = (size.height - barHeight) / 2
        context.fill(
            Path(roundedRect: CGRect(x: x, y: y, width: barWidth, height: barHeight),
                 cornerRadius: 2),
            with: .color(DesignSystem.Colors.vibrantBlue)
        )
    }
}
```

### Spring Animation Attachment
```swift
// Source: WWDC23 "Animate with Springs" — duration/bounce parameters
ZStack {
    // ... state branches
}
.animation(.spring(duration: 0.35, bounce: 0.1), value: appState.phase)
```

### Capsule Background
```swift
// Source: Apple SwiftUI Capsule documentation
.background(
    Capsule()
        .fill(DesignSystem.Colors.deepNavy.opacity(0.92))
        .shadow(color: .black.opacity(0.3), radius: 12, x: 0, y: 6)
)
```

### NSWindow Bottom-Center Positioning
```swift
// Source: NSScreen.visibleFrame documentation + existing AppDelegate pattern
if let screen = NSScreen.main {
    let f = screen.visibleFrame
    let w: CGFloat = 280
    let h: CGFloat = 52
    recordingWindow?.setFrame(
        NSRect(x: f.midX - w / 2, y: f.minY + 32, width: w, height: h),
        display: true
    )
}
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `.spring(response:dampingFraction:)` | `.spring(duration:bounce:)` | WWDC23 (macOS 14+) | More intuitive parameters; both work on macOS 14 |
| Individual Shape views per bar | Canvas single-pass | macOS 12+ | Less view allocation; required by OVLAY-04 |
| RoundedRectangle(cornerRadius:16) | Capsule() | Phase 3 | Pill/stadium shape, mathematically correct |

**Deprecated/outdated in this phase:**
- `WaveformView` (ForEach+WaveformBar): replaced by Canvas
- `CircularWaveformView`: not used in new pill design, can be removed
- `FullScreenRecordingOverlay`: not used, can be removed
- `.ultraThinMaterial` background on overlay: replaced by deepNavy fill

---

## Open Questions

1. **Idle state visibility**
   - What we know: Overlay is shown only when recording starts, hidden on idle
   - What's unclear: Should the idle branch even render, or just leave window hidden?
   - Recommendation: Keep idle branch for preview completeness; window stays hidden at idle (no behavior change from current). The OVLAY-02 "4 distinct states" requirement applies to what a user can see during a session, not that idle must be actively displayed as a floating window.

2. **Done state visual design**
   - What we know: It must be distinct; flash for 0.8s
   - What's unclear: Exact color / icon — checkmark on blue, or success-green tint?
   - Recommendation: Use `DesignSystem.Colors.softBlueWhite` text + `checkmark.circle.fill` SF Symbol on `deepNavy` background. Avoid adding a new green to DesignSystem unless user specifically requests it.

3. **Window borderless hit-test**
   - What we know: `ignoresMouseEvents = true` is already set
   - What's unclear: Does `ignoresMouseEvents` survive `orderFront`/`orderOut` cycles?
   - Recommendation: Verify in first manual test. If not, re-set `ignoresMouseEvents = true` inside `showRecordingOverlay()` on every show.

---

## Validation Architecture

> `workflow.nyquist_validation` is absent in `.planning/config.json` — treated as enabled.

### Test Framework

| Property | Value |
|----------|-------|
| Framework | None detected — this is a macOS SwiftUI app with no XCTest suite in the project |
| Config file | None — Wave 0 gap |
| Quick run command | Manual: build and run in Xcode, exercise all 4 states |
| Full suite command | Manual verification per ROADMAP.md success criteria |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| OVLAY-01 | Overlay is Capsule at bottom-center | manual-only | visual inspection during recording | N/A |
| OVLAY-02 | 4 states visually distinct | manual-only | exercise all 4 phases; observer can identify each | N/A |
| OVLAY-03 | Spring transitions, no abrupt cuts | manual-only | observe state changes during live session | N/A |
| OVLAY-04 | Canvas waveform replaces ForEach bars | code review | grep `ForEach` in RecordingOverlayView.swift — must return no match | N/A |

**Justification for manual-only:** SwiftUI view rendering and spring animation fidelity cannot be verified with unit tests without a full UI testing framework (XCUITest). The project has no test target. Adding XCUITest is out of scope for Phase 3. OVLAY-04 has a mechanical code-review check: the `WaveformView`/`WaveformBar` structs and `ForEach(0..<barCount)` call must be absent from RecordingOverlayView.swift after the phase.

### Wave 0 Gaps

- [ ] No XCTest target exists — not required for Phase 3, but noted
- Manual verification protocol: build → hold Fn → observe recording state → release → observe transcribing → wait for done flash → confirm hide at 0.8s

*(Adding a test target is out of scope — Phase 3 verifies via manual ROADMAP.md success criteria)*

---

## Sources

### Primary (HIGH confidence)
- Apple Developer Documentation — Capsule shape: https://developer.apple.com/documentation/swiftui/capsule
- Apple Developer Documentation — Canvas view: https://developer.apple.com/documentation/swiftui/canvas
- Apple WWDC23 "Animate with Springs" session: https://developer.apple.com/videos/play/wwdc2023/10158/
- Existing source code: `FlowSpeech/AppDelegate.swift`, `FlowSpeech/Views/RecordingOverlayView.swift`, `FlowSpeech/FlowSpeechApp.swift`, `FlowSpeech/DesignSystem.swift`

### Secondary (MEDIUM confidence)
- Swift with Majid — Mastering Canvas in SwiftUI (2023): https://swiftwithmajid.com/2023/04/11/mastering-canvas-in-swiftui/
- SwiftDevNotes — Better performance with Canvas in SwiftUI: https://swdevnotes.com/swift/2022/better-performance-with-canvas-in-swiftui/
- Hacking with Swift — Spring animations: https://www.hackingwithswift.com/quick-start/swiftui/how-to-create-a-spring-animation

### Tertiary (LOW confidence)
- None relied upon for critical claims

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no new dependencies; all APIs verified in existing codebase or Apple docs
- Architecture: HIGH — derived from direct source code audit of AppDelegate.swift and RecordingOverlayView.swift
- Pitfalls: HIGH — critical done-state bug is directly visible in AppDelegate.swift line 231; other pitfalls derived from established FNDTN-04 patterns

**Research date:** 2026-03-26
**Valid until:** 2026-06-26 (stable SwiftUI/AppKit APIs — unlikely to change in 90 days)
