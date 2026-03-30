---
gsd_state_version: 1.0
milestone: v1.2
milestone_name: Companion App
status: executing
stopped_at: Completed 07-dictionary-snippets-07-04-PLAN.md
last_updated: "2026-03-30T14:36:14.434Z"
last_activity: 2026-03-30
progress:
  total_phases: 8
  completed_phases: 5
  total_plans: 8
  completed_plans: 14
  percent: 0
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-30)

**Core value:** Hold a key, speak, and have accurate text appear where you need it — zero friction dictation.
**Current focus:** Phase 07 — dictionary-snippets

## Current Position

Phase: 07 (dictionary-snippets) — EXECUTING
Plan: 4 of 4
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
| Phase 06-history P01 | 8 | 1 tasks | 1 files |
| Phase 06-history P02 | 12 | 1 tasks | 1 files |
| Phase 07-dictionary-snippets P01 | 2 | 2 tasks | 3 files |
| Phase 07-dictionary-snippets P02 | 5 | 1 tasks | 1 files |
| Phase 07-dictionary-snippets P03 | 2 | 1 tasks | 1 files |
| Phase 07-dictionary-snippets P04 | 3 | 1 tasks | 1 files |

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


- [Phase 07-01]: Case-insensitive TextReplacer using NSRegularExpression — Whisper output capitalisation is non-deterministic (D-02)
- [Phase 07-01]: Sentence-format Whisper prompt 'In this transcript: ...' — outperforms comma-separated lists (D-05)
- [Phase 07-01]: Newest-first sort for buildPrompt truncation prioritisation (D-06)
- [Phase 07-02]: EditingDictionaryState as value-type struct with Identifiable conformance — enables .sheet(item:) pattern with SwiftUI copy semantics for safe field binding
- [Phase 07-02]: PromptCharCountBar always visible below divider — visible even when list is empty, giving users baseline context before adding any terms
- [Phase 07-03]: EditingSnippetState is a plain struct (not @Model) as sheet binding to avoid SwiftData mutation race during sheet dismissal
- [Phase 07-03]: TextEditor placeholder via ZStack overlay allowsHitTesting(false) — standard macOS pattern since TextEditor lacks native placeholder API

- [Phase 07-04]: Two separate background ModelContexts in transcribe(): one for prompt building (createdAt sorted), one for expansion (unsorted); both disposable
- [Phase 07-04]: [07-04] dictionaryService and snippetService stored as AppDelegate properties matching existing service singleton pattern

### Pending Todos

None yet.

### Blockers/Concerns

- setActivationPolicy exact timing: 0.1s delay and applicationWillFinishLaunching vs applicationDidFinishLaunching may need hardware validation — spike in Phase 5
- Snippet partial vs. whole-word matching: exact behavior (punctuation stripping, standalone triggers) must be decided before Phase 7 begins
- @Query pagination UX for large histories: FetchDescriptor offset pattern for "load more" — decide at Phase 6 planning time
- VersionedSchema forward planning: sketch anticipated v1.3 fields (sourceAppBundleID, audio path) during Phase 5 model work

## Session Continuity

Last activity: 2026-03-30
Last session: 2026-03-30T14:36:14.430Z
Stopped at: Completed 07-dictionary-snippets-07-04-PLAN.md
Resume file: None
