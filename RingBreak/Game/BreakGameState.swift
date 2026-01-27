//
//  BreakGameState.swift
//  RingBreak
//
//  State machine for the Ring Break desk exercise game
//

import Foundation
import Combine
import AppKit

// Notification posted when a session is completed
extension Notification.Name {
    static let sessionCompleted = Notification.Name("com.ringbreak.sessionCompleted")
}

/// Game phases for the break exercise
enum BreakGamePhase: Equatable {
    case notConnected
    case ready
    case squeezePhase
    case pullPhase
    case celebration
}

/// Difficulty levels for the game
enum GameDifficulty: String, CaseIterable, Identifiable {
    case easy = "Easy"
    case medium = "Medium"
    case hard = "Hard"

    var id: String { rawValue }

    /// Target flex value threshold to reach for a successful rep
    var targetThreshold: Double {
        switch self {
        case .easy: return 0.65
        case .medium: return 0.75
        case .hard: return 0.80
        }
    }

    /// How much the flex value can drop while holding and still count
    var holdTolerance: Double {
        switch self {
        case .easy: return 0.18
        case .medium: return 0.13
        case .hard: return 0.08
        }
    }

    var description: String {
        switch self {
        case .easy: return "Lower squeeze/pull target, more forgiving holds"
        case .medium: return "Balanced challenge for regular use"
        case .hard: return "Higher targets, requires precise holds"
        }
    }
}

/// Manages the Ring Break game state, rep detection, and persistence
@MainActor
class BreakGameState: ObservableObject {
    // MARK: - Published Properties

    @Published private(set) var phase: BreakGamePhase = .notConnected
    @Published private(set) var currentReps: Int = 0
    @Published private(set) var targetReps: Int = 10
    @Published private(set) var totalProgress: Double = 0
    @Published var difficulty: GameDifficulty = .medium {
        didSet {
            UserDefaults.standard.set(difficulty.rawValue, forKey: UserDefaultsKeys.difficulty)
        }
    }

    // Stats
    @Published private(set) var dailyStreak: Int = 0
    @Published private(set) var sessionsToday: Int = 0
    @Published private(set) var sessionsThisWeek: Int = 0
    @Published private(set) var dailyHistory: [Date: Int] = [:]

    // MARK: - Initialization

    init() {
        loadStats()
        loadDifficulty()
    }

    private func loadDifficulty() {
        if let savedDifficulty = UserDefaults.standard.string(forKey: UserDefaultsKeys.difficulty),
           let difficulty = GameDifficulty(rawValue: savedDifficulty) {
            self.difficulty = difficulty
        }
    }

    // MARK: - Public Methods

    /// Update the game state based on connection status
    func updateConnectionStatus(isConnected: Bool, ringConAttached: Bool) {
        if !isConnected || !ringConAttached {
            if phase != .notConnected {
                phase = .notConnected
            }
        } else if phase == .notConnected {
            phase = .ready
        }
    }

    /// Start a new exercise session
    func startExercise() {
        guard phase == .ready || phase == .celebration else { return }

        phase = .squeezePhase
        currentReps = 0
        totalProgress = 0
    }

    /// Reset to ready state
    func reset() {
        phase = .ready
        currentReps = 0
        totalProgress = 0
    }

    /// Return to home/ready state (can be called at any time)
    func returnToHome() {
        phase = .ready
        currentReps = 0
        totalProgress = 0
    }

    /// Increment rep counter (called from view when hold target is hit)
    func incrementRep() {
        currentReps += 1

        // Update progress (single unified progress bar)
        totalProgress = Double(currentReps) / Double(targetReps)

        // Check if exercise complete
        if currentReps >= targetReps {
            // All reps done - celebrate!
            totalProgress = 1.0
            recordCompletedSession()
            playCelebrationSound()
            phase = .celebration
        } else {
            // Alternate between squeeze and pull
            if phase == .squeezePhase {
                phase = .pullPhase
            } else {
                phase = .squeezePhase
            }
        }
    }

    // MARK: - Persistence

    private func loadStats() {
        let defaults = UserDefaults.standard
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Load streak
        dailyStreak = defaults.integer(forKey: UserDefaultsKeys.dailyStreak)

        // Check if streak should reset (missed a day)
        if let lastDate = defaults.object(forKey: UserDefaultsKeys.lastExerciseDate) as? Date {
            let lastDay = calendar.startOfDay(for: lastDate)
            let daysBetween = calendar.dateComponents([.day], from: lastDay, to: today).day ?? 0

            if daysBetween > 1 {
                // Missed a day, reset streak
                dailyStreak = 0
                defaults.set(0, forKey: UserDefaultsKeys.dailyStreak)
            }
        }

        // Load sessions today
        if let sessionDate = defaults.object(forKey: UserDefaultsKeys.sessionsTodayDate) as? Date {
            let sessionDay = calendar.startOfDay(for: sessionDate)
            if sessionDay == today {
                sessionsToday = defaults.integer(forKey: UserDefaultsKeys.sessionsToday)
            } else {
                sessionsToday = 0
            }
        }

        // Load sessions this week
        let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today))!
        if let storedWeekStart = defaults.object(forKey: UserDefaultsKeys.weekStartDate) as? Date {
            if calendar.isDate(storedWeekStart, inSameDayAs: weekStart) {
                sessionsThisWeek = defaults.integer(forKey: UserDefaultsKeys.sessionsThisWeek)
            } else {
                sessionsThisWeek = 0
            }
        }

        // Load daily history
        loadDailyHistory()

        // Sync sessionsToday into dailyHistory (in case of format mismatch from old data)
        if sessionsToday > 0 {
            dailyHistory[today] = sessionsToday
        }
    }

    private func loadDailyHistory() {
        let defaults = UserDefaults.standard
        guard let historyData = defaults.dictionary(forKey: UserDefaultsKeys.dailyHistory) as? [String: Int] else {
            dailyHistory = [:]
            return
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        let calendar = Calendar.current

        dailyHistory = historyData.compactMapValues { $0 }.reduce(into: [Date: Int]()) { result, pair in
            if let date = formatter.date(from: pair.key) {
                let normalizedDate = calendar.startOfDay(for: date)
                result[normalizedDate] = pair.value
            }
        }
    }

    private func saveDailyHistory() {
        let defaults = UserDefaults.standard
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current

        let historyData = dailyHistory.reduce(into: [String: Int]()) { result, pair in
            let dateString = formatter.string(from: pair.key)
            result[dateString] = pair.value
        }

        defaults.set(historyData, forKey: UserDefaultsKeys.dailyHistory)
    }

    /// Returns rep counts for the last N days (including today), sorted chronologically
    func getRecentHistory(days: Int = 7) -> [(date: Date, reps: Int)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        var result: [(date: Date, reps: Int)] = []

        for dayOffset in (0..<days).reversed() {
            if let date = calendar.date(byAdding: .day, value: -dayOffset, to: today) {
                let reps = dailyHistory[date] ?? 0
                result.append((date: date, reps: reps))
            }
        }

        return result
    }

    private func recordCompletedSession() {
        let defaults = UserDefaults.standard
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Update sessions today
        sessionsToday += 1
        defaults.set(sessionsToday, forKey: UserDefaultsKeys.sessionsToday)
        defaults.set(today, forKey: UserDefaultsKeys.sessionsTodayDate)

        // Update daily history
        dailyHistory[today] = sessionsToday
        saveDailyHistory()

        // Update sessions this week
        sessionsThisWeek += 1
        let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today))!
        defaults.set(sessionsThisWeek, forKey: UserDefaultsKeys.sessionsThisWeek)
        defaults.set(weekStart, forKey: UserDefaultsKeys.weekStartDate)

        // Update streak
        if let lastDate = defaults.object(forKey: UserDefaultsKeys.lastExerciseDate) as? Date {
            let lastDay = calendar.startOfDay(for: lastDate)
            if lastDay != today {
                let daysBetween = calendar.dateComponents([.day], from: lastDay, to: today).day ?? 0
                if daysBetween == 1 {
                    dailyStreak += 1
                } else if daysBetween > 1 {
                    dailyStreak = 1
                }
            }
        } else {
            dailyStreak = 1
        }

        defaults.set(dailyStreak, forKey: UserDefaultsKeys.dailyStreak)
        defaults.set(Date(), forKey: UserDefaultsKeys.lastExerciseDate)

        // Notify other services that a session was completed
        NotificationCenter.default.post(name: .sessionCompleted, object: nil)
    }

    // MARK: - Audio

    private func playCelebrationSound() {
        // Play a triumphant celebration sound
        SoundHelper.play("Hero")
    }
}
