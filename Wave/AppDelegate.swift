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
import os

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var recordingWindow: NSWindow?
    var companionWindow: NSWindow?
    var originalWindowDelegate: NSWindowDelegate?
    var modelContainer: ModelContainer?
    /// Called from SwiftUI to open the companion WindowGroup
    var openCompanionWindow: (() -> Void)?

    let appState = AppState()
    let audioLevels = AudioLevelModel()
    let hotkeyManager = HotkeyManager()
    let audioRecorder = AudioRecorder()
    let whisperService = WhisperService()
    let cleanupService = TextCleanupService()
    let textInserter = TextInserter()
    let exclusionService = AppExclusionService()
    let dictionaryService = DictionaryService.shared
    let snippetService = SnippetService.shared
    let hidFnKeyMonitor = HIDFnKeyMonitor()
    let audioDeviceObserver = AudioDeviceObserver()

    private var eventMonitor: Any?
    private var flagsMonitor: Any?
    private var localFlagsMonitor: Any?
    private var cancellables = Set<AnyCancellable>()

    private var recordingStartTime: Date?
    private var recordingSourceApp: String?

    private var transcriptionTask: Task<Void, Never>?
    private var transcribeWatchdog: DispatchWorkItem?
    private var maxDurationWorkItem: DispatchWorkItem?
    private static let maxRecordingDuration: TimeInterval = 15 * 60
    private static let transcribeWatchdogTimeout: TimeInterval = 45

    private let latencyLog = Logger(subsystem: "com.flowspeech.app", category: "latency")

    /// Single-slot recovery file: a dictation whose transcription failed is
    /// parked here instead of being deleted, so "Retry Last Dictation" works.
    static let recoveryFileURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Wave", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("last-failed.m4a")
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        setupHotkeys()
        setupAudioRecorder()

        // Pre-build the overlay window and preload sounds so the first hotkey
        // press doesn't pay for SwiftUI's initial render or disk I/O.
        makeOverlayWindowIfNeeded()
        preloadSounds()

        // If the default mic changes mid-recording (AirPods connect/disconnect),
        // the recorder is bound to the vanished device: salvage what we have.
        audioDeviceObserver.onDefaultInputChanged = { [weak self] in
            guard let self = self, self.appState.phase == .recording else { return }
            self.stopRecordingAndTranscribe()
        }
        audioDeviceObserver.start()

        // Check for required permissions
        checkPermissions()

        // Announce dictation state changes to VoiceOver users (the overlay
        // window itself never gets focus, so announcements are the only channel)
        appState.$phase
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { phase in
                let announcement: String?
                switch phase {
                case .recording: announcement = "Recording"
                case .done: announcement = "Transcription done"
                case .error(let message): announcement = message
                case .idle, .transcribing: announcement = nil
                }
                guard let announcement else { return }
                NSAccessibility.post(
                    element: NSApp as Any,
                    notification: .announcementRequested,
                    userInfo: [
                        .announcement: announcement,
                        .priority: NSAccessibilityPriorityLevel.medium.rawValue
                    ]
                )
            }
            .store(in: &cancellables)

        // Observe hotkey tap health
        hotkeyManager.$isTapHealthy
            .receive(on: DispatchQueue.main)
            .sink { [weak self] healthy in
                self?.updateMenuBarIconForHealth(healthy: healthy)
            }
            .store(in: &cancellables)

        // Reconfigure the input layers when user changes hotkey in settings
        appState.$selectedHotkey
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newHotkey in
                guard let self = self else { return }
                // Reset modifier state to prevent stuck recording
                self.modifierKeyDown = false
                self.fnSource = nil
                if self.appState.phase == .recording {
                    self.cancelRecording()
                }
                self.updateHotkeyInfrastructure(for: newHotkey)
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
                if window !== self.recordingWindow {
                    window.close()
                }
            }
            NSApp.setActivationPolicy(.accessory)
        }

        // 90-day retention cleanup — deferred because modelContainer is set by WaveApp.init() after this method
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
        menu.addItem(NSMenuItem(title: "Retry Last Dictation", action: #selector(retryLastDictation), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openCompanionSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Wave", action: #selector(quitApp), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    // MARK: - Hotkey Setup

    private func setupHotkeys() {
        // NSEvent monitors — handle capsLock/doubleTapCapsLock; Fn also as fallback.
        // Always on: they are cheap and cover every hotkey mode.
        flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
        }

        // Also monitor local events for when app is focused
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event
        }

        // CGEventTap + HID layer are started per-hotkey (they are expensive
        // always-on keyboard taps and inert for modes that don't need them)
        updateHotkeyInfrastructure(for: appState.selectedHotkey)

        // Monitor for escape to cancel recording
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyDown(event)
        }
    }

    /// Starts only the input layers the selected hotkey actually needs:
    /// CGEventTap for the key-combo hotkeys, IOHIDManager for Fn (Chrome
    /// swallows Fn from NSEvent monitors). Everything else runs on the
    /// always-on NSEvent monitors.
    private func updateHotkeyInfrastructure(for hotkey: HotkeyOption) {
        hotkeyManager.stop()
        if hotkey == .optionSpace || hotkey == .controlSpace {
            hotkeyManager.configure(
                hotkey: hotkey,
                onDown: { [weak self] in
                    DispatchQueue.main.async { self?.startRecording() }
                },
                onUp: { [weak self] in
                    DispatchQueue.main.async { self?.stopRecordingAndTranscribe() }
                }
            )
            hotkeyManager.start()
        }

        if hotkey == .fnKey {
            hidFnKeyMonitor.start(
                onFnDown: { [weak self] in
                    guard let self = self, self.appState.selectedHotkey == .fnKey else { return }
                    guard !self.modifierKeyDown else { return }
                    self.modifierKeyDown = true
                    self.fnSource = .hid
                    self.startRecording()
                },
                onFnUp: { [weak self] in
                    guard let self = self, self.appState.selectedHotkey == .fnKey else { return }
                    guard self.modifierKeyDown else { return }
                    self.modifierKeyDown = false
                    self.fnSource = nil
                    self.stopRecordingAndTranscribe()
                }
            )
        } else {
            hidFnKeyMonitor.stop()
        }
    }

    private var modifierKeyDown = false
    /// Tracks which source triggered the current Fn press to prevent cross-source release
    private enum FnSource { case hid, nsEvent }
    private var fnSource: FnSource?
    /// Caps Lock only reports its toggle STATE via flagsChanged (no clean
    /// down/up like Fn), so caps hotkeys work as press-to-toggle.
    private var lastCapsLockOn = false
    private var lastCapsTapTime: Date?
    private let capsDoubleTapInterval: TimeInterval = 0.4

    private func handleFlagsChanged(_ event: NSEvent) {
        let flags = event.modifierFlags

        switch appState.selectedHotkey {
        case .optionSpace, .controlSpace:
            return

        case .capsLock, .doubleTapCapsLock:
            handleCapsLockToggle(capsOn: flags.contains(.capsLock))

        case .fnKey:
            let keyPressed = flags.contains(.function)
            // Handle hold-to-record; skip if HID monitor already owns this press
            if keyPressed && !modifierKeyDown {
                if fnSource == .hid { return }
                modifierKeyDown = true
                fnSource = .nsEvent
                startRecording()
            } else if !keyPressed && modifierKeyDown {
                if fnSource == .hid { return }
                modifierKeyDown = false
                fnSource = nil
                stopRecordingAndTranscribe()
            }
        }
    }

    private func handleCapsLockToggle(capsOn: Bool) {
        // flagsChanged also fires for other modifiers; only react to actual
        // Caps Lock state transitions.
        guard capsOn != lastCapsLockOn else { return }
        lastCapsLockOn = capsOn

        switch appState.selectedHotkey {
        case .capsLock:
            // Press to start, press again to stop
            if appState.phase == .recording {
                stopRecordingAndTranscribe()
            } else {
                startRecording()
            }
        case .doubleTapCapsLock:
            if appState.phase == .recording {
                // Single tap stops
                stopRecordingAndTranscribe()
                lastCapsTapTime = nil
            } else {
                let now = Date()
                if let last = lastCapsTapTime, now.timeIntervalSince(last) < capsDoubleTapInterval {
                    lastCapsTapTime = nil
                    startRecording()
                } else {
                    lastCapsTapTime = now
                }
            }
        default:
            break
        }
    }

    private func handleKeyDown(_ event: NSEvent) {
        // Escape cancels both an active recording and an in-flight transcription
        guard event.keyCode == 53 else { return }
        switch appState.phase {
        case .recording:
            cancelRecording()
        case .transcribing:
            cancelTranscription()
        default:
            break
        }
    }

    // MARK: - Audio Recording Setup

    private func setupAudioRecorder() {
        // Level timer fires on the main run loop, so this mutates on main directly
        audioRecorder.onAudioLevel = { [weak self] level in
            self?.audioLevels.push(level)
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
        // Block while recording AND while a transcription is still in flight,
        // otherwise two overlapping pipelines clobber each other's state.
        guard appState.phase != .recording, appState.phase != .transcribing else { return }
        guard !exclusionService.shouldSuppressHotkey() else {
            // Silently suppress — no sound, no overlay
            return
        }

        appState.phase = .recording
        appState.errorMessage = nil
        audioLevels.reset()

        // Capture recording metadata at start (source app may change during Whisper API call)
        recordingStartTime = Date()
        recordingSourceApp = NSWorkspace.shared.frontmostApplication?.localizedName

        // Pill first: show the overlay before anything else so it paints on the
        // next commit. Mic spin-up and sound load must not block that paint.
        showRecordingOverlay()
        updateMenuBarIcon()

        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.appState.phase == .recording else { return }
            self.audioRecorder.startRecording()
            self.playFeedbackSound("wave-start", volume: 0.6)

            // Auto-stop very long recordings before they hit API size limits
            let limit = DispatchWorkItem { [weak self] in
                guard let self = self, self.appState.phase == .recording else { return }
                self.stopRecordingAndTranscribe()
            }
            self.maxDurationWorkItem?.cancel()
            self.maxDurationWorkItem = limit
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.maxRecordingDuration, execute: limit)
        }
    }

    func stopRecordingAndTranscribe() {
        guard appState.phase == .recording else { return }
        maxDurationWorkItem?.cancel()

        // Discard accidental taps silently: below ~0.3s there is no usable speech
        let duration = recordingStartTime.map { Date().timeIntervalSince($0) } ?? 0
        if duration < 0.3 {
            appState.phase = .idle
            audioRecorder.cancelRecording()
            hideRecordingOverlay()
            updateMenuBarIcon()
            return
        }

        appState.phase = .transcribing

        // Stop audio recording
        guard let audioURL = audioRecorder.stopRecording() else {
            appState.errorMessage = "Failed to save recording"
            showErrorPill("Recording failed")
            return
        }

        // Update UI
        updateMenuBarIcon()

        startTranscription(audioURL: audioURL, duration: duration)
    }

    /// Snapshots settings on the main thread, launches the transcription task,
    /// and arms a watchdog so the app can never get stuck in .transcribing.
    private func startTranscription(audioURL: URL, duration: TimeInterval) {
        let provider = appState.transcriptionProvider
        let request = TranscriptionRequest(
            provider: provider,
            model: provider == .groq ? "whisper-large-v3-turbo" : appState.selectedModel.rawValue,
            language: appState.language == "auto" ? nil : appState.language,
            smartCleanup: appState.smartCleanup,
            duration: duration,
            sourceApp: recordingSourceApp
        )
        recordingStartTime = nil
        recordingSourceApp = nil

        transcriptionTask = Task {
            await transcribe(audioURL: audioURL, request: request)
            DispatchQueue.main.async { [weak self] in
                self?.transcribeWatchdog?.cancel()
                self?.transcribeWatchdog = nil
            }
        }

        let watchdog = DispatchWorkItem { [weak self] in
            guard let self = self, self.appState.phase == .transcribing else { return }
            self.transcriptionTask?.cancel()
            self.appState.errorMessage = "Transcription timed out"
            self.showErrorPill("Timed out")
        }
        transcribeWatchdog?.cancel()
        transcribeWatchdog = watchdog
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.transcribeWatchdogTimeout, execute: watchdog)
    }

    /// Menu action: re-transcribe the recording parked by the last failure.
    @objc func retryLastDictation() {
        let source = Self.recoveryFileURL
        guard FileManager.default.fileExists(atPath: source.path) else {
            showErrorPill("No failed dictation")
            return
        }
        guard appState.phase == .idle || appState.phase == .done else { return }

        // Work on a temp copy so another failure can re-park it
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("flowspeech_retry_\(UUID().uuidString).m4a")
        do {
            try FileManager.default.moveItem(at: source, to: tempURL)
        } catch {
            showErrorPill("Retry failed")
            return
        }

        appState.phase = .transcribing
        showRecordingOverlay()
        updateMenuBarIcon()
        startTranscription(audioURL: tempURL, duration: 0)
    }

    func cancelRecording() {
        maxDurationWorkItem?.cancel()
        appState.phase = .idle
        audioRecorder.cancelRecording()
        hideRecordingOverlay()
        updateMenuBarIcon()

        // Play cancel sound (soft)
        playFeedbackSound("wave-cancel", volume: 0.5)
    }

    /// Escape during .transcribing: abort the in-flight task and reset
    func cancelTranscription() {
        transcriptionTask?.cancel()
        transcribeWatchdog?.cancel()
        appState.phase = .idle
        hideRecordingOverlay()
        updateMenuBarIcon()
        playFeedbackSound("wave-cancel", volume: 0.5)
    }

    // MARK: - Sound Feedback

    /// Custom bundled UI sounds (Resources/Sounds/*.caf): warm, quiet blips
    /// designed for a tool used dozens of times a day. Respects the sound toggle.
    private var soundCache: [String: NSSound] = [:]

    private func playFeedbackSound(_ name: String, volume: Float) {
        guard appState.soundFeedback else { return }
        guard let sound = cachedSound(name) else { return }
        sound.volume = volume
        if sound.isPlaying { sound.stop() }
        sound.play()
    }

    private func cachedSound(_ name: String) -> NSSound? {
        if let cached = soundCache[name] { return cached }
        guard let url = Bundle.main.url(forResource: name, withExtension: "caf", subdirectory: "Sounds"),
              let sound = NSSound(contentsOf: url, byReference: true) else { return nil }
        soundCache[name] = sound
        return sound
    }

    private func preloadSounds() {
        for name in ["wave-start", "wave-done", "wave-cancel", "wave-error"] {
            _ = cachedSound(name)
        }
    }

    // MARK: - Transcription

    private func transcribe(audioURL: URL, request: TranscriptionRequest) async {
        let provider = request.provider
        let tStart = CFAbsoluteTimeGetCurrent()

        // Get the provider's API key from Keychain
        let storedKey = provider == .groq
            ? KeychainManager.shared.getGroqAPIKey()
            : KeychainManager.shared.getAPIKey()
        guard let apiKey = storedKey else {
            await MainActor.run {
                appState.errorMessage = provider == .groq
                    ? "No Groq API key configured. Please add it in Settings."
                    : "No OpenAI API key configured. Please add it in Settings."
                showErrorPill(provider == .groq ? "No Groq API key" : "No OpenAI API key")
            }
            parkForRetry(audioURL)
            return
        }

        // Kept so the catch block can park already-transcribed text in the clipboard
        var transcription: String?

        do {
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

            // Transcribe using the selected provider
            let result = try await whisperService.transcribe(
                audioURL: audioURL,
                apiKey: apiKey,
                model: request.model,
                endpoint: provider.transcriptionURL,
                language: request.language,
                prompt: whisperPrompt
            )
            let tTranscribed = CFAbsoluteTimeGetCurrent()

            // Never paste an empty result (silence, stray noise)
            guard !result.isEmpty else {
                await MainActor.run { showErrorPill("Nothing heard") }
                try? FileManager.default.removeItem(at: audioURL)
                return
            }
            transcription = result

            // Smart Cleanup only pays off for longer dictations; short ones
            // skip the extra round-trip entirely.
            var finalText = result
            if request.smartCleanup && result.split(separator: " ").count >= 10 {
                finalText = await cleanupService.cleanup(text: result, apiKey: apiKey, provider: provider)
            }
            let tCleaned = CFAbsoluteTimeGetCurrent()

            // Post-transcription expansion: abbreviations then snippets (D-08 pipeline order)
            if let container = modelContainer {
                let bgContext = ModelContext(container)
                let dictWords = (try? bgContext.fetch(FetchDescriptor<DictionaryWord>())) ?? []
                let snippets = (try? bgContext.fetch(FetchDescriptor<Snippet>())) ?? []
                finalText = dictionaryService.expand(text: finalText, words: dictWords)
                finalText = snippetService.expand(text: finalText, snippets: snippets)
            }

            let textToInsert = finalText
            await MainActor.run {
                appState.lastTranscription = textToInsert
                appState.phase = .done
                updateMenuBarIcon()

                // Show done flash briefly, then hide overlay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                    self?.hideRecordingOverlay()
                }

                // Return to idle shortly after
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    if self?.appState.phase == .done {
                        self?.appState.phase = .idle
                        self?.updateMenuBarIcon()
                    }
                }

                // Insert text at cursor (tiny delay to let modifier keys settle)
                if appState.autoInsertText {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [self] in
                        textInserter.insertText(textToInsert)
                        // Play success sound (soft)
                        playFeedbackSound("wave-done", volume: 0.6)
                    }
                } else {
                    playFeedbackSound("wave-done", volume: 0.6)
                }
            }

            // Save to SwiftData AFTER the paste is scheduled (D-01: always save,
            // even if paste fails — D-02); history writes must not delay the text.
            let wordCount = finalText.split(separator: " ").count
            if let container = modelContainer {
                let bgContext = ModelContext(container)
                let entry = TranscriptionEntry(
                    rawText: result,
                    cleanedText: finalText,
                    durationSeconds: request.duration,
                    wordCount: wordCount,
                    sourceAppName: request.sourceApp
                )
                bgContext.insert(entry)
                try? bgContext.save()
            }

            // Clean up audio file
            try? FileManager.default.removeItem(at: audioURL)

            let transcribeMs = Int((tTranscribed - tStart) * 1000)
            let cleanupMs = Int((tCleaned - tTranscribed) * 1000)
            let totalMs = Int((CFAbsoluteTimeGetCurrent() - tStart) * 1000)
            latencyLog.info("stop→paste \(totalMs, privacy: .public)ms | transcribe \(transcribeMs, privacy: .public)ms | cleanup \(cleanupMs, privacy: .public)ms | provider \(provider.rawValue, privacy: .public) | words \(wordCount, privacy: .public)")

        } catch is CancellationError {
            // User hit Escape or the watchdog fired; UI reset happens there
            try? FileManager.default.removeItem(at: audioURL)
        } catch {
            let rescuedTranscription = transcription
            await MainActor.run {
                appState.errorMessage = "Transcription failed: \(error.localizedDescription)"
                // Never lose dictated text: if transcription succeeded but a later
                // step failed, park the raw transcript in the clipboard.
                if let rescued = rescuedTranscription {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(rescued, forType: .string)
                    showErrorPill("Failed, text in clipboard")
                } else {
                    showErrorPill("Failed, menu has Retry")
                }
            }
            // Keep the recording for "Retry Last Dictation" instead of deleting it
            parkForRetry(audioURL)
        }
    }

    private func parkForRetry(_ audioURL: URL) {
        let dest = Self.recoveryFileURL
        try? FileManager.default.removeItem(at: dest)
        try? FileManager.default.moveItem(at: audioURL, to: dest)
    }

    /// Shows a short error message in the overlay pill, then resets to idle.
    /// Must be called on the main thread.
    private func showErrorPill(_ message: String) {
        appState.phase = .error(message)
        showRecordingOverlay()
        updateMenuBarIcon()
        playFeedbackSound("wave-error", volume: 0.7)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard let self = self else { return }
            if case .error = self.appState.phase {
                self.appState.phase = .idle
                self.hideRecordingOverlay()
                self.updateMenuBarIcon()
            }
        }
    }

    // MARK: - Recording Overlay

    private static let pillHeight: CGFloat = 28
    private static let pillWidth: CGFloat = 96
    private static let pillErrorWidth: CGFloat = 240

    private func makeOverlayWindowIfNeeded() {
        guard recordingWindow == nil else { return }
        let contentView = RecordingOverlayView()
            .environmentObject(appState)
            .environmentObject(audioLevels)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Self.pillWidth, height: Self.pillHeight),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = DraggablePillHostingView(rootView: contentView)
        window.backgroundColor = .clear
        window.isOpaque = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.hasShadow = true
        recordingWindow = window

        // Remember where the user drags the pill (fires on programmatic moves
        // too, which is harmless: those derive from the saved position)
        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: window, queue: .main
        ) { [weak self] _ in
            guard let frame = self?.recordingWindow?.frame else { return }
            let defaults = UserDefaults.standard
            defaults.set(frame.midX, forKey: "overlayPillCenterX")
            defaults.set(frame.midY, forKey: "overlayPillCenterY")
        }
    }

    private var savedPillCenter: CGPoint? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "overlayPillCenterX") != nil else { return nil }
        return CGPoint(
            x: defaults.double(forKey: "overlayPillCenterX"),
            y: defaults.double(forKey: "overlayPillCenterY")
        )
    }

    private func showRecordingOverlay() {
        makeOverlayWindowIfNeeded()
        guard let window = recordingWindow else { return }

        // Error messages need more room than the minimal waveform pill
        var width = Self.pillWidth
        if case .error = appState.phase { width = Self.pillErrorWidth }
        let size = NSSize(width: width, height: Self.pillHeight)

        // Use the user's dragged position if it is still on a connected screen;
        // otherwise default to bottom-center of the screen under the mouse
        // (NSScreen.main is the menu-bar screen, wrong on multi-monitor setups).
        let origin: NSPoint
        if let center = savedPillCenter,
           NSScreen.screens.contains(where: { NSPointInRect(center, $0.visibleFrame) }) {
            origin = NSPoint(x: center.x - size.width / 2, y: center.y - size.height / 2)
        } else {
            let mouseLocation = NSEvent.mouseLocation
            let activeScreen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
            let screenFrame = (activeScreen ?? NSScreen.main)?.visibleFrame ?? .zero
            origin = NSPoint(x: screenFrame.midX - size.width / 2, y: screenFrame.minY + 24)
        }
        window.setFrame(NSRect(origin: origin, size: size), display: true)

        // Fade in instead of popping into place
        if !window.isVisible { window.alphaValue = 0 }
        window.orderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
        }
    }

    private func hideRecordingOverlay() {
        guard let window = recordingWindow, window.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0
        }, completionHandler: {
            // A re-show may have started a fade-in meanwhile; only hide if
            // the fade-out actually finished.
            if window.alphaValue == 0 { window.orderOut(nil) }
        })
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
            case .error:
                button.image = self.makeMenuBarIcon(color: NSColor.systemRed)
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

    // MARK: - Onboarding

    private func showOnboarding() {
        let onboardingView = OnboardingView {
            UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        }
        .environmentObject(appState)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 550),
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
        // File I/O off the launch path
        DispatchQueue.global(qos: .utility).async {
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
}

// Import for microphone permission check
import AVFoundation

// MARK: - Draggable Pill Hosting View

/// Lets the borderless overlay pill be dragged anywhere without
/// making the window key or stealing focus from the app being dictated into.
private final class DraggablePillHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

// MARK: - Transcription Request

/// Settings snapshot taken on the main thread before the transcription task
/// starts, so the background work never reads shared mutable state.
struct TranscriptionRequest {
    let provider: TranscriptionProvider
    let model: String
    let language: String?
    let smartCleanup: Bool
    let duration: TimeInterval
    let sourceApp: String?
}

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
