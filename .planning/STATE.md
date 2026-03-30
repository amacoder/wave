---
gsd_state_version: 1.0
milestone: v1.2
milestone_name: Companion App
status: verifying
stopped_at: Completed 06-02-PLAN.md (HomeView history UI)
last_updated: "2026-03-30T13:20:38.957Z"
last_activity: 2026-03-30
progress:
  total_phases: 8
  completed_phases: 6
  total_plans: 10
  completed_plans: 10
  percent: 0
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-30)

**Core value:** Hold a key, speak, and have accurate text appear where you need it — zero friction dictation.
**Current focus:** Phase 06 — history

## Current Position

Phase: 06 (history) — EXECUTING
Plan: 2 of 2
Status: Phase complete — ready for verification
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
| Phase 06-history P01 | 8 | 1 tasks | 1 files |
| Phase 06-history P02 | 12 | 1 tasks | 1 files |

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
- [Phase 06-01]: Save runs BEFORE MainActor.run paste block so persistence succeeds even when autoInsertText is disabled (D-02)
- [Phase 06-01]: Background ModelContext(container) used per save to avoid cross-thread SwiftData access
- [Phase 06-01]: cleanupOldEntries() deferred via DispatchQueue.main.async because FlowSpeechApp.init() sets modelContainer after applicationDidFinishLaunching
- [Phase 06-01]: Source app captured at startRecording() start, not transcription end, so correct app stored even if user switches focus during Whisper API call
- [Phase 06-02]: FetchDescriptor fetchLimit must be set as a property after init on macOS SDK 26.4, not as constructor argument
- [Phase 06-02]: Undo delete pattern: hold pendingUndo in-memory, delete from context, start 3-second Task, re-insert on undo tap

### Pending Todos

None yet.

### Blockers/Concerns

- setActivationPolicy exact timing: 0.1s delay and applicationWillFinishLaunching vs applicationDidFinishLaunching may need hardware validation — spike in Phase 5
- Snippet partial vs. whole-word matching: exact behavior (punctuation stripping, standalone triggers) must be decided before Phase 7 begins
- @Query pagination UX for large histories: FetchDescriptor offset pattern for "load more" — decide at Phase 6 planning time
- VersionedSchema forward planning: sketch anticipated v1.3 fields (sourceAppBundleID, audio path) during Phase 5 model work

## Session Continuity

Last activity: 2026-03-30
Last session: 2026-03-30T13:20:38.951Z
Stopped at: Completed 06-02-PLAN.md (HomeView history UI)
Resume file: None
