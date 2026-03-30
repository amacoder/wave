# Architecture Research

**Domain:** macOS companion app — v1.2 SwiftData persistence, windowed UI, history, dictionary, snippets
**Researched:** 2026-03-30
**Confidence:** HIGH (codebase read directly; SwiftData and macOS API patterns verified against official docs and WWDC materials)

---

## Existing Architecture Baseline (v1.1)

Before describing what changes, here is the current state that all additions must integrate with.

```
┌─────────────────────────────────────────────────────────────────┐
│  FlowSpeechApp (@main)  →  @NSApplicationDelegateAdaptor        │
│  body: Settings { EmptyView() }   ← menu-bar-only, no window   │
├─────────────────────────────────────────────────────────────────┤
│  AppDelegate (class)                                            │
│  ├── AppState (ObservableObject) — RecordingPhase, settings     │
│  ├── HotkeyManager — CGEventTap + NSEvent flagsChanged          │
│  ├── AudioRecorder — AVFoundation audio capture                 │
│  ├── WhisperService — URLSession → OpenAI API                   │
│  ├── TextCleanupService — GPT-4o-mini post-processing           │
│  ├── TextInserter — NSPasteboard + CGEvent Cmd+V                │
│  ├── AppExclusionService — NSWorkspace + CGWindowListCopyInfo   │
│  └── KeychainManager — SecItem API key storage                  │
├─────────────────────────────────────────────────────────────────┤
│  Windows (all AppDelegate-owned NSWindow instances)             │
│  ├── recordingWindow — borderless floating pill overlay         │
│  ├── settingsWindow — Settings tabbed view (5 tabs)             │
│  └── onboarding — one-time wizard                               │
├─────────────────────────────────────────────────────────────────┤
│  Persistence                                                    │
│  └── UserDefaults only — settings, hotkey prefs, language       │
└─────────────────────────────────────────────────────────────────┘
```

The transcription pipeline in `AppDelegate.transcribe()` is the central point where all v1.2 new features hook in:

```
AudioRecorder → WhisperService → TextCleanupService → TextInserter
```

---

## Target Architecture (v1.2)

```
┌─────────────────────────────────────────────────────────────────┐
│  FlowSpeechApp (@main)                                          │
│  ├── modelContainer: ModelContainer  ← created in init()        │
│  ├── @NSApplicationDelegateAdaptor AppDelegate                  │
│  ├── WindowGroup("Wave", id: "main") { CompanionAppView }       │
│  │     .modelContainer(modelContainer)                          │
│  └── Settings { EmptyView() }                                   │
├─────────────────────────────────────────────────────────────────┤
│  AppDelegate (modified)                                         │
│  ├── All existing services (unchanged)                          │
│  ├── historyService: HistoryService  ← NEW                      │
│  └── transcribe() pipeline with 3 new hooks:                   │
│      1. Dictionary prompt injection → WhisperService            │
│      2. Snippet expansion → TextInserter (post-transcription)   │
│      3. History save → HistoryService (after final text ready)  │
├─────────────────────────────────────────────────────────────────┤
│  Services/ (new additions)                                      │
│  ├── HistoryService — SwiftData background save + fetch         │
│  ├── DictionaryService — loads custom words → Whisper prompt    │
│  └── SnippetService — trigger matching + expansion              │
├─────────────────────────────────────────────────────────────────┤
│  Models/ (new — SwiftData @Model types)                         │
│  ├── TranscriptionEntry — id, text, rawText, date, wordCount    │
│  ├── DictionaryWord — id, word, createdAt                       │
│  └── Snippet — id, trigger, expansion, createdAt               │
├─────────────────────────────────────────────────────────────────┤
│  Views/ (new additions)                                         │
│  ├── CompanionAppView — NavigationSplitView root               │
│  ├── HomeView — transcription history, stats, per-entry actions │
│  ├── DictionaryView — custom word list CRUD                     │
│  └── SnippetsView — trigger/expansion pair CRUD                │
├─────────────────────────────────────────────────────────────────┤
│  Persistence                                                    │
│  ├── UserDefaults — existing settings (unchanged)               │
│  └── SwiftData SQLite store — history, dictionary, snippets     │
└─────────────────────────────────────────────────────────────────┘
```

---

## Component Responsibilities

### New Components

| Component | Responsibility | Implementation |
|-----------|----------------|----------------|
| `HistoryService` | Write entries after transcription; provide read API for HomeView | `@ModelActor` wrapping a background ModelContext |
| `DictionaryService` | Load all DictionaryWords; build prompt string for WhisperService | Fetches from ModelContext; returns `String` |
| `SnippetService` | Check final text for trigger phrases; expand to full text | Pure Swift string scan; no persistence of its own |
| `TranscriptionEntry` | Persisted record of one dictation session | `@Model` class with text, rawText, date, wordCount, duration |
| `DictionaryWord` | One user-defined vocabulary term | `@Model` class with word string and createdAt date |
| `Snippet` | One trigger → expansion mapping | `@Model` class with trigger, expansion, createdAt |
| `CompanionAppView` | Root NavigationSplitView with sidebar | SwiftUI WindowGroup scene |
| `HomeView` | Display history list with date sections and stats | `@Query` for TranscriptionEntry |
| `DictionaryView` | CRUD for DictionaryWord entries | `@Query` + `@Environment(\.modelContext)` |
| `SnippetsView` | CRUD for Snippet entries | `@Query` + `@Environment(\.modelContext)` |

### Modified Components

| Component | What Changes |
|-----------|-------------|
| `FlowSpeechApp` | Add ModelContainer creation; add WindowGroup for companion app |
| `AppDelegate` | Add `historyService`, wire dictionary prompt and snippet expansion into `transcribe()` |
| `AppState` | Add `showInDock: Bool` (already exists — needs to actually drive activation policy) |

---

## SwiftData Integration Pattern

### ModelContainer Ownership

The ModelContainer must be created in `FlowSpeechApp.init()` and shared via `.modelContainer()` modifier. This is the only approach that shares one SQLite file between the WindowGroup views and the background service contexts.

**Confidence: HIGH** — verified against Apple's official SwiftData documentation and WWDC23 "Dive deeper into SwiftData" session.

```swift
@main
struct FlowSpeechApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    let modelContainer: ModelContainer

    init() {
        do {
            let schema = Schema([
                TranscriptionEntry.self,
                DictionaryWord.self,
                Snippet.self
            ])
            modelContainer = try ModelContainer(for: schema)
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup("Wave", id: "main") {
            CompanionAppView()
        }
        .modelContainer(modelContainer)

        Settings {
            EmptyView()
        }
    }
}
```

### Sharing the Container with AppDelegate

AppDelegate creates services before the scene is rendered. Pass the container via the adaptor reference after `applicationDidFinishLaunching`:

```swift
// In AppDelegate.applicationDidFinishLaunching:
// Access via: (NSApp.delegate as? AppDelegate)?.historyService
// But simpler: inject in FlowSpeechApp after init

// In FlowSpeechApp.init():
// After creating modelContainer, inject into appDelegate via the adaptor
// appDelegate.historyService = HistoryService(modelContainer: modelContainer)
```

The cleanest approach: AppDelegate creates HistoryService with a deferred container. FlowSpeechApp sets the container after the adaptor is initialized.

```swift
// FlowSpeechApp
init() {
    // ...create modelContainer...
    // Wire into AppDelegate after adaptor exists:
    appDelegate.configure(modelContainer: modelContainer)
}
```

### Background Save (HistoryService)

AppDelegate's `transcribe()` runs in a Swift `Task` (async context). SwiftData's `ModelContext` is not Sendable — it must be used on its actor. Use `@ModelActor` macro for background operations.

**Confidence: HIGH** — verified against "Use SwiftData like a boss" (Medium, 2024) and Apple Developer Forums thread/763500.

```swift
@ModelActor
actor HistoryService {
    func save(text: String, rawText: String, duration: TimeInterval, wordCount: Int) async throws {
        let entry = TranscriptionEntry(
            text: text,
            rawText: rawText,
            date: Date(),
            duration: duration,
            wordCount: wordCount
        )
        modelContext.insert(entry)
        try modelContext.save()
    }

    func recentEntries(limit: Int = 100) async throws -> [TranscriptionEntry] {
        let descriptor = FetchDescriptor<TranscriptionEntry>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }
}
```

### Views Use @Query Directly

Views should use SwiftData's `@Query` property wrapper — they get the main context via the environment from `.modelContainer()` on the WindowGroup.

```swift
struct HomeView: View {
    @Query(sort: \TranscriptionEntry.date, order: .reverse) var entries: [TranscriptionEntry]
    @Environment(\.modelContext) private var context

    var body: some View {
        List(entries) { entry in
            EntryRowView(entry: entry)
        }
    }
}
```

---

## Windowed App Integration

### Activation Policy (Dock Icon)

The existing `AppState.showInDock: Bool` setting exists but is not yet wired to actual dock visibility. In v1.2, the companion window needs dock presence to be reachable. The pattern:

- Default: `.accessory` policy (menu-bar-only, existing behavior)
- When companion window opens: call `NSApp.setActivationPolicy(.regular)`
- When companion window closes (and no others open): call `NSApp.setActivationPolicy(.accessory)`

**Confidence: MEDIUM** — NSApp.setActivationPolicy is well-documented, but toggling at runtime has a known quirk where all windows may briefly hide. Workaround: delay 0.3s after switching to `.regular` before calling `makeKeyAndOrderFront`.

```swift
// In AppDelegate — open companion app
func openCompanionApp() {
    NSApp.setActivationPolicy(.regular)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        // Open the WindowGroup window via openWindow environment action
        // or direct NSWindow manipulation
        NSApp.activate(ignoringOtherApps: true)
    }
}
```

### WindowGroup vs. Window Scene

Use `WindowGroup` not `Window` (the single-instance variant). `WindowGroup` is the standard for document-style companion apps and allows the system to manage window restoration. The "Wave" companion app is not a document app, but `WindowGroup` with a unique `id:` parameter behaves like a single named window on macOS.

### Sidebar Structure

`NavigationSplitView` with three items: Home, Dictionary, Snippets. This is the standard macOS sidebar navigation pattern (Files, Mail, etc.).

```swift
struct CompanionAppView: View {
    @State private var selection: SidebarItem? = .home

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selection) { item in
                Label(item.title, systemImage: item.icon)
            }
            .listStyle(.sidebar)
        } detail: {
            switch selection {
            case .home: HomeView()
            case .dictionary: DictionaryView()
            case .snippets: SnippetsView()
            case nil: HomeView()
            }
        }
    }
}

enum SidebarItem: String, CaseIterable, Identifiable {
    case home, dictionary, snippets
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var icon: String {
        switch self {
        case .home: return "clock"
        case .dictionary: return "character.book.closed"
        case .snippets: return "text.badge.plus"
        }
    }
}
```

---

## Dictionary → Whisper Integration

The Whisper API `prompt` parameter (already wired in `WhisperService.transcribe()` as an optional `String?`) is the correct injection point. The dictionary feeds a comma-separated or sentence-format prompt.

**Confidence: HIGH** — WhisperService already accepts `prompt: String?`. OpenAI docs confirm prompt parameter improves recognition of custom words (verified against https://platform.openai.com/docs/guides/speech-to-text).

**Key constraint:** Whisper-1 only uses the final 224 tokens of the prompt. Keep dictionary prompts short — recommend max 50 words. GPT-4o-transcribe handles longer prompts better but the same limit principle applies.

### DictionaryService

```swift
class DictionaryService {
    private let modelContainer: ModelContainer

    func buildPrompt() async -> String? {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<DictionaryWord>(
            sortBy: [SortDescriptor(\.word)]
        )
        guard let words = try? context.fetch(descriptor), !words.isEmpty else {
            return nil
        }
        // Format as a natural sentence to help Whisper recognize the words
        return words.map(\.word).joined(separator: ", ")
    }
}
```

### Integration Point in AppDelegate.transcribe()

```swift
// In transcribe(audioURL:), before calling whisperService.transcribe():
let dictionaryPrompt = await dictionaryService.buildPrompt()

let transcription = try await whisperService.transcribe(
    audioURL: audioURL,
    apiKey: apiKey,
    model: appState.selectedModel,
    language: appState.language == "auto" ? nil : appState.language,
    prompt: dictionaryPrompt  // passes nil if dictionary is empty — no change to existing behavior
)
```

The `prompt:` parameter is already accepted by `WhisperService.transcribe()` — this is a zero-structural-change integration. Only the call site in `AppDelegate` needs updating.

---

## Snippets Integration

Snippets are text expansion: if the transcribed text contains a trigger phrase, replace it with the full expansion. This happens **after** transcription and cleanup, **before** `textInserter.insertText()`.

### SnippetService

```swift
class SnippetService {
    private let modelContainer: ModelContainer

    // Returns expanded text if any snippet trigger matched; otherwise original text
    func expand(text: String) async -> String {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<Snippet>()
        guard let snippets = try? context.fetch(descriptor), !snippets.isEmpty else {
            return text
        }

        var result = text
        for snippet in snippets {
            // Case-insensitive whole-word match
            result = result.replacingOccurrences(
                of: snippet.trigger,
                with: snippet.expansion,
                options: [.caseInsensitive]
            )
        }
        return result
    }
}
```

### Integration Point in AppDelegate.transcribe()

```swift
// After cleanup, before text insertion:
var finalText = transcription
if appState.smartCleanup {
    finalText = await cleanupService.cleanup(text: transcription, apiKey: apiKey)
}

// Snippet expansion — new step
finalText = await snippetService.expand(text: finalText)

// History save — new step
try? await historyService.save(
    text: finalText,
    rawText: transcription,
    duration: recordingDuration,
    wordCount: finalText.split(separator: " ").count
)

// Existing text insertion (unchanged)
if appState.autoInsertText {
    textInserter.insertText(finalText)
}
```

---

## Data Models

### TranscriptionEntry

```swift
@Model
final class TranscriptionEntry {
    var id: UUID
    var text: String          // final text after cleanup + snippet expansion
    var rawText: String       // original Whisper output before any processing
    var date: Date
    var duration: TimeInterval  // recording duration in seconds
    var wordCount: Int

    init(text: String, rawText: String, date: Date = .now,
         duration: TimeInterval = 0, wordCount: Int = 0) {
        self.id = UUID()
        self.text = text
        self.rawText = rawText
        self.date = date
        self.duration = duration
        self.wordCount = wordCount
    }
}
```

### DictionaryWord

```swift
@Model
final class DictionaryWord {
    var id: UUID
    var word: String
    var createdAt: Date

    init(word: String) {
        self.id = UUID()
        self.word = word
        self.createdAt = .now
    }
}
```

### Snippet

```swift
@Model
final class Snippet {
    var id: UUID
    var trigger: String     // what the user says
    var expansion: String   // what gets inserted
    var createdAt: Date

    init(trigger: String, expansion: String) {
        self.id = UUID()
        self.trigger = trigger
        self.expansion = expansion
        self.createdAt = .now
    }
}
```

---

## Recommended File Structure (v1.2 additions)

```
FlowSpeech/
├── AppDelegate.swift            (modify — wire history, dictionary, snippets into transcribe())
├── FlowSpeechApp.swift          (modify — add ModelContainer, WindowGroup)
├── DesignSystem.swift           (no change)
├── Models/                      (NEW folder)
│   ├── TranscriptionEntry.swift
│   ├── DictionaryWord.swift
│   └── Snippet.swift
├── Services/
│   ├── AudioRecorder.swift      (no change)
│   ├── WhisperService.swift     (no change — prompt param already exists)
│   ├── TextCleanupService.swift (no change)
│   ├── TextInserter.swift       (no change)
│   ├── HotkeyManager.swift      (no change)
│   ├── KeychainManager.swift    (no change)
│   ├── AppExclusionService.swift (no change)
│   ├── HistoryService.swift     (NEW — @ModelActor, background save/fetch)
│   ├── DictionaryService.swift  (NEW — builds Whisper prompt from DictionaryWords)
│   └── SnippetService.swift     (NEW — trigger matching + text expansion)
└── Views/
    ├── RecordingOverlayView.swift   (no change)
    ├── SettingsView.swift           (no change)
    ├── MenuBarPopoverView.swift     (no change)
    ├── OnboardingView.swift         (no change)
    ├── ExclusionSettingsTab.swift   (no change)
    ├── CompanionAppView.swift       (NEW — NavigationSplitView root)
    ├── HomeView.swift               (NEW — history list with date groupings + stats)
    ├── DictionaryView.swift         (NEW — word list CRUD)
    └── SnippetsView.swift           (NEW — snippet pair CRUD)
```

---

## Data Flow

### Transcription Pipeline (v1.2 — annotated)

```
User holds hotkey
    ↓
AppDelegate.startRecording()
AppState.phase = .recording
AudioRecorder.startRecording()

User releases hotkey
    ↓
AppDelegate.stopRecordingAndTranscribe()
AudioRecorder.stopRecording() → audioURL

                              ┌──────────────────────────────────┐
                              │  DictionaryService.buildPrompt() │
                              │  fetch DictionaryWords → String? │
                              └──────────────┬───────────────────┘
                                             ↓
WhisperService.transcribe(audioURL, prompt: dictionaryPrompt)
    → rawTranscription: String

TextCleanupService.cleanup(rawTranscription) [if smartCleanup enabled]
    → cleanedText: String

                              ┌──────────────────────────────────┐
                              │  SnippetService.expand(text)     │
                              │  scan for trigger phrases        │
                              └──────────────┬───────────────────┘
                                             ↓
                                    finalText: String

                              ┌──────────────────────────────────┐
                              │  HistoryService.save(finalText)  │
                              │  insert TranscriptionEntry       │
                              │  @ModelActor background context  │
                              └──────────────────────────────────┘
                                             ↓
TextInserter.insertText(finalText) [if autoInsertText]
AppState.phase = .done → .idle
HomeView auto-refreshes via @Query (main context notified by SwiftData merge)
```

### ModelContainer Flow

```
FlowSpeechApp.init()
    └── ModelContainer(schema: [TranscriptionEntry, DictionaryWord, Snippet])
            │
            ├── .modelContainer(modelContainer) on WindowGroup
            │       → injects into SwiftUI environment
            │       → @Query in HomeView, DictionaryView, SnippetsView
            │       → @Environment(\.modelContext) for inserts/deletes
            │
            └── injected into AppDelegate via configure(modelContainer:)
                    → HistoryService(@ModelActor) ← background save
                    → DictionaryService ← builds prompt (reads only)
                    → SnippetService ← reads snippets for expansion
```

### Dock Icon State Flow

```
App launch
    → NSApp.setActivationPolicy(.accessory)   ← menu-bar-only, no dock icon

User clicks menu bar item → "Open Wave"
    → AppDelegate.openCompanionApp()
    → NSApp.setActivationPolicy(.regular)
    → delay 0.1s
    → activate WindowGroup window
    → NSApp.activate()

User closes companion window
    → windowWillClose notification
    → if no other windows open: NSApp.setActivationPolicy(.accessory)
```

---

## Build Order (Dependency-Aware)

Dependencies flow: Models → Services → AppDelegate wiring → Views → WindowGroup scene.

### Step 1 — Data Models (no UI, no AppDelegate changes)

1. Create `Models/TranscriptionEntry.swift` (`@Model` class)
2. Create `Models/DictionaryWord.swift` (`@Model` class)
3. Create `Models/Snippet.swift` (`@Model` class)

**Why first:** Everything downstream depends on these types. Zero risk to existing functionality.

### Step 2 — ModelContainer Setup

4. Modify `FlowSpeechApp.swift`: create `ModelContainer` in `init()`, add `WindowGroup` scene with `.modelContainer()`
5. Add `AppDelegate.configure(modelContainer:)` method (called from FlowSpeechApp after adaptor init)

**Why second:** Services need the container reference. The WindowGroup can exist before views are written — it will just show an empty view until Step 5.

### Step 3 — HistoryService

6. Create `Services/HistoryService.swift` with `@ModelActor` and `save()` method
7. Wire into `AppDelegate.transcribe()`: call `historyService.save()` after final text is ready

**Why third:** History save is purely additive to the pipeline. No existing behavior changes. Verify entries appear in the SQLite store using Xcode's data model inspector before building any UI.

### Step 4 — Dictionary Feature (end-to-end before any UI polish)

8. Create `Services/DictionaryService.swift`
9. Wire into `AppDelegate.transcribe()`: call `dictionaryService.buildPrompt()`, pass to `whisperService.transcribe()`
10. Create `Views/DictionaryView.swift` (CRUD for DictionaryWord)

**Why fourth:** Dictionary has a complete user-visible loop (add word → dictate → see improvement). Building the view before history UI lets you test the Whisper prompt integration with real audio.

### Step 5 — Snippets Feature

11. Create `Services/SnippetService.swift`
12. Wire into `AppDelegate.transcribe()`: call `snippetService.expand()` after cleanup
13. Create `Views/SnippetsView.swift` (CRUD for Snippet pairs)

**Why fifth:** Depends on Step 3 (history should save the expanded text, not pre-expansion). Independent of dictionary.

### Step 6 — Companion App Window + HomeView

14. Create `Views/CompanionAppView.swift` (NavigationSplitView root)
15. Create `Views/HomeView.swift` (history list with date groupings and stats)
16. Wire dock icon toggle in AppDelegate (openCompanionApp, windowWillClose handler)
17. Add "Open Wave" menu bar item pointing to openCompanionApp

**Why last:** HomeView is the most complex view (grouping, stats, per-entry actions). The underlying data (history entries from Step 3) will already be populated by the time this UI lands. Building the window infrastructure before the views means you can incrementally add views to a working shell.

---

## Integration Points

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| AppDelegate ↔ HistoryService | `await historyService.save(...)` | Async, background actor. Fire-and-forget is acceptable (use `try?`) |
| AppDelegate ↔ DictionaryService | `await dictionaryService.buildPrompt()` | Reads only. Returns `String?` — nil means empty dictionary, no prompt sent |
| AppDelegate ↔ SnippetService | `await snippetService.expand(text:)` | Pure transformation. Returns original text if no snippets match |
| HomeView ↔ ModelContainer | `@Query` property wrapper | Automatic re-render on new entries. No polling needed |
| DictionaryView ↔ ModelContext | `@Environment(\.modelContext)` | Insert/delete via modelContext directly |
| SnippetsView ↔ ModelContext | `@Environment(\.modelContext)` | Insert/delete via modelContext directly |

### Where the transcription pipeline is modified (AppDelegate.transcribe())

This is the single most important integration point. The current pipeline at lines 278-322 of `AppDelegate.swift` becomes:

```
Line 279: dictionaryPrompt = await dictionaryService.buildPrompt()  ← INSERT
Line 280: transcription = try await whisperService.transcribe(..., prompt: dictionaryPrompt)
Line 287: finalText = await cleanupService.cleanup(...)
Line 290: finalText = await snippetService.expand(text: finalText)  ← INSERT
Line 291: try? await historyService.save(text: finalText, ...)      ← INSERT
Line 292: await MainActor.run { ... }  ← existing block, no change
```

Three new `await` calls added to a function that is already async. No threading model changes required.

---

## Architectural Patterns

### Pattern 1: @ModelActor for Background Persistence

**What:** Annotate service classes with `@ModelActor` (WWDC24 macro) to bind them to a background Swift actor. The macro creates an isolated executor using the ModelContainer.

**When to use:** Any service that writes to SwiftData from non-UI code (AppDelegate's transcription pipeline).

**Trade-offs:**
- Pro: Swift compiler enforces thread safety — no manual DispatchQueue.main juggling
- Pro: Background saves don't block the main thread or UI
- Con: ModelObjects fetched on background actor cannot be passed to views directly — pass `PersistentIdentifier` or raw value types instead

### Pattern 2: @Query for Reactive Views

**What:** SwiftUI views declare their data needs with `@Query`. SwiftData automatically notifies views when the underlying store changes (including changes from background contexts).

**When to use:** All list views in the companion app (HomeView, DictionaryView, SnippetsView).

**Trade-offs:**
- Pro: Zero boilerplate — no NSFetchedResultsController equivalent needed
- Pro: Works automatically across actor boundaries (main context reflects background saves)
- Con: Limited sorting/filtering expressiveness compared to NSPredicate (though sufficient for this app)

### Pattern 3: Prompt Passthrough for Dictionary

**What:** DictionaryService builds a `String?` prompt that flows through the existing `prompt:` parameter of `WhisperService.transcribe()`. No new API surface on WhisperService.

**When to use:** When adding behavior that maps directly to an existing API parameter.

**Trade-offs:**
- Pro: WhisperService is unchanged; the integration is at the call site only
- Pro: Empty dictionary gracefully becomes `nil` prompt — identical to current behavior
- Con: Prompt is limited to ~224 tokens for whisper-1; extremely large dictionaries will be silently truncated

### Pattern 4: Snippet Post-Processing as Pure Transformation

**What:** SnippetService takes a String in and returns a String out. No side effects, no state mutation.

**When to use:** Text transformation that doesn't need to persist anything itself.

**Trade-offs:**
- Pro: Trivial to test; trivial to move earlier/later in pipeline
- Pro: SnippetService reads from SwiftData but only for the snippet list — no write operations
- Con: Triggers are matched as substrings (case-insensitive) — need to define rules for partial vs. whole-word matching before implementation

---

## Anti-Patterns to Avoid

### Anti-Pattern 1: Creating Multiple ModelContainers

**What people do:** Create a new ModelContainer in each service or view that needs persistence.

**Why it's wrong:** Multiple containers pointing to the same SQLite file will corrupt the store or produce merge conflicts. SwiftData is not designed for multiple container instances.

**Do this instead:** Create exactly one ModelContainer in `FlowSpeechApp.init()`, share it via `.modelContainer()` to views, and inject it directly into services via `configure(modelContainer:)` on AppDelegate.

### Anti-Pattern 2: Using modelContext from a SwiftUI View in AppDelegate

**What people do:** Reach into the SwiftUI environment to get the main ModelContext for use in AppDelegate/services.

**Why it's wrong:** There is no clean way to get the environment ModelContext from outside the SwiftUI view hierarchy. It leads to force-unwrapping or notification hacks.

**Do this instead:** Services own their own ModelContext (created from the shared ModelContainer). The service's context is separate from the view's context; SwiftData handles merging automatically.

### Anti-Pattern 3: Storing History in AppState

**What people do:** Accumulate transcription history as a `[String]` array in AppState (ObservableObject), then serialize to UserDefaults.

**Why it's wrong:** UserDefaults has a soft limit (~1MB total) and is not designed for append-only log data. History can grow to thousands of entries quickly (daily dictation user → 1000+ entries/year).

**Do this instead:** SwiftData's SQLite store handles arbitrary amounts of entries efficiently with indexed queries.

### Anti-Pattern 4: Snippet Expansion Before Cleanup

**What people do:** Apply snippet expansion to the raw Whisper output before running TextCleanupService.

**Why it's wrong:** Whisper may transcribe a trigger phrase with different capitalization or with surrounding filler words that cleanup would remove. Expanding before cleanup means the expansion sees uncleaned text.

**Do this instead:** Apply snippets after cleanup — the final transformation step before text insertion.

### Anti-Pattern 5: Blocking Main Thread in buildPrompt()

**What people do:** Call DictionaryService.buildPrompt() synchronously on the main thread before passing to WhisperService.

**Why it's wrong:** `transcribe()` is already an `async` function. ModelContext fetch is fast but should not block main thread.

**Do this instead:** `buildPrompt()` is `async` and creates its own ModelContext from the container. The `transcribe()` call site uses `await`. No UI blocking.

---

## Scaling Considerations

This is a single-user local app. The relevant dimension is data volume over time.

| Concern | At 100 entries | At 10,000 entries | At 100,000 entries |
|---------|----------------|-------------------|--------------------|
| HomeView render | Instant | Instant with `@Query` fetch limit | Paginate or limit query to 1000 |
| Dictionary prompt | ~50 words recommended | N/A — UI should warn at 50+ words | N/A |
| Snippet scan | O(n×m) scan — negligible | Still negligible (<100 snippets) | N/A |
| SQLite store size | ~50KB | ~5MB | ~50MB — fine |

**Practical limit:** Whisper prompt parameter (224 tokens for whisper-1) is the binding constraint for dictionary size, not SwiftData performance. Enforce a soft cap of 50 words in DictionaryView UI.

---

## Sources

- [SwiftData — Apple Developer Documentation](https://developer.apple.com/documentation/swiftdata)
- [ModelContainer — Apple Developer Documentation](https://developer.apple.com/documentation/swiftdata/modelcontainer)
- [Dive deeper into SwiftData — WWDC23](https://developer.apple.com/videos/play/wwdc2023/10196/)
- [Track model changes with SwiftData history — WWDC24](https://developer.apple.com/videos/play/wwdc2024/10075/)
- [What's new in SwiftData — WWDC24](https://developer.apple.com/videos/play/wwdc2024/10137/)
- [How to create a background context — Hacking with Swift](https://www.hackingwithswift.com/quick-start/swiftdata/how-to-create-a-background-context)
- [Using ModelActor in SwiftData — BrightDigit](https://brightdigit.com/tutorials/swiftdata-modelactor/)
- [Configuring SwiftData in a SwiftUI app — polpiella.dev](https://www.polpiella.dev/configuring-swiftdata-in-a-swiftui-app)
- [NSApplicationActivationPolicy.regular — Apple Developer Documentation](https://developer.apple.com/documentation/appkit/nsapplication/activationpolicy-swift.enum/regular)
- [Fine-Tuning macOS App Activation Behavior — artlasovsky.com](https://artlasovsky.com/fine-tuning-macos-app-activation-behavior)
- [OpenAI Speech-to-Text API — prompt parameter](https://platform.openai.com/docs/guides/speech-to-text)
- [Whisper prompting guide — OpenAI Cookbook](https://developers.openai.com/cookbook/examples/whisper_prompting_guide)
- Direct codebase analysis: AppDelegate.swift, FlowSpeechApp.swift, WhisperService.swift, TextInserter.swift (read 2026-03-30)

---

*Architecture research for: Wave v1.2 — companion app, SwiftData persistence, history, dictionary, snippets*
*Researched: 2026-03-30*
