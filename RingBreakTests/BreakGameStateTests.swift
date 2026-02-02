//
//  BreakGameStateTests.swift
//  RingBreakTests
//
//  Tests for the BreakGameState state machine, focusing on:
//  - Connection transitions
//  - Pause/resume on Ring-Con detach (with debounce)
//  - Exercise flow and phase alternation
//  - Quit from pause
//

@testable import RingBreak
import XCTest

@MainActor
final class BreakGameStateTests: XCTestCase {
    var gameState: BreakGameState!

    override func setUp() {
        super.setUp()
        clearGameStateDefaults()
        gameState = BreakGameState()
    }

    override func tearDown() {
        gameState = nil
        clearGameStateDefaults()
        super.tearDown()
    }

    /// Clear UserDefaults keys used by BreakGameState to ensure test isolation
    private func clearGameStateDefaults() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: UserDefaultsKeys.dailyStreak)
        defaults.removeObject(forKey: UserDefaultsKeys.lastExerciseDate)
        defaults.removeObject(forKey: UserDefaultsKeys.sessionsToday)
        defaults.removeObject(forKey: UserDefaultsKeys.sessionsTodayDate)
        defaults.removeObject(forKey: UserDefaultsKeys.sessionsThisWeek)
        defaults.removeObject(forKey: UserDefaultsKeys.weekStartDate)
        defaults.removeObject(forKey: UserDefaultsKeys.difficulty)
        defaults.removeObject(forKey: UserDefaultsKeys.dailyHistory)
    }

    // MARK: - Initial State

    func testInitialPhaseIsNotConnected() {
        XCTAssertEqual(gameState.phase, .notConnected)
        XCTAssertEqual(gameState.currentReps, 0)
        XCTAssertEqual(gameState.totalProgress, 0)
        XCTAssertNil(gameState.pausedFromPhase)
    }

    // MARK: - Connection Status Transitions

    func testConnectedWithRingConTransitionsToReady() {
        gameState.updateConnectionStatus(isConnected: true, ringConAttached: true)
        XCTAssertEqual(gameState.phase, .ready)
    }

    func testConnectedWithoutRingConStaysNotConnected() {
        // Connected Joy-Con but no Ring-Con, from notConnected → stays notConnected
        gameState.updateConnectionStatus(isConnected: true, ringConAttached: false)
        XCTAssertEqual(gameState.phase, .notConnected)
    }

    func testDisconnectedFromReadyTransitionsToNotConnected() {
        gameState.updateConnectionStatus(isConnected: true, ringConAttached: true)
        XCTAssertEqual(gameState.phase, .ready)

        gameState.updateConnectionStatus(isConnected: false, ringConAttached: false)
        XCTAssertEqual(gameState.phase, .notConnected)
    }

    func testRingConDetachDuringReadyTransitionsToNotConnected() {
        gameState.updateConnectionStatus(isConnected: true, ringConAttached: true)
        XCTAssertEqual(gameState.phase, .ready)

        // Ring-Con detach outside exercise: nothing to preserve
        gameState.updateConnectionStatus(isConnected: true, ringConAttached: false)
        XCTAssertEqual(gameState.phase, .notConnected)
    }

    func testReconnectFromNotConnectedGoesToReady() {
        gameState.updateConnectionStatus(isConnected: true, ringConAttached: true)
        gameState.updateConnectionStatus(isConnected: false, ringConAttached: false)
        XCTAssertEqual(gameState.phase, .notConnected)

        gameState.updateConnectionStatus(isConnected: true, ringConAttached: true)
        XCTAssertEqual(gameState.phase, .ready)
    }

    // MARK: - Pause on Ring-Con Detach During Exercise

    func testRingConDetachDuringExerciseDoesNotImmediatelyPause() {
        gameState.updateConnectionStatus(isConnected: true, ringConAttached: true)
        gameState.startExercise()
        XCTAssertEqual(gameState.phase, .squeezePhase)

        // Detach: debounce starts, should NOT immediately pause
        gameState.updateConnectionStatus(isConnected: true, ringConAttached: false)
        XCTAssertEqual(gameState.phase, .squeezePhase)
    }

    func testRingConDetachDuringExercisePausesAfterDebounce() async {
        gameState.updateConnectionStatus(isConnected: true, ringConAttached: true)
        gameState.startExercise()
        XCTAssertEqual(gameState.phase, .squeezePhase)

        gameState.updateConnectionStatus(isConnected: true, ringConAttached: false)

        // Wait for debounce (1.5s + margin)
        try? await Task.sleep(nanoseconds: UInt64((Constants.pauseDebounceDuration + 0.3) * 1_000_000_000))

        XCTAssertEqual(gameState.phase, .paused)
        XCTAssertEqual(gameState.pausedFromPhase, .squeezePhase)
    }

    func testRingConReattachCancelsPauseDebounce() async {
        gameState.updateConnectionStatus(isConnected: true, ringConAttached: true)
        gameState.startExercise()

        // Detach
        gameState.updateConnectionStatus(isConnected: true, ringConAttached: false)

        // Wait a bit but less than debounce
        try? await Task.sleep(nanoseconds: UInt64(Constants.pauseDebounceDuration * 0.3 * 1_000_000_000))

        // Reattach before debounce fires
        gameState.updateConnectionStatus(isConnected: true, ringConAttached: true)
        XCTAssertEqual(gameState.phase, .squeezePhase)

        // Wait past debounce time to confirm it was cancelled
        try? await Task.sleep(nanoseconds: UInt64((Constants.pauseDebounceDuration + 0.3) * 1_000_000_000))
        XCTAssertEqual(gameState.phase, .squeezePhase)
    }

    func testResumeFromPauseOnRingConReattach() async {
        gameState.updateConnectionStatus(isConnected: true, ringConAttached: true)
        gameState.startExercise()

        // Pause via debounce
        gameState.updateConnectionStatus(isConnected: true, ringConAttached: false)
        try? await Task.sleep(nanoseconds: UInt64((Constants.pauseDebounceDuration + 0.3) * 1_000_000_000))
        XCTAssertEqual(gameState.phase, .paused)
        XCTAssertEqual(gameState.pausedFromPhase, .squeezePhase)

        // Reattach
        gameState.updateConnectionStatus(isConnected: true, ringConAttached: true)
        XCTAssertEqual(gameState.phase, .squeezePhase)
        XCTAssertNil(gameState.pausedFromPhase)
    }

    func testPauseAndResumeFromPullPhase() async {
        gameState.updateConnectionStatus(isConnected: true, ringConAttached: true)
        gameState.startExercise()
        gameState.incrementRep() // squeezePhase → pullPhase
        XCTAssertEqual(gameState.phase, .pullPhase)

        // Pause
        gameState.updateConnectionStatus(isConnected: true, ringConAttached: false)
        try? await Task.sleep(nanoseconds: UInt64((Constants.pauseDebounceDuration + 0.3) * 1_000_000_000))
        XCTAssertEqual(gameState.phase, .paused)
        XCTAssertEqual(gameState.pausedFromPhase, .pullPhase)

        // Resume
        gameState.updateConnectionStatus(isConnected: true, ringConAttached: true)
        XCTAssertEqual(gameState.phase, .pullPhase)
    }

    func testFullDisconnectDuringPauseGoesToNotConnected() async {
        gameState.updateConnectionStatus(isConnected: true, ringConAttached: true)
        gameState.startExercise()

        // Pause
        gameState.updateConnectionStatus(isConnected: true, ringConAttached: false)
        try? await Task.sleep(nanoseconds: UInt64((Constants.pauseDebounceDuration + 0.3) * 1_000_000_000))
        XCTAssertEqual(gameState.phase, .paused)

        // Full Bluetooth disconnect
        gameState.updateConnectionStatus(isConnected: false, ringConAttached: false)
        XCTAssertEqual(gameState.phase, .notConnected)
        XCTAssertNil(gameState.pausedFromPhase)
    }

    func testFullDisconnectDuringDebounceGoesToNotConnected() {
        gameState.updateConnectionStatus(isConnected: true, ringConAttached: true)
        gameState.startExercise()

        // Start debounce
        gameState.updateConnectionStatus(isConnected: true, ringConAttached: false)
        XCTAssertEqual(gameState.phase, .squeezePhase)

        // Full disconnect before debounce fires
        gameState.updateConnectionStatus(isConnected: false, ringConAttached: false)
        XCTAssertEqual(gameState.phase, .notConnected)
    }

    func testRingConDetachWhileAlreadyPausedIsNoOp() async {
        gameState.updateConnectionStatus(isConnected: true, ringConAttached: true)
        gameState.startExercise()

        // Pause
        gameState.updateConnectionStatus(isConnected: true, ringConAttached: false)
        try? await Task.sleep(nanoseconds: UInt64((Constants.pauseDebounceDuration + 0.3) * 1_000_000_000))
        XCTAssertEqual(gameState.phase, .paused)

        // Another detach while already paused
        gameState.updateConnectionStatus(isConnected: true, ringConAttached: false)
        XCTAssertEqual(gameState.phase, .paused)
    }

    func testRingConDetachDuringCelebrationGoesToNotConnected() {
        gameState.updateConnectionStatus(isConnected: true, ringConAttached: true)
        gameState.startExercise()
        for _ in 0..<gameState.targetReps {
            gameState.incrementRep()
        }
        XCTAssertEqual(gameState.phase, .celebration)

        // Detach during celebration: nothing to preserve → notConnected
        gameState.updateConnectionStatus(isConnected: true, ringConAttached: false)
        XCTAssertEqual(gameState.phase, .notConnected)
    }

    // MARK: - Quit from Pause

    func testQuitFromPauseResetsToReady() async {
        gameState.updateConnectionStatus(isConnected: true, ringConAttached: true)
        gameState.startExercise()
        gameState.incrementRep() // 1 rep completed

        // Pause
        gameState.updateConnectionStatus(isConnected: true, ringConAttached: false)
        try? await Task.sleep(nanoseconds: UInt64((Constants.pauseDebounceDuration + 0.3) * 1_000_000_000))
        XCTAssertEqual(gameState.phase, .paused)

        gameState.quitFromPause()
        XCTAssertEqual(gameState.phase, .ready)
        XCTAssertEqual(gameState.currentReps, 0)
        XCTAssertEqual(gameState.totalProgress, 0)
        XCTAssertNil(gameState.pausedFromPhase)
    }

    // MARK: - Start Exercise

    func testStartExerciseFromReady() {
        gameState.updateConnectionStatus(isConnected: true, ringConAttached: true)
        gameState.startExercise()
        XCTAssertEqual(gameState.phase, .squeezePhase)
        XCTAssertEqual(gameState.currentReps, 0)
        XCTAssertEqual(gameState.totalProgress, 0)
    }

    func testStartExerciseFromNotConnectedIsNoOp() {
        gameState.startExercise()
        XCTAssertEqual(gameState.phase, .notConnected)
    }

    func testStartExerciseFromCelebration() {
        gameState.updateConnectionStatus(isConnected: true, ringConAttached: true)
        gameState.startExercise()
        for _ in 0..<gameState.targetReps {
            gameState.incrementRep()
        }
        XCTAssertEqual(gameState.phase, .celebration)

        // "Do another" flow
        gameState.startExercise()
        XCTAssertEqual(gameState.phase, .squeezePhase)
        XCTAssertEqual(gameState.currentReps, 0)
    }

    // MARK: - Rep Counting and Phase Alternation

    func testIncrementRepAlternatesPhases() {
        gameState.updateConnectionStatus(isConnected: true, ringConAttached: true)
        gameState.startExercise()
        XCTAssertEqual(gameState.phase, .squeezePhase)

        gameState.incrementRep()
        XCTAssertEqual(gameState.phase, .pullPhase)
        XCTAssertEqual(gameState.currentReps, 1)

        gameState.incrementRep()
        XCTAssertEqual(gameState.phase, .squeezePhase)
        XCTAssertEqual(gameState.currentReps, 2)
    }

    func testIncrementRepTriggersCelebrationAtTarget() {
        gameState.updateConnectionStatus(isConnected: true, ringConAttached: true)
        gameState.startExercise()

        for _ in 0..<gameState.targetReps {
            gameState.incrementRep()
        }

        XCTAssertEqual(gameState.phase, .celebration)
        XCTAssertEqual(gameState.totalProgress, 1.0)
        XCTAssertEqual(gameState.currentReps, gameState.targetReps)
    }

    func testProgressUpdatesWithReps() {
        gameState.updateConnectionStatus(isConnected: true, ringConAttached: true)
        gameState.startExercise()

        gameState.incrementRep()
        let expectedProgress = 1.0 / Double(gameState.targetReps)
        XCTAssertEqual(gameState.totalProgress, expectedProgress, accuracy: 0.001)

        gameState.incrementRep()
        let expectedProgress2 = 2.0 / Double(gameState.targetReps)
        XCTAssertEqual(gameState.totalProgress, expectedProgress2, accuracy: 0.001)
    }

    // MARK: - Return to Home

    func testReturnToHomeFromExercise() {
        gameState.updateConnectionStatus(isConnected: true, ringConAttached: true)
        gameState.startExercise()
        gameState.incrementRep()

        gameState.returnToHome()
        XCTAssertEqual(gameState.phase, .ready)
        XCTAssertEqual(gameState.currentReps, 0)
        XCTAssertEqual(gameState.totalProgress, 0)
    }

    func testReturnToHomeFromCelebration() {
        gameState.updateConnectionStatus(isConnected: true, ringConAttached: true)
        gameState.startExercise()
        for _ in 0..<gameState.targetReps {
            gameState.incrementRep()
        }
        XCTAssertEqual(gameState.phase, .celebration)

        gameState.returnToHome()
        XCTAssertEqual(gameState.phase, .ready)
        XCTAssertEqual(gameState.currentReps, 0)
    }

    func testResetFromExercise() {
        gameState.updateConnectionStatus(isConnected: true, ringConAttached: true)
        gameState.startExercise()
        gameState.incrementRep()

        gameState.reset()
        XCTAssertEqual(gameState.phase, .ready)
        XCTAssertEqual(gameState.currentReps, 0)
        XCTAssertEqual(gameState.totalProgress, 0)
    }

    // MARK: - "Do Another" Flow

    func testDoAnotherRequiresReturnToHomeFirst() {
        gameState.updateConnectionStatus(isConnected: true, ringConAttached: true)
        gameState.startExercise()
        for _ in 0..<gameState.targetReps {
            gameState.incrementRep()
        }
        XCTAssertEqual(gameState.phase, .celebration)

        // The fix: returnToHome before startExercise for "Do Another"
        gameState.returnToHome()
        XCTAssertEqual(gameState.phase, .ready)

        gameState.startExercise()
        XCTAssertEqual(gameState.phase, .squeezePhase)
        XCTAssertEqual(gameState.currentReps, 0)
        XCTAssertEqual(gameState.totalProgress, 0)
    }

    // MARK: - Multiple Debounce Prevention

    func testMultipleDetachEventsDoNotCreateMultipleDebounces() async {
        gameState.updateConnectionStatus(isConnected: true, ringConAttached: true)
        gameState.startExercise()

        // Multiple detach events in quick succession
        gameState.updateConnectionStatus(isConnected: true, ringConAttached: false)
        gameState.updateConnectionStatus(isConnected: true, ringConAttached: false)
        gameState.updateConnectionStatus(isConnected: true, ringConAttached: false)

        // Should still be in exercise (single debounce in progress)
        XCTAssertEqual(gameState.phase, .squeezePhase)

        // Wait for debounce
        try? await Task.sleep(nanoseconds: UInt64((Constants.pauseDebounceDuration + 0.3) * 1_000_000_000))
        XCTAssertEqual(gameState.phase, .paused)
    }

    // MARK: - Session Recording

    func testCompletedSessionRecordsStats() {
        gameState.updateConnectionStatus(isConnected: true, ringConAttached: true)
        gameState.startExercise()
        let initialSessionsToday = gameState.sessionsToday

        for _ in 0..<gameState.targetReps {
            gameState.incrementRep()
        }

        XCTAssertEqual(gameState.sessionsToday, initialSessionsToday + 1)
    }

    func testPartialSessionDoesNotRecordStats() {
        gameState.updateConnectionStatus(isConnected: true, ringConAttached: true)
        gameState.startExercise()
        let initialSessionsToday = gameState.sessionsToday

        // Only do a few reps, then cancel
        gameState.incrementRep()
        gameState.incrementRep()
        gameState.returnToHome()

        XCTAssertEqual(gameState.sessionsToday, initialSessionsToday)
    }

    // MARK: - Difficulty

    func testDifficultyPersistsToUserDefaults() {
        gameState.difficulty = .hard
        XCTAssertEqual(
            UserDefaults.standard.string(forKey: UserDefaultsKeys.difficulty),
            "Hard"
        )

        gameState.difficulty = .easy
        XCTAssertEqual(
            UserDefaults.standard.string(forKey: UserDefaultsKeys.difficulty),
            "Easy"
        )
    }
}
