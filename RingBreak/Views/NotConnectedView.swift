//
//  NotConnectedView.swift
//  RingBreak
//
//  View shown when Ring-Con is not connected
//

import SwiftUI
import AppKit

struct NotConnectedView: View {
    @ObservedObject var ringConManager: RingConManager
    @ObservedObject var gameState: BreakGameState
    let displayFlexValue: Double
    let onSettingsTapped: () -> Void
    let onStreakTapped: () -> Void

    @State private var isStreakHovered = false
    @State private var isSettingsHovered = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            // HEADER - at top, fixed size
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

            // CENTER AREA - ring is rendered by parent, we show overlays
            ZStack {
                connectionInstructionsView
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Button below the ring
            Button(action: {
                #if DEBUG
                DebugLogger.shared.clear()
                #endif
                ringConManager.checkBluetoothAndDeviceStatus()
                ringConManager.startScanning()
            }) {
                HStack(spacing: 8) {
                    if ringConManager.connectionState == .scanning || ringConManager.connectionState == .connecting {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 16, height: 16)
                    }
                    Text(scanButtonLabel)
                }
                .frame(width: 160)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(ringConManager.connectionState == .scanning || ringConManager.connectionState == .connecting || ringConManager.bluetoothStatus == .off || ringConManager.bluetoothStatus == .unauthorized)
            .padding(.bottom, 8)

            // STATUS - at bottom, fixed size
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 6, height: 6)
                    Text(statusText)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                if let error = ringConManager.lastError {
                    Text(error)
                        .font(.caption2)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                } else {
                    Text(" ")
                        .font(.caption2)
                        .padding(.horizontal)
                }
            }
            .frame(height: 50)
            .padding(.bottom, 12)
        }
        .onAppear {
            ringConManager.checkBluetoothAndDeviceStatus()
        }
    }

    @ViewBuilder
    private var connectionInstructionsView: some View {
        VStack(spacing: 8) {
            if ringConManager.bluetoothStatus == .unauthorized {
                Image(systemName: "hand.raised.circle")
                    .font(.title)
                    .foregroundColor(.red)
                Text("Bluetooth Permission Required")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Button("Open System Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.link)
                .font(.subheadline)
            } else if ringConManager.bluetoothStatus == .off {
                Image(systemName: "antenna.radiowaves.left.and.right.slash")
                    .font(.title)
                    .foregroundColor(.red)
                Text("Turn on Bluetooth")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else if ringConManager.pairedDeviceStatus == .pairedAndConnected {
                Image(systemName: "checkmark.circle")
                    .font(.title)
                    .foregroundColor(.green)
                Text("Joy-Con Ready")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else if ringConManager.pairedDeviceStatus == .pairedNotConnected {
                Text("Press any button on Joy-Con")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                Text("Pair Joy-Con (R) in\nSystem Settings → Bluetooth")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var scanButtonLabel: String {
        switch ringConManager.connectionState {
        case .scanning: return "Scanning..."
        case .connecting: return "Connecting..."
        default:
            if ringConManager.pairedDeviceStatus == .pairedAndConnected {
                return "Connect"
            } else {
                return "Scan for Joy-Con"
            }
        }
    }

    private var statusColor: Color {
        switch ringConManager.connectionState {
        case .connected: return .green
        case .scanning, .connecting: return .orange
        default: return .red
        }
    }

    private var statusText: String {
        switch ringConManager.connectionState {
        case .connected: return "Connected"
        case .scanning: return "Scanning..."
        case .connecting: return "Connecting..."
        default: return "Not connected"
        }
    }
}
