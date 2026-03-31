//
//  AudioRecorder.swift
//  Wave
//
//  AVFoundation audio recording with level metering
//

import Foundation
import AVFoundation

class AudioRecorder: NSObject, ObservableObject {
    private var audioRecorder: AVAudioRecorder?
    private var levelTimer: Timer?
    private var recordingURL: URL?
    
    var onAudioLevel: ((Float) -> Void)?
    
    // MARK: - Recording
    
    func startRecording() {
        // Use temp directory instead of documents
        let tempDir = FileManager.default.temporaryDirectory
        let audioFilename = tempDir.appendingPathComponent("flowspeech_\(UUID().uuidString).m4a")
        recordingURL = audioFilename
        
        // Audio settings optimized for speech
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,  // Standard sample rate
            AVNumberOfChannelsKey: 1,   // Mono
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        do {
            audioRecorder = try AVAudioRecorder(url: audioFilename, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.isMeteringEnabled = true
            
            let started = audioRecorder?.record() ?? false

            if started {
                // Start level monitoring
                startLevelMonitoring()
            }

        } catch {
            #if DEBUG
            print("Failed to create recorder: \(error.localizedDescription)")
            #endif
        }
    }
    
    func stopRecording() -> URL? {
        stopLevelMonitoring()
        audioRecorder?.stop()
        
        let url = recordingURL
        audioRecorder = nil
        
        return url
    }
    
    func cancelRecording() {
        stopLevelMonitoring()
        audioRecorder?.stop()
        
        // Delete the recording file
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        
        recordingURL = nil
        audioRecorder = nil
    }
    
    // MARK: - Level Monitoring
    
    private func startLevelMonitoring() {
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.updateAudioLevel()
        }
    }
    
    private func stopLevelMonitoring() {
        levelTimer?.invalidate()
        levelTimer = nil
    }
    
    private func updateAudioLevel() {
        guard let recorder = audioRecorder else { return }
        
        recorder.updateMeters()
        
        // Get the average power level (in dB, typically -160 to 0)
        let avgPower = recorder.averagePower(forChannel: 0)
        
        // Convert dB to a 0-1 scale
        // -60 dB = silence, 0 dB = max
        let normalizedLevel = max(0, (avgPower + 60) / 60)
        
        onAudioLevel?(normalizedLevel)
    }
    
    // MARK: - Duration
    
    var currentTime: TimeInterval {
        audioRecorder?.currentTime ?? 0
    }
    
    var isRecording: Bool {
        audioRecorder?.isRecording ?? false
    }
}

// MARK: - AVAudioRecorderDelegate

extension AudioRecorder: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        // No-op: delegate required but logging removed for production
    }

    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        #if DEBUG
        print("Recording encode error: \(error?.localizedDescription ?? "Unknown error")")
        #endif
    }
}
