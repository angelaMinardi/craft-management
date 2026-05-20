//
//  RootView.swift
//  PatternVault
//

import SwiftUI

struct RootView: View {
    @EnvironmentObject var auth: AuthService
    @ObservedObject private var celebrationStore = CelebrationStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
        .animation(reduceMotion ? .none : .easeInOut(duration: 0.2), value: auth.isSignedIn)
        .animation(reduceMotion ? .none : .easeInOut(duration: 0.3), value: hasSeenOnboarding)
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
        .fullScreenCover(isPresented: $auth.isRecoveringPassword) {
            SetNewPasswordView()
        }
        .onAppear {
            // Migration: anyone who's already signed in from a prior build
            // (predating this change) has effectively completed onboarding —
            // don't force them back through the funnel.
            if auth.isSignedIn && !hasSeenOnboarding {
                hasSeenOnboarding = true
            }
        }
        .onChange(of: celebrationStore.pendingMilestone?.milestoneId) { _, newId in
            guard newId != nil else { return }
            GrowthOrchestrator.shared.registerPositiveEvent(.milestoneCelebration)
        }
        .onChange(of: auth.currentUserId) { oldId, newId in
            // Use UUID identity (not isSignedIn) so silent token refresh doesn't
            // re-fire these events on every refresh tick.
            guard oldId != newId else { return }
            if let newId {
                // Reconcile pre-auth StoreKit purchases into Supabase entitlements,
                // and fire the onboarding-completed signal post-auth.
                Task {
                    await SubscriptionStore.shared.updateSubscriptionStatus(userId: newId)
                    await SubscriptionStore.shared.refreshUsage(userId: newId)
                }
                if hasSeenOnboarding, !authComplete {
                    GrowthOrchestrator.shared.markOnboardingCompleted()
                    GrowthOrchestrator.shared.registerPositiveEvent(.onboardingComplete)
                    authComplete = true
                }
            }
        }
    }
}

// MARK: - Set new password (after password-reset recovery link)

private struct SetNewPasswordView: View {
    @EnvironmentObject var auth: AuthService
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @FocusState private var focusedField: Field?
    enum Field { case password, confirm }

    private var passwordValid: Bool { newPassword.count >= AuthValidation.minPasswordLength }
    private var matches: Bool { newPassword == confirmPassword }
    private var canSubmit: Bool { passwordValid && matches && !auth.isLoading }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.xl) {
                    SpriteMascotView.idle(size: 80)
                        .padding(.top, Theme.Spacing.xl)
                    VStack(spacing: Theme.Spacing.sm) {
                        Text("Set a new password")
                            .font(Theme.Typography.title)
                            .foregroundStyle(Theme.deepPlum)
                        Text("Choose a password you haven't used here before.")
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.deepPlum.opacity(0.6))
                            .multilineTextAlignment(.center)
                    }

                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("New password")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.deepPlum.opacity(0.6))
                        SecureField("\(AuthValidation.minPasswordLength)+ characters", text: $newPassword)
                            .textContentType(.newPassword)
                            .focused($focusedField, equals: .password)
                            .padding(12)
                            .background(Theme.warmCream)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.small))

                        Text("Confirm password")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.deepPlum.opacity(0.6))
                            .padding(.top, Theme.Spacing.sm)
                        SecureField("Repeat new password", text: $confirmPassword)
                            .textContentType(.newPassword)
                            .focused($focusedField, equals: .confirm)
                            .padding(12)
                            .background(Theme.warmCream)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.small))

                        if !newPassword.isEmpty && !passwordValid {
                            Text("At least \(AuthValidation.minPasswordLength) characters")
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.softCoral)
                        }
                        if !confirmPassword.isEmpty && !matches {
                            Text("Passwords don't match")
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.softCoral)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.xl)

                    if let msg = auth.errorMessage {
                        Text(msg)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.softCoral)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, Theme.Spacing.xl)
                    }

                    Button {
                        Task {
                            _ = await auth.updatePassword(to: newPassword)
                        }
                    } label: {
                        HStack {
                            if auth.isLoading { ProgressView().tint(.white) }
                            Text("Update password")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!canSubmit)
                    .padding(.horizontal, Theme.Spacing.xl)
                }
                .padding(.bottom, 40)
            }
            .background(Theme.screenGradient.ignoresSafeArea())
            .navigationTitle("Reset password")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(true)
        }
    }
}
