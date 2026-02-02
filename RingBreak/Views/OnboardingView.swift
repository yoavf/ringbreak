//
//  OnboardingView.swift
//  RingBreak
//
//  First-launch onboarding tutorial
//

import SwiftUI

struct OnboardingView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var notificationService: NotificationService
    @ObservedObject var ringConManager: RingConManager
    @AppStorage(UserDefaultsKeys.soundsEnabled) private var soundsEnabled = true
    var onComplete: () -> Void

    @State private var currentStep = 0
    @State private var showingCalibration = false

    private let totalSteps = 5

    private var backgroundColor: Color {
        AppColors.background(for: colorScheme)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Content
            TabView(selection: $currentStep) {
                introStep.tag(0)
                pairJoyConStep.tag(1)
                connectRingConStep.tag(2)
                calibrateStep.tag(3)
                settingsStep.tag(4)
            }
            .tabViewStyle(.automatic)
            .animation(.easeInOut, value: currentStep)

            // Navigation
            VStack(spacing: 16) {
                // Progress dots
                HStack(spacing: 8) {
                    ForEach(0..<totalSteps, id: \.self) { index in
                        Circle()
                            .fill(index == currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 8, height: 8)
                            .animation(.easeInOut, value: currentStep)
                    }
                }

                // Buttons
                HStack(spacing: 16) {
                    if currentStep > 0 {
                        Button("Back") {
                            if currentStep == 3 && ringConManager.isCalibrating {
                                ringConManager.cancelCalibration()
                            }
                            withAnimation {
                                currentStep -= 1
                            }
                        }
                        .buttonStyle(.bordered)
                        .focusable(false)
                    }

                    Spacer()

                    Button("Skip") {
                        if currentStep == 3 && ringConManager.isCalibrating {
                            ringConManager.cancelCalibration()
                        }
                        completeOnboarding()
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .focusable(false)

                    if currentStep == totalSteps - 1 {
                        Button("Get Started") {
                            advancePrimaryAction()
                        }
                        .buttonStyle(.borderedProminent)
                        .focusable(false)
                    } else if canAdvance {
                        Button("Next") {
                            advancePrimaryAction()
                        }
                        .buttonStyle(.borderedProminent)
                        .focusable(false)
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
        }
        .frame(width: 420, height: 620)
        .background(backgroundColor)
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.space) {
            if canAdvance {
                advancePrimaryAction()
                return .handled
            }
            return .ignored
        }
    }

    private var canAdvance: Bool {
        if currentStep == totalSteps - 1 {
            return true
        }
        return currentStep == 0
            || (currentStep == 1 && ringConManager.isConnected)
            || (currentStep == 2 && ringConManager.ringConAttached)
            || (currentStep == 3 && ringConManager.calibrationPhase == .complete)
    }

    private func advancePrimaryAction() {
        if currentStep == totalSteps - 1 {
            completeOnboarding()
        } else {
            withAnimation {
                currentStep += 1
            }
        }
    }

    private func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: UserDefaultsKeys.hasCompletedOnboarding)
        onComplete()
    }

    @ViewBuilder
    private func onboardingImage(_ name: String, maxHeight: CGFloat, fill: Bool = false) -> some View {
        if let url = Bundle.main.url(forResource: name, withExtension: "png"),
           let nsImage = NSImage(contentsOf: url) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: fill ? .fill : .fit)
                .frame(height: fill ? maxHeight : nil, alignment: .center)
                .frame(maxHeight: maxHeight)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: fill ? 0 : 16))
                .shadow(color: fill ? .clear : .black.opacity(0.1), radius: 8, y: 4)
        } else {
            // Fallback placeholder
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.secondary.opacity(0.2))
                .frame(height: maxHeight)
                .overlay(
                    Text("Image not found: \(name)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                )
        }
    }

    // MARK: - Step Views

    private var introStep: some View {
        VStack(spacing: 24) {
            Spacer()

            onboardingImage("intro", maxHeight: 280)

            VStack(spacing: 12) {
                Text("Welcome to ring-break")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Quick desk exercises with your Ring-Con to stay active throughout the day.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()
        }
    }

    private var pairJoyConStep: some View {
        VStack(spacing: 24) {
            Spacer()

            onboardingImage("pair-joycon", maxHeight: 220, fill: true)

            VStack(spacing: 12) {
                Text("Pair Joy-Con (R)")
                    .font(.title2)
                    .fontWeight(.bold)

                VStack(spacing: 4) {
                    Text("Hold the sync button until lights flash, then pair in")
                        .font(.body)
                        .foregroundColor(.secondary)

                    Button {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Text("System Settings \u{2192} Bluetooth")
                            .font(.body)
                    }
                    .buttonStyle(.link)
                    .focusable(false)
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

                pairStatusIndicator
            }

            Spacer()
        }
        .onAppear {
            if ringConManager.pairedDeviceStatus != .noPairedDevice {
                ringConManager.autoConnectIfAvailable()
            }
            ringConManager.startScanning()
        }
    }

    @ViewBuilder
    private var pairStatusIndicator: some View {
        HStack(spacing: 8) {
            if ringConManager.isConnected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 16))
                Text("Connected!")
                    .font(.callout)
                    .foregroundColor(.green)
            } else if ringConManager.connectionState == .connecting || ringConManager.connectionState == .scanning {
                ProgressView()
                    .controlSize(.small)
                Text("Connecting...")
                    .font(.callout)
                    .foregroundColor(.secondary)
            } else {
                ProgressView()
                    .controlSize(.small)
                Text("Waiting for pairing...")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(ringConManager.isConnected ? Color.green.opacity(0.1) : Color.secondary.opacity(0.1))
        )
    }

    private var connectRingConStep: some View {
        VStack(spacing: 24) {
            Spacer()

            onboardingImage("connect-joycon", maxHeight: 280, fill: true)

            VStack(spacing: 12) {
                Text("Attach to Ring-Con")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Slide the Joy-Con into the Ring-Con rail until it clicks.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                ringConAttachIndicator
            }

            Spacer()
        }
    }

    @ViewBuilder
    private var ringConAttachIndicator: some View {
        HStack(spacing: 8) {
            if ringConManager.ringConAttached {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 16))
                Text("Ring-Con Detected!")
                    .font(.callout)
                    .foregroundColor(.green)
            } else if ringConManager.connectionState == .connecting {
                ProgressView()
                    .controlSize(.small)
                Text("Setting up Ring-Con...")
                    .font(.callout)
                    .foregroundColor(.secondary)
            } else {
                ProgressView()
                    .controlSize(.small)
                Text("Waiting for Ring-Con...")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(ringConManager.ringConAttached ? Color.green.opacity(0.1) : Color.secondary.opacity(0.1))
        )
    }

    private var calibrateStep: some View {
        VStack(spacing: 20) {
            Spacer()

            if ringConManager.calibrationPhase == .complete {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.green)

                Text("Calibration Complete!")
                    .font(.title2)
                    .fontWeight(.bold)

                Button("Redo calibration") {
                    showingCalibration = true
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
                .font(.caption)
                .focusable(false)
            } else {
                RingConSceneView(flexValue: 0.5)
                    .frame(width: 160, height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )

                VStack(spacing: 12) {
                    Text("Calibrate Ring-Con")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("Calibration measures your ring's flex range for accurate tracking.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Button("Start Calibration") {
                    showingCalibration = true
                }
                .buttonStyle(.borderedProminent)
                .focusable(false)
                .disabled(!ringConManager.isConnected || !ringConManager.ringConAttached)

                if !ringConManager.isConnected || !ringConManager.ringConAttached {
                    Text("Connect Ring-Con to calibrate")
                        .font(.caption)
                        .foregroundColor(.orange)
                } else {
                    Text("You can calibrate later in Settings")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .sheet(isPresented: $showingCalibration) {
            CalibrationView(ringConManager: ringConManager) {
                showingCalibration = false
            }
        }
    }

    // MARK: - Settings Step

    private var settingsStep: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 12) {
                Text("Quick Settings")
                    .font(.title)
                    .fontWeight(.bold)

                Text("You can always change these later.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            // Toggle rows
            VStack(spacing: 0) {
                // Notifications toggle
                HStack {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 18))
                        .foregroundColor(notificationService.isEnabled ? .accentColor : .secondary)
                        .frame(width: 32)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Exercise Reminders")
                            .foregroundColor(.primary)
                        Text("Get reminded to take breaks")
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
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
                .onTapGesture {
                    notificationService.isEnabled.toggle()
                }

                if notificationService.isEnabled {
                    Divider()
                        .padding(.leading, 48)

                    // Interval picker
                    HStack {
                        Image(systemName: "clock")
                            .font(.system(size: 18))
                            .foregroundColor(.secondary)
                            .frame(width: 32)

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
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }

                Divider()
                    .padding(.leading, 48)

                // Sounds toggle
                HStack {
                    Image(systemName: soundsEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .font(.system(size: 18))
                        .foregroundColor(soundsEnabled ? .accentColor : .secondary)
                        .frame(width: 32)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sound Effects")
                            .foregroundColor(.primary)
                        Text("Audio feedback during exercises")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Toggle("", isOn: $soundsEnabled)
                        .labelsHidden()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
                .onTapGesture {
                    soundsEnabled.toggle()
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
            .padding(.horizontal, 32)

            Spacer()
        }
    }
}

#Preview {
    OnboardingView(ringConManager: RingConManager(), onComplete: {})
        .environmentObject(NotificationService.shared)
}
