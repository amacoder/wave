//
//  HIDFnKeyMonitor.swift
//  Wave
//
//  Monitors the Fn/Globe key via IOHIDManager at the USB HID transport layer.
//  This bypasses Chrome's event interception that blocks NSEvent global monitors.
//

import Foundation
import IOKit
import IOKit.hid

final class HIDFnKeyMonitor {
    // Apple Vendor Top Case usage page and Fn key usage
    static let appleVendorTopCasePage: UInt32 = 0xFF
    static let keyboardFnUsage: UInt32 = 0x03

    private var manager: IOHIDManager?
    var onFnDown: (() -> Void)?
    var onFnUp: (() -> Void)?

    /// Start monitoring Fn/Globe key via IOKit HID.
    /// Callbacks fire on the main thread.
    func start(onFnDown: @escaping () -> Void, onFnUp: @escaping () -> Void) {
        guard manager == nil else { return }

        self.onFnDown = onFnDown
        self.onFnUp = onFnUp

        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        manager = mgr

        // Match all keyboard-type HID devices
        let keyboards: [[String: Any]] = [
            [
                kIOHIDDeviceUsagePageKey as String: kHIDPage_GenericDesktop,
                kIOHIDDeviceUsageKey as String: kHIDUsage_GD_Keyboard
            ],
            [
                kIOHIDDeviceUsagePageKey as String: kHIDPage_GenericDesktop,
                kIOHIDDeviceUsageKey as String: kHIDUsage_GD_Keypad
            ]
        ]
        IOHIDManagerSetDeviceMatchingMultiple(mgr, keyboards as CFArray)

        // Register input value callback
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterInputValueCallback(mgr, hidInputCallback, context)

        IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        let result = IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))

        #if DEBUG
        if result == kIOReturnSuccess {
            print("HIDFnKeyMonitor: started successfully")
        } else {
            print("HIDFnKeyMonitor: failed to open manager (error \(result))")
        }
        #endif
    }

    func stop() {
        guard let mgr = manager else { return }
        IOHIDManagerClose(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        manager = nil
        onFnDown = nil
        onFnUp = nil
        #if DEBUG
        print("HIDFnKeyMonitor: stopped")
        #endif
    }

    deinit {
        stop()
    }
}

// MARK: - HID Callback (C-function)

private func hidInputCallback(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    value: IOHIDValue
) {
    guard let context = context else { return }
    let monitor = Unmanaged<HIDFnKeyMonitor>.fromOpaque(context).takeUnretainedValue()

    let element = IOHIDValueGetElement(value)
    let usagePage = IOHIDElementGetUsagePage(element)
    let usage = IOHIDElementGetUsage(element)

    // Only care about Apple Vendor Top Case → Fn key
    guard usagePage == HIDFnKeyMonitor.appleVendorTopCasePage,
          usage == HIDFnKeyMonitor.keyboardFnUsage else {
        return
    }

    let pressed = IOHIDValueGetIntegerValue(value) != 0

    #if DEBUG
    print("HIDFnKeyMonitor: Fn \(pressed ? "DOWN" : "UP") (page=0x\(String(usagePage, radix: 16)), usage=0x\(String(usage, radix: 16)))")
    #endif

    DispatchQueue.main.async {
        if pressed {
            monitor.onFnDown?()
        } else {
            monitor.onFnUp?()
        }
    }
}
