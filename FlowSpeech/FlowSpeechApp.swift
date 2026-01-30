//
//  FlowSpeechApp.swift
//  FlowSpeech
//
//  Created by Amadeus
//  Voice dictation app inspired by Wispr Flow
//

import SwiftUI

@main
struct FlowSpeechApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

// MARK: - App State (Observable)
class AppState: ObservableObject {
    @Published var isRecording = false
    @Published var isTranscribing = false
    @Published var lastTranscription: String?
    @Published var errorMessage: String?
    @Published var audioLevel: Float = 0.0
    @Published var audioLevels: [Float] = Array(repeating: 0.0, count: 30)
    
    // Settings
    @Published var selectedModel: WhisperModel = .whisper1
    @Published var selectedHotkey: HotkeyOption = .fnKey
    @Published var launchAtLogin: Bool = false
    @Published var showInDock: Bool = false
    @Published var autoInsertText: Bool = true
    @Published var language: String = "auto"
    
    init() {
        loadSettings()
    }
    
    func loadSettings() {
        let defaults = UserDefaults.standard
        if let modelRaw = defaults.string(forKey: "selectedModel"),
           let model = WhisperModel(rawValue: modelRaw) {
            selectedModel = model
        }
        if let hotkeyRaw = defaults.string(forKey: "selectedHotkey"),
           let hotkey = HotkeyOption(rawValue: hotkeyRaw) {
            selectedHotkey = hotkey
        }
        launchAtLogin = defaults.bool(forKey: "launchAtLogin")
        showInDock = defaults.bool(forKey: "showInDock")
        autoInsertText = defaults.bool(forKey: "autoInsertText")
        if let lang = defaults.string(forKey: "language") {
            language = lang
        }
    }
    
    func saveSettings() {
        let defaults = UserDefaults.standard
        defaults.set(selectedModel.rawValue, forKey: "selectedModel")
        defaults.set(selectedHotkey.rawValue, forKey: "selectedHotkey")
        defaults.set(launchAtLogin, forKey: "launchAtLogin")
        defaults.set(showInDock, forKey: "showInDock")
        defaults.set(autoInsertText, forKey: "autoInsertText")
        defaults.set(language, forKey: "language")
    }
    
    func updateAudioLevel(_ level: Float) {
        DispatchQueue.main.async {
            self.audioLevel = level
            self.audioLevels.removeFirst()
            self.audioLevels.append(level)
        }
    }
    
    func clearError() {
        errorMessage = nil
    }
}

// MARK: - Whisper Model Options
enum WhisperModel: String, CaseIterable, Identifiable {
    case whisper1 = "whisper-1"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .whisper1: return "Whisper-1"
        }
    }
}

// MARK: - Hotkey Options
enum HotkeyOption: String, CaseIterable, Identifiable {
    case capsLock = "capsLock"
    case optionSpace = "optionSpace"
    case controlSpace = "controlSpace"
    case fnKey = "fnKey"
    case doubleTapCapsLock = "doubleTapCapsLock"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .capsLock: return "Hold Caps Lock"
        case .optionSpace: return "Option + Space"
        case .controlSpace: return "Control + Space"
        case .fnKey: return "Hold Fn Key"
        case .doubleTapCapsLock: return "Double-tap Caps Lock"
        }
    }
    
    var description: String {
        switch self {
        case .capsLock: return "Hold to record, release to transcribe"
        case .optionSpace: return "Press to toggle recording"
        case .controlSpace: return "Press to toggle recording"
        case .fnKey: return "Hold to record, release to transcribe"
        case .doubleTapCapsLock: return "Double-tap to start, tap again to stop"
        }
    }
}

// MARK: - Supported Languages
struct SupportedLanguage: Identifiable, Hashable {
    let code: String
    let name: String
    var id: String { code }
    
    static let all: [SupportedLanguage] = [
        SupportedLanguage(code: "auto", name: "Auto-detect"),
        SupportedLanguage(code: "en", name: "English"),
        SupportedLanguage(code: "de", name: "German"),
        SupportedLanguage(code: "fr", name: "French"),
        SupportedLanguage(code: "es", name: "Spanish"),
        SupportedLanguage(code: "it", name: "Italian"),
        SupportedLanguage(code: "pt", name: "Portuguese"),
        SupportedLanguage(code: "nl", name: "Dutch"),
        SupportedLanguage(code: "pl", name: "Polish"),
        SupportedLanguage(code: "ru", name: "Russian"),
        SupportedLanguage(code: "ja", name: "Japanese"),
        SupportedLanguage(code: "ko", name: "Korean"),
        SupportedLanguage(code: "zh", name: "Chinese"),
        SupportedLanguage(code: "ar", name: "Arabic"),
        SupportedLanguage(code: "hi", name: "Hindi"),
        SupportedLanguage(code: "tr", name: "Turkish"),
        SupportedLanguage(code: "vi", name: "Vietnamese"),
        SupportedLanguage(code: "th", name: "Thai"),
        SupportedLanguage(code: "sv", name: "Swedish"),
        SupportedLanguage(code: "da", name: "Danish"),
        SupportedLanguage(code: "fi", name: "Finnish"),
        SupportedLanguage(code: "no", name: "Norwegian"),
    ]
}
