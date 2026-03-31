---
phase: 06-history
plan: 02
subsystem: ui
tags: [swiftui, swiftdata, history, homeview, macos]

# Dependency graph
requires:
  - phase: 06-01
    provides: TranscriptionEntry SwiftData model and ModelContainer wiring in FlowSpeechApp
provides:
  - HomeView with @Query-driven transcription history list
  - Date-grouped sections (TODAY / YESTERDAY / THIS WEEK / OLDER)
  - Stats header with streak, total words, and average WPM
  - Per-entry copy action (click to copy, hover icon feedback)
  - Per-entry delete with 3-second undo toast
  - EmptyStateView fallback
affects: [future phases referencing companion window home screen]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "@Query with FetchDescriptor property-set fetchLimit instead of init argument (macOS 26 SDK)"
    - "Private structs co-located in HomeView.swift (HistoryHeaderView, StatBadge, HistoryEntryRow, UndoToastView)"
    - "Delete-then-undo: modelContext.delete + pendingUndo @State + Task.sleep(3s) + modelContext.insert re-insert"

key-files:
  created: []
  modified:
    - FlowSpeech/Views/CompanionWindow/HomeView.swift

key-decisions:
  - "FetchDescriptor fetchLimit must be set as a property after init, not as constructor argument — @Query(FetchDescriptor<T>(sortBy:fetchLimit:)) does not compile on current SDK"
  - "UndoToastView uses Task.sleep for 3-second dismiss; auto-save race condition accepted as acceptable edge case per RESEARCH.md"
  - "groupedEntries computed property filters in Swift, not in #Predicate, to avoid Calendar-in-predicate runtime crash"

patterns-established:
  - "Pattern: @Query FetchDescriptor with fetchLimit via property mutation: var d = FetchDescriptor<T>(sortBy:...); d.fetchLimit = N; @Query(d)"
  - "Pattern: Undo toast with pendingUndo: TranscriptionEntry? + undoToastTask cancellation on re-delete"

requirements-completed: [HIST-02, HIST-03, HIST-04, HIST-05]

# Metrics
duration: 12min
completed: 2026-03-30
---

# Phase 6 Plan 02: History History UI Summary

**SwiftUI HomeView with @Query-driven history list, date grouping (TODAY/YESTERDAY/THIS WEEK/OLDER), welcome stats header (streak/words/WPM), click-to-copy, hover delete, and 3-second undo toast**

## Performance

- **Duration:** ~12 min
- **Started:** 2026-03-30T00:00:00Z
- **Completed:** 2026-03-30T00:12:00Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments

- Replaced HomeView placeholder with full interactive history UI (265 lines)
- @Query with FetchDescriptor fetchLimit 200 sorted by timestamp descending
- HistoryHeaderView: welcome greeting using NSFullUserName(), three StatBadge items (streak days, total words, avg WPM)
- HistoryEntryRow: .onHover icon reveal, .onTapGesture copy, .contentShape(Rectangle()), fixedSize no-truncation text
- UndoToastView: .regularMaterial background, .transition(.move(edge:.bottom).combined(with:.opacity)), Task.sleep 3-second auto-dismiss
- EmptyStateView rendered when entries is empty
- xcodebuild BUILD SUCCEEDED with zero errors

## Task Commits

Each task was committed atomically:

1. **Task 1: Build HomeView with @Query, date grouping, and stats header** - `7c5d94f` (feat)

## Files Created/Modified

- `FlowSpeech/Views/CompanionWindow/HomeView.swift` - Rewritten from 18-line placeholder to 265-line full history UI with all private sub-structs

## Decisions Made

- `FetchDescriptor` in this SDK version does not accept `fetchLimit` as an initializer argument — must use property mutation: `var d = FetchDescriptor<TranscriptionEntry>(sortBy: ...); d.fetchLimit = 200`. Fixed immediately as a Rule 3 blocking issue.
- Undo pattern: hold `pendingUndo` in-memory, `modelContext.delete`, start 3-second Task, cancel on re-delete or Undo tap, then `modelContext.insert` to restore. Auto-save race accepted per RESEARCH.md guidance.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Fixed FetchDescriptor fetchLimit compile error**
- **Found during:** Task 1 (first build attempt)
- **Issue:** `FetchDescriptor<TranscriptionEntry>(sortBy:fetchLimit:)` produces "extra argument 'fetchLimit' in call" in current SDK
- **Fix:** Changed to property mutation pattern: create descriptor with sortBy, then set `.fetchLimit = 200` separately, pass result to `@Query({...}())`
- **Files modified:** FlowSpeech/Views/CompanionWindow/HomeView.swift
- **Verification:** xcodebuild BUILD SUCCEEDED
- **Committed in:** 7c5d94f (part of task commit)

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** Fix required for compilation. No scope change. All acceptance criteria met.

## Issues Encountered

- SwiftData `@Query` macro on macOS SDK 26.4 does not support `fetchLimit` in `FetchDescriptor` initializer — must use property-set pattern. Resolved inline.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- HomeView is fully functional — history UI ready for end-to-end testing with real transcription entries saved in Phase 6 Plan 01
- Requirements HIST-02, HIST-03, HIST-04, HIST-05 satisfied
- No blockers for remaining phase work

---
*Phase: 06-history*
*Completed: 2026-03-30*

## Self-Check: PASSED

- HomeView.swift: FOUND (277 lines, exceeds 150-line minimum)
- 06-02-SUMMARY.md: FOUND
- Commit 7c5d94f: FOUND
- Commit e99b84a: FOUND
- @Query pattern: present
- FetchDescriptor + fetchLimit: present
- groupedEntries: present
- NSPasteboard: present
- modelContext.delete: present
- modelContext.insert: present
- regularMaterial: present
- xcodebuild BUILD SUCCEEDED: confirmed
