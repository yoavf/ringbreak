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
    @AppStorage(UserDefaultsKeys.soundsEnabled) private var soundsEnabled = true
    var onComplete: () -> Void

    @State private var currentStep = 0

    private let totalSteps = 4

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
                settingsStep.tag(3)
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
                            withAnimation {
                                currentStep -= 1
                            }
                        }
                        .buttonStyle(.bordered)
                        .focusable(false)
                    }

                    Spacer()

                    Button("Skip") {
                        completeOnboarding()
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .focusable(false)

                    if currentStep < totalSteps - 1 {
                        Button("Next") {
                            withAnimation {
                                currentStep += 1
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .focusable(false)
                    } else {
                        Button("Get Started") {
                            completeOnboarding()
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
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
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

            onboardingImage("pair-joycon", maxHeight: 280)

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
                        Text("System Settings → Bluetooth")
                            .font(.body)
                    }
                    .buttonStyle(.link)
                    .focusable(false)
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            }

            Spacer()
        }
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
            }

            Spacer()
        }
    }

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
    OnboardingView(onComplete: {})
        .environmentObject(NotificationService.shared)
}
