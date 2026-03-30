# Stack Research

**Domain:** macOS companion app additions — SwiftData persistence, windowed UI with sidebar navigation, transcription history, custom dictionary, text expansion snippets
**Researched:** 2026-03-30
**Confidence:** MEDIUM-HIGH (Apple-first stack; SwiftData bugs are real but manageable for this scope and data volume)

---

## Context: What Already Exists (Do Not Re-Research)

The existing Wave codebase (v1.1.1) already has and does not need changes to:
- SwiftUI + AppDelegate hybrid (NSHostingView inside NSWindow)
- AppKit (NSStatusBar, NSWindow, NSEvent, CGEvent, NSPasteboard)
- Combine (used in AppDelegate for reactive subscriptions)
- AVFoundation (AudioRecorder)
- Settings stored in UserDefaults + Keychain
- AppState as an ObservableObject passed via environmentObject

This research covers only the **additions** required for the v1.2 companion app milestone.

---

## Recommended Stack

### Core Technologies — New Capabilities Only

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| SwiftData | macOS 14+ (built-in) | Persistent storage for history, dictionary, snippets | Already decided in PROJECT.md (`SwiftData over GRDB/raw SQLite` key decision). SQLite-backed, no dependencies. Tight SwiftUI integration via `@Query` and `@Model`. macOS 14+ is acceptable per project constraints. |
| SwiftUI `NavigationSplitView` | macOS 13+ (built-in) | Sidebar + detail layout for companion window | The native pattern for macOS sidebar apps. Renders translucent sidebar automatically. Handles column visibility, keyboard navigation, and macOS window conventions. Two columns sufficient: sidebar (nav items) + detail (content). |
| SwiftUI `WindowGroup` + `openWindow` | macOS 13+ (built-in) | Opening the companion window from menu bar or hotkey | `openWindow(id:)` environment action brings an existing window to front if already open — critical for single-instance companion windows. Cleaner lifecycle than raw NSWindow for this use case. |
| `NSApp.setActivationPolicy(_:)` | AppKit (macOS 10.6+) | Toggle dock icon when companion window opens/closes | The established pattern for menu bar apps that conditionally show a dock icon. `.regular` shows dock presence + menu bar; `.accessory` removes both. Integrates directly with existing AppDelegate. |

### Supporting Patterns — No New Libraries

| Pattern | Purpose | Integration Point |
|---------|---------|-------------------|
| Single shared `ModelContainer` | Avoid multiple-container crash bug | Initialize once in `FlowSpeechApp.body` or `AppDelegate.applicationDidFinishLaunching`, inject via `.modelContainer()` modifier |
| `@Query` with dynamic sort via child view init | History sorted by date descending, filterable | Parent view owns sort/filter state; child view receives it in `init` and builds `@Query` from it — the standard SwiftData workaround for dynamic queries |
| `Dictionary(grouping:)` on fetched results | Date-section grouping for history list | Done in the view layer on the `@Query` result; avoids complex `#Predicate` expressions that hit compiler limits |
| Explicit `try? modelContext.save()` after mutations | Guard against SwiftData auto-save unreliability | Called after every insert/delete; wraps cleanly in a `PersistenceService` helper |
| `VersionedSchema` defined from day one | Future-safe schema migration | Define even for v1 schema — adding it retroactively requires more manual migration work |

---

## Installation

No SPM package dependencies to add. All capabilities are in the macOS 14 SDK.

**Changes to project setup:**

1. Add `import SwiftData` to model and service files
2. Register `ModelContainer` in `FlowSpeechApp.body`:

```swift
@main
struct FlowSpeechApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup("Wave", id: "companion") {
            CompanionView()
        }
        .modelContainer(AppDelegate.sharedModelContainer)

        Settings {
            SettingsView()
                .environmentObject(appDelegate.appState)
        }
    }
}
```

3. Expose `static let sharedModelContainer: ModelContainer` from `AppDelegate` so both the scene and AppDelegate's transcription save path share one container.

---

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| SwiftData | Core Data | If targeting macOS 13 or earlier, or if data models have complex many-to-many relationships needing custom SQL. Core Data is more battle-tested. For this project (3 simple models, macOS 14+ already required, PROJECT.md explicitly chose SwiftData) — SwiftData is correct. |
| SwiftData | GRDB + SQLite | If query performance becomes critical (tens of thousands of entries) or SwiftData's predicate limitations block needed filtering. GRDB gives full SQL control. Defer unless actually needed — not warranted at this data volume. |
| SwiftData | JSON files in Application Support | Acceptable for snippets and dictionary (small, bounded datasets) but not for history (unbounded, needs date-range queries). Mixing persistence approaches adds complexity for no benefit. |
| `NavigationSplitView` | Custom `HSplitView` | Only if design requires pixel-exact sidebar control that NavigationSplitView's column system cannot accommodate. NavigationSplitView handles resize, collapse, and macOS sidebar conventions for free. |
| `WindowGroup` + `openWindow` | Manual NSWindow management in AppDelegate | The project already uses NSWindow for overlay and settings — both are acceptable candidates for raw NSWindow because they have atypical behavior (overlay is borderless/floating; settings already works). The companion window follows standard macOS window conventions and benefits from SwiftUI scene lifecycle, state restoration, and the openWindow de-duplication behavior. |

---

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| Multiple `ModelContainer` instances | Confirmed crash bug on macOS 14 when the same `@Model` type appears in more than one `ModelContainer` in the same process. Apple developer forums confirm this. | Single shared `ModelContainer` initialized once, accessed as a static or injected via environment |
| `@AppStorage` for history data | `UserDefaults` is not designed for collections or unbounded data. No query capability. Plist format has no practical size limit but serializing arrays of structs through Codable on every access is expensive. | SwiftData `@Model` + `@Query` |
| CloudKit sync in `ModelConfiguration` | Not needed for solo user. Adds `#Unique` constraint incompatibilities and unpredictable merge behavior. Zero user benefit at this stage. | Plain local SwiftData without `.cloudKit(...)` configuration |
| `@ModelActor` for the primary transcription save | `@ModelActor` is for background-thread batch operations (importing, bulk deletes). Transcription saves are one record per dictation — a single lightweight insert on the main context is correct and simpler. Background actor adds concurrency complexity with no benefit at this write frequency. | Direct `modelContext.insert()` on main `ModelContext` in transcription completion handler |
| Complex `#Predicate` expressions | The SwiftData predicate macro has known compiler limits — expressions with more than 3-4 conditions or optional chaining cause "expression too complex" errors. Date bucketing predicates are especially problematic. | Fetch with simple predicate (or no predicate), then filter/group in Swift |
| Core Data alongside SwiftData | There is no existing Core Data store in Wave to migrate from — introducing Core Data now is pure complexity with no benefit. | SwiftData only |

---

## Stack Patterns by Variant

**Injecting ModelContainer from AppDelegate into SwiftUI scenes:**

AppDelegate needs to save transcriptions via `ModelContext`. The scene needs to provide `ModelContext` to views via `@Query`. Both must use the same container. Pattern: expose a `static let sharedModelContainer` from `AppDelegate` initialized in a `static var` block. `FlowSpeechApp` references it in the `.modelContainer()` modifier.

**Dynamic `@Query` for history (sorted, filterable):**

`@Query` does not accept dynamic sort descriptors directly in the property wrapper. Workaround: the outer view owns sort state (`@State var sortOrder: SortOrder`), passes it to a child view `HistoryListView(sortOrder: sortOrder)`, and inside `HistoryListView.init` the `@Query` is constructed:

```swift
struct HistoryListView: View {
    @Query private var entries: [TranscriptionEntry]

    init(sortOrder: SortOrder) {
        _entries = Query(sort: \TranscriptionEntry.timestamp, order: sortOrder)
    }
}
```

**Date-grouped history sections:**

Group in the view layer after the `@Query` fetch — do not attempt this in `#Predicate`:

```swift
let grouped = Dictionary(grouping: entries) { entry in
    Calendar.current.startOfDay(for: entry.timestamp)
}
let sortedDays = grouped.keys.sorted(by: >)
```

Render each day as a `Section` with a localized header ("Today", "Yesterday", or formatted date string using `RelativeDateTimeFormatter` or `DateFormatter`).

**Dock presence toggle:**

```swift
// Call when companion window opens (NSWindowDelegate.windowDidBecomeKey or openWindow callback):
NSApp.setActivationPolicy(.regular)

// Call when companion window closes and no other regular windows remain:
NSApp.setActivationPolicy(.accessory)
```

There is a brief visual flicker on toggle — this is the standard behavior seen in Bear, Fantastical, and similar apps. Accept it; no workaround that avoids the flicker is stable across macOS versions.

**Snippet trigger matching at transcription time:**

After `finalText` is produced in `AppDelegate.transcribe()`, scan the text for snippet triggers before text insertion. Pattern: fetch all snippets once (cache in `AppDelegate` or `PersistenceService`), then do a string scan:

```swift
var processed = finalText
for snippet in cachedSnippets {
    processed = processed.replacingOccurrences(of: snippet.trigger, with: snippet.expansion)
}
```

This runs synchronously on the main thread before `textInserter.insertText()` — acceptable given the O(n) scan over a small snippet list (typically < 100 entries).

---

## Version Compatibility

| Component | Requirement | Notes |
|-----------|-------------|-------|
| SwiftData (`@Model`, `@Query`, `ModelContainer`) | macOS 14.0+ | PROJECT.md specifies macOS 14+ as acceptable. Do not add `@available` guards — just require 14+ in deployment target. |
| `NavigationSplitView` | macOS 13.0+ | Available since Ventura; safe unconditionally given macOS 14+ target |
| `openWindow` environment action | macOS 13.0+ | Available since Ventura; safe unconditionally |
| `NSApp.setActivationPolicy(_:)` | macOS 10.6+ | Long-standing stable API; no compatibility concern |
| `@ModelActor` macro | macOS 14.0+, Xcode 15+ | Only needed if background batch operations become necessary — not required for v1.2 feature set |
| `VersionedSchema` + `SchemaMigrationPlan` | macOS 14.0+ | Define v1 schema as `VersionedSchema` from the start; lightweight migrations (add property with default value) require no custom code |

---

## Known SwiftData Bugs to Design Around (macOS 14, as of 2024)

These are confirmed issues reported in Apple Developer Forums and community analysis. The patterns above already account for them:

| Bug | Impact on Wave | Mitigation Already Embedded |
|-----|---------------|----------------------------|
| Auto-save unreliable; changes lost on unexpected quit | Transcription entries could be lost | Explicit `try? modelContext.save()` after each `insert()` |
| Arrays of `@Model` objects randomly reordered on reload | History order wrong without sort | Always use `SortDescriptor` on `timestamp` in `@Query`; never rely on fetch order |
| Non-optional relationship properties are secretly nullable; runtime crash on access | Relationships between models would crash | Keep all model-to-model relationships as Swift optionals; guard before accessing |
| Complex `#Predicate` expressions cause compiler errors | Date-range or multi-condition queries fail to compile | Simple predicates only; group/filter in Swift after fetch |
| Same `@Model` type in multiple `ModelContainer` crashes | N/A if architecture is correct | Enforced by single shared `ModelContainer` pattern above |
| `ModelContext.didSave` / `willSave` notifications do not fire | Cannot observe context saves reactively | Not needed for this feature set; use `@Query` for reactive UI updates instead |

---

## Recommended Data Model Shapes

These shapes are informed by the feature requirements and SwiftData constraints. Exact field names are for the implementation phase.

**TranscriptionEntry** — one record per dictation
- `id: UUID` (default)
- `timestamp: Date` (indexed; primary sort key; used for date grouping)
- `text: String` (the final transcribed + processed text)
- `rawText: String?` (pre-cleanup text, for "retry transcript" action)
- `duration: Double` (recording duration in seconds; used for WPM calculation)
- `wordCount: Int` (computed at save time from `text.split(separator: " ").count`)
- `model: String` (Whisper model rawValue used, e.g. `"gpt-4o-transcribe"`)

**DictionaryTerm** — user vocabulary / corrections
- `id: UUID`
- `term: String` (the word or phrase; unique)
- `createdAt: Date`
- Note: no relationship to `TranscriptionEntry` — terms are injected into the Whisper API `prompt` parameter at transcription time, not linked to entries

**Snippet** — text expansion rules
- `id: UUID`
- `trigger: String` (spoken or typed phrase; unique; case-insensitive match recommended)
- `expansion: String` (the full text to substitute)
- `createdAt: Date`
- `useCount: Int` (incremented each time snippet fires; useful for stats display)

---

## Sources

- [SwiftData Architecture Patterns — AzamSharp (March 2025)](https://azamsharp.com/2025/03/28/swiftdata-architecture-patterns-and-practices.html) — MEDIUM confidence (current patterns, pragmatic guidance)
- [SwiftData Pitfalls — Wade Tregaskis](https://wadetregaskis.com/swiftdata-pitfalls/) — HIGH confidence (detailed technical analysis; consistent with Apple forum reports)
- [SwiftData Issues in macOS 14 — Michael Tsai (June 2024)](https://mjtsai.com/blog/2024/06/04/swiftdata-issues-in-macos-14-and-ios-17/) — HIGH confidence (aggregation of confirmed forum reports)
- [Apple Developer Docs: ModelContainer](https://developer.apple.com/documentation/swiftdata/modelcontainer) — HIGH confidence (official)
- [Apple Developer Docs: NavigationSplitView](https://developer.apple.com/documentation/swiftui/navigationsplitview) — HIGH confidence (official)
- [Apple Developer Docs: openWindow environment value](https://developer.apple.com/documentation/swiftui/environmentvalues/openwindow) — HIGH confidence (official)
- [SwiftUI for Mac 2024 — TrozWare](https://troz.net/post/2024/swiftui-mac-2024/) — MEDIUM confidence (well-maintained community article, covers WindowGroup variants)
- [Toggle macOS dock icon — artlasovsky GitHub](https://github.com/artlasovsky/toggle-macos-dock-icon) — MEDIUM confidence (working code reference for activation policy toggle)
- [HackingWithSwift: ModelContainer/ModelContext differences](https://www.hackingwithswift.com/quick-start/swiftdata/whats-the-difference-between-modelcontainer-modelcontext-and-modelconfiguration) — MEDIUM confidence
- [HackingWithSwift: SwiftData Lightweight vs Complex Migrations](https://www.hackingwithswift.com/quick-start/swiftdata/lightweight-vs-complex-migrations) — MEDIUM confidence
- [SwiftData background contexts — Use Your Loaf](https://useyourloaf.com/blog/swiftdata-background-tasks/) — MEDIUM confidence
- [Deep dive into dynamic SwiftData queries — Mathis Gaignet](https://medium.com/@matgnt/deep-dive-into-dynamic-swiftdata-queries-9d029568dd8f) — MEDIUM confidence (dynamic @Query child-view-init pattern)

---

*Stack research for: Wave v1.2 companion app (SwiftData persistence + windowed UI)*
*Researched: 2026-03-30*
