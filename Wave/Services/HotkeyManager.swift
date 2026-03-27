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
    
    // For double-tap detection
    private var lastKeyTime: Date?
    private let doubleTapInterval: TimeInterval = 0.3
    
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
            #if DEBUG
            print("Failed to create event tap - accessibility permission may be required")
            #endif
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
        let flags = event.flags
        
        switch currentHotkey {
        case .fnKey:
            // Fn key handling
            if flags.contains(.maskSecondaryFn) {
                onHotkeyDown?()
            } else {
                onHotkeyUp?()
            }
            return nil // Don't consume modifier events
            
        default:
            return nil
        }
    }
    
    // MARK: - Caps Lock Specific
    
    /// Disables Caps Lock's normal behavior (toggling caps)
    /// This requires root access or special configuration
    func disableCapsLockDefault() {
        // This requires using hidutil or similar system commands
        // For safety, we don't actually disable it, just intercept
        // Users can disable it manually in System Settings > Keyboard > Modifier Keys
    }
    
    // MARK: - Helpers
    
    static func keyCodeToString(_ keyCode: UInt16) -> String {
        let keyMap: [UInt16: String] = [
            0x00: "A", 0x01: "S", 0x02: "D", 0x03: "F",
            0x04: "H", 0x05: "G", 0x06: "Z", 0x07: "X",
            0x08: "C", 0x09: "V", 0x0B: "B", 0x0C: "Q",
            0x0D: "W", 0x0E: "E", 0x0F: "R", 0x10: "Y",
            0x11: "T", 0x12: "1", 0x13: "2", 0x14: "3",
            0x15: "4", 0x16: "6", 0x17: "5", 0x18: "=",
            0x19: "9", 0x1A: "7", 0x1B: "-", 0x1C: "8",
            0x1D: "0", 0x1E: "]", 0x1F: "O", 0x20: "U",
            0x21: "[", 0x22: "I", 0x23: "P", 0x24: "Return",
            0x25: "L", 0x26: "J", 0x27: "'", 0x28: "K",
            0x29: ";", 0x2A: "\\", 0x2B: ",", 0x2C: "/",
            0x2D: "N", 0x2E: "M", 0x2F: ".", 0x30: "Tab",
            0x31: "Space", 0x32: "`", 0x33: "Delete",
            0x35: "Escape", 0x37: "Command", 0x38: "Shift",
            0x39: "Caps Lock", 0x3A: "Option", 0x3B: "Control",
            0x3C: "Right Shift", 0x3D: "Right Option",
            0x3E: "Right Control", 0x3F: "Function",
        ]
        return keyMap[keyCode] ?? "Key \(keyCode)"
    }
}
