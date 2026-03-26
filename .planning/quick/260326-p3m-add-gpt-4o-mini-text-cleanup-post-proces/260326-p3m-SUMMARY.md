---
phase: quick
plan: 260326-p3m
subsystem: transcription-pipeline
tags: [gpt-4o-mini, cleanup, post-processing, settings]
dependency_graph:
  requires: [WhisperService, KeychainManager, AppState]
  provides: [TextCleanupService, smartCleanup-setting, Smart-Cleanup-toggle]
  affects: [transcription-pipeline, SettingsView]
tech_stack:
  added: [GPT-4o-mini chat completions via URLSession]
  patterns: [graceful-degradation, UserDefaults-nil-guard, async-no-throw]
key_files:
  created:
    - FlowSpeech/Services/TextCleanupService.swift
  modified:
    - FlowSpeech/FlowSpeechApp.swift
    - FlowSpeech/AppDelegate.swift
    - FlowSpeech/Views/SettingsView.swift
    - FlowSpeech.xcodeproj/project.pbxproj
decisions:
  - "cleanup() declared async (not async throws) — internally catches all errors and returns original text; never propagates throws, so no try at call site needed"
  - "Cleanup step runs before MainActor.run — avoids blocking UI thread during network call"
  - "finalText variable introduced to cleanly separate raw transcription from cleaned result across the whole MainActor block"
metrics:
  duration: 2 min
  completed_date: "2026-03-26"
  tasks_completed: 2
  files_changed: 5
---

# Quick Task 260326-p3m: Add GPT-4o-mini Text Cleanup Post-Processing Summary

**One-liner:** GPT-4o-mini Smart Cleanup post-processes Whisper transcripts to remove filler words and fix grammar, with a persistent Settings toggle defaulting to ON.

## What Was Built

- **TextCleanupService** (`FlowSpeech/Services/TextCleanupService.swift`): async service that calls OpenAI's `/v1/chat/completions` endpoint with `gpt-4o-mini`, temperature 0, max_tokens 4096. System prompt instructs the model to remove filler words, fix grammar/punctuation, and preserve meaning. On any network or decode error, returns original text unchanged.

- **AppState.smartCleanup**: `@Published var smartCleanup: Bool = true` added to AppState with full UserDefaults persistence (nil-guard pattern, same as `autoInsertText`).

- **Transcription pipeline wiring** in `AppDelegate.transcribe()`: After Whisper returns, if `appState.smartCleanup` is true, calls `await cleanupService.cleanup(text:apiKey:)` and stores result in `finalText`. All downstream uses (`lastTranscription`, `insertText`, print) now reference `finalText`.

- **Settings UI**: New "Post-Processing" section in `TranscriptionSettingsTab` with a `Toggle("Smart Cleanup")` that auto-saves on change.

## Commits

| Task | Commit | Description |
|------|--------|-------------|
| Task 1 | b0ca86d | feat: TextCleanupService + smartCleanup AppState setting |
| Task 2 | 4cb3f7c | feat: pipeline wiring + Settings toggle |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Removed `throws` from TextCleanupService.cleanup signature**
- **Found during:** Task 2 — AppDelegate calls `await cleanupService.cleanup(...)` without `try`
- **Issue:** Method was declared `async throws` but internally catches all errors; calling code in AppDelegate used it without `try` (as the plan example showed), which would be a compile error
- **Fix:** Changed signature to `async -> String` — method never propagates throws; all errors result in returning original text
- **Files modified:** `FlowSpeech/Services/TextCleanupService.swift`
- **Commit:** 4cb3f7c (included in Task 2 commit)

## Self-Check: PASSED

- FlowSpeech/Services/TextCleanupService.swift: FOUND
- FlowSpeech/FlowSpeechApp.swift contains `smartCleanup`: FOUND
- FlowSpeech/AppDelegate.swift contains `cleanupService`: FOUND
- FlowSpeech/Views/SettingsView.swift contains `Smart Cleanup`: FOUND
- Build result: ** BUILD SUCCEEDED **
- Commits b0ca86d, 4cb3f7c: FOUND
