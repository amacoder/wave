//
//  AudioRecorder.swift
//  FlowSpeech
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
        // Create temporary file URL
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let audioFilename = documentsPath.appendingPathComponent("recording_\(UUID().uuidString).m4a")
        recordingURL = audioFilename
        
        // Audio settings optimized for speech
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16000.0,  // 16kHz is good for speech
            AVNumberOfChannelsKey: 1,   // Mono
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            AVEncoderBitRateKey: 64000  // 64kbps
        ]
        
        do {
            audioRecorder = try AVAudioRecorder(url: audioFilename, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.record()
            
            // Start level monitoring
            startLevelMonitoring()
            
        } catch {
            print("Failed to start recording: \(error)")
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
        if !flag {
            print("Recording finished unsuccessfully")
        }
    }
    
    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        print("Recording encode error: \(error?.localizedDescription ?? "Unknown error")")
    }
}
