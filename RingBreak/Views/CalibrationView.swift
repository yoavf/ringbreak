//
//  CalibrationView.swift
//  RingBreak
//

import SwiftUI

struct CalibrationView: View {
    @ObservedObject var ringConManager: RingConManager
    let onClose: () -> Void

    private var isFailed: Bool {
        if case .failed = ringConManager.calibrationPhase { return true }
        return false
    }

    private var title: String {
        switch ringConManager.calibrationPhase {
        case .neutral:
            return "Hold Neutral"
        case .pull:
            return "Pull Hardest"
        case .squeeze:
            return "Squeeze Hardest"
        case .complete:
            return "Calibration Complete"
        case .failed:
            return "Calibration Failed"
        default:
            return "Calibration"
        }
    }

    private var instruction: String {
        switch ringConManager.calibrationPhase {
        case .neutral:
            return "Hold the Ring-Con steady with no pull or squeeze."
        case .pull:
            return "Pull the Ring-Con apart as hard as you can."
        case .squeeze:
            return "Squeeze the Ring-Con as hard as you can."
        case .complete:
            return "You're all set. This range will be used for flex scaling."
        case .failed(let reason):
            switch reason {
            case .noPull:
                return "No pull was detected. Make sure the Ring-Con is attached and try again."
            case .noSqueeze:
                return "No squeeze was detected. Make sure the Ring-Con is attached and try again."
            }
        default:
            return "Starting calibration..."
        }
    }

    /// Target flex value for the 3D model based on current calibration phase
    /// 0.0 = full pull, 0.5 = neutral, 1.0 = full squeeze
    private var targetFlexValue: Double {
        switch ringConManager.calibrationPhase {
        case .neutral:
            return 0.5
        case .pull:
            return 0.0
        case .squeeze:
            return 1.0
        case .complete, .failed:
            return 0.5
        default:
            return 0.5
        }
    }

    var body: some View {
        HStack(spacing: 24) {
            // 3D model preview showing target position
            RingConSceneView(flexValue: targetFlexValue)
                .frame(width: 120, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )

            VStack(spacing: 16) {
                Text(title)
                    .font(.title)
                    .fontWeight(.bold)

                Text(instruction)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: 240)

                if ringConManager.calibrationPhase == .complete {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.green)
                } else if isFailed {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.orange)
                } else {
                    Text("\(ringConManager.calibrationSecondsRemaining)s")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }

                if isFailed {
                    HStack(spacing: 12) {
                        Button("Cancel") {
                            onClose()
                        }
                        .buttonStyle(.bordered)

                        Button("Retry") {
                            ringConManager.startGuidedCalibration()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else if ringConManager.calibrationPhase == .complete {
                    VStack(spacing: 20) {
                        Button("Done") {
                            onClose()
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Redo calibration") {
                            ringConManager.startGuidedCalibration()
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.accentColor)
                        .font(.caption)
                    }
                } else {
                    Button("Cancel") {
                        ringConManager.cancelCalibration()
                        onClose()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .frame(minWidth: 480, minHeight: 280)
        .padding()
        .onAppear {
            if !ringConManager.isCalibrating {
                ringConManager.startGuidedCalibration()
            }
        }
        .onChange(of: ringConManager.isConnected) { connected in
            if !connected {
                ringConManager.cancelCalibration()
                onClose()
            }
        }
    }
}

#Preview {
    CalibrationView(ringConManager: RingConManager()) {}
}
