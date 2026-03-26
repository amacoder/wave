---
phase: 4
slug: app-exclusion
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-26
---

# Phase 4 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | None detected — native macOS SwiftUI app; no XCTest configured |
| **Config file** | None |
| **Quick run command** | `xcodebuild build -scheme FlowSpeech -destination 'platform=macOS'` |
| **Full suite command** | Manual smoke test (build + hotkey suppression test) |
| **Estimated runtime** | ~30 seconds (build) |

---

## Sampling Rate

- **After every task commit:** Run `xcodebuild build -scheme FlowSpeech -destination 'platform=macOS'`
- **After every plan wave:** Manual smoke test of hotkey suppression with excluded app focused
- **Before `/gsd:verify-work`:** All three success criteria verified manually
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 04-01-01 | 01 | 1 | EXCL-01, EXCL-02, EXCL-03 | manual | Build succeeds | N/A | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

*Existing infrastructure covers all phase requirements — no test framework to install. All validation is manual functional testing per established project pattern.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Installed apps list populates with names, icons, checkboxes | EXCL-01 | UI rendering requires visual inspection | Open Settings > Exclusion tab; verify apps load with icons and checkboxes |
| Search field filters app list | EXCL-01 | UI interaction | Type in search field; verify list filters correctly |
| Checked app persists across relaunch | EXCL-01 | Requires app restart cycle | Check an app, quit, relaunch, verify checkbox state |
| Hotkey suppressed when excluded app is frontmost | EXCL-02 | Requires multi-app interaction | Exclude an app, focus it, hold hotkey; verify no recording starts |
| Auto-suppress in fullscreen apps | EXCL-02 | Requires fullscreen app | Enter fullscreen in any app with auto-suppress on; hold hotkey; verify suppression |
| Exclusion tab appears in Settings | EXCL-03 | UI presence check | Open Settings; verify Exclusion tab exists and is navigable |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
