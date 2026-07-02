# Wave - Voice Dictation App for macOS

**Status:** ✅ Ready for Testing  
**Created:** 2026-01-29  
**Owner:** Amadeus  
**Version:** 1.0.0

---

## Overview

Wave is a native macOS voice dictation app. It provides effortless voice-to-text in any application using OpenAI's transcription API.

## Implementation Status

### ✅ Completed Features

1. **Native SwiftUI Mac App**
   - Menu bar app (no dock icon by default)
   - Floating recording overlay with waveform
   - Settings window with tabbed UI
   - Onboarding wizard for first-run setup

2. **Global Hotkey System**
   - Hold Caps Lock to record, release to transcribe
   - Double-tap Caps Lock option
   - Option+Space and Control+Space alternatives
   - Escape to cancel recording

3. **Audio Recording**
   - AVFoundation-based recording
   - 16kHz mono M4A format (optimized for speech)
   - Real-time audio level metering
   - Live waveform visualization

4. **OpenAI Whisper Integration**
   - Supports `gpt-4o-transcribe`, `gpt-4o-mini-transcribe`, `whisper-1`
   - Language selection (auto-detect or 20+ languages)
   - Proper error handling with user-friendly messages
   - Multipart form upload

5. **Text Insertion**
   - Accessibility API for direct insertion at cursor
   - Clipboard fallback (paste + restore)
   - Works in most text fields

6. **Secure Storage**
   - API key stored in macOS Keychain
   - Never stored in plaintext or transmitted unnecessarily

7. **Polished UI**
   - Deep blue (#2563EB) / Teal (#0D9488) gradient accents
   - Dark/Light mode support via system colors
   - Visual feedback for all states (ready, recording, transcribing)
   - Sound effects for start/stop/error

---

## Architecture

```
FlowSpeech/
├── FlowSpeechApp.swift          # App entry point, AppState model
├── AppDelegate.swift            # Menu bar, global hotkeys, orchestration
├── Views/
│   ├── SettingsView.swift       # 5-tab settings window
│   ├── RecordingOverlayView.swift  # Floating indicator + waveform
│   ├── OnboardingView.swift     # First-run wizard
│   └── MenuBarPopoverView.swift # Quick access popover
├── Services/
│   ├── AudioRecorder.swift      # AVFoundation recording + metering
│   ├── WhisperService.swift     # OpenAI API client
│   ├── KeychainManager.swift    # Secure API key storage
│   ├── TextInserter.swift       # Accessibility API text insertion
│   └── HotkeyManager.swift      # CGEvent hotkey handling
├── Resources/
│   └── Assets.xcassets          # Colors, app icon
├── Info.plist                   # App configuration
└── FlowSpeech.entitlements      # Permissions
```

---

## Technical Decisions Made

### 1. Hotkey Implementation
**Decision:** Use NSEvent monitors for Caps Lock, CGEventTap for advanced combos.

**Rationale:** NSEvent.addGlobalMonitorForEvents works well for flagsChanged (Caps Lock) without needing full event tap permissions. The CGEventTap is available for more complex scenarios.

### 2. Audio Format
**Decision:** M4A at 16kHz mono, 64kbps AAC

**Rationale:** 
- 16kHz is optimal for speech recognition (Whisper recommends it)
- AAC compression keeps file sizes small
- M4A is natively supported by macOS and OpenAI

### 3. App Sandbox
**Decision:** Disabled (hardened runtime enabled)

**Rationale:** 
- Event taps for global hotkeys don't work in sandbox
- Accessibility API requires non-sandboxed execution
- Hardened runtime provides security without sandbox limitations

### 4. Text Insertion Strategy
**Decision:** Try Accessibility API first, fall back to clipboard paste

**Rationale:**
- Accessibility API provides seamless insertion
- Clipboard fallback ensures broad compatibility
- Original clipboard content is restored after paste

### 5. Default Model
**Decision:** `gpt-4o-transcribe` (best quality)

**Rationale:** Quality is more important than slight speed gains for dictation. Users can switch to mini model in settings if preferred.

---

## UI Design

### Color Palette
| Purpose | Light Mode | Dark Mode |
|---------|------------|-----------|
| Primary Accent | #2563EB (Deep Blue) | #608AFA |
| Secondary Accent | #0D9488 (Teal) | #14B8A6 |
| Recording | #EF4444 (Red) | #EF4444 |
| Background | System | System |

### Recording Overlay
- 200x80 floating window
- Ultra-thin material background
- Pulsing red indicator
- 15-bar waveform visualization
- "ESC to cancel" hint

### Settings Window
- 5 tabs: General, Hotkey, Transcription, API, About
- 500x400 window
- Native macOS form styling

---

## Permissions Required

| Permission | Purpose | Requested When |
|------------|---------|----------------|
| Microphone | Audio recording | First recording attempt |
| Accessibility | Text insertion | Onboarding |

**Note:** Users should also be guided to disable Caps Lock's default behavior in System Settings → Keyboard → Modifier Keys.

---

## Build Instructions

1. Open `FlowSpeech.xcodeproj` in Xcode 15+
2. Select your development team for signing
3. Build and run (⌘R)

### For Release
```bash
xcodebuild -scheme FlowSpeech -configuration Release archive
```

---

## Testing Checklist

### Core Functionality
- [ ] App launches and shows in menu bar
- [ ] Settings window opens (menu bar → Settings)
- [ ] API key saves to Keychain
- [ ] Caps Lock hold starts recording
- [ ] Waveform animates during recording
- [ ] Release stops and transcribes
- [ ] Text inserts at cursor in TextEdit
- [ ] Text inserts in browser text fields
- [ ] ESC cancels recording

### Error Handling
- [ ] Missing API key shows clear error
- [ ] Invalid API key shows API error message
- [ ] Network failure handled gracefully
- [ ] Audio permission denied shows guidance

### UI Polish
- [ ] Dark mode looks correct
- [ ] Light mode looks correct
- [ ] Recording overlay appears near top center
- [ ] Onboarding completes without errors
- [ ] All hotkey options work

---

## Future Enhancements

1. **Streaming Transcription** — Show text as it's transcribed
2. **Personal Dictionary** — Custom words for better accuracy
3. **App-specific Tones** — Adjust formality per app
4. **History** — View recent transcriptions
5. **Snippets** — Voice shortcuts for common phrases
6. **Menu Bar Animation** — Waveform in menu bar icon during recording
7. **App Icon** — Custom designed icon (currently uses system symbol)

---

## Resources

- [OpenAI Speech-to-Text Docs](https://platform.openai.com/docs/guides/speech-to-text)
- [Apple AVFoundation](https://developer.apple.com/av-foundation/)
- [Apple Accessibility](https://developer.apple.com/documentation/accessibility)

---

## Changelog

### v1.0.0 (2026-01-29)
- Initial implementation
- Core voice dictation functionality
- Settings UI with all configuration options
- Onboarding wizard
- Multiple hotkey options
- Multi-language support
