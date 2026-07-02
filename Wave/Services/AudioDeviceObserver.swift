//
//  AudioDeviceObserver.swift
//  Wave
//
//  Watches the system default input device via Core Audio. AVAudioRecorder
//  binds to the device active at record() time, so a mid-recording switch
//  (AirPods connect/disconnect) silently breaks capture; the AppDelegate
//  uses this to salvage the recording when that happens.
//

import CoreAudio
import Foundation

final class AudioDeviceObserver {
    var onDefaultInputChanged: (() -> Void)?

    private var isListening = false
    private var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultInputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    private lazy var listenerBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        self?.onDefaultInputChanged?()
    }

    func start() {
        guard !isListening else { return }
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            listenerBlock
        )
        isListening = true
    }

    func stop() {
        guard isListening else { return }
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            listenerBlock
        )
        isListening = false
    }

    deinit {
        stop()
    }
}
