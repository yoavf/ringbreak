//
//  UserDefaultsKeys.swift
//  RingBreak
//
//  Centralized UserDefaults keys to avoid duplication
//

import Foundation

enum UserDefaultsKeys {
    // MARK: - Game State
    static let dailyStreak = "breakGame.dailyStreak"
    static let lastExerciseDate = "breakGame.lastExerciseDate"
    static let sessionsToday = "breakGame.sessionsToday"
    static let sessionsTodayDate = "breakGame.sessionsTodayDate"
    static let sessionsThisWeek = "breakGame.sessionsThisWeek"
    static let weekStartDate = "breakGame.weekStartDate"
    static let difficulty = "breakGame.difficulty"
    static let dailyHistory = "breakGame.dailyHistory"

    // MARK: - Notifications
    static let notificationsEnabled = "notifications.isEnabled"
    static let notificationInterval = "notifications.interval"

    // MARK: - App Settings
    static let hasCompletedOnboarding = "hasCompletedOnboarding"
    static let showMenubarIcon = "settings.showMenubarIcon"
    static let showDockIcon = "settings.showDockIcon"
    static let soundsEnabled = "settings.soundsEnabled"
}
