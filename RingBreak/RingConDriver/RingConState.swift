//
//  RingConState.swift
//  RingBreak
//
//  State model for Ring-Con flex sensor and Joy-Con connection
//

import Foundation

/// Connection state for the Joy-Con controller
enum ConnectionState: Equatable {
    case disconnected
    case scanning
    case connecting
    case connected
}

/// 3D vector for motion values
struct Vector3: Equatable {
    var x: Double
    var y: Double
    var z: Double

    static let zero = Vector3(x: 0, y: 0, z: 0)

    var magnitude: Double {
        sqrt(x * x + y * y + z * z)
    }
}

/// IMU reading with accelerometer and gyroscope data
struct IMUReading: Equatable {
    var acceleration: Vector3
    var angularVelocity: Vector3
}

/// Orientation derived from IMU data (degrees)
struct Orientation: Equatable {
    var pitch: Double
    var roll: Double
    var yaw: Double

    static let zero = Orientation(pitch: 0, roll: 0, yaw: 0)
}

/// Represents the current state of the Ring-Con flex sensor
struct RingConFlexState {
    /// Raw flex sensor value from the Ring-Con (typically 0x0000-0xFFFF)
    var rawValue: UInt16 = 0x8000  // Neutral position

    /// Calibration offset for neutral position
    var neutralOffset: UInt16 = 0x8000

    /// Maximum squeeze value observed during calibration
    var maxSqueeze: UInt16 = 0xFFFF

    /// Maximum pull value observed during calibration
    var maxPull: UInt16 = 0x0000

    /// Normalized flex value from 0.0 (full pull) to 1.0 (full squeeze)
    var normalizedValue: Double {
        let neutral = Double(neutralOffset)
        let raw = Double(rawValue)

        if raw >= neutral {
            // Squeezing (positive direction)
            let range = Double(maxSqueeze) - neutral
            guard range > 0 else { return 0.5 }
            return 0.5 + ((raw - neutral) / range) * 0.5
        } else {
            // Pulling (negative direction)
            let range = neutral - Double(maxPull)
            guard range > 0 else { return 0.5 }
            return 0.5 - ((neutral - raw) / range) * 0.5
        }
    }

    /// Returns true if the user is actively squeezing
    var isSqueezing: Bool {
        normalizedValue > 0.6
    }

    /// Returns true if the user is actively pulling
    var isPulling: Bool {
        normalizedValue < 0.4
    }
}

/// Joy-Con device type
enum JoyConType: UInt8 {
    case left = 0x01
    case right = 0x02
    case proController = 0x03

    var name: String {
        switch self {
        case .left: return "Joy-Con (L)"
        case .right: return "Joy-Con (R)"
        case .proController: return "Pro Controller"
        }
    }

    /// Only the right Joy-Con supports Ring-Con attachment
    var supportsRingCon: Bool {
        self == .right
    }
}

/// MCU (Microcontroller Unit) state for Ring-Con communication
enum MCUState: Equatable {
    case disabled
    case standby
    case ringConMode
    case error(String)
}

/// Represents the complete state of a connected Joy-Con with Ring-Con
struct JoyConState {
    var type: JoyConType = .right
    var batteryLevel: UInt8 = 0
    var isCharging: Bool = false

    // Button states
    var buttons: JoyConButtons = JoyConButtons()

    // Analog stick state (for Joy-Con R, this is the right stick)
    var stickX: Double = 0.5
    var stickY: Double = 0.5

    // MCU state
    var mcuState: MCUState = .disabled

    // Ring-Con state
    var ringConAttached: Bool = false
    var flexState: RingConFlexState = RingConFlexState()
}

/// Button state for Joy-Con
struct JoyConButtons: Equatable {
    // Face buttons (Joy-Con R)
    var a: Bool = false
    var b: Bool = false
    var x: Bool = false
    var y: Bool = false

    // Shoulder buttons
    var r: Bool = false
    var zr: Bool = false
    var sr: Bool = false
    var sl: Bool = false

    // System buttons
    var plus: Bool = false
    var home: Bool = false
    var stickButton: Bool = false
}
