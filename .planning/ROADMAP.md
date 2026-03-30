# Roadmap: Wave

## Milestones

- ✅ **v1.1 UI Revamp & Polish** - Phases 1-4 (shipped 2026-03-26)
- 🚧 **v1.2 Companion App** - Phases 5-8 (in progress)

## Overview

v1.1 built the design system, clipboard persistence, overlay redesign, and app exclusion on top of the v1.0 foundation. v1.2 transforms Wave from a menu-bar-only utility into a full companion app: a windowed SwiftUI companion with SwiftData persistence, transcription history with date groupings and stats, a custom dictionary that injects vocabulary into the Whisper API, and text expansion snippets that fire after GPT cleanup. Phases are ordered by hard dependency — the SwiftData ModelContainer and WindowGroup must exist before any feature can be built, history is the highest user-value feature and ships early, and integration edge cases (focus restoration, overlay/companion interaction) are validated last when both subsystems exist simultaneously.

## Phases

<details>
<summary>✅ v1.1 UI Revamp & Polish (Phases 1-4) - SHIPPED 2026-03-26</summary>

- [x] **Phase 1: Foundation** - RecordingPhase enum, design tokens, CGEventTap health, animation gating (completed 2026-03-26)
- [x] **Phase 2: Clipboard Persistence** - Fix clipboard restore bug, add changeCount guard and TransientType marker (completed 2026-03-26)
- [x] **Phase 3: Overlay Redesign** - Pill shape, 4-state rendering, spring animations, Canvas waveform (completed 2026-03-26)
- [x] **Phase 4: App Exclusion** - Installed apps picker, fullscreen detection, Exclusion settings tab (completed 2026-03-26)

</details>

### v1.2 Companion App

- [ ] **Phase 5: Companion Shell** - WindowGroup companion window, NavigationSplitView sidebar, SwiftData ModelContainer, dock icon toggle
- [ ] **Phase 6: History** - Pipeline save, date-grouped HomeView, stats header, copy/delete actions, fetchLimit and retention
- [ ] **Phase 7: Dictionary & Snippets** - Whisper prompt injection via DictionaryService, snippet post-processing via SnippetService, CRUD views for both
- [ ] **Phase 8: Integration Polish** - Focus restoration before paste, overlay/companion interaction correctness, acceptance test against pitfalls checklist

## Phase Details

<details>
<summary>✅ v1.1 UI Revamp & Polish (Phases 1-4) - SHIPPED 2026-03-26</summary>

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
- [x] 01-01-PLAN.md — RecordingPhase enum + CGEventTap health monitoring
- [x] 01-02-PLAN.md — DesignSystem tokens + animation phase gating

### Phase 2: Clipboard Persistence
**Goal**: Transcription always remains on the clipboard after paste, and clipboard managers do not log transcription content
**Depends on**: Phase 1
**Requirements**: CLIP-01, CLIP-02, CLIP-03
**Success Criteria** (what must be TRUE):
  1. After dictating and pasting, the transcribed text is still available via Cmd+V (clipboard not restored to prior content)
  2. If the user copies something else during the paste window, their copy is preserved and the transcription restore is skipped
  3. Clipboard managers (e.g., Paste, Raycast clipboard history) do not record transcription content due to the TransientType marker
**Plans:** 1/1 plans complete
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
- [x] 03-01-PLAN.md — Pill overlay rewrite with 4-state ZStack, Canvas waveform, spring transitions, and done-flash timing

### Phase 4: App Exclusion
**Goal**: Users can explicitly exclude apps from triggering dictation, and the hotkey is automatically suppressed when a fullscreen or borderless-windowed app is focused
**Depends on**: Phase 1
**Requirements**: EXCL-01, EXCL-02, EXCL-03
**Success Criteria** (what must be TRUE):
  1. User can open Settings, navigate to an Exclusion tab, browse installed apps with a search field, and toggle exclusion via checkboxes — no manual bundle ID entry required
  2. Holding the hotkey while a manually excluded app (e.g., League of Legends) is in focus does not start recording
  3. Holding the hotkey while any fullscreen or borderless-windowed app is focused does not start recording (when auto-suppress toggle is enabled)
**Plans:** 2/2 plans complete
Plans:
- [x] 04-01-PLAN.md — AppExclusionService with suppression logic, fullscreen detection, and hotkey guard wiring
- [x] 04-02-PLAN.md — ExclusionSettingsTab UI with installed apps picker, search, checkboxes, and visual verification

</details>

---

### Phase 5: Companion Shell
**Goal**: Users can open a companion window with sidebar navigation, the app shows a dock icon when the window is open, and the shared SwiftData ModelContainer is wired correctly into both the window scene and AppDelegate
**Depends on**: Phase 4
**Requirements**: SHELL-01, SHELL-02, SHELL-03
**Success Criteria** (what must be TRUE):
  1. User can open the companion window from the menu bar and see a sidebar with Home, Dictionary, and Snippets navigation items
  2. Wave's dock icon appears when the companion window is open and disappears when the window is closed
  3. The companion window is a SwiftUI WindowGroup scene (not a manual NSWindow) so that @Query works correctly in all views
  4. SwiftData ModelContainer is initialized once in FlowSpeechApp.init() and shared with AppDelegate — no second container is ever created
**Plans:** 2 plans
Plans:
- [x] 05-01-PLAN.md — SwiftData models, ModelContainer, WindowGroup scene, NavigationSplitView sidebar with placeholder views
- [x] 05-02-PLAN.md — Dock icon toggle, window hide-on-close lifecycle, menu bar "Open Wave" item, dock-click reopen

### Phase 6: History
**Goal**: Every transcription is automatically saved and users can browse, copy, and delete their transcription history grouped by date with usage stats at a glance
**Depends on**: Phase 5
**Requirements**: HIST-01, HIST-02, HIST-03, HIST-04, HIST-05
**Success Criteria** (what must be TRUE):
  1. After completing a dictation, the transcription appears in the Home view without any manual action — timestamp, word count, WPM, and source app are all present
  2. The history list is grouped into Today, Yesterday, This Week, and Older sections — entries do not appear in a flat undifferentiated list
  3. A stats header above the list shows consecutive usage streak in days, total word count, and average WPM
  4. User can tap Copy on any entry to put its text on the clipboard, and Delete to remove it permanently
  5. History does not degrade in open speed after months of use — a fetchLimit of 200 and 90-day retention are enforced from day one
**Plans:** 2/2 plans complete
Plans:
- [x] 06-01-PLAN.md — Pipeline save hook, recording metadata capture, 90-day retention cleanup
- [x] 06-02-PLAN.md — HomeView with @Query, date grouping, stats header, copy/delete actions, undo toast

### Phase 7: Dictionary & Snippets
**Goal**: Users can teach Wave custom vocabulary that improves Whisper transcription accuracy, and create trigger phrases that automatically expand into longer text after each dictation
**Depends on**: Phase 5
**Requirements**: DICT-01, DICT-02, DICT-03, DICT-04, DICT-05, SNIP-01, SNIP-02, SNIP-03, SNIP-04
**Success Criteria** (what must be TRUE):
  1. User can add a custom word or abbreviation expansion in the Dictionary tab and the next transcription reflects the improvement (the term is fed into the Whisper API prompt parameter)
  2. The Dictionary tab shows a live character count toward the Whisper prompt limit and warns when approaching the cap
  3. User can search, edit, and delete dictionary entries from the Dictionary tab
  4. User can create a snippet with a trigger phrase and expanded text, and saying the trigger phrase in any dictation automatically replaces it with the expanded text before the text is pasted
  5. Snippet expansion runs after GPT-4o-mini cleanup and before paste — the final pasted text contains expanded content, not raw triggers
  6. User can search, edit, and delete snippet entries from the Snippets tab
**Plans:** 4 plans
Plans:
- [ ] 07-01-PLAN.md — DictionaryService + SnippetService with shared TextReplacer engine
- [ ] 07-02-PLAN.md — DictionaryView full CRUD with search, edit sheet, and character count bar
- [ ] 07-03-PLAN.md — SnippetsView full CRUD with search, edit sheet, and two-line row display
- [ ] 07-04-PLAN.md — Pipeline wiring in AppDelegate (prompt injection + post-transcription expansion)

### Phase 8: Integration Polish
**Goal**: Dictation pasting goes to the correct app even when the companion window is open, and the overlay and companion window do not interfere with each other's focus behavior
**Depends on**: Phase 7
**Requirements**: — (cross-cutting correctness, no dedicated requirements)
**Success Criteria** (what must be TRUE):
  1. Dictating while the companion window is open pastes text into the previously focused app, not into the companion window
  2. Opening the companion window while a dictation is in progress is blocked — the window only opens when the app is idle
  3. The recording overlay does not steal keyboard focus from text fields in the companion window
**Plans**: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 5 → 6 → 7 → 8

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Foundation | v1.1 | 2/2 | Complete | 2026-03-26 |
| 2. Clipboard Persistence | v1.1 | 1/1 | Complete | 2026-03-26 |
| 3. Overlay Redesign | v1.1 | 1/1 | Complete | 2026-03-26 |
| 4. App Exclusion | v1.1 | 2/2 | Complete | 2026-03-26 |
| 5. Companion Shell | v1.2 | 2/2 | Complete | 2026-03-30 |
| 6. History | v1.2 | 2/2 | Complete   | 2026-03-30 |
| 7. Dictionary & Snippets | v1.2 | 0/4 | Not started | - |
| 8. Integration Polish | v1.2 | 0/TBD | Not started | - |

---
*Roadmap created: 2026-03-26*
*v1.2 phases added: 2026-03-30*
*Milestone: v1.2 Companion App*
