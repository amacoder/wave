# Wave

## What This Is

A macOS menu bar speech-to-text app that lets you hold a hotkey (Fn by default), speak, and have your words transcribed via OpenAI Whisper and automatically pasted into whatever text field is focused. Built with SwiftUI, targeting macOS with a minimal, non-intrusive overlay UI.

## Core Value

Hold a key, speak, and have accurate text appear where you need it — zero friction dictation that stays out of your way.

## Current Milestone: v1.2 Companion App

**Goal:** Transform Wave from a menu-bar-only utility into a full companion app with transcription history, custom vocabulary, and text expansion snippets.

**Target features:**
- Windowed app with sidebar navigation and dock presence
- Home: transcription history with date groupings, stats (streak, word count, WPM)
- Per-entry actions: copy, delete, retry transcript
- Dictionary: custom vocabulary/terms to improve transcription accuracy
- Snippets: text expansion shortcuts (say trigger phrase → inserts expanded text)
- SwiftData persistence (macOS 14+)

## Requirements

### Validated

<!-- Shipped and confirmed working in v1.0 -->

- Fn key hold-to-record dictation
- Whisper API transcription (model selection, language hints)
- Auto-paste to active text field via clipboard + Cmd+V
- Settings window (5 tabs: General, Hotkey, Transcription, API, About)
- Onboarding wizard (5 steps)
- Menu bar integration with recording state icon
- Floating overlay with waveform visualization
- ESC to cancel recording
- Keychain-secured API key storage
- Multiple hotkey options (Caps Lock, Fn, Option+Space, Control+Space, Double-tap Caps Lock)

### Active

- [ ] Windowed companion app with sidebar navigation and dock icon
- [ ] Transcription history with date groupings and stats
- [ ] Custom dictionary for vocabulary/term corrections
- [ ] Snippets for text expansion shortcuts
- [ ] Per-entry actions: copy, delete, retry transcript

### Out of Scope

- On-device transcription (Whisper API is sufficient for now) — complexity too high
- Notch integration — not all Macs have notch, defer to future
- Multiple language auto-detection — single language hint is enough
- Style/writing preferences — deferred to v1.3
- Notes/Scratchpad — deferred to v1.3
- Audio download/playback — deferred to v1.3
- Team sharing (dictionary/snippets) — solo user for now

## Context

- SwiftUI macOS app, 11 Swift source files
- Architecture: AppDelegate orchestrates services (AudioRecorder, WhisperService, TextInserter, HotkeyManager, KeychainManager)
- State: centralized AppState with RecordingPhase enum (idle/recording/transcribing/done)
- Design system: DesignSystem.swift with blue palette tokens (deepNavy, vibrantBlue, softBlueWhite, teal)
- CGEventTap health monitoring with auto-recovery in HotkeyManager
- Overlay: pill-shaped Capsule (280x52) at bottom-center with 4-state ZStack, Canvas waveform, spring transitions
- Text insertion: clipboard + CGEvent Cmd+V (transcription persists on clipboard, TransientType marker hides from clipboard managers)
- Hotkey detection: dual approach (NSEvent flagsChanged + CGEventTap backup)
- App exclusion: AppExclusionService with NSMetadataQuery app discovery, manual exclusion set, fullscreen/borderless detection via CGWindowListCopyWindowInfo, ExclusionSettingsTab in Settings
- Reference design: Glaido's "Flow Bar" — small pill overlay, soft neutrals, editorial aesthetic
- Target palette: deep navy background, vibrant blue accent, soft blue-white highlights

## Constraints

- **Platform**: macOS only (SwiftUI)
- **Permissions**: Requires Microphone, Accessibility, and Input Monitoring
- **API**: OpenAI Whisper API (requires user's API key)
- **Design reference**: Glaido aesthetic adapted to blue palette

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Blue palette over black/beige | User preference; blue is universally appealing and distinct from Glaido | — Pending |
| Glaido as design reference | Best-in-class UX for push-to-talk dictation apps | — Pending |
| Game exclusion via app detection | User plays League of Legends; accidental Fn triggers during gaming | Shipped Phase 04 |
| Clipboard persistence (don't restore) | Transcription lost when no text field focused; clipboard restore removes it | Shipped Phase 02 |
| SwiftData over GRDB/raw SQLite | Modern Apple persistence, tight SwiftUI integration, macOS 14+ acceptable | — Pending |
| Companion app with dock presence | Evolve from menu-bar-only to windowed app matching Flow's UX pattern | — Pending |

---
*Last updated: 2026-03-30 after milestone v1.2 start*
