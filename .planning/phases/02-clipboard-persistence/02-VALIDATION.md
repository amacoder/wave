---
phase: 2
slug: clipboard-persistence
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-26
---

# Phase 2 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | None — project has no XCTest target |
| **Config file** | None |
| **Quick run command** | Manual: build and run FlowSpeech, dictate, press Cmd+V after paste |
| **Full suite command** | Manual: same, plus open Maccy/Raycast and verify clipboard history does not contain transcription |
| **Estimated runtime** | ~60 seconds (manual) |

---

## Sampling Rate

- **After every task commit:** Build app, dictate one phrase, verify Cmd+V pastes transcription again
- **After every plan wave:** Build app, dictate, copy something else mid-window, verify user copy survives; open Maccy, verify transcription absent
- **Before `/gsd:verify-work`:** All three manual steps green
- **Max feedback latency:** ~60 seconds (manual build + test)

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 02-01-01 | 01 | 1 | CLIP-01, CLIP-02, CLIP-03 | manual | — | — | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements. No XCTest target exists and none is required — all three requirements are UI/integration-level behaviours requiring real system clipboard interaction.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| After paste, Cmd+V still inserts transcription | CLIP-01 | Requires running macOS app + real clipboard | 1. Build & run FlowSpeech 2. Dictate a phrase 3. Wait for paste 4. Press Cmd+V in a text field 5. Verify transcription appears |
| User copy during paste window is preserved | CLIP-02 | Requires timing-sensitive interaction with system clipboard | 1. Build & run 2. Dictate 3. Quickly Cmd+C some other text 4. Cmd+V → verify user-copied text appears |
| Clipboard managers don't log transcription | CLIP-03 | Requires Maccy/Raycast running and inspecting their history | 1. Open Maccy 2. Dictate via FlowSpeech 3. Check Maccy history → transcription should NOT appear |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 60s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
