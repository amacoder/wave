# Wave

**Effortless voice dictation for macOS** — Press one key. Start talking. Your words appear as clean, professional text instantly.

![macOS](https://img.shields.io/badge/macOS-14.0+-blue.svg)
![Swift](https://img.shields.io/badge/Swift-5.9-orange.svg)
![License](https://img.shields.io/badge/License-MIT-green.svg)

## Features

- **Voice-to-text anywhere** — Works in any app, inserts text at cursor
- **Smart Cleanup** — GPT-4o-mini removes filler words (um, uh, like, you know), fixes grammar and punctuation automatically
- **Fast transcription** — Powered by OpenAI's GPT-4o Transcribe
- **Companion Window** — Full app with sidebar navigation: Home, Dictionary, Snippets, Settings
- **Transcription History** — Browse past transcriptions grouped by date, with copy and delete
- **Custom Dictionary** — Add vocabulary to improve Whisper accuracy, create abbreviation expansions
- **Text Snippets** — Trigger phrases that automatically expand into longer text after dictation
- **Clipboard persistence** — Transcription stays on your clipboard after paste
- **App exclusion** — Automatically suppresses hotkey in games and fullscreen apps
- **Global hotkey** — Hold Fn (or Caps Lock) to record, release to transcribe
- **Compact overlay** — Minimal pill with waveform, sits above the dock
- **Sidebar settings** — Clean, organized preferences with 6 tabs
- **Secure** — API key stored in macOS Keychain
- **100+ languages** — Auto-detect or choose your language

## Requirements

- macOS 14.0 (Sonoma) or later
- OpenAI API key with audio transcription access
- Accessibility permissions (for text insertion)
- Microphone permissions

## Installation

1. **Clone the repo**
   ```bash
   git clone https://github.com/amacoder/wave.git
   cd wave
   ```

2. **Open in Xcode**
   ```bash
   open Wave.xcodeproj
   ```
   Configure your signing team, then `Cmd+R` to build and run.

3. **Or build a DMG**
   ```bash
   chmod +x build-dmg.sh
   ./build-dmg.sh
   ```
   This produces `Wave.dmg` in the project root — open it and drag to Applications.

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

### Dictionary

Add custom words to improve transcription accuracy:
- **Vocabulary hints** — Technical terms, names, jargon fed to Whisper as context
- **Abbreviations** — Short triggers that expand to full text (e.g., "btw" → "by the way")
- Character count bar shows progress toward the 1,100-char Whisper prompt limit

### Snippets

Create trigger phrases that auto-expand after dictation:
- Say "sig" → inserts your full name
- Say "my email" → inserts your email address
- Expansion runs after GPT cleanup, before paste

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
├── WaveApp.swift                    # App entry point, SwiftData container
├── AppDelegate.swift                # Menu bar, hotkeys, transcription pipeline
├── DesignSystem.swift               # Amber/yellow palette tokens
├── Models/
│   ├── TranscriptionEntry.swift     # History entry model (SwiftData)
│   ├── DictionaryWord.swift         # Vocabulary/abbreviation model
│   └── Snippet.swift                # Text expansion model
├── Views/
│   ├── CompanionWindow/
│   │   ├── CompanionWindowView.swift # Root NavigationSplitView
│   │   ├── SidebarView.swift        # Sidebar navigation
│   │   ├── HomeView.swift           # History + stats
│   │   ├── DictionaryView.swift     # CRUD dictionary management
│   │   ├── SnippetsView.swift       # CRUD snippet management
│   │   └── CompanionSettingsView.swift
│   ├── Shared/
│   │   ├── EmptyStateView.swift     # Reusable empty state
│   │   └── WindowAccessor.swift     # NSWindow bridge
│   ├── SettingsView.swift           # Sidebar settings
│   ├── RecordingOverlayView.swift   # Compact pill overlay
│   ├── ExclusionSettingsTab.swift   # App exclusion UI
│   ├── OnboardingView.swift         # First-run wizard
│   └── MenuBarPopoverView.swift     # Quick access menu
├── Services/
│   ├── AudioRecorder.swift          # AVFoundation recording
│   ├── WhisperService.swift         # OpenAI transcription API
│   ├── TextCleanupService.swift     # GPT-4o-mini post-processing
│   ├── DictionaryService.swift      # Vocabulary hints + abbreviation expansion
│   ├── SnippetService.swift         # Text expansion engine (TextReplacer)
│   ├── AppExclusionService.swift    # App exclusion + fullscreen detection
│   ├── KeychainManager.swift        # Secure storage
│   ├── TextInserter.swift           # Accessibility text insertion
│   └── HotkeyManager.swift         # Global hotkey handling
└── Resources/
    └── Assets.xcassets              # Icons, colors
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

### Fn key doesn't trigger recording (especially in Chrome)
macOS defaults to using the fn/globe key for the Emoji picker. This blocks Wave from seeing fn keypresses — particularly in Chrome, which fully suppresses the event. **This is required for fn key to work:**

System Settings → Keyboard → **"Press 🌐 key to"** → Set to **"Do Nothing"**

### Caps Lock still toggles caps
System Settings → Keyboard → Modifier Keys → Set Caps Lock to "No Action"

## Privacy

- **API key:** Stored locally in macOS Keychain, never transmitted except to OpenAI
- **Audio:** Sent to OpenAI for transcription, not stored locally after processing
- **No telemetry:** Wave doesn't collect any usage data

## License

MIT License - See [LICENSE](LICENSE) for details.

---

**Made by [Wave Contributors](https://github.com/amacoder/wave)**
