# Requirements: Wave

**Defined:** 2026-03-26
**Core Value:** Hold a key, speak, and have accurate text appear where you need it — zero friction dictation.

## v1.1 Requirements (Complete)

### Foundation

- [x] **FNDTN-01**: App uses a RecordingPhase enum (idle/recording/transcribing/done) instead of dual booleans
- [x] **FNDTN-02**: App has centralized blue design tokens (deep navy, vibrant blue, soft blue-white)
- [x] **FNDTN-03**: CGEventTap health is verified periodically and re-enabled if silently disabled
- [x] **FNDTN-04**: SwiftUI animations stop when overlay window is hidden

### Overlay UI

- [x] **OVLAY-01**: Recording overlay is a pill shape positioned at bottom-center of screen
- [x] **OVLAY-02**: Overlay renders 4 distinct visual states (idle, recording, transcribing, done)
- [x] **OVLAY-03**: State transitions use spring animations with subtle fades
- [x] **OVLAY-04**: Waveform uses Canvas single-draw-pass instead of ForEach+bars

### Clipboard

- [x] **CLIP-01**: Transcription remains on clipboard after paste (no restore of previous content)
- [x] **CLIP-02**: Clipboard restore only occurs if user hasn't copied something else (changeCount guard)
- [x] **CLIP-03**: Clipboard writes include TransientType marker for clipboard manager compatibility

### App Exclusion

- [x] **EXCL-01**: User can select apps to exclude from an installed apps picker (no manual bundle ID entry)
- [x] **EXCL-02**: Hotkey is auto-suppressed when frontmost app is in fullscreen or borderless-windowed mode
- [x] **EXCL-03**: Settings includes an Exclusion tab with installed apps list, search, and checkboxes

## v1.2 Requirements

Requirements for Companion App milestone.

### App Shell

- [ ] **SHELL-01**: User can open a companion window with sidebar navigation (Home, Dictionary, Snippets)
- [x] **SHELL-02**: App shows dock icon when companion window is open and hides it when closed
- [ ] **SHELL-03**: Companion window uses SwiftUI WindowGroup with SwiftData ModelContainer shared across app

### History

- [x] **HIST-01**: Every completed transcription is automatically saved with timestamp, raw text, cleaned text, duration, word count, and focused app name
- [x] **HIST-02**: User can view transcription history grouped by date (Today, Yesterday, This Week, Older)
- [x] **HIST-03**: User can see stats bar showing streak days, total word count, and average WPM
- [x] **HIST-04**: User can copy a transcription entry's text to clipboard
- [x] **HIST-05**: User can delete individual transcription entries

### Dictionary

- [ ] **DICT-01**: User can add custom words/terms to improve Whisper transcription accuracy
- [ ] **DICT-02**: User can add abbreviation expansions (e.g., "btw" → "by the way")
- [ ] **DICT-03**: Dictionary words are fed into Whisper API prompt parameter (with 224-token cap enforced)
- [ ] **DICT-04**: User can search, edit, and delete dictionary entries
- [ ] **DICT-05**: Dictionary UI shows character count toward the Whisper prompt limit

### Snippets

- [ ] **SNIP-01**: User can create text expansion snippets with trigger phrase and expanded text
- [ ] **SNIP-02**: Trigger phrases in transcriptions are automatically replaced with expanded text (case-insensitive)
- [ ] **SNIP-03**: Snippet expansion runs after GPT-4o-mini cleanup, before paste
- [ ] **SNIP-04**: User can search, edit, and delete snippet entries

## Future Requirements

### Enhancements

- **ENH-01**: Notch-based UI for MacBooks with hardware notch
- **ENH-02**: On-device transcription (local Whisper model)
- **ENH-03**: Multi-language auto-detection
- **STYLE-01**: Writing style/formatting preferences
- **NOTES-01**: Quick voice notes (scratchpad)
- **AUDIO-01**: Download/replay audio for past transcriptions
- **RETRY-01**: Retry transcription for a history entry (requires stored audio)

## Out of Scope

| Feature | Reason |
|---------|--------|
| On-device transcription | High complexity, Whisper API sufficient |
| Notch integration | Not all Macs have notch |
| Multi-language auto-detect | Single language hint sufficient |
| Style/writing preferences | Deferred to v1.3 |
| Notes/Scratchpad | Deferred to v1.3 |
| Audio download/replay | Deferred to v1.3 (storage complexity) |
| Retry transcript | Requires audio storage, deferred to v1.3 |
| Team sharing (dictionary/snippets) | Solo user for now |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| FNDTN-01 | Phase 1 | Complete |
| FNDTN-02 | Phase 1 | Complete |
| FNDTN-03 | Phase 1 | Complete |
| FNDTN-04 | Phase 1 | Complete |
| CLIP-01 | Phase 2 | Complete |
| CLIP-02 | Phase 2 | Complete |
| CLIP-03 | Phase 2 | Complete |
| OVLAY-01 | Phase 3 | Complete |
| OVLAY-02 | Phase 3 | Complete |
| OVLAY-03 | Phase 3 | Complete |
| OVLAY-04 | Phase 3 | Complete |
| EXCL-01 | Phase 4 | Complete |
| EXCL-02 | Phase 4 | Complete |
| EXCL-03 | Phase 4 | Complete |
| SHELL-01 | Phase 5 | Pending |
| SHELL-02 | Phase 5 | Complete |
| SHELL-03 | Phase 5 | Pending |
| HIST-01 | Phase 6 | Complete |
| HIST-02 | Phase 6 | Complete |
| HIST-03 | Phase 6 | Complete |
| HIST-04 | Phase 6 | Complete |
| HIST-05 | Phase 6 | Complete |
| DICT-01 | Phase 7 | Pending |
| DICT-02 | Phase 7 | Pending |
| DICT-03 | Phase 7 | Pending |
| DICT-04 | Phase 7 | Pending |
| DICT-05 | Phase 7 | Pending |
| SNIP-01 | Phase 7 | Pending |
| SNIP-02 | Phase 7 | Pending |
| SNIP-03 | Phase 7 | Pending |
| SNIP-04 | Phase 7 | Pending |

**Coverage:**
- v1.1 requirements: 14 total (all complete)
- v1.2 requirements: 16 total
- Mapped to phases: 16/16 ✓
- Unmapped: 0 ✓

---
*Requirements defined: 2026-03-26*
*Last updated: 2026-03-30 — v1.2 requirements mapped to phases 5-7*
