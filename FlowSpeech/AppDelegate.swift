//
//  AppDelegate.swift
//  Wave
//
//  Menu bar app setup and global hotkey handling
//

import SwiftUI
import AppKit
import Carbon.HIToolbox
import Combine
import SwiftData

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var recordingWindow: NSWindow?
    var settingsWindow: NSWindow?
    var companionWindow: NSWindow?
    var originalWindowDelegate: NSWindowDelegate?
    var modelContainer: ModelContainer?
    /// Called from SwiftUI to open the companion WindowGroup
    var openCompanionWindow: (() -> Void)?
    
    let appState = AppState()
    let hotkeyManager = HotkeyManager()
    let audioRecorder = AudioRecorder()
    let whisperService = WhisperService()
    let cleanupService = TextCleanupService()
    let textInserter = TextInserter()
    let exclusionService = AppExclusionService()
    let dictionaryService = DictionaryService.shared
    let snippetService = SnippetService.shared
    
    private var eventMonitor: Any?
    private var flagsMonitor: Any?
    private var cancellables = Set<AnyCancellable>()

    private var recordingStartTime: Date?
    private var recordingSourceApp: String?
    
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

        // Reconfigure HotkeyManager when user changes hotkey in settings
        appState.$selectedHotkey
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newHotkey in
                guard let self = self else { return }
                self.hotkeyManager.stop()
                self.hotkeyManager.configure(
                    hotkey: newHotkey,
                    onDown: { [weak self] in
                        DispatchQueue.main.async { self?.startRecording() }
                    },
                    onUp: { [weak self] in
                        DispatchQueue.main.async { self?.stopRecordingAndTranscribe() }
                    }
                )
                self.hotkeyManager.start()
            }
            .store(in: &cancellables)

        // Clean up orphaned audio temp files from previous sessions
        cleanupOrphanedTempFiles()

        // Show onboarding if first launch
        if !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
            showOnboarding()
        }

        // Close any auto-opened SwiftUI WindowGroup windows (LSUIElement menu bar app)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            for window in NSApp.windows where window.title == "Wave" || window.identifier?.rawValue.contains("companion") == true {
                if window !== self.settingsWindow && window !== self.recordingWindow {
                    window.close()
                }
            }
            NSApp.setActivationPolicy(.accessory)
        }

        // 90-day retention cleanup — deferred because modelContainer is set by FlowSpeechApp.init() after this method
        DispatchQueue.main.async { [weak self] in
            self?.cleanupOldEntries()
        }
    }
    
    // MARK: - Menu Bar Setup
    
    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.image = makeMenuBarIcon()
        }
        
        // Build simple menu
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open Wave", action: #selector(openCompanion), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Start Recording", action: #selector(toggleRecording), keyEquivalent: "r"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openCompanionSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Wave", action: #selector(quitApp), keyEquivalent: "q"))
        
        statusItem.menu = menu
    }
    
    // MARK: - Hotkey Setup
    
    private func setupHotkeys() {
        // Configure and start the CGEventTap-based HotkeyManager (robust fn key detection)
        hotkeyManager.configure(
            hotkey: appState.selectedHotkey,
            onDown: { [weak self] in
                DispatchQueue.main.async {
                    self?.startRecording()
                }
            },
            onUp: { [weak self] in
                DispatchQueue.main.async {
                    self?.stopRecordingAndTranscribe()
                }
            }
        )
        hotkeyManager.start()

        // NSEvent monitors — primary handler for fn key (works in Chrome)
        flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
        }

        // Also monitor local events for when app is focused
        NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event
        }

        // Monitor for escape to cancel recording
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyDown(event)
        }
    }
    
    private var modifierKeyDown = false
    
    private func handleFlagsChanged(_ event: NSEvent) {
        // Option+space and control+space are handled by HotkeyManager's CGEventTap
        // Fn key is handled here via NSEvent (works in Chrome where CGEventTap misses fn release)
        // NSEvent also handles caps lock variants
        switch appState.selectedHotkey {
        case .optionSpace, .controlSpace:
            return
        case .fnKey, .capsLock, .doubleTapCapsLock:
            break
        }

        let flags = event.modifierFlags
        let keyPressed: Bool
        switch appState.selectedHotkey {
        case .fnKey:
            keyPressed = flags.contains(.function)
        case .capsLock:
            keyPressed = flags.contains(.option)
        case .doubleTapCapsLock:
            keyPressed = flags.contains(.capsLock)
        default:
            return
        }

        // Handle hold-to-record
        if keyPressed && !modifierKeyDown {
            modifierKeyDown = true
            #if DEBUG
            print("Hotkey pressed - starting recording")
            #endif
            startRecording()
        } else if !keyPressed && modifierKeyDown {
            modifierKeyDown = false
            #if DEBUG
            print("Hotkey released - stopping recording")
            #endif
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

        // Capture recording metadata at start (source app may change during Whisper API call)
        recordingStartTime = Date()
        recordingSourceApp = NSWorkspace.shared.frontmostApplication?.localizedName

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
        #if DEBUG
        print("Starting transcription for: \(audioURL.path)")
        #endif

        do {
            // Get API key from Keychain
            guard let apiKey = KeychainManager.shared.getAPIKey() else {
                await MainActor.run {
                    appState.errorMessage = "No API key configured. Please add your OpenAI API key in Settings."
                    appState.phase = .idle
                    hideRecordingOverlay()
                    updateMenuBarIcon()
                }
                return
            }
            
            #if DEBUG
            print("API key found, calling Whisper API with model: \(appState.selectedModel.rawValue)")
            #endif

            // Build Whisper prompt from dictionary vocabulary hints
            var whisperPrompt: String? = nil
            if let container = modelContainer {
                let bgContext = ModelContext(container)
                let descriptor = FetchDescriptor<DictionaryWord>(
                    sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
                )
                if let words = try? bgContext.fetch(descriptor) {
                    whisperPrompt = dictionaryService.buildPrompt(words: words)
                }
            }

            // Transcribe using Whisper API
            let transcription = try await whisperService.transcribe(
                audioURL: audioURL,
                apiKey: apiKey,
                model: appState.selectedModel,
                language: appState.language == "auto" ? nil : appState.language,
                prompt: whisperPrompt
            )

            // Post-process: run Smart Cleanup via GPT-4o-mini if enabled
            var finalText = transcription
            if appState.smartCleanup {
                finalText = await cleanupService.cleanup(text: transcription, apiKey: apiKey)
            }

            // Post-transcription expansion: abbreviations then snippets (D-08 pipeline order)
            if let container = modelContainer {
                let bgContext = ModelContext(container)
                let dictWords = (try? bgContext.fetch(FetchDescriptor<DictionaryWord>())) ?? []
                let snippets = (try? bgContext.fetch(FetchDescriptor<Snippet>())) ?? []
                finalText = dictionaryService.expand(text: finalText, words: dictWords)
                finalText = snippetService.expand(text: finalText, snippets: snippets)
            }

            #if DEBUG
            if whisperPrompt != nil {
                print("Whisper prompt: \(whisperPrompt!.prefix(100))...")
            }
            print("Final text after expansion: \(finalText.prefix(100))...")
            #endif

            // Save transcription to SwiftData (D-01: always save, even if paste fails — D-02)
            let wordCount = finalText.split(separator: " ").count
            let duration = recordingStartTime.map { Date().timeIntervalSince($0) } ?? 0
            let sourceApp = recordingSourceApp

            if let container = modelContainer {
                let bgContext = ModelContext(container)
                let entry = TranscriptionEntry(
                    rawText: transcription,
                    cleanedText: finalText,
                    durationSeconds: duration,
                    wordCount: wordCount,
                    sourceAppName: sourceApp
                )
                bgContext.insert(entry)
                try? bgContext.save()
            }

            // Reset recording metadata
            recordingStartTime = nil
            recordingSourceApp = nil

            await MainActor.run {
                appState.lastTranscription = finalText
                appState.phase = .done
                updateMenuBarIcon()

                // Show done flash for 0.8s, then hide overlay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                    self?.hideRecordingOverlay()
                }

                // Return to idle after 1.5s (unchanged timing)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                    if self?.appState.phase == .done {
                        self?.appState.phase = .idle
                        self?.updateMenuBarIcon()
                    }
                }

                // Insert text at cursor (with small delay to let modifier keys settle)
                if appState.autoInsertText {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [self] in
                        textInserter.insertText(finalText)
                        // Play success sound
                        NSSound(named: "Glass")?.play()
                    }
                } else {
                    NSSound(named: "Glass")?.play()
                }
            }

            // Clean up audio file
            try? FileManager.default.removeItem(at: audioURL)

        } catch {
            #if DEBUG
            print("Transcription error: \(error.localizedDescription)")
            #endif
            await MainActor.run {
                appState.errorMessage = "Transcription failed: \(error.localizedDescription)"
                appState.phase = .idle
                hideRecordingOverlay()
                updateMenuBarIcon()

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
                contentRect: NSRect(x: 0, y: 0, width: 120, height: 36),
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
            let pillWidth: CGFloat = 120
            let pillHeight: CGFloat = 36
            let x = screenFrame.midX - pillWidth / 2
            let y = screenFrame.minY + 24  // just above the Dock
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

    private func makeMenuBarIcon(color: NSColor? = nil) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let path = NSBezierPath()
            let sx: CGFloat = 18.0 / 16.0
            let sy: CGFloat = 18.0 / 16.0
            path.move(to: NSPoint(x: 2 * sx, y: 18 - 8.5 * sy))
            path.curve(to: NSPoint(x: 5 * sx, y: 18 - 4.5 * sy),
                       controlPoint1: NSPoint(x: 2.8 * sx, y: 18 - 8.5 * sy),
                       controlPoint2: NSPoint(x: 3.5 * sx, y: 18 - 4.5 * sy))
            path.curve(to: NSPoint(x: 8 * sx, y: 18 - 9.0 * sy),
                       controlPoint1: NSPoint(x: 6 * sx, y: 18 - 4.5 * sy),
                       controlPoint2: NSPoint(x: 6.2 * sx, y: 18 - 8.2 * sy))
            path.curve(to: NSPoint(x: 11 * sx, y: 18 - 4.5 * sy),
                       controlPoint1: NSPoint(x: 9.8 * sx, y: 18 - 9.8 * sy),
                       controlPoint2: NSPoint(x: 9.5 * sx, y: 18 - 4.5 * sy))
            path.curve(to: NSPoint(x: 14 * sx, y: 18 - 8.5 * sy),
                       controlPoint1: NSPoint(x: 12.5 * sx, y: 18 - 4.5 * sy),
                       controlPoint2: NSPoint(x: 13.2 * sx, y: 18 - 8.5 * sy))
            path.lineWidth = 2.2 * sx
            path.lineCapStyle = .round
            (color ?? NSColor.black).setStroke()
            path.stroke()
            return true
        }
        // Only use template mode for default (no color) — lets system handle dark/light
        image.isTemplate = (color == nil)
        return image
    }

    private func updateMenuBarIcon() {
        DispatchQueue.main.async {
            guard let button = self.statusItem.button else { return }
            switch self.appState.phase {
            case .idle, .done:
                button.image = self.makeMenuBarIcon()
            case .recording:
                button.image = self.makeMenuBarIcon(color: NSColor(red: 0.984, green: 0.749, blue: 0.141, alpha: 1))
            case .transcribing:
                button.image = self.makeMenuBarIcon(color: NSColor(red: 0.961, green: 0.620, blue: 0.043, alpha: 1))
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

    // MARK: - Dock Icon Toggle

    func enableDockIcon() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func disableDockIcon() {
        // Delay to prevent focus-stealing flicker (RESEARCH.md Pitfall 3)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    // MARK: - Companion Window

    @objc func openCompanion() {
        NSApp.setActivationPolicy(.regular)
        // If the companion window already exists, just bring it forward
        if let window = companionWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        // Otherwise ask SwiftUI to create a new one
        openCompanionWindow?()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openCompanion()
        return false  // Prevent macOS from also auto-opening a WindowGroup window
    }

    @objc func openCompanionSettings() {
        openCompanion()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NotificationCenter.default.post(name: .navigateToSettings, object: nil)
        }
    }

    // MARK: - Settings

    @objc func openSettings() {
        if settingsWindow == nil {
            let settingsView = SettingsView()
                .environmentObject(appState)
                .environmentObject(exclusionService)
            
            settingsWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 680, height: 560),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            settingsWindow?.title = "Wave Settings"
            settingsWindow?.contentView = NSHostingView(rootView: settingsView)
            settingsWindow?.center()
        }
        
        settingsWindow?.makeKeyAndOrderFront(nil)
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
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
        window.title = "Welcome to Wave"
        window.contentView = NSHostingView(rootView: onboardingView)
        window.center()
        window.makeKeyAndOrderFront(nil)
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
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

    // MARK: - Retention Cleanup

    private func cleanupOldEntries() {
        guard let container = modelContainer else { return }
        Task {
            let context = ModelContext(container)
            let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: Date())!
            let predicate = #Predicate<TranscriptionEntry> { $0.timestamp < cutoff }
            try? context.delete(model: TranscriptionEntry.self, where: predicate)
            try? context.save()
        }
    }

    // MARK: - Temp File Cleanup

    private func cleanupOrphanedTempFiles() {
        let tempDir = FileManager.default.temporaryDirectory
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: tempDir,
            includingPropertiesForKeys: nil
        ) else { return }

        for file in contents where file.lastPathComponent.hasPrefix("flowspeech_") && file.pathExtension == "m4a" {
            try? FileManager.default.removeItem(at: file)
        }
    }
}

// Import for microphone permission check
import AVFoundation

// MARK: - NSWindowDelegate (companion window hide-on-close)

extension AppDelegate: NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Only intercept the companion window — let other windows close normally
        guard sender === companionWindow else {
            return true
        }
        // Let SwiftUI close normally, disable dock icon
        companionWindow = nil
        disableDockIcon()
        return true
    }

    func windowDidBecomeKey(_ notification: Notification) {
        originalWindowDelegate?.windowDidBecomeKey?(notification)
    }

    func windowDidResignKey(_ notification: Notification) {
        originalWindowDelegate?.windowDidResignKey?(notification)
    }

    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window === companionWindow {
            companionWindow = nil
            disableDockIcon()
        }
        originalWindowDelegate?.windowWillClose?(notification)
    }
}
