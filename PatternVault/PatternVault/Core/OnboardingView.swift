//
//  OnboardingView.swift
//  PatternVault
//
//  Professional, enticing onboarding in the spirit of Duolingo/BitePal:
//  clear progress, benefit-led copy, mascot as hero, and a rewarding finish.
//

import SwiftUI

struct OnboardingView: View {
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var currentPage = 0
    @State private var mascotBounce = false
    @State private var titleAppeared = false
    @State private var subtitleAppeared = false
    @State private var buttonAppeared = false
    @State private var isCelebrating = false

    private let totalPages = 3

    var body: some View {
        ZStack {
            Theme.warmCream.ignoresSafeArea()
            SparkleBackgroundView()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar: app name + progress + skip
                HStack {
                    Text("Pattern Vault")
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.deepPlum.opacity(0.8))

                    Spacer()

                    // Pill progress bar
                    Capsule()
                        .fill(Theme.deepPlum.opacity(0.12))
                        .frame(width: 72, height: 6)
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(Theme.deepPlum)
                                .frame(width: 72 * progressFraction)
                                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: currentPage)
                        }

                    Spacer()

                    Button("Skip") {
                        withAnimation(.easeOut(duration: 0.25)) {
                            hasSeenOnboarding = true
                        }
                    }
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.deepPlum.opacity(0.6))
                }
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.top, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.sm)

                TabView(selection: $currentPage) {
                    onboardingPage(
                        title: "Welcome to Pattern Vault!",
                        subtitle: "Discover, organize, and manage your patterns with ease.",
                        heroImageName: nil
                    )
                    .tag(0)

                    onboardingPage(
                        title: "Save from\nanywhere",
                        subtitle: "Share a link from Safari, YouTube, or any app. We'll grab the details for you.",
                        heroImageName: "ShareToPatternVault"
                    )
                    .tag(1)

                    onboardingPage(
                        title: "Never lose a\npattern again",
                        subtitle: "Tags, notes, and your whole library in your pocket. Ready when you are.",
                        heroImageName: nil
                    )
                    .tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.spring(response: 0.45, dampingFraction: 0.82), value: currentPage)

                // Page dots (subtle)
                HStack(spacing: 6) {
                    ForEach(0..<totalPages, id: \.self) { index in
                        Circle()
                            .fill(index == currentPage ? Theme.softCoral : Theme.deepPlum.opacity(0.18))
                            .frame(width: index == currentPage ? 8 : 6, height: 6)
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentPage)
                    }
                }
                .padding(.bottom, Theme.Spacing.lg)

                // Primary action
                Group {
                    if currentPage < totalPages - 1 {
                        Button {
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                                currentPage += 1
                                triggerPageAnimations()
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text("Next")
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .font(Theme.Typography.headline)
                            .foregroundStyle(.white)
                            .padding(.horizontal, Theme.Spacing.xxl)
                            .padding(.vertical, 16)
                            .background(Theme.deepPlum)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(OnboardingButtonStyle())
                    } else {
                        Button {
                            isCelebrating = true
                        } label: {
                            Text("Get started")
                                .font(Theme.Typography.headline)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Theme.softCoral)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(OnboardingButtonStyle())
                        .padding(.horizontal, Theme.Spacing.xxl)
                        .scaleEffect(buttonAppeared ? 1 : 0.92)
                        .opacity(buttonAppeared ? 1 : 0)
                    }
                }
                .padding(.bottom, Theme.Spacing.xxl + 8)
            }

            // Celebration overlay: jumping mascot then dismiss
            if isCelebrating {
                Theme.warmCream.ignoresSafeArea()
                VStack(spacing: Theme.Spacing.xl) {
                    Spacer()
                    Text("You're in!")
                        .font(Theme.Typography.title)
                        .foregroundStyle(Theme.deepPlum.opacity(0.9))
                    SpriteMascotView.jumping(size: 200) {
                        hasSeenOnboarding = true
                        isCelebrating = false
                    }
                    Spacer()
                }
                .transition(.opacity)
            }
        }
        .onAppear { triggerPageAnimations() }
        .onChange(of: currentPage) { _, _ in triggerPageAnimations() }
    }

    private var progressFraction: CGFloat {
        CGFloat(currentPage + 1) / CGFloat(totalPages)
    }

    private func triggerPageAnimations() {
        mascotBounce = false
        titleAppeared = false
        subtitleAppeared = false
        buttonAppeared = false

        withAnimation(.spring(response: 0.55, dampingFraction: 0.72).delay(0.08)) {
            mascotBounce = true
        }
        withAnimation(.easeOut(duration: 0.38).delay(0.22)) {
            titleAppeared = true
        }
        withAnimation(.easeOut(duration: 0.35).delay(0.42)) {
            subtitleAppeared = true
        }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.75).delay(0.58)) {
            buttonAppeared = true
        }
    }

    @ViewBuilder
    private func onboardingPage(title: String, subtitle: String, heroImageName: String? = nil) -> some View {
        let isShareSlide = heroImageName != nil

        VStack(spacing: 0) {
            if isShareSlide {
                // Page 2: image is the hero — compact title/subtitle at top, then image fills the rest
                VStack(spacing: Theme.Spacing.sm) {
                    Text(title)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.deepPlum)
                        .multilineTextAlignment(.center)
                        .offset(y: titleAppeared ? 0 : 12)
                        .opacity(titleAppeared ? 1 : 0)
                    Text(subtitle)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.deepPlum.opacity(0.65))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Theme.Spacing.lg)
                        .offset(y: subtitleAppeared ? 0 : 8)
                        .opacity(subtitleAppeared ? 1 : 0)
                }
                .padding(.top, Theme.Spacing.md)
                .padding(.bottom, Theme.Spacing.sm)

                Image(heroImageName!)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, Theme.Spacing.lg)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.large))
                    .scaleEffect(mascotBounce ? 1 : 0.95)
                    .opacity(mascotBounce ? 1 : 0)
                    .layoutPriority(1)

                Spacer()
                    .frame(minHeight: 16)
            } else {
                // Pages 1 & 3: mascot hero, then title and subtitle below
                Spacer()
                    .frame(maxHeight: 24)

                ZStack {
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.large * 2)
                        .fill(Theme.cardBackground)
                        .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 4)
                        .frame(width: 200, height: 200)

                    SpriteMascotView(folder: "OnboardingMascotFrames", size: 176)
                        .scaleEffect(mascotBounce ? 1 : 0.7)
                        .opacity(mascotBounce ? 1 : 0)
                }
                .frame(height: 220)

                Spacer()
                    .frame(height: Theme.Spacing.xxl)

                VStack(spacing: Theme.Spacing.md) {
                    Text(title)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.deepPlum)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                        .offset(y: titleAppeared ? 0 : 16)
                        .opacity(titleAppeared ? 1 : 0)

                    Text(subtitle)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.deepPlum.opacity(0.65))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .padding(.horizontal, Theme.Spacing.xxl)
                        .offset(y: subtitleAppeared ? 0 : 12)
                        .opacity(subtitleAppeared ? 1 : 0)
                }

                Spacer()
            }
        }
    }
}

// MARK: - Button style for onboarding (subtle press)

private struct OnboardingButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
