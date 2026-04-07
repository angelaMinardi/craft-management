//
//  AchievementGridView.swift
//  PatternVault
//
//  Badge collection grid showing unlocked and locked achievements.
//

import SwiftUI

struct AchievementGridView: View {
    @ObservedObject var store: AchievementStore
    @Environment(\.dismiss) private var dismiss

    private let columns = [
        GridItem(.flexible(), spacing: Theme.Spacing.md),
        GridItem(.flexible(), spacing: Theme.Spacing.md),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    headerSection
                    badgeGrid
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.lg)
                .padding(.bottom, 40)
            }
            .background(Theme.screenGradient)
            .navigationTitle("Achievements")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.deepPlum)
                }
            }
        }
    }

    private var headerSection: some View {
        HStack(spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(store.progress.unlockedIds.count) / \(AchievementCatalog.allBadges.count)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.deepPlum)
                Text("Badges earned")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Semantic.textSecondary)
            }
            Spacer()
            SpriteMascotView.idle(size: 56)
        }
        .padding(Theme.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.large)
                .fill(Theme.warmCream)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.large)
                .stroke(Theme.deepPlum.opacity(0.08), lineWidth: 1)
        )
    }

    private var badgeGrid: some View {
        LazyVGrid(columns: columns, spacing: Theme.Spacing.md) {
            ForEach(AchievementCatalog.allBadges) { badge in
                badgeCell(badge)
            }
        }
    }

    private func badgeCell(_ badge: AchievementBadge) -> some View {
        let isUnlocked = store.progress.unlockedIds.contains(badge.id)
        let unlockDate = store.progress.unlockedDates[badge.id]

        return VStack(spacing: Theme.Spacing.sm) {
            Text(isUnlocked ? badge.emoji : "❓")
                .font(.system(size: 36))

            Text(isUnlocked ? badge.title : "???")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(isUnlocked ? Theme.Semantic.textPrimary : Theme.Semantic.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(isUnlocked ? badge.description : badge.hint)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(isUnlocked ? Theme.Semantic.textSecondary : Theme.Semantic.textTertiary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)

            if isUnlocked, let date = unlockDate {
                Text(date, style: .date)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.sageGreen.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                .fill(isUnlocked ? Color.white.opacity(0.78) : Theme.warmCream.opacity(0.9))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                .stroke(isUnlocked ? Theme.sageGreen.opacity(0.3) : Theme.Semantic.borderStandard, lineWidth: 1)
        )
    }
}
