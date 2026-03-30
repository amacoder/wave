---
phase: 06-history
plan: 01
subsystem: database
tags: [swiftdata, transcription, history, retention, appdelegate]

# Dependency graph
requires:
  - phase: 05-companion-shell
    provides: TranscriptionEntry SwiftData model and ModelContainer setup in FlowSpeechApp.init()
provides:
  - AppDelegate save hook: every completed transcription is persisted to SwiftData
  - Source app capture at recording start via NSWorkspace.frontmostApplication
  - Duration tracking via recordingStartTime property
  - 90-day retention cleanup on app launch via cleanupOldEntries()
affects: [06-02, companion-window, history-view]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Background ModelContext pattern: ModelContext(container) in async task for thread-safe SwiftData writes"
    - "Deferred launch cleanup: DispatchQueue.main.async in applicationDidFinishLaunching to call cleanup after modelContainer is set by FlowSpeechApp.init()"
    - "Capture-early pattern: source app captured at recording START not at transcription end (user may switch apps during 2-4s Whisper API call)"

key-files:
  created: []
  modified:
    - FlowSpeech/AppDelegate.swift

key-decisions:
  - "Save runs BEFORE MainActor.run paste block so persistence succeeds even when autoInsertText is disabled or no focused text field exists (D-02)"
  - "Background ModelContext(container) used instead of main view context to avoid threading issues in async transcribe()"
  - "cleanupOldEntries() deferred via DispatchQueue.main.async because FlowSpeechApp.init() sets modelContainer after applicationDidFinishLaunching returns"
  - "Source app captured at startRecording() via NSWorkspace.shared.frontmostApplication?.localizedName — user may switch apps during Whisper API call (D-03/D-04)"

patterns-established:
  - "Background SwiftData write: create ModelContext(container) inside async context, insert, try? save()"
  - "Deferred init dependency: use DispatchQueue.main.async when property is set after applicationDidFinishLaunching"

requirements-completed: [HIST-01]

# Metrics
duration: 8min
completed: 2026-03-30
---

# Phase 06 Plan 01: Transcription Save Hook Summary

**SwiftData save pipeline wired into AppDelegate.transcribe() with source app capture, duration tracking, and silent 90-day retention cleanup on launch**

## Performance

- **Duration:** 8 min
- **Started:** 2026-03-30T00:00:00Z
- **Completed:** 2026-03-30T00:08:00Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments

- Every completed dictation now automatically saves a TranscriptionEntry to SwiftData with rawText, cleanedText, durationSeconds, wordCount, and sourceAppName
- Source app name captured at recording start (not transcription end) so the correct app is stored even when users switch focus during the Whisper API call
- Recording duration computed from a new `recordingStartTime` property measured from startRecording() to transcription complete
- 90-day retention cleanup added as a silent background Task on app launch, deferred correctly to run after FlowSpeechApp.init() assigns modelContainer
- xcodebuild BUILD SUCCEEDED with zero errors

## Task Commits

Each task was committed atomically:

1. **Task 1: Add recording metadata capture and transcription save hook** - `6ba62c8` (feat)

**Plan metadata:** pending docs commit

## Files Created/Modified

- `FlowSpeech/AppDelegate.swift` - Added recordingStartTime/recordingSourceApp properties, metadata capture in startRecording(), SwiftData save block in transcribe(), cleanupOldEntries() method

## Decisions Made

- Save block placed BEFORE `await MainActor.run` so persistence happens regardless of whether paste succeeds (D-02 compliance)
- Used a fresh `ModelContext(container)` per save rather than sharing the main view context — avoids cross-thread SwiftData access
- `cleanupOldEntries()` called via `DispatchQueue.main.async` at end of applicationDidFinishLaunching because `modelContainer` is assigned by `FlowSpeechApp.init()` which runs after the delegate method; the deferred call on the main queue runs after init completes

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Save hook is live; every transcription will be persisted from this point forward
- Phase 06-02 (history UI in companion window) can now query TranscriptionEntry records from SwiftData
- No blockers for 06-02

## Self-Check: PASSED

- `FlowSpeech/AppDelegate.swift` - FOUND
- `.planning/phases/06-history/06-01-SUMMARY.md` - FOUND
- Commit `6ba62c8` (feat: transcription save hook) - FOUND

---
*Phase: 06-history*
*Completed: 2026-03-30*
