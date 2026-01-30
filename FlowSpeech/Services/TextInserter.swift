//
//  TextInserter.swift
//  FlowSpeech
//
//  Inserts transcribed text at cursor using Accessibility API
//

import Foundation
import AppKit
import ApplicationServices

class TextInserter {
    
    // MARK: - Text Insertion
    
    /// Inserts text at the current cursor position via clipboard + Cmd+V
    func insertText(_ text: String) {
        print("TextInserter: inserting via clipboard + CGEvent Cmd+V")
        
        // Save current clipboard
        let pasteboard = NSPasteboard.general
        let oldContent = pasteboard.string(forType: .string)
        
        // Set text to clipboard
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        
        // Clear any held modifier keys first
        clearModifierKeys()
        
        // Small delay to ensure modifiers are cleared
        usleep(50000) // 50ms
        
        // Simulate Cmd+V
        simulatePaste()
        
        // Restore old clipboard after delay
        if let old = oldContent {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                pasteboard.clearContents()
                pasteboard.setString(old, forType: .string)
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
        
        print("TextInserter: modifier keys cleared")
    }
    
    private func simulatePaste() {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            print("TextInserter: failed to create event source")
            return
        }
        
        // Create Cmd+V key events
        guard let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 55, keyDown: true),
              let vDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let vUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false),
              let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 55, keyDown: false) else {
            print("TextInserter: failed to create key events")
            return
        }
        
        // Post: Cmd down, V down, V up, Cmd up
        cmdDown.post(tap: .cghidEventTap)
        usleep(10000)
        
        vDown.flags = .maskCommand
        vDown.post(tap: .cghidEventTap)
        usleep(10000)
        
        vUp.flags = .maskCommand
        vUp.post(tap: .cghidEventTap)
        usleep(10000)
        
        cmdUp.post(tap: .cghidEventTap)
        
        print("TextInserter: Cmd+V posted via CGEvent")
    }
    
    // MARK: - Accessibility API Method
    
    private func insertTextViaAccessibility(_ text: String) -> Bool {
        // Get the focused application
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return false
        }
        
        let pid = app.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)
        
        // Get the focused element
        var focusedElement: CFTypeRef?
        let focusResult = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )
        
        guard focusResult == .success,
              let element = focusedElement else {
            return false
        }
        
        let axElement = element as! AXUIElement
        
        // Check if the element is a text field
        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(axElement, kAXRoleAttribute as CFString, &role)
        
        guard let roleString = role as? String,
              roleString == kAXTextFieldRole || roleString == kAXTextAreaRole else {
            return false
        }
        
        // Get current selection range
        var selectedRange: CFTypeRef?
        let rangeResult = AXUIElementCopyAttributeValue(
            axElement,
            kAXSelectedTextRangeAttribute as CFString,
            &selectedRange
        )
        
        if rangeResult == .success, let range = selectedRange {
            // Get the range value
            var cfRange = CFRange()
            if AXValueGetValue(range as! AXValue, .cfRange, &cfRange) {
                // Insert text by setting selected text
                let setResult = AXUIElementSetAttributeValue(
                    axElement,
                    kAXSelectedTextAttribute as CFString,
                    text as CFString
                )
                
                return setResult == .success
            }
        }
        
        // Alternative: Try setting the value directly (appends to existing)
        var currentValue: CFTypeRef?
        let valueResult = AXUIElementCopyAttributeValue(
            axElement,
            kAXValueAttribute as CFString,
            &currentValue
        )
        
        if valueResult == .success, let current = currentValue as? String {
            let newValue = current + text
            let setResult = AXUIElementSetAttributeValue(
                axElement,
                kAXValueAttribute as CFString,
                newValue as CFString
            )
            return setResult == .success
        }
        
        return false
    }
    
    // MARK: - Typing Simulation (Alternative)
    
    /// Types text character by character using CGEvents
    /// Slower but works in more applications
    func typeText(_ text: String, delay: TimeInterval = 0.01) {
        let source = CGEventSource(stateID: .hidSystemState)
        
        for char in text {
            // Create unicode string for the character
            var unicodeChar = Array(String(char).utf16)
            
            // Key down
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
            keyDown?.keyboardSetUnicodeString(stringLength: unicodeChar.count, unicodeString: &unicodeChar)
            keyDown?.post(tap: .cghidEventTap)
            
            // Key up
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            keyUp?.keyboardSetUnicodeString(stringLength: unicodeChar.count, unicodeString: &unicodeChar)
            keyUp?.post(tap: .cghidEventTap)
            
            // Small delay between characters
            Thread.sleep(forTimeInterval: delay)
        }
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
