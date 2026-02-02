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
    @State private var dotCount = 0
    @State private var dotTimer: Timer?

    /// Joy-Con is connected at the HID level (connecting/connected)
    private var joyConActive: Bool {
        ringConManager.connectionState == .connected || ringConManager.connectionState == .connecting
    }

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

            // Button below the ring — hidden when Joy-Con is connected (nothing for user to do)
            if !joyConActive {
                Button {
                    #if DEBUG
                    DebugLogger.shared.clear()
                    #endif
                    ringConManager.checkBluetoothAndDeviceStatus()
                    ringConManager.startScanning()
                } label: {
                    HStack(spacing: 8) {
                        if ringConManager.connectionState == .scanning {
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
                .disabled(
                    ringConManager.connectionState == .scanning
                    || ringConManager.bluetoothStatus == .off
                    || ringConManager.bluetoothStatus == .unauthorized
                )
                .padding(.bottom, 8)
            } else {
                // Spacer to keep layout stable when button is hidden
                Color.clear
                    .frame(height: 44)
                    .padding(.bottom, 8)
            }

            // STATUS - at bottom, fixed size
            VStack(spacing: 4) {
                DeviceStatusBar(ringConManager: ringConManager)

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
            if ringConManager.bluetoothStatus == .unknown {
                // Waiting for Bluetooth authorization/state — show nothing
                EmptyView()
            } else if ringConManager.bluetoothStatus == .unauthorized {
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
            } else if ringConManager.connectionState == .connecting {
                // MCU initialization in progress — we found the Joy-Con
                HStack(spacing: 0) {
                    Text("Setting up Ring-Con")
                    Text(".").opacity(dotCount >= 0 ? 1 : 0)
                    Text(".").opacity(dotCount >= 1 ? 1 : 0)
                    Text(".").opacity(dotCount >= 2 ? 1 : 0)
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
                .onAppear { startDotAnimation() }
                .onDisappear { dotTimer?.invalidate(); dotTimer = nil; dotCount = 0 }
            } else if ringConManager.connectionState == .connected && !ringConManager.ringConAttached {
                // MCU ready, scanning for Ring-Con presence
                HStack(spacing: 0) {
                    Text("Looking for Ring-Con")
                    Text(".").opacity(dotCount >= 0 ? 1 : 0)
                    Text(".").opacity(dotCount >= 1 ? 1 : 0)
                    Text(".").opacity(dotCount >= 2 ? 1 : 0)
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
                .onAppear { startDotAnimation() }
                .onDisappear { dotTimer?.invalidate(); dotTimer = nil; dotCount = 0 }
                Text("Make sure Joy-Con is inserted in Ring-Con")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            } else if ringConManager.lastError != nil {
                // Connection failed — show error with guidance
                Text("Connection failed")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text("Press Connect to try again")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if ringConManager.pairedDeviceStatus == .pairedNotConnected {
                Text("Press any button on Joy-Con")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else if ringConManager.pairedDeviceStatus == .pairedAndConnected {
                Text("Joy-Con detected")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                Text("Pair Joy-Con (R) in\nSystem Settings \u{2192} Bluetooth")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func startDotAnimation() {
        dotTimer?.invalidate()
        dotCount = 0
        dotTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
            Task { @MainActor in
                guard joyConActive else {
                    timer.invalidate()
                    dotTimer = nil
                    return
                }
                dotCount = (dotCount + 1) % 3
            }
        }
    }

    private var scanButtonLabel: String {
        switch ringConManager.connectionState {
        case .scanning: return "Scanning..."
        default:
            if ringConManager.pairedDeviceStatus == .pairedAndConnected {
                return "Connect"
            } else {
                return "Scan for Joy-Con"
            }
        }
    }
}
