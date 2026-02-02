//
//  Constants.swift
//  RingBreak
//
//  App-wide constants for configuration and thresholds
//

import Foundation
import AppKit

/// Helper to play sounds respecting the user's sound setting
enum SoundHelper {
    static func play(_ name: String) {
        guard UserDefaults.standard.object(forKey: UserDefaultsKeys.soundsEnabled) as? Bool ?? true else { return }
        NSSound(named: NSSound.Name(name))?.play()
    }
}

enum Constants {
    // MARK: - Exercise

    /// Flex value at which the ring is considered "at rest" (neutral).
    /// Below this = idle, above = active effort in squeeze direction.
    /// Pull direction uses 1.0 - this value.
    static let relaxedThreshold: Double = 0.55

    /// Flex value that triggers auto-start countdown from ready state
    static let squeezeStartThreshold: Double = 0.70

    /// Seconds to hold at target for a successful rep
    static let holdDuration: Int = 3

    /// Pre-exercise countdown (3, 2, 1, go)
    static let startCountdown: Int = 3

    /// Default number of reps per session
    static let targetReps: Int = 10

    /// Seconds of struggling before showing "Calibrate pressure?" prompt
    static let calibrationPromptDelay: TimeInterval = 5

    // MARK: - Ring-Con Detection

    /// Consecutive HID reports without presence byte before marking Ring-Con detached
    static let ringConMissedThreshold: Int = 15

    /// Consecutive presence bytes needed before confirming Ring-Con attached
    static let ringConPresentThreshold: Int = 3

    /// Seconds to wait before pausing game on Ring-Con detach (filters brief flapping)
    static let pauseDebounceDuration: TimeInterval = 1.5

    /// Seconds between MCU re-init attempts to detect Ring-Con re-attachment
    static let ringConRecoveryInterval: TimeInterval = 5.0

    // MARK: - Calibration

    /// Seconds to hold neutral position during calibration
    static let calibrationHoldDuration: Int = 5

    /// Seconds to perform pull/squeeze during calibration
    static let calibrationActionDuration: Int = 5

    /// Minimum raw flex range (pull or squeeze) for calibration to be considered valid
    static let calibrationMinRange: Int = 2

    // MARK: - Timers

    /// Menubar update interval in seconds
    static let menubarUpdateInterval: TimeInterval = 60

    /// Notification snooze duration in seconds (30 minutes)
    static let snoozeDuration: TimeInterval = 30 * 60

    // MARK: - URLs

    /// GitHub repository URL
    static let gitHubURL = "https://github.com/yoavf/ringbreak"
}
