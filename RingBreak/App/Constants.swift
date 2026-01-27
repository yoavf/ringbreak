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
    // MARK: - Exercise Detection

    /// Flex value threshold for detecting the start of activity (above neutral)
    static let activityStartThreshold: Double = 0.55

    /// Flex value threshold for squeeze detection trigger in ready state
    static let squeezeStartThreshold: Double = 0.70

    /// Duration in seconds to hold at target for a successful rep
    static let holdDuration: Int = 3

    /// Seconds of failed attempts before showing calibration prompt
    static let calibrationPromptDelay: TimeInterval = 8

    // MARK: - Timers

    /// Menubar update interval in seconds
    static let menubarUpdateInterval: TimeInterval = 60

    /// Notification snooze duration in seconds (30 minutes)
    static let snoozeDuration: TimeInterval = 30 * 60

    // MARK: - Rep Detection Debounce

    /// Minimum time between reps to prevent double-counting
    static let repDebounceInterval: TimeInterval = 0.3

    // MARK: - URLs

    /// GitHub repository URL
    static let gitHubURL = "https://github.com/yoavf/ringbreak"
}
