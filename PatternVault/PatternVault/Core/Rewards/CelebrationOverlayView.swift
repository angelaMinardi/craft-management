//
//  CelebrationOverlayView.swift
//  PatternVault
//
//  One-time milestone celebration: jumping mascot + title/subtitle + confetti.
//  Stays up until the user taps "Nice!" to dismiss.
//

import SwiftUI

// MARK: - Confetti (little falling shapes)

private struct ConfettiPiece: Identifiable {
    let id: Int
    let color: Color
    let xRatio: CGFloat
    let delay: Double
    let duration: Double
    let size: CGFloat
    let isCircle: Bool
    let drift: CGFloat
    let rotationSpeed: Double
}

private struct ConfettiOverlay: View {
    @State private var startTime = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let colors: [Color] = [
        Theme.softCoral,
        Theme.deepPlum.opacity(0.9),
        Theme.sageGreen,
        Theme.dustyBlue,
        Theme.honey
    ]
    private static let pieceCount = 55

    /// Deterministic "random" from index so confetti is stable across redraws.
    private static func seed(_ i: Int) -> Double {
        let x = sin(Double(i) * 12.9898) * 43758.5453
        return x - floor(x)
    }

    private static let pieces: [ConfettiPiece] = (0..<pieceCount).map { i in
        ConfettiPiece(
            id: i,
            color: colors[i % colors.count],
            xRatio: CGFloat(seed(i)),
            delay: Double(seed(i + 100)) * 0.6,
            duration: 2.2 + Double(seed(i + 200)) * 1.3,
            size: CGFloat(5 + seed(i + 300) * 6),
            isCircle: seed(i + 400) > 0.5,
            drift: CGFloat((seed(i + 500) - 0.5) * 60),
            rotationSpeed: 0.5 + Double(seed(i + 600)) * 1.5
        )
    }

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1/30, paused: reduceMotion)) { context in
                let t = context.date.timeIntervalSince(startTime)
                ZStack(alignment: .topLeading) {
                    ForEach(Self.pieces) { piece in
                        pieceView(piece, at: t, width: geo.size.width, height: geo.size.height)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { startTime = Date() }
        .allowsHitTesting(false)
    }

    private func pieceView(_ piece: ConfettiPiece, at t: Double, width: CGFloat, height: CGFloat) -> some View {
        let elapsed = t - piece.delay
        guard elapsed > 0 else {
            return AnyView(EmptyView())
        }
        let progress = min(1, elapsed / piece.duration)
        let y = progress * (height + 40)
        let x = width * piece.xRatio + piece.drift * progress
        let rotation = Angle.degrees(elapsed * 360 * piece.rotationSpeed)
        let shape: AnyView
        if piece.isCircle {
            shape = AnyView(Circle().fill(piece.color))
        } else {
            shape = AnyView(
                RoundedRectangle(cornerRadius: 1)
                    .fill(piece.color)
                    .frame(width: piece.size * 0.6, height: piece.size)
            )
        }
        return AnyView(
            shape
                .frame(width: piece.size, height: piece.size)
                .position(x: x, y: y)
                .rotationEffect(rotation)
                .opacity(progress < 0.9 ? 0.85 : 0.85 * (1 - (progress - 0.9) / 0.1))
        )
    }
}

// MARK: - Celebration overlay

struct CelebrationOverlayView: View {
    let milestoneId: String
    let onDismiss: () -> Void

    @State private var dismissRequested = false

    private var title: String {
        CelebrationStore.title(for: milestoneId) ?? "Nice!"
    }

    private var subtitle: String? {
        CelebrationStore.subtitle(for: milestoneId)
    }

    var body: some View {
        ZStack {
            Theme.warmCream.ignoresSafeArea()

            ConfettiOverlay()
                .ignoresSafeArea()

            VStack(spacing: Theme.Spacing.xl) {
                Spacer()
                SpriteMascotView.jumping(size: 160) {
                    // Jump completes; celebration stays until user taps Nice!
                }
                VStack(spacing: Theme.Spacing.sm) {
                    Text(title)
                        .font(Theme.Typography.titleBold)
                        .foregroundStyle(Theme.deepPlum)
                        .multilineTextAlignment(.center)
                    if let subtitle {
                        Text(subtitle)
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.deepPlum.opacity(0.7))
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, Theme.Spacing.xl)

                Button {
                    requestDismiss()
                } label: {
                    Text("Nice!")
                        .font(Theme.Typography.bodySemibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, Theme.Spacing.xxl)
                        .padding(.vertical, Theme.Spacing.sm)
                        .background(Theme.softCoral)
                        .clipShape(Capsule())
                }
                .padding(.top, Theme.Spacing.md)

                Spacer()
            }
        }
        .onAppear { HapticService.mediumImpact() }
    }

    private func requestDismiss() {
        dismissRequested = true
        onDismiss()
    }
}
