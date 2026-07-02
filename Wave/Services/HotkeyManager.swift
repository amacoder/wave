//
//  HotkeyManager.swift
//  Wave
//
//  Global hotkey management using Carbon and CGEvent
//

import Foundation
import Combine
import Carbon.HIToolbox

import AppKit

class HotkeyManager: ObservableObject {
    
    typealias HotkeyAction = () -> Void
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    @Published var isTapHealthy: Bool = true
    private var healthTimer: Timer?
    
    private var onHotkeyDown: HotkeyAction?
    private var onHotkeyUp: HotkeyAction?

    // Current hotkey configuration
    var currentHotkey: HotkeyOption = .capsLock
    var modifierKey: CGEventFlags = []
    var keyCode: UInt16 = 0
    
    deinit {
        stopHealthCheck()
        stop()
    }
    
    // MARK: - Setup
    
    func configure(hotkey: HotkeyOption, onDown: @escaping HotkeyAction, onUp: @escaping HotkeyAction) {
        currentHotkey = hotkey
        onHotkeyDown = onDown
        onHotkeyUp = onUp
        
        switch hotkey {
        case .capsLock, .doubleTapCapsLock:
            // Handled via flagsChanged in AppDelegate
            break
        case .optionSpace:
            modifierKey = .maskAlternate
            keyCode = 49 // Space
        case .controlSpace:
            modifierKey = .maskControl
            keyCode = 49 // Space
        case .fnKey:
            modifierKey = .maskSecondaryFn
            keyCode = 0
        }
    }
    
    // MARK: - Event Tap (for advanced hotkey handling)
    
    func start() {
        guard eventTap == nil else { return }

        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue) |
                                     (1 << CGEventType.keyUp.rawValue) |
                                     (1 << CGEventType.flagsChanged.rawValue)
        
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passRetained(event) }

                let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()

                if let result = manager.handleEvent(type: type, event: event) {
                    return result ? nil : Unmanaged.passRetained(event)
                }

                return Unmanaged.passRetained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
        
        guard let eventTap = eventTap else {
            return
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        startHealthCheck()
    }

    func stop() {
        stopHealthCheck()
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        
        if let runLoopSource = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        
        eventTap = nil
        runLoopSource = nil
    }

    // MARK: - Health Check

    func startHealthCheck() {
        healthTimer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkTapHealth()
        }
        RunLoop.main.add(healthTimer!, forMode: .common)
    }

    private func checkTapHealth() {
        guard let tap = eventTap else {
            DispatchQueue.main.async { self.isTapHealthy = false }
            return
        }
        let enabled = CGEvent.tapIsEnabled(tap: tap)
        if !enabled {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        let nowHealthy = CGEvent.tapIsEnabled(tap: tap)
        DispatchQueue.main.async { self.isTapHealthy = nowHealthy }
    }

    func stopHealthCheck() {
        healthTimer?.invalidate()
        healthTimer = nil
    }

    // MARK: - Event Handling
    
    private func handleEvent(type: CGEventType, event: CGEvent) -> Bool? {
        switch type {
        case .keyDown:
            return handleKeyDown(event: event)
        case .keyUp:
            return handleKeyUp(event: event)
        case .flagsChanged:
            return handleFlagsChanged(event: event)
        case CGEventType(rawValue: 0xFFFFFFFE)!, // tapDisabledByTimeout
             CGEventType(rawValue: 0xFFFFFFFF)!: // tapDisabledByUserInput
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return nil
        default:
            return nil
        }
    }
    
    private func handleKeyDown(event: CGEvent) -> Bool? {
        let flags = event.flags
        let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        
        // Check if our hotkey combo is pressed
        if modifierKey.rawValue != 0 && flags.contains(modifierKey) && code == keyCode {
            onHotkeyDown?()
            return true // Consume the event
        }
        
        return nil
    }
    
    private func handleKeyUp(event: CGEvent) -> Bool? {
        let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        
        if code == keyCode && (currentHotkey == .optionSpace || currentHotkey == .controlSpace) {
            onHotkeyUp?()
            return true
        }
        
        return nil
    }
    
    private func handleFlagsChanged(event: CGEvent) -> Bool? {
        switch currentHotkey {
        case .fnKey:
            // Fn key handled by NSEvent monitor in AppDelegate (works in Chrome)
            return nil

        default:
            return nil
        }
    }
    
}
