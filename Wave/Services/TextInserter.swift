//
//  TextInserter.swift
//  Wave
//
//  Inserts transcribed text at cursor using Accessibility API
//

import Foundation
import AppKit
import ApplicationServices

// MARK: - NSPasteboard type constants

extension NSPasteboard.PasteboardType {
    /// Marks a pasteboard write as transient so clipboard managers skip logging.
    /// Source: http://nspasteboard.org
    static let transientContent = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
}

class TextInserter {

    // MARK: - Text Insertion

    /// Inserts text at the current cursor position via clipboard + Cmd+V,
    /// then restores the user's previous clipboard content (CLIP-02).
    func insertText(_ text: String) {
        let pasteboard = NSPasteboard.general

        // ponytail: string-only clipboard snapshot; full multi-type restore if anyone misses images
        let previousClipboard = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Mark as transient so clipboard managers skip logging (CLIP-03)
        pasteboard.setData(Data(), forType: .transientContent)

        // Snapshot for the restore guard (CLIP-02)
        let changeCountAfterWrite = pasteboard.changeCount

        // Clear any held modifier keys first
        clearModifierKeys()

        // Small delay to ensure modifiers are cleared
        usleep(20000) // 20ms

        // Simulate Cmd+V
        simulatePaste()

        // Restore the user's clipboard once the paste has landed.
        // Skip if the user copied something else in the meantime (changeCount moved).
        if let previous = previousClipboard {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                guard pasteboard.changeCount == changeCountAfterWrite else { return }
                pasteboard.clearContents()
                pasteboard.setString(previous, forType: .string)
            }
        }
    }
    
    private func clearModifierKeys() {
        // Post key-up events for common modifiers to ensure they're released
        let source = CGEventSource(stateID: .hidSystemState)
        
        // Release Fn key (keycode 63)
        if let fnUp = CGEvent(keyboardEventSource: source, virtualKey: 63, keyDown: false) {
            fnUp.post(tap: .cghidEventTap)
        }
        
        // Release Option keys
        if let optUp = CGEvent(keyboardEventSource: source, virtualKey: 58, keyDown: false) {
            optUp.post(tap: .cghidEventTap)
        }
        
        // Release Control
        if let ctrlUp = CGEvent(keyboardEventSource: source, virtualKey: 59, keyDown: false) {
            ctrlUp.post(tap: .cghidEventTap)
        }
        
        #if DEBUG
        print("TextInserter: modifier keys cleared")
        #endif
    }
    
    private func simulatePaste() {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            #if DEBUG
            print("TextInserter: failed to create event source")
            #endif
            return
        }
        
        // Create Cmd+V key events
        guard let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 55, keyDown: true),
              let vDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let vUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false),
              let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 55, keyDown: false) else {
            #if DEBUG
            print("TextInserter: failed to create key events")
            #endif
            return
        }
        
        // Post: Cmd down, V down, V up, Cmd up
        cmdDown.post(tap: .cghidEventTap)
        usleep(5000)

        vDown.flags = .maskCommand
        vDown.post(tap: .cghidEventTap)
        usleep(5000)

        vUp.flags = .maskCommand
        vUp.post(tap: .cghidEventTap)
        usleep(5000)

        cmdUp.post(tap: .cghidEventTap)
        
        #if DEBUG
        print("TextInserter: Cmd+V posted via CGEvent")
        #endif
    }
    
    // MARK: - Permissions Check
    
    static var hasAccessibilityPermission: Bool {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        return AXIsProcessTrustedWithOptions(options)
    }
    
    static func requestAccessibilityPermission() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options)
    }
}
