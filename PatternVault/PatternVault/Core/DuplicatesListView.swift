//
//  DuplicatesListView.swift
//  PatternVault
//
//  Shows groups of duplicate patterns and lets the user remove extras.
//

import SwiftUI

struct DuplicatesListView: View {
    @EnvironmentObject var auth: AuthService
    @ObservedObject var store: PatternStore
    @State private var groups: [[Pattern]] = []
    @State private var isDeleting = false

    var body: some View {
        Group {
            if groups.isEmpty {
                emptyView
            } else {
                listView
            }
        }
        .background(Theme.screenGradient.ignoresSafeArea())
        .navigationTitle("Duplicate patterns")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            groups = PatternDuplicateHelper.duplicateGroups(in: store.patterns)
        }
        .refreshable {
            groups = PatternDuplicateHelper.duplicateGroups(in: store.patterns)
        }
    }

    private var emptyView: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer().frame(height: 60)
            TappableMascotView(size: 100)
            Text("No duplicates found")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.deepPlum)
            Text("Patterns with the same link or same title from the same site are listed here.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.deepPlum.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.xl)
        }
        .frame(maxWidth: .infinity)
    }

    private var listView: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                Text("Tap Remove on patterns you don’t need. The first in each group is kept.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.deepPlum.opacity(0.6))
                    .padding(.horizontal, Theme.Spacing.lg)
                ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                    duplicateGroupCard(group)
                }
            }
            .padding(.bottom, 100)
        }
    }

    private func duplicateGroupCard(_ group: [Pattern]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("\(group.count) copies")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.softCoral)
            ForEach(group) { pattern in
                HStack(alignment: .top, spacing: Theme.Spacing.md) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(pattern.title)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.deepPlum)
                            .lineLimit(2)
                        if let host = URL(string: pattern.sourceUrl)?.host {
                            Text(host)
                                .font(Theme.Typography.caption2)
                                .foregroundStyle(Theme.deepPlum.opacity(0.5))
                        }
                    }
                    Spacer(minLength: 0)
                    if pattern.id != group.first?.id {
                        Button(role: .destructive) {
                            removePattern(pattern, from: group)
                        } label: {
                            Text("Remove")
                                .font(Theme.Typography.caption)
                        }
                        .disabled(isDeleting)
                    } else {
                        Text("Keep")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.sageGreen)
                    }
                }
                .padding(Theme.Spacing.md)
                .background(Theme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                        .stroke(Theme.deepPlum.opacity(0.08), lineWidth: 1)
                )
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
    }

    private func removePattern(_ pattern: Pattern, from group: [Pattern]) {
        guard let userId = auth.currentUserId else { return }
        isDeleting = true
        Task {
            await store.delete(pattern: pattern, userId: userId)
            groups = PatternDuplicateHelper.duplicateGroups(in: store.patterns)
            isDeleting = false
        }
    }
}
