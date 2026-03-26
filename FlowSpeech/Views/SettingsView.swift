//
//  SettingsView.swift
//  FlowSpeech
//
//  Settings/Preferences window
//

import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    
    @State private var apiKey: String = ""
    @State private var showAPIKey: Bool = false
    @State private var isAPIKeySaved: Bool = false
    @State private var selectedTab: SettingsTab = .general
    
    enum SettingsTab: String, CaseIterable {
        case general = "General"
        case hotkey = "Hotkey"
        case transcription = "Transcription"
        case api = "API"
        case about = "About"
    }
    
    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gear") }
                .tag(SettingsTab.general)
            
            HotkeySettingsTab()
                .tabItem { Label("Hotkey", systemImage: "keyboard") }
                .tag(SettingsTab.hotkey)
            
            TranscriptionSettingsTab()
                .tabItem { Label("Transcription", systemImage: "waveform") }
                .tag(SettingsTab.transcription)
            
            APISettingsTab(apiKey: $apiKey, showAPIKey: $showAPIKey, isAPIKeySaved: $isAPIKeySaved)
                .tabItem { Label("API", systemImage: "key") }
                .tag(SettingsTab.api)
            
            AboutTab()
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(SettingsTab.about)
        }
        .padding(20)
        .frame(width: 500, height: 400)
        .environmentObject(appState)
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
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "star.fill")
                            .foregroundColor(.yellow)
                        Text("GPT-4o Transcribe")
                            .fontWeight(.medium)
                    }
                    Text("Best quality, understands context better, handles accents well.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Divider()
                    
                    HStack {
                        Image(systemName: "bolt.fill")
                            .foregroundColor(.blue)
                        Text("GPT-4o Mini Transcribe")
                            .fontWeight(.medium)
                    }
                    Text("Faster response, good for quick notes. Slightly lower accuracy.")
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
            Image(systemName: "mic.fill")
                .font(.system(size: 60))
                .foregroundStyle(
                    LinearGradient(
                        colors: [DesignSystem.Colors.vibrantBlue, DesignSystem.Colors.teal],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            Text("Flow Speech")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Version 1.0.0")
                .foregroundColor(.secondary)
            
            Text("Effortless voice dictation for macOS")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Divider()
                .padding(.horizontal, 60)
            
            VStack(spacing: 8) {
                Text("Built with ❤️ by Amadeus")
                Text("Inspired by Wispr Flow")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            HStack(spacing: 20) {
                Link("GitHub", destination: URL(string: "https://github.com")!)
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
}
