//
//  ReadyView.swift
//  RingBreak
//
//  View shown when connected and ready to start exercise
//

import SwiftUI

struct ReadyView: View {
    @ObservedObject var ringConManager: RingConManager
    @ObservedObject var gameState: BreakGameState
    @Binding var isCountingDown: Bool
    @Binding var startCountdown: Int
    let onSettingsTapped: () -> Void
    let onStreakTapped: () -> Void
    let onStartExercise: () -> Void

    @State private var isStreakHovered = false
    @State private var isSettingsHovered = false
    @State private var countdownTimer: Timer?
    @Environment(\.colorScheme) private var colorScheme

    private var countdownColor: Color {
        colorScheme == .dark ? AppColors.countdownDark : .accentColor
    }

    private var glowOpacity: Double {
        colorScheme == .dark ? 0.3 : 0.8
    }

    var body: some View {
        VStack(spacing: 0) {
            // HEADER - switches between normal header and countdown header
            if isCountingDown {
                // Countdown header - matches exercise view layout exactly
                HStack {
                    Button {
                        // Cancel countdown
                        countdownTimer?.invalidate()
                        countdownTimer = nil
                        isCountingDown = false
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.borderless)
                    Spacer()
                    // Show rep counter to match ExerciseView
                    Text("1/\(gameState.targetReps)")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                .padding(.top)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                // Normal ready header
                HStack {
                    Button {
                        onStreakTapped()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: isStreakHovered ? "flame.fill" : "flame")
                                .foregroundColor(.orange)
                                .scaleEffect(isStreakHovered ? 1.2 : 1.0)
                                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isStreakHovered)
                            if gameState.dailyStreak > 0 {
                                Text("\(gameState.dailyStreak)")
                            }
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .onHover { hovering in
                        isStreakHovered = hovering
                    }
                    .opacity(1)
                    .frame(width: 60, alignment: .leading)

                    Spacer()

                    RingBreakLogo(height: 48)

                    Spacer()

                    Button { onSettingsTapped() } label: {
                        Image(systemName: isSettingsHovered ? "gearshape.fill" : "gearshape")
                            .foregroundColor(.secondary)
                            .scaleEffect(isSettingsHovered ? 1.2 : 1.0)
                            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSettingsHovered)
                    }
                    .buttonStyle(.borderless)
                    .focusable(false)
                    .onHover { hovering in
                        isSettingsHovered = hovering
                    }
                    .frame(width: 60, alignment: .trailing)
                }
                .padding(.horizontal)
                .padding(.top, 16)
                .fixedSize(horizontal: false, vertical: true)
            }

            // CENTER AREA - ring is rendered by parent, we just show overlays
            ZStack {
                // Countdown overlay (only during countdown)
                if isCountingDown {
                    VStack(spacing: 8) {
                        Text("\(startCountdown)")
                            .font(.system(size: 120, weight: .bold, design: .rounded))
                            .foregroundColor(countdownColor)
                            .shadow(color: countdownColor.opacity(glowOpacity), radius: 20)
                            .contentTransition(.numericText())
                            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: startCountdown)
                        Text("Get ready...")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // CONTROLS / BOTTOM AREA - matches ExerciseView layout during countdown
            if isCountingDown {
                // Match ExerciseView's progress bar area (50pt height + 8pt padding)
                Color.clear
                    .frame(height: 50)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            } else {
                VStack(spacing: 12) {
                    if gameState.sessionsToday > 0 {
                        HStack(spacing: 6) {
                            Text("\(gameState.sessionsToday)")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                            Text(gameState.sessionsToday == 1 ? "session today" : "sessions today")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Button(action: { startWithCountdown() }) {
                        Text("Start")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 140)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Text("or squeeze to start")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 8)

                // STATUS - at bottom, fixed size (only when not counting down)
                DeviceStatusBar(ringConManager: ringConManager)
                    .frame(height: 50)
                    .padding(.bottom, 12)
            }
        }
        .onChange(of: ringConManager.flexValue) { newValue in
            if gameState.phase == .ready && !isCountingDown && newValue > Constants.squeezeStartThreshold {
                startWithCountdown()
            }
        }
    }

    private func startWithCountdown() {
        guard !isCountingDown else { return }

        isCountingDown = true
        startCountdown = Constants.startCountdown

        // Play sound for "3"
        SoundHelper.play("Tink")

        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak gameState] timer in
            Task { @MainActor in
                guard isCountingDown else {
                    timer.invalidate()
                    countdownTimer = nil
                    return
                }
                if startCountdown > 1 {
                    withAnimation {
                        startCountdown -= 1
                    }
                    SoundHelper.play("Tink")
                } else {
                    timer.invalidate()
                    countdownTimer = nil
                    SoundHelper.play("Glass")
                    // No animation - instant transition to match layouts exactly
                    isCountingDown = false
                    gameState?.startExercise()
                    onStartExercise()
                }
            }
        }
    }
}
