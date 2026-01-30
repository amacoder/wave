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
    
    /// Inserts text at the current cursor position via clipboard + paste
    func insertText(_ text: String) {
        print("TextInserter: inserting via clipboard paste")
        
        // Save current clipboard
        let pasteboard = NSPasteboard.general
        let oldContent = pasteboard.string(forType: .string)
        
        // Set text to clipboard
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        
        // Paste via AppleScript (requires Automation permission for System Events)
        let script = """
        tell application "System Events"
            keystroke "v" using command down
        end tell
        """
        
        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)
            if let error = error {
                print("TextInserter: AppleScript error - \(error[NSAppleScript.errorBriefMessage] ?? "unknown")")
                print("TextInserter: Grant Automation permission: System Settings → Privacy & Security → Automation → FlowSpeech → System Events")
            } else {
                print("TextInserter: paste successful")
            }
        }
        
        // Restore old clipboard after delay
        if let old = oldContent {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                pasteboard.clearContents()
                pasteboard.setString(old, forType: .string)
            }
        }
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
    
    // MARK: - Clipboard Method
    
    private func insertTextViaClipboard(_ text: String) {
        // Save current clipboard content
        let pasteboard = NSPasteboard.general
        let oldContent = pasteboard.string(forType: .string)
        
        // Set new text
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        
        print("TextInserter: clipboard set, simulating Cmd+V...")
        
        // Small delay to ensure clipboard is set
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [self] in
            simulatePaste()
            
            // Restore old clipboard content after paste completes
            if let old = oldContent {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    pasteboard.clearContents()
                    pasteboard.setString(old, forType: .string)
                    print("TextInserter: clipboard restored")
                }
            }
        }
    }
    
    private func simulatePaste() {
        // Create event source
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            print("TextInserter: ERROR - failed to create event source")
            return
        }
        
        // Key code for 'V' is 9
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
            print("TextInserter: ERROR - failed to create key events")
            return
        }
        
        // Add Command modifier
        keyDown.flags = [.maskCommand]
        keyUp.flags = [.maskCommand]
        
        // Post to the session
        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)
        
        print("TextInserter: Cmd+V posted")
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
