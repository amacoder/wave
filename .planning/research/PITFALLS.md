# Pitfalls Research

**Domain:** macOS SwiftUI menu bar dictation app — UI revamp, game exclusion, clipboard persistence, animation polish
**Researched:** 2026-03-26
**Confidence:** HIGH for clipboard/CGEventTap pitfalls (well-documented); MEDIUM for game/fullscreen detection (platform-specific, edge cases vary)

---

## Critical Pitfalls

### Pitfall 1: NSWindow Level Conflict — Overlay Disappears Behind Fullscreen Apps

**What goes wrong:**
The current overlay uses `.floating` window level with `[.canJoinAllSpaces, .stationary, .ignoresCycle]` collection behavior. This combination causes the window to either (a) fail to appear above apps running in their own fullscreen Space, or (b) appear but be obscured by Metal/Quartz exclusive fullscreen games. Users in fullscreen apps — including the primary target user playing League of Legends — see nothing when they dictate.

**Why it happens:**
macOS fullscreen apps run in a dedicated Space. `.floating` level does not cross Space boundaries without `NSWindowCollectionBehaviorFullScreenAuxiliary`. Even with that flag added, games using exclusive Metal fullscreen (not macOS Spaces fullscreen) bypass the normal window layering entirely — they own a CGDirectDisplay surface directly.

**How to avoid:**
Add `.fullScreenAuxiliary` to the window's `collectionBehavior` when showing the overlay. For the game exclusion feature, the correct solution is to suppress the hotkey entirely when a game is in focus — do NOT attempt to show the overlay above an exclusive-fullscreen game. Treat exclusion and overlay layering as two separate problems.

The overlay behavior should be:
```swift
recordingWindow?.collectionBehavior = [
    .canJoinAllSpaces,
    .stationary,
    .ignoresCycle,
    .fullScreenAuxiliary  // ADD THIS — required for macOS Spaces fullscreen
]
// For overlay level, use .statusBar or higher for non-game fullscreen
// Do NOT attempt .screenSaver level — blocked by sandboxing in most cases
```

**Warning signs:**
- QA test in macOS Spaces fullscreen (Safari, or any app clicked to fullscreen via green button) and the overlay doesn't appear
- Overlay appears but overlaps a different monitor than the one with the fullscreen app
- User reports recording starts (sound plays) but no indicator is visible

**Phase to address:** Phase 1 — UI Revamp (any window reconstruction must include this flag from the start, not patched in later)

---

### Pitfall 2: CGEventTap Silently Disabled — Hotkeys Stop Working After Code Signing or Update

**What goes wrong:**
After re-signing the binary (e.g., build after any code change), the CGEventTap in `HotkeyManager` creates successfully (non-nil return), but events never fire. The tap is "installed" but functionally inert. This is especially likely to manifest after any accessibility permission interaction caused by UI changes triggering a TCC re-evaluation.

**Why it happens:**
macOS TCC (Transparency, Consent, and Control) ties the accessibility permission grant to the code signature identity. When the binary is re-signed — even with the same certificate — it can trigger re-evaluation. The tap creation API (`CGEvent.tapCreate`) returns a non-nil `CFMachPort` even when the underlying access is not yet confirmed, making success look identical to failure. The existing check `guard let eventTap = eventTap else { ... }` only catches total nil failures, not silent inert taps.

Additionally, if the app's UI changes affect the permission prompt flow (onboarding changes, settings window changes) and the user dismisses a stale prompt, the tap can be left in a disabled state with no error delivered to the callback.

**How to avoid:**
1. Never treat non-nil `eventTap` as healthy. Always verify with `CGEvent.tapIsEnabled(tap:)` after installation.
2. Add a health-check timer that fires every 2-3 seconds and calls `CGEvent.tapIsEnabled(tap:)`. If the tap is disabled, attempt to re-enable it. If re-enable fails, set an app state error flag and update the menu bar icon.
3. On any code change that might affect TCC, remove the app from System Settings > Privacy & Security > Accessibility and re-add it.

```swift
// Health check pattern
private func installTapHealthCheck() {
    Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
        guard let tap = self?.hotkeyManager.eventTap else { return }
        if !CGEvent.tapIsEnabled(tap: tap) {
            CGEvent.tapEnable(tap: tap, enable: true)
            if !CGEvent.tapIsEnabled(tap: tap) {
                // Permission revoked — show error in menu bar
                self?.appState.errorMessage = "Input monitoring permission revoked. Check System Settings."
            }
        }
    }
}
```

**Warning signs:**
- Hotkey works on first launch after permission grant, then stops after a clean build and relaunch
- `HotkeyManager.start()` prints no error but key events never fire
- Works when launched from Xcode but not from Finder/Dock after archive

**Phase to address:** Phase 1 — UI Revamp (UI reconstruction often triggers TCC re-evaluation; add health check before any other features)

---

### Pitfall 3: Clipboard Race Condition — Transcription Overwrites Another App's Content, Then Restores Wrong Value

**What goes wrong:**
`TextInserter.insertText(_:)` saves `oldContent`, sets transcription on clipboard, pastes via CGEvent, then restores `oldContent` after 0.5 seconds. Three race conditions exist:

1. **User copies something between transcription completion and the 0.5s restore** — the restore overwrites the user's new copy.
2. **Another app (clipboard manager, password manager) reads the clipboard mid-operation** — it logs the transcription as user-copied data.
3. **The async DispatchQueue.main.asyncAfter fires after the window is deallocated** — memory access on cleared pasteboard object.

For clipboard persistence mode (new feature: don't restore), the restore is intentionally skipped. But the current code structure always restores if `oldContent != nil`, meaning the new "persistence" behavior requires a separate code path that could easily regress.

**How to avoid:**
1. Mark the clipboard write with `org.nspasteboard.TransientType` so clipboard managers skip it:
```swift
pasteboard.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
pasteboard.setString(text, forType: .string)
```
2. Capture a `changeCount` snapshot before writing. In the restore block, check if `changeCount` has advanced — if it has, the user or another app wrote something new, so skip the restore:
```swift
let changeCountSnapshot = pasteboard.changeCount
DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
    guard pasteboard.changeCount == changeCountSnapshot + 1 else { return } // Someone else wrote
    if let old = oldContent {
        pasteboard.clearContents()
        pasteboard.setString(old, forType: .string)
    }
}
```
3. For clipboard persistence mode: use a `UserDefaults`-backed flag checked synchronously in `insertText`, not a conditional in a completion block. This prevents the conditional from being wrong after a settings change mid-operation.

**Warning signs:**
- User reports losing clipboard content after dictation
- Clipboard manager (e.g., Maccy, Pasta) logs every transcription in history
- Clipboard restore fires after user has already pasted something else

**Phase to address:** Phase 3 — Clipboard Persistence (the feature directly changes this code path; do both the persistence flag and the changeCount guard together)

---

### Pitfall 4: Game/Fullscreen Detection False Positives and False Negatives

**What goes wrong:**
`CGWindowListCopyWindowInfo` with frame-size comparison to `NSScreen.main?.frame` is the intuitive approach, but produces both false positives (videos in browser, fullscreen Terminal, fullscreen Xcode) and false negatives (games using exclusive Metal fullscreen that don't register as a normal "window" in the list).

Specifically for League of Legends: the game runs on macOS via Rosetta. It can alternate between windowed, borderless windowed, and exclusive fullscreen modes based on in-game settings. The bundle ID is `com.riotgames.LeagueofLegends.LeagueClientUx` for the client but `com.riotgames.LeagueofLegends` for the game process. Detecting by window geometry alone misses the game's Rosetta-translated process.

**Why it happens:**
There is no single reliable API for "is a game running in exclusive fullscreen." `NSWindowCollectionBehavior` flags are only accessible for your own windows. For another app's windows, you're limited to `CGWindowListCopyWindowInfo` and `NSRunningApplication`. macOS Sequoia and newer versions have begun returning incorrect owner info from `CGWindowListCopyWindowInfo` (all status items attributed to Control Center).

**How to avoid:**
Use a three-signal detection approach. Require at least two of three signals to trigger exclusion to reduce false positives:

1. **App is in a known exclusion list** (user-configurable bundle IDs). Default list includes known game bundle IDs. This handles the League use case precisely.
2. **Frontmost app has a window matching screen dimensions** — `CGWindowListCopyWindowInfo` + frame comparison. Catches generic fullscreen games.
3. **App's window layer is 0 and display connection count is > 0 via `CGGetOnlineDisplayList`** — indicates exclusive display ownership.

For the user interface, the exclusion list is the primary mechanism (explicit, no false positives). Frame detection is secondary and only used for "auto-detect fullscreen" if the user enables it.

Do NOT use NSWorkspace notifications alone — `NSWorkspaceActiveSpaceDidChangeNotification` fires when spaces change, not when a game enters exclusive fullscreen within the same space.

```swift
// Primary detection: explicit bundle ID blocklist
let frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
let isExcluded = appState.excludedBundleIDs.contains(frontmostBundleID)
```

**Warning signs:**
- Hotkey suppressed in Xcode with a large editor window (false positive)
- Hotkey fires normally during League game but not during client (bundle ID mismatch)
- Detection works in testing but fails after OS update that changes CGWindowListCopyWindowInfo behavior

**Phase to address:** Phase 2 — Game/Fullscreen Exclusion

---

### Pitfall 5: Animation Timers Running When Overlay Is Hidden — CPU Drain and State Corruption

**What goes wrong:**
The current `RecordingOverlayView` uses `withAnimation(.easeInOut(duration: 1).repeatForever(...))` started in `.onAppear`. The `TranscribingView` uses a similar infinite rotation. When `hideRecordingOverlay()` calls `orderOut(nil)`, the NSWindow is hidden but the SwiftUI view remains alive and all animations continue running. Over a typical day with many dictation sessions, this accumulates:

- RepeatForever animations continue executing on the render thread
- `appState.audioLevels` updates still trigger re-renders on a hidden view
- `CircularWaveformView`'s Canvas draws on hidden windows

On macOS Sequoia (15+), NSHostingView layout is computed more lazily, which means the view hierarchy may also attempt layout passes while hidden, triggering the "reentrant layout" warning in logs.

**Why it happens:**
`orderOut(nil)` hides the window from the screen compositor but does not pause SwiftUI's rendering engine. The view's animation state machines remain active. The existing architecture reuses `recordingWindow` across sessions (created once, never deallocated), compounding the effect.

**How to avoid:**
Two options — choose based on redesign scope:

Option A (minimal change): Use an explicit `@State var isVisible: Bool` bound to `appState.isRecording || appState.isTranscribing`. Gate all animations behind this flag. Drive animation timing with `Task.sleep` or `withAnimation` that is explicitly cancelled on state change, not `repeatForever`.

Option B (recommended with UI revamp): Replace `orderOut/orderFront` with adding/removing the NSHostingView's root view entirely, or use a `TimelineView` with `.animation` that automatically pauses when not visible. The overlay view should not hold animation state across sessions.

For the waveform specifically, move audio level updates from `AppState` to a publisher that only fires when `isRecording == true` and the overlay window is visible. Avoid sending 60 updates/second to a hidden view.

**Warning signs:**
- CPU usage stays elevated (2-5% instead of ~0%) between dictation sessions
- Log shows "NSHostingView is being laid out reentrantly" during rapid session start/stop
- `WaveformBar` animations still visible briefly when overlay reappears after a hide (leftover animation state from previous session)

**Phase to address:** Phase 1 — UI Revamp (animation architecture is set during redesign; adding these guards after the fact is much harder)

---

## Technical Debt Patterns

Shortcuts that seem reasonable now but create long-term problems.

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| `usleep` calls in `TextInserter` on main thread | Simple modifier key clearing | Blocks UI thread for 50-60ms; visible stutter on fast machines | Never — replace with async dispatch + continuation |
| Hardcoded `0.5s` clipboard restore delay | Works on most machines | Fails on slow machines (paste hasn't completed); too slow on fast machines | Acceptable for v1.1 if documented as "known timing assumption" |
| Single `recordingWindow` instance (create once, never destroy) | Avoids recreation cost | Accumulates stale animation state; CGWindowListCopyWindowInfo sees it even when hidden | Acceptable only if all animations are gated on visibility flag |
| Bundle ID blocklist hardcoded to League of Legends | Solves immediate use case | Users with other games need to manually edit defaults or no UI exists | Never — provide settings UI from day one |
| `NSEvent.addGlobalMonitorForEvents` AND CGEventTap (duplicate) | Belt-and-suspenders | Two handlers both fire for the same key; can cause double-start-recording if not guarded by `modifierKeyDown` state | Acceptable as backup, but requires explicit de-duplication test |

---

## Integration Gotchas

Common mistakes when connecting to macOS system APIs.

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| CGEventTap + code signing | Treat non-nil return as success | Always verify `CGEvent.tapIsEnabled(tap:)` post-install; add runtime health check |
| NSPasteboard + clipboard managers | Write only `.string` type | Add `org.nspasteboard.TransientType` marker to prevent clipboard managers from logging transcriptions |
| NSWorkspace.frontmostApplication | Cache the value across the hotkey lifecycle | Re-query at hotkey-down time; app focus can change between monitor setup and key press |
| CGEvent Cmd+V simulation | Post with `.cgSessionEventTap` immediately after clipboard write | Add a `CGEventSource(stateID: .combinedSessionState)` source, not `.hidSystemState`, for synthetic events; the latter can confuse some apps' undo stacks |
| SwiftUI `withAnimation(.repeatForever)` | Start in `.onAppear` with no stop condition | Pair every `repeatForever` start with an explicit cancellation when the view should go idle |

---

## Performance Traps

Patterns that work initially but create problems over time.

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Audio level updates at 60Hz publishing to AppState (observed object) | Every waveform bar re-renders 60x/second; SwiftUI diffs 30 views per frame | Throttle updates to 20Hz; use `@Published` with a `.debounce` or rate-limit in `AudioRecorder.onAudioLevel` | Immediately visible; worsens with more waveform bars |
| Canvas in `CircularWaveformView` redraws on every level change | GPU work on a view that's rarely visible | Gate Canvas redraws behind a `@State isDrawing: Bool`; only set true when overlay is visible | As session frequency increases |
| CGWindowListCopyWindowInfo called on every flagsChanged event | 5-10ms stall per hotkey press on window-heavy desktops | Call only once per hotkey-down, cache result; use NSWorkspace observers for app changes | Noticeable on machines with 20+ open windows |
| NSHostingView size recalculation on Sequoia | Layout pass triggered on `orderFront` causes jitter/jump on first appearance | Pre-warm the window by calling `layoutIfNeeded()` after creation before showing | macOS 15 Sequoia and later |

---

## Security Mistakes

Domain-specific security issues.

| Mistake | Risk | Prevention |
|---------|------|------------|
| Transcribed text persists on general pasteboard indefinitely | Sensitive dictated content (passwords, private notes) readable by any app polling the pasteboard | Default behavior: use `org.nspasteboard.TransientType` marker; only disable restore if user explicitly opts into persistence |
| Excluded bundle ID list stored in plain UserDefaults | Trivially modified by any process; not a security boundary | Acceptable — this is a UX feature not a security boundary; document that the list is a user convenience not a sandbox |
| CGEventTap with `.defaultTap` consumes all key events | If the callback hangs, all keyboard input is blocked system-wide | Always return quickly from the tap callback; defer heavy work to async dispatch |

---

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| Overlay appears in same position every time (centered, fixed Y) | Covers text field user is typing into | Position overlay near the bottom-center of the screen, or detect the active text field position via AX API and offset the overlay |
| Clipboard persistence is silent — user doesn't know transcription is on clipboard | User thinks dictation failed if paste doesn't work; tries to dictate again | Show a subtle "Copied" indicator in the overlay's done-state animation |
| Game exclusion with no feedback | User holds hotkey in a game, nothing happens, doesn't know why | Show a brief menu bar notification or badge when hotkey is suppressed due to exclusion |
| Animation plays full enter sequence even on very short recordings (< 1 second) | Jarring; animation not finished when transcription already complete | Use interruptible animations; all state transitions should be cancellable mid-animation |
| Settings window uses NSApp.activate — steals focus from user's work | User is in the middle of typing; settings opens and interrupts | Open settings window without `NSApp.activate(ignoringOtherApps:)` for non-modal windows |

---

## "Looks Done But Isn't" Checklist

Things that appear complete but are missing critical pieces.

- [ ] **Game exclusion:** Often missing user-configurable exclusion list — verify Settings has UI to add/remove bundle IDs (not just hardcoded League)
- [ ] **Clipboard persistence:** Often missing `org.nspasteboard.TransientType` marker — verify Maccy or another clipboard manager does NOT log transcriptions in its history
- [ ] **CGEventTap health:** Often missing runtime tap-alive check — verify hotkey still works after 30 minutes of app running (tap can silently disable on some OS versions)
- [ ] **Animation gating:** Often missing stop conditions for `repeatForever` — verify CPU usage is < 1% when not recording (use Activity Monitor)
- [ ] **Overlay positioning on multi-monitor:** Often tested only on main screen — verify overlay appears on the screen containing the active window, not always on `NSScreen.main`
- [ ] **Clipboard restore race:** Often missing `changeCount` guard — verify clipboard content is NOT corrupted if user copies something during the 0.5s restore window
- [ ] **Fullscreen collection behavior:** Often missing `.fullScreenAuxiliary` — verify overlay appears when Safari is in macOS fullscreen Space

---

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| CGEventTap silently disabled | LOW | Remove app from Accessibility settings, re-add, relaunch. Add health-check timer to prevent recurrence. |
| Clipboard corruption from restore race | LOW | Manually re-copy what was lost; add `changeCount` guard before next release |
| Overlay missing fullscreen collection behavior | LOW | Add `.fullScreenAuxiliary` to window creation; test in Spaces fullscreen |
| RepeatForever animation CPU drain | MEDIUM | Add `isVisible` guard to all animation blocks; requires UI test to confirm fix |
| Game detection false positives blocking dictation in non-games | MEDIUM | Switch to explicit bundle ID list as primary signal; disable frame-based auto-detection by default |
| TextInserter `usleep` main thread block causing UI freeze | HIGH | Refactor to `DispatchQueue.global().async` with a completion callback; requires rethinking TextInserter's threading model |

---

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| NSWindow level / fullscreen collection behavior | Phase 1 — UI Revamp | Test overlay visibility in Safari fullscreen Space before shipping |
| CGEventTap silent disable + health check | Phase 1 — UI Revamp | Rebuild, re-sign, relaunch 3 times; hotkey must work each time |
| Animation gating (repeatForever CPU drain) | Phase 1 — UI Revamp | Activity Monitor shows < 1% CPU when idle after 3 recording sessions |
| Game detection false positives | Phase 2 — Game Exclusion | Test exclusion with League; test non-exclusion in fullscreen Xcode, Terminal, Safari |
| Clipboard changeCount race condition | Phase 3 — Clipboard Persistence | Copy text, dictate, verify original clipboard survives after 1s |
| Clipboard TransientType marker | Phase 3 — Clipboard Persistence | Maccy/clipboard manager shows no transcription in history |
| Main thread `usleep` in TextInserter | Phase 3 — Clipboard Persistence | Profiler shows no main-thread stalls during text insertion |

---

## Sources

- [CGEvent Taps and Code Signing: The Silent Disable Race — Daniel Raffel (2026-02-19)](https://danielraffel.me/til/2026/02/19/cgevent-taps-and-code-signing-the-silent-disable-race/)
- [Identifying and Handling Transient or Special Data on the Clipboard — NSPasteboard.org](http://nspasteboard.org/)
- [Fullscreen Detection — Apple Developer Forums](https://developer.apple.com/forums/thread/792917)
- [Fullscreen Detection using Core Graphics — Apple Developer Forums](https://developer.apple.com/forums/thread/779272)
- [Window visible on all spaces including fullscreen apps — Apple Developer Forums](https://developer.apple.com/forums/thread/26677)
- [Accessibility Permission in macOS — jano.dev (2025-01-08)](https://jano.dev/apple/macos/swift/2025/01/08/Accessibility-Permission.html)
- [FB18327911: CGWindowListCopyWindowInfo returns all status items as Control Center in macOS 26](https://github.com/feedback-assistant/reports/issues/679)
- [NSPasteboard changeCount — Apple Developer Documentation](https://developer.apple.com/documentation/appkit/nspasteboard/1533544-changecount)
- [Bridging SwiftUI and Core Animations — Cameron Little (2024-11-14)](https://camlittle.com/posts/2024-11-14-swiftui-core-animation/)
- [NSHostingView centering changes in macOS Sequoia — Furnace Creek Software (2024-12-07)](https://furnacecreek.org/blog/2024-12-07-centering-nswindows-with-nshostingcontrollers-on-sequoia)

---
*Pitfalls research for: macOS dictation app UI revamp, game exclusion, clipboard persistence, animation polish*
*Researched: 2026-03-26*
