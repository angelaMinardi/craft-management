//
//  DashboardView.swift
//  PatternVault
//
//  Home screen: hero greeting with mascot, bordered stat cards,
//  and polished recent patterns section.
//

import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var auth: AuthService
    @ObservedObject var store: PatternStore

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
                        statsSection
                        recentSection
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.xxl + 60)
            }
            .background(Theme.screenGradient)
            .navigationTitle("Pattern Vault")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable {
                if let userId = auth.currentUserId {
                    await store.load(userId: userId)
                }
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
    }

    private var emptySection: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer().frame(height: 40)

            // Branded empty card (Luma-style)
            VStack(spacing: Theme.Spacing.lg) {
                SpriteMascotView.idle(size: 120)

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
    }

    // MARK: - Hero Greeting (mascot peeking, warm gradient card)

    private var heroGreeting: some View {
        ZStack(alignment: .trailing) {
            // Content
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(greetingText)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.softCoral)

                Text("Your Vault")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.deepPlum)

                Text("\(store.patterns.count) pattern\(store.patterns.count == 1 ? "" : "s") saved")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.deepPlum.opacity(0.5))
                    .padding(.top, 1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.xl)
            .padding(.trailing, 80) // room for mascot

            // Mascot peeking from right edge
            SpriteMascotView.idle(size: 80)
                .offset(x: 10, y: 4)
                .padding(.trailing, Theme.Spacing.md)
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
    }

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 { return "Good morning" }
        if hour < 17 { return "Good afternoon" }
        return "Good evening"
    }

    // MARK: - Stats (bordered cards with chevrons, Timespent-style)

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
            // Icon circle
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
                            PatternCardView(pattern: pattern, elevated: true)
                                .frame(width: 168)
                        }
                        .buttonStyle(.plain)
                        .staggeredAppear(index: index + 5)
                    }
                }
                .padding(.vertical, Theme.Spacing.xs)
                .padding(.horizontal, 2)
            }
            .padding(.horizontal, -Theme.Spacing.lg)
        }
        .staggeredAppear(index: 5)
    }
}
