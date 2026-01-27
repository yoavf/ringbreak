//
//  AppColors.swift
//  RingBreak
//
//  Centralized color definitions for the app
//

import SwiftUI

enum AppColors {
    // MARK: - Background Colors

    /// Dark mode background: #1F2937
    static let backgroundDark = Color(red: 0.122, green: 0.161, blue: 0.216)

    /// Light mode background: #F9FAFB
    static let backgroundLight = Color(red: 0.976, green: 0.980, blue: 0.984)

    /// Returns the appropriate background color for the current color scheme
    static func background(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? backgroundDark : backgroundLight
    }

    // MARK: - Accent Colors

    /// Soft blue for dark mode countdowns
    static let countdownDark = Color(red: 0.6, green: 0.7, blue: 0.9)

    /// Soft green for dark mode success
    static let successDark = Color(red: 0.4, green: 0.8, blue: 0.6)

    // MARK: - Graph Colors

    static let graphLine = Color.orange
    static let graphGrid = Color.white.opacity(0.1)
}

// MARK: - View Extension for easy background access

extension View {
    func appBackground(for colorScheme: ColorScheme) -> some View {
        self.background(AppColors.background(for: colorScheme))
    }
}
