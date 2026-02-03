#!/usr/bin/env swift
//
//  ringcon_profiler.swift
//  Standalone CLI to monitor raw Joy-Con HID bytes for Ring-Con reverse engineering
//
//  Compile: swiftc -framework IOKit -framework CoreFoundation ringcon_profiler.swift -o ringcon-profiler
//  Run:     ./ringcon-profiler
//
//  IMPORTANT: Close the RingBreak app before running this tool!

import Foundation
import IOKit
import IOKit.hid

// MARK: - Constants

let kVendorNintendo: Int = 0x057E
let kProductJoyConR: Int = 0x2007
let kNeutralRumble: [UInt8] = [0x00, 0x01, 0x40, 0x40, 0x00, 0x01, 0x40, 0x40]

// MARK: - Global State

var g_device: IOHIDDevice?
var g_packetNum: UInt8 = 0
var g_reportCount: Int = 0
var g_lastBytes = [UInt8](repeating: 0xFF, count: 50)
var g_mcuReady = false
var g_startTime = Date()
let g_reportBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 512)
var g_phase = ""
var g_lastPrintTime = Date()
var g_wasAttached = false
var g_detachedSince: Date? = nil
var g_lastRecoveryAttempt: Date? = nil
let g_recoveryInterval: TimeInterval = 5.0  // Re-init MCU every 5s after detachment

// Track which bytes have ever changed (to find interesting positions)
var g_byteEverChanged = [Bool](repeating: false, count: 50)
var g_minSeen = [UInt8](repeating: 0xFF, count: 50)
var g_maxSeen = [UInt8](repeating: 0x00, count: 50)

// MARK: - CRC8

let g_crc8Table: [UInt8] = {
    var table = [UInt8](repeating: 0, count: 256)
    for i in 0..<256 {
        var crc = UInt8(i)
        for _ in 0..<8 {
            crc = (crc & 0x80 != 0) ? (crc << 1) ^ 0x07 : crc << 1
        }
        table[i] = crc
    }
    return table
}()

func crc8(_ data: [UInt8], from: Int, count: Int) -> UInt8 {
    var crc: UInt8 = 0
    for i in from..<(from + count) {
        crc = g_crc8Table[Int(crc ^ data[i])]
    }
    return crc
}

// MARK: - HID Output

func sendSubcommand(_ subcmd: UInt8, args: [UInt8] = []) {
    guard let device = g_device else { return }

    var report = [UInt8](repeating: 0, count: 49)
    report[0] = 0x01
    report[1] = g_packetNum & 0x0F
    g_packetNum = (g_packetNum &+ 1) & 0x0F

    for i in 0..<8 { report[2 + i] = kNeutralRumble[i] }

    report[10] = subcmd
    for (i, b) in args.enumerated() {
        if 11 + i < report.count { report[11 + i] = b }
    }

    IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(report[0]), report, report.count)
}

func sendMCUConfig(_ bytes: [UInt8]) {
    var arg = [UInt8](repeating: 0, count: 38)
    for (i, b) in bytes.enumerated() {
        if i < 37 { arg[i] = b }
    }
    arg[37] = crc8(arg, from: 1, count: 36)
    sendSubcommand(0x21, args: arg)
}

// MARK: - Input Report Handler

let g_inputCallback: IOHIDReportCallback = { context, result, sender, type, reportID, report, reportLength in
    let len = Int(reportLength)
    guard len >= 1 else { return }

    // Build data array with report ID at [0]
    var data: [UInt8]
    if report[0] == UInt8(reportID) {
        // Buffer already includes report ID
        data = Array(UnsafeBufferPointer(start: report, count: len))
    } else {
        // Prepend report ID
        data = [UInt8(reportID)] + Array(UnsafeBufferPointer(start: report, count: len))
    }

    let rid = data[0]

    // Only process standard (0x30) and MCU (0x31) input reports
    guard rid == 0x30 || rid == 0x31 else {
        // Show subcommand replies briefly during init
        if rid == 0x21 && !g_mcuReady {
            let ack = data.count > 13 ? data[13] : 0
            let sub = data.count > 14 ? data[14] : 0
            let ackStr = (ack & 0x80 != 0) ? "ACK" : "NAK"
            print("  reply: \(ackStr) subcmd=0x\(String(format: "%02X", sub))")
        }
        return
    }

    guard g_mcuReady else { return }

    g_reportCount += 1

    let maxByte = min(data.count, 50)

    // Track changes across all byte positions
    var changedPositions = [Int]()
    for i in 0..<maxByte {
        if g_reportCount > 1 && data[i] != g_lastBytes[i] {
            changedPositions.append(i)
            g_byteEverChanged[i] = true
        }
        if data[i] < g_minSeen[i] { g_minSeen[i] = data[i] }
        if data[i] > g_maxSeen[i] { g_maxSeen[i] = data[i] }
    }

    // Decide whether to print
    let byte40 = maxByte > 40 ? data[40] : 0xFF
    let byte42 = maxByte > 42 ? data[42] : 0xFF
    let attached = byte42 == 0x20
    let byte40Changed = changedPositions.contains(40)
    let byte42Changed = changedPositions.contains(42)
    let now = Date()
    let periodic = now.timeIntervalSince(g_lastPrintTime) >= 1.0
    let earlyReport = g_reportCount <= 5

    let shouldPrint = byte40Changed || byte42Changed || periodic || earlyReport

    if shouldPrint {
        g_lastPrintTime = now

        let elapsed = now.timeIntervalSince(g_startTime)

        // Describe flex position
        let flexDesc: String
        if !attached {
            flexDesc = "---"
        } else if byte40 <= 3 {
            flexDesc = "PULL"
        } else if byte40 >= 7 && byte40 <= 13 {
            flexDesc = "neut"
        } else if byte40 >= 17 {
            flexDesc = "SQZE"
        } else if byte40 < 7 {
            flexDesc = "pull"
        } else {
            flexDesc = "sqze"
        }

        // Format bytes 35-49 with byte 40 and byte 42 highlighted
        var hexParts = [String]()
        for i in 35..<min(50, maxByte) {
            let b = data[i]
            if i == 40 {
                hexParts.append("[\(String(format: "%02X", b))]")
            } else if i == 42 {
                hexParts.append("(\(String(format: "%02X", b)))")
            } else if changedPositions.contains(i) {
                hexParts.append("*\(String(format: "%02X", b))")
            } else {
                hexParts.append(" \(String(format: "%02X", b))")
            }
        }
        let hexStr = hexParts.joined(separator: "")

        let tag: String
        if byte42Changed {
            tag = attached ? "<< RING-CON ATTACHED (b42=0x20)" : "<< RING-CON DETACHED (b42=0x00)"
        } else if byte40Changed {
            tag = "<< flex changed"
        } else if earlyReport {
            tag = ""
        } else {
            tag = "(heartbeat)"
        }

        let presenceStr = attached ? "ON " : "OFF"

        print(String(format: "%7.2fs | #%06d | b40=0x%02X (%2d) | b42=%@ | %@ | %@ %@",
                      elapsed, g_reportCount, byte40, byte40, presenceStr, flexDesc, hexStr, tag))
    }

    // Track attach/detach transitions for recovery
    if attached && !g_wasAttached {
        g_detachedSince = nil
        g_lastRecoveryAttempt = nil
    } else if !attached && g_wasAttached {
        g_detachedSince = now
    }
    g_wasAttached = attached

    // Auto-recovery: re-init MCU periodically while detached
    if !attached && g_detachedSince != nil {
        let lastAttempt = g_lastRecoveryAttempt ?? .distantPast
        if now.timeIntervalSince(lastAttempt) >= g_recoveryInterval {
            g_lastRecoveryAttempt = now
            let elapsed = now.timeIntervalSince(g_startTime)
            print(String(format: "%7.2fs | >>>>>> | Re-initializing MCU to detect Ring-Con re-attachment...", elapsed))
            g_mcuReady = false
            DispatchQueue.global().async {
                initMCU()
            }
        }
    }

    // Store for next comparison
    for i in 0..<maxByte { g_lastBytes[i] = data[i] }
}

// MARK: - MCU Initialization

func initMCU() {
    func step(_ n: Int, _ desc: String) {
        print("  [\(n)/12] \(desc)")
    }

    print("\n--- MCU Initialization ---\n")

    step(1, "Enable IMU")
    sendSubcommand(0x40, args: [0x01])
    Thread.sleep(forTimeInterval: 0.1)

    step(2, "Set IMU sensitivity")
    sendSubcommand(0x41, args: [0x03, 0x00, 0x01, 0x01])
    Thread.sleep(forTimeInterval: 0.1)

    step(3, "Set input mode -> full+IMU (0x30)")
    sendSubcommand(0x03, args: [0x30])
    Thread.sleep(forTimeInterval: 0.1)

    step(4, "Enable MCU")
    sendSubcommand(0x22, args: [0x01])
    Thread.sleep(forTimeInterval: 0.3)

    step(5, "Set input mode again (0x30)")
    sendSubcommand(0x03, args: [0x30])
    Thread.sleep(forTimeInterval: 0.15)

    step(6, "Configure MCU -> Ring-Con mode")
    sendMCUConfig([0x21, 0x00, 0x03])
    Thread.sleep(forTimeInterval: 0.15)

    step(7, "MCU external ready")
    sendMCUConfig([0x21, 0x01, 0x01])
    Thread.sleep(forTimeInterval: 0.15)

    step(8, "Detect Ring-Con (polling...)")
    for _ in 1...30 {
        sendSubcommand(0x59, args: [0x00])
        Thread.sleep(forTimeInterval: 0.05)
    }

    step(9, "Enable Ring-Con IMU")
    sendSubcommand(0x40, args: [0x03])
    Thread.sleep(forTimeInterval: 0.15)

    step(10, "Configure external device")
    var cfg = [UInt8](repeating: 0, count: 38)
    cfg[0] = 0x06; cfg[1] = 0x03; cfg[2] = 0x25; cfg[3] = 0x06
    cfg[8] = 0x1C; cfg[9] = 0x16; cfg[10] = 0xED; cfg[11] = 0x34; cfg[12] = 0x36
    cfg[16] = 0x0A; cfg[17] = 0x64; cfg[18] = 0x0B; cfg[19] = 0xE6
    cfg[20] = 0xA9; cfg[21] = 0x22; cfg[24] = 0x04
    cfg[32] = 0x90; cfg[33] = 0xA8; cfg[34] = 0xE1; cfg[35] = 0x34; cfg[36] = 0x36
    sendSubcommand(0x5C, args: cfg)
    Thread.sleep(forTimeInterval: 0.25)

    step(11, "Start external polling")
    sendSubcommand(0x5A, args: [0x04, 0x01, 0x01, 0x02])
    Thread.sleep(forTimeInterval: 0.15)

    step(12, "Set external config")
    sendSubcommand(0x58, args: [0x04, 0x04, 0x12, 0x02])
    Thread.sleep(forTimeInterval: 0.15)

    g_mcuReady = true
    g_reportCount = 0
    g_startTime = Date()
    g_lastPrintTime = Date()

    print("""

    --- MCU Ready ---

    === LIVE BYTE MONITORING ===

    Instructions:
      1. With Ring-Con ATTACHED: squeeze and pull to see normal values
      2. DETACH the Ring-Con from the Joy-Con rail
      3. Watch what byte 40 does (this is the key question!)
      4. RE-ATTACH the Ring-Con and observe recovery
      5. Press Ctrl-C to quit, then check the summary

    Legend:
      [XX] = byte 40 (flex value), (XX) = byte 42 (presence: 20=attached, 00=detached)
      *XX = changed this frame
      b42: ON = Ring-Con attached (0x20), OFF = detached

       TIME   |  RPT#  | BYTE 40        | B42  | FLEX | BYTES [35-49]
    -----------+--------+----------------+------+------+-------------------------------------------
    """)
}

// MARK: - Summary on Exit

func printSummary() {
    print("\n\n=== BYTE CHANGE SUMMARY (positions 0-49) ===")
    print("Shows which byte positions ever changed, with min/max values seen.\n")
    print("  POS | CHANGED | MIN  | MAX  | NOTES")
    print("  ----+---------+------+------+------")
    for i in 0..<50 {
        if g_byteEverChanged[i] || i == 40 {
            let ch = g_byteEverChanged[i] ? "  YES  " : "  no   "
            let note: String
            switch i {
            case 0: note = "Report ID"
            case 1: note = "Timer"
            case 2: note = "Battery"
            case 3...5: note = "Buttons"
            case 6...11: note = "Stick"
            case 12: note = "Vibrator"
            case 40: note = "<<< RING-CON FLEX BYTE"
            case 42: note = "<<< RING-CON PRESENCE (0x20=attached, 0x00=detached)"
            case 13...48: note = "IMU data"
            default: note = ""
            }
            print(String(format: "   %2d | %@ | 0x%02X | 0x%02X | %@",
                         i, ch, g_minSeen[i], g_maxSeen[i], note))
        }
    }
    print("\nTotal reports processed: \(g_reportCount)")
}

// MARK: - Device Callbacks

let g_matchCallback: IOHIDDeviceCallback = { context, result, sender, device in
    print("Joy-Con (R) found!")
    g_device = device

    IOHIDDeviceRegisterInputReportCallback(device, g_reportBuffer, 512, g_inputCallback, nil)

    DispatchQueue.global().async {
        initMCU()
    }
}

let g_removeCallback: IOHIDDeviceCallback = { context, result, sender, device in
    print("\n!!! Joy-Con DISCONNECTED (Bluetooth HID removed) !!!")
    g_device = nil
    g_mcuReady = false
}

// MARK: - Main

// Handle Ctrl-C to print summary
signal(SIGINT) { _ in
    printSummary()
    exit(0)
}

print("""
=== Ring-Con Byte Profiler ===
Monitor raw Joy-Con HID bytes to understand Ring-Con attach/detach behavior.

IMPORTANT: Close the RingBreak app first (it will conflict with HID access).

Scanning for Joy-Con (R)...
""")

let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

let matching: [String: Any] = [
    kIOHIDVendorIDKey as String: kVendorNintendo,
    kIOHIDProductIDKey as String: kProductJoyConR
]

IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
IOHIDManagerRegisterDeviceMatchingCallback(manager, g_matchCallback, nil)
IOHIDManagerRegisterDeviceRemovalCallback(manager, g_removeCallback, nil)
IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
if openResult != kIOReturnSuccess {
    print("ERROR: Failed to open HID manager (code: \(openResult))")
    print("Make sure RingBreak app is closed and Joy-Con is paired.")
    exit(1)
}

RunLoop.current.run()
