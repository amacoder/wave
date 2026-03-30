# Project Research Summary

**Project:** Wave v1.2 — Companion App
**Domain:** macOS dictation app — windowed companion with transcription history, custom dictionary, and text expansion snippets added to existing v1.1 menu-bar-only app
**Researched:** 2026-03-30
**Confidence:** HIGH

## Executive Summary

Wave v1.2 adds a companion window to an existing menu-bar dictation app. The well-worn macOS pattern for this class of app is a `NavigationSplitView`-based sidebar window managed as a SwiftUI `WindowGroup` scene, with SwiftData providing local SQLite persistence. All four new feature areas (companion shell, history, dictionary, snippets) build on top of a single shared `ModelContainer` initialized once in `FlowSpeechApp.init()` and injected into both the view hierarchy and AppDelegate-owned services. No new dependencies are required — the entire feature set is achievable with the macOS 14 SDK already in scope for the project.

The recommended build order is strictly dependency-driven: data models first, then `ModelContainer` wiring, then backend services (`HistoryService`, `DictionaryService`, `SnippetService`) wired into `AppDelegate.transcribe()`, then companion views last. This order means each phase is independently testable before building the next layer. The three pipeline hooks (dictionary prompt injection, snippet expansion, history save) are each single-`await`-call additions to an already-async function. Dictionary and snippets are the lowest-complexity features and should be built before the complex history UI, not after.

The most consequential risks are architectural, not implementation-level. Using `NSHostingView` for the companion window instead of `WindowGroup` silently breaks `@Query` (blank data, no error). Toggling `NSApp.setActivationPolicy()` dynamically hides all open windows including the recording overlay. Both decisions are irreversible once the window infrastructure is built — they must be made correctly in the foundation phase. The other critical risk is unbounded history growth: a `fetchLimit` and retention policy must ship from day one, not be added retroactively.

---

## Key Findings

### Recommended Stack

The v1.1 codebase is left entirely untouched. All additions target the macOS 14 SDK with no SPM packages. The single architectural addition is a shared `ModelContainer` initialized in `FlowSpeechApp.init()` and threaded into AppDelegate via a `configure(modelContainer:)` method.

See full details: [.planning/research/STACK.md](.planning/research/STACK.md)

**Core technologies:**
- **SwiftData** (`@Model`, `@Query`, `ModelContainer`): Persistent storage for history, dictionary, snippets — explicitly chosen over GRDB in PROJECT.md; SQLite-backed with tight SwiftUI integration; macOS 14+ only (already in scope)
- **SwiftUI `NavigationSplitView`**: Sidebar + detail layout — handles resize, collapse, and macOS conventions automatically; two-column layout is sufficient
- **SwiftUI `WindowGroup` + `openWindow`**: Manages companion window lifecycle; `openWindow(id:)` de-duplicates (brings existing window to front); must be used over manual `NSWindow` for `@Query` to function correctly
- **`NSApp.setActivationPolicy(_:)`**: Dock icon toggle — `.regular` when companion is open, `.accessory` when closed; must be committed to permanently after first open, never toggled dynamically mid-session

**Critical SwiftData patterns to follow:**
- Single shared `ModelContainer`, never multiple instances (confirmed crash bug with multiple containers)
- `@ModelActor` for background saves from the transcription pipeline (HistoryService)
- `@Query` with child-view-init trick for dynamic sorting
- Explicit `try? modelContext.save()` after every insert (auto-save is unreliable)
- Simple predicates only; group/filter in Swift after fetch (complex predicates hit compiler limits)
- `VersionedSchema` defined from the v1 schema even if no migration is needed yet

### Expected Features

The feature set is well-benchmarked against Wispr Flow, which ships an equivalent companion app. Wave v1.2 targets parity on all core features with two meaningful differentiators: dictionary injection directly into the Whisper API `prompt` parameter (competitors using black-box APIs cannot do this as precisely), and full ownership of the transcription pipeline end-to-end.

See full details: [.planning/research/FEATURES.md](.planning/research/FEATURES.md)

**Must have (table stakes):**
- Companion window with sidebar navigation (History, Dictionary, Snippets) — macOS convention; tab bars are iOS, not macOS
- Date-grouped history list (Today / Yesterday / This Week / Older) — flat lists are unusable at scale; Wispr Flow parity
- Per-entry copy and delete actions — copy is the primary reason to open history
- Word count and WPM per entry — computed at save time; Wispr Flow parity
- Usage stats header (streak, total words, avg WPM) — habit-formation signal
- Dictionary tab with Whisper `prompt` injection — core accuracy value prop; Wave differentiator
- Snippets tab with post-processing trigger replacement — automation value prop
- Dock presence when companion is open — macOS convention

**Should have (competitive differentiators):**
- Recording pipeline writes `TranscriptionEntry` on every successful transcription — without this, history is useless
- Dictionary terms as Whisper prompt — Wave owns the full API call; competitors cannot do this as precisely
- Usage streak (consecutive days) — Wispr Flow lacks aggregate streak; Wave differentiator

**Defer (v1.2.x / v1.3+):**
- Full-text history search — add when list grows past ~50 entries in real use
- Audio playback per entry — requires audio file storage system; scope risk
- Dynamic snippet variables (date, clipboard contents) — parser complexity; 80% of use cases are static
- Bulk snippet import/export — only when power users request it
- Auto-learn vocabulary from history — NLP complexity with false positives; no clear UX

### Architecture Approach

The existing `AppDelegate.transcribe()` pipeline is the single integration point for all three new backend features. Three `await` calls are inserted into this already-async function: `dictionaryService.buildPrompt()` before the Whisper call, `snippetService.expand(text:)` after GPT cleanup, and `historyService.save(...)` after snippet expansion. No threading model changes are needed. The companion views are entirely decoupled from the pipeline — they observe the same SwiftData store via `@Query` and auto-refresh when background saves land.

See full details: [.planning/research/ARCHITECTURE.md](.planning/research/ARCHITECTURE.md)

**Major components:**
1. **`HistoryService` (`@ModelActor`)** — background actor that saves `TranscriptionEntry` records after each dictation; Swift compiler enforces thread safety via the macro
2. **`DictionaryService`** — reads `DictionaryWord` records, builds comma-separated prompt string; returns `nil` if dictionary is empty (preserving existing WhisperService behavior unchanged)
3. **`SnippetService`** — pure string transformation; reads `Snippet` records, applies case-insensitive trigger replacement to final text before paste; must run after GPT cleanup, before `TextInserter`
4. **`CompanionAppView` (NavigationSplitView)** — root view of the `WindowGroup` scene; sidebar with Home/Dictionary/Snippets; detail column switches on selection
5. **`HomeView`** — history list with `@Query`, date-section grouping via `Dictionary(grouping:)` in the view layer, usage stats header; most complex view — built last
6. **`DictionaryView` + `SnippetsView`** — CRUD views using `@Query` + `@Environment(\.modelContext)`; straightforward list-with-add-sheet pattern

**Build order:** Models → ModelContainer → HistoryService + pipeline wiring → DictionaryService + DictionaryView → SnippetService + SnippetsView → CompanionAppView + HomeView + dock toggle

### Critical Pitfalls

See full details: [.planning/research/PITFALLS.md](.planning/research/PITFALLS.md)

1. **`setActivationPolicy(.regular/.accessory)` hides all open windows** — calling this mid-session causes the recording overlay and settings window to disappear. Prevention: commit to permanent dock presence after first companion open; persist a `hasEverOpenedCompanion` flag; never toggle policy mid-session; set activation policy in `applicationWillFinishLaunching`, not `applicationDidFinishLaunching`.

2. **`@Query` silently fails in `NSHostingView`-hosted views** — history list shows empty with no error. Prevention: companion window must use SwiftUI `WindowGroup` with `.modelContainer()` at the scene level; do not create a manual `NSWindow` for the companion.

3. **Passing `PersistentModel` instances across actor boundaries crashes** — SwiftData models are not `Sendable`; crash is non-deterministic and surfaces in production. Prevention: map to a plain `Sendable` struct before any actor boundary crossing; `HistoryService` writes using its own `@ModelActor` context, never passing model objects out.

4. **Companion window opening steals focus from dictation target** — `NSApp.activate()` changes frontmost app, causing `TextInserter` to paste into the companion instead of the user's document. Prevention: snapshot `NSWorkspace.shared.frontmostApplication` at recording start; restore focus before `Cmd+V`; gate companion window open behind `appState.phase == .idle`.

5. **Unbounded history store causes slow opens after months of use** — a moderate user accumulates 7,000+ records/year; `@Query` with no limit loads all into memory. Prevention: set `fetchLimit = 200` in `@Query`; implement 90-day retention at save time; ship both from day one, not retroactively.

---

## Implications for Roadmap

Based on the dependency graph from FEATURES.md and the build order from ARCHITECTURE.md, a 4-phase structure is strongly supported by the research.

### Phase 1: Foundation — Companion Window Shell + Data Layer

**Rationale:** The companion window is required by all three feature tabs. The `ModelContainer` is required by all three services. Both must exist before any feature work begins. The windowing architecture decision (`WindowGroup`, not `NSHostingView`) and the activation policy strategy are irreversible once made — they must be correct here or the entire feature set breaks in silent, hard-to-diagnose ways (Pitfalls 1, 2, 11).

**Delivers:** An openable companion window with `NavigationSplitView` sidebar (Home, Dictionary, Snippets sections in empty state), SwiftData schema (`TranscriptionEntry`, `DictionaryWord`, `Snippet`) compiled and schema-versioned, `ModelContainer` wired into both scene and AppDelegate via `configure(modelContainer:)`, dock icon appearance/disappearance working correctly, `NotificationCenter` bridge for `openWindow` from AppDelegate.

**Addresses:** Sidebar navigation, dock presence (table stakes from FEATURES.md)

**Avoids:** Pitfall 1 (activation policy hides all windows), Pitfall 2 (@Query silent failure in NSHostingView), Pitfall 4 (companion open steals focus), Pitfall 11 (openWindow fails from AppDelegate)

**Research flag:** Standard patterns — skip `/gsd:research-phase`. `WindowGroup`, `NavigationSplitView`, and `setActivationPolicy` are all well-documented by multiple HIGH-confidence sources.

---

### Phase 2: History — Pipeline Save + HomeView

**Rationale:** History is the highest user-value feature and requires wiring the transcription pipeline. `HistoryService` should be built and verified against the live SQLite store before `HomeView` is written, so the data layer is validated independently. `fetchLimit` and retention policy must ship in this phase (Pitfall 5).

**Delivers:** `HistoryService` (`@ModelActor`) saving `TranscriptionEntry` after each transcription; `HomeView` with date-grouped list (Today/Yesterday/This Week/Older), per-entry copy/delete, word count and WPM per entry, usage stats header (streak, total words, avg WPM); `fetchLimit = 200` and 90-day retention from day one.

**Addresses:** Timestamped transcription list, date grouping, copy/delete actions, word count + WPM, usage stats (all P1 from FEATURES.md)

**Avoids:** Pitfall 3 (PersistentModel across actors — use Sendable snapshots), Pitfall 5 (unbounded store — fetchLimit + retention), Pitfall 9 (@Query re-fetch flash — background context save + `includePendingChanges: false`)

**Research flag:** Standard patterns — `@ModelActor`, `@Query`, `Dictionary(grouping:)` for date sections are all well-documented. No research phase needed.

---

### Phase 3: Dictionary + Snippets — Pipeline Features

**Rationale:** Dictionary and snippets share the same structure (CRUD views + a pipeline hook) and are independent of each other, making them natural Phase 3 siblings. Dictionary goes first because its pipeline hook is a zero-risk modification to the existing optional `prompt:` parameter already accepted by `WhisperService`. Snippets go second because the correct position in the pipeline (after GPT cleanup, before paste) is easier to verify once the full pipeline has been exercised.

**Delivers:** `DictionaryService` with Whisper `prompt` injection; `DictionaryView` CRUD with character counter and 800-char prompt cap warning; `SnippetService` with case-insensitive trigger replacement; `SnippetsView` CRUD; snippet monitor pause/resume around the recording→insertion window.

**Addresses:** Dictionary tab + Whisper prompt injection, snippets tab + post-processing replacement (P1 features from FEATURES.md)

**Avoids:** Pitfall 6 (prompt silently truncated — 800-char cap, counter in UI), Pitfall 7 (snippet fires during dictation — pause monitor), Pitfall 12 (special chars break prompt — sanitize at entry), Pitfall 13 (snippet fires on synthetic paste — `isSynthesizingPaste` flag)

**Research flag:** Standard patterns — skip `/gsd:research-phase`. Whisper `prompt` parameter is documented by OpenAI (HIGH confidence); string replacement for snippets is trivial.

---

### Phase 4: Integration Polish — Focus Restoration + Edge Cases

**Rationale:** After the three feature phases exist independently, interaction edge cases between subsystems become testable. Focus restoration (Pitfall 4) and overlay first-responder behavior (Pitfall 14) require both the recording pipeline and companion window to exist simultaneously. This phase uses the "Looks Done But Isn't" checklist from PITFALLS.md as its acceptance criteria.

**Delivers:** Target app focus snapshotted at recording start and restored before paste; recording overlay prevented from becoming key window (`canBecomeKey = false`); companion window open gated behind `appState.phase == .idle`; full acceptance test pass against PITFALLS.md checklist.

**Addresses:** Focus restoration correctness, overlay/companion interaction, regression validation

**Avoids:** Pitfall 4 (focus stealing), Pitfall 14 (overlay steals first responder from companion text fields)

**Research flag:** Standard patterns — skip `/gsd:research-phase`. AppKit window management APIs are stable and well-documented.

---

### Phase Ordering Rationale

- **Foundation before features:** `WindowGroup` and `ModelContainer` are hard prerequisites for every feature tab. This is not optional — deferring them creates unbuildable features.
- **Pipeline services before views:** `HistoryService` verified against a live SQLite store before `HomeView` is built means data layer bugs are caught without UI noise. The pattern holds for Dictionary and Snippets too.
- **Dictionary before snippets:** Dictionary prompt injection is genuinely zero-risk (nil-safe optional parameter already exists on WhisperService). Snippets introduce a new event monitoring concern that benefits from seeing the full pipeline first.
- **Integration polish last:** Edge cases involving multiple subsystems (recording + companion window open simultaneously) can only be tested and fixed after both subsystems exist.
- **All critical pitfalls are addressed in-phase**, not patched on: Pitfalls 1/2/4/11 in Phase 1, Pitfalls 3/5/9 in Phase 2, Pitfalls 6/7/12/13 in Phase 3, Pitfalls 8/14 in Phase 4.

### Research Flags

**Skip research phase for all phases.** The entire feature set uses well-documented Apple-first APIs with multiple HIGH-confidence sources. The pitfalls are catalogued with concrete prevention patterns. No phase involves third-party integrations, niche APIs, or underdocumented behavior.

If a spike is warranted anywhere, the `setActivationPolicy` timing (the 0.1s delay for avoiding window-hiding behavior) is best validated with a targeted build test in Phase 1 rather than a research phase.

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All technologies are official Apple APIs with no guesswork. SwiftData bugs are catalogued from Apple Developer Forums and community analysis with concrete mitigations. |
| Features | HIGH | Core features verified against Wispr Flow public docs and changelog. Whisper prompt mechanics verified against OpenAI official cookbook. Competitor internals are LOW confidence but only affect anti-feature decisions, not build decisions. |
| Architecture | HIGH | Codebase read directly (AppDelegate.swift, FlowSpeechApp.swift, WhisperService.swift confirmed 2026-03-30). Build order derived from actual dependency graph. Integration points are specific line numbers in existing files. |
| Pitfalls | HIGH | Critical pitfalls (activation policy, @Query environment, PersistentModel thread safety) each have multiple corroborating sources including Apple Developer Forums threads. Prevention patterns are concrete and implementation-ready. |

**Overall confidence: HIGH**

### Gaps to Address

- **`setActivationPolicy` exact timing:** The 0.1s delay in ARCHITECTURE.md and `applicationWillFinishLaunching` timing in PITFALLS.md may need adjustment on specific hardware. Validate with a spike in Phase 1.
- **Snippet partial vs. whole-word matching:** ARCHITECTURE.md flags this as "need to define rules before implementation." Wispr Flow strips punctuation on standalone triggers. The exact behavior for Wave should be decided before Phase 3 begins.
- **`@Query` pagination UX for large histories:** `@Query` does not support cursor-based pagination natively. Phase 2 will need to implement a manual `FetchDescriptor` with increasing offset for "load more" behavior — implementation pattern should be decided at Phase 2 planning time.
- **`VersionedSchema` forward planning:** The v1 schema should sketch anticipated v1.3 fields (`sourceAppBundleID`, audio file path) during Phase 1 data model work so lightweight migrations can be planned in advance.

---

## Sources

### Primary (HIGH confidence)
- [Apple Developer Documentation: SwiftData](https://developer.apple.com/documentation/swiftdata) — ModelContainer, @Model, @Query, macOS 14+ requirements
- [Apple Developer Documentation: NavigationSplitView](https://developer.apple.com/documentation/swiftui/navigationsplitview) — sidebar layout patterns
- [Apple Developer Documentation: openWindow](https://developer.apple.com/documentation/swiftui/environmentvalues/openwindow) — WindowGroup scene management
- [WWDC23: Dive deeper into SwiftData](https://developer.apple.com/videos/play/wwdc2023/10196/) — ModelContainer ownership, sharing between scenes and services
- [WWDC24: What's new in SwiftData](https://developer.apple.com/videos/play/wwdc2024/10137/) — @ModelActor macro, background context patterns
- [OpenAI Whisper Prompting Guide](https://cookbook.openai.com/examples/whisper_prompting_guide) — 224-token limit, prompt formatting for vocabulary injection
- [OpenAI Speech-to-Text API](https://platform.openai.com/docs/guides/speech-to-text) — prompt parameter behavior confirmed
- [Wispr Flow Snippets Documentation](https://docs.wisprflow.ai/articles/5784437944-create-and-use-snippets) — trigger matching, punctuation stripping, 60-char trigger limit, 4,000-char expansion limit
- [Wispr Flow History Changelog](https://roadmap.wisprflow.ai/changelog/view-your-previous-history-and-report-transcriptions) — date grouping labels, retry transcript, audio playback features
- Direct codebase analysis: AppDelegate.swift, FlowSpeechApp.swift, WhisperService.swift, TextInserter.swift (read 2026-03-30)

### Secondary (MEDIUM confidence)
- [SwiftData Pitfalls — Wade Tregaskis](https://wadetregaskis.com/swiftdata-pitfalls/) — comprehensive SwiftData bug catalogue; consistent with Apple forum reports
- [SwiftData Issues in macOS 14 — Michael Tsai](https://mjtsai.com/blog/2024/06/04/swiftdata-issues-in-macos-14-and-ios-17/) — aggregation of confirmed forum reports
- [Taking SwiftData Further: @ModelActor — Medium](https://killlilwinters.medium.com/taking-swiftdata-further-modelactor-swift-concurrency-and-avoiding-mainactor-pitfalls-3692f61f2fa1) — @ModelActor threading pitfalls
- [Concurrent Programming in SwiftData — fatbobman.com](https://fatbobman.com/en/posts/concurret-programming-in-swiftdata/) — PersistentModel cross-actor crash behavior
- [SwiftData Fetching Pending Changes — Use Your Loaf](https://useyourloaf.com/blog/swiftdata-fetching-pending-changes/) — @Query re-fetch over-notification behavior
- [Fine-Tuning macOS App Activation Behavior — artlasovsky.com](https://artlasovsky.com/fine-tuning-macos-app-activation-behavior) — setActivationPolicy timing and flash prevention
- [Apple Developer Forums: ModelContext not available in NSHostingView](https://developer.apple.com/forums/thread/740864) — @Query silent failure confirmed
- [Deep dive into dynamic SwiftData queries — Medium/Gaignet](https://medium.com/@matgnt/deep-dive-into-dynamic-swiftdata-queries-9d029568dd8f) — child-view-init pattern for dynamic @Query
- [SwiftUI for Mac 2024 — TrozWare](https://troz.net/post/2024/swiftui-mac-2024/) — WindowGroup variants on macOS

### Tertiary (LOW confidence)
- [A Fading Thought — AI Dictation True Differentiators](https://afadingthought.substack.com/p/best-ai-dictation-tools-for-mac) — competitor philosophy analysis; opinion piece used only for anti-feature decisions

---
*Research completed: 2026-03-30*
*Ready for roadmap: yes*
