---
phase: 01-foundation
plan: 02
subsystem: ui
tags: [swiftui, design-system, color-tokens, animations, cpu-optimization, macos]

# Dependency graph
requires:
  - phase: 01-01
    provides: RecordingPhase enum and AppState.phase for animation gating

provides:
  - DesignSystem.swift with blue palette tokens (deepNavy, vibrantBlue, softBlueWhite, teal, accentGradient)
  - Color(hex:) extension centralized in DesignSystem.swift
  - Phase-gated SwiftUI animations — all repeatForever loops driven by appState.phase via onChange
  - Zero idle CPU from animation loops (animations stop when phase returns to .idle)

affects:
  - 01-03
  - 02-overlay-redesign
  - 03-flow-bar

# Tech tracking
tech-stack:
  added: []
  patterns:
    - DesignSystem enum with nested Colors sub-enum for token organization
    - Phase-gated animation pattern: onChange(of: appState.phase) + onAppear guard

key-files:
  created:
    - FlowSpeech/DesignSystem.swift
  modified:
    - FlowSpeech/Views/SettingsView.swift
    - FlowSpeech/Views/RecordingOverlayView.swift
    - FlowSpeech/Views/MenuBarPopoverView.swift
    - FlowSpeech/Views/OnboardingView.swift
    - FlowSpeech.xcodeproj/project.pbxproj

key-decisions:
  - "DesignSystem.Colors.accentGradient used where gradient direction matches (.leading/.trailing); explicit color references kept for other directions"
  - "CircularWaveformView @State property renamed from phase to animationPhase to avoid shadowing appState.phase"
  - "onAppear blocks retained alongside onChange to handle edge case where view appears while already in an active phase"
  - "TranscribingStatusView and TranscribingView both given @EnvironmentObject appState for phase access"

patterns-established:
  - "Phase-gated animation: .onChange(of: appState.phase) { _, newPhase in } starts animation when phase matches, withAnimation(.linear(duration: 0)) stops it on any other phase"
  - "Color token usage: always DesignSystem.Colors.X — never hardcoded Color(hex:) outside DesignSystem.swift"

requirements-completed: [FNDTN-02, FNDTN-04]

# Metrics
duration: 4min
completed: 2026-03-26
---

# Phase 01 Plan 02: Design System and Animation Gating Summary

**Centralized blue palette into DesignSystem.swift and eliminated idle CPU drain by gating all SwiftUI repeatForever animations on AppState.phase via onChange**

## Performance

- **Duration:** 4 min
- **Started:** 2026-03-26T12:56:28Z
- **Completed:** 2026-03-26T12:59:56Z
- **Tasks:** 2
- **Files modified:** 6

## Accomplishments

- Created `FlowSpeech/DesignSystem.swift` with `deepNavy`, `vibrantBlue`, `softBlueWhite`, `teal` color tokens and `accentGradient` convenience gradient; moved `Color(hex:)` extension here as the single source of truth
- Migrated all 11 hardcoded `Color(hex:)` call sites across 4 view files to `DesignSystem.Colors` tokens; zero `Color(hex:)` calls remain outside DesignSystem.swift
- Replaced unconditional `repeatForever` animations started in `onAppear` with `onChange(of: appState.phase)` guards in `RecordingOverlayView`, `TranscribingView`, `CircularWaveformView`, `RecordingStatusView`, and `TranscribingStatusView` — animations now start only when the relevant phase is active and stop immediately on phase change

## Task Commits

Each task was committed atomically:

1. **Task 1: Create DesignSystem.swift and migrate Color(hex:) calls** - `e1662c4` (feat)
2. **Task 2: Gate SwiftUI animations on RecordingPhase** - `c0be980` (feat)

## Files Created/Modified

- `FlowSpeech/DesignSystem.swift` - New file: color tokens (deepNavy, vibrantBlue, softBlueWhite, teal, accentGradient) and Color(hex:) extension
- `FlowSpeech/Views/SettingsView.swift` - Replaced Color(hex:) in AboutTab gradient; removed duplicate Color(hex:) extension
- `FlowSpeech/Views/RecordingOverlayView.swift` - Migrated 3 Color(hex:) sites; gated pulse, rotation, and animationPhase animations on appState.phase
- `FlowSpeech/Views/MenuBarPopoverView.swift` - Migrated 2 Color(hex:) sites; gated pulse (RecordingStatusView) and rotation (TranscribingStatusView) on appState.phase
- `FlowSpeech/Views/OnboardingView.swift` - Migrated 7 Color(hex:) sites to DesignSystem.Colors tokens
- `FlowSpeech.xcodeproj/project.pbxproj` - Added DesignSystem.swift to FlowSpeech group and Sources build phase

## Decisions Made

- `DesignSystem.Colors.accentGradient` (.leading/.trailing) used as-is where gradient direction matches; explicit `[vibrantBlue, teal]` used for other directions (.topLeading/.bottomTrailing, .bottom/.top)
- `CircularWaveformView` `@State private var phase` renamed to `animationPhase` to prevent shadowing the `appState.phase` property accessed via `@EnvironmentObject`
- Both `onChange` and `onAppear` retained together: `onAppear` handles the case where view appears while the app is already mid-recording/transcribing (e.g., app launched mid-session)
- `TranscribingStatusView` and `TranscribingView` gained `@EnvironmentObject var appState: AppState` — both were previously stateless on phase; required for onChange pattern

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- DesignSystem.swift is ready to serve as the color token foundation for Phase 3 overlay redesign
- Animation gating pattern established — future animated views should follow onChange + onAppear guard convention
- All views compile and build successfully with zero errors

---
*Phase: 01-foundation*
*Completed: 2026-03-26*
