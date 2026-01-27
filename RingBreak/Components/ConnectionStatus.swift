//
//  ConnectionStatus.swift
//  RingBreak
//

import SwiftUI

struct ConnectionStatus: View {
    @ObservedObject var ringConManager: RingConManager

    private var statusColor: Color {
        switch ringConManager.connectionState {
        case .disconnected:
            return .red
        case .scanning:
            return .orange
        case .connecting:
            return .yellow
        case .connected:
            return ringConManager.ringConAttached ? .green : .blue
        }
    }

    private var statusText: String {
        switch ringConManager.connectionState {
        case .disconnected:
            return "Not Connected"
        case .scanning:
            return "Scanning..."
        case .connecting:
            return "Connecting..."
        case .connected:
            return ringConManager.ringConAttached ? "Ring-Con Ready" : "Joy-Con Connected"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)

            Text(statusText)
                .font(.subheadline)

            if ringConManager.connectionState == .scanning {
                SwiftUI.ProgressView()
                    .scaleEffect(0.6)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(20)
    }
}

#Preview {
    VStack(spacing: 20) {
        ConnectionStatus(ringConManager: RingConManager())
    }
    .padding()
}
