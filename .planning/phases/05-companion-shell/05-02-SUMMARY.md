---
phase: 05-companion-shell
plan: 02
subsystem: companion-window
tags: [swiftui, appkit, dock-icon, windowlifecycle, nswindelegate, activation-policy]
dependency_graph:
  requires:
    - phase: 05-01
      provides: [companionWindow, originalWindowDelegate, modelContainer, WindowGroup-companion, WindowAccessor, NSWindowDelegate-extension]
  provides: [enableDockIcon, disableDockIcon, openCompanion, applicationShouldHandleReopen, Open-Wave-menu-item, windowShouldClose-with-guard]
  affects: [Phase 06 — recording history pipeline, Phase 07 — dictionary/snippets CRUD]
tech_stack:
  added: []
  patterns: [setActivationPolicy-toggle, hide-on-close-with-guard, dock-icon-lifecycle]
key_files:
  created: []
  modified:
    - FlowSpeech/AppDelegate.swift
key-decisions:
  - "windowShouldClose guards sender === companionWindow so settings and onboarding windows still close normally"
  - "disableDockIcon uses 100ms async delay to prevent focus-stealing flicker when companion hides"
  - "openCompanion() falls through to enableDockIcon() on first open (companionWindow == nil) — SwiftUI WindowGroup presents window on app activate since there are no visible windows"
  - "applicationShouldHandleReopen delegates to openCompanion() — dock click and Cmd+Tab reopen share same code path"
requirements-completed: [SHELL-02]
duration: 6min
completed: "2026-03-30"
---

# Phase 5 Plan 2: Companion Window Lifecycle Summary

**Dock icon toggle + hide-on-close + "Open Wave" menu item wired into AppDelegate via enableDockIcon/disableDockIcon methods and applicationShouldHandleReopen.**

## Performance

- **Duration:** ~6 min
- **Started:** 2026-03-30T09:31:00Z
- **Completed:** 2026-03-30T09:37:24Z
- **Tasks:** 1 of 2 complete (Task 2 is checkpoint:human-verify — awaiting user validation)
- **Files modified:** 1

## Accomplishments

- Added `enableDockIcon()` — calls `setActivationPolicy(.regular)` then `NSApp.activate()` for immediate dock appearance
- Added `disableDockIcon()` — deferred 100ms `setActivationPolicy(.accessory)` to prevent focus-stealing flicker
- Added `@objc openCompanion()` — `makeKeyAndOrderFront` if window exists, else `enableDockIcon()` for first open via SwiftUI WindowGroup auto-present
- Added `applicationShouldHandleReopen` — dock icon click and re-activation both route to `openCompanion()`
- Added "Open Wave" as first item in menu bar dropdown (before existing "Start Recording")
- Fixed `windowShouldClose` to guard `sender === companionWindow` — settings and onboarding windows now close normally
- `windowShouldClose` now calls `disableDockIcon()` instead of inline `setActivationPolicy`
- Added `windowWillClose` delegate forwarding to `originalWindowDelegate`
- Build: **BUILD SUCCEEDED** — no errors, no warnings

## Task Commits

1. **Task 1: Dock icon toggle, window lifecycle, menu bar item** - `f777927` (feat)

**Plan metadata:** (to be added after human verify)

## Files Created/Modified

- `/FlowSpeech/AppDelegate.swift` — enableDockIcon, disableDockIcon, openCompanion, applicationShouldHandleReopen, "Open Wave" menu item, fixed windowShouldClose guard, windowWillClose forwarding

## Decisions Made

- `windowShouldClose` must guard `sender === companionWindow` because AppDelegate is now the delegate for all windows that go through WindowAccessor, but settings and onboarding windows should still close normally.
- First-open via `openCompanion()` when `companionWindow == nil`: calling `enableDockIcon()` activates the app, which causes SwiftUI to present the `WindowGroup(id: "companion")` because there are no currently visible windows. This is the simplest approach and avoids NotificationCenter hacks.
- `disableDockIcon()` always deferred 100ms — matches RESEARCH.md Pitfall 3 documented behavior.

## Deviations from Plan

None — plan executed exactly as written. The existing Plan 01 `windowShouldClose` implementation was missing the `guard sender === companionWindow` check and the `disableDockIcon()` call; these were exactly what Plan 02 specified.

## Issues Encountered

None — build succeeded on first attempt.

## Self-Check: PASSED

Files verified present:
- FlowSpeech/AppDelegate.swift: FOUND
- .planning/phases/05-companion-shell/05-02-SUMMARY.md: FOUND

Commits verified:
- f777927: feat(05-02): wire dock icon toggle, companion window lifecycle, and menu bar item

## Next Phase Readiness

- Complete companion shell is ready for human verification (Task 2 checkpoint)
- After verification: Phase 6 can begin wiring `TranscriptionEntry` saves into the dictation pipeline
- `companionWindow` reference is set by `WindowAccessor` in `CompanionWindowView` — Plan 06 can query it for navigation

---
*Phase: 05-companion-shell*
*Completed: 2026-03-30*
