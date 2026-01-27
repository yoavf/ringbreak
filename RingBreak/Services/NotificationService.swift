//
//  NotificationService.swift
//  RingBreak
//
//  Manages local notifications for exercise reminders
//

import Foundation
import UserNotifications
import AppKit

/// Reminder interval options
enum ReminderInterval: Int, CaseIterable, Identifiable {
    case oneHour = 1
    case twoHours = 2
    case threeHours = 3
    case fourHours = 4

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .oneHour: return "1 hour"
        case .twoHours: return "2 hours"
        case .threeHours: return "3 hours"
        case .fourHours: return "4 hours"
        }
    }

    var seconds: TimeInterval {
        TimeInterval(rawValue * 3600)
    }
}

@MainActor
class NotificationService: NSObject, ObservableObject {
    static let shared = NotificationService()

    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: UserDefaultsKeys.notificationsEnabled)
            if isEnabled {
                scheduleNextReminder()
            } else {
                cancelAllReminders()
            }
        }
    }

    @Published var interval: ReminderInterval {
        didSet {
            UserDefaults.standard.set(interval.rawValue, forKey: UserDefaultsKeys.notificationInterval)
            if isEnabled {
                scheduleNextReminder()
            }
        }
    }

    @Published private(set) var permissionGranted: Bool = false

    private let notificationCenter = UNUserNotificationCenter.current()
    private let notificationIdentifier = "ringbreak.reminder"
    private let snoozeIdentifier = "ringbreak.snooze"

    // Workspace notifications for screen sleep
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var sessionObserver: NSObjectProtocol?
    private var isPaused = false

    override init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: UserDefaultsKeys.notificationsEnabled)
        let savedInterval = UserDefaults.standard.integer(forKey: UserDefaultsKeys.notificationInterval)
        self.interval = ReminderInterval(rawValue: savedInterval) ?? .twoHours

        super.init()

        setupNotificationActions()
        setupSleepObservers()
        setupSessionObserver()
        checkPermission()
    }

    deinit {
        if let sleepObserver = sleepObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver)
        }
        if let wakeObserver = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        if let sessionObserver = sessionObserver {
            NotificationCenter.default.removeObserver(sessionObserver)
        }
    }

    private func setupSessionObserver() {
        sessionObserver = NotificationCenter.default.addObserver(
            forName: .sessionCompleted,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.sessionCompleted()
            }
        }
    }

    // MARK: - Permission

    func requestPermission() async -> Bool {
        do {
            let granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
            await MainActor.run {
                self.permissionGranted = granted
            }
            return granted
        } catch {
            #if DEBUG
            print("NotificationService: Permission request failed: \(error)")
            #endif
            return false
        }
    }

    private func checkPermission() {
        Task {
            let settings = await notificationCenter.notificationSettings()
            await MainActor.run {
                self.permissionGranted = settings.authorizationStatus == .authorized
            }
        }
    }

    // MARK: - Notification Actions

    private func setupNotificationActions() {
        let snoozeAction = UNNotificationAction(
            identifier: "SNOOZE_ACTION",
            title: "Snooze 30 min",
            options: []
        )

        let openAction = UNNotificationAction(
            identifier: "OPEN_ACTION",
            title: "Let's Go!",
            options: [.foreground]
        )

        let category = UNNotificationCategory(
            identifier: "REMINDER_CATEGORY",
            actions: [openAction, snoozeAction],
            intentIdentifiers: [],
            options: []
        )

        notificationCenter.setNotificationCategories([category])
    }

    // MARK: - Scheduling

    func scheduleNextReminder() {
        guard isEnabled && permissionGranted && !isPaused else { return }

        // Cancel existing reminders first
        cancelAllReminders()

        // Calculate time until next reminder based on last exercise
        let lastExercise = UserDefaults.standard.object(forKey: UserDefaultsKeys.lastExerciseDate) as? Date ?? Date()
        let nextReminderDate = lastExercise.addingTimeInterval(interval.seconds)

        // If the next reminder would be in the past, schedule from now
        let fireDate = nextReminderDate > Date() ? nextReminderDate : Date().addingTimeInterval(interval.seconds)

        let content = UNMutableNotificationContent()
        content.title = "Time for a Ring Break!"
        content.body = "Take a quick stretch break with your Ring-Con."
        content.sound = .default    
        content.categoryIdentifier = "REMINDER_CATEGORY"

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: fireDate.timeIntervalSinceNow,
            repeats: false
        )

        let request = UNNotificationRequest(
            identifier: notificationIdentifier,
            content: content,
            trigger: trigger
        )

        notificationCenter.add(request) { error in
            #if DEBUG
            if let error = error {
                print("NotificationService: Failed to schedule: \(error)")
            }
            #endif
        }
    }

    func scheduleSnooze() {
        guard isEnabled && permissionGranted else { return }

        let content = UNMutableNotificationContent()
        content.title = "Ring Break Reminder"
        content.body = "Your snooze is up! Time for a quick exercise."
        content.sound = .default
        content.categoryIdentifier = "REMINDER_CATEGORY"

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: Constants.snoozeDuration,
            repeats: false
        )

        let request = UNNotificationRequest(
            identifier: snoozeIdentifier,
            content: content,
            trigger: trigger
        )

        notificationCenter.add(request) { error in
            #if DEBUG
            if let error = error {
                print("NotificationService: Failed to schedule snooze: \(error)")
            }
            #endif
        }
    }

    func cancelAllReminders() {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [notificationIdentifier, snoozeIdentifier])
    }

    /// Call this after completing an exercise session
    func sessionCompleted() {
        // Reschedule for next interval from now
        scheduleNextReminder()
    }

    // MARK: - Sleep/Wake Handling

    private func setupSleepObservers() {
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleSleep()
            }
        }

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleWake()
            }
        }
    }

    private func handleSleep() {
        isPaused = true
        cancelAllReminders()
    }

    private func handleWake() {
        isPaused = false
        if isEnabled {
            // Reschedule after a short delay to let system settle
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.scheduleNextReminder()
            }
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationService: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            switch response.actionIdentifier {
            case "SNOOZE_ACTION":
                scheduleSnooze()
            case "OPEN_ACTION", UNNotificationDefaultActionIdentifier:
                // Bring app to front
                NSApp.activate(ignoringOtherApps: true)
            default:
                break
            }
            completionHandler()
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Don't show notification when app is in foreground
        completionHandler([])
    }
}
