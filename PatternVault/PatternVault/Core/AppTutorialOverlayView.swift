//
//  AppTutorialOverlayView.swift
//  PatternVault
//
//  Full-screen overlay with coach-mark bubbles anchored to UI elements.
//  Bubbles sit above the target with a tail pointing at it so the target stays visible.
//

import SwiftUI

struct AppTutorialOverlayView: View {
    @ObservedObject var store: AppTutorialStore
    var anchorFrames: TutorialAnchorFrames
    @State private var bubbleAppeared = false
    @State private var showingSkipPouty = false
    @State private var showingDoneCelebration = false

    private let gap: CGFloat = 16
    private let tailLength: CGFloat = 10
    private let tailWidth: CGFloat = 20
    private let bubbleBodyHeight: CGFloat = 270
    private let tabBarHeight: CGFloat = 84
    private let bubbleMaxWidth: CGFloat = 280
    private let horizontalInset: CGFloat = 20
    private let safeBottomInset: CGFloat = 24

    var body: some View {
        ZStack {
            if store.isActive {
                // Dimmed background should only exist while tutorial is active.
                Color.clear
                    .background(Theme.deepPlum.opacity(0.4))
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            if store.isActive && store.isLastStep {
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture {
                        store.next()
                    }
            }

            if store.isActive {
                if showingSkipPouty {
                    skipPoutyView
                } else if showingDoneCelebration {
                    doneCelebrationView
                } else if store.currentStep < AppTutorialStore.steps.count {
                    let step = AppTutorialStore.steps[store.currentStep]
                    GeometryReader { geo in
                        let placement = placement(for: step, in: geo.size)
                        speechBubble(step: step, showTail: placement.showTail, tailPointsUp: placement.tailPointsUp)
                            .frame(width: placement.bubbleWidth, height: placement.bubbleHeight)
                            .scaleEffect(bubbleAppeared ? 1 : 0.92)
                            .opacity(bubbleAppeared ? 1 : 0)
                            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: bubbleAppeared)
                            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: store.currentStep)
                            .position(x: placement.centerX, y: placement.centerY)
                    }
                }
            }
        }
        .onAppear {
            normalizeTutorialStateIfNeeded()
        }
        .onChange(of: store.currentStep) { _, _ in
            bubbleAppeared = false
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8).delay(0.05)) {
                bubbleAppeared = true
            }
            normalizeTutorialStateIfNeeded()
        }
        .onChange(of: store.isActive) { _, _ in
            normalizeTutorialStateIfNeeded()
        }
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8).delay(0.1)) {
                bubbleAppeared = true
            }
        }
    }

    private func normalizeTutorialStateIfNeeded() {
        guard store.isActive else { return }
        guard !showingSkipPouty, !showingDoneCelebration else { return }
        guard store.currentStep >= AppTutorialStore.steps.count else { return }
        // Safety: never leave the dim layer up with no active bubble step.
        store.next()
    }

    /// Placement: center of the bubble (including tail), size, tail visibility and direction.
    private struct BubblePlacement {
        var centerX: CGFloat
        var centerY: CGFloat
        var bubbleWidth: CGFloat
        var bubbleHeight: CGFloat
        var showTail: Bool
        var tailPointsUp: Bool = false
    }

    private func placement(for step: AppTutorialStep, in size: CGSize) -> BubblePlacement {
        let totalHeight = bubbleBodyHeight + (step.anchorId == .welcome ? 0 : tailLength)
        let w = min(bubbleMaxWidth, size.width - horizontalInset * 2)
        let safeTop: CGFloat = 24
        let minCenterX = horizontalInset + w / 2
        let maxCenterX = size.width - horizontalInset - w / 2

        func clampX(_ x: CGFloat) -> CGFloat { min(max(minCenterX, x), maxCenterX) }

        switch step.anchorId {
        case .welcome:
            return BubblePlacement(
                centerX: clampX(size.width / 2),
                centerY: size.height / 2 - 20,
                bubbleWidth: w,
                bubbleHeight: bubbleBodyHeight,
                showTail: false
            )

        case .tabBar:
            let tailTipY = size.height - tabBarHeight - gap
            let preferredCenterY = tailTipY - totalHeight / 2
            let centerY = min(tailTipY - totalHeight / 2, max(safeTop + totalHeight / 2, preferredCenterY))
            return BubblePlacement(
                centerX: clampX(size.width / 2),
                centerY: centerY,
                bubbleWidth: w,
                bubbleHeight: totalHeight,
                showTail: true
            )

        case .tabPatterns, .tabStash, .tabSettings:
            let tabIndex: CGFloat = step.anchorId == .tabPatterns ? 1 : (step.anchorId == .tabStash ? 3 : 4)
            let tailTipX = size.width * (tabIndex + 0.5) / 5
            let tailTipY = size.height - tabBarHeight - gap
            let preferredCenterY = tailTipY - totalHeight / 2
            let centerY = min(tailTipY - totalHeight / 2, max(safeTop + totalHeight / 2, preferredCenterY))
            return BubblePlacement(
                centerX: clampX(tailTipX),
                centerY: centerY,
                bubbleWidth: w,
                bubbleHeight: totalHeight,
                showTail: true
            )

        default:
            guard let frame = anchorFrames.frames[step.anchorId] else {
                return BubblePlacement(
                    centerX: clampX(size.width / 2),
                    centerY: size.height / 2 - 20,
                    bubbleWidth: w,
                    bubbleHeight: bubbleBodyHeight,
                    showTail: false
                )
            }
            let tailTipX = frame.midX
            let spaceAbove = frame.minY - gap - safeTop
            let spaceBelow = (size.height - safeBottomInset) - (frame.maxY + gap)
            let fitsAbove = spaceAbove >= totalHeight
            let fitsBelow = spaceBelow >= totalHeight

            if fitsAbove {
                let preferredCenterY = frame.minY - gap - totalHeight / 2
                let centerY = min(frame.minY - gap - totalHeight / 2, max(safeTop + totalHeight / 2, preferredCenterY))
                return BubblePlacement(
                    centerX: clampX(tailTipX),
                    centerY: centerY,
                    bubbleWidth: w,
                    bubbleHeight: totalHeight,
                    showTail: true
                )
            } else if fitsBelow {
                let tailTipYBelow = frame.maxY + gap
                let preferredCenterY = tailTipYBelow + totalHeight / 2
                let maxCenterY = size.height - safeBottomInset - totalHeight / 2
                let centerY = min(maxCenterY, max(preferredCenterY, safeTop + totalHeight / 2))
                return BubblePlacement(
                    centerX: clampX(tailTipX),
                    centerY: centerY,
                    bubbleWidth: w,
                    bubbleHeight: totalHeight,
                    showTail: true,
                    tailPointsUp: true
                )
            } else {
                if spaceAbove >= spaceBelow {
                    let centerY = frame.minY - gap - totalHeight / 2
                    return BubblePlacement(
                        centerX: clampX(tailTipX),
                        centerY: max(safeTop + totalHeight / 2, centerY),
                        bubbleWidth: w,
                        bubbleHeight: totalHeight,
                        showTail: true
                    )
                } else {
                    let tailTipYBelow = frame.maxY + gap
                    let preferredCenterY = tailTipYBelow + totalHeight / 2
                    let maxCenterY = size.height - safeBottomInset - totalHeight / 2
                    let centerY = min(maxCenterY, preferredCenterY)
                    return BubblePlacement(
                        centerX: clampX(tailTipX),
                        centerY: centerY,
                        bubbleWidth: w,
                        bubbleHeight: totalHeight,
                        showTail: true,
                        tailPointsUp: true
                    )
                }
            }
        }
    }

    private func speechBubble(step: AppTutorialStep, showTail: Bool, tailPointsUp: Bool = false) -> some View {
        ZStack(alignment: tailPointsUp ? .top : .bottom) {
            bubbleCardContent(step: step)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.large))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.large)
                        .stroke(Theme.deepPlum.opacity(0.12), lineWidth: 1.5)
                )
                .padding(tailPointsUp ? .top : .bottom, showTail ? tailLength : 0)

            if showTail {
                HStack {
                    Spacer(minLength: 0)
                    SpeechBubbleTail(pointsUp: tailPointsUp)
                        .fill(Theme.cardBackground)
                        .frame(width: tailWidth, height: tailLength)
                        .overlay(
                            SpeechBubbleTail(pointsUp: tailPointsUp)
                                .stroke(Theme.deepPlum.opacity(0.12), lineWidth: 1.5)
                        )
                    Spacer(minLength: 0)
                }
            }
        }
        .shadow(color: Color.black.opacity(0.12), radius: 16, x: 0, y: 8)
    }

    private var skipPoutyView: some View {
        VStack(spacing: Theme.Spacing.lg) {
            SpriteMascotView.pouty(size: 100)
            Text("Skipped!")
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.deepPlum.opacity(0.8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var doneCelebrationView: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Text("You're all set!")
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.deepPlum.opacity(0.9))
            SpriteMascotView.jumping(size: 160) {
                dismissCelebration()
            }
            Button("Continue") {
                dismissCelebration()
            }
            .font(Theme.Typography.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.vertical, 12)
            .background(Theme.softCoral)
            .clipShape(Capsule())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { dismissCelebration() }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                if showingDoneCelebration { dismissCelebration() }
            }
        }
    }

    private func dismissCelebration() {
        store.next()
        showingDoneCelebration = false
    }

    private static func mascotPose(for step: AppTutorialStep) -> MascotPose {
        switch step.anchorId {
        case .tabBar:
            return .thinking
        default:
            return .idle
        }
    }

    private enum MascotPose {
        case idle, thinking
    }

    private func bubbleCardContent(step: AppTutorialStep) -> some View {
        let pose = Self.mascotPose(for: step)
        let showInteractionHint = store.currentStep > 0 && store.currentStep <= 4
        return VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            // Mascot as the "speaker" of the bubble
            Group {
                switch pose {
                case .idle:
                    SpriteMascotView.idle(size: 52)
                case .thinking:
                    SpriteMascotView.thinking(size: 52)
                }
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text(step.title)
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.deepPlum)
                Text(step.body)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.deepPlum.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)

                if showInteractionHint {
                    HStack(spacing: 6) {
                        Image(systemName: "hand.tap")
                        Text("Tap highlighted areas to try things.")
                    }
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.deepPlum.opacity(0.65))
                    .padding(.top, 2)
                    .accessibilityLabel("Tap highlighted areas to try things")
                }
            }

            HStack(spacing: Theme.Spacing.md) {
                Button("Skip") {
                    showingSkipPouty = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        store.skip()
                        showingSkipPouty = false
                    }
                }
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.deepPlum.opacity(0.6))
                .accessibilityLabel("Skip tutorial")

                Spacer()

                Button {
                    store.next()
                } label: {
                    HStack(spacing: 6) {
                        Text(store.isLastStep ? "Done" : "Next")
                        if !store.isLastStep {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                        }
                    }
                    .font(Theme.Typography.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Theme.Spacing.xl)
                    .padding(.vertical, 12)
                    .background(Theme.softCoral)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(store.isLastStep ? "Done" : "Next")
            }
        }
        .padding(Theme.Spacing.xl)
    }
}

/// Triangle for speech-bubble tail (points down or up).
private struct SpeechBubbleTail: Shape {
    var pointsUp: Bool = false

    func path(in rect: CGRect) -> Path {
        var path = Path()
        if pointsUp {
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        } else {
            path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        }
        path.closeSubpath()
        return path
    }
}
