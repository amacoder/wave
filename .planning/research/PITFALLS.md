# Domain Pitfalls — v1.2 Companion App

**Domain:** Adding windowed companion app (history, dictionary, snippets) to existing macOS menu-bar dictation app
**Researched:** 2026-03-30
**Confidence:** HIGH for LSUIElement/activation pitfalls and SwiftData threading (multiple developer accounts, Apple forums); MEDIUM for snippet/CGEvent interaction (inference from architecture); HIGH for Whisper prompt limit (official OpenAI docs)

---

## Critical Pitfalls

Mistakes that cause rewrites, data loss, or require TCC permission re-grants.

---

### Pitfall 1: `setActivationPolicy(.regular)` Hides All Windows Immediately

**What goes wrong:**
When the companion window is opened from the menu bar (a `.accessory` activation-policy app), calling `NSApp.setActivationPolicy(.regular)` to make the dock icon appear causes macOS to immediately hide all currently visible windows. The overlay and any open settings window both disappear before the companion window finishes presenting. When switching back to `.accessory` to hide the dock icon later, the same thing happens: all windows hide again.

**Why it happens:**
`NSApp.setActivationPolicy(.accessory)` was designed for apps that never show regular windows. When you toggle it at runtime, AppKit interprets it as "return to background-only mode" and hides the entire window stack. This is a documented side effect with no workaround that preserves existing window state. Reference: [NSApp.setActivationPolicy(.accessory) hides all windows](https://github.com/onmyway133/notes/issues/569).

**Consequences:**
- Recording overlay disappears mid-dictation when companion opens
- Settings window closes unexpectedly
- User loses window context; feels broken

**Prevention:**
Make the dock/no-dock state a one-way decision at launch time, not a dynamic toggle. The cleanest approach for Wave:

1. Remove `LSUIElement = true` from Info.plist entirely.
2. At app launch, dynamically set `NSApp.setActivationPolicy(.accessory)` if the companion has never been opened (maintaining current menu-bar-only feel).
3. Once the companion is opened for the first time, persist a flag in UserDefaults (`hasEverOpenedCompanion`) and switch to `.regular` policy permanently.
4. If users want to hide the dock icon, respect it at next launch rather than mid-session.

Alternative if you must keep dynamic toggling: never show the overlay or settings while transitioning between policies. Gate all window operations behind an `isTransitioningPolicy` semaphore with a 200ms delay.

**Detection:**
- Build + open companion window → overlay disappears
- Open Settings → switch to companion → Settings closes unexpectedly

**Phase to address:** Companion App foundation phase — must be architected before any windowing work, not patched on.

---

### Pitfall 2: SwiftData `@Query` Silently Fails in Views Hosted by `NSHostingView`

**What goes wrong:**
`@Query` annotated properties in SwiftUI views work when the view is presented through SwiftUI's `WindowGroup` or `Window` scene, but fail silently (or crash with "Set a .modelContext in view's environment to use Query") when the view is hosted via `NSHostingView` in a manually-managed `NSWindow`. The companion window, which the app currently creates manually in `AppDelegate`, falls into this trap. Views render but no data appears.

**Why it happens:**
`@Query` relies on the SwiftUI environment key `\.modelContext` being injected by the scene infrastructure. When you create an `NSHostingView` directly, you bypass the scene graph. The `.modelContainer()` modifier on a view embedded in `NSHostingView` does propagate the environment correctly, but `@Query` has a secondary dependency on the container being registered through the scene system (for automatic save and change tracking). This is a known issue documented on Apple Developer Forums ([ModelContext for SwiftData is not available](https://developer.apple.com/forums/thread/740864)).

**Consequences:**
- History list shows empty even with records in the store
- No crash, no visible error — just blank UI

**Prevention:**
Two valid approaches:

Option A (Recommended): Migrate the companion window to a SwiftUI `WindowGroup` scene in `FlowSpeechApp`. Use the `openWindow` environment action to open it programmatically from `AppDelegate` via a `NotificationCenter` post. Attach `.modelContainer(sharedContainer)` at the `WindowGroup` level. This makes `@Query` work automatically.

```swift
// FlowSpeechApp.swift
@main
struct FlowSpeechApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    let container = try! ModelContainer(for: TranscriptionRecord.self, DictionaryEntry.self, Snippet.self)

    var body: some Scene {
        WindowGroup("Wave", id: "companion") {
            CompanionView()
        }
        .modelContainer(container)
        .defaultSize(width: 900, height: 600)
        .defaultPosition(.center)

        Settings {
            SettingsView()
        }
    }
}
```

Option B (Keep manual NSWindow): Inject `container.mainContext` explicitly via the environment on `NSHostingView`:

```swift
NSHostingView(rootView: CompanionView().environment(\.modelContext, container.mainContext))
```

Do NOT use `@Query` in views hosted this way — use explicit `FetchDescriptor` calls with the injected `modelContext` instead.

**Detection:**
- History tab shows no entries despite confirmed saves
- Console shows "Set a .modelContext in view's environment" at app launch

**Phase to address:** Phase 1 of companion app — the window architecture decision locks in which option is correct.

---

### Pitfall 3: Passing `PersistentModel` Instances Across Actor Boundaries Crashes

**What goes wrong:**
`TranscriptionRecord` objects fetched on the `@MainActor` context (via `@Query` or direct fetch) are passed into a background `Task` for processing — for example, to re-run cleanup on a history entry. This crashes with `EXC_BAD_ACCESS` or produces undefined behavior. Models look thread-safe (they're `class` types) but are not `Sendable`.

**Why it happens:**
SwiftData models hold a reference to their `ModelContext`. Accessing a `PersistentModel` from a different thread than its context's queue is unsupported. The crash often manifests not at the pass site but later, during deallocation or the next autosave cycle. From Apple Developer Forums: "After the fetch operation, when models (PersistentModel) are passed to other functions and threads, they retain their context. Changing a field in one model across different threads can lead to an application crash." ([Concurrent Programming in SwiftData](https://fatbobman.com/en/posts/concurret-programming-in-swiftdata/)).

**Consequences:**
- Non-deterministic crash that only appears under concurrent load
- Hard to reproduce in development; surfaces in production use

**Prevention:**
Never pass `PersistentModel` instances across actor boundaries. Map to a plain `Sendable` struct before crossing:

```swift
// Safe: convert before crossing actor boundary
struct TranscriptionSnapshot: Sendable {
    let id: PersistentIdentifier
    let text: String
    let date: Date
}

// In @MainActor context:
let snapshot = TranscriptionSnapshot(id: record.persistentModelID, text: record.text, date: record.date)

// Now safe to pass to background task:
Task.detached {
    await process(snapshot)
}
```

For background writes, use `@ModelActor` but ONLY with a fresh `ModelContext`, never `container.mainContext` — passing `mainContext` to `ModelActor` unbinds the UI state. ([ModelActor pitfalls](https://killlilwinters.medium.com/taking-swiftdata-further-modelactor-swift-concurrency-and-avoiding-mainactor-pitfalls-3692f61f2fa1)).

**Detection:**
- EXC_BAD_ACCESS crash in `NSPersistentStoreCoordinator` internal methods
- Crash only appears when concurrent operations overlap (e.g., recording + viewing history simultaneously)

**Phase to address:** History storage phase — any background save operation (auto-saving transcription result) is a crossing site.

---

### Pitfall 4: Companion Window Opening Steals Focus, Breaks Active Dictation

**What goes wrong:**
When the companion window is opened (e.g., from the menu bar while recording), `NSApp.activate()` brings Wave to the foreground. The previously focused text field (where the user intends to paste the transcription) loses focus. After transcription completes, `TextInserter.insertText()` fires `Cmd+V` — which now pastes into the companion window's search field or history list, not the user's intended target.

**Why it happens:**
`makeKeyAndOrderFront` + `NSApp.activate()` changes `NSWorkspace.shared.frontmostApplication` to Wave. The `TextInserter` does not snapshot the target app at recording start — it fires `Cmd+V` into whatever is frontmost at insertion time.

**Consequences:**
- Transcription pasted to wrong app
- User cannot replicate; appears as intermittent paste failure
- Companion window may receive and act on the paste (inserting into a search/filter field)

**Prevention:**
Snapshot the target app's `pid` at recording start and restore focus before insertion:

```swift
// In startRecording():
let targetApp = NSWorkspace.shared.frontmostApplication

// In TextInserter.insertText(), before Cmd+V:
targetApp?.activate(options: .activateIgnoringOtherApps)
Thread.sleep(forTimeInterval: 0.05) // let activation settle
simulatePaste()
```

Additionally, the companion window should NOT call `NSApp.activate()` if a recording is in progress. Gate companion window presentation behind `appState.phase == .idle`.

**Detection:**
- Start recording in Xcode → open companion window before releasing hotkey → transcription appears in companion search bar

**Phase to address:** Companion App foundation phase — the window-opening code path must check `appState.phase`.

---

### Pitfall 5: History Grows Unbounded, Store Becomes Slow Over Months

**What goes wrong:**
Every dictation session saves a `TranscriptionRecord`. A moderate user dictating 20 times per day accumulates 7,000+ records per year. SwiftData does not prune old records automatically. After 6-12 months, `@Query` fetches with no limit take 200-500ms, causing the history view to stutter on open. Full-text search becomes noticeably slow.

**Why it happens:**
SwiftData fetches load models into memory. A `@Query` with no `FetchDescriptor.fetchLimit` and no predicate loads every record into memory at query time. The issue is compounded by `@Query` re-executing the full fetch whenever any property of any record changes (e.g., autosave updating a `lastModified` timestamp on every transcription save triggers a full reload).

**Consequences:**
- App feels increasingly sluggish over time
- Users with long history cannot open the app without a beachball

**Prevention:**

1. Always use `fetchLimit` for the main history list. Display the latest 200 records; load more on scroll:

```swift
var descriptor = FetchDescriptor<TranscriptionRecord>(
    sortBy: [SortDescriptor(\.date, order: .reverse)]
)
descriptor.fetchLimit = 200
```

2. Implement a retention policy at save time: after saving a new record, delete records older than 90 days (or user-configured limit):

```swift
func trimHistory(context: ModelContext, keepDays: Int = 90) {
    let cutoff = Calendar.current.date(byAdding: .day, value: -keepDays, to: Date())!
    let old = FetchDescriptor<TranscriptionRecord>(
        predicate: #Predicate { $0.date < cutoff }
    )
    let toDelete = (try? context.fetch(old)) ?? []
    toDelete.forEach { context.delete($0) }
}
```

3. Store only `text`, `date`, `wordCount`, and `appBundleID` per record. Do NOT store raw audio paths or base64 audio in SwiftData — that causes exponential store growth.

**Detection:**
- Seed 10,000 records in simulator; open history tab and measure time-to-interactive
- Profile shows `NSPersistentStoreCoordinator` taking > 100ms in the main thread on app open

**Phase to address:** History storage phase — set `fetchLimit` and retention policy from the first day of shipping history, not retroactively.

---

## Moderate Pitfalls

---

### Pitfall 6: Whisper `prompt` Field Silently Truncated at 224 Tokens

**What goes wrong:**
The custom dictionary feature feeds user-defined terms into Whisper's `prompt` parameter to improve transcription of proper nouns and jargon. If the dictionary grows beyond ~892 characters, Whisper silently drops everything beyond token 224. The user adds 50 custom terms, but only the first 25 actually influence transcription. There is no error — the API call succeeds.

**Why it happens:**
Whisper's context window is 448 tokens, split evenly between prompt (224 tokens max) and output. Characters after token 224 are silently ignored at the model level, not at the API level. The API itself has no validation for this. Confirmed in [OpenAI Whisper GitHub Discussion #1824](https://github.com/openai/whisper/discussions/1824) and [OpenAI Cookbook: Whisper Prompting Guide](https://cookbook.openai.com/examples/whisper_prompting_guide).

**Prevention:**

1. Cap the prompt string at 800 characters before sending. Whisper's tokenizer averages ~4 characters/token, so 800 chars ≈ 200 tokens (safe margin):

```swift
// In WhisperService.transcribe():
let cappedPrompt = dictionaryPrompt.count > 800
    ? String(dictionaryPrompt.prefix(800))
    : dictionaryPrompt

// Use cappedPrompt, not dictionaryPrompt
```

2. In the Dictionary UI, show a character counter and warn when the user's terms would exceed the effective limit.

3. Prioritize recently-used terms if the list exceeds the limit (sort by `lastUsedDate` descending, truncate to fit).

**Detection:**
- Add 60 custom terms → verify the last 30 do not improve accuracy (blind test with those terms)

**Phase to address:** Dictionary feature phase.

---

### Pitfall 7: Snippet Trigger Fires During Dictation — Inserts Expansion Instead of Literal Text

**What goes wrong:**
The snippet system monitors keyboard events (via `NSEvent.addGlobalMonitorForEvents`) to detect typed trigger phrases. During active recording, the hotkey manager is also monitoring events. If the user's dictation trigger phrase (e.g., holding Fn) happens to be typed character-by-character by another app or input method while the snippet monitor is running, the snippet fires mid-dictation and inserts expanded text into the wrong target.

A more common scenario: The user dictates a phrase that matches a snippet trigger word (e.g., "my email"). After transcription, `TextInserter` pastes the literal phrase. But if the snippet monitor is watching `NSPasteboard` changes, it may intercept the paste and attempt to expand "my email" into the email address — inserting expanded text instead of the transcription result.

**Why it happens:**
Global `NSEvent` monitors and CGEvent taps do not have per-app scoping. Both the hotkey system and the snippet system compete for the same event stream. If snippet expansion triggers on clipboard-paste events or on the `Cmd+V` CGEvent fired by `TextInserter`, the snippet logic sees the pasted text as "typed" and attempts to expand it.

**Prevention:**

1. Snippet expansion should ONLY trigger on genuine keyboard input events (`NSEvent.EventTypeMask.keyDown`), never on synthetic CGEvents or clipboard-paste events. Add a check: if the event's `CGEventSource` is `combinedSessionState` (not `hidSystemState`), it is a synthetic event — skip snippet detection.

2. Disable snippet monitoring during the window from `startRecording()` to `insertText()` completion:

```swift
// In startRecording():
snippetMonitor.pause()

// After TextInserter.insertText() returns:
DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
    self.snippetMonitor.resume()
}
```

3. Do not use clipboard-change events as a snippet trigger signal. Snippet expansion should be strictly word-boundary triggered on keyDown events only.

**Detection:**
- Add snippet "my email" → dictate the phrase "my email" → verify transcription appears literally, not expanded

**Phase to address:** Snippets feature phase.

---

### Pitfall 8: `NavigationSplitView` Toolbar Insets Break Layout When Hosted in `NSWindow`

**What goes wrong:**
`NavigationSplitView` inside a SwiftUI `WindowGroup` adds an invisible top spacing in the detail column equal to the toolbar height. When `.windowToolbarStyle(.unified)` or `.windowStyle(.titleBar)` is applied, this doubles the vertical inset. The sidebar content also gets clipped at the bottom on macOS 14 Ventura if the window height is constrained.

**Why it happens:**
`NavigationSplitView` was designed for `WindowGroup` windows with `NSToolbar` integration. It assumes a `fullSizeContentView` window style mask. Without it, safe area calculations are wrong. The `inspector()` modifier compounds this by adding a second set of insets.

**Prevention:**

1. Use `.windowStyle(.titleBar)` with `.windowToolbarStyle(.unified(showsTitle: true))` on the companion `WindowGroup` — this is the combination that gives correct behavior.
2. Add `.ignoresSafeArea(.all)` to the `NavigationSplitView` root, then add back safe area insets manually per column.
3. Do not use `inspector()` modifier in the initial implementation — it adds layout complexity with no benefit for Wave's use case.
4. Set `.fullSizeContentView` in the window's `styleMask` if using a manual `NSWindow` approach.

**Detection:**
- History tab shows white gap at top equal to toolbar height
- Sidebar list items are clipped at bottom by 22px

**Phase to address:** Companion App UI phase.

---

### Pitfall 9: `@Query` Re-Fetches Entire History on Every Autosave

**What goes wrong:**
SwiftData's `autosaveEnabled` defaults to `true` on `ModelContext`. Each time a transcription is saved (every dictation session), the autosave triggers change tracking across all observed contexts. Any view using `@Query` for `TranscriptionRecord` gets notified and re-executes its fetch — even if the change is a write, not a modification of the queried records. On a busy history view, this causes a visible UI refresh every time the user dictates.

**Why it happens:**
SwiftData's change notification system does not distinguish between "a new record was added" and "an existing record in your query was modified." All changes to a model type broadcast to all `@Query` observers of that type. Confirmed as an unresolved issue with SwiftData's pending-changes behavior pre-iOS 17.4 / macOS 14.4, but the over-notification behavior persists post-patch. ([SwiftData Fetching Pending Changes](https://useyourloaf.com/blog/swiftdata-fetching-pending-changes/)).

**Prevention:**

1. Save new transcription records from a background `ModelActor` context, not from `container.mainContext`. Background context saves do not directly trigger `@Query` observers on the main context until the next runloop tick, giving the UI a chance to batch.

2. Use `FetchDescriptor` with `includePendingChanges: false` for the history list. This prevents pending (unsaved) records from appearing prematurely:

```swift
var descriptor = FetchDescriptor<TranscriptionRecord>(
    sortBy: [SortDescriptor(\.date, order: .reverse)]
)
descriptor.fetchLimit = 200
descriptor.includePendingChanges = false
```

3. For the history list view, consider adding `.animation(.none)` to the list to suppress the flash-reload animation on background updates.

**Detection:**
- Keep history view open, dictate 5 times in rapid succession → observe whether the list visibly refreshes/flickers on each dictation

**Phase to address:** History storage phase — set `includePendingChanges: false` from the start.

---

## Minor Pitfalls

---

### Pitfall 10: Dock Icon Appears Then Disappears on Cold Launch (LSUIElement Timing Bug)

**What goes wrong:**
If `LSUIElement = true` in Info.plist but the app calls `setActivationPolicy(.regular)` at launch to show the dock icon when the companion has been opened before, users see the dock icon briefly appear (during AppKit's initial setup), disappear (when `LSUIElement = true` is applied by LaunchServices), and then reappear (when `setActivationPolicy(.regular)` fires in `applicationDidFinishLaunching`). This flash is more visible on fast Macs.

**Prevention:**
Remove `LSUIElement = true` from Info.plist entirely. Control dock presence exclusively via `setActivationPolicy()` at launch. Set it synchronously in `applicationWillFinishLaunching` (before the first window appears), not in `applicationDidFinishLaunching` — the latter is too late and causes the flash. Reference: [Fine-Tuning macOS App Activation Behavior](https://artlasovsky.com/fine-tuning-macos-app-activation-behavior).

**Phase to address:** Companion App foundation phase.

---

### Pitfall 11: Companion Window `openWindow` Requires Scene-Graph Context — Fails from AppDelegate

**What goes wrong:**
SwiftUI's `openWindow` environment action cannot be called from `AppDelegate`. If the menu bar "Open Wave" button calls `openWindow` directly, it crashes with `Fatal error: No window with id 'companion' was found.` The action requires an active SwiftUI view in the responder chain.

**Prevention:**
Use `NotificationCenter` as the bridge. Post a notification from `AppDelegate`, listen in a hidden SwiftUI view that has the `openWindow` environment, and trigger the open from there:

```swift
// AppDelegate:
NotificationCenter.default.post(name: .openCompanion, object: nil)

// Hidden SwiftUI view (always in scene graph):
struct CompanionOpener: View {
    @Environment(\.openWindow) var openWindow
    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .onReceive(NotificationCenter.default.publisher(for: .openCompanion)) { _ in
                openWindow(id: "companion")
            }
    }
}
```

**Phase to address:** Companion App foundation phase.

---

### Pitfall 12: Custom Dictionary Terms with Special Characters Break Whisper Prompt

**What goes wrong:**
Users add dictionary terms containing newlines, quotes, or non-ASCII characters (e.g., product names with trademark symbols, names with accents). When these terms are joined into the Whisper `prompt` string, the resulting multipart form body is malformed. Whisper returns a 400 error or ignores the prompt silently.

**Prevention:**
Sanitize dictionary terms before building the prompt string:

```swift
func buildWhisperPrompt(from terms: [String]) -> String {
    let sanitized = terms.map { term in
        term
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    .filter { !$0.isEmpty }
    let joined = sanitized.joined(separator: ", ")
    return String(joined.prefix(800)) // enforce 800-char cap
}
```

Validate terms at entry time in the Dictionary UI: reject empty terms and strip leading/trailing whitespace.

**Phase to address:** Dictionary feature phase.

---

### Pitfall 13: Snippet Expansion Conflicts with App's Own `Cmd+V` Paste

**What goes wrong:**
The snippet system, monitoring for trigger phrases typed by the user, may observe the `Cmd+V` CGEvent fired by `TextInserter` as the beginning of a new typed sequence. If the first word of the pasted transcription matches a snippet trigger, the snippet fires and appends the expansion after the pasted text.

**Prevention:**
Set a flag in `TextInserter` during the simulated paste window:

```swift
class TextInserter {
    var isSynthesizingPaste = false

    func insertText(_ text: String) {
        isSynthesizingPaste = true
        // ... paste logic ...
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.isSynthesizingPaste = false
        }
    }
}

// In SnippetMonitor:
guard !textInserter.isSynthesizingPaste else { return }
```

**Phase to address:** Snippets feature phase.

---

### Pitfall 14: `NSWindow` for Companion Loses First Responder When Overlay Appears

**What goes wrong:**
When the floating overlay (`recordingWindow`) calls `orderFront(nil)`, it briefly steals first responder from the companion window's text fields (e.g., the dictionary entry field, the snippet trigger field). Characters the user is typing into those fields are dropped for 1-2 keystrokes. The overlay is correctly set to `ignoresMouseEvents = true` but does not suppress keyboard first-responder stealing.

**Prevention:**
When `orderFront(nil)` is called on the overlay, explicitly restore first responder to the companion window if it was the previous key window:

```swift
private func showRecordingOverlay() {
    let previousKeyWindow = NSApp.keyWindow
    recordingWindow?.orderFront(nil)
    // Overlay should never become key — restore if needed
    if NSApp.keyWindow === recordingWindow {
        previousKeyWindow?.makeKey()
    }
}
```

Additionally, set `recordingWindow?.canBecomeKey = false` (via subclass override) to prevent it from ever becoming key window.

**Phase to address:** Companion App integration phase.

---

## Phase-Specific Warnings

| Phase Topic | Likely Pitfall | Mitigation |
|-------------|----------------|------------|
| Companion window foundation | `setActivationPolicy` hides existing windows (Pitfall 1) | Commit to permanent dock presence when companion is first opened; never toggle policy mid-session |
| Companion window foundation | `@Query` silent failure in NSHostingView (Pitfall 2) | Use SwiftUI `WindowGroup` scene for companion, not manual `NSWindow` |
| Companion window foundation | Companion window open steals focus from dictation target (Pitfall 4) | Snapshot target app pid at recording start; gate window open on `appState.phase == .idle` |
| History storage | Unbounded store growth (Pitfall 5) | Ship `fetchLimit` and 90-day retention on day one |
| History storage | `@Query` re-fetch flash on every dictation save (Pitfall 9) | Save from background context; use `includePendingChanges: false` |
| History storage | PersistentModel passed to background Task crashes (Pitfall 3) | Map to `Sendable` struct before any actor boundary crossing |
| Dictionary feature | Whisper prompt silently truncated (Pitfall 6) | Cap prompt at 800 chars; show counter in UI |
| Dictionary feature | Special characters break prompt (Pitfall 12) | Sanitize at entry time; strip newlines and trim whitespace |
| Snippets feature | Snippet fires during/after dictation paste (Pitfall 7) | Pause snippet monitor during recording→insertion window |
| Snippets feature | Snippet fires on TextInserter's Cmd+V (Pitfall 13) | Set `isSynthesizingPaste` flag during paste window |
| Companion UI | NavigationSplitView toolbar insets corrupt layout (Pitfall 8) | Use `WindowGroup` + `.windowToolbarStyle(.unified)` from the start |
| Companion integration | Overlay steals first responder from companion (Pitfall 14) | Prevent overlay window from ever becoming key window |

---

## "Looks Done But Isn't" Checklist

- [ ] **Activation policy:** Does the dock icon appear/disappear correctly? No flash on cold launch. Test: quit, relaunch, verify no icon flicker.
- [ ] **@Query environment:** With companion in `WindowGroup`, open History tab — does it show saved records? Test: dictate once, open companion, verify entry appears.
- [ ] **Background save safety:** Does dictating while History tab is open cause any crash? Run 10 dictation cycles with companion open, watch for EXC_BAD_ACCESS.
- [ ] **Focus restoration:** Dictate into TextEdit → open companion → dictate again → verify transcription goes to TextEdit, not companion.
- [ ] **History growth:** Seed 5,000 records, open History tab, measure time-to-interactive. Must be < 300ms.
- [ ] **Whisper prompt cap:** Add 100 dictionary terms, confirm only first ~25 terms (first 800 chars) are sent in the prompt (log the prompt string).
- [ ] **Snippet suppression:** During recording, type a snippet trigger on a physical keyboard; snippet must NOT fire until after recording ends.
- [ ] **Overlay focus:** Open companion, click dictionary entry field, start recording. First responder must stay on companion's text field.

---

## Sources

- [NSApp.setActivationPolicy(.accessory) hides all windows](https://github.com/onmyway133/notes/issues/569)
- [Showing Settings from macOS Menu Bar Items — steipete.me (2025)](https://steipete.me/posts/2025/showing-settings-from-macos-menu-bar-items)
- [Fine-Tuning macOS App Activation Behavior — artlasovsky.com](https://artlasovsky.com/fine-tuning-macos-app-activation-behavior)
- [ModelContext for SwiftData is not available — Apple Developer Forums](https://developer.apple.com/forums/thread/740864)
- [Taking SwiftData Further: @ModelActor, Swift Concurrency, and Avoiding @MainActor Pitfalls — Medium](https://killlilwinters.medium.com/taking-swiftdata-further-modelactor-swift-concurrency-and-avoiding-mainactor-pitfalls-3692f61f2fa1)
- [Concurrent Programming in SwiftData — fatbobman.com](https://fatbobman.com/en/posts/concurret-programming-in-swiftdata/)
- [Ongoing Issues with ModelActor in SwiftData — Apple Developer Forums](https://developer.apple.com/forums/thread/770416)
- [SwiftData Fetching Pending Changes — Use Your Loaf](https://useyourloaf.com/blog/swiftdata-fetching-pending-changes/)
- [How to optimize SwiftData apps — Hacking with Swift](https://www.hackingwithswift.com/quick-start/swiftdata/how-to-optimize-the-performance-of-your-swiftdata-apps)
- [Whisper Prompt Length — openai/whisper GitHub Discussion #1824](https://github.com/openai/whisper/discussions/1824)
- [Whisper Prompting Guide — OpenAI Cookbook](https://cookbook.openai.com/examples/whisper_prompting_guide)
- [SwiftUI NavigationSplitView on macOS — Apple Developer Forums](https://developer.apple.com/forums/thread/746611)
- [macOS full height sidebar window — Medium/bancarel.paul](https://medium.com/@bancarel.paul/macos-full-height-sidebar-window-62a214309a80)
- [Window Management with SwiftUI 4 — fline.dev](https://www.fline.dev/window-management-on-macos-with-swiftui-4/)
- [Nailing the Activation Behavior of a Spotlight/Raycast-Like Command Palette — multi.app](https://multi.app/blog/nailing-the-activation-behavior-of-a-spotlight-raycast-like-command-palette)
- [NSApp.setActivationPolicy(.regular) — Apple Developer Forums](https://developer.apple.com/forums/thread/650270)

---
*Pitfalls research for: v1.2 companion app — history, dictionary, snippets added to existing menu-bar dictation app*
*Researched: 2026-03-30*
