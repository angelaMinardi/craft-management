//
//  StashAndToolsView.swift
//  PatternVault
//
//  Main-tab hub for materials (stash) and tools. Craft-agnostic; accessible from the tab bar.
//

import SwiftUI

struct StashAndToolsView: View {
    @ObservedObject var tutorialStore: AppTutorialStore
    @ObservedObject var store: PatternStore

    private var currentStepAnchor: TutorialAnchor? {
        guard tutorialStore.isActive, tutorialStore.currentStep < AppTutorialStore.steps.count else { return nil }
        return AppTutorialStore.steps[tutorialStore.currentStep].anchorId
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    headerSection
                    VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                        stashCard
                        toolsCard
                        findPatternsCard
                        glossaryCard
                    }
                    .tutorialAnchor(.stashCards, isActive: currentStepAnchor == .stashCards)
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.lg)
                .padding(.bottom, 100)
            }
            .background(Theme.screenGradient.ignoresSafeArea())
            .navigationTitle("Stash & tools")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var headerSection: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.lg) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Materials & tools")
                    .font(Theme.Typography.largeTitle)
                    .foregroundStyle(Theme.deepPlum)
                Text("Track what you have on hand so you’re ready for your next project.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Semantic.textTertiary)
            }
            Spacer(minLength: 0)
            TappableMascotView(size: 52)
        }
    }

    private var stashCard: some View {
        NavigationLink {
            YarnStashListView(store: store)
        } label: {
            HStack(spacing: Theme.Spacing.lg) {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                        .fill(Theme.sageGreen.opacity(0.14))
                        .frame(width: 56, height: 56)
                    Image(systemName: "archivebox.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Theme.sageGreen)
                }
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Stash")
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.deepPlum)
                    Text("Yarn, fabric, or other materials you have on hand")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Semantic.textMuted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Semantic.iconFaint)
            }
            .padding(Theme.Spacing.lg)
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.large))
            .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }

    private var findPatternsCard: some View {
        Button {
            if let url = URL(string: "https://www.ravelry.com/patterns/search") {
                UIApplication.shared.open(url)
            }
        } label: {
            HStack(spacing: Theme.Spacing.lg) {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                        .fill(Theme.softCoral.opacity(0.14))
                        .frame(width: 56, height: 56)
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 24))
                        .foregroundStyle(Theme.softCoral)
                }
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Search on Ravelry")
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.deepPlum)
                    Text("Open Ravelry in Safari to search for patterns")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Semantic.textMuted)
                }
                Spacer(minLength: 0)
                Image(systemName: "safari")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Semantic.iconFaint)
            }
            .padding(Theme.Spacing.lg)
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.large))
            .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }

    private var glossaryCard: some View {
        NavigationLink {
            GlossaryView()
        } label: {
            HStack(spacing: Theme.Spacing.lg) {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                        .fill(Theme.dustyBlue.opacity(0.14))
                        .frame(width: 56, height: 56)
                    Image(systemName: "character.book.closed.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Theme.dustyBlue)
                }
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Stitch Glossary")
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.deepPlum)
                    Text("Look up knitting & crochet abbreviations")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Semantic.textMuted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Semantic.iconFaint)
            }
            .padding(Theme.Spacing.lg)
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.large))
            .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }

    private var toolsCard: some View {
        NavigationLink {
            NeedleHookListView()
        } label: {
            HStack(spacing: Theme.Spacing.lg) {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                        .fill(Theme.dustyBlue.opacity(0.14))
                        .frame(width: 56, height: 56)
                    Image(systemName: "scissors")
                        .font(.system(size: 26))
                        .foregroundStyle(Theme.dustyBlue)
                }
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Tools")
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.deepPlum)
                    Text("Needles, hooks, and other tools")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Semantic.textMuted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Semantic.iconFaint)
            }
            .padding(Theme.Spacing.lg)
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.large))
            .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }
}
