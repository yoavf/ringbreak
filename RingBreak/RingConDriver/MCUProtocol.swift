//
//  MCUProtocol.swift
//  RingBreak
//
//  Protocol definitions for Joy-Con MCU communication
//  Based on reverse-engineering from Ringcon-Driver and joytk projects
//

import Foundation

/// HID report IDs for Joy-Con communication
enum HIDReportID: UInt8 {
    /// Standard input report with button/stick data (50 bytes)
    case standardInput = 0x30

    /// Input report with MCU data (362 bytes)
    case mcuInput = 0x31

    /// Rumble and subcommand output report
    case rumbleSubcommand = 0x01

    /// Rumble only output report
    case rumbleOnly = 0x10

    /// Request specific input report type
    case requestReport = 0x1F
}

/// Subcommand IDs for Joy-Con configuration
enum Subcommand: UInt8 {
    /// Get controller state
    case getState = 0x00

    /// Request device info (firmware, type, MAC)
    case requestDeviceInfo = 0x02

    /// Set input report mode
    case setInputReportMode = 0x03

    /// Set HCI state (for pairing)
    case setHCIState = 0x06

    /// SPI flash read
    case spiFlashRead = 0x10

    /// Set player lights
    case setPlayerLights = 0x30

    /// Get player lights
    case getPlayerLights = 0x31

    /// Set home light
    case setHomeLight = 0x38

    /// Enable IMU
    case enableIMU = 0x40

    /// Set IMU sensitivity
    case setIMUSensitivity = 0x41

    /// Enable vibration
    case enableVibration = 0x48

    /// Get regulated voltage
    case getVoltage = 0x50

    /// Set MCU configuration (for Ring-Con)
    case setMCUConfig = 0x21

    /// Set MCU state
    case setMCUState = 0x22
}

/// Input report modes
enum InputReportMode: UInt8 {
    /// Standard mode (0x3F reports)
    case standard = 0x3F

    /// Full mode with IMU data (0x30 reports)
    case fullWithIMU = 0x30

    /// MCU update state mode (0x31 reports)
    case mcuUpdateState = 0x31
}

/// MCU command types
enum MCUCommand: UInt8 {
    /// Set MCU mode
    case setMode = 0x21

    /// Configure MCU
    case configure = 0x22

    /// Read MCU data
    case readData = 0x23

    /// Write MCU data
    case writeData = 0x24
}

/// MCU modes
enum MCUMode: UInt8 {
    /// MCU is suspended/standby
    case standby = 0x01

    /// NFC mode
    case nfc = 0x04

    /// IR camera mode
    case ir = 0x05

    /// Ring-Con mode (external device polling)
    case ringCon = 0x17  // 23 in decimal
}

/// CRC-8 calculation for MCU commands (polynomial 0x07)
struct CRC8 {
    static let table: [UInt8] = {
        var table = [UInt8](repeating: 0, count: 256)
        for i in 0..<256 {
            var crc = UInt8(i)
            for _ in 0..<8 {
                if crc & 0x80 != 0 {
                    crc = (crc << 1) ^ 0x07
                } else {
                    crc <<= 1
                }
            }
            table[i] = crc
        }
        return table
    }()

    static func calculate(_ data: [UInt8]) -> UInt8 {
        var crc: UInt8 = 0
        for byte in data {
            crc = table[Int(crc ^ byte)]
        }
        return crc
    }
}

/// Builder for Joy-Con output reports
struct OutputReportBuilder {
    private var data: [UInt8]
    private var globalPacketNumber: UInt8 = 0

    init() {
        data = [UInt8](repeating: 0, count: 49)
    }

    /// Create a rumble + subcommand report
    mutating func buildSubcommandReport(subcommand: Subcommand, argument: [UInt8] = []) -> [UInt8] {
        data = [UInt8](repeating: 0, count: 49)
        data[0] = HIDReportID.rumbleSubcommand.rawValue
        data[1] = globalPacketNumber
        globalPacketNumber = (globalPacketNumber + 1) & 0x0F

        // Neutral rumble data (bytes 2-9)
        data[2] = 0x00
        data[3] = 0x01
        data[4] = 0x40
        data[5] = 0x40
        data[6] = 0x00
        data[7] = 0x01
        data[8] = 0x40
        data[9] = 0x40

        // Subcommand
        data[10] = subcommand.rawValue

        // Subcommand arguments
        for (i, byte) in argument.prefix(38).enumerated() {
            data[11 + i] = byte
        }

        return data
    }

    /// Create a rumble + subcommand report with raw subcommand ID
    mutating func buildSubcommandReportRaw(subcommandID: UInt8, argument: [UInt8] = []) -> [UInt8] {
        data = [UInt8](repeating: 0, count: 49)
        data[0] = HIDReportID.rumbleSubcommand.rawValue
        data[1] = globalPacketNumber
        globalPacketNumber = (globalPacketNumber + 1) & 0x0F

        // Neutral rumble data (bytes 2-9)
        data[2] = 0x00
        data[3] = 0x01
        data[4] = 0x40
        data[5] = 0x40
        data[6] = 0x00
        data[7] = 0x01
        data[8] = 0x40
        data[9] = 0x40

        // Subcommand
        data[10] = subcommandID

        // Subcommand arguments
        for (i, byte) in argument.prefix(38).enumerated() {
            data[11 + i] = byte
        }

        return data
    }

    /// Create an MCU command report
    mutating func buildMCUCommandReport(command: MCUCommand, subcommand: UInt8, argument: [UInt8] = []) -> [UInt8] {
        var mcuData = [UInt8](repeating: 0, count: 38)
        mcuData[0] = command.rawValue
        mcuData[1] = subcommand

        for (i, byte) in argument.prefix(35).enumerated() {
            mcuData[2 + i] = byte
        }

        // Calculate CRC
        mcuData[37] = CRC8.calculate(Array(mcuData[0..<37]))

        return buildSubcommandReport(subcommand: .setMCUConfig, argument: mcuData)
    }
}

/// Parser for Joy-Con input reports
struct InputReportParser {
    /// Parse button state from standard input report
    static func parseButtons(from data: [UInt8], offset: Int = 0) -> JoyConButtons {
        guard data.count > offset + 2 else {
            return JoyConButtons()
        }

        let byte1 = data[offset]
        let byte2 = data[offset + 1]
        _ = data[offset + 2]  // byte3 reserved for future use

        return JoyConButtons(
            a: (byte1 & 0x08) != 0,
            b: (byte1 & 0x04) != 0,
            x: (byte1 & 0x02) != 0,
            y: (byte1 & 0x01) != 0,
            r: (byte1 & 0x40) != 0,
            zr: (byte1 & 0x80) != 0,
            sr: (byte2 & 0x10) != 0,
            sl: (byte2 & 0x20) != 0,
            plus: (byte2 & 0x02) != 0,
            home: (byte2 & 0x10) != 0,
            stickButton: (byte2 & 0x08) != 0
        )
    }

    /// Parse analog stick from standard input report (12-bit values)
    static func parseStick(from data: [UInt8], offset: Int) -> (x: Double, y: Double) {
        guard data.count > offset + 2 else {
            return (0.5, 0.5)
        }

        // Stick data is packed: [X low, X high | Y low, Y high]
        let xRaw = UInt16(data[offset]) | ((UInt16(data[offset + 1]) & 0x0F) << 8)
        let yRaw = (UInt16(data[offset + 1]) >> 4) | (UInt16(data[offset + 2]) << 4)

        // Normalize to 0.0-1.0 range (12-bit values, 0-4095)
        return (Double(xRaw) / 4095.0, Double(yRaw) / 4095.0)
    }

    /// Parse Ring-Con flex value from MCU report (0x31 input report)
    /// Based on reverse engineering from Ringcon-Driver and joy/joytk projects
    static func parseRingConFlex(from data: [UInt8]) -> UInt16? {
        // MCU report format (0x31):
        // [0]    = Report ID (0x31)
        // [1]    = Timer/packet counter
        // [2]    = Battery + connection info
        // [3-5]  = Button state
        // [6-11] = Analog stick data
        // [12]   = Vibrator input report
        // [13-48] = IMU data (6-axis, 3 frames)
        // [49+]  = MCU data (up to 313 bytes)
        //
        // Ring-Con MCU data format:
        // The flex sensor value is a 16-bit signed integer
        // Neutral position is around 0x0000
        // Squeeze gives positive values, pull gives negative values

        guard data.count >= 52 else { return nil }

        // MCU data starts at offset 49 in 0x31 reports
        let mcuOffset = 49

        // Check for valid MCU report marker
        // Ring-Con data has a specific format after MCU initialization
        guard data.count > mcuOffset + 3 else { return nil }

        // Try multiple known offsets for Ring-Con flex data
        // Different firmware versions may use different layouts
        let possibleOffsets = [mcuOffset + 0, mcuOffset + 2, 40, 38]

        for offset in possibleOffsets {
            guard data.count > offset + 1 else { continue }

            let flexValue = UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)

            // Valid flex values should be within a reasonable range
            // Ring-Con typically reports values around 0x8000 (neutral) ± 0x3000
            if flexValue >= 0x2000 && flexValue <= 0xE000 {
                return flexValue
            }
        }

        // Fallback: try the standard offset
        let fallbackOffset = 40
        guard data.count > fallbackOffset + 1 else { return nil }
        return UInt16(data[fallbackOffset]) | (UInt16(data[fallbackOffset + 1]) << 8)
    }

    /// Check if MCU report contains Ring-Con data
    static func containsRingConData(in data: [UInt8]) -> Bool {
        guard data.count >= 50 else { return false }

        // Check report type
        guard data[0] == HIDReportID.mcuInput.rawValue else { return false }

        // MCU reports with Ring-Con data should have sufficient length
        return data.count >= 52
    }

    /// Parse IMU samples (3 frames) from input report (0x30/0x31)
    /// Returns accelerometer (g) and gyroscope (deg/s) readings
    static func parseIMUSamples(from data: [UInt8]) -> [IMUReading] {
        // IMU data starts at byte 13 and consists of 3 frames of 12 bytes:
        // [axL, axH, ayL, ayH, azL, azH, gxL, gxH, gyL, gyH, gzL, gzH]
        let imuOffset = 13
        let frameSize = 12
        let frameCount = 3
        guard data.count >= imuOffset + frameSize * frameCount else { return [] }

        return (0..<frameCount).compactMap { frame in
            let base = imuOffset + frame * frameSize
            guard data.count >= base + frameSize else { return nil }

            let ax = Int16(bitPattern: UInt16(data[base]) | (UInt16(data[base + 1]) << 8))
            let ay = Int16(bitPattern: UInt16(data[base + 2]) | (UInt16(data[base + 3]) << 8))
            let az = Int16(bitPattern: UInt16(data[base + 4]) | (UInt16(data[base + 5]) << 8))
            let gx = Int16(bitPattern: UInt16(data[base + 6]) | (UInt16(data[base + 7]) << 8))
            let gy = Int16(bitPattern: UInt16(data[base + 8]) | (UInt16(data[base + 9]) << 8))
            let gz = Int16(bitPattern: UInt16(data[base + 10]) | (UInt16(data[base + 11]) << 8))

            let accelScale = 1.0 / 4096.0
            let gyroScale = 1.0 / 16.4

            let acceleration = Vector3(
                x: Double(ax) * accelScale,
                y: Double(ay) * accelScale,
                z: Double(az) * accelScale
            )
            let angularVelocity = Vector3(
                x: Double(gx) * gyroScale,
                y: Double(gy) * gyroScale,
                z: Double(gz) * gyroScale
            )

            return IMUReading(acceleration: acceleration, angularVelocity: angularVelocity)
        }
    }

    // Raw IMU frames parser removed; using calibrated single-frame parsing in RingConManager.

    /// Parse the MCU state from subcommand reply
    static func parseMCUState(from data: [UInt8]) -> MCUState {
        guard data.count >= 16 else { return .disabled }

        // Subcommand reply format:
        // [0] = Report ID
        // [13] = Subcommand reply ID
        // [14] = ACK byte (0x80 = success)
        // [15+] = Reply data

        guard data[14] & 0x80 != 0 else {
            return .error("MCU command failed")
        }

        // Check MCU mode in reply
        if data.count >= 17 {
            switch data[16] {
            case 0x00: return .standby
            case 0x01: return .standby // NFC/IR standby
            case 0x03: return .ringConMode
            default: return .standby
            }
        }

        return .standby
    }

    /// Parse battery level from input report
    static func parseBattery(from data: [UInt8]) -> (level: UInt8, charging: Bool) {
        guard data.count > 2 else {
            return (0, false)
        }

        let batteryByte = data[2]
        let level = (batteryByte >> 4) & 0x0F  // High nibble is battery level
        let charging = (batteryByte & 0x10) != 0

        return (level, charging)
    }
}

/// Sequence for initializing Ring-Con MCU mode
struct RingConInitSequence {
    /// Commands to send in order to enable Ring-Con mode
    static var commands: [(description: String, builder: (inout OutputReportBuilder) -> [UInt8])] {
        return [
            ("Enable MCU", { builder in
                builder.buildSubcommandReport(subcommand: .setMCUState, argument: [0x01])
            }),
            ("Configure MCU for Ring-Con", { builder in
                builder.buildMCUCommandReport(command: .setMode, subcommand: MCUMode.ringCon.rawValue)
            }),
            ("Request Ring-Con data", { builder in
                builder.buildMCUCommandReport(command: .configure, subcommand: 0x02, argument: [0x00])
            })
        ]
    }
}
