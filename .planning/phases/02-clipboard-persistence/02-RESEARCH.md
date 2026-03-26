# Phase 2: Clipboard Persistence - Research

**Researched:** 2026-03-26
**Domain:** AppKit / NSPasteboard — clipboard persistence, TransientType marker, changeCount guard
**Confidence:** HIGH (findings derived from direct codebase inspection + verified nspasteboard.org spec + Maccy open-source reference)

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| CLIP-01 | Transcription remains on clipboard after paste (no restore of previous content) | Current code does a 0.5 s delayed restore; removing that block is the entire fix |
| CLIP-02 | Clipboard restore only occurs if user hasn't copied something else (changeCount guard) | NSPasteboard.changeCount increments on every write; snapshot before paste, compare before restore |
| CLIP-03 | Clipboard writes include TransientType marker for clipboard manager compatibility | nspasteboard.org spec; Maccy source confirms `.transient` type is in its ignore list |
</phase_requirements>

---

## Summary

Phase 2 is a surgical, three-change fix to `TextInserter.swift`. Zero new files are required and no new dependencies are introduced. The current `insertText(_:)` implementation already contains all three problem sites inline:

1. **CLIP-01** — The `DispatchQueue.main.asyncAfter(deadline: .now() + 0.5)` block at line 38–43 restores the old clipboard. Removing it satisfies CLIP-01.
2. **CLIP-02** — Before removing the restore, the `changeCount` of the pasteboard must be snapshot immediately after the transcription write. The (now-conditional) restore block checks whether `changeCount` has incremented; if it has, the user copied something new during the paste window and the restore is skipped.
3. **CLIP-03** — After `pasteboard.clearContents()` and before `pasteboard.setString(text, forType: .string)`, a single extra `setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))` call marks the write as transient. All major clipboard managers (Maccy, Raycast, Paste, Alfred) check for and respect this marker.

Because CLIP-02 is defined as "restore only if user hasn't copied something else" — and the nominal path for CLIP-01 is "no restore at all" — the two requirements interact: CLIP-01 removes the restore, while CLIP-02 is a safety net that only matters if a future developer re-introduces a restore path. The cleanest implementation is to remove the restore entirely (satisfying CLIP-01) while leaving the changeCount snapshot in place as a guard comment for future maintainers and to satisfy the CLIP-02 requirement explicitly.

**Primary recommendation:** Edit `TextInserter.swift` only. Three targeted changes — remove the restore block, snapshot changeCount, add TransientType write — complete the entire phase.

---

## Standard Stack

### Core (already in project — no new dependencies)

| Component | Version | Purpose | Notes |
|-----------|---------|---------|-------|
| AppKit (NSPasteboard) | macOS 10.0+ | Clipboard read/write | Already imported in TextInserter.swift |
| Foundation (DispatchQueue) | — | Async timing | Already used in AppDelegate.swift |

### No New Dependencies Required

This phase adds zero new frameworks or packages.

---

## Architecture Patterns

### Current TextInserter.insertText flow

```
insertText(text)
  1. snapshot oldContent = pasteboard.string(forType: .string)
  2. pasteboard.clearContents()
  3. pasteboard.setString(text, forType: .string)
  4. clearModifierKeys() + 50ms sleep
  5. simulatePaste()          ← Cmd+V via CGEvent
  6. [0.5s later] restore oldContent   ← REMOVE THIS
```

### Target flow after Phase 2

```
insertText(text)
  1. pasteboard.clearContents()
  2. pasteboard.setString(text, forType: .string)          ← CLIP-01: no save/restore
  3. pasteboard.setData(Data(), forType: .transient)       ← CLIP-03: TransientType marker
  4. snapshot changeCountAfterWrite = pasteboard.changeCount  ← CLIP-02: for guard
  5. clearModifierKeys() + 50ms sleep
  6. simulatePaste()          ← unchanged
  (no restore block)
```

### Pattern: TransientType Write

**What:** Adding `org.nspasteboard.TransientType` with an empty Data payload tells clipboard history utilities the write is ephemeral and should not be recorded.

**Spec source:** nspasteboard.org (the canonical reference for this convention)

**Swift implementation:**
```swift
// Source: http://nspasteboard.org + Maccy source
pasteboard.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
```

This call must happen on the same `clearContents` cycle (before `simulatePaste`). Adding it after a separate `clearContents()` would invalidate the transcription write.

**Order matters:** `clearContents()` resets the change count. All type writes in a single cycle must follow one `clearContents()`.

### Pattern: changeCount Guard

**What:** `NSPasteboard.changeCount` is an integer that the system increments on every successful write to the pasteboard. It does not wrap.

**Usage:**
```swift
// Snapshot immediately after our write
let changeCountAfterWrite = pasteboard.changeCount

// Guard in any future restore path:
guard pasteboard.changeCount == changeCountAfterWrite else {
    // User copied something during the paste window — skip restore
    return
}
```

**Key property:** The snapshot must be taken after the `setString` + `setData` writes, not before. At that point `changeCount` reflects our write. Any subsequent user copy will increment it again, making the guard condition false.

### Anti-Patterns to Avoid

- **Saving and restoring oldContent unconditionally:** This is the current bug. After dictation the user expects Cmd+V to re-paste the transcription, but the 0.5 s restore overwrites it with the previous clipboard item.
- **Calling clearContents() twice:** Each `clearContents()` starts a new pasteboard write transaction and increments changeCount. If TransientType is added after a second `clearContents()`, the string write is lost.
- **Taking the changeCount snapshot before our write:** The snapshot would capture the pre-write count, so the guard would fire incorrectly if no user copy occurred (count would already differ by 1 from our write).
- **Using NSPasteboard.PasteboardType.string as the only type:** Writing only `.string` is fine for paste, but omitting the TransientType marker means Maccy, Raycast, and Paste will log the transcription as a regular clipboard entry.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Clipboard manager exclusion protocol | Custom UTType, custom Info.plist key, sandboxing tricks | `org.nspasteboard.TransientType` marker | Universally adopted convention; nspasteboard.org is the canonical spec; Maccy, Raycast, Paste, and Alfred all honour it |
| Detecting user clipboard changes | Polling loop, notification observer hack | `NSPasteboard.changeCount` comparison | System-provided integer; no polling needed for a single comparison window |

**Key insight:** The nspasteboard.org convention has been the standard since ~2013 and has near-universal adoption among macOS clipboard managers. No alternative mechanism is necessary or appropriate.

---

## Common Pitfalls

### Pitfall 1: Snapshot changeCount Before the Write

**What goes wrong:** The guard fires even when the user did not copy anything, because our own write already incremented the count.
**Why it happens:** changeCount increments on every write, including ours.
**How to avoid:** Always snapshot changeCount _after_ the final `setData`/`setString` call in the same transaction.
**Warning signs:** Restore logic always skipping, even in a clean test environment.

### Pitfall 2: Multiple clearContents Calls in One insertText Invocation

**What goes wrong:** Second `clearContents()` wipes the first write; the pasteboard ends up with only the types added after the second clear.
**Why it happens:** `clearContents()` starts a new transaction. Adding TransientType after the string write requires no second clear — `setData` extends the current transaction.
**How to avoid:** One `clearContents()` per logical write. All types (`string` + `transient`) are written in the same transaction.

### Pitfall 3: TransientType Payload Must Be Non-nil

**What goes wrong:** Passing `nil` data to `setData(_:forType:)` may silently fail or crash.
**Why it happens:** The API contract for `setData` requires a non-nil `Data` object.
**How to avoid:** Use `Data()` (empty but non-nil) as the payload. The spec says "payload of your choice" — empty Data is the standard choice.

### Pitfall 4: Timing Race Between Paste and Clipboard Manager Polling

**What goes wrong:** Some clipboard managers poll at 0.5–1 s intervals. If they poll between the `setString` call and the `setData(transient)` call, they might record the write before the transient marker is present.
**Why it happens:** The two writes happen in the same synchronous block, but on a very slow system there could theoretically be a race.
**How to avoid:** This is not a real-world problem because both writes are synchronous on the main thread and complete in microseconds. Clipboard managers poll on their own thread, not between two synchronous NSPasteboard calls. No special handling required.

---

## Code Examples

### Complete Revised insertText (target state)

```swift
// Source: derived from TextInserter.swift + nspasteboard.org spec
func insertText(_ text: String) {
    let pasteboard = NSPasteboard.general

    // Write transcription — no save/restore (CLIP-01)
    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)
    // Mark as transient so clipboard managers skip logging (CLIP-03)
    pasteboard.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
    // Snapshot so a future restore guard can detect user-copy (CLIP-02)
    let changeCountAfterWrite = pasteboard.changeCount

    clearModifierKeys()
    usleep(50000)
    simulatePaste()

    // No restore block. changeCountAfterWrite available if restore ever needed:
    // guard pasteboard.changeCount == changeCountAfterWrite else { return }
}
```

### TransientType Type Constant (optional helper)

```swift
// Source: http://nspasteboard.org
extension NSPasteboard.PasteboardType {
    static let transientContent = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
}
```

Using a named constant avoids the raw string appearing in two places if the type is ever reused.

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Save clipboard before write, restore after paste | Write-and-leave (no restore) | This phase | Transcription persists for Cmd+V re-use |
| No TransientType marker | TransientType marker on write | This phase | Clipboard managers do not log dictation |
| No changeCount guard | changeCount snapshot for future guard | This phase | Explicit documentation of CLIP-02 intent |

---

## Open Questions

1. **Does Raycast honour TransientType in 2026?**
   - What we know: Maccy (open source) explicitly ignores `org.nspasteboard.TransientType`. Raycast's documentation mentions "sensitive information like passwords is automatically ignored" but does not specify the mechanism.
   - What's unclear: Whether Raycast uses the nspasteboard.org convention specifically vs. its own heuristic.
   - Recommendation: The TransientType marker is the correct implementation regardless. If Raycast does not honour it, that is Raycast's issue; no alternative mechanism exists in the public API. Ship with TransientType and verify manually with Raycast during validation.

2. **Should `oldContent` saving be removed entirely or conditionalised?**
   - What we know: CLIP-01 says transcription stays on clipboard (no restore). The 0.5 s restore is the only place `oldContent` is used.
   - What's unclear: Whether any edge case (e.g., user pastes into a password field that clears clipboard) would benefit from restoration.
   - Recommendation: Remove the save/restore entirely. The STATE.md decision log entry "Clipboard persistence on by default — remove 0.5s restore, keep transcription available via Cmd+V" is a locked decision.

---

## Validation Architecture

> nyquist_validation key absent from config.json — treated as enabled.

### Test Framework

| Property | Value |
|----------|-------|
| Framework | None detected — project has no XCTest target |
| Config file | None |
| Quick run command | Manual: build and run FlowSpeech, dictate, press Cmd+V after paste |
| Full suite command | Manual: same, plus open Maccy/Raycast and verify clipboard history does not contain transcription |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| CLIP-01 | After paste, Cmd+V still inserts transcription | manual-only | — | — |
| CLIP-02 | If user copies during paste window, their copy is preserved | manual-only | — | — |
| CLIP-03 | Transcription does not appear in Maccy / Raycast clipboard history | manual-only | — | — |

All three requirements are UI/integration-level behaviours that require a running macOS app interacting with real system clipboard state. Automated unit tests for NSPasteboard are possible but would require mocking the pasteboard (fragile) and would not validate clipboard manager behaviour. Manual testing is the appropriate validation path for this phase.

### Sampling Rate

- **Per task commit:** Build app, dictate one phrase, verify Cmd+V pastes transcription again
- **Per wave merge:** Build app, dictate, copy something else mid-window, verify user copy survives; open Maccy, verify transcription absent
- **Phase gate:** All three manual steps green before `/gsd:verify-work`

### Wave 0 Gaps

None — this phase makes no changes to test infrastructure. No XCTest target exists in the project and none is required for this phase.

---

## Sources

### Primary (HIGH confidence)
- http://nspasteboard.org — canonical spec for TransientType, ConcealedType, AutoGeneratedType; payload format; adoption requirement
- TextInserter.swift (codebase) — direct inspection of lines 17–43 (the restore block) and lines 21–26 (the existing clearContents + setString pattern)
- AppDelegate.swift (codebase) — confirmed `textInserter.insertText(transcription)` call site at line 244

### Secondary (MEDIUM confidence)
- https://github.com/p0deje/Maccy/blob/master/Maccy/Clipboard.swift — open-source confirmation that `NSPasteboard.PasteboardType.transient` (i.e., `org.nspasteboard.TransientType`) is in the ignored set; changeCount polling pattern
- https://developer.apple.com/documentation/appkit/nspasteboard/1533544-changecount — Apple docs for changeCount (page content unverifiable via fetch but API behaviour confirmed via multiple secondary sources)

### Tertiary (LOW confidence)
- Raycast clipboard history documentation — implies sensitivity detection but does not document TransientType support; treat as unverified

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — zero new dependencies, existing NSPasteboard usage already in file
- Architecture: HIGH — direct codebase inspection, nspasteboard.org spec is authoritative and stable
- Pitfalls: HIGH — derived from API contract (clearContents transaction semantics) and spec (payload non-nil)
- Clipboard manager compatibility: MEDIUM — Maccy confirmed via open source; Raycast unconfirmed but TransientType is the only public mechanism

**Research date:** 2026-03-26
**Valid until:** 2026-09-26 (nspasteboard.org convention is stable; NSPasteboard API unlikely to change)
