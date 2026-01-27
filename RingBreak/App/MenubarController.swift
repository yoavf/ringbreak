//
//  MenubarController.swift
//  RingBreak
//
//  Manages the menubar status item with Ring-Con icon and dropdown menu
//

import AppKit
import Combine

@MainActor
class MenubarController: ObservableObject {
    private var statusItem: NSStatusItem?
    private var updateTimer: Timer?
    private var onActivate: (() -> Void)?
    private var sessionObserver: NSObjectProtocol?
    private var timeMenuItem: NSMenuItem?

    @Published var isVisible: Bool = true {
        didSet {
            UserDefaults.standard.set(isVisible, forKey: UserDefaultsKeys.showMenubarIcon)
            updateVisibility()
        }
    }

    init() {
        self.isVisible = UserDefaults.standard.object(forKey: UserDefaultsKeys.showMenubarIcon) as? Bool ?? false

        if isVisible {
            setupStatusItem()
            setupMenu()
        }
        startTimer()
        setupSessionObserver()
    }

    deinit {
        updateTimer?.invalidate()
        if let observer = sessionObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func setupSessionObserver() {
        sessionObserver = NotificationCenter.default.addObserver(
            forName: .sessionCompleted,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    func setActivateCallback(_ callback: @escaping () -> Void) {
        onActivate = callback
    }

    private func updateVisibility() {
        if isVisible {
            if statusItem == nil {
                setupStatusItem()
                setupMenu()
            }
        } else {
            if let item = statusItem {
                NSStatusBar.system.removeStatusItem(item)
                statusItem = nil
            }
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        guard let button = statusItem?.button else { return }

        button.image = createRingConIcon()
        button.image?.isTemplate = true
    }

    private func setupMenu() {
        let menu = NSMenu()

        // Time since last exercise (disabled, just for display)
        timeMenuItem = NSMenuItem(title: formatTimeMenuText(), action: nil, keyEquivalent: "")
        timeMenuItem?.isEnabled = false
        if let item = timeMenuItem {
            menu.addItem(item)
        }

        menu.addItem(NSMenuItem.separator())

        // Open Ring Break
        let openItem = NSMenuItem(title: "Open Ring Break", action: #selector(openApp), keyEquivalent: "o")
        openItem.target = self
        menu.addItem(openItem)

        // View on GitHub
        let githubItem = NSMenuItem(title: "View on GitHub", action: #selector(openGitHub), keyEquivalent: "")
        githubItem.target = self
        menu.addItem(githubItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(title: "Quit Ring Break", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    @objc private func openApp() {
        // Activate the app first
        NSApp.activate(ignoringOtherApps: true)

        // Find the main app window
        if let window = NSApp.windows.first(where: { $0.canBecomeKey && !($0 is NSPanel) }) {
            // If window is miniaturized, deminiaturize it
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            // Show and focus the window
            window.orderFrontRegardless()
        }

        onActivate?()
    }

    @objc private func openGitHub() {
        if let url = URL(string: Constants.gitHubURL) {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func startTimer() {
        // Update every minute
        updateTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateTimeDisplay()
            }
        }
    }

    private func updateTimeDisplay() {
        timeMenuItem?.title = formatTimeMenuText()
    }

    private func createRingConIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            // Draw a ring (circle with thick stroke)
            let ringRect = rect.insetBy(dx: 2, dy: 2)
            let path = NSBezierPath(ovalIn: ringRect)
            path.lineWidth = 2.5

            // Use template-friendly color (will be inverted by system)
            NSColor.black.setStroke()
            path.stroke()

            // Add small grip indicators on sides
            let gripSize: CGFloat = 3
            let centerY = rect.midY

            // Left grip
            let leftGrip = NSBezierPath(
                roundedRect: NSRect(x: 0, y: centerY - gripSize/2, width: gripSize, height: gripSize),
                xRadius: 1,
                yRadius: 1
            )
            NSColor.black.setFill()
            leftGrip.fill()

            // Right grip
            let rightGrip = NSBezierPath(
                roundedRect: NSRect(x: rect.width - gripSize, y: centerY - gripSize/2, width: gripSize, height: gripSize),
                xRadius: 1,
                yRadius: 1
            )
            rightGrip.fill()

            return true
        }

        return image
    }

    private func formatTimeMenuText() -> String {
        guard let lastDate = UserDefaults.standard.object(forKey: UserDefaultsKeys.lastExerciseDate) as? Date else {
            return "Last exercise: Never"
        }

        let elapsed = Date().timeIntervalSince(lastDate)

        if elapsed < 60 {
            return "Last exercise: Just now"
        }

        let minutes = Int(elapsed / 60)
        let hours = minutes / 60
        let remainingMinutes = minutes % 60

        let timeString: String
        if hours == 0 {
            timeString = "\(minutes) min ago"
        } else if remainingMinutes == 0 {
            timeString = hours == 1 ? "1 hour ago" : "\(hours) hours ago"
        } else {
            timeString = "\(hours)h \(remainingMinutes)m ago"
        }

        return "Last exercise: \(timeString)"
    }

    /// Force refresh the display (call after completing a session)
    func refresh() {
        updateTimeDisplay()
    }
}
