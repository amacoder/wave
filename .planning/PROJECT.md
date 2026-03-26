# SpeechFlow

## What This Is

A macOS menu bar speech-to-text app that lets you hold a hotkey (Fn by default), speak, and have your words transcribed via OpenAI Whisper and automatically pasted into whatever text field is focused. Built with SwiftUI, targeting macOS with a minimal, non-intrusive overlay UI.

## Core Value

Hold a key, speak, and have accurate text appear where you need it — zero friction dictation that stays out of your way.

## Current Milestone: v1.1 UI Revamp & Polish

**Goal:** Redesign the UI with a polished, Wispr Flow-inspired blue aesthetic, fix UX bugs, and add smart app exclusion and clipboard resilience.

**Target features:**
- UI overhaul with blue color palette (Wispr Flow "Flow Bar" inspired)
- Recording overlay redesign with smooth animations
- Game/fullscreen app exclusion (suppress hotkey in games)
- Clipboard persistence (transcription always available via Cmd+V)
- Animation polish across all state transitions

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

- [ ] Redesign overlay and views with Wispr Flow-inspired blue palette
- [ ] Fix buggy recording overlay appearance when holding Fn
- [ ] Suppress hotkey activation when games/fullscreen apps are in focus
- [ ] Keep transcription on clipboard after paste (clipboard persistence)
- [x] Smooth state transition animations (idle -> recording -> transcribing -> done) — Validated in Phase 01

### Out of Scope

- On-device transcription (Whisper API is sufficient for now) — complexity too high
- Notch integration — not all Macs have notch, defer to future
- Multiple language auto-detection — single language hint is enough for v1.1

## Context

- SwiftUI macOS app, 11 Swift source files
- Architecture: AppDelegate orchestrates services (AudioRecorder, WhisperService, TextInserter, HotkeyManager, KeychainManager)
- State: centralized AppState with RecordingPhase enum (idle/recording/transcribing/done)
- Design system: DesignSystem.swift with blue palette tokens (deepNavy, vibrantBlue, softBlueWhite, teal)
- CGEventTap health monitoring with auto-recovery in HotkeyManager
- Overlay: floating borderless window with .ultraThinMaterial
- Text insertion: clipboard + CGEvent Cmd+V with 0.5s clipboard restore
- Hotkey detection: dual approach (NSEvent flagsChanged + CGEventTap backup)
- No app exclusion logic exists currently
- Reference design: Wispr Flow's "Flow Bar" — small pill overlay, soft neutrals, editorial aesthetic
- Target palette: deep navy background, vibrant blue accent, soft blue-white highlights

## Constraints

- **Platform**: macOS only (SwiftUI)
- **Permissions**: Requires Microphone, Accessibility, and Input Monitoring
- **API**: OpenAI Whisper API (requires user's API key)
- **Design reference**: Wispr Flow aesthetic adapted to blue palette

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Blue palette over black/beige | User preference; blue is universally appealing and distinct from Wispr Flow | — Pending |
| Wispr Flow as design reference | Best-in-class UX for push-to-talk dictation apps | — Pending |
| Game exclusion via app detection | User plays League of Legends; accidental Fn triggers during gaming | — Pending |
| Clipboard persistence (don't restore) | Transcription lost when no text field focused; clipboard restore removes it | — Pending |

---
*Last updated: 2026-03-26 after Phase 01 (Foundation) completion*
