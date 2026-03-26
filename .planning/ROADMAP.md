# Roadmap: SpeechFlow

## Milestones

- 🚧 **v1.1 UI Revamp & Polish** - Phases 1-4 (in progress)

## Overview

v1.1 builds four capabilities on top of the working v1.0 foundation: a design system and state machine refactor that unblocks all UI work, an isolated clipboard persistence fix, a full overlay redesign with spring animations, and a game/fullscreen app exclusion system with Settings UI. Phases are ordered by dependency — nothing in Phase 3 or 4 can be built correctly without Phase 1, and clipboard persistence is independent enough to ship and validate early.

## Phases

- [x] **Phase 1: Foundation** - RecordingPhase enum, design tokens, CGEventTap health, animation gating (completed 2026-03-26)
- [x] **Phase 2: Clipboard Persistence** - Fix clipboard restore bug, add changeCount guard and TransientType marker (completed 2026-03-26)
- [x] **Phase 3: Overlay Redesign** - Pill shape, 4-state rendering, spring animations, Canvas waveform (completed 2026-03-26)
- [ ] **Phase 4: App Exclusion** - Installed apps picker, fullscreen detection, Exclusion settings tab

## Phase Details

### Phase 1: Foundation
**Goal**: The app has a shared design system and a single RecordingPhase enum driving all state, with CGEventTap health verified and animation CPU drain prevented
**Depends on**: Nothing (first phase)
**Requirements**: FNDTN-01, FNDTN-02, FNDTN-03, FNDTN-04
**Success Criteria** (what must be TRUE):
  1. App compiles and runs with RecordingPhase enum replacing dual isRecording/isTranscribing booleans at all call sites
  2. All UI references a DesignSystem.swift constants file for deep navy, vibrant blue, and soft blue-white colors rather than hardcoded hex values
  3. CGEventTap health is checked every 2 seconds and the menu bar icon reflects a degraded state if the tap cannot be re-enabled
  4. SwiftUI animations on the overlay do not execute while the overlay window is hidden (verified via Activity Monitor CPU at <1% between sessions)
**Plans:** 2/2 plans complete
Plans:
- [ ] 01-01-PLAN.md — RecordingPhase enum + CGEventTap health monitoring
- [ ] 01-02-PLAN.md — DesignSystem tokens + animation phase gating

### Phase 2: Clipboard Persistence
**Goal**: Transcription always remains on the clipboard after paste, and clipboard managers do not log transcription content
**Depends on**: Phase 1
**Requirements**: CLIP-01, CLIP-02, CLIP-03
**Success Criteria** (what must be TRUE):
  1. After dictating and pasting, the transcribed text is still available via Cmd+V (clipboard not restored to prior content)
  2. If the user copies something else during the paste window, their copy is preserved and the transcription restore is skipped
  3. Clipboard managers (e.g., Paste, Raycast clipboard history) do not record transcription content due to the TransientType marker
**Plans:** 1 plan
Plans:
- [x] 02-01-PLAN.md — Remove clipboard restore, add TransientType marker and changeCount guard

### Phase 3: Overlay Redesign
**Goal**: The recording overlay is a polished pill shape at bottom-center with distinct visuals for all four states and smooth spring transitions between them
**Depends on**: Phase 1
**Requirements**: OVLAY-01, OVLAY-02, OVLAY-03, OVLAY-04
**Success Criteria** (what must be TRUE):
  1. The overlay appears as a pill (Capsule) positioned at bottom-center of the main screen with the blue palette applied
  2. Each of the four states (idle, recording, transcribing, done) renders a visually distinct appearance — a human observer can identify the current state without any other information
  3. Transitions between states use spring animations with no abrupt cuts or layout jumps
  4. The waveform renders using a Canvas single-draw-pass and the overlay window disappears after a 0.8s done-state flash
**Plans:** 1/1 plans complete
Plans:
- [ ] 03-01-PLAN.md — Pill overlay rewrite with 4-state ZStack, Canvas waveform, spring transitions, and done-flash timing

### Phase 4: App Exclusion
**Goal**: Users can explicitly exclude apps from triggering dictation, and the hotkey is automatically suppressed when a fullscreen or borderless-windowed app is focused
**Depends on**: Phase 1
**Requirements**: EXCL-01, EXCL-02, EXCL-03
**Success Criteria** (what must be TRUE):
  1. User can open Settings, navigate to an Exclusion tab, browse installed apps with a search field, and toggle exclusion via checkboxes — no manual bundle ID entry required
  2. Holding the hotkey while a manually excluded app (e.g., League of Legends) is in focus does not start recording
  3. Holding the hotkey while any fullscreen or borderless-windowed app is focused does not start recording (when auto-suppress toggle is enabled)
**Plans:** 2 plans
Plans:
- [ ] 04-01-PLAN.md — AppExclusionService with suppression logic, fullscreen detection, and hotkey guard wiring
- [ ] 04-02-PLAN.md — ExclusionSettingsTab UI with installed apps picker, search, checkboxes, and visual verification

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Foundation | 2/2 | Complete   | 2026-03-26 |
| 2. Clipboard Persistence | 1/1 | Complete    | 2026-03-26 |
| 3. Overlay Redesign | 1/1 | Complete   | 2026-03-26 |
| 4. App Exclusion | 0/2 | Not started | - |

---
*Roadmap created: 2026-03-26*
*Milestone: v1.1 UI Revamp & Polish*
