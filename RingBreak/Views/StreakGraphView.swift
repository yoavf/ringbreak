 //
//  StreakGraphView.swift
//  RingBreak
//
//  Animated streak graph following Apple HIG guidelines
//

import SwiftUI

struct StreakGraphView: View {
    @ObservedObject var gameState: BreakGameState
    var onBack: () -> Void

    @State private var animationProgress: CGFloat = 0
    @State private var dotPulse: Bool = false

    // Use centralized colors from AppColors
    private let backgroundColor = AppColors.backgroundDark
    private let lineColor = AppColors.graphLine
    private let gridColor = AppColors.graphGrid

    private var hasAnyData: Bool {
        !gameState.dailyHistory.isEmpty
    }

    var body: some View {
        ZStack {
            // Background
            backgroundColor
                .ignoresSafeArea()

            VStack(spacing: 24) {
                // Header with logo and back button - fixed size
                HStack {
                    Button {
                        onBack()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.body.weight(.semibold))
                            Text("Back")
                        }
                        .foregroundColor(.orange)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.escape, modifiers: [])
                    .frame(width: 60, alignment: .leading)

                    Spacer()

                    RingBreakLogo(height: 48, forceDark: true)

                    Spacer()

                    // Empty space to balance header
                    Color.clear.frame(width: 60)
                }
                .padding(.horizontal)
                .padding(.top, 16)
                .fixedSize(horizontal: false, vertical: true)

                // Streak display - fixed size
                if gameState.dailyStreak > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "flame.fill")
                            .foregroundColor(.orange)
                        Text("\(gameState.dailyStreak) day streak")
                            .foregroundColor(.white)
                    }
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                }

                // Graph - fills remaining space
                graphView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
            }

            // Empty state overlay
            if !hasAnyData {
                VStack(spacing: 0) {
                    // Back button header
                    HStack {
                        Button {
                            onBack()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                    .font(.body.weight(.semibold))
                                Text("Back")
                            }
                            .foregroundColor(.orange)
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut(.escape, modifiers: [])

                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.top, 16)

                    // Centered content
                    Spacer()

                    VStack(spacing: 16) {
                        Image(systemName: "flame")
                            .font(.system(size: 48))
                            .foregroundColor(.orange.opacity(0.6))
                        Text("Log your first session\nto start a streak")
                            .font(.title3)
                            .fontWeight(.medium)
                            .foregroundColor(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                    }

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(backgroundColor.opacity(0.95))
            }
        }
        .onAppear {
            // Animate the line drawing
            withAnimation(.easeOut(duration: 1.2)) {
                animationProgress = 1.0
            }
            // Start dot pulsing after line animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    dotPulse = true
                }
            }
        }
    }

    private var graphView: some View {
        let history = gameState.getRecentHistory(days: 7)
        let maxSessions = max(history.map { $0.reps }.max() ?? 5, 5) + 2

        return VStack(spacing: 0) {
            // Y-axis label
            HStack {
                Text("Sessions")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
                Spacer()
            }
            .padding(.bottom, 8)

            // Graph area
            GeometryReader { geo in
                let graphPadding: CGFloat = 40 // Padding on left and right for labels
                let width = geo.size.width - graphPadding * 2
                let height = geo.size.height - 30 // Leave room for x-axis labels
                let stepX = width / CGFloat(max(history.count - 1, 1))

                ZStack(alignment: .bottomLeading) {
                    // Grid lines
                    ForEach(0..<5) { i in
                        let y = height * CGFloat(i) / 4
                        Path { path in
                            path.move(to: CGPoint(x: graphPadding, y: y))
                            path.addLine(to: CGPoint(x: geo.size.width - graphPadding, y: y))
                        }
                        .stroke(gridColor, lineWidth: 1)
                    }

                    // Y-axis labels
                    ForEach(0..<5) { i in
                        let value = maxSessions * (4 - i) / 4
                        let y = height * CGFloat(i) / 4
                        Text("\(value)")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.4))
                            .position(x: 15, y: y)
                    }

                    // Animated line
                    if history.count > 1 {
                        animatedLinePath(history: history, maxSessions: maxSessions, width: width, height: height, stepX: stepX)
                            .trim(from: 0, to: animationProgress)
                            .stroke(
                                LinearGradient(
                                    colors: [lineColor.opacity(0.6), lineColor],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                            )

                        // Gradient fill under the line
                        animatedAreaPath(history: history, maxSessions: maxSessions, width: width, height: height, stepX: stepX)
                            .fill(
                                LinearGradient(
                                    colors: [lineColor.opacity(0.3), lineColor.opacity(0.05)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .opacity(Double(animationProgress))
                    }

                    // Data points
                    ForEach(Array(history.enumerated()), id: \.offset) { index, dataPoint in
                        let x = graphPadding + stepX * CGFloat(index)
                        let y = height - (height * CGFloat(dataPoint.reps) / CGFloat(maxSessions))
                        let isToday = index == history.count - 1

                        Circle()
                            .fill(isToday ? lineColor : lineColor.opacity(0.8))
                            .frame(width: isToday ? 12 : 8, height: isToday ? 12 : 8)
                            .scaleEffect(isToday && dotPulse ? 1.3 : 1.0)
                            .shadow(color: isToday ? lineColor.opacity(0.6) : .clear, radius: dotPulse ? 8 : 4)
                            .position(x: x, y: y)
                            .opacity(CGFloat(index) / CGFloat(max(history.count - 1, 1)) <= animationProgress ? 1 : 0)
                    }

                    // X-axis labels (days)
                    ForEach(Array(history.enumerated()), id: \.offset) { index, dataPoint in
                        let x = graphPadding + stepX * CGFloat(index)
                        let dayLabel = dayLabel(for: dataPoint.date, isToday: index == history.count - 1)

                        Text(dayLabel)
                            .font(.caption2)
                            .foregroundColor(index == history.count - 1 ? .white : .white.opacity(0.5))
                            .position(x: x, y: height + 15)
                    }
                }
            }
        }
    }

    private func animatedLinePath(history: [(date: Date, reps: Int)], maxSessions: Int, width: CGFloat, height: CGFloat, stepX: CGFloat) -> Path {
        Path { path in
            for (index, dataPoint) in history.enumerated() {
                let x = stepX * CGFloat(index)
                let y = height - (height * CGFloat(dataPoint.reps) / CGFloat(maxSessions))

                if index == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
        }
        .offsetBy(dx: 40, dy: 0) // Match graphPadding
    }

    private func animatedAreaPath(history: [(date: Date, reps: Int)], maxSessions: Int, width: CGFloat, height: CGFloat, stepX: CGFloat) -> Path {
        Path { path in
            guard !history.isEmpty else { return }

            // Start at bottom left
            path.move(to: CGPoint(x: 0, y: height))

            // Draw line to first point
            let firstY = height - (height * CGFloat(history[0].reps) / CGFloat(maxSessions))
            path.addLine(to: CGPoint(x: 0, y: firstY))

            // Draw along the data points
            for (index, dataPoint) in history.enumerated() {
                let x = stepX * CGFloat(index)
                let y = height - (height * CGFloat(dataPoint.reps) / CGFloat(maxSessions))
                path.addLine(to: CGPoint(x: x, y: y))
            }

            // Close the path
            let lastX = stepX * CGFloat(history.count - 1)
            path.addLine(to: CGPoint(x: lastX, y: height))
            path.closeSubpath()
        }
        .offsetBy(dx: 40, dy: 0) // Match graphPadding
    }

    private func dayLabel(for date: Date, isToday: Bool) -> String {
        if isToday {
            return "Today"
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }
}

#Preview {
    StreakGraphView(
        gameState: BreakGameState(),
        onBack: {}
    )
    .frame(width: 420, height: 620)
}
