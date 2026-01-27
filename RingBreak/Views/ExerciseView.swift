//
//  ExerciseView.swift
//  RingBreak
//
//  View shown during active exercise (squeeze/pull phases)
//

import SwiftUI

struct ExerciseView: View {
    @ObservedObject var ringConManager: RingConManager
    @ObservedObject var gameState: BreakGameState
    @Binding var showingCalibration: Bool
    let onCancel: () -> Void

    // Hold state
    @State private var holdState: HoldState = .idle
    @State private var holdCountdown: Int = 0
    @State private var holdTimer: Timer?

    // Calibration prompt
    @State private var failedAttemptTime: Date?
    @State private var showCalibrationPrompt = false
    @State private var calibrationTriggeredDuringExercise = false
    private let calibrationPromptDelay: TimeInterval = 5

    // Arrow animation
    @State private var arrowAnimationPhase: CGFloat = 0

    private let holdDuration = 3

    @Environment(\.colorScheme) private var colorScheme

    enum HoldState {
        case idle
        case active
        case holding
        case relaxing
    }

    private var successColor: Color {
        colorScheme == .dark ? AppColors.successDark : .green
    }

    private var glowOpacity: Double {
        colorScheme == .dark ? 0.3 : 0.8
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top bar - fixed size
            HStack {
                Button {
                    cancelHoldTimer()
                    withAnimation { holdState = .idle }
                    onCancel()
                } label: {
                    Image(systemName: "xmark")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                Spacer()
                Text("\(gameState.currentReps + 1)/\(gameState.targetReps)")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.top)
            .fixedSize(horizontal: false, vertical: true)

            // CENTER AREA - ring is rendered by parent, we show overlays
            ZStack {
                // Animated arrows overlaid on the ring (hidden during hold/relax)
                if holdState == .idle || holdState == .active {
                    animatedDirectionArrows
                }

                // Center overlay content
                VStack(spacing: 8) {
                    switch holdState {
                    case .holding:
                        Text("\(holdCountdown)")
                            .font(.system(size: 100, weight: .bold, design: .rounded))
                            .foregroundColor(successColor)
                            .shadow(color: successColor.opacity(glowOpacity), radius: 15)
                            .contentTransition(.numericText())
                            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: holdCountdown)
                        Text("HOLD")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(successColor.opacity(0.8))

                    case .relaxing:
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(successColor)
                            .shadow(color: successColor.opacity(glowOpacity), radius: 10)
                        Text("Relax")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.secondary)

                    case .active:
                        Text(gameState.phase == .squeezePhase ? "SQUEEZE" : "PULL")
                            .font(.system(size: 28, weight: .heavy))
                            .foregroundColor(gameState.phase == .squeezePhase ? .orange : .cyan)

                    case .idle:
                        VStack(spacing: 4) {
                            Text(gameState.phase == .squeezePhase ? "SQUEEZE" : "PULL")
                                .font(.system(size: 28, weight: .heavy))
                                .foregroundColor(gameState.phase == .squeezePhase ? .orange : .cyan)
                        }
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: holdState)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Progress bar (only visible when actively pushing toward target)
            targetProgressView
                .opacity(holdState == .active ? 1 : 0)
                .frame(height: 50)
                .padding(.horizontal)
                .padding(.bottom, 8)

            // Calibration prompt
            if showCalibrationPrompt {
                Button {
                    cancelHoldTimer()
                    holdState = .idle
                    calibrationTriggeredDuringExercise = true
                    onCancel()
                    ringConManager.startGuidedCalibration()
                    showingCalibration = true
                    showCalibrationPrompt = false
                } label: {
                    Text("Calibrate pressure?")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.borderless)
                .padding(.bottom, 8)
            }
        }
        .onChange(of: ringConManager.flexValue) { newValue in
            checkTargetReached(newValue)
            trackCalibrationNeed(newValue)
        }
        .onChange(of: gameState.phase) { _ in
            holdState = .idle
            failedAttemptTime = nil
            showCalibrationPrompt = false
        }
        .onChange(of: gameState.currentReps) { _ in
            failedAttemptTime = nil
            showCalibrationPrompt = false
        }
    }

    // MARK: - Target Progress

    private var targetProgressView: some View {
        let targetThreshold = gameState.difficulty.targetThreshold
        let startThreshold: Double = 0.55

        let progress: Double
        let encouragement: String

        if gameState.phase == .squeezePhase {
            let flexValue = ringConManager.flexValue
            if flexValue <= startThreshold {
                progress = 0
                encouragement = ""
            } else if flexValue >= targetThreshold {
                progress = 1
                encouragement = ""
            } else {
                progress = (flexValue - startThreshold) / (targetThreshold - startThreshold)
                if progress > 0.9 {
                    encouragement = "Almost there!"
                } else if progress > 0.6 {
                    encouragement = "Keep squeezing!"
                } else if progress > 0.2 {
                    encouragement = "Good, more!"
                } else {
                    encouragement = ""
                }
            }
        } else {
            let flexValue = ringConManager.flexValue
            let pullTarget = 1.0 - targetThreshold
            let pullStart = 1.0 - startThreshold
            if flexValue >= pullStart {
                progress = 0
                encouragement = ""
            } else if flexValue <= pullTarget {
                progress = 1
                encouragement = ""
            } else {
                progress = (pullStart - flexValue) / (pullStart - pullTarget)
                if progress > 0.9 {
                    encouragement = "Almost there!"
                } else if progress > 0.6 {
                    encouragement = "Keep pulling!"
                } else if progress > 0.2 {
                    encouragement = "Good, more!"
                } else {
                    encouragement = ""
                }
            }
        }

        return VStack(spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.2))

                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.green.opacity(0.3))
                        .frame(width: geo.size.width * 0.15)
                        .offset(x: geo.size.width * 0.85)

                    RoundedRectangle(cornerRadius: 8)
                        .fill(progressColor(for: progress))
                        .frame(width: geo.size.width * min(progress, 1.0))
                        .animation(.easeOut(duration: 0.1), value: progress)
                }
            }
            .frame(height: 16)
            .frame(maxWidth: 200)

            Text(encouragement.isEmpty ? " " : encouragement)
                .font(.headline)
                .foregroundColor(encouragement.isEmpty ? .clear : progressColor(for: progress))
                .frame(height: 20)
        }
    }

    private func progressColor(for progress: Double) -> Color {
        if progress > 0.85 {
            return .green
        } else if progress > 0.5 {
            return .yellow
        } else {
            return gameState.phase == .squeezePhase ? .orange : .cyan
        }
    }

    // MARK: - Target Detection

    private func checkTargetReached(_ flexValue: Double) {
        let targetThreshold = gameState.difficulty.targetThreshold
        let holdTolerance = gameState.difficulty.holdTolerance
        let holdMinThreshold = targetThreshold - holdTolerance
        let relaxedThreshold = 0.55

        if gameState.phase == .squeezePhase {
            if holdState == .holding {
                if flexValue < holdMinThreshold {
                    cancelHoldTimer()
                    withAnimation { holdState = .idle }
                }
            } else if holdState == .relaxing {
                if flexValue < relaxedThreshold {
                    withAnimation { holdState = .idle }
                }
            } else {
                if flexValue >= targetThreshold {
                    startHoldCountdown()
                } else if flexValue > relaxedThreshold && holdState == .idle {
                    holdState = .active
                } else if flexValue <= relaxedThreshold && holdState == .active {
                    holdState = .idle
                }
            }
        } else if gameState.phase == .pullPhase {
            let pullTarget = 1.0 - targetThreshold
            let pullHoldMin = 1.0 - holdMinThreshold
            let pullRelaxed = 1.0 - relaxedThreshold

            if holdState == .holding {
                if flexValue > pullHoldMin {
                    cancelHoldTimer()
                    withAnimation { holdState = .idle }
                }
            } else if holdState == .relaxing {
                if flexValue > pullRelaxed {
                    withAnimation { holdState = .idle }
                }
            } else {
                if flexValue <= pullTarget {
                    startHoldCountdown()
                } else if flexValue < pullRelaxed && holdState == .idle {
                    holdState = .active
                } else if flexValue >= pullRelaxed && holdState == .active {
                    holdState = .idle
                }
            }
        }
    }

    private func trackCalibrationNeed(_ flexValue: Double) {
        guard !showCalibrationPrompt else { return }
        guard gameState.phase == .squeezePhase || gameState.phase == .pullPhase else { return }
        guard holdState != .relaxing else { return }

        let targetThreshold = gameState.difficulty.targetThreshold

        let isAttempting: Bool
        if gameState.phase == .squeezePhase {
            let effortThreshold = 0.55 + (targetThreshold - 0.55) * 0.5
            isAttempting = flexValue > effortThreshold && flexValue < targetThreshold && holdState != .holding
        } else {
            let pullTarget = 1.0 - targetThreshold
            let effortThreshold = 0.45 - (0.45 - pullTarget) * 0.5
            isAttempting = flexValue < effortThreshold && flexValue > pullTarget && holdState != .holding
        }

        if isAttempting {
            if failedAttemptTime == nil {
                failedAttemptTime = Date()
            } else if let startTime = failedAttemptTime,
                      Date().timeIntervalSince(startTime) > calibrationPromptDelay {
                withAnimation { showCalibrationPrompt = true }
            }
        } else if holdState == .idle {
            failedAttemptTime = nil
        }
    }

    // MARK: - Hold Timer

    private func startHoldCountdown() {
        cancelHoldTimer()

        SoundHelper.play("Ping")
        withAnimation {
            holdState = .holding
            holdCountdown = holdDuration
        }

        holdTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            Task { @MainActor in
                if holdCountdown > 1 {
                    withAnimation { holdCountdown -= 1 }
                    SoundHelper.play("Tink")
                } else {
                    timer.invalidate()
                    holdTimer = nil
                    let isLastRep = gameState.currentReps + 1 >= gameState.targetReps
                    if !isLastRep {
                        SoundHelper.play("Glass")
                    }
                    gameState.incrementRep()
                    withAnimation { holdState = .relaxing }
                }
            }
        }
    }

    private func cancelHoldTimer() {
        holdTimer?.invalidate()
        holdTimer = nil
    }

    // MARK: - Animated Arrows

    private var animatedDirectionArrows: some View {
        let isSqueeze = gameState.phase == .squeezePhase
        let color = isSqueeze ? Color.orange : Color.cyan

        return HStack {
            HStack(spacing: -4) {
                ForEach(0..<2, id: \.self) { i in
                    Image(systemName: isSqueeze ? "chevron.compact.right" : "chevron.compact.left")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(color.opacity(0.4 + Double(i) * 0.3))
                        .offset(x: isSqueeze ? arrowAnimationPhase * 8 : -arrowAnimationPhase * 8)
                        .animation(
                            .easeInOut(duration: 0.8)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.15),
                            value: arrowAnimationPhase
                        )
                }
            }

            Spacer()

            HStack(spacing: -4) {
                ForEach(0..<2, id: \.self) { i in
                    Image(systemName: isSqueeze ? "chevron.compact.left" : "chevron.compact.right")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(color.opacity(0.4 + Double(1 - i) * 0.3))
                        .offset(x: isSqueeze ? -arrowAnimationPhase * 8 : arrowAnimationPhase * 8)
                        .animation(
                            .easeInOut(duration: 0.8)
                            .repeatForever(autoreverses: true)
                            .delay(Double(1 - i) * 0.15),
                            value: arrowAnimationPhase
                        )
                }
            }
        }
        .padding(.horizontal, 16)
        .onAppear { arrowAnimationPhase = 1 }
        .onDisappear { arrowAnimationPhase = 0 }
    }
}
