//
//  AppDelegate.swift
//  FlowSpeech
//
//  Menu bar app setup and global hotkey handling
//

import SwiftUI
import AppKit
import Carbon.HIToolbox

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var recordingWindow: NSWindow?
    var settingsWindow: NSWindow?
    
    let appState = AppState()
    let hotkeyManager = HotkeyManager()
    let audioRecorder = AudioRecorder()
    let whisperService = WhisperService()
    let textInserter = TextInserter()
    
    private var eventMonitor: Any?
    private var flagsMonitor: Any?
    private var capsLockPressed = false
    private var lastCapsLockTime: Date?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        setupHotkeys()
        setupAudioRecorder()
        
        // Check for required permissions
        checkPermissions()
        
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
    
    private func handleFlagsChanged(_ event: NSEvent) {
        let capsLockOn = event.modifierFlags.contains(.capsLock)
        
        switch appState.selectedHotkey {
        case .capsLock:
            // Hold to record mode
            if capsLockOn && !capsLockPressed {
                capsLockPressed = true
                startRecording()
            } else if !capsLockOn && capsLockPressed {
                capsLockPressed = false
                stopRecordingAndTranscribe()
            }
            
        case .doubleTapCapsLock:
            // Double-tap mode
            if capsLockOn {
                let now = Date()
                if let lastTime = lastCapsLockTime,
                   now.timeIntervalSince(lastTime) < 0.4 {
                    // Double tap detected
                    if appState.isRecording {
                        stopRecordingAndTranscribe()
                    } else {
                        startRecording()
                    }
                    lastCapsLockTime = nil
                } else {
                    lastCapsLockTime = now
                }
            }
            
        default:
            break
        }
    }
    
    private func handleKeyDown(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        
        switch appState.selectedHotkey {
        case .optionSpace:
            if flags.contains(.option) && event.keyCode == 49 { // Space key
                toggleRecording()
            }
            
        case .controlSpace:
            if flags.contains(.control) && event.keyCode == 49 { // Space key
                toggleRecording()
            }
            
        default:
            break
        }
        
        // Escape to cancel recording
        if event.keyCode == 53 && appState.isRecording { // Escape key
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
        if appState.isRecording {
            stopRecordingAndTranscribe()
        } else {
            startRecording()
        }
    }
    
    func startRecording() {
        guard !appState.isRecording else { return }
        
        appState.isRecording = true
        appState.errorMessage = nil
        appState.audioLevels = Array(repeating: 0.0, count: 30)
        
        // Update menu bar icon
        updateMenuBarIcon(recording: true)
        
        // Show recording overlay
        showRecordingOverlay()
        
        // Start audio recording
        audioRecorder.startRecording()
        
        // Play start sound (subtle)
        NSSound(named: "Tink")?.play()
    }
    
    func stopRecordingAndTranscribe() {
        guard appState.isRecording else { return }
        
        appState.isRecording = false
        appState.isTranscribing = true
        
        // Stop audio recording
        guard let audioURL = audioRecorder.stopRecording() else {
            appState.errorMessage = "Failed to save recording"
            appState.isTranscribing = false
            hideRecordingOverlay()
            updateMenuBarIcon(recording: false)
            return
        }
        
        // Update UI
        updateMenuBarIcon(recording: false)
        
        // Transcribe
        Task {
            await transcribe(audioURL: audioURL)
        }
    }
    
    func cancelRecording() {
        appState.isRecording = false
        audioRecorder.cancelRecording()
        hideRecordingOverlay()
        updateMenuBarIcon(recording: false)
        
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
                    appState.isTranscribing = false
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
                appState.lastTranscription = transcription
                appState.isTranscribing = false
                hideRecordingOverlay()
                
                // Insert text at cursor
                if appState.autoInsertText {
                    print("Inserting text at cursor...")
                    textInserter.insertText(transcription)
                }
                
                // Play success sound
                NSSound(named: "Glass")?.play()
            }
            
            // Clean up audio file
            try? FileManager.default.removeItem(at: audioURL)
            
        } catch {
            print("Transcription ERROR: \(error.localizedDescription)")
            await MainActor.run {
                appState.errorMessage = "Transcription failed: \(error.localizedDescription)"
                appState.isTranscribing = false
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
                contentRect: NSRect(x: 0, y: 0, width: 200, height: 80),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            recordingWindow?.contentView = NSHostingView(rootView: contentView)
            recordingWindow?.backgroundColor = .clear
            recordingWindow?.isOpaque = false
            recordingWindow?.level = .floating
            recordingWindow?.collectionBehavior = [.canJoinAllSpaces, .stationary]
            recordingWindow?.hasShadow = true
        }
        
        // Position near the mouse cursor or center of screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let windowSize = recordingWindow!.frame.size
            let x = screenFrame.midX - windowSize.width / 2
            let y = screenFrame.maxY - windowSize.height - 100
            recordingWindow?.setFrameOrigin(NSPoint(x: x, y: y))
        }
        
        recordingWindow?.orderFront(nil)
    }
    
    private func hideRecordingOverlay() {
        recordingWindow?.orderOut(nil)
    }
    
    // MARK: - Menu Bar Icon
    
    private func updateMenuBarIcon(recording: Bool) {
        DispatchQueue.main.async {
            if let button = self.statusItem.button {
                if recording {
                    button.image = NSImage(systemSymbolName: "mic.badge.plus", accessibilityDescription: "Recording")
                    button.contentTintColor = .systemRed
                } else {
                    button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Flow Speech")
                    button.contentTintColor = nil
                }
            }
        }
    }
    
    // MARK: - Settings
    
    @objc func openSettings() {
        if settingsWindow == nil {
            let settingsView = SettingsView()
                .environmentObject(appState)
            
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
