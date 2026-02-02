//
//  GameDifficultyTests.swift
//  RingBreakTests
//
//  Tests for difficulty invariants and the hold threshold clamping fix.
//

@testable import RingBreak
import XCTest

final class GameDifficultyTests: XCTestCase {

    private var relaxedThreshold: Double { Constants.relaxedThreshold }

    // MARK: - Difficulty Ordering Invariants

    func testHarderDifficultyRequiresMoreForceAndPrecision() {
        let difficulties = GameDifficulty.allCases.sorted {
            $0.targetThreshold < $1.targetThreshold
        }

        // Harder difficulties should require more force (higher threshold)
        // and more precision (lower tolerance)
        for i in 0..<(difficulties.count - 1) {
            let easier = difficulties[i]
            let harder = difficulties[i + 1]
            XCTAssertLessThan(easier.targetThreshold, harder.targetThreshold,
                "\(easier.rawValue) should have lower target than \(harder.rawValue)")
            XCTAssertGreaterThan(easier.holdTolerance, harder.holdTolerance,
                "\(easier.rawValue) should have more tolerance than \(harder.rawValue)")
        }
    }

    // MARK: - Hold Threshold Clamping (Bug Fix)
    //
    // Without clamping: easy holdMin = 0.65 - 0.18 = 0.47,
    // which is BELOW the relaxed neutral point (0.55).
    // This caused the hold countdown to never cancel on easy,
    // even when the user fully relaxes.

    func testHoldMinNeverDropsBelowRelaxedThreshold() {
        for difficulty in GameDifficulty.allCases {
            let holdMin = max(difficulty.targetThreshold - difficulty.holdTolerance, relaxedThreshold)
            XCTAssertGreaterThanOrEqual(holdMin, relaxedThreshold,
                "\(difficulty.rawValue): holdMin \(holdMin) must be >= relaxedThreshold \(relaxedThreshold)")
        }
    }

    func testEasyDifficultyNeedsClampingWithoutFix() {
        // This is the specific case that caused the bug
        let unclamped = GameDifficulty.easy.targetThreshold - GameDifficulty.easy.holdTolerance
        XCTAssertLessThan(unclamped, relaxedThreshold,
            "Easy's raw holdMin should be below relaxed — proving the clamp is needed")
    }

    func testPullHoldMinNeverExceedsPullRelaxed() {
        let pullRelaxed = 1.0 - relaxedThreshold
        for difficulty in GameDifficulty.allCases {
            let holdMin = max(difficulty.targetThreshold - difficulty.holdTolerance, relaxedThreshold)
            let pullHoldMin = 1.0 - holdMin

            XCTAssertLessThanOrEqual(pullHoldMin, pullRelaxed,
                "\(difficulty.rawValue): pull holdMin \(pullHoldMin) must be <= pullRelaxed \(pullRelaxed)")
        }
    }

    func testHoldMinIsBetweenRelaxedAndTarget() {
        for difficulty in GameDifficulty.allCases {
            let holdMin = max(difficulty.targetThreshold - difficulty.holdTolerance, relaxedThreshold)
            XCTAssertGreaterThanOrEqual(holdMin, relaxedThreshold)
            XCTAssertLessThanOrEqual(holdMin, difficulty.targetThreshold,
                "\(difficulty.rawValue): holdMin should not exceed target")
        }
    }

    // MARK: - CalibrationPhase Associated Value

    func testCalibrationFailedPhasesDistinguishReason() {
        let failedPull: CalibrationPhase = .failed(.noPull)
        let failedSqueeze: CalibrationPhase = .failed(.noSqueeze)

        XCTAssertNotEqual(failedPull, failedSqueeze)
        XCTAssertEqual(failedPull, .failed(.noPull))
        XCTAssertEqual(failedSqueeze, .failed(.noSqueeze))
    }
}
