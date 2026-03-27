# Wave

**Effortless voice dictation for macOS** — Press one key. Start talking. Your words appear as clean, professional text instantly.

![macOS](https://img.shields.io/badge/macOS-13.0+-blue.svg)
![Swift](https://img.shields.io/badge/Swift-5.9-orange.svg)
![License](https://img.shields.io/badge/License-MIT-green.svg)

## Features

- **Voice-to-text anywhere** — Works in any app, inserts text at cursor
- **Smart Cleanup** — GPT-4o-mini removes filler words (um, uh, like, you know), fixes grammar and punctuation automatically
- **Fast transcription** — Powered by OpenAI's GPT-4o Transcribe
- **Clipboard persistence** — Transcription stays on your clipboard after paste, always available via Cmd+V
- **App exclusion** — Automatically suppresses hotkey in games and fullscreen apps
- **Global hotkey** — Hold Fn (or Caps Lock) to record, release to transcribe
- **Compact overlay** — Minimal pill with waveform, sits above the dock
- **Sidebar settings** — Clean, organized preferences with 6 tabs
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
   git clone https://github.com/amacoder/wave.git
   cd wave
   ```

2. **Open in Xcode**
   ```bash
   open Wave.xcodeproj
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
Wave/
├── WaveApp.swift           # App entry point, AppState
├── AppDelegate.swift             # Menu bar, hotkeys, orchestration
├── DesignSystem.swift            # Amber/yellow palette tokens
├── Views/
│   ├── SettingsView.swift        # Sidebar settings
│   ├── RecordingOverlayView.swift # Compact pill overlay
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

## Changelog

### v1.1 — UI Revamp & Polish (2026-03-26)

**Rebrand**
- Custom amber/yellow color palette and branding
- New amber/yellow color palette and custom wave app icon
- Programmatic wave icon in menu bar (turns amber when recording)

**Smart Cleanup (New)**
- GPT-4o-mini post-processing removes filler words (um, uh, like, you know, basically, literally)
- Fixes grammar and punctuation while preserving meaning
- Toggle on/off in Settings → Transcription

**Transcription Upgrade**
- Added GPT-4o Transcribe model (best quality, same price as Whisper-1)
- Added GPT-4o Mini Transcribe (half price, still good)
- Whisper-1 kept as legacy option
- Updated model comparison in Settings

**UI Overhaul**
- Sidebar settings layout (inspired by Stash) replacing dropdown tab bar
- Compact recording overlay pill (inspired by Glaido) — icon + waveform only, no text
- Recording overlay sits just above the dock

**Clipboard Persistence**
- Transcription stays on clipboard after paste
- Always available via Cmd+V even if no text field was focused

**App Exclusion**
- Exclude specific apps from triggering dictation (e.g., games)
- Auto-suppress hotkey in fullscreen and borderless-windowed apps
- Searchable installed apps list with icons and checkboxes in Settings
- League of Legends pre-excluded by default

**Foundation**
- Centralized design system with amber palette tokens
- Smooth spring animations across all state transitions
- CGEventTap health monitoring with auto-recovery

### v1.0 — Initial Release

- Hold-to-record voice dictation with Whisper API
- Auto-paste transcription to active text field
- 5 hotkey options (Fn, Caps Lock, Option+Space, Control+Space)
- Onboarding wizard
- Keychain-secured API key storage
- Menu bar integration
- 100+ language support

## License

MIT License - See [LICENSE](LICENSE) for details.

---

**Made by [Wave Contributors](https://github.com/amacoder/wave)**
