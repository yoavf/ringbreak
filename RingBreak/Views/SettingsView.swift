//
//  SettingsView.swift
//  RingBreak
//
//  Settings screen for difficulty and calibration
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var gameState: BreakGameState
    @ObservedObject var ringConManager: RingConManager
    @ObservedObject var menubarController: MenubarController
    @EnvironmentObject private var notificationService: NotificationService
    @Environment(\.colorScheme) private var colorScheme
    var onBack: () -> Void
    @State private var showingCalibration = false
    @State private var showingHideDockConfirmation = false
    @AppStorage(UserDefaultsKeys.showDockIcon) private var showDockIcon = true
    @AppStorage(UserDefaultsKeys.soundsEnabled) private var soundsEnabled = true

    private var backgroundColor: Color {
        AppColors.background(for: colorScheme)
    }

    var body: some View {
        VStack(spacing: 0) {
            // HEADER - compact
            HStack {
                Button {
                    onBack()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.semibold))
                        Text("Back")
                    }
                    .foregroundColor(.accentColor)
                }
                .buttonStyle(.borderless)
                .focusable(false)
                .keyboardShortcut(.escape, modifiers: [])

                Spacer()

                Text("Settings")
                    .font(.headline)

                Spacer()

                // Balance the back button
                Color.clear.frame(width: 50)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .fixedSize(horizontal: false, vertical: true)

            // CONTENT - scrollable settings
            ScrollView {
                VStack(spacing: 24) {
                    // Difficulty Section
                    SettingsSection(title: "Difficulty") {
                        VStack(spacing: 0) {
                            ForEach(Array(GameDifficulty.allCases.enumerated()), id: \.element) { index, difficulty in
                                DifficultyRow(
                                    difficulty: difficulty,
                                    isSelected: gameState.difficulty == difficulty,
                                    onSelect: {
                                        withAnimation(.easeInOut(duration: 0.15)) {
                                            gameState.difficulty = difficulty
                                        }
                                    }
                                )

                                if index < GameDifficulty.allCases.count - 1 {
                                    Divider()
                                        .padding(.leading, 40)
                                }
                            }
                        }
                    }

                    // Calibration Section
                    SettingsSection(title: "Ring-Con") {
                        Button {
                            if ringConManager.isConnected {
                                showingCalibration = true
                            }
                        } label: {
                            HStack {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 16))
                                    .foregroundColor(ringConManager.isConnected ? .accentColor : .secondary)
                                    .frame(width: 28)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Calibrate")
                                        .foregroundColor(ringConManager.isConnected ? .primary : .secondary)
                                    Text(ringConManager.isConnected ? "Reset neutral position" : "Connect Ring-Con first")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.secondary.opacity(0.5))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(!ringConManager.isConnected)
                    }

                    // Reminders Section
                    SettingsSection(title: "Reminders") {
                        VStack(spacing: 0) {
                            // Enable toggle
                            HStack {
                                Image(systemName: "bell.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(notificationService.isEnabled ? .accentColor : .secondary)
                                    .frame(width: 28)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Exercise Reminders")
                                        .foregroundColor(.primary)
                                    Text(notificationService.isEnabled ? "Notifications enabled" : "Get reminded to take breaks")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Toggle("", isOn: $notificationService.isEnabled)
                                    .labelsHidden()
                                    .onChange(of: notificationService.isEnabled) { newValue in
                                        if newValue && !notificationService.permissionGranted {
                                            Task {
                                                await notificationService.requestPermission()
                                            }
                                        }
                                    }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                notificationService.isEnabled.toggle()
                            }

                            if notificationService.isEnabled {
                                Divider()
                                    .padding(.leading, 40)

                                // Interval picker
                                HStack {
                                    Image(systemName: "clock")
                                        .font(.system(size: 16))
                                        .foregroundColor(.secondary)
                                        .frame(width: 28)

                                    Text("Remind every")
                                        .foregroundColor(.primary)

                                    Spacer()

                                    Picker("", selection: $notificationService.interval) {
                                        ForEach(ReminderInterval.allCases) { interval in
                                            Text(interval.displayName).tag(interval)
                                        }
                                    }
                                    .labelsHidden()
                                    .pickerStyle(.menu)
                                    .frame(width: 100)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                            }
                        }
                    }

                    // App Settings Section
                    SettingsSection(title: "App") {
                        VStack(spacing: 0) {
                            // Menubar icon toggle
                            HStack {
                                Image(systemName: "menubar.rectangle")
                                    .font(.system(size: 16))
                                    .foregroundColor(menubarController.isVisible ? .accentColor : .secondary)
                                    .frame(width: 28)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Menu Bar Icon")
                                        .foregroundColor(.primary)
                                    Text("Quick access from menu bar")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Toggle("", isOn: $menubarController.isVisible)
                                    .labelsHidden()
                                    .onChange(of: menubarController.isVisible) { newValue in
                                        // If turning off menubar, force dock icon on
                                        if !newValue && !showDockIcon {
                                            showDockIcon = true
                                        }
                                    }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                menubarController.isVisible.toggle()
                            }

                            Divider()
                                .padding(.leading, 40)

                            // Dock icon toggle
                            HStack {
                                Image(systemName: "dock.rectangle")
                                    .font(.system(size: 16))
                                    .foregroundColor(showDockIcon ? .accentColor : .secondary)
                                    .frame(width: 28)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Dock Icon")
                                        .foregroundColor(.primary)
                                    Text(showDockIcon ? "Visible in Dock" : "Hidden from Dock")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Toggle("", isOn: Binding(
                                    get: { showDockIcon },
                                    set: { newValue in
                                        if newValue {
                                            // Turning on - no confirmation needed
                                            showDockIcon = true
                                            updateDockIconVisibility(visible: true)
                                        } else {
                                            // Turning off - show confirmation
                                            showingHideDockConfirmation = true
                                        }
                                    }
                                ))
                                    .labelsHidden()
                                    .disabled(!menubarController.isVisible)  // Can't hide both
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                guard menubarController.isVisible else { return }
                                if showDockIcon {
                                    showingHideDockConfirmation = true
                                } else {
                                    showDockIcon = true
                                    updateDockIconVisibility(visible: true)
                                }
                            }

                            Divider()
                                .padding(.leading, 40)

                            // Sound toggle
                            HStack {
                                Image(systemName: soundsEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(soundsEnabled ? .accentColor : .secondary)
                                    .frame(width: 28)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Sounds")
                                        .foregroundColor(.primary)
                                    Text(soundsEnabled ? "Sound effects enabled" : "Sound effects muted")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Toggle("", isOn: $soundsEnabled)
                                    .labelsHidden()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                soundsEnabled.toggle()
                            }
                        }
                    }

                    // Debug Section
                    SettingsSection(title: "Debug") {
                        Button {
                            let connectionState = "\(ringConManager.connectionState)"
                            let bluetoothStatus = "\(ringConManager.bluetoothStatus)"
                            let ringConAttached = ringConManager.ringConAttached
                            let calibrationInfo = ringConManager.isConnected
                                ? "flex=\(String(format: "%.1f%%", ringConManager.flexValue * 100))"
                                : "not connected"
                            DebugLogger.shared.presentExportPanel(
                                connectionState: connectionState,
                                bluetoothStatus: bluetoothStatus,
                                ringConAttached: ringConAttached,
                                calibrationInfo: calibrationInfo
                            )
                        } label: {
                            HStack {
                                Image(systemName: "ladybug")
                                    .font(.system(size: 16))
                                    .foregroundColor(.accentColor)
                                    .frame(width: 28)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Export Debug Logs")
                                        .foregroundColor(.primary)
                                    Text("Save connection & sensor logs to file")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.secondary.opacity(0.5))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    // About Section
                    SettingsSection(title: "About") {
                        VStack(spacing: 0) {
                            HStack {
                                Text("Version")
                                    .foregroundColor(.primary)
                                Spacer()
                                Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0")
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)

                            Divider()
                                .padding(.leading, 12)

                            Button {
                                if let url = URL(string: Constants.gitHubURL) {
                                    NSWorkspace.shared.open(url)
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "star")
                                        .font(.system(size: 16))
                                        .foregroundColor(.accentColor)
                                        .frame(width: 28)

                                    Text("Star on GitHub")
                                        .foregroundColor(.primary)

                                    Spacer()

                                    Image(systemName: "arrow.up.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(.secondary.opacity(0.5))
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .background(backgroundColor)
        .sheet(isPresented: $showingCalibration) {
            CalibrationView(ringConManager: ringConManager) {
                showingCalibration = false
            }
        }
        .alert("Hide Dock Icon?", isPresented: $showingHideDockConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Hide") {
                showDockIcon = false
                updateDockIconVisibility(visible: false)
            }
        } message: {
            Text("The app will continue running in the menu bar. Use the menu bar icon to access Ring Break.")
        }
    }

    private func updateDockIconVisibility(visible: Bool) {
        if visible {
            NSApp.setActivationPolicy(.regular)
            // Activate app to ensure window is visible
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
            }
        } else {
            // Store reference to window before changing policy
            let window = NSApp.windows.first(where: { $0.canBecomeKey && !($0 is NSPanel) })

            NSApp.setActivationPolicy(.accessory)

            // Re-activate and show window after policy change
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
                window?.makeKeyAndOrderFront(nil)
            }
        }
    }
}

// MARK: - Settings Section

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.leading, 12)

            content
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
        }
    }
}

// MARK: - Difficulty Row

struct DifficultyRow: View {
    let difficulty: GameDifficulty
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // Difficulty indicator
                Circle()
                    .fill(difficultyColor)
                    .frame(width: 10, height: 10)
                    .overlay(
                        Circle()
                            .stroke(difficultyColor.opacity(0.3), lineWidth: 3)
                    )
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(difficulty.rawValue)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)

                    Text(difficultyDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var difficultyColor: Color {
        switch difficulty {
        case .easy: return .green
        case .medium: return .orange
        case .hard: return .red
        }
    }

    private var difficultyDescription: String {
        switch difficulty {
        case .easy: return "65% squeeze threshold"
        case .medium: return "75% squeeze threshold"
        case .hard: return "80% squeeze threshold"
        }
    }
}

#Preview {
    SettingsView(
        gameState: BreakGameState(),
        ringConManager: RingConManager(),
        menubarController: MenubarController(),
        onBack: {}
    )
    .environmentObject(NotificationService.shared)
    .frame(width: 420, height: 620)
}
