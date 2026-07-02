//
//  OnboardingView.swift
//  Wave
//
//  First-run setup wizard
//

import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @State private var currentStep = 0
    
    let onComplete: () -> Void
    
    private let steps = [
        OnboardingStep(
            icon: "mic.fill",
            title: "Welcome to Wave",
            description: "Effortless voice dictation for macOS. Speak naturally and let AI convert your voice to polished text.",
            action: nil
        ),
        OnboardingStep(
            icon: "key.fill",
            title: "Connect a Transcription Provider",
            description: "Wave transcribes your voice in the cloud. Groq is fast and has a free tier; OpenAI works too.",
            action: .apiKey
        ),
        OnboardingStep(
            icon: "keyboard",
            title: "Choose Your Hotkey",
            description: "Select how you want to activate voice recording. Hold the key to record, release to transcribe.",
            action: .hotkey
        ),
        OnboardingStep(
            icon: "hand.raised.fill",
            title: "Grant Permissions",
            description: "Wave needs access to your microphone and accessibility features to insert text.",
            action: .permissions
        ),
        OnboardingStep(
            icon: "checkmark.circle.fill",
            title: "You're All Set!",
            description: "Hold your hotkey to record, release to transcribe. Click the menu bar icon and select \"Open Wave\" to manage your history and settings.",
            action: nil
        )
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Progress indicator
            HStack(spacing: 8) {
                ForEach(0..<steps.count, id: \.self) { index in
                    Circle()
                        .fill(index <= currentStep ? DesignSystem.Colors.accent : Color.gray.opacity(0.3))
                        .frame(width: 8, height: 8)
                        .animation(.easeInOut, value: currentStep)
                }
            }
            .padding(.top, 20)
            
            Spacer()
            
            // Step content
            let step = steps[currentStep]
            
            VStack(spacing: 24) {
                Image(systemName: step.icon)
                    .font(.system(size: 64))
                    .foregroundStyle(DesignSystem.Colors.accentGradient)
                    .transition(.scale.combined(with: .opacity))
                
                Text(step.title)
                    .font(.title)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                
                Text(step.description)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                
                // Step-specific content
                if let action = step.action {
                    stepActionView(action)
                        .padding(.top, 10)
                }
            }
            .animation(.easeInOut, value: currentStep)
            
            Spacer()
            
            // Navigation buttons
            HStack {
                if currentStep > 0 {
                    Button("Back") {
                        withAnimation {
                            currentStep -= 1
                        }
                    }
                    .buttonStyle(.bordered)
                }
                
                Spacer()
                
                if currentStep < steps.count - 1 {
                    Button("Continue") {
                        withAnimation {
                            currentStep += 1
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DesignSystem.Colors.accent)
                } else {
                    Button("Get Started") {
                        onComplete()
                        // Close the window
                        NSApplication.shared.keyWindow?.close()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DesignSystem.Colors.accentDeep)
                }
            }
            .padding(30)
        }
        .frame(width: 500, height: 550)
    }
    
    @ViewBuilder
    private func stepActionView(_ action: OnboardingAction) -> some View {
        switch action {
        case .apiKey:
            APIKeySetupView()
            
        case .hotkey:
            HotkeySetupView()
            
        case .permissions:
            PermissionsSetupView()
        }
    }
}

// MARK: - Onboarding Models

struct OnboardingStep {
    let icon: String
    let title: String
    let description: String
    let action: OnboardingAction?
}

enum OnboardingAction {
    case apiKey
    case hotkey
    case permissions
}

// MARK: - API Key Setup

struct APIKeySetupView: View {
    @EnvironmentObject var appState: AppState
    @State private var provider: TranscriptionProvider = .groq
    @State private var apiKey = ""
    @State private var isSaved = false
    @State private var validationError: String?

    private var keyPrefix: String { provider == .groq ? "gsk_" : "sk-" }

    var body: some View {
        VStack(spacing: 12) {
            Picker("", selection: $provider) {
                ForEach(TranscriptionProvider.allCases) { p in
                    Text(p.displayName).tag(p)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 300)
            .onChange(of: provider) { _, _ in
                isSaved = false
                validationError = nil
            }

            HStack {
                SecureField("\(keyPrefix)...", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 300)

                Button(isSaved ? "Saved" : "Save") {
                    saveKey()
                }
                .disabled(apiKey.isEmpty || isSaved)
                .buttonStyle(.bordered)
            }

            if let validationError {
                Label(validationError, systemImage: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.red)
            } else if isSaved {
                Label("Saved securely in Keychain", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.green)
            } else {
                Text("You can also add a key later in Settings → API.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Link(provider == .groq ? "Get a free API key from Groq →" : "Get an API key from OpenAI →",
                 destination: URL(string: provider == .groq
                    ? "https://console.groq.com/keys"
                    : "https://platform.openai.com/api-keys")!)
                .font(.caption)
        }
    }

    private func saveKey() {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(keyPrefix), trimmed.count >= 20 else {
            validationError = "Invalid key format (must start with \(keyPrefix))"
            return
        }
        let ok = provider == .groq
            ? KeychainManager.shared.saveGroqAPIKey(trimmed)
            : KeychainManager.shared.saveAPIKey(trimmed)
        if ok {
            isSaved = true
            validationError = nil
            apiKey = ""
            // Use the provider the user just set up
            appState.transcriptionProvider = provider
            appState.saveSettings()
        } else {
            validationError = "Could not save to Keychain"
        }
    }
}

// MARK: - Hotkey Setup

struct HotkeySetupView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(spacing: 8) {
            ForEach(HotkeyOption.allCases) { option in
                HotkeyOptionButton(
                    option: option,
                    isSelected: appState.selectedHotkey == option
                ) {
                    appState.selectedHotkey = option
                    appState.saveSettings()
                }
            }
        }
    }
}

struct HotkeyOptionButton: View {
    let option: HotkeyOption
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.displayName)
                        .fontWeight(isSelected ? .semibold : .regular)
                    Text(option.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(DesignSystem.Colors.accent)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(width: 320)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? DesignSystem.Colors.accent.opacity(0.1) : Color.gray.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? DesignSystem.Colors.accent : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Permissions Setup

struct PermissionsSetupView: View {
    @State private var hasAccessibility = TextInserter.hasAccessibilityPermission
    @State private var hasMicrophone = true // Assume granted after request
    
    var body: some View {
        VStack(spacing: 16) {
            PermissionRow(
                icon: "mic.fill",
                title: "Microphone",
                description: "Required for voice recording",
                isGranted: hasMicrophone
            ) {
                // Request microphone access
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    DispatchQueue.main.async {
                        hasMicrophone = granted
                    }
                }
            }
            
            PermissionRow(
                icon: "hand.raised.fill",
                title: "Accessibility",
                description: "Required to insert text at cursor",
                isGranted: hasAccessibility
            ) {
                TextInserter.requestAccessibilityPermission()
                // Check again after a short delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    hasAccessibility = TextInserter.hasAccessibilityPermission
                }
            }
        }
        .onAppear {
            hasAccessibility = TextInserter.hasAccessibilityPermission
        }
    }
}

struct PermissionRow: View {
    let icon: String
    let title: String
    let description: String
    let isGranted: Bool
    let onRequest: () -> Void
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(isGranted ? .green : .orange)
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if isGranted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            } else {
                Button("Grant") {
                    onRequest()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(width: 380)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.gray.opacity(0.1))
        )
    }
}

import AVFoundation

#Preview {
    OnboardingView(onComplete: {})
        .environmentObject(AppState())
}
