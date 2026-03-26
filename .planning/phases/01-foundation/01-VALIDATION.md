---
phase: 1
slug: foundation
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-26
---

# Phase 1 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | None — no XCTest target configured |
| **Config file** | none — Wave 0 not applicable (no test infra in project) |
| **Quick run command** | `xcodebuild build -scheme FlowSpeech -destination 'platform=macOS'` |
| **Full suite command** | `xcodebuild build -scheme FlowSpeech -destination 'platform=macOS'` |
| **Estimated runtime** | ~15 seconds |

---

## Sampling Rate

- **After every task commit:** Run `xcodebuild build -scheme FlowSpeech -destination 'platform=macOS'`
- **After every plan wave:** Run full build + manual smoke test
- **Before `/gsd:verify-work`:** Full build must succeed + manual verification protocol below
- **Max feedback latency:** 15 seconds (build time)

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 1-01-01 | 01 | 1 | FNDTN-01 | build + grep | `xcodebuild build` + `grep -r "phase: RecordingPhase" FlowSpeech/` | N/A | ⬜ pending |
| 1-02-01 | 02 | 1 | FNDTN-02 | build + grep | `xcodebuild build` + `grep -r "Color(hex:" FlowSpeech/` returns 0 outside DesignSystem | N/A | ⬜ pending |
| 1-03-01 | 03 | 1 | FNDTN-03 | build + manual | `xcodebuild build` + revoke Accessibility, observe icon | N/A | ⬜ pending |
| 1-04-01 | 04 | 2 | FNDTN-04 | build + manual | `xcodebuild build` + Activity Monitor CPU check | N/A | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements. No test framework setup needed — Phase 1 is structural refactoring verified by successful compilation and manual smoke testing.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| All 4 phase transitions (idle→recording→transcribing→done→idle) | FNDTN-01 | Runtime state machine requires user interaction | Hold hotkey → record → release → verify transcription → verify return to idle |
| Menu bar icon shows degraded state | FNDTN-03 | Requires revoking Accessibility permission | Open System Settings → Privacy → Accessibility → remove FlowSpeech → wait 2s → observe icon |
| CPU <1% between sessions | FNDTN-04 | Requires Activity Monitor observation | Complete one recording session → wait 10s → check Activity Monitor CPU column |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 15s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
