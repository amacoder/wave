//
//  AppDelegate.swift
//  FlowSpeech
//
//  Menu bar app setup and global hotkey handling
//

import SwiftUI
import AppKit
import Carbon.HIToolbox
import Combine

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var recordingWindow: NSWindow?
    var settingsWindow: NSWindow?
    
    let appState = AppState()
    let hotkeyManager = HotkeyManager()
    let audioRecorder = AudioRecorder()
    let whisperService = WhisperService()
    let textInserter = TextInserter()
    let exclusionService = AppExclusionService()
    
    private var eventMonitor: Any?
    private var flagsMonitor: Any?
    private var cancellables = Set<AnyCancellable>()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        setupHotkeys()
        setupAudioRecorder()
        
        // Check for required permissions
        checkPermissions()

        // Observe hotkey tap health
        hotkeyManager.$isTapHealthy
            .receive(on: DispatchQueue.main)
            .sink { [weak self] healthy in
                self?.updateMenuBarIconForHealth(healthy: healthy)
            }
            .store(in: &cancellables)

        // Show onboarding if first launch
        if !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
            showOnboarding()
        }
    }
    
    // MARK: - Menu Bar Setup
    
    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Flow Speech")
        }
        
        // Build simple menu
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Start Recording", action: #selector(toggleRecording), keyEquivalent: "r"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Flow Speech", action: #selector(quitApp), keyEquivalent: "q"))
        
        statusItem.menu = menu
    }
    
    // MARK: - Hotkey Setup
    
    private func setupHotkeys() {
        // Monitor for Caps Lock (flags changed events)
        flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
        }
        
        // Also monitor local events for when app is focused
        NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event
        }
        
        // Monitor for modifier key combinations
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyDown(event)
        }
    }
    
    private var modifierKeyDown = false
    
    private func handleFlagsChanged(_ event: NSEvent) {
        let flags = event.modifierFlags
        
        // Check which modifier to use based on selected hotkey
        let keyPressed: Bool
        switch appState.selectedHotkey {
        case .fnKey:
            keyPressed = flags.contains(.function)
        case .optionSpace, .capsLock:
            keyPressed = flags.contains(.option)
        case .controlSpace:
            keyPressed = flags.contains(.control)
        case .doubleTapCapsLock:
            keyPressed = flags.contains(.capsLock)
        }
        
        // Handle hold-to-record
        if keyPressed && !modifierKeyDown {
            modifierKeyDown = true
            print("Hotkey pressed - starting recording")
            startRecording()
        } else if !keyPressed && modifierKeyDown {
            modifierKeyDown = false
            print("Hotkey released - stopping recording")
            stopRecordingAndTranscribe()
        }
    }
    
    private func handleKeyDown(_ event: NSEvent) {
        // Escape to cancel recording
        if event.keyCode == 53 && appState.phase == .recording {
            cancelRecording()
        }
    }
    
    // MARK: - Audio Recording Setup
    
    private func setupAudioRecorder() {
        audioRecorder.onAudioLevel = { [weak self] level in
            self?.appState.updateAudioLevel(level)
        }
    }
    
    // MARK: - Recording Actions
    
    @objc func toggleRecording() {
        if appState.phase == .recording {
            stopRecordingAndTranscribe()
        } else {
            startRecording()
        }
    }
    
    func startRecording() {
        guard appState.phase != .recording else { return }
        guard !exclusionService.shouldSuppressHotkey() else {
            // Silently suppress — no sound, no overlay
            return
        }

        appState.phase = .recording
        appState.errorMessage = nil
        appState.audioLevels = Array(repeating: 0.0, count: 30)

        // Update menu bar icon
        updateMenuBarIcon()
        
        // Show recording overlay
        showRecordingOverlay()
        
        // Start audio recording
        audioRecorder.startRecording()
        
        // Play start sound (subtle)
        NSSound(named: "Tink")?.play()
    }
    
    func stopRecordingAndTranscribe() {
        guard appState.phase == .recording else { return }

        appState.phase = .transcribing

        // Stop audio recording
        guard let audioURL = audioRecorder.stopRecording() else {
            appState.errorMessage = "Failed to save recording"
            appState.phase = .idle
            hideRecordingOverlay()
            updateMenuBarIcon()
            return
        }

        // Update UI
        updateMenuBarIcon()
        
        // Transcribe
        Task {
            await transcribe(audioURL: audioURL)
        }
    }
    
    func cancelRecording() {
        appState.phase = .idle
        audioRecorder.cancelRecording()
        hideRecordingOverlay()
        updateMenuBarIcon()
        
        // Play cancel sound
        NSSound(named: "Basso")?.play()
    }
    
    // MARK: - Transcription
    
    private func transcribe(audioURL: URL) async {
        print("Starting transcription for: \(audioURL.path)")
        
        do {
            // Get API key from Keychain
            guard let apiKey = KeychainManager.shared.getAPIKey() else {
                print("ERROR: No API key found in keychain")
                await MainActor.run {
                    appState.errorMessage = "No API key configured. Please add your OpenAI API key in Settings."
                    appState.phase = .idle
                    hideRecordingOverlay()
                }
                return
            }
            
            print("API key found, calling Whisper API with model: \(appState.selectedModel.rawValue)")
            
            // Transcribe using Whisper API
            let transcription = try await whisperService.transcribe(
                audioURL: audioURL,
                apiKey: apiKey,
                model: appState.selectedModel,
                language: appState.language == "auto" ? nil : appState.language
            )
            
            print("Transcription successful: \(transcription)")
            
            await MainActor.run {
                print("MainActor block running, autoInsertText: \(appState.autoInsertText)")
                appState.lastTranscription = transcription
                appState.phase = .done

                // Show done flash for 0.8s, then hide overlay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                    self?.hideRecordingOverlay()
                }

                // Return to idle after 1.5s (unchanged timing)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                    if self?.appState.phase == .done {
                        self?.appState.phase = .idle
                    }
                }

                // Insert text at cursor (with small delay to let modifier keys settle)
                if appState.autoInsertText {
                    print("Inserting text at cursor (after delay)...")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [self] in
                        textInserter.insertText(transcription)
                        print("Text insertion completed")
                        // Play success sound
                        NSSound(named: "Glass")?.play()
                    }
                } else {
                    print("autoInsertText is OFF, skipping insertion")
                    NSSound(named: "Glass")?.play()
                }
            }
            
            // Clean up audio file
            try? FileManager.default.removeItem(at: audioURL)
            
        } catch {
            print("Transcription ERROR: \(error.localizedDescription)")
            await MainActor.run {
                appState.errorMessage = "Transcription failed: \(error.localizedDescription)"
                appState.phase = .idle
                hideRecordingOverlay()

                // Play error sound
                NSSound(named: "Basso")?.play()
            }
        }
    }
    
    // MARK: - Recording Overlay
    
    private func showRecordingOverlay() {
        if recordingWindow == nil {
            let contentView = RecordingOverlayView()
                .environmentObject(appState)

            recordingWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 280, height: 52),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            recordingWindow?.contentView = NSHostingView(rootView: contentView)
            recordingWindow?.backgroundColor = .clear
            recordingWindow?.isOpaque = false
            recordingWindow?.level = .floating
            recordingWindow?.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            recordingWindow?.hasShadow = true
        }

        // Position pill at bottom-center on every show (fixes window resize not triggered)
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let pillWidth: CGFloat = 280
            let pillHeight: CGFloat = 52
            let x = screenFrame.midX - pillWidth / 2
            let y = screenFrame.minY + 32  // 32pt above the Dock
            recordingWindow?.setFrame(
                NSRect(x: x, y: y, width: pillWidth, height: pillHeight),
                display: true
            )
        }

        recordingWindow?.ignoresMouseEvents = true // Don't steal focus
        recordingWindow?.orderFront(nil)
    }
    
    private func hideRecordingOverlay() {
        recordingWindow?.orderOut(nil)
    }
    
    // MARK: - Menu Bar Icon
    
    private func updateMenuBarIcon() {
        DispatchQueue.main.async {
            guard let button = self.statusItem.button else { return }
            switch self.appState.phase {
            case .idle, .done:
                button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Flow Speech")
                button.contentTintColor = nil
            case .recording:
                button.image = NSImage(systemSymbolName: "mic.badge.plus", accessibilityDescription: "Recording")
                button.contentTintColor = .systemRed
            case .transcribing:
                button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Transcribing")
                button.contentTintColor = .systemBlue
            }
        }
    }
    
    // MARK: - Health-based icon

    private var lastKnownHealthy: Bool = true

    private func updateMenuBarIconForHealth(healthy: Bool) {
        lastKnownHealthy = healthy
        if !healthy {
            if let button = statusItem.button {
                button.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Hotkey Unavailable")
                button.contentTintColor = .systemYellow
            }
        } else {
            updateMenuBarIcon()
        }
    }

    // MARK: - Settings

    @objc func openSettings() {
        if settingsWindow == nil {
            let settingsView = SettingsView()
                .environmentObject(appState)
                .environmentObject(exclusionService)
            
            settingsWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 500, height: 450),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            settingsWindow?.title = "Flow Speech Settings"
            settingsWindow?.contentView = NSHostingView(rootView: settingsView)
            settingsWindow?.center()
        }
        
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    // MARK: - Onboarding
    
    private func showOnboarding() {
        let onboardingView = OnboardingView {
            UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        }
        .environmentObject(appState)
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 600),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Flow Speech"
        window.contentView = NSHostingView(rootView: onboardingView)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    // MARK: - Permissions
    
    private func checkPermissions() {
        // Check microphone permission
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
        case .denied, .restricted:
            DispatchQueue.main.async {
                self.appState.errorMessage = "Microphone access is required. Please enable it in System Settings > Privacy & Security > Microphone."
            }
        default:
            break
        }
        
        // Check accessibility permission
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let accessibilityEnabled = AXIsProcessTrustedWithOptions(options)
        
        if !accessibilityEnabled {
            DispatchQueue.main.async {
                self.appState.errorMessage = "Accessibility access is required for text insertion. Please enable it in System Settings > Privacy & Security > Accessibility."
            }
        }
    }
    
    // MARK: - Quit
    
    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}

// Import for microphone permission check
import AVFoundation
