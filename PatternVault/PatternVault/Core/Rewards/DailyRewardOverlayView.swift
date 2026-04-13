//
//  DailyRewardOverlayView.swift
//  PatternVault
//
//  Brief overlay banner shown when a daily check-in reward is granted.
//

import SwiftUI

struct DailyRewardOverlayView: View {
    let result: DailyRewardResult
    let onDismiss: () -> Void

    @State private var isVisible = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if isVisible {
            HStack(spacing: Theme.Spacing.sm) {
                SpriteMascotView.jumping(size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text("+\(result.pointsGranted) Thread Points!")
                        .font(Theme.Typography.footnoteSemibold)
                        .foregroundStyle(Theme.Semantic.textPrimary)
                    Text("Day \(result.consecutiveDay) check-in")
                        .font(Theme.Typography.caption2.weight(.semibold))
                        .foregroundStyle(Theme.Semantic.textSecondary)
                }
                Spacer()
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.Semantic.iconMuted)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(Theme.honey.gradient)
            .clipShape(Capsule())
            .shadow(color: Theme.honey.opacity(0.3), radius: 8, y: 4)
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.top, 6)
            .transition(.move(edge: .top).combined(with: .opacity))
            .onTapGesture {
                withAnimation(reduceMotion ? .none : .easeOut(duration: 0.25)) {
                    isVisible = false
                }
                onDismiss()
            }
            .task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                withAnimation(reduceMotion ? .none : .easeOut(duration: 0.3)) {
                    isVisible = false
                }
                onDismiss()
            }
        }
    }
}
