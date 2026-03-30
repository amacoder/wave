---
phase: 07-dictionary-snippets
plan: 01
subsystem: services
tags: [swift, foundation, nsregularexpression, swiftdata, text-replacement, whisper]

# Dependency graph
requires:
  - phase: 05-companion-shell
    provides: DictionaryWord and Snippet SwiftData models
  - phase: 06-history
    provides: background ModelContext fetch pattern for AppDelegate services
provides:
  - TextReplacer.replaceAll() whole-word case-insensitive punctuation-tolerant replacement engine
  - SnippetService.shared.expand() for snippet trigger expansion
  - DictionaryService.shared.buildPrompt() for Whisper vocabulary-hint prompt construction
  - DictionaryService.shared.expand() for abbreviation expansion
  - DictionaryService.shared.promptCharacterCount() for DictionaryView character count bar
  - DictionaryService.promptCharLimit = 1_100 constant for UI bar
affects: [07-02-dictionary-view, 07-03-snippets-view, 07-04-pipeline-wiring]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "TextReplacer enum as shared replacement engine namespace — both DictionaryService and SnippetService delegate to it (D-10)"
    - "Service accepts data at call time — no SwiftData coupling, AppDelegate passes fetched arrays (Phase 6 pattern)"
    - "Trigger length descending sort before replacement — longer triggers matched first to avoid partial matches"
    - "Punctuation-tolerant regex ([^a-zA-Z0-9\\s]?)(\\btrigger\\b)([^a-zA-Z0-9\\s]?) preserves surrounding punctuation while replacing trigger"

key-files:
  created:
    - FlowSpeech/Services/SnippetService.swift
    - FlowSpeech/Services/DictionaryService.swift
  modified:
    - FlowSpeech.xcodeproj/project.pbxproj

key-decisions:
  - "Case-insensitive matching (D-02) — Whisper output capitalisation is non-deterministic"
  - "Sentence-format Whisper prompt 'In this transcript: ...' (D-05) — outperforms comma-separated lists per OpenAI cookbook"
  - "Newest-first sort for prompt construction (D-06) — prioritises recently-added terms under token cap"
  - "Sequential replacement on mutating string with descending-length sort — simpler than true single-pass; cascading documented as undefined behaviour"
  - "Hard truncation at 1,100 chars via prefix(1_100) — conservative ceiling under 224-token Whisper limit (DICT-03)"

patterns-established:
  - "Pattern 1: TextReplacer.replaceAll() is the single code path for all text replacement — abbreviations and snippets share it (D-10)"
  - "Pattern 2: Service files accept model arrays at call time — never hold ModelContext (Phase 6 lesson)"

requirements-completed: [DICT-01, DICT-02, DICT-03, SNIP-02, SNIP-03]

# Metrics
duration: 2min
completed: 2026-03-30
---

# Phase 7 Plan 01: Dictionary & Snippet Services Summary

**TextReplacer engine (whole-word, case-insensitive, punctuation-tolerant NSRegularExpression) shared by DictionaryService (Whisper prompt + abbreviation expansion) and SnippetService (trigger expansion)**

## Performance

- **Duration:** 2 min
- **Started:** 2026-03-30T14:26:51Z
- **Completed:** 2026-03-30T14:29:24Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments

- TextReplacer enum with `replaceAll(in:replacements:)` — triggers sorted by length descending, NSRegularExpression with `.caseInsensitive`, punctuation-preserving capture groups
- SnippetService singleton delegating to TextReplacer for trigger phrase expansion (SNIP-02, SNIP-03)
- DictionaryService with sentence-format Whisper prompt construction truncated at 1,100 chars (DICT-01, DICT-03), abbreviation expansion (DICT-02), and character count helper for UI (DICT-05 partial)
- Both service files registered in Xcode project.pbxproj; xcodebuild BUILD SUCCEEDED

## Task Commits

Each task was committed atomically:

1. **Task 1: Create shared TextReplacer and SnippetService** - `3896e80` (feat)
2. **Task 2: Create DictionaryService** - `36de84e` (feat)

## Files Created/Modified

- `FlowSpeech/Services/SnippetService.swift` - TextReplacer engine + SnippetService singleton
- `FlowSpeech/Services/DictionaryService.swift` - DictionaryService singleton with buildPrompt, expand, promptCharacterCount
- `FlowSpeech.xcodeproj/project.pbxproj` - Registered both new service files (IDs ...030, ...031)

## Decisions Made

- Case-insensitive matching chosen (D-02) — Whisper transcribes unpredictably ("BTW", "btw", "Btw")
- Sentence format for Whisper prompt (D-05) — "In this transcript: ..." outperforms comma-separated lists
- Newest-first sort for buildPrompt (D-06) — ensures most recent vocabulary terms survive truncation
- Sequential replacement with descending-length trigger sort — pragmatic over true single-pass; cascading documented as undefined behaviour in code comment
- Punctuation capture group pattern `([^a-zA-Z0-9\s]?)(\btrigger\b)([^a-zA-Z0-9\s]?)` with `$1expansion$3` replacement — preserves surrounding punctuation (D-03, Pitfall 1 from RESEARCH.md)

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

Build failed on first attempt because DictionaryService.swift was registered in project.pbxproj before the file was created on disk (both tasks share one pbxproj edit). Fixed by creating DictionaryService.swift immediately after registration before running the build check.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- `TextReplacer.replaceAll()` ready for use in Plan 02 (DictionaryView) and Plan 03 (SnippetsView)
- `DictionaryService.shared` and `SnippetService.shared` ready for AppDelegate pipeline wiring in Plan 04
- `DictionaryService.promptCharLimit` constant available for DictionaryView bottom bar
- No blockers for remaining Phase 7 plans

---
*Phase: 07-dictionary-snippets*
*Completed: 2026-03-30*
