---
gsd_state_version: 1.0
milestone: v1.2
milestone_name: Companion App
status: executing
stopped_at: "Checkpoint 05-02 Task 2: human-verify companion lifecycle"
last_updated: "2026-03-30T09:38:52.725Z"
last_activity: 2026-03-30
progress:
  total_phases: 8
  completed_phases: 4
  total_plans: 6
  completed_plans: 7
  percent: 0
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-30)

**Core value:** Hold a key, speak, and have accurate text appear where you need it — zero friction dictation.
**Current focus:** Phase 05 — companion-shell

## Current Position

Phase: 05 (companion-shell) — EXECUTING
Plan: 2 of 2 complete
Status: Ready to execute
Last activity: 2026-03-30

Progress: [░░░░░░░░░░] 0% (v1.2 phases)

## Performance Metrics

**Velocity:**

- Total plans completed: 7 (v1.1) + 1 (v1.2)
- Average duration: 7 min
- Total execution time: ~37 min

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 01-foundation | 2 | 8 min | 4 min |
| 02-clipboard-persistence | 1 | 10 min | 10 min |
| 03-overlay-redesign | 1 | 12 min | 12 min |
| 04-app-exclusion | 2 | 5 min | 2.5 min |
| 05-companion-shell P01 | 4 | 2 tasks | 13 files |

*Updated after each plan completion*
| Phase 05-companion-shell P02 | 6 | 1 tasks | 1 files |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- SwiftData over GRDB — modern Apple persistence, macOS 14+ acceptable (confirmed for v1.2)
- Companion window must use WindowGroup (not NSWindow) — @Query silently fails in NSHostingView
- setActivationPolicy: commit permanently after first companion open, never toggle mid-session
- Snippet expansion runs after GPT-4o-mini cleanup, before TextInserter (pipeline order locked)
- fetchLimit = 200 + 90-day retention — ship from day one, not retroactively
- [Phase 05-01]: Single ModelContainer initialized in FlowSpeechApp.init() and shared with AppDelegate — no second container
- [Phase 05-01]: WindowGroup scene (not NSHostingView) for companion window — required for @Query to work in Phase 6
- [Phase 05-01]: NSWindowDelegate chaining: windowShouldClose returns false + orderOut + 0.1s setActivationPolicy(.accessory) delay
- [Phase 05-02]: windowShouldClose guards sender === companionWindow so settings/onboarding windows still close normally
- [Phase 05-02]: disableDockIcon uses 100ms async delay to prevent focus-stealing flicker; openCompanion first-open relies on SwiftUI WindowGroup auto-present on app activate

### Pending Todos

None yet.

### Blockers/Concerns

- setActivationPolicy exact timing: 0.1s delay and applicationWillFinishLaunching vs applicationDidFinishLaunching may need hardware validation — spike in Phase 5
- Snippet partial vs. whole-word matching: exact behavior (punctuation stripping, standalone triggers) must be decided before Phase 7 begins
- @Query pagination UX for large histories: FetchDescriptor offset pattern for "load more" — decide at Phase 6 planning time
- VersionedSchema forward planning: sketch anticipated v1.3 fields (sourceAppBundleID, audio path) during Phase 5 model work

## Session Continuity

Last activity: 2026-03-30
Last session: 2026-03-30T09:38:52.721Z
Stopped at: Checkpoint 05-02 Task 2: human-verify companion lifecycle
Resume file: None
