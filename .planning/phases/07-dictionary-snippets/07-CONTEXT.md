# Phase 7: Dictionary & Snippets - Context

**Gathered:** 2026-03-30
**Status:** Ready for planning

<domain>
## Phase Boundary

Users can teach Wave custom vocabulary that improves Whisper transcription accuracy (vocabulary hints fed into the Whisper API prompt parameter), add abbreviation expansions that replace terms post-transcription, and create trigger-phrase snippets that auto-expand into longer text after each dictation. Both Dictionary and Snippets tabs get full CRUD views replacing their current placeholders. Two new services: DictionaryService (prompt construction + abbreviation expansion) and SnippetService (trigger matching + text replacement).

</domain>

<decisions>
## Implementation Decisions

### Snippet matching behavior
- **D-01:** Whole-word matching only — trigger "addr" matches standalone "addr" but not "address"
- **D-02:** Case sensitivity — Claude's discretion (case-insensitive recommended given Whisper output variability)
- **D-03:** Strip adjacent punctuation before matching — "sig." and "sig," both match trigger "sig"
- **D-04:** Multiple triggers can fire in a single transcription — all matches expanded in one pass

### Dictionary prompt strategy
- **D-05:** Whisper prompt format — Claude's discretion (comma-separated list vs context sentences)
- **D-06:** Token cap prioritization — Claude's discretion (most-recently-added-first recommended)
- **D-07:** Abbreviation replacements run as post-transcription text replacement using the same engine as snippets — not relying on Whisper prompt alone

### Pipeline integration
- **D-08:** Pipeline order (locked from STATE.md): Whisper → GPT-4o-mini cleanup → abbreviation expansion + snippet expansion → paste
- **D-09:** Dictionary vocabulary hints (non-abbreviation entries) are injected into WhisperService.transcribe() prompt parameter
- **D-10:** Abbreviations and snippets share the same post-transcription replacement engine — one code path for both

### Dictionary tab layout
- **D-11:** Simple list with toolbar + button at top, search bar, scrollable list of entries
- **D-12:** Vocabulary hints show term only; abbreviations show "term → replacement" format
- **D-13:** Add/edit via inline sheet with term field, optional replacement field, isAbbreviation toggle
- **D-14:** Persistent bottom bar showing character/token count toward 224-token Whisper prompt limit with color progression (green → yellow → red)
- **D-15:** Delete via hover trash icon (matching Phase 6 history pattern)

### Snippets tab layout
- **D-16:** Same list pattern as Dictionary — toolbar + button, search bar, scrollable list
- **D-17:** Each entry shows trigger on first line, "→ expansion text..." on second line
- **D-18:** Long expansion text truncated with ellipsis (~60 chars) in list view
- **D-19:** Add/edit via sheet with "Trigger phrase" text field and "Expands to" multi-line text area
- **D-20:** Delete via hover trash icon (same pattern as dictionary and history)

### Claude's Discretion
- Case-insensitive vs case-sensitive snippet matching (D-02)
- Whisper prompt format: comma-separated list vs context sentences (D-05)
- Token cap prioritization strategy (D-06)
- Exact SF Symbol choices for toolbar buttons and empty states
- Sheet styling and animation details
- Token count color thresholds
- Search implementation details (local filter vs @Query predicate)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirements
- `.planning/REQUIREMENTS.md` — DICT-01 through DICT-05 and SNIP-01 through SNIP-04 define acceptance criteria

### Architecture & state
- `.planning/PROJECT.md` — App architecture, service layer, design system details
- `.planning/STATE.md` — Pipeline order decision, snippet matching blocker note, accumulated context

### Prior phase context
- `.planning/phases/05-companion-shell/05-CONTEXT.md` — SwiftData models (DictionaryWord, Snippet), ModelContainer setup, sidebar navigation, companion window architecture
- `.planning/phases/06-history/06-CONTEXT.md` — Pipeline save hook pattern, hover action pattern (copy/delete), list design conventions

### Existing code
- `FlowSpeech/Models/DictionaryWord.swift` — SwiftData model with term, replacement?, isAbbreviation, createdAt
- `FlowSpeech/Models/Snippet.swift` — SwiftData model with trigger, expansion, createdAt
- `FlowSpeech/Views/CompanionWindow/DictionaryView.swift` — Current placeholder (EmptyStateView) to be replaced
- `FlowSpeech/Views/CompanionWindow/SnippetsView.swift` — Current placeholder (EmptyStateView) to be replaced
- `FlowSpeech/Services/WhisperService.swift` — Already accepts `prompt:` parameter (line 38) — dictionary injection point
- `FlowSpeech/AppDelegate.swift` — Transcription pipeline: `transcribe()` at line 287, `finalText` computed at line 317-320, snippet/abbreviation expansion inserts after line 320 before paste at line 365

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `DictionaryWord` model: Already defined with term, replacement?, isAbbreviation flag — ready for @Query
- `Snippet` model: Already defined with trigger, expansion — ready for @Query
- `EmptyStateView`: Reusable empty state component for when lists are empty
- `DesignSystem.Colors`: Palette tokens for consistent styling
- `WhisperService.transcribe(prompt:)`: Already accepts optional prompt string — no API changes needed

### Established Patterns
- WindowGroup scene with `.modelContainer()` — @Query works in all companion views
- Phase 6 hover actions: trash icon appears on hover for delete (reuse same pattern)
- Phase 6 save hook: Background ModelContext for SwiftData writes from AppDelegate
- Phase 6 undo toast: Could reuse for dictionary/snippet delete if desired

### Integration Points
- `WhisperService.transcribe()` line 38: Pass constructed prompt from DictionaryService
- `AppDelegate.transcribe()` line 309-313: Wire DictionaryService to build prompt before Whisper call
- `AppDelegate.transcribe()` line 317-320: Insert SnippetService expansion after GPT cleanup, before save/paste
- `DictionaryView.swift`: Replace EmptyStateView with full CRUD list
- `SnippetsView.swift`: Replace EmptyStateView with full CRUD list

</code_context>

<specifics>
## Specific Ideas

- Dictionary and Snippets tabs follow the same visual pattern: toolbar + button, search, scrollable list, hover delete — consistent companion app feel
- Abbreviation expansion and snippet expansion share one replacement engine — DRY, one behavior to test
- Token count bar at bottom of Dictionary is always visible, color-coded like a progress bar approaching a limit
- Delete pattern matches Phase 6 history (hover trash icon) for consistency across all three tabs

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 07-dictionary-snippets*
*Context gathered: 2026-03-30*
