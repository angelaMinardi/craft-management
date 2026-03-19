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
    @State private var showPaywall = false

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
                    } else if store.patterns.isEmpty {
                        emptySection
                    } else {
                        heroGreeting
                            .tutorialAnchor(.homeVault, isActive: currentStepAnchor == .homeVault)
                        craftCategoryRow
                            .tutorialAnchor(.homeCrafts, isActive: currentStepAnchor == .homeCrafts)
                        statsSection
                            .tutorialAnchor(.homeStats, isActive: currentStepAnchor == .homeStats)
                        recentSection
                        if !SubscriptionStore.shared.isPremium {
                            premiumTeaserRow
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.lg)
                .padding(.bottom, 100)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: 84)
            }
            .background(Theme.screenGradient)
            .navigationTitle("Pattern Vault")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable {
                if let userId = auth.currentUserId {
                    await store.load(userId: userId)
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
            .task {
                if store.patterns.isEmpty, let userId = auth.currentUserId {
                    await store.load(userId: userId)
                }
            }
        }
    }

    // MARK: - Loading & empty

    private var loadingSection: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer().frame(height: 60)
            SpriteMascotView.walking(size: 100)
            Text("Loading your vault...")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.deepPlum.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Loading your vault")
    }

    private var emptySection: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer().frame(height: 40)

            VStack(spacing: Theme.Spacing.lg) {
                TappableMascotView(size: 120)

                Text("Your vault is empty")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.deepPlum)

                Text("Share a pattern from Safari or any app\nto start building your collection.")
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

    // MARK: - Hero Greeting (personalized, avatar, accent keyword)

    private var heroGreeting: some View {
        ZStack(alignment: .bottomTrailing) {
            HStack(alignment: .top, spacing: Theme.Spacing.lg) {
                // Left: greeting content
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text(personalizedGreeting)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.deepPlum.opacity(0.5))

                    // Accent keyword headline
                    (Text("Your ")
                        .foregroundStyle(Theme.deepPlum)
                    + Text("Vault")
                        .foregroundStyle(Theme.softCoral)
                    )
                    .font(.system(size: 28, weight: .bold, design: .rounded))

                    Text("\(store.patterns.count) pattern\(store.patterns.count == 1 ? "" : "s") in your vault")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.deepPlum.opacity(0.45))
                        .padding(.top, 1)
                }

                Spacer(minLength: 0)

                // Right: avatar circle
                ZStack {
                    Circle()
                        .fill(Theme.softCoral.opacity(0.12))
                        .frame(width: 52, height: 52)

                    if let initial = userInitial {
                        Text(initial)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.softCoral)
                    } else {
                        SpriteMascotView.idle(size: 44)
                            .clipShape(Circle())
                    }
                }
                .padding(.top, 2)
            }
            .padding(Theme.Spacing.xl)

            SpriteMascotView.knitting(size: 48)
                .padding(.trailing, Theme.Spacing.md)
                .padding(.bottom, Theme.Spacing.md)
        }
        .background(
            LinearGradient(
                colors: [Theme.warmCream, Color(red: 1.0, green: 0.96, blue: 0.93)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .borderedCard()
        .staggeredAppear(index: 0)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Your Vault, \(store.patterns.count) pattern\(store.patterns.count == 1 ? "" : "s") in your vault")
    }

    private var premiumTeaserRow: some View {
        Button {
            showPaywall = true
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

    private var personalizedGreeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let timeOfDay: String
        if hour < 12 { timeOfDay = "Good morning" }
        else if hour < 17 { timeOfDay = "Good afternoon" }
        else { timeOfDay = "Good evening" }

        if let name = auth.displayName {
            let firstName = name.components(separatedBy: " ").first ?? name
            return "\(timeOfDay), \(firstName)"
        }
        return timeOfDay
    }

    private var userInitial: String? {
        if let name = auth.displayName, let first = name.first {
            return String(first).uppercased()
        }
        if let email = auth.userEmail, let first = email.first {
            return String(first).uppercased()
        }
        return nil
    }

    // MARK: - Craft Category Quick-access (Newronation-style icon row)

    @ViewBuilder
    private var craftCategoryRow: some View {
        let categories = uniqueCraftTypes
        if !categories.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.lg) {
                    ForEach(Array(categories.enumerated()), id: \.element) { index, craft in
                        Button {
                            onSelectCraft?(craft)
                        } label: {
                            VStack(spacing: Theme.Spacing.xs) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                                        .fill(craftCategoryColor(for: craft).opacity(0.1))
                                        .frame(width: 56, height: 56)
                                    Image(systemName: craftCategoryIcon(for: craft))
                                        .font(.system(size: 22, weight: .medium))
                                        .foregroundStyle(craftCategoryColor(for: craft))
                                }
                                Text(craft.capitalized)
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundStyle(Theme.deepPlum.opacity(0.6))
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(craft.capitalized)
                        .accessibilityHint("Opens Patterns tab filtered by \(craft)")
                        .staggeredAppear(index: index + 1)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    private var uniqueCraftTypes: [String] {
        let types = store.patterns
            .compactMap { $0.craftType }
            .filter { !$0.isEmpty }
        // Deduplicate while preserving order
        var seen = Set<String>()
        return types.filter { seen.insert($0.lowercased()).inserted }
            .prefix(6)
            .map { $0 }
    }

    private func craftCategoryIcon(for craft: String) -> String {
        switch craft.lowercased() {
        case let c where c.contains("knit"): return "scissors"
        case let c where c.contains("crochet"): return "hurricane"
        case let c where c.contains("sew"), let c where c.contains("quilt"): return "rectangle.split.2x2"
        case let c where c.contains("embroider"): return "paintbrush.pointed"
        case let c where c.contains("weav"): return "square.grid.3x3"
        case let c where c.contains("macram"): return "circle.grid.cross"
        case let c where c.contains("leather"): return "rectangle.3.group"
        case let c where c.contains("bead"): return "circle.hexagongrid.fill"
        case let c where c.contains("jewelry"), let c where c.contains("jewell"): return "diamond"
        case let c where c.contains("paper"): return "doc.fill"
        case let c where c.contains("wood"): return "hammer.fill"
        default: return "sparkles"
        }
    }

    private func craftCategoryColor(for craft: String) -> Color {
        switch craft.lowercased() {
        case let c where c.contains("knit"): return Theme.softCoral
        case let c where c.contains("crochet"): return Theme.deepPlum
        case let c where c.contains("sew"), let c where c.contains("quilt"): return Theme.sageGreen
        case let c where c.contains("embroider"): return Theme.honey
        case let c where c.contains("weav"): return Theme.dustyBlue
        case let c where c.contains("macram"): return Theme.softCoral
        case let c where c.contains("leather"): return Theme.deepPlum.opacity(0.9)
        case let c where c.contains("bead"): return Theme.dustyBlue
        case let c where c.contains("jewelry"), let c where c.contains("jewell"): return Theme.honey
        case let c where c.contains("paper"): return Theme.sageGreen
        case let c where c.contains("wood"): return Theme.softCoral
        default: return Theme.softCoral
        }
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
                    .fill(color.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(color)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("\(count)")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.deepPlum)
                Text(title)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.deepPlum.opacity(0.45))
            }

            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.lg)
        .borderedCard()
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
                action: { /* navigates to Patterns tab — handled by parent */ }
            )
            .padding(.horizontal, 2)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.lg) {
                    ForEach(Array(store.patterns.prefix(5).enumerated()), id: \.element.id) { index, pattern in
                        NavigationLink(destination: PatternDetailView(store: store, pattern: pattern)) {
                            PatternCardView(pattern: pattern, userId: auth.currentUserId, elevated: true)
                                .frame(width: 168)
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
