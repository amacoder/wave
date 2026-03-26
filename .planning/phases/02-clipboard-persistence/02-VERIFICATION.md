---
phase: 02-clipboard-persistence
verified: 2026-03-26T00:00:00Z
status: human_needed
score: 3/3 must-haves verified (automated); 3 truths need human confirmation
human_verification:
  - test: "After dictating, press Cmd+V in a different field"
    expected: "The transcribed text appears again — not whatever was on clipboard before dictation"
    why_human: "Requires running app, triggering real dictation, and observing paste behavior at runtime"
  - test: "After dictation paste completes, copy different text then press Cmd+V in a new field"
    expected: "The manually-copied text appears — not the transcription"
    why_human: "Requires runtime interaction to verify clipboard state ordering and changeCount behavior"
  - test: "With Maccy or Raycast clipboard history open, dictate a unique phrase then inspect clipboard history"
    expected: "The dictated phrase does NOT appear in clipboard manager history"
    why_human: "Requires a clipboard manager installed and running; cannot verify TransientType protocol compliance programmatically"
---

# Phase 2: Clipboard Persistence Verification Report

**Phase Goal:** Transcription always remains on the clipboard after paste, and clipboard managers do not log transcription content
**Verified:** 2026-03-26
**Status:** human_needed — all automated checks pass; behavioral truths require runtime confirmation
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | After dictating and pasting, Cmd+V re-pastes the transcription (clipboard not restored) | ? NEEDS HUMAN | Code confirms restore block removed: no `asyncAfter`, no `oldContent`, no `DispatchQueue` in `insertText`. Behavioral confirmation requires runtime test. |
| 2 | If the user copies something else during the paste window, their copy is preserved | ? NEEDS HUMAN | `changeCountAfterWrite` snapshot present with guard comment (CLIP-02). No restore path exists to overwrite user copy. Behavioral confirmation requires runtime test. |
| 3 | Clipboard managers (Maccy, Raycast, Paste) do not log transcription content | ? NEEDS HUMAN | `org.nspasteboard.TransientType` marker written via `setData(Data(), forType: .transientContent)` in same transaction. Protocol compliance verified by code; actual exclusion from a running clipboard manager requires human test. |

**Score:** 3/3 truths implemented; all three require human runtime verification per the phase plan's blocking checkpoint (Task 2).

---

## Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `FlowSpeech/Services/TextInserter.swift` | Revised insertText with no restore, TransientType marker, changeCount guard | VERIFIED | File exists (226 lines, substantive), implements all three changes, wired via `AppDelegate.swift:244` |

### Level 1 — Exists

`FlowSpeech/Services/TextInserter.swift` — present, 226 lines.

### Level 2 — Substantive (Acceptance Criteria Check)

All six acceptance criteria from the PLAN pass:

| Criterion | Check | Result |
|-----------|-------|--------|
| Does NOT contain `let oldContent` in `insertText` | `grep "let oldContent"` — no match | PASS |
| Does NOT contain `asyncAfter` or `DispatchQueue` in `insertText` | `grep "asyncAfter\|DispatchQueue"` — no match | PASS |
| Contains `org.nspasteboard.TransientType` | Line 17: `NSPasteboard.PasteboardType("org.nspasteboard.TransientType")` | PASS |
| Contains `pasteboard.setData(Data(), forType:` with TransientType | Line 35: `pasteboard.setData(Data(), forType: .transientContent)` | PASS |
| Contains `pasteboard.changeCount` assigned to a variable after setString/setData | Line 38: `let changeCountAfterWrite = pasteboard.changeCount` | PASS |
| Exactly ONE `clearContents()` call in `insertText` | Single match at line 31 | PASS |

### Level 3 — Wired

Call site confirmed: `FlowSpeech/AppDelegate.swift:244` calls `textInserter.insertText(transcription)` — unchanged from Phase 1 as planned.

---

## Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `FlowSpeech/Services/TextInserter.swift` | `NSPasteboard.general` | `setData + setString` in single `clearContents` transaction | WIRED | `clearContents()` line 31, `setString` line 32, `setData(.transientContent)` line 35 — single transaction confirmed |
| `FlowSpeech/AppDelegate.swift` | `FlowSpeech/Services/TextInserter.swift` | `textInserter.insertText(transcription)` call site | WIRED | Confirmed at `AppDelegate.swift:244` |

---

## Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| CLIP-01 | 02-01-PLAN.md | Transcription remains on clipboard after paste (no restore of previous content) | SATISFIED | `oldContent` save removed, `DispatchQueue` restore block removed. Comment on line 30: `// Write transcription to clipboard — no save/restore (CLIP-01)` |
| CLIP-02 | 02-01-PLAN.md | Clipboard restore only occurs if user hasn't copied something else (changeCount guard) | SATISFIED | `changeCountAfterWrite` snapshot at line 38; guard pattern documented in comment lines 49-52; no restore path exists so guard is dormant (correct per spec) |
| CLIP-03 | 02-01-PLAN.md | Clipboard writes include TransientType marker for clipboard manager compatibility | SATISFIED | `NSPasteboard.PasteboardType.transientContent` extension at line 14-18; `setData(Data(), forType: .transientContent)` at line 35 with comment: `// Mark as transient so clipboard managers skip logging (CLIP-03)` |

No orphaned requirements: CLIP-01, CLIP-02, CLIP-03 are the only IDs mapped to Phase 2 in REQUIREMENTS.md, and all three appear in the PLAN's `requirements` field.

---

## Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| — | — | — | — | No anti-patterns detected |

Scan results:
- No `TODO`, `FIXME`, `XXX`, `HACK`, or `PLACEHOLDER` comments in `insertText` method
- No `return null`, `return {}`, `return []` in `insertText`
- No stub handlers
- The `_ = changeCountAfterWrite` suppression on line 52 is intentional and documented — not a stub

---

## Build Verification

`xcodebuild -scheme FlowSpeech -configuration Debug build` — **BUILD SUCCEEDED** (zero errors).

Commit `ee33d7d` verified in git history with correct changeset: `FlowSpeech/Services/TextInserter.swift | 45 ++++++++++++++++++++--------------`.

---

## Human Verification Required

All three observable truths have complete code implementations but their behavioral correctness can only be confirmed at runtime. The PLAN designates Task 2 as a `checkpoint:human-verify gate="blocking"` for exactly this reason.

### 1. Clipboard Persistence (CLIP-01)

**Test:** Build and run FlowSpeech. Hold the hotkey, dictate a short phrase, release. After transcription pastes into target field, open a different text field and press Cmd+V.
**Expected:** The transcribed text appears again (not whatever was on clipboard before dictation).
**Why human:** Requires a running app, real dictation, and observing paste behavior in two separate text fields.

### 2. User Copy Preserved (CLIP-02)

**Test:** Dictate a phrase via FlowSpeech. Immediately after paste completes, select different text and press Cmd+C. Then press Cmd+V in a new field.
**Expected:** The manually-copied text appears — not the transcription.
**Why human:** Requires runtime clipboard state sequencing; changeCount guard is dormant code that cannot be exercised programmatically.

### 3. Clipboard Manager Exclusion (CLIP-03)

**Test:** With Maccy or Raycast clipboard history open, dictate a unique phrase (e.g., "clipboard test alpha bravo"). Check clipboard history.
**Expected:** The dictated phrase does NOT appear in clipboard manager history.
**Why human:** Requires a clipboard manager installed and running; TransientType protocol compliance cannot be verified without an actual conforming clipboard manager process.
**Note:** If no clipboard manager is installed, this test can be skipped — the TransientType marker is implemented per spec.

---

## Summary

Phase 2's single modified file (`FlowSpeech/Services/TextInserter.swift`) implements all three requirements exactly as specified. The code is substantive, wired, and the build passes with zero errors. The committed change (ee33d7d) matches the declared changeset.

All three truths are blocked on human runtime confirmation — this is expected and was planned for. No automated gaps were found.

---

_Verified: 2026-03-26_
_Verifier: Claude (gsd-verifier)_
