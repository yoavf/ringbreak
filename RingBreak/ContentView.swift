//
//  ContentView.swift
//  RingBreak
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var menubarController: MenubarController
    @StateObject private var ringConManager = RingConManager()
    @AppStorage(UserDefaultsKeys.hasCompletedOnboarding) private var hasCompletedOnboarding = false

    var body: some View {
        Group {
            if hasCompletedOnboarding {
                RingBreakView(ringConManager: ringConManager, menubarController: menubarController)
            } else {
                OnboardingView {
                    hasCompletedOnboarding = true
                }
            }
        }
        .background(WindowAccessor())
    }
}

/// Helper to access and configure the NSWindow to hide instead of close
struct WindowAccessor: NSViewRepresentable {
    class Coordinator: NSObject, NSWindowDelegate {
        func windowShouldClose(_ sender: NSWindow) -> Bool {
            // Hide instead of close
            sender.orderOut(nil)

            // Restore accessory mode if dock icon should be hidden
            let showDock = UserDefaults.standard.object(forKey: UserDefaultsKeys.showDockIcon) as? Bool ?? true
            if !showDock {
                NSApp.setActivationPolicy(.accessory)
            }

            return false
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                window.delegate = context.coordinator
                window.isReleasedWhenClosed = false
                window.identifier = NSUserInterfaceItemIdentifier("MainWindow")
                // Dock icon hiding happens when user closes window, not on startup
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

#Preview {
    ContentView(menubarController: MenubarController())
}
