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
    @AppStorage("onboarding_milestone_auth_required_shown") private var authRequiredShown = false
    @AppStorage("onboarding_milestone_auth_complete") private var authComplete = false

    var body: some View {
        Group {
            if !hasSeenOnboarding {
                OnboardingView()
            } else if auth.isSignedIn {
                MainTabView(sharedURL: $sharedURL, savedPatternId: $savedPatternId)
            } else {
                AuthGateView(
                    titleOverride: authRequiredShown ? "Sign in to save your first win" : nil,
                    subtitleOverride: authRequiredShown ? "Your setup is ready locally. Sign in to save and sync it across devices." : nil
                )
            }
        }
        .animation(.easeInOut(duration: 0.2), value: auth.isSignedIn)
        .animation(.easeInOut(duration: 0.3), value: hasSeenOnboarding)
        .fullScreenCover(item: Binding(
            get: { celebrationStore.pendingMilestone },
            set: { celebrationStore.pendingMilestone = $0 }
        )) { pending in
            CelebrationOverlayView(milestoneId: pending.milestoneId) {
                GrowthOrchestrator.shared.registerPositiveEvent(.milestoneCelebration)
                celebrationStore.clearPending()
                GrowthOrchestrator.shared.requestReviewIfEligible()
            }
        }
        .onChange(of: celebrationStore.pendingMilestone?.milestoneId) { _, newId in
            guard newId != nil else { return }
            GrowthOrchestrator.shared.registerPositiveEvent(.milestoneCelebration)
        }
        .onChange(of: auth.isSignedIn) { _, signedIn in
            if signedIn, hasSeenOnboarding {
                authComplete = true
            }
        }
    }
}
