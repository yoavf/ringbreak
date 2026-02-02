//
//  RingConDisconnectedOverlay.swift
//  RingBreak
//
//  Lightweight overlay shown when Ring-Con detaches mid-exercise
//

import SwiftUI

struct RingConDisconnectedOverlay: View {
    @ObservedObject var gameState: BreakGameState
    let onQuit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Top bar — matches ExerciseView layout
            HStack {
                Button {
                    onQuit()
                } label: {
                    Image(systemName: "xmark")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                Spacer()
                Text("\(gameState.currentReps)/\(gameState.targetReps)")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.top)
            .fixedSize(horizontal: false, vertical: true)

            // Center — spinner + message
            Spacer()
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                Text("Ring-Con Disconnected")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
                Text("Reattach to continue")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
    }
}
