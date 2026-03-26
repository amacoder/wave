# Requirements: SpeechFlow

**Defined:** 2026-03-26
**Core Value:** Hold a key, speak, and have accurate text appear where you need it — zero friction dictation.

## v1.1 Requirements

Requirements for UI Revamp & Polish milestone. Each maps to roadmap phases.

### Foundation

- [ ] **FNDTN-01**: App uses a RecordingPhase enum (idle/recording/transcribing/done) instead of dual booleans
- [ ] **FNDTN-02**: App has centralized blue design tokens (deep navy, vibrant blue, soft blue-white)
- [ ] **FNDTN-03**: CGEventTap health is verified periodically and re-enabled if silently disabled
- [ ] **FNDTN-04**: SwiftUI animations stop when overlay window is hidden

### Overlay UI

- [ ] **OVLAY-01**: Recording overlay is a pill shape positioned at bottom-center of screen
- [ ] **OVLAY-02**: Overlay renders 4 distinct visual states (idle, recording, transcribing, done)
- [ ] **OVLAY-03**: State transitions use spring animations with subtle fades
- [ ] **OVLAY-04**: Waveform uses Canvas single-draw-pass instead of ForEach+bars

### Clipboard

- [ ] **CLIP-01**: Transcription remains on clipboard after paste (no restore of previous content)
- [ ] **CLIP-02**: Clipboard restore only occurs if user hasn't copied something else (changeCount guard)
- [ ] **CLIP-03**: Clipboard writes include TransientType marker for clipboard manager compatibility

### App Exclusion

- [ ] **EXCL-01**: User can select apps to exclude from an installed apps picker (no manual bundle ID entry)
- [ ] **EXCL-02**: Hotkey is auto-suppressed when frontmost app is in fullscreen or borderless-windowed mode
- [ ] **EXCL-03**: Settings includes an Exclusion tab with installed apps list, search, and checkboxes

## Future Requirements

### Enhancements

- **ENH-01**: Notch-based UI for MacBooks with hardware notch
- **ENH-02**: On-device transcription (local Whisper model)
- **ENH-03**: Multi-language auto-detection

## Out of Scope

| Feature | Reason |
|---------|--------|
| On-device transcription | High complexity, Whisper API sufficient for v1.1 |
| Notch integration | Not all Macs have notch, defer to future |
| Multi-language auto-detect | Single language hint sufficient |
| Custom hotkey recording | Existing 5 hotkey options cover common cases |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| FNDTN-01 | — | Pending |
| FNDTN-02 | — | Pending |
| FNDTN-03 | — | Pending |
| FNDTN-04 | — | Pending |
| OVLAY-01 | — | Pending |
| OVLAY-02 | — | Pending |
| OVLAY-03 | — | Pending |
| OVLAY-04 | — | Pending |
| CLIP-01 | — | Pending |
| CLIP-02 | — | Pending |
| CLIP-03 | — | Pending |
| EXCL-01 | — | Pending |
| EXCL-02 | — | Pending |
| EXCL-03 | — | Pending |

**Coverage:**
- v1.1 requirements: 14 total
- Mapped to phases: 0
- Unmapped: 14 ⚠️

---
*Requirements defined: 2026-03-26*
*Last updated: 2026-03-26 after initial definition*
