//
//  ConnectionStatus.swift
//  RingBreak
//
//  Two-device status bar showing Joy-Con and Ring-Con connection states

import SwiftUI

struct DeviceStatusBar: View {
    @ObservedObject var ringConManager: RingConManager

    var body: some View {
        HStack(spacing: 16) {
            joyConIndicator
            if ringConManager.connectionState == .connected || ringConManager.connectionState == .connecting {
                ringConIndicator
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(20)
    }

    // MARK: - Joy-Con Indicator

    @ViewBuilder
    private var joyConIndicator: some View {
        HStack(spacing: 6) {
            joyConDot
            Text("Joy-Con")
                .font(.caption2)
                .foregroundColor(.secondary)
            if ringConManager.connectionState == .scanning {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 10, height: 10)
            }
        }
    }

    @ViewBuilder
    private var joyConDot: some View {
        switch ringConManager.connectionState {
        case .disconnected:
            Circle().fill(Color.gray).frame(width: 8, height: 8)
        case .scanning:
            Circle().fill(Color.orange).frame(width: 8, height: 8)
        case .connecting, .connected:
            Circle().fill(Color.green).frame(width: 8, height: 8)
        }
    }

    // MARK: - Ring-Con Indicator

    @ViewBuilder
    private var ringConIndicator: some View {
        HStack(spacing: 6) {
            ringConDot
            Text("Ring-Con")
                .font(.caption2)
                .foregroundColor(.secondary)
            if !ringConManager.ringConAttached {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 10, height: 10)
            }
        }
    }

    @ViewBuilder
    private var ringConDot: some View {
        if ringConManager.ringConAttached {
            Circle().fill(Color.green).frame(width: 8, height: 8)
        } else {
            Circle().fill(Color.orange).frame(width: 8, height: 8)
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        DeviceStatusBar(ringConManager: RingConManager())
    }
    .padding()
}
