//
//  CalibrationView.swift
//  RingBreak
//

import SwiftUI

struct CalibrationView: View {
    @ObservedObject var ringConManager: RingConManager
    let onClose: () -> Void

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
        default:
            return "Starting calibration..."
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            Text(title)
                .font(.title)
                .fontWeight(.bold)

            Text(instruction)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            if ringConManager.calibrationPhase != .complete {
                Text("\(ringConManager.calibrationSecondsRemaining)s")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .monospacedDigit()
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.green)
            }

            HStack(spacing: 12) {
                Button("Cancel") {
                    ringConManager.cancelCalibration()
                    onClose()
                }
                .buttonStyle(.bordered)

                if ringConManager.calibrationPhase == .complete {
                    Button("Done") {
                        onClose()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .frame(minWidth: 420, minHeight: 260)
        .padding()
        .onChange(of: ringConManager.calibrationPhase) { newPhase in
            if newPhase == .complete {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    onClose()
                }
            }
        }
    }
}

#Preview {
    CalibrationView(ringConManager: RingConManager()) {}
}
