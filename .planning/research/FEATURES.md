# Feature Research

**Domain:** macOS dictation app — companion app with transcription history, custom dictionary, and text expansion snippets
**Researched:** 2026-03-30
**Confidence:** HIGH for core patterns (Wispr Flow docs verified); MEDIUM for Whisper prompt mechanics (OpenAI cookbook verified); LOW for competitor internals not publicly documented

## Feature Landscape

This research covers only the new v1.2 milestone features. v1.1 shipped features (overlay, animations, game exclusion, clipboard persistence, blue palette) are treated as foundations.

---

### Table Stakes (Users Expect These)

Features that best-in-class dictation apps universally provide. Missing these makes the companion app feel unfinished.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Timestamped transcription list | Any history feature shows when things happened; without timestamps history is unnavigable | LOW | Store `createdAt: Date` on each SwiftData record; sort descending |
| Date grouping (Today / Yesterday / This Week / Older) | Wispr Flow and every comparable app groups history by time bucket; flat lists are unusable at scale | MEDIUM | Compute section keys from `Calendar.current` comparisons on `createdAt`; `List` with `Section` headers in SwiftUI |
| Copy action per entry | Users open history to re-use text; copy is the primary action | LOW | `UIPasteboard` / `NSPasteboard` write on button tap |
| Delete action per entry | History accumulates; pruning is expected | LOW | `.onDelete` modifier or swipe-to-delete; SwiftData `modelContext.delete(entry)` |
| Full text visible in list | Truncated previews that can't be expanded feel like a bug | LOW | List row shows 2-3 line preview; tapping opens a detail view with full text |
| Sidebar navigation with distinct sections | Companion apps with multiple feature areas (history, dictionary, snippets) require sidebar; tab bars are iOS convention, not macOS | LOW | `NavigationSplitView` with sidebar `.listStyle(.sidebar)`; three items: History, Dictionary, Snippets |
| Dock presence when companion is open | Menu-bar-only apps feel limited; companion app implies standard macOS window | LOW | `LSUIElement = NO` when companion window is open, or separate `NSWindowController` that shows/hides Dock icon via `NSApp.setActivationPolicy(.regular/.accessory)` |

---

### Differentiators (Competitive Advantage)

Features that go beyond what competitors provide or do better in Wave's specific context.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Usage stats (streak, total words, WPM) | Gives users a sense of progress; drives habit formation; Wispr Flow shows WPM per entry but not aggregate streaks | MEDIUM | Streak = consecutive calendar days with at least one transcription; word count = `components(separatedBy: .whitespaces).count`; WPM = words / (duration in minutes) |
| Retry transcript per entry | Users can re-trigger Whisper on a stored audio file if initial transcription was wrong; Wispr Flow has this as a specific changelog feature | MEDIUM | Requires storing raw audio per entry alongside text; audio is non-trivial storage; see dependency notes |
| Dictionary words fed directly into Whisper prompt | Wave controls the full API call, so custom vocabulary is injected as the `prompt` parameter on every transcription — competitors that use black-box APIs cannot do this as precisely | LOW | Format: comma-separated proper nouns / terms appended to any existing prompt string; max 224 tokens total; group by domain for better bias |
| Snippet trigger detection via post-processing | Wave owns the transcription pipeline; after Whisper returns text, a simple string scan checks for any registered trigger phrases and replaces them in-place before pasting | LOW | String replacement pass on `transcribedText`; case-insensitive match; Wispr Flow strips punctuation on standalone-trigger matches — do the same |
| Static text expansion only (no dynamic variables for v1.2) | Simpler to build and explain; Wispr Flow also ships static-only initially | LOW | Store `(trigger: String, expansion: String)` pairs; no date/time interpolation until validated |
| Word count and WPM per history entry | Matches Wispr Flow's per-entry metadata; gives immediate feedback after dictation | LOW | Computed at save time; stored as integers on the model; no recalculation needed |

---

### Anti-Features (Commonly Requested, Often Problematic)

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Audio playback per history entry | Wispr Flow has it; users want to verify transcription accuracy | Storing audio per entry multiplies storage significantly (1 min audio ≈ 1-2 MB compressed); complicates the data model; requires media player UI; file management for deletions | Store text only for v1.2; note "audio playback" as v1.3 feature if demand is confirmed |
| Full-text search across history | Power-user appeal; expected in any list with >50 items | `.searchable` in SwiftUI + SwiftData predicate filtering is straightforward, but adds a non-trivial interaction surface (debounce, empty states, highlight matches); scope risk | Defer to v1.3; the list with date sections is sufficient for initial launch |
| Dynamic snippet variables (today's date, clipboard contents) | TextExpander-style power | Significantly increases parser complexity; edge cases multiply (nested variables, malformed syntax); 80% of snippet use cases are static text | Static text only for v1.2; add date variable as a single special case in v1.3 if users request it |
| Auto-learn vocabulary from history | AI-style "learns what you say" | Requires NLP pass on every transcript; false-positive proper nouns; unclear how to surface additions for user review; scope risk for a minor accuracy gain | Manual dictionary only; let users add terms explicitly |
| Team/shared dictionary and snippets | Enterprise appeal | Requires sync infrastructure, conflict resolution, access control; out of scope per PROJECT.md | Solo user; single-device persistence via SwiftData for now |
| Bulk import/export history | Power user data portability | CSV/JSON parsing, file picker, schema versioning; high complexity for low initial demand | Add copy-all-to-clipboard or "export as text file" as a minimal v1.3 feature |
| Separate Dock icon vs menu-bar icon management UI | Some users want companion always in Dock | Toggling `NSApp.setActivationPolicy` at runtime is fragile; plist `LSUIElement` controls cannot be changed post-launch without restart | Show Dock icon when companion window is open; hide when window closes; no user-facing toggle |

---

## Feature Dependencies

```
[Companion App Shell (NavigationSplitView + sidebar)]
    └──required by──> [History Tab]
    └──required by──> [Dictionary Tab]
    └──required by──> [Snippets Tab]
    └──requires──> [Dock presence toggle logic (NSApp.setActivationPolicy)]

[SwiftData Model Container]
    └──required by──> [History Tab] (TranscriptionEntry model)
    └──required by──> [Dictionary Tab] (DictionaryEntry model)
    └──required by──> [Snippets Tab] (SnippetEntry model)
    └──requires──> [macOS 14+ minimum — already in scope per PROJECT.md]

[History Tab]
    └──requires──> [Recording pipeline writes entry on transcription complete]
    └──enhances──> [Stats (streak, word count, WPM)] (computed from history entries)
    └──optionally──> [Retry transcript] (requires stored audio — defer)

[Dictionary Tab]
    └──enhances──> [Whisper transcription accuracy via prompt injection]
    └──requires──> [WhisperService reads DictionaryEntry list at call time]
    └──independent of──> [Snippets Tab]

[Snippets Tab]
    └──requires──> [Post-processing pass in WhisperService after transcription]
    └──independent of──> [Dictionary Tab]
    └──independent of──> [History Tab]

[Whisper prompt injection (Dictionary)]
    └──requires──> [Dictionary words loaded before API call]
    └──conflicts with──> [Prompt exceeding 224 token limit] (guard: truncate word list if needed)

[Snippet post-processing]
    └──requires──> [Final transcribed text exists]
    └──must run──> after [GPT-4o-mini cleanup] (so snippets apply to cleaned text, not raw ASR)
    └──must run──> before [TextInserter pastes text]
```

### Dependency Notes

- **Companion shell is the foundation:** No history, dictionary, or snippets UI is possible until `NavigationSplitView` shell exists. This must be Phase 1.
- **SwiftData container must exist before any tab:** All three feature tabs read/write SwiftData. The model schema and `ModelContainer` setup must land in the same phase as the shell.
- **Recording pipeline must write history entries:** After `WhisperService` returns a transcript (and after GPT cleanup), `AppDelegate`/`AppState` must persist a `TranscriptionEntry`. This is the critical bridge between the existing pipeline and the new companion.
- **Dictionary injection is low-cost but must be wired into WhisperService:** At the point where the API call is constructed, load dictionary terms, format as a comma-separated prompt prefix, and append to any existing `prompt` parameter. Guard against the 224 token limit.
- **Snippet replacement must run after GPT cleanup, before paste:** Running before cleanup risks the cleanup model paraphrasing the trigger phrase away. Running after ensures the snippet fires on the final, user-visible text.
- **Audio storage for "retry transcript" is a storage risk:** Deferring audio storage eliminates retry as a v1.2 feature. This is the right call — retry requires a separate audio file management system.

---

## MVP Definition (v1.2 Companion App)

### Launch With (v1.2)

- [ ] **Companion window with sidebar navigation** — Three sections: History, Dictionary, Snippets. `NavigationSplitView`. Dock icon shows when window is open.
- [ ] **SwiftData schema** — `TranscriptionEntry`, `DictionaryEntry`, `SnippetEntry` models with `ModelContainer` wired into app lifecycle.
- [ ] **History tab** — Date-grouped list (Today/Yesterday/This Week/Older), per-entry copy and delete, word count and WPM per entry.
- [ ] **Usage stats** — Streak days, total words, average WPM shown at top of History tab.
- [ ] **Dictionary tab** — Add/edit/delete custom vocabulary terms. Terms injected as Whisper `prompt` parameter on each transcription call.
- [ ] **Snippets tab** — Add/edit/delete (trigger, expansion) pairs. Post-processing pass replaces trigger phrases in transcribed text before paste.
- [ ] **Recording pipeline writes to history** — `TranscriptionEntry` created after each successful transcription, capturing text, duration, word count, WPM, timestamp.

### Add After Validation (v1.2.x)

- [ ] **Search in history** — Full-text filter with `.searchable`; add when list grows past ~50 entries in real use.
- [ ] **Date variable in snippets** — Single `{date}` variable that expands to today's date; add if users request dynamic content.
- [ ] **Per-entry "open in source app"** — If source app bundle ID stored with entry, offer re-focus. Requires storing `sourceAppBundleID` on `TranscriptionEntry`.

### Future Consideration (v1.3+)

- [ ] **Audio playback per entry** — Requires audio file storage; defer until v1.3 per PROJECT.md.
- [ ] **Full history search with highlighted matches** — Beyond simple filter; deferred.
- [ ] **Bulk import/export snippets (CSV/JSON)** — Wispr Flow supports 1,000-item bulk import; add if power users request it.
- [ ] **Writing style preferences** — AI rewrite modes per PROJECT.md v1.3 scope.
- [ ] **Notes/scratchpad** — Per PROJECT.md v1.3 scope.

---

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Companion shell + sidebar navigation | HIGH (foundation for everything) | LOW (NavigationSplitView is standard) | P1 |
| SwiftData schema + persistence | HIGH (nothing works without it) | MEDIUM (schema design, migration risk) | P1 |
| Recording pipeline writes history | HIGH (history is useless without data) | MEDIUM (bridge from existing pipeline) | P1 |
| History tab (list + date groups) | HIGH (primary user-facing feature) | MEDIUM (date grouping logic) | P1 |
| Usage stats (streak, word count, WPM) | MEDIUM (nice habit signal) | LOW (computed from history) | P1 |
| Dictionary tab + Whisper prompt injection | HIGH (core accuracy value prop) | LOW (API call modification) | P1 |
| Snippets tab + post-processing replacement | HIGH (automation value prop) | LOW (string scan pass) | P1 |
| Per-entry copy action | HIGH (main reason to open history) | LOW | P1 |
| Per-entry delete action | MEDIUM (hygiene) | LOW | P1 |
| Dock icon management | MEDIUM (macOS convention) | LOW | P1 |
| Search in history | MEDIUM (grows in value with use) | MEDIUM | P2 |
| Per-entry source app tracking | LOW (convenience) | LOW (store bundleID on entry) | P2 |
| Audio playback per entry | MEDIUM (verification) | HIGH (file storage + player) | P3 |
| Dynamic snippet variables | LOW-MEDIUM (power users) | HIGH (parser complexity) | P3 |

**Priority key:**
- P1: Must have for v1.2 launch
- P2: Ship in v1.2 if scope permits, otherwise v1.2.x
- P3: v1.3+ consideration

---

## Competitor Feature Analysis

| Feature | Wispr Flow | Superwhisper | Wave v1.2 Plan |
|---------|------------|--------------|----------------|
| History tab | Yes — date groups (Today/Yesterday/This Week/Last Week/Older), filter by source app, full-text search, sort options, WPM per entry | Meeting notes / file transcription log; not a per-dictation log | Date groups, per-entry copy/delete/WPM; no search at launch |
| Stats | WPM per entry; no aggregate streak visible | Not documented | Streak days, total words, avg WPM in header |
| Retry transcript | Yes — explicitly in changelog; requires stored audio | Not documented | Deferred (requires audio storage) |
| Custom vocabulary / dictionary | Yes — "learns unique words"; likely prompt injection | Yes — "Enter names, abbreviations, specialized terms once. Superwhisper remembers forever." | Manual entry, injected as Whisper `prompt` parameter |
| Snippets / text expansion | Yes — trigger phrase → static expansion; 60-char trigger, 4,000-char expansion; strips punctuation on standalone match | Not documented | Trigger → expansion pairs; post-processing string replacement |
| Bulk snippet import | Yes — up to 1,000 items, 3 MB file | Not documented | Not in v1.2; deferred |
| Companion window / dock presence | Yes — full app with sidebar; dock icon | Yes — full app | NavigationSplitView + dock icon when open |
| Audio playback | Yes — "listen to your recordings to verify accuracy" | Yes (file transcription) | Deferred to v1.3 |

---

## Technical Implementation Notes

### Whisper Prompt Injection for Dictionary

The Whisper API `prompt` parameter accepts up to **224 tokens** (multilingual tokenizer). Format dictionary terms as a comma-separated list of proper nouns/phrases appended to the existing prompt string:

```
"Wave, OpenAI, GPT-4o-mini, Kubernetes, PostgreSQL, [user terms...]"
```

- Longer prompts are more reliable than short ones (OpenAI Cookbook, verified HIGH confidence)
- Group terms by domain when possible ("React, TypeScript, SwiftUI, Xcode" vs a random list)
- Guard: if term list exceeds ~180 tokens, truncate to the most recently added terms (user-controlled order)
- Whisper follows the prompt's spelling for ambiguous phonetics — it cannot override the spoken word, only guide ambiguous transcription

### Snippet Trigger Detection

Post-processing pass after GPT-4o-mini cleanup, before `TextInserter`:

1. Load all `SnippetEntry` records from SwiftData
2. For each entry, do a case-insensitive search for `trigger` in `cleanedText`
3. On match: replace first occurrence with `expansion` (or all occurrences — TBD)
4. Edge case: strip trailing punctuation from the match window (Wispr Flow does this for standalone triggers)
5. Pass modified text to `TextInserter`

Complexity: LOW. No regex required for static triggers — `String.replacingOccurrences(of:with:options:)` with `.caseInsensitive` is sufficient.

### SwiftData Model Schema

Three models needed:

```swift
@Model class TranscriptionEntry {
    var text: String
    var createdAt: Date
    var durationSeconds: Double
    var wordCount: Int
    var wpm: Double
    var sourceAppBundleID: String?   // optional, for v1.2.x
}

@Model class DictionaryEntry {
    var term: String
    var createdAt: Date
}

@Model class SnippetEntry {
    var trigger: String
    var expansion: String
    var createdAt: Date
}
```

Streak calculation: query `TranscriptionEntry` grouped by `Calendar.current.startOfDay(for: createdAt)`, count consecutive days ending today.

### Dock Icon Toggle

```swift
// When companion window opens:
NSApp.setActivationPolicy(.regular)

// When companion window closes (all windows hidden):
NSApp.setActivationPolicy(.accessory)
```

`NSApp.setActivationPolicy` can be called at runtime without restart. `.accessory` = menu-bar-only (no Dock icon, no Cmd+Tab). `.regular` = Dock + Cmd+Tab. This is the standard pattern for hybrid menu-bar / windowed apps.

---

## Sources

- [Wispr Flow Snippets Documentation](https://docs.wisprflow.ai/articles/5784437944-create-and-use-snippets) — Trigger matching behavior, punctuation stripping, 60-char trigger limit, 4,000-char expansion limit (HIGH confidence)
- [Wispr Flow History Changelog](https://roadmap.wisprflow.ai/changelog/view-your-previous-history-and-report-transcriptions) — Date grouping, retry transcript, audio playback features (HIGH confidence)
- [OpenAI Whisper Prompting Guide](https://developers.openai.com/cookbook/examples/whisper_prompting_guide) — 224-token limit, prompt formatting for vocabulary injection, style-vs-instruction behavior (HIGH confidence)
- [Superwhisper](https://superwhisper.com/) — Custom vocabulary feature confirmed; snippets not documented (MEDIUM confidence)
- [Raycast Wispr Flow Extension](https://www.raycast.com/carterm/wispr-flow) — History grouping labels (Today/Yesterday/This Week/Last Week/Older), sort options, WPM metadata per entry (MEDIUM confidence — third-party extension mirroring app's data model)
- [A Fading Thought — AI Dictation True Differentiators](https://afadingthought.substack.com/p/best-ai-dictation-tools-for-mac) — Competitor philosophy analysis (LOW confidence — opinion piece)
- [SwiftData Apple Developer Documentation](https://developer.apple.com/documentation/swiftdata) — `@Model`, `ModelContainer`, macOS 14+ requirement (HIGH confidence)

---

*Feature research for: Wave v1.2 Companion App (history, dictionary, snippets)*
*Researched: 2026-03-30*
