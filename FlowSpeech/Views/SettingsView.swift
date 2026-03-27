//
//  SettingsView.swift
//  Wave
//
//  Settings window with sidebar navigation (Stash-style)
//

import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var exclusionService: AppExclusionService

    @State private var apiKey: String = ""
    @State private var showAPIKey: Bool = false
    @State private var isAPIKeySaved: Bool = false
    @State private var selectedTab: SettingsTab = .general

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

    var body: some View {
        HStack(spacing: 0) {
            // Fixed sidebar
            VStack(spacing: 0) {
                // App icon header
                VStack(spacing: 6) {
                    Image("WaveOverlayIcon")
                        .resizable()
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    Text("Wave")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                }
                .padding(.top, 20)
                .padding(.bottom, 16)

                // Tab list
                VStack(spacing: 2) {
                    ForEach(SettingsTab.allCases) { tab in
                        HStack(spacing: 8) {
                            Image(systemName: tab.icon)
                                .frame(width: 20)
                                .foregroundColor(selectedTab == tab ? .white : .primary)
                            Text(tab.rawValue)
                                .foregroundColor(selectedTab == tab ? .white : .primary)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selectedTab == tab ? Color.accentColor : Color.clear)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { selectedTab = tab }
                    }
                }
                .padding(.horizontal, 8)

                Spacer()
            }
            .frame(width: 170)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Content
            Group {
                switch selectedTab {
                case .general:
                    GeneralSettingsTab()
                case .hotkey:
                    HotkeySettingsTab()
                case .transcription:
                    TranscriptionSettingsTab()
                case .api:
                    APISettingsTab(apiKey: $apiKey, showAPIKey: $showAPIKey, isAPIKeySaved: $isAPIKeySaved)
                case .exclusion:
                    ExclusionSettingsTab()
                case .about:
                    AboutTab()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 680, height: 560)
        .environmentObject(appState)
        .environmentObject(exclusionService)
        .onAppear {
            isAPIKeySaved = KeychainManager.shared.hasAPIKey()
        }
    }
}

// MARK: - General Settings Tab

struct GeneralSettingsTab: View {
    @EnvironmentObject var appState: AppState
    @State private var launchAtLogin: Bool = false

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
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Granted")
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("Permissions")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            launchAtLogin = appState.launchAtLogin
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
                print("Failed to set launch at login: \(error)")
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
                Picker("Model", selection: $appState.selectedModel) {
                    ForEach(WhisperModel.allCases) { model in
                        Text(model.displayName).tag(model)
                    }
                }
                .onChange(of: appState.selectedModel) { _, _ in
                    appState.saveSettings()
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
                Text("Uses GPT-4o-mini to remove filler words (um, uh, like, you know), fix grammar, and clean up punctuation while preserving your original meaning.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

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
        .formStyle(.grouped)
    }
}

// MARK: - API Settings Tab

struct APISettingsTab: View {
    @Binding var apiKey: String
    @Binding var showAPIKey: Bool
    @Binding var isAPIKeySaved: Bool

    @State private var saveStatus: String?

    var body: some View {
        Form {
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
                            Text(status)
                                .font(.caption)
                                .foregroundColor(status.contains("✓") ? .green : .red)
                        }
                    }

                    if isAPIKeySaved {
                        Label("API key is saved securely in Keychain", systemImage: "lock.shield.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
            } header: {
                Text("OpenAI API Key")
            } footer: {
                Link("Get an API key from OpenAI →",
                     destination: URL(string: "https://platform.openai.com/api-keys")!)
                    .font(.caption)
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your API key is stored securely in the macOS Keychain and is never transmitted anywhere except to OpenAI's servers for transcription.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("Security")
            }
        }
        .formStyle(.grouped)
    }

    private func saveAPIKey() {
        if KeychainManager.shared.saveAPIKey(apiKey) {
            saveStatus = "✓ Saved"
            isAPIKeySaved = true
            apiKey = ""

            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                saveStatus = nil
            }
        } else {
            saveStatus = "✗ Failed to save"
        }
    }

    private func deleteAPIKey() {
        if KeychainManager.shared.deleteAPIKey() {
            isAPIKeySaved = false
            saveStatus = "Deleted"

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

            Text("Version 1.1.0")
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


#Preview {
    SettingsView()
        .environmentObject(AppState())
        .environmentObject(AppExclusionService())
}
