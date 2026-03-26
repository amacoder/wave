---
phase: 3
slug: overlay-redesign
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-26
---

# Phase 3 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | None — macOS SwiftUI app with no XCTest suite |
| **Config file** | None |
| **Quick run command** | `xcodebuild -scheme FlowSpeech -configuration Debug build` |
| **Full suite command** | Manual: build and run, exercise all 4 recording states |
| **Estimated runtime** | ~30 seconds (build) + ~60 seconds (manual exercise) |

---

## Sampling Rate

- **After every task commit:** Run `xcodebuild -scheme FlowSpeech -configuration Debug build`
- **After every plan wave:** Full manual exercise of all 4 states
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds (build check)

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 03-XX-01 | XX | 1 | OVLAY-01 | manual | visual inspection — Capsule at bottom-center | N/A | ⬜ pending |
| 03-XX-02 | XX | 1 | OVLAY-02 | manual | exercise all 4 phases — observer identifies each | N/A | ⬜ pending |
| 03-XX-03 | XX | 1 | OVLAY-03 | manual | observe state transitions — no abrupt cuts | N/A | ⬜ pending |
| 03-XX-04 | XX | 1 | OVLAY-04 | code-review | `grep -c "ForEach" FlowSpeech/Views/RecordingOverlayView.swift` returns 0 | N/A | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

*No XCTest target exists. Not required for Phase 3 — all requirements are UI/visual behaviors verified manually or via code review. Build compilation is the only automatable check.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Capsule pill shape at bottom-center | OVLAY-01 | Visual rendering — no XCUITest target | Build and run, hold Fn, confirm overlay is pill shape at screen bottom-center |
| 4 distinct visual states | OVLAY-02 | Visual rendering — requires human observation | Exercise idle→recording→transcribing→done, confirm each visually distinct |
| Spring transitions, no abrupt cuts | OVLAY-03 | Animation fidelity — cannot unit test | Observe state changes during live session, confirm smooth springs |
| Canvas waveform replaces ForEach | OVLAY-04 | Partial code-review check | `grep "ForEach" RecordingOverlayView.swift` must return no match; visual confirm waveform renders |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
