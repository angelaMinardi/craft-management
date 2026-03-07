//
//  RootView.swift
//  PatternVault
//

import SwiftUI

struct RootView: View {
    @EnvironmentObject var auth: AuthService
    @Binding var sharedURL: String?
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

    var body: some View {
        Group {
            if !hasSeenOnboarding {
                OnboardingView()
            } else if auth.isSignedIn {
                MainTabView(sharedURL: $sharedURL)
            } else {
                AuthGateView()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: auth.isSignedIn)
        .animation(.easeInOut(duration: 0.3), value: hasSeenOnboarding)
    }
}
