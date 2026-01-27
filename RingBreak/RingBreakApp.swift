//
//  RingBreakApp.swift
//  RingBreak
//
//  Ring Break - Ring-Con Fitness App for macOS
//

import SwiftUI
import UserNotifications

@main
struct RingBreakApp: App {
    @StateObject private var menubarController = MenubarController()
    @StateObject private var notificationService = NotificationService.shared

    init() {
        // Set up notification delegate
        UNUserNotificationCenter.current().delegate = NotificationService.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView(menubarController: menubarController)
                .environmentObject(notificationService)
                .onAppear {
                    setupApp()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }

    private func setupApp() {
        menubarController.setActivateCallback {
            // Window activation handled in controller
        }

        // Apply saved dock icon visibility (must be done after NSApp is initialized)
        let showDock = UserDefaults.standard.object(forKey: UserDefaultsKeys.showDockIcon) as? Bool ?? true
        if !showDock {
            NSApp.setActivationPolicy(.accessory)
        }

        if notificationService.isEnabled && !notificationService.permissionGranted {
            Task {
                await notificationService.requestPermission()
            }
        }
    }
}
