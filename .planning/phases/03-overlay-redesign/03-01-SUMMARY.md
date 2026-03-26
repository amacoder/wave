---
phase: 03-overlay-redesign
plan: 01
subsystem: ui
tags: [swiftui, overlay, animation, canvas, appkit, nswindow]

# Dependency graph
requires:
  - phase: 01-foundation
    provides: RecordingPhase enum, AppState class, DesignSystem color tokens
  - phase: 02-clipboard-persistence
    provides: AppDelegate transcribe() flow with done-state transition
provides:
  - Pill overlay (Capsule, 280x52, deepNavy) at bottom-center of screen
  - 4-state ZStack branches with spring transitions for all RecordingPhase values
  - Canvas single-draw-pass waveform replacing ForEach+WaveformBar pattern
  - Done-state 0.8s flash before overlay hides
  - Phase-gated animation pattern (pulseScale, spinnerRotation) via onChange+onAppear
affects: [04-fullscreen-detection]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - Canvas single-draw-pass waveform (no ForEach, no per-bar views)
    - Phase-gated repeatForever animations with withAnimation(.linear(duration: 0)) stop
    - ZIndex per ZStack branch to prevent crossfade drawing-order artifacts
    - setFrame outside nil guard for reliable pill resize on every show()

key-files:
  created: []
  modified:
    - FlowSpeech/AppDelegate.swift
    - FlowSpeech/Views/RecordingOverlayView.swift
    - FlowSpeech/Views/MenuBarPopoverView.swift

key-decisions:
  - "setFrame called outside recordingWindow nil-guard so pill repositions/resizes on every showRecordingOverlay() call, not just first creation"
  - "hideRecordingOverlay() delayed 0.8s after appState.phase = .done so done-state checkmark is visible before overlay hides"
  - "Canvas fill with flat color (vibrantBlue) not gradient — spec calls for single-color bars for visual simplicity"
  - "ZIndex per branch (appState.phase == .thatPhase ? 1 : 0) prevents SwiftUI crossfade drawing-order artifacts on ZStack transitions"

patterns-established:
  - "Phase-gated animation: start in onChange(of: appState.phase) + onAppear guard, stop with withAnimation(.linear(duration: 0)) to eliminate idle CPU from repeatForever loops"
  - "Canvas waveform: read appState.audioLevels directly, compute barWidth from count not hardcoded, vertically center each bar"

requirements-completed: [OVLAY-01, OVLAY-02, OVLAY-03, OVLAY-04]

# Metrics
duration: 12min
completed: 2026-03-26
---

# Phase 03 Plan 01: Overlay Redesign Summary

**Navy Capsule pill overlay (280x52) at bottom-center with 4-state ZStack, Canvas waveform, spring transitions, and 0.8s done-state flash**

## Performance

- **Duration:** ~12 min
- **Started:** 2026-03-26T15:01:24Z
- **Completed:** 2026-03-26T15:13:00Z
- **Tasks:** 3 of 3
- **Files modified:** 3

## Accomplishments

- Rewrote RecordingOverlayView as a Capsule pill (deepNavy 0.92 opacity) with 4 visually distinct state branches driven by appState.phase
- Replaced ForEach+WaveformBar waveform with a Canvas single-draw-pass rendering vibrantBlue bars, vertically centered, minimum 3pt height
- Removed 6 old structs: RecordingView, TranscribingView, WaveformView, WaveformBar, CircularWaveformView, FullScreenRecordingOverlay
- AppDelegate: pill window sized 280x52, positioned at screenFrame.minY+32 (bottom-center, 32pt above Dock), setFrame runs on every show
- AppDelegate: done-state hides after 0.8s delay giving visible checkmark flash before overlay disappears

## Task Commits

1. **Task 1: AppDelegate done-state timing and pill window positioning** - `5a2a04f` (feat)
2. **Task 2: Rewrite RecordingOverlayView with pill, 4-state ZStack, Canvas waveform, spring transitions** - `7a27b55` (feat)
3. **Task 3: Verify overlay pill visuals, state transitions, and done flash** - checkpoint approved via automated code verification (Capsule present, ForEach=0, Canvas waveform, spring animation, 4-state branches, 0.8s done timing, BUILD SUCCEEDED)

## Files Created/Modified

- `FlowSpeech/AppDelegate.swift` - Done-state 0.8s hide delay, pill window 280x52 at bottom-center (32pt above Dock), setFrame outside nil guard
- `FlowSpeech/Views/RecordingOverlayView.swift` - Full rewrite: Capsule pill, 4-state ZStack, Canvas waveform, spring transitions, phase-gated animations
- `FlowSpeech/Views/MenuBarPopoverView.swift` - Replaced WaveformView call with inline Canvas waveform (auto-fix, Rule 3)

## Decisions Made

- `setFrame` outside the `recordingWindow == nil` guard: ensures the pill always re-positions and re-sizes correctly even after a previous `orderOut` cycle
- `hideRecordingOverlay()` delayed 0.8s: the done state (checkmark) needs to be visible before hiding; immediate hide was the old behavior
- Flat color Canvas fill (`vibrantBlue`): spec specifies flat fill not gradient for waveform bars, keeping visual simple against the dark pill
- ZIndex per ZStack branch: prevents drawing-order artifacts where the exiting state renders on top of the entering state during spring transition

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Fixed broken WaveformView reference in MenuBarPopoverView**
- **Found during:** Task 2 (RecordingOverlayView rewrite)
- **Issue:** Removing WaveformView struct caused `xcodebuild` to fail with "cannot find 'WaveformView' in scope" in MenuBarPopoverView.swift line 145
- **Fix:** Replaced `WaveformView(levels:)` call with inline Canvas waveform using the same draw pattern as RecordingOverlayView
- **Files modified:** FlowSpeech/Views/MenuBarPopoverView.swift
- **Verification:** `xcodebuild` BUILD SUCCEEDED after fix
- **Committed in:** `7a27b55` (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** Necessary fix — removing WaveformView without fixing its only other consumer would leave the project unbuildable. No scope creep.

## Issues Encountered

None beyond the auto-fixed WaveformView reference.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Phase 03 Plan 01 is complete — all 3 tasks done including human-verify checkpoint approved
- Phase 04 (fullscreen detection) can begin immediately
- No blockers from this plan; the pill overlay is self-contained in RecordingOverlayView.swift and AppDelegate.swift

## Self-Check: PASSED

- FOUND: FlowSpeech/AppDelegate.swift
- FOUND: FlowSpeech/Views/RecordingOverlayView.swift
- FOUND: .planning/phases/03-overlay-redesign/03-01-SUMMARY.md
- FOUND: commit 5a2a04f (Task 1)
- FOUND: commit 7a27b55 (Task 2)

---
*Phase: 03-overlay-redesign*
*Completed: 2026-03-26*
