# Project Research Summary

**Project:** SpeechFlow v1.1 — UI Revamp, App Exclusion, Clipboard Persistence
**Domain:** macOS menu bar push-to-talk dictation app — incremental v1.1 milestone
**Researched:** 2026-03-26
**Confidence:** HIGH

## Executive Summary

SpeechFlow v1.1 is a well-scoped incremental milestone on top of a working v1.0 foundation. The app already has the correct architecture — SwiftUI/AppKit hybrid, service-oriented layer, ObservableObject state — so this milestone is about adding four capabilities, not rebuilding. Every required feature maps cleanly to native Apple frameworks with no third-party dependencies needed: NSWorkspace for app exclusion, CGWindowListCopyWindowInfo for fullscreen detection, NSPasteboard for clipboard persistence, and SwiftUI animation APIs for the overlay redesign. The recommended approach is to build in dependency order: design system first, then state machine refactor, clipboard persistence, overlay redesign, and finally app exclusion with its Settings UI.

The central pattern is replacing dual `isRecording`/`isTranscribing` booleans with a single `RecordingPhase` enum — this unblocks all animation work and eliminates impossible boolean states. The "Flow Bar" pill overlay at bottom-center is the established pattern in this category (Wispr Flow uses this exact layout), and it's achievable with a handful of changes to window positioning and shape. The blue palette identity is pure design work requiring a new `DesignSystem.swift` constants file that all UI targets reference.

The most consequential risks are operational rather than conceptual. CGEventTap silent disabling after code signing is a known macOS pitfall that can make the entire app appear broken post-build without any logged error. Animation timers running when the overlay is hidden will drain CPU across many sessions. Game/fullscreen detection via window geometry alone produces false positives on fullscreen Xcode or Terminal — the correct approach pairs an explicit user-configurable bundle ID list as the primary signal with geometry detection as a fallback. All five critical pitfalls have documented prevention strategies and must be addressed in the phase they appear, not patched later.

---

## Key Findings

### Recommended Stack

All capability additions use native Apple system frameworks already imported in the codebase. No package manager changes are needed. The key additions are `NSWorkspace.didActivateApplicationNotification` (push-based app change observation, zero polling cost), `CGWindowListCopyWindowInfo` (fullscreen geometry detection, no Screen Recording permission needed for bounds-only), and SwiftUI `TimelineView` + `Canvas` for high-performance waveform rendering. The waveform is the one place where the existing `ForEach`-over-structs approach causes real performance problems at 20-30fps update rates; `Canvas` eliminates this with a single draw call per frame.

The minimum macOS version is unspecified in PROJECT.md. The recommended baseline is macOS 13 (Ventura) — this excludes `PhaseAnimator` (macOS 14 only) but includes `TimelineView`, `Canvas`, and all AppKit APIs needed. If the team confirms macOS 14 minimum, `PhaseAnimator` becomes available and simplifies the animation state machine.

**Core technologies:**
- `NSWorkspace.didActivateApplicationNotification`: Push-based frontmost app change observation — zero-cost when no switch occurs; already partially used in codebase
- `CGWindowListCopyWindowInfo`: Fullscreen detection for other processes — compare `kCGWindowBounds` against `NSScreen.main.frame`; no special permissions needed for bounds
- `TimelineView(.animation) + Canvas`: Waveform rendering at 20-30fps — replaces `ForEach` over `WaveformBar` views; eliminates SwiftUI diffing overhead
- `NSWindow.Level.statusBar + .fullScreenAuxiliary`: Overlay visibility in all contexts — required for overlay to appear above macOS Spaces fullscreen apps
- `withAnimation(.spring(duration:bounce:))`: State transition animations — available macOS 12+; covers all required animation needs without third-party libraries
- `@AppStorage` with JSON-encoded `[String]`: Exclusion list persistence — consistent with existing UserDefaults patterns in the codebase

### Expected Features

The v1.1 milestone has six must-ship features, all P1. The dependency graph is well-defined: pill overlay and animations require the `RecordingPhase` enum; clipboard persistence is independent; game exclusion requires both HotkeyManager integration and a new Settings tab.

**Must have (table stakes for this milestone):**
- Pill overlay at bottom-center — replaces current top-positioned floating window; Wispr Flow's "Flow Bar" has established this as the expected pattern
- Four-state visual progression (idle/recording/transcribing/done) — users need to know the app heard them and is working; distinct visual for each state
- Spring animations on all state transitions — abrupt appearance and state changes feel broken; `.spring(duration: 0.4, bounce: 0.25)` is the correct API
- Clipboard persistence toggle — the current 0.5s restore is a real v1.0 bug that actively loses user clipboard content; default ON
- Game/fullscreen exclusion — hotkey conflicts in fullscreen games (League of Legends) are the primary reported user pain point; suppression must happen before recording starts
- Blue palette applied throughout — `DesignSystem.swift` constants used by overlay, menu bar, settings

**Should have (P2, ship if time permits):**
- "Add current app" button in exclusion settings — reads frontmost bundle ID in one click; reduces friction significantly
- Bundle ID exclusion list UI with list display — manual text entry works but a list view is much better UX

**Defer to v2+:**
- Notch integration — only meaningful for MacBook Pro 2021+; universal bottom-center pill works for all Macs
- Waveform amplitude tracking from mic buffer — decorative animated bars satisfy the UX need; real amplitude requires AVAudioEngine tap changes
- macOS 16 pasteboard privacy handling — not broadly shipped; revisit when macOS 16 releases

### Architecture Approach

The existing service-oriented architecture requires no structural changes — only targeted modifications to existing components and two new files (`AppExclusionService.swift`, `DesignSystem.swift`) plus one new view (`ExclusionListView.swift`). The most impactful change is adding `RecordingPhase` enum to `AppState` and deriving `isRecording`/`isTranscribing` from it, which is a backward-compatible refactor with approximately six call sites to update. `TextInserter` needs its clipboard-write operation separated from the paste operation — the write should always happen, paste is conditional on `autoInsertText` setting.

**Major components and changes:**
1. `AppState` — add `recordingPhase: RecordingPhase`, `excludedAppBundleIDs: [String]`, `excludeFullscreenApps: Bool`
2. `AppExclusionService` (new) — encapsulates `isFrontmostAppExcluded()` and `isAppFullscreen()` with `Set<String>` lookup for O(1) exclusion check; reads UserDefaults directly (thread-safe for reads from CGEventTap callback)
3. `DesignSystem.swift` (new) — color constants, spacing, typography; referenced by all UI files
4. `RecordingOverlayView` (redesign) — pill shape via `Capsule()`, bottom-center positioning, phase-driven rendering via `switch appState.recordingPhase`, spring transitions
5. `TextInserter` — remove clipboard restore block; split into `placeOnClipboard()` + `simulatePaste()`
6. `AppDelegate` — add exclusion check before `startRecording()`, alpha fade animations on overlay show/hide, `showCompletionBriefly()` for 0.8s done-state flash
7. `SettingsView` + `ExclusionListView` (new) — 6th settings tab for exclusion list management

### Critical Pitfalls

1. **NSWindow level blocks overlay in fullscreen Spaces** — Use `.statusBar` level with `[.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]`. Must be set from the start of Phase 1; patching it later is much harder. Separate game exclusion (suppress hotkey) from overlay layering (overlay visible in non-game fullscreen) as distinct problems.

2. **CGEventTap silent disable after code signing** — Non-nil `eventTap` is not proof the tap is functional. Add `CGEvent.tapIsEnabled(tap:)` health check on a 2-second timer. If disabled and re-enable fails, surface an error in the menu bar icon. Address before shipping any UI that might trigger TCC re-evaluation.

3. **Clipboard race condition with restore** — Current 0.5s restore can overwrite the user's new copy. Add `changeCount` guard: capture `pasteboard.changeCount` before write, skip restore if count has advanced. Add `org.nspasteboard.TransientType` marker so clipboard managers don't log transcriptions.

4. **Game/fullscreen detection false positives** — CGWindow frame comparison alone will suppress dictation in fullscreen Xcode, Terminal, Safari. Use bundle ID exclusion list as the primary signal (explicit, no false positives) and geometry detection as an opt-in secondary. Never trigger suppression on geometry alone by default.

5. **Animation timers running on hidden overlay** — `withAnimation(.repeatForever)` started in `.onAppear` continues executing after `orderOut(nil)`. Gate all animations on a `@State var isVisible` flag. Verify CPU usage is <1% between sessions in Activity Monitor before shipping.

---

## Implications for Roadmap

Based on the dependency graph and pitfall-to-phase mapping, the research converges on a clean four-phase build order. All four research files agree on this ordering independently.

### Phase 1: Foundation — Design System + State Machine + Animation Architecture

**Rationale:** Everything else depends on `RecordingPhase` enum and `DesignSystem.swift`. The two most dangerous pitfalls (CGEventTap silent disable, animation CPU drain) must be addressed here before UI work begins, because UI reconstruction triggers TCC re-evaluation and animation architecture is much harder to add after the overlay is designed.

**Delivers:** `DesignSystem.swift` with blue palette constants; `RecordingPhase` enum in `AppState`; backward-compatible derivation of `isRecording`/`isTranscribing`; CGEventTap health check timer; animation gating via `isVisible` flag on overlay; `.fullScreenAuxiliary` window collection behavior.

**Addresses:** Visible state progression (table stakes), blue palette identity (differentiator)

**Avoids:** CGEventTap silent disable (Pitfall 2), animation CPU drain (Pitfall 5), NSWindow level conflict (Pitfall 1)

**Research flag:** Standard patterns — no additional research needed. All APIs are native AppKit/SwiftUI.

### Phase 2: Clipboard Persistence

**Rationale:** Independent of overlay redesign and exclusion. Small, high-value, fixes a real v1.0 bug. Ship early to validate that the clipboard architecture is correct before building more on top of TextInserter.

**Delivers:** `placeOnClipboard()` / `simulatePaste()` separation in `TextInserter`; `org.nspasteboard.TransientType` marker; `changeCount` race condition guard; Settings toggle for persistence behavior; transcription available on clipboard even when `autoInsertText` is off.

**Addresses:** Clipboard persistence (P1 table stakes)

**Avoids:** Clipboard race condition (Pitfall 3), clipboard manager logging issue

**Research flag:** Standard patterns — well-documented NSPasteboard behavior. No additional research needed.

### Phase 3: Overlay Redesign + Animations

**Rationale:** Depends on `RecordingPhase` (Phase 1) and must be built after the state machine is in place. This is the largest UI surface — pill shape, bottom positioning, phase-driven rendering, spring animations, alpha fade, done-state flash. Doing this after clipboard persistence means one fewer variable when testing the redesign.

**Delivers:** `RecordingOverlayView` redesigned with `Capsule()` pill, bottom-center positioning via `NSScreen.main?.visibleFrame`, `switch appState.recordingPhase` rendering, `TimelineView` + `Canvas` waveform, `NSAnimationContext` alpha fade on show/hide, 0.8s done-state flash via `showCompletionBriefly()`.

**Addresses:** Pill overlay at bottom-center (P1), four-state visual progression (P1), spring animations (P1), blue palette on overlay (P1)

**Avoids:** Animation timers on hidden overlay (Pitfall 5, already gated in Phase 1)

**Research flag:** Standard patterns — SwiftUI animation APIs are well-documented. May want to validate `TimelineView` + `Canvas` performance on macOS 13 if targeting Ventura minimum.

### Phase 4: App Exclusion + Settings UI

**Rationale:** Most complex feature — requires new service, new UI, and integration with HotkeyManager callback path. Building last avoids its Settings tab work being blocked by UI churn from Phase 3. The CGWindowListCopyWindowInfo path needs targeted testing on multiple window configurations.

**Delivers:** `AppExclusionService.swift` with `isFrontmostAppExcluded()` and `isAppFullscreen()` using `Set<String>` for O(1) lookup; exclusion check in `AppDelegate.handleFlagsChanged()` before `startRecording()`; `ExclusionListView.swift`; 6th Settings tab; default exclusion list including `com.riotgames.LeagueofLegends`; auto-detect fullscreen toggle (opt-in, default off to avoid false positives).

**Addresses:** Game/fullscreen exclusion (P1), bundle ID exclusion list UI (P2)

**Avoids:** Game detection false positives (Pitfall 4), AXUIElement fullscreen detection anti-pattern

**Research flag:** Needs careful testing. `CGWindowListCopyWindowInfo` behavior changed in macOS 26 (all status items attributed to Control Center per FB18327911). Test exclusion list against: League of Legends bundle IDs, fullscreen Safari, fullscreen Xcode, and fullscreen Terminal — all should behave correctly.

### Phase Ordering Rationale

- `DesignSystem.swift` and `RecordingPhase` enum are pure prerequisites — nothing else can be built correctly without them
- Clipboard persistence is the most isolated feature; early shipping validates the TextInserter refactor independently
- Overlay redesign cannot start until phase-driven state exists to render against
- App exclusion has the most test surface (edge cases with different apps and macOS versions) so it benefits from being last when the team has full project context
- All five critical pitfalls map to Phase 1 (3 pitfalls) or Phase 3-4 (1 pitfall each); addressing them in-phase rather than as post-hoc fixes is the research recommendation

### Research Flags

Phases needing deeper research during planning:
- **Phase 4 (App Exclusion):** The `CGWindowListCopyWindowInfo` regression in macOS 26 (FB18327911 — status items attributed to Control Center) needs validation on the actual target OS. If the team is shipping for macOS 15+, confirm the bounds-comparison path still works. The League of Legends bundle ID split (`com.riotgames.LeagueofLegends.LeagueClientUx` for client vs `com.riotgames.LeagueofLegends` for game process) needs hands-on verification.

Phases with standard patterns (skip research-phase):
- **Phase 1 (Foundation):** CGEventTap health check, RecordingPhase enum, window collection behavior — all well-documented in official Apple docs and confirmed in codebase read.
- **Phase 2 (Clipboard Persistence):** NSPasteboard change count, TransientType marker — fully documented at nspasteboard.org and Apple developer docs.
- **Phase 3 (Overlay Redesign):** SwiftUI spring animations, TimelineView + Canvas — WWDC23 documented, stable APIs. macOS 13 vs 14 compatibility is the only decision point (PhaseAnimator availability).

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All APIs are native Apple frameworks verified against official docs and the existing codebase. No third-party dependencies introduced. Version compatibility table fully documented in STACK.md. |
| Features | MEDIUM | Table stakes and must-have features are HIGH confidence based on competitor analysis (Wispr Flow, Superwhisper) and Apple HIG patterns. Competitor internals (their exact exclusion implementation) are LOW confidence — not publicly documented. |
| Architecture | HIGH | Architecture research read the actual codebase directly. All component boundaries, modification scopes, and integration points verified against existing Swift files. Build order is dependency-driven, not speculative. |
| Pitfalls | HIGH for clipboard/CGEventTap (well-documented, multiple sources), MEDIUM for game/fullscreen detection (platform-specific edge cases, one known macOS 26 regression) | |

**Overall confidence:** HIGH

### Gaps to Address

- **macOS minimum version:** PROJECT.md does not specify. The choice between macOS 13 (excludes `PhaseAnimator`) and macOS 14 (enables `PhaseAnimator`) affects Phase 3 animation implementation. Decide before Phase 1 begins. Recommendation: macOS 13 (Ventura) for broadest reach; use manual `RecordingPhase` state machine instead of `PhaseAnimator`.
- **CGWindowListCopyWindowInfo on macOS 26:** The known regression (FB18327911) attributes all status bar items to Control Center. Need to validate whether the `kCGWindowOwnerPID` filter path used for fullscreen detection is affected. This is specific to macOS 26 beta and may be resolved before general availability.
- **Multi-monitor overlay positioning:** The research recommends bottom-center of `NSScreen.main` but the user may be working on a secondary monitor. PITFALLS.md flags this in the "Looks Done But Isn't" checklist. A follow-up decision: use `NSScreen.main` (simpler) or detect the screen containing the active window via AX API (correct but more complex).
- **League of Legends bundle ID verification:** The research identifies `com.riotgames.LeagueofLegends` (game) and `com.riotgames.LeagueofLegends.LeagueClientUx` (client) as the relevant bundle IDs. Both should be in the default exclusion list, but this needs hands-on confirmation.

---

## Sources

### Primary (HIGH confidence)
- Apple Developer Documentation — NSWorkspace, NSRunningApplication, CGWindowListCopyWindowInfo, NSPasteboard, NSWindow, SwiftUI animation APIs
- WWDC23 Session 10157 "Wind your way through advanced animations in SwiftUI" — PhaseAnimator, KeyframeAnimator introduction
- WWDC23 Session 10158 "Animate with Springs" — spring(duration:bounce:) API
- Direct codebase analysis: AppDelegate.swift, TextInserter.swift, HotkeyManager.swift, RecordingOverlayView.swift, FlowSpeechApp.swift (all read 2026-03-26)
- Apple Developer Forums thread/792917 — confirms no `isFullScreen` on NSRunningApplication; CGWindow bounds is the correct approach

### Secondary (MEDIUM confidence)
- NSPasteboard.org — TransientType and clipboard manager marker conventions
- Gertrude App blog — NSWorkspace.shared.runningApplications patterns
- Wispr Flow changelog — Flow Bar positioning and interaction model (competitor analysis)
- Superwhisper changelog — animation and overlay design patterns
- NSHostingView Sequoia centering changes — Furnace Creek Software (2024-12-07)
- Daniel Raffel — CGEvent Taps and Code Signing: The Silent Disable Race (2026-02-19)

### Tertiary (LOW confidence)
- FB18327911: CGWindowListCopyWindowInfo regression in macOS 26 — needs validation; filed as feedback, not confirmed fixed
- Competitor exclusion feature internals (Wispr Flow, Superwhisper) — not publicly documented; inferred from behavior

---
*Research completed: 2026-03-26*
*Ready for roadmap: yes*
