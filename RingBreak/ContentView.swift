//
//  ContentView.swift
//  RingBreak
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var menubarController: MenubarController
    @StateObject private var ringConManager = RingConManager()
    @AppStorage(UserDefaultsKeys.hasCompletedOnboarding) private var hasCompletedOnboarding = false

    var body: some View {
        if hasCompletedOnboarding {
            RingBreakView(ringConManager: ringConManager, menubarController: menubarController)
        } else {
            OnboardingView {
                hasCompletedOnboarding = true
            }
        }
    }
}

#Preview {
    ContentView(menubarController: MenubarController())
}
