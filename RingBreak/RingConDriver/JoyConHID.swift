//
//  JoyConHID.swift
//  RingBreak
//
//  Low-level HID communication with Joy-Con controller
//

import Foundation
import IOKit
import IOKit.hid

/// Nintendo vendor and product IDs
enum NintendoHID {
    static let vendorID: Int = 0x057E
    static let productIDJoyConL: Int = 0x2006
    static let productIDJoyConR: Int = 0x2007
    static let productIDProController: Int = 0x2009
}

/// Errors that can occur during HID communication
enum JoyConHIDError: Error, LocalizedError {
    case deviceNotFound
    case openFailed
    case writeFailed
    case readFailed
    case timeout
    case invalidResponse
    case mcuInitFailed(String)

    var errorDescription: String? {
        switch self {
        case .deviceNotFound:
            return "Joy-Con not found. Make sure it's paired via Bluetooth."
        case .openFailed:
            return "Failed to open connection to Joy-Con."
        case .writeFailed:
            return "Failed to send data to Joy-Con."
        case .readFailed:
            return "Failed to read data from Joy-Con."
        case .timeout:
            return "Communication with Joy-Con timed out."
        case .invalidResponse:
            return "Received invalid response from Joy-Con."
        case .mcuInitFailed(let reason):
            return "MCU initialization failed: \(reason)"
        }
    }
}

/// Delegate protocol for receiving Joy-Con HID events
protocol JoyConHIDDelegate: AnyObject {
    func joyConHID(_ hid: JoyConHID, didReceiveInputReport data: [UInt8])
    func joyConHID(_ hid: JoyConHID, didDisconnect error: Error?)
}

/// Low-level HID interface for Joy-Con communication
class JoyConHID {
    weak var delegate: JoyConHIDDelegate?

    private var device: IOHIDDevice?
    private var manager: IOHIDManager?
    private let queue = DispatchQueue(label: "com.fitring.joyconhid", qos: .userInteractive)

    private var reportBuffer = [UInt8](repeating: 0, count: 362)
    private var outputReportBuilder = OutputReportBuilder()

    /// Whether the device is currently connected
    var isConnected: Bool {
        device != nil
    }

    /// The type of connected Joy-Con
    private(set) var deviceType: JoyConType?

    init() {}

    deinit {
        disconnect()
    }

    /// Start scanning for Joy-Con devices
    func startScanning(completion: @escaping (Result<JoyConType, JoyConHIDError>) -> Void) {
        Task { @MainActor in
            DebugLogger.shared.logConnection("Starting scan for Joy-Con devices...")
        }

        queue.async { [weak self] in
            guard let self = self else { return }

            // Create HID manager
            let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
            self.manager = manager

            // Set up matching criteria for Nintendo controllers
            let matchingDicts: [[String: Any]] = [
                [
                    kIOHIDVendorIDKey: NintendoHID.vendorID,
                    kIOHIDProductIDKey: NintendoHID.productIDJoyConR
                ],
                [
                    kIOHIDVendorIDKey: NintendoHID.vendorID,
                    kIOHIDProductIDKey: NintendoHID.productIDJoyConL
                ],
                [
                    kIOHIDVendorIDKey: NintendoHID.vendorID,
                    kIOHIDProductIDKey: NintendoHID.productIDProController
                ]
            ]

            IOHIDManagerSetDeviceMatchingMultiple(manager, matchingDicts as CFArray)

            // Open the manager
            let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            guard openResult == kIOReturnSuccess else {
                Task { @MainActor in
                    DebugLogger.shared.logError("Failed to open HID manager: \(openResult)")
                }
                DispatchQueue.main.async {
                    completion(.failure(.openFailed))
                }
                return
            }

            Task { @MainActor in
                DebugLogger.shared.logConnection("HID manager opened, looking for devices...")
            }

            // Get matching devices
            guard let deviceSet = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>,
                  let device = deviceSet.first else {
                Task { @MainActor in
                    DebugLogger.shared.logError("No Nintendo devices found")
                }
                DispatchQueue.main.async {
                    completion(.failure(.deviceNotFound))
                }
                return
            }

            Task { @MainActor in
                DebugLogger.shared.logConnection("Found \(deviceSet.count) Nintendo device(s)")
            }

            // Determine device type
            let productID = self.getProductID(from: device)
            let deviceType: JoyConType
            switch productID {
            case NintendoHID.productIDJoyConL:
                deviceType = .left
            case NintendoHID.productIDJoyConR:
                deviceType = .right
            case NintendoHID.productIDProController:
                deviceType = .proController
            default:
                DispatchQueue.main.async {
                    completion(.failure(.deviceNotFound))
                }
                return
            }

            // Open the device
            let deviceOpenResult = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
            guard deviceOpenResult == kIOReturnSuccess else {
                DispatchQueue.main.async {
                    completion(.failure(.openFailed))
                }
                return
            }

            self.device = device
            self.deviceType = deviceType

            Task { @MainActor in
                DebugLogger.shared.logConnection("Device opened: \(deviceType.name) (0x\(String(format: "%04X", productID)))")
            }

            // Register input report callback
            self.registerInputReportCallback()

            // Schedule on the MAIN run loop so callbacks work
            guard let mainRunLoop = CFRunLoopGetMain() else {
                Task { @MainActor in
                    DebugLogger.shared.logError("Failed to get main run loop")
                }
                DispatchQueue.main.async {
                    completion(.failure(.openFailed))
                }
                return
            }
            IOHIDDeviceScheduleWithRunLoop(device, mainRunLoop, CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerScheduleWithRunLoop(manager, mainRunLoop, CFRunLoopMode.defaultMode.rawValue)

            Task { @MainActor in
                DebugLogger.shared.logConnection("HID callback registered on main run loop")
            }

            DispatchQueue.main.async {
                completion(.success(deviceType))
            }
        }
    }

    /// Disconnect from the Joy-Con
    func disconnect() {
        queue.async { [weak self] in
            guard let self = self else { return }

            if let device = self.device {
                IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
            }

            if let manager = self.manager {
                IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            }

            self.device = nil
            self.manager = nil
            self.deviceType = nil
        }
    }

    /// Send a raw output report to the Joy-Con
    func sendOutputReport(_ data: [UInt8]) throws {
        guard let device = device else {
            throw JoyConHIDError.deviceNotFound
        }

        let result = data.withUnsafeBufferPointer { ptr in
            IOHIDDeviceSetReport(
                device,
                kIOHIDReportTypeOutput,
                CFIndex(data[0]),
                ptr.baseAddress!,
                data.count
            )
        }

        guard result == kIOReturnSuccess else {
            throw JoyConHIDError.writeFailed
        }
    }

    /// Send a subcommand and wait for response
    func sendSubcommand(_ subcommand: Subcommand, argument: [UInt8] = []) async throws -> [UInt8] {
        let report = outputReportBuilder.buildSubcommandReport(subcommand: subcommand, argument: argument)

        // Log what we're sending
        let argHex = argument.prefix(10).map { String(format: "%02X", $0) }.joined(separator: " ")
        Task { @MainActor in
            DebugLogger.shared.log("TX: subcmd=0x\(String(format: "%02X", subcommand.rawValue)) args=[\(argHex)]", category: .hid)
        }

        try sendOutputReport(report)

        // Wait for response
        try await Task.sleep(nanoseconds: 50_000_000)  // 50ms

        return reportBuffer
    }

    /// Set the input report mode
    func setInputReportMode(_ mode: InputReportMode) async throws {
        _ = try await sendSubcommand(.setInputReportMode, argument: [mode.rawValue])
    }

    /// Enable the IMU (accelerometer/gyroscope)
    func enableIMU() async throws {
        _ = try await sendSubcommand(.enableIMU, argument: [0x01])
    }

    /// Set IMU sensitivity (gyro and accel ranges + filters)
    func setIMUSensitivity(gyro: UInt8, accel: UInt8, gyroPerformance: UInt8, accelFilter: UInt8) async throws {
        _ = try await sendSubcommand(.setIMUSensitivity, argument: [gyro, accel, gyroPerformance, accelFilter])
    }

    /// Enable the MCU
    func enableMCU() async throws {
        // Step 1: Enable MCU hardware
        Task { @MainActor in
            DebugLogger.shared.log("MCU Enable: Sending 0x22 with 0x01", category: .mcu)
        }
        _ = try await sendSubcommand(.setMCUState, argument: [0x01])
        try await Task.sleep(nanoseconds: 200_000_000)  // 200ms for MCU to initialize

        // Step 2: Resume MCU and start data streaming
        // 0x21 argument tells MCU to start outputting data to input reports
        Task { @MainActor in
            DebugLogger.shared.log("MCU Resume: Sending 0x22 with 0x21", category: .mcu)
        }
        _ = try await sendSubcommand(.setMCUState, argument: [0x21])
        try await Task.sleep(nanoseconds: 200_000_000)
    }

    /// Configure MCU for Ring-Con mode
    /// Based on exact sequence from Ringcon-Driver project
    func configureRingConMode() async throws {
        Task { @MainActor in
            DebugLogger.shared.log("=== MCU Configuration for Ring-Con (from Ringcon-Driver) ===", category: .mcu)
        }

        // Step 1: Set MCU mode to Ring-Con (mode 3)
        // MCU payload format: [0]=0x21, [1]=mode_param, [2]=mode, CRC at [37]
        Task { @MainActor in
            DebugLogger.shared.log("Step 1: Set MCU to Ring-Con mode (21 21 00 03)", category: .mcu)
        }
        var mcuCmd1 = [UInt8](repeating: 0, count: 38)
        mcuCmd1[0] = 0x21   // MCU command
        mcuCmd1[1] = 0x00   // Mode param
        mcuCmd1[2] = 0x03   // Mode 3 = Ring-Con
        mcuCmd1[37] = CRC8.calculate(Array(mcuCmd1[1..<37]))  // CRC over bytes 1-36
        _ = try await sendSubcommand(.setMCUConfig, argument: mcuCmd1)
        try await Task.sleep(nanoseconds: 200_000_000)

        // Step 2: Set MCU to external ready state (21 21 01 01)
        Task { @MainActor in
            DebugLogger.shared.log("Step 2: Set MCU to external ready (21 21 01 01)", category: .mcu)
        }
        var mcuCmd2 = [UInt8](repeating: 0, count: 38)
        mcuCmd2[0] = 0x21
        mcuCmd2[1] = 0x01
        mcuCmd2[2] = 0x01
        mcuCmd2[37] = CRC8.calculate(Array(mcuCmd2[1..<37]))
        _ = try await sendSubcommand(.setMCUConfig, argument: mcuCmd2)
        try await Task.sleep(nanoseconds: 200_000_000)

        // Step 3: Get external device data (subcommand 0x59)
        // Wait for Ring-Con detection - Ringcon-Driver checks buf[16] == 0x20
        Task { @MainActor in
            DebugLogger.shared.log("Step 3: Detecting Ring-Con (0x59)...", category: .mcu)
        }
        var ringConDetected = false
        for attempt in 1...30 {  // More attempts, Ring-Con needs time
            let response = try await sendSubcommand(0x59, argument: [0x00])
            try await Task.sleep(nanoseconds: 50_000_000)  // 50ms between attempts

            // Check response - Ring-Con detected when byte 16 == 0x20
            // Response format: [0]=0x21, [13]=ACK, [14]=subcmd, [15+]=reply data
            // So byte 16 is reply[1]
            if response.count > 16 {
                let detectionByte = response[16]
                Task { @MainActor in
                    DebugLogger.shared.log("  Attempt \(attempt): response[16]=0x\(String(format: "%02X", detectionByte))", category: .mcu)
                }
                if detectionByte == 0x20 {
                    ringConDetected = true
                    Task { @MainActor in
                        DebugLogger.shared.log("  Ring-Con DETECTED at attempt \(attempt)!", category: .mcu)
                    }
                    break
                }
            }
        }

        if !ringConDetected {
            Task { @MainActor in
                DebugLogger.shared.log("WARNING: Ring-Con not detected after 30 attempts, continuing anyway...", category: .mcu)
            }
        }

        // Step 3.5: Enable Ring-Con IMU mode (subcommand 0x40 with arg 0x03)
        // From Ringcon-Driver: buf[0] = 0x03; send_subcommand(0x01, 0x40, buf, 1);
        Task { @MainActor in
            DebugLogger.shared.log("Step 3.5: Enable Ring-Con IMU (0x40, arg=0x03)", category: .mcu)
        }
        _ = try await sendSubcommand(0x40, argument: [0x03])
        try await Task.sleep(nanoseconds: 100_000_000)

        // Step 4: Configure external device (subcommand 0x5C)
        // This sets up Ring-Con with specific parameters
        Task { @MainActor in
            DebugLogger.shared.log("Step 4: Configure external device (0x5C)", category: .mcu)
        }
        var configData = [UInt8](repeating: 0, count: 38)
        configData[0] = 0x06
        configData[1] = 0x03
        configData[2] = 0x25
        configData[3] = 0x06
        configData[8] = 0x1C
        configData[9] = 0x16
        configData[10] = 0xED
        configData[11] = 0x34
        configData[12] = 0x36
        configData[16] = 0x0A  // timestamp bytes
        configData[17] = 0x64
        configData[18] = 0x0B
        configData[19] = 0xE6
        configData[20] = 0xA9
        configData[21] = 0x22
        configData[24] = 0x04
        configData[32] = 0x90
        configData[33] = 0xA8
        configData[34] = 0xE1
        configData[35] = 0x34
        configData[36] = 0x36
        _ = try await sendSubcommand(0x5C, argument: configData)
        try await Task.sleep(nanoseconds: 200_000_000)

        // Step 5: Start external polling (subcommand 0x5A)
        Task { @MainActor in
            DebugLogger.shared.log("Step 5: Start external polling (0x5A)", category: .mcu)
        }
        _ = try await sendSubcommand(0x5A, argument: [0x04, 0x01, 0x01, 0x02])
        try await Task.sleep(nanoseconds: 100_000_000)

        // Step 6: Set external config (subcommand 0x58)
        Task { @MainActor in
            DebugLogger.shared.log("Step 6: Set external config (0x58)", category: .mcu)
        }
        _ = try await sendSubcommand(0x58, argument: [0x04, 0x04, 0x12, 0x02])
        try await Task.sleep(nanoseconds: 100_000_000)

        Task { @MainActor in
            DebugLogger.shared.log("=== MCU Configuration Complete ===", category: .mcu)
        }
    }

    /// Send a subcommand with numeric ID (for subcommands not in enum)
    func sendSubcommand(_ subcommandID: UInt8, argument: [UInt8]) async throws -> [UInt8] {
        let report = outputReportBuilder.buildSubcommandReportRaw(subcommandID: subcommandID, argument: argument)

        let argHex = argument.prefix(10).map { String(format: "%02X", $0) }.joined(separator: " ")
        Task { @MainActor in
            DebugLogger.shared.log("TX: subcmd=0x\(String(format: "%02X", subcommandID)) args=[\(argHex)]", category: .hid)
        }

        try sendOutputReport(report)
        try await Task.sleep(nanoseconds: 50_000_000)

        return reportBuffer
    }

    /// Start Ring-Con data polling (continuous polling request)
    func startRingConPolling() async throws {
        Task { @MainActor in
            DebugLogger.shared.log("Starting continuous polling for Ring-Con data", category: .mcu)
        }

        // Send multiple polling requests to ensure Ring-Con is detected
        for i in 1...3 {
            var pollCmd = [UInt8](repeating: 0, count: 38)
            // Command 0x02 = Request/poll for data
            // With different sub-types to try to activate Ring-Con
            pollCmd[0] = 0x02
            pollCmd[1] = UInt8(i)  // Try different polling types
            pollCmd[37] = CRC8.calculate(Array(pollCmd[1..<37]))

            Task { @MainActor in
                DebugLogger.shared.log("Poll request \(i) with type \(i)", category: .mcu)
            }
            _ = try await sendSubcommand(.setMCUConfig, argument: pollCmd)
            try await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    // MARK: - Private Methods

    private func getProductID(from device: IOHIDDevice) -> Int {
        guard let productID = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int else {
            return 0
        }
        return productID
    }

    private func registerInputReportCallback() {
        guard let device = device else { return }

        let context = Unmanaged.passUnretained(self).toOpaque()

        IOHIDDeviceRegisterInputReportCallback(
            device,
            &reportBuffer,
            reportBuffer.count,
            { context, result, sender, type, reportID, report, reportLength in
                guard let context = context else { return }
                let hid = Unmanaged<JoyConHID>.fromOpaque(context).takeUnretainedValue()

                if result == kIOReturnSuccess {
                    let data = Array(UnsafeBufferPointer(start: report, count: reportLength))

                    // Single dispatch to main thread for both logging and processing
                    DispatchQueue.main.async {
                        DebugLogger.shared.logHIDReport(data)
                        hid.delegate?.joyConHID(hid, didReceiveInputReport: data)
                    }
                } else {
                    DispatchQueue.main.async {
                        DebugLogger.shared.logError("HID report callback error: \(result)")
                    }
                }
            },
            context
        )
    }
}

// MARK: - Device Enumeration Helper

extension JoyConHID {
    /// List all connected Nintendo controllers
    static func listConnectedDevices() -> [(name: String, productID: Int)] {
        var devices: [(String, Int)] = []

        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

        let matchingDict: [String: Any] = [
            kIOHIDVendorIDKey: NintendoHID.vendorID
        ]

        IOHIDManagerSetDeviceMatching(manager, matchingDict as CFDictionary)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))

        if let deviceSet = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> {
            for device in deviceSet {
                if let name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String,
                   let productID = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int {
                    devices.append((name, productID))
                }
            }
        }

        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))

        return devices
    }
}
