//
//  DashboardView.swift
//  PatternVault
//
//  Home screen: personalized greeting with avatar, craft category
//  shortcuts, bordered stat cards, and polished recent patterns.
//

import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var auth: AuthService
    @ObservedObject var store: PatternStore
    @ObservedObject var tutorialStore: AppTutorialStore
    var onSelectCraft: ((String) -> Void)? = nil
    var onViewAllPatterns: (() -> Void)? = nil
    @State private var showPaywall = false
    @ObservedObject private var mascotStore = MascotInteractionStore.shared
    @ObservedObject private var storyStore = MascotStoryStore.shared
    @State private var showMascotRename = false
    @State private var mascotNameDraft = ""
    @State private var showStore = false
    @State private var showHelp = false
    @State private var showStoryLog = false
    @State private var lastSavedCount = 0
    @State private var lastCompletedCount = 0
    @State private var showEnrichingAlert = false
    @State private var enrichingAlertPatternId: UUID?

    private var currentStepAnchor: TutorialAnchor? {
        guard tutorialStore.isActive, tutorialStore.currentStep < AppTutorialStore.steps.count else { return nil }
        return AppTutorialStore.steps[tutorialStore.currentStep].anchorId
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    if store.isLoading {
                        loadingSection
                    } else {
                        dashboardContent
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.lg)
                .padding(.bottom, 100)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: 84)
            }
            .background(seamlessBackground)
            .navigationTitle("Pattern Vault")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable {
                if let userId = auth.currentUserId {
                    await store.load(userId: userId)
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView(source: .dashboard)
            }
            .sheet(isPresented: $showStore) {
                MascotStoreSheet(mascotStore: mascotStore)
            }
            .sheet(isPresented: $showHelp) {
                MascotHelpView()
            }
            .sheet(isPresented: $showStoryLog) {
                MascotStoryLogView(storyStore: storyStore, mascotName: mascotStore.mascotName) { chapter in
                    storyStore.showingChapterId = chapter.id
                }
            }
            .sheet(item: Binding<MascotStoryChapter?>(
                get: { storyStore.chapter(for: storyStore.showingChapterId) },
                set: { _ in storyStore.showingChapterId = nil }
            )) { chapter in
                MascotStoryCutsceneView(chapter: chapter, mascotName: mascotStore.mascotName) {
                    storyStore.markViewed(id: chapter.id)
                    storyStore.showingChapterId = nil
                }
            }
            .alert("Still Processing", isPresented: $showEnrichingAlert) {
                Button("Retry Now") {
                    if let pid = enrichingAlertPatternId,
                       let pattern = store.patterns.first(where: { $0.id == pid }),
                       let userId = auth.currentUserId {
                        Task { await store.retryEnrichment(pattern: pattern, userId: userId) }
                    }
                }
                Button("OK", role: .cancel) { }
            } message: {
                Text("This pattern is still being analyzed. You'll get a notification when it's ready — feel free to leave and come back!")
            }
            .alert("Name your mascot", isPresented: $showMascotRename) {
                TextField("Mascot name", text: $mascotNameDraft)
                Button("Save") {
                    mascotStore.setName(mascotNameDraft)
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This name appears in dashboard encouragement.")
            }
            .overlay(alignment: .top) {
                if storyStore.showUnlockBanner, let pending = storyStore.chapter(for: storyStore.progress.pendingId) {
                    Button {
                        storyStore.openPendingChapter()
                    } label: {
                        HStack {
                            Image(systemName: "sparkles")
                            Text("Story unlocked: \(pending.title)")
                                .lineLimit(1)
                            Spacer()
                            Text("Play")
                                .font(.caption.bold())
                        }
                        .font(Theme.Typography.caption)
                        .foregroundStyle(.white)
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.vertical, Theme.Spacing.sm)
                        .background(Theme.deepPlum)
                        .clipShape(Capsule())
                        .padding(.top, 6)
                        .padding(.horizontal, Theme.Spacing.lg)
                    }
                    .buttonStyle(.plain)
                }
            }
            .task {
                if store.patterns.isEmpty, let userId = auth.currentUserId {
                    await store.load(userId: userId)
                }
                mascotStore.syncFallbackCounts(patterns: store.patterns)
                lastSavedCount = store.patterns.count
                lastCompletedCount = store.completedCount
                evaluateStoryUnlocks()
            }
            .onChange(of: store.patterns.count) { _, _ in
                mascotStore.syncFallbackCounts(patterns: store.patterns)
                if store.patterns.count > lastSavedCount {
                    mascotStore.rewardForPatternSaved()
                }
                lastSavedCount = store.patterns.count
                evaluateStoryUnlocks()
            }
            .onChange(of: mascotStore.streakCount) { _, _ in evaluateStoryUnlocks() }
            .onChange(of: store.completedCount) { _, newValue in
                if newValue > lastCompletedCount {
                    mascotStore.rewardForPatternCompletion()
                }
                lastCompletedCount = newValue
                evaluateStoryUnlocks()
            }
        }
    }

    // MARK: - Loading & empty

    private var loadingSection: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer().frame(height: 60)
            SpriteMascotView.thinking(size: 100)
                .accessibilityHidden(true)
            Text("Loading your vault...")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.deepPlum.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Mascot thinking. Loading your vault.")
    }

    private var dashboardContent: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            MascotDashboardPanelView(
                store: mascotStore,
                onOpenSettings: {
                    mascotNameDraft = mascotStore.mascotName
                    showMascotRename = true
                },
                onOpenStore: {
                    showStore = true
                    mascotStore.markExplanationsSeen()
                },
                showLabels: !mascotStore.hasSeenExplanations
            )
            .overlay(alignment: .topLeading) {
                if !mascotStore.hasSeenExplanations {
                    Button {
                        showHelp = true
                        mascotStore.markExplanationsSeen()
                    } label: {
                        Image(systemName: "questionmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Theme.deepPlum.opacity(0.6))
                    }
                    .padding(10)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                Button {
                    showStoryLog = true
                } label: {
                    Label("Story", systemImage: "book.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Theme.deepPlum.opacity(0.82))
                        .clipShape(Capsule())
                }
                .padding(10)
            }
            .tutorialAnchor(.homeVault, isActive: currentStepAnchor == .homeVault)
            .padding(.bottom, -Theme.Spacing.sm)

            if store.patterns.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    nextActionBanner(
                        title: "Your next step: save one pattern",
                        subtitle: "\(mascotStore.mascotName) is ready to help you start."
                    )
                    emptySection
                }
                .padding(.horizontal, Theme.Spacing.xs)
            } else {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    statsSection
                        .tutorialAnchor(.homeStats, isActive: currentStepAnchor == .homeStats)
                    recentSection
                    if !SubscriptionStore.shared.isPremium {
                        premiumTeaserRow
                    }
                }
                .padding(.horizontal, Theme.Spacing.xs)
            }
        }
    }

    private var seamlessBackground: some View {
        ZStack {
            Theme.screenGradient
            Image("MascotHeroBackground")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
                .opacity(0.26)
                .mask(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.95),
                            .white.opacity(0.9),
                            .white.opacity(0.7),
                            .white.opacity(0.35),
                            .clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
    }

    private var emptySection: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer().frame(height: 40)

            VStack(spacing: Theme.Spacing.lg) {
                Text("Your next win starts here")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.deepPlum)

                Text("Save one pattern from Safari or any app.\nYou'll be ready to track progress right away.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.deepPlum.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            .padding(.vertical, Theme.Spacing.xxl)
            .padding(.horizontal, Theme.Spacing.xl)
            .frame(maxWidth: .infinity)
            .borderedCard()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Your vault is empty. Share a pattern from Safari or any app to start building your collection.")
    }

    private var premiumTeaserRow: some View {
        Button {
            if GrowthOrchestrator.shared.canShowPaywall(source: .dashboard) {
                showPaywall = true
            }
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "crown")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.honey.opacity(0.9))
                Text(Theme.Premium.teaser)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.deepPlum.opacity(0.55))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.deepPlum.opacity(0.25))
            }
            .padding(.vertical, Theme.Spacing.sm)
            .padding(.horizontal, Theme.Spacing.md)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Theme.Premium.teaser)
        .accessibilityHint("Opens Premium")
    }

    private func nextActionBanner(title: String, subtitle: String) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "sparkles")
                .font(.system(size: 14))
                .foregroundStyle(Theme.honey)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.deepPlum)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Text(subtitle)
                    .font(Theme.Typography.caption2)
                    .foregroundStyle(Theme.deepPlum.opacity(0.55))
                    .lineLimit(3)
                    .minimumScaleFactor(0.85)
            }
            Spacer()
        }
        .padding(.vertical, Theme.Spacing.sm)
        .padding(.horizontal, Theme.Spacing.md)
        .background(Color.white.opacity(0.42))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                .stroke(Theme.deepPlum.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
        .accessibilityElement(children: .combine)
    }

    private var nextActionTitle: String {
        if let inProgress = store.patterns.first(where: { $0.status == .inProgress }) {
            return "Continue \(inProgress.title)"
        }
        if let want = store.patterns.first(where: { $0.status == .wantToMake }) {
            return "Start \(want.title)"
        }
        return "Log progress on your latest pattern"
    }

    private var nextActionSubtitle: String {
        if store.inProgressCount > 0 {
            return "A quick progress update keeps your streak moving."
        }
        if store.wantToMakeCount > 0 {
            return "Starting one project unlocks better recommendations."
        }
        return "Small updates now make your next session easier."
    }

    private func evaluateStoryUnlocks() {
        storyStore.evaluateUnlocks(
            hasSeenOnboarding: UserDefaults.standard.bool(forKey: "hasSeenOnboarding"),
            streak: mascotStore.streakCount,
            savedCount: store.patterns.count,
            completedCount: store.completedCount,
            hasAnyNote: UserDefaults.standard.bool(forKey: "mascot_has_any_note")
        )
    }

    // MARK: - Stats (bordered cards, Timespent-style)

    private var statsSection: some View {
        VStack(spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.md) {
                statCard(
                    title: "Want to make",
                    count: store.wantToMakeCount,
                    icon: "heart.fill",
                    color: Theme.softCoral,
                    index: 1
                )
                statCard(
                    title: "In progress",
                    count: store.inProgressCount,
                    icon: "hammer.fill",
                    color: Theme.honey,
                    index: 2
                )
            }
            HStack(spacing: Theme.Spacing.md) {
                statCard(
                    title: "Completed",
                    count: store.completedCount,
                    icon: "checkmark.circle.fill",
                    color: Theme.sageGreen,
                    index: 3
                )
                statCard(
                    title: "All saved",
                    count: store.patterns.count,
                    icon: "bookmark.fill",
                    color: Theme.dustyBlue,
                    index: 4
                )
            }
        }
    }

    @ViewBuilder
    private func statCard(title: String, count: Int, icon: String, color: Color, index: Int) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.14))
                    .frame(width: 38, height: 38)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(color)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("\(count)")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.deepPlum)
                Text(title)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.deepPlum.opacity(0.5))
            }

            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                .fill(Color.white.opacity(0.62))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                .stroke(Theme.deepPlum.opacity(0.08), lineWidth: 1)
        )
        .staggeredAppear(index: index)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(count) pattern\(count == 1 ? "" : "s")")
        .accessibilityHint("Status: \(title)")
    }

    // MARK: - Recent (section header + horizontal cards)

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeaderView(
                title: "Recent",
                trailing: store.patterns.count > 3 ? "View all" : nil,
                action: {
                    onViewAllPatterns?()
                }
            )
            .padding(.horizontal, 2)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.lg) {
                    ForEach(Array(store.patterns.prefix(5).enumerated()), id: \.element.id) { index, pattern in
                        Group {
                            if pattern.isEnriching {
                                Button {
                                    enrichingAlertPatternId = pattern.id
                                    showEnrichingAlert = true
                                } label: {
                                    PatternCardView(pattern: pattern, userId: auth.currentUserId, elevated: true)
                                        .frame(width: 168)
                                }
                            } else {
                                NavigationLink(destination: PatternDetailView(store: store, pattern: pattern)) {
                                    PatternCardView(pattern: pattern, userId: auth.currentUserId, elevated: true)
                                        .frame(width: 168)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .frame(width: 168)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .staggeredAppear(index: index + 5)
                    }
                }
                .padding(.vertical, Theme.Spacing.sm)
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.sm)
            }
        }
        .padding(.bottom, Theme.Spacing.lg)
        .staggeredAppear(index: 5)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Recent patterns")
    }
}
