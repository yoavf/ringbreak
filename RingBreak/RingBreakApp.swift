//
//  RingBreakApp.swift
//  RingBreak
//
//  Ring Break - Ring-Con Fitness App for macOS
//

import SwiftUI
import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // When dock icon is clicked and no visible windows, show our hidden window
        if !flag {
            openMainWindow()
        }
        // Return false to prevent SwiftUI WindowGroup from creating a new window
        return false
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // When app becomes active (e.g., via alt+tab), show the window if hidden
        let hasVisibleWindow = NSApp.windows.contains { window in
            window.isVisible &&
            window.identifier?.rawValue == "MainWindow"
        }
        if !hasVisibleWindow {
            openMainWindow()
        }
    }

    /// Opens the main window if it exists (hidden or visible)
    @MainActor
    func openMainWindow() {
        print("=== openMainWindow ===")
        print("Windows count: \(NSApp.windows.count)")
        for (i, w) in NSApp.windows.enumerated() {
            print("  [\(i)] id=\(w.identifier?.rawValue ?? "nil") visible=\(w.isVisible) canBecomeKey=\(w.canBecomeKey)")
        }

        // Look for our main window by identifier (it may be hidden but not destroyed)
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "MainWindow" }) {
            print("Found MainWindow")

            if window.isMiniaturized {
                window.deminiaturize(nil)
            }

            window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]

            // Activate app and bring window to front
            // Use NSRunningApplication for more reliable activation from accessory mode
            NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            window.makeKeyAndOrderFront(nil)

            // If window didn't become key (activation still in progress), retry after short delay
            if !window.isKeyWindow {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    NSApp.activate(ignoringOtherApps: true)
                    window.makeKeyAndOrderFront(nil)
                }
            }

            print("After show: visible=\(window.isVisible) isKey=\(window.isKeyWindow)")
            return
        }

        print("MainWindow not found, trying fallback")
        // Fallback: look for any suitable window
        if let window = NSApp.windows.first(where: { window in
            window.canBecomeKey &&
            !(window is NSPanel) &&
            String(describing: type(of: window)) != "NSStatusBarWindow" &&
            String(describing: type(of: window)) != "NSPopupMenuWindow"
        }) {
            print("Found fallback window")
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        print("No window found at all!")
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct RingBreakApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
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
        menubarController.setActivateCallback { [weak appDelegate] in
            appDelegate?.openMainWindow()
        }

        // Dock icon always shows on startup with the window.
        // It hides (accessory mode) only when user closes the window, if that setting is enabled.

        if notificationService.isEnabled && !notificationService.permissionGranted {
            Task {
                await notificationService.requestPermission()
            }
        }
    }
}
