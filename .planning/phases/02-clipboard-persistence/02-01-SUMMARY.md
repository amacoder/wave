---
phase: 02-clipboard-persistence
plan: 01
subsystem: clipboard
tags: [NSPasteboard, TransientType, clipboard-manager, macOS, Swift]

# Dependency graph
requires:
  - phase: 01-foundation
    provides: TextInserter class with insertText method and CGEvent paste simulation
provides:
  - Clipboard persistence after dictation (Cmd+V re-pastes transcription)
  - TransientType marker preventing clipboard manager logging
  - changeCount guard pattern for safe future restore logic
affects: [03-overlay-ui, 04-game-compatibility]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - NSPasteboard TransientType write in single clearContents transaction (no save/restore cycle)
    - changeCount snapshot after write for future conditional restore guard

key-files:
  created: []
  modified:
    - FlowSpeech/Services/TextInserter.swift

key-decisions:
  - "Remove clipboard restore entirely — transcription stays on clipboard after paste so Cmd+V re-pastes it"
  - "org.nspasteboard.TransientType marker added with empty Data() payload in same clearContents transaction to exclude content from clipboard manager history"
  - "changeCountAfterWrite snapshot retained as dead code with comment documenting the restore-guard pattern (CLIP-02), not yet wired to any restore path"

patterns-established:
  - "Single clearContents transaction: clearContents → setString → setData(TransientType) — never call clearContents twice or TransientType write is wiped"
  - "NSPasteboard.PasteboardType extension for named constants avoids raw string repetition"

requirements-completed: [CLIP-01, CLIP-02, CLIP-03]

# Metrics
duration: ~10min
completed: 2026-03-26
---

# Phase 2 Plan 01: Clipboard Persistence Summary

**Removed clipboard restore from insertText, added org.nspasteboard.TransientType marker and changeCount snapshot so transcription persists on Cmd+V and clipboard managers skip logging**

## Performance

- **Duration:** ~10 min
- **Started:** 2026-03-26
- **Completed:** 2026-03-26
- **Tasks:** 2 (1 auto + 1 human-verify checkpoint)
- **Files modified:** 1

## Accomplishments

- Removed the 0.5s asyncAfter restore block — transcription now remains on the clipboard after paste, enabling Cmd+V to re-paste it
- Added org.nspasteboard.TransientType marker in the same clearContents transaction so clipboard managers (Maccy, Raycast, Paste) skip logging the transcription
- Added changeCountAfterWrite snapshot with a commented restore-guard pattern for CLIP-02 compliance without introducing a restore path

## Task Commits

1. **Task 1: Revise insertText to remove restore, add TransientType, snapshot changeCount** - `ee33d7d` (feat)
2. **Task 2: Human verify checkpoint** - APPROVED by user (automated verification deferred)

## Files Created/Modified

- `FlowSpeech/Services/TextInserter.swift` - Revised insertText: removed oldContent save + asyncAfter restore, added NSPasteboard.PasteboardType.transientContent extension and setData write, added changeCountAfterWrite snapshot

## Decisions Made

- Remove clipboard restore entirely (CLIP-01): the old design restored the prior clipboard 0.5s after paste, breaking Cmd+V re-paste. Removing the restore is the correct behavior for a dictation app where the transcription is the valuable content.
- TransientType via extension constant (not raw string): added `NSPasteboard.PasteboardType.transientContent` extension above the class for readability and to avoid magic strings.
- changeCount as dormant snapshot (CLIP-02): snapshotted but not wired to any restore gate — preserves the pattern if a restore path is re-introduced, silenced with `_ = changeCountAfterWrite`.

## Deviations from Plan

None - plan executed exactly as written. The optional NSPasteboard.PasteboardType extension was added (permitted by plan step 6).

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Clipboard persistence is complete and verified by user
- TextInserter.swift is stable; no further changes anticipated for Phase 3
- Phase 3 (overlay UI) can proceed — no clipboard dependencies to resolve

---
*Phase: 02-clipboard-persistence*
*Completed: 2026-03-26*
