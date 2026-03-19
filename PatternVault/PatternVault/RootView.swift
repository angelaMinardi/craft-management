//
//  RootView.swift
//  PatternVault
//

import SwiftUI

struct RootView: View {
    @EnvironmentObject var auth: AuthService
    @ObservedObject private var celebrationStore = CelebrationStore.shared
    @Binding var sharedURL: String?
    @Binding var savedPatternId: UUID?
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

    var body: some View {
        Group {
            if !hasSeenOnboarding {
                OnboardingView()
            } else if auth.isSignedIn {
                MainTabView(sharedURL: $sharedURL, savedPatternId: $savedPatternId)
            } else {
                AuthGateView()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: auth.isSignedIn)
        .animation(.easeInOut(duration: 0.3), value: hasSeenOnboarding)
        .fullScreenCover(item: Binding(
            get: { celebrationStore.pendingMilestone },
            set: { celebrationStore.pendingMilestone = $0 }
        )) { pending in
            CelebrationOverlayView(milestoneId: pending.milestoneId) {
                celebrationStore.clearPending()
            }
        }
    }
}
