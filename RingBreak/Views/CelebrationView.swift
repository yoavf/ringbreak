//
//  CelebrationView.swift
//  RingBreak
//
//  View shown after completing an exercise session
//

import SwiftUI

struct CelebrationView: View {
    @ObservedObject var gameState: BreakGameState
    let onHome: () -> Void
    let onDoAnother: () -> Void

    @State private var isHomeHovered = false
    @Environment(\.colorScheme) private var colorScheme

    private var successColor: Color {
        colorScheme == .dark ? AppColors.successDark : .green
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top bar with logo - fixed size
            HStack {
                Color.clear.frame(width: 60)

                Spacer()

                RingBreakLogo(height: 48)

                Spacer()

                Button { onHome() } label: {
                    Image(systemName: isHomeHovered ? "house.fill" : "house")
                        .foregroundColor(.secondary)
                        .scaleEffect(isHomeHovered ? 1.2 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isHomeHovered)
                }
                .buttonStyle(.borderless)
                .onHover { hovering in
                    isHomeHovered = hovering
                }
                .frame(width: 60, alignment: .trailing)
            }
            .padding(.horizontal)
            .padding(.top, 16)
            .fixedSize(horizontal: false, vertical: true)

            // 3D Ring with success message overlay - fills remaining space
            ZStack {
                RingConSceneView(flexValue: 0.5)

                VStack(spacing: 12) {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 48))
                            .foregroundColor(successColor)
                        Text("Complete!")
                            .font(.title2)
                            .fontWeight(.bold)
                    }

                    VStack(spacing: 4) {
                        Text("\(gameState.sessionsToday) sessions today")
                            .font(.subheadline)
                        if gameState.dailyStreak > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "flame")
                                    .foregroundColor(.orange)
                                Text("\(gameState.dailyStreak) day streak")
                            }
                            .font(.caption)
                        }
                    }
                    .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Button below the ring
            Button(action: { onDoAnother() }) {
                Text("Do Another")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 140)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.bottom, 8)

            // Bottom spacing for consistency - fixed size
            HStack(spacing: 4) {
                Circle().fill(Color.green).frame(width: 6, height: 6)
                Text("Connected")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(height: 50, alignment: .top)
            .padding(.bottom, 12)
        }
    }
}
