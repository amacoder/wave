# Flow Speech

**Effortless voice dictation for macOS** - A native SwiftUI app inspired by [Wispr Flow](https://wisprflow.ai/).

![macOS](https://img.shields.io/badge/macOS-13.0+-blue.svg)
![Swift](https://img.shields.io/badge/Swift-5.9-orange.svg)
![License](https://img.shields.io/badge/License-MIT-green.svg)

## Features

- 🎙️ **Voice-to-text anywhere** — Works in any app, inserts text at cursor
- ⚡ **Fast transcription** — Powered by OpenAI's Whisper API
- 🎯 **Global hotkey** — Hold Caps Lock to record, release to transcribe
- 🌊 **Live waveform** — Visual feedback while recording
- 🔐 **Secure** — API key stored in macOS Keychain
- 🌍 **100+ languages** — Auto-detect or choose your language
- 🌓 **Dark/Light mode** — Adapts to your system theme

## Requirements

- macOS 13.0 (Ventura) or later
- OpenAI API key with audio transcription access
- Accessibility permissions (for text insertion)
- Microphone permissions

## Installation

### Build from Source

1. **Clone the repository**
   ```bash
   git clone https://github.com/yourusername/flow-speech.git
   cd flow-speech
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
   - Or build for release: `Cmd+Shift+R`

### First Run

1. Launch Flow Speech
2. Complete the onboarding wizard:
   - Enter your OpenAI API key
   - Choose your preferred hotkey
   - Grant required permissions

## Usage

### Basic Recording

1. **Start recording:** Hold your chosen hotkey (default: Caps Lock)
2. **Speak naturally:** The waveform shows you're being heard
3. **Stop recording:** Release the hotkey
4. **Text appears:** Transcribed text is inserted at your cursor

### Hotkey Options

| Hotkey | Behavior |
|--------|----------|
| Hold Caps Lock | Hold to record, release to transcribe |
| Double-tap Caps Lock | Tap twice to start, tap again to stop |
| Option + Space | Press to toggle recording |
| Control + Space | Press to toggle recording |

### Settings

Access settings via:
- Menu bar icon → Settings
- Keyboard shortcut: `Cmd+,`

**Available settings:**
- Model selection (GPT-4o Transcribe, Mini, Whisper-1)
- Language preference
- Launch at login
- Hotkey configuration

### Tips

- **Caps Lock users:** Consider disabling Caps Lock's default behavior in System Settings → Keyboard → Modifier Keys (set Caps Lock to "No Action")
- **Better accuracy:** Speak clearly with minimal background noise
- **Long recordings:** Whisper supports up to 25MB audio files

## Architecture

```
FlowSpeech/
├── FlowSpeechApp.swift          # App entry point, AppState
├── AppDelegate.swift            # Menu bar, hotkeys, orchestration
├── Views/
│   ├── SettingsView.swift       # Preferences tabs
│   ├── RecordingOverlayView.swift # Floating recording indicator
│   ├── OnboardingView.swift     # First-run wizard
│   └── MenuBarPopoverView.swift # Quick access menu
├── Services/
│   ├── AudioRecorder.swift      # AVFoundation recording
│   ├── WhisperService.swift     # OpenAI API integration
│   ├── KeychainManager.swift    # Secure storage
│   ├── TextInserter.swift       # Accessibility text insertion
│   └── HotkeyManager.swift      # Global hotkey handling
└── Resources/
    └── Assets.xcassets          # Colors, icons
```

## API Costs

Flow Speech uses OpenAI's Whisper API:

| Model | Cost | Quality |
|-------|------|---------|
| gpt-4o-transcribe | $0.006/min | Best |
| gpt-4o-mini-transcribe | $0.003/min | Good |
| whisper-1 | $0.006/min | Classic |

A typical 30-second recording costs less than $0.01.

## Troubleshooting

### "Accessibility permission required"
Go to System Settings → Privacy & Security → Accessibility → Enable Flow Speech

### "Microphone access denied"
Go to System Settings → Privacy & Security → Microphone → Enable Flow Speech

### Text not appearing
- Ensure the target app has a focused text field
- Try the clipboard fallback (text is copied if direct insertion fails)
- Check Accessibility permissions

### Caps Lock still toggles caps
System Settings → Keyboard → Modifier Keys → Set Caps Lock to "No Action"

## Development

### Building
```bash
xcodebuild -scheme FlowSpeech -configuration Release
```

### Running Tests
```bash
xcodebuild test -scheme FlowSpeech
```

## Privacy

- **API key:** Stored locally in macOS Keychain, never transmitted except to OpenAI
- **Audio:** Sent to OpenAI for transcription, not stored locally after processing
- **No telemetry:** Flow Speech doesn't collect any usage data

## License

MIT License - See [LICENSE](LICENSE) for details.

## Acknowledgments

- Inspired by [Wispr Flow](https://wisprflow.ai/)
- Powered by [OpenAI Whisper](https://openai.com/research/whisper)
- Built with SwiftUI and ❤️

---

**Made by Amadeus** 
