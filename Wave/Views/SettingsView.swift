//
//  SettingsView.swift
//  Wave
//
//  Settings window with sidebar navigation (Stash-style)
//

import SwiftUI
import ServiceManagement
import AVFoundation

enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "General"
    case hotkey = "Hotkey"
    case transcription = "Transcription"
    case api = "API"
    case exclusion = "Exclusion"
    case about = "About"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: return "gear"
        case .hotkey: return "keyboard"
        case .transcription: return "waveform"
        case .api: return "key"
        case .exclusion: return "hand.raised"
        case .about: return "info.circle"
        }
    }
}

// MARK: - General Settings Tab

struct GeneralSettingsTab: View {
    @EnvironmentObject var appState: AppState
    @State private var launchAtLogin: Bool = false
    @State private var micStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .audio)

    var body: some View {
        Form {
            Section {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        setLaunchAtLogin(newValue)
                        appState.launchAtLogin = newValue
                        appState.saveSettings()
                    }

                Toggle("Auto-insert transcribed text", isOn: $appState.autoInsertText)
                    .onChange(of: appState.autoInsertText) { _, _ in
                        appState.saveSettings()
                    }

                Toggle("Sound effects", isOn: $appState.soundFeedback)
                    .onChange(of: appState.soundFeedback) { _, _ in
                        appState.saveSettings()
                    }
            } header: {
                Text("Startup")
            }

            Section {
                HStack {
                    Text("Accessibility Permission")
                    Spacer()
                    if TextInserter.hasAccessibilityPermission {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Granted")
                            .foregroundColor(.secondary)
                    } else {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                        Button("Grant Access") {
                            TextInserter.requestAccessibilityPermission()
                        }
                    }
                }

                HStack {
                    Text("Microphone Permission")
                    Spacer()
                    switch micStatus {
                    case .authorized:
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Granted")
                            .foregroundColor(.secondary)
                    case .notDetermined:
                        Button("Request Access") {
                            AVCaptureDevice.requestAccess(for: .audio) { _ in
                                DispatchQueue.main.async {
                                    micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
                                }
                            }
                        }
                    default:
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                        Button("Open System Settings") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                }
            } header: {
                Text("Permissions")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            launchAtLogin = appState.launchAtLogin
            micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                #if DEBUG
                print("Failed to set launch at login: \(error)")
                #endif
            }
        }
    }
}

// MARK: - Hotkey Settings Tab

struct HotkeySettingsTab: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Form {
            Section {
                Picker("Activation Method", selection: $appState.selectedHotkey) {
                    ForEach(HotkeyOption.allCases) { option in
                        VStack(alignment: .leading) {
                            Text(option.displayName)
                            Text(option.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .tag(option)
                    }
                }
                .pickerStyle(.radioGroup)
                .onChange(of: appState.selectedHotkey) { _, _ in
                    appState.saveSettings()
                }
            } header: {
                Text("Hotkey")
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label {
                        Text("Caps Lock users: Consider remapping Caps Lock to do nothing in System Settings → Keyboard → Modifier Keys, so it doesn't toggle caps while recording.")
                    } icon: {
                        Image(systemName: "lightbulb")
                            .foregroundColor(.yellow)
                    }
                    .font(.callout)
                    .padding(.vertical, 4)
                }
            } header: {
                Text("Tips")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Transcription Settings Tab

struct TranscriptionSettingsTab: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Form {
            Section {
                Picker("Provider", selection: $appState.transcriptionProvider) {
                    ForEach(TranscriptionProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: appState.transcriptionProvider) { _, _ in
                    appState.saveSettings()
                }

                if appState.transcriptionProvider == .openai {
                    Picker("Model", selection: $appState.selectedModel) {
                        ForEach(WhisperModel.allCases) { model in
                            Text(model.displayName).tag(model)
                        }
                    }
                    .onChange(of: appState.selectedModel) { _, _ in
                        appState.saveSettings()
                    }
                } else {
                    LabeledContent("Model", value: "Whisper Large v3 Turbo")
                }

                Picker("Language", selection: $appState.language) {
                    ForEach(SupportedLanguage.all) { lang in
                        Text(lang.name).tag(lang.code)
                    }
                }
                .onChange(of: appState.language) { _, _ in
                    appState.saveSettings()
                }
            } header: {
                Text("Transcription")
            }

            Section {
                Toggle("Smart Cleanup", isOn: $appState.smartCleanup)
                    .onChange(of: appState.smartCleanup) { _, _ in
                        appState.saveSettings()
                    }
            } header: {
                Text("Post-Processing")
            } footer: {
                Text("Removes filler sounds (um, uh, äh) and fixes punctuation without rewriting your words. Skipped automatically for short dictations to keep them instant.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if appState.transcriptionProvider == .openai {
                modelComparisonSection
            }
        }
        .formStyle(.grouped)
    }

    private var modelComparisonSection: some View {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "star.fill")
                            .foregroundColor(.yellow)
                        Text("GPT-4o Transcribe")
                            .fontWeight(.medium)
                        Text("Recommended")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.yellow.opacity(0.2))
                            .clipShape(Capsule())
                    }
                    Text("Best quality. Understands context, handles accents, proper punctuation.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Divider()

                    HStack {
                        Image(systemName: "bolt.fill")
                            .foregroundColor(.orange)
                        Text("GPT-4o Mini Transcribe")
                            .fontWeight(.medium)
                    }
                    Text("Faster and cheaper. Good for quick notes and simple dictation.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Divider()

                    HStack {
                        Image(systemName: "clock.fill")
                            .foregroundColor(.secondary)
                        Text("Whisper-1 (Legacy)")
                            .fontWeight(.medium)
                    }
                    Text("Original model. Basic transcription without context understanding.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            } header: {
                Text("Model Comparison")
            }
    }
}

// MARK: - API Settings Tab

struct APISettingsTab: View {
    @EnvironmentObject var appState: AppState
    @Binding var apiKey: String
    @Binding var showAPIKey: Bool
    @Binding var isAPIKeySaved: Bool

    enum SaveStatus {
        case saved
        case deleted
        case failed(String)
    }

    @State private var saveStatus: SaveStatus?

    @State private var groqKey: String = ""
    @State private var showGroqKey: Bool = false
    @State private var isGroqKeySaved: Bool = false
    @State private var groqSaveStatus: SaveStatus?

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        if showGroqKey {
                            TextField("gsk_...", text: $groqKey)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                        } else {
                            SecureField("gsk_...", text: $groqKey)
                                .textFieldStyle(.roundedBorder)
                        }

                        Button(action: { showGroqKey.toggle() }) {
                            Image(systemName: showGroqKey ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)
                    }

                    HStack {
                        Button("Save API Key") {
                            saveGroqKey()
                        }
                        .disabled(groqKey.isEmpty)

                        if isGroqKeySaved {
                            Button("Delete Key", role: .destructive) {
                                deleteGroqKey()
                            }
                        }

                        Spacer()

                        if let status = groqSaveStatus {
                            statusLabel(status)
                        }
                    }

                    if isGroqKeySaved {
                        Label("API key is saved securely in Keychain", systemImage: "lock.shield.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
            } header: {
                sectionHeader("Groq API Key", isActive: appState.transcriptionProvider == .groq)
            } footer: {
                Link("Get a free API key from Groq →",
                     destination: URL(string: "https://console.groq.com/keys")!)
                    .font(.caption)
            }

            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        if showAPIKey {
                            TextField("sk-...", text: $apiKey)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                        } else {
                            SecureField("sk-...", text: $apiKey)
                                .textFieldStyle(.roundedBorder)
                        }

                        Button(action: { showAPIKey.toggle() }) {
                            Image(systemName: showAPIKey ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)
                    }

                    HStack {
                        Button("Save API Key") {
                            saveAPIKey()
                        }
                        .disabled(apiKey.isEmpty)

                        if isAPIKeySaved {
                            Button("Delete Key", role: .destructive) {
                                deleteAPIKey()
                            }
                        }

                        Spacer()

                        if let status = saveStatus {
                            statusLabel(status)
                        }
                    }

                    if isAPIKeySaved {
                        Label("API key is saved securely in Keychain", systemImage: "lock.shield.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
            } header: {
                sectionHeader("OpenAI API Key", isActive: appState.transcriptionProvider == .openai)
            } footer: {
                Link("Get an API key from OpenAI →",
                     destination: URL(string: "https://platform.openai.com/api-keys")!)
                    .font(.caption)
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your API keys are stored securely in the macOS Keychain and are only transmitted to the selected provider (Groq or OpenAI) for transcription.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("Security")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            isGroqKeySaved = KeychainManager.shared.hasGroqAPIKey()
        }
    }

    // MARK: - Shared UI

    @ViewBuilder
    private func statusLabel(_ status: SaveStatus) -> some View {
        switch status {
        case .saved:
            Label("Saved", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundColor(.green)
        case .deleted:
            Label("Deleted", systemImage: "trash")
                .font(.caption)
                .foregroundColor(.secondary)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.circle.fill")
                .font(.caption)
                .foregroundColor(.red)
        }
    }

    private func sectionHeader(_ title: String, isActive: Bool) -> some View {
        HStack(spacing: 6) {
            Text(title)
            if isActive {
                Text("Active")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(DesignSystem.Colors.accent.opacity(0.25))
                    .clipShape(Capsule())
            }
        }
    }

    // MARK: - Actions

    private func saveGroqKey() {
        let trimmed = groqKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("gsk_"), trimmed.count >= 20 else {
            groqSaveStatus = .failed("Invalid key format (must start with gsk_)")
            return
        }

        if KeychainManager.shared.saveGroqAPIKey(trimmed) {
            groqSaveStatus = .saved
            isGroqKeySaved = true
            groqKey = ""

            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                groqSaveStatus = nil
            }
        } else {
            groqSaveStatus = .failed("Failed to save")
        }
    }

    private func deleteGroqKey() {
        if KeychainManager.shared.deleteGroqAPIKey() {
            isGroqKeySaved = false
            groqSaveStatus = .deleted

            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                groqSaveStatus = nil
            }
        }
    }

    private func saveAPIKey() {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("sk-"), trimmed.count >= 20 else {
            saveStatus = .failed("Invalid key format (must start with sk-)")
            return
        }

        if KeychainManager.shared.saveAPIKey(trimmed) {
            saveStatus = .saved
            isAPIKeySaved = true
            apiKey = ""

            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                saveStatus = nil
            }
        } else {
            saveStatus = .failed("Failed to save")
        }
    }

    private func deleteAPIKey() {
        if KeychainManager.shared.deleteAPIKey() {
            isAPIKeySaved = false
            saveStatus = .deleted

            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                saveStatus = nil
            }
        }
    }
}

// MARK: - About Tab

struct AboutTab: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image("AppIcon")
                .resizable()
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 18))

            Text("Wave")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")")
                .foregroundColor(.secondary)

            Text("Effortless voice dictation for macOS")
                .font(.headline)
                .foregroundColor(.secondary)

            Divider()
                .padding(.horizontal, 60)

            VStack(spacing: 8) {
                Text("Built with ❤️ by Amadeus")
                Text("Press one key. Start talking.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 20) {
                Link("GitHub", destination: URL(string: "https://github.com/maewa-space/wave")!)
                Link("OpenAI", destination: URL(string: "https://openai.com")!)
            }
            .font(.caption)

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
