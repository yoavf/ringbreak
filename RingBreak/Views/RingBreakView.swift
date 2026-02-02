//
//  RingBreakView.swift
//  RingBreak
//
//  Main view for the Ring Break fitness app
//

import SwiftUI
import AppKit

/// Navigation screens for in-place navigation
enum AppScreen {
    case main
    case settings
    case streakGraph
}

struct RingBreakView: View {
    @ObservedObject var ringConManager: RingConManager
    @ObservedObject var menubarController: MenubarController
    @StateObject private var gameState = BreakGameState()
    @State private var showingCalibration = false
    @State private var currentScreen: AppScreen = .main
    @Environment(\.colorScheme) private var colorScheme

    // Pre-exercise countdown (shared with ReadyView)
    @State private var startCountdown: Int = 0
    @State private var isCountingDown = false
    @State private var countdownTimer: Timer?

    private var backgroundColor: Color {
        AppColors.background(for: colorScheme)
    }

    private var displayFlexValue: Double {
        ringConManager.isConnected ? ringConManager.flexValue : 0.5
    }

    var body: some View {
        currentScreenView
            .frame(width: 420, height: 620, alignment: .top)
            .background(backgroundColor)
            .sheet(isPresented: $showingCalibration) {
                CalibrationView(ringConManager: ringConManager) {
                    showingCalibration = false
                }
            }
    }

    @ViewBuilder
    private var currentScreenView: some View {
        switch currentScreen {
        case .main:
            mainContentView
        case .settings:
            SettingsView(
                gameState: gameState,
                ringConManager: ringConManager,
                menubarController: menubarController,
                onBack: { currentScreen = .main }
            )
        case .streakGraph:
            StreakGraphView(
                gameState: gameState,
                onBack: { currentScreen = .main }
            )
        }
    }

    // MARK: - Main Content View

    /// Whether the 3D ring should be shown (phases that display the ring)
    private var showsRing: Bool {
        switch gameState.phase {
        case .notConnected, .ready, .squeezePhase, .pullPhase:
            return true
        case .celebration:
            return false
        }
    }

    /// Ring scale - smaller when in ready state (not counting down), same size for countdown and exercise
    private var ringScale: CGFloat {
        if gameState.phase == .ready && !isCountingDown {
            return 0.85
        }
        // Same size for countdown and exercise phases to avoid blink
        return 0.9
    }

    private var mainContentView: some View {
        ZStack {
            // Persistent 3D ring view - never destroyed during phase transitions
            if showsRing {
                RingConSceneView(flexValue: displayFlexValue)
                    .scaleEffect(ringScale)
                    .animation(.spring(response: 0.5, dampingFraction: 0.7), value: ringScale)
            }

            // Phase-specific UI overlaid on top
            switch gameState.phase {
            case .notConnected:
                NotConnectedView(
                    ringConManager: ringConManager,
                    gameState: gameState,
                    displayFlexValue: displayFlexValue,
                    onSettingsTapped: { currentScreen = .settings },
                    onStreakTapped: { currentScreen = .streakGraph }
                )
            case .ready:
                ReadyView(
                    ringConManager: ringConManager,
                    gameState: gameState,
                    isCountingDown: $isCountingDown,
                    startCountdown: $startCountdown,
                    onSettingsTapped: { currentScreen = .settings },
                    onStreakTapped: { currentScreen = .streakGraph },
                    onStartExercise: { }
                )
            case .squeezePhase, .pullPhase:
                ExerciseView(
                    ringConManager: ringConManager,
                    gameState: gameState,
                    showingCalibration: $showingCalibration,
                    onCancel: { gameState.returnToHome() }
                )
            case .celebration:
                CelebrationView(
                    gameState: gameState,
                    onHome: { gameState.returnToHome() },
                    onDoAnother: { startWithCountdown() }
                )
            }
        }
        .onAppear {
            updateGameState()
            ringConManager.autoConnectIfAvailable()
        }
        .onChange(of: ringConManager.isConnected) { _ in
            updateGameState()
        }
        .onChange(of: ringConManager.ringConAttached) { _ in
            updateGameState()
        }
    }

    private func updateGameState() {
        gameState.updateConnectionStatus(
            isConnected: ringConManager.isConnected,
            ringConAttached: ringConManager.ringConAttached
        )
    }

    private func startWithCountdown() {
        guard !isCountingDown else { return }

        isCountingDown = true
        startCountdown = 3

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
                    withAnimation {
                        isCountingDown = false
                        gameState?.startExercise()
                    }
                }
            }
        }
    }
}

#Preview {
    RingBreakView(ringConManager: RingConManager(), menubarController: MenubarController())
}
