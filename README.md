# Wave

**Effortless voice dictation for macOS** — Press one key. Start talking. Your words appear as clean, professional text instantly.

![macOS](https://img.shields.io/badge/macOS-13.0+-blue.svg)
![Swift](https://img.shields.io/badge/Swift-5.9-orange.svg)
![License](https://img.shields.io/badge/License-MIT-green.svg)

## Features

- **Voice-to-text anywhere** — Works in any app, inserts text at cursor
- **Smart Cleanup** — GPT-4o-mini removes filler words, fixes grammar and punctuation
- **Fast transcription** — Powered by OpenAI's GPT-4o Transcribe
- **Global hotkey** — Hold Fn (or Caps Lock) to record, release to transcribe
- **App exclusion** — Automatically suppresses hotkey in games and fullscreen apps
- **Live waveform** — Compact overlay pill with visual feedback
- **Secure** — API key stored in macOS Keychain
- **100+ languages** — Auto-detect or choose your language

## Requirements

- macOS 13.0 (Ventura) or later
- OpenAI API key with audio transcription access
- Accessibility permissions (for text insertion)
- Microphone permissions

## Installation

### Build from Source

1. **Clone the repository**
   ```bash
   git clone https://github.com/maewa-space/wave.git
   cd wave
   ```

2. **Open in Xcode**
   ```bash
   open FlowSpeech.xcodeproj
   ```

3. **Configure signing**
   - Open the project settings
   - Select your development team
   - Update the bundle identifier if needed

4. **Build and run**
   - Press `Cmd+R` or click the Play button

### First Run

1. Launch Wave
2. Complete the onboarding wizard:
   - Enter your OpenAI API key
   - Choose your preferred hotkey
   - Grant required permissions

## Usage

### Basic Recording

1. **Start recording:** Hold your chosen hotkey (default: Fn)
2. **Speak naturally:** The waveform shows you're being heard
3. **Stop recording:** Release the hotkey
4. **Text appears:** Clean, polished text is inserted at your cursor

### Hotkey Options

| Hotkey | Behavior |
|--------|----------|
| Hold Fn | Hold to record, release to transcribe |
| Hold Caps Lock | Hold to record, release to transcribe |
| Option + Space | Press to toggle recording |
| Control + Space | Press to toggle recording |

### Settings

Access settings via the menu bar icon → Settings (`Cmd+,`)

- **General** — Launch at login, permissions
- **Hotkey** — Choose activation method
- **Transcription** — Model selection, language, Smart Cleanup toggle
- **API** — OpenAI API key management
- **Exclusion** — App exclusion list, fullscreen auto-suppress
- **About** — Version info

## Architecture

```
FlowSpeech/
├── FlowSpeechApp.swift           # App entry point, AppState
├── AppDelegate.swift             # Menu bar, hotkeys, orchestration
├── DesignSystem.swift            # Amber/yellow palette tokens
├── Views/
│   ├── SettingsView.swift        # Sidebar settings (Stash-style)
│   ├── RecordingOverlayView.swift # Compact pill overlay (Glaido-style)
│   ├── ExclusionSettingsTab.swift # App exclusion UI
│   ├── OnboardingView.swift      # First-run wizard
│   └── MenuBarPopoverView.swift  # Quick access menu
├── Services/
│   ├── AudioRecorder.swift       # AVFoundation recording
│   ├── WhisperService.swift      # OpenAI transcription API
│   ├── TextCleanupService.swift  # GPT-4o-mini post-processing
│   ├── AppExclusionService.swift # App exclusion + fullscreen detection
│   ├── KeychainManager.swift     # Secure storage
│   ├── TextInserter.swift        # Accessibility text insertion
│   └── HotkeyManager.swift      # Global hotkey handling
└── Resources/
    └── Assets.xcassets           # Icons, colors
```

## API Costs

| Model | Cost | Quality |
|-------|------|---------|
| GPT-4o Transcribe | $0.006/min | Best (recommended) |
| GPT-4o Mini Transcribe | $0.003/min | Good, faster |
| Whisper-1 | $0.006/min | Legacy |

Smart Cleanup adds ~$0.001 per transcription (GPT-4o-mini).

A typical 30-second recording costs less than $0.01.

## Troubleshooting

### "Accessibility permission required"
System Settings → Privacy & Security → Accessibility → Enable Wave

### "Microphone access denied"
System Settings → Privacy & Security → Microphone → Enable Wave

### Text not appearing
- Ensure the target app has a focused text field
- Check Accessibility permissions
- Text is always copied to clipboard as fallback

### Caps Lock still toggles caps
System Settings → Keyboard → Modifier Keys → Set Caps Lock to "No Action"

## Privacy

- **API key:** Stored locally in macOS Keychain, never transmitted except to OpenAI
- **Audio:** Sent to OpenAI for transcription, not stored locally after processing
- **No telemetry:** Wave doesn't collect any usage data

## License

MIT License - See [LICENSE](LICENSE) for details.

---

**Made by [Amadeus](https://github.com/maewa-space)**
