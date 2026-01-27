//
//  RingBreakLogo.swift
//  RingBreak
//
//  App logo component using PNG image with dark/light variants
//

import SwiftUI

struct RingBreakLogo: View {
    var height: CGFloat = 40
    var forceDark: Bool = false  // Use dark logo on light backgrounds (default)
    var forceLight: Bool = false // Use light logo on dark backgrounds

    @Environment(\.colorScheme) private var colorScheme

    private var logoName: String {
        if forceLight {
            return "ring-break-logo-light"
        } else if forceDark {
            return "ring-break-logo-dark"
        } else {
            // Auto: use dark logo for dark mode, light logo for light mode
            return colorScheme == .dark ? "ring-break-logo-dark" : "ring-break-logo-light"
        }
    }

    var body: some View {
        if let path = Bundle.main.path(forResource: logoName, ofType: "png"),
           let nsImage = NSImage(contentsOfFile: path) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: height)
        }
    }
}

#Preview {
    VStack(spacing: 30) {
        // Auto (follows system color scheme)
        RingBreakLogo(height: 40)

        // Light logo (dark text) for light backgrounds
        RingBreakLogo(height: 40, forceLight: true)
            .padding()
            .background(Color.white)
            .cornerRadius(8)

        // Dark logo (light text) for dark backgrounds
        RingBreakLogo(height: 40, forceDark: true)
            .padding()
            .background(Color(red: 0.08, green: 0.12, blue: 0.22))
            .cornerRadius(8)
    }
    .padding(40)
    .background(Color.gray.opacity(0.2))
}
