//
//  PatternListView.swift
//  PatternVault
//

import SwiftUI

struct PatternListView: View {
    @EnvironmentObject var auth: AuthService
    @ObservedObject var store: PatternStore
    @Binding var sharedURL: String?

    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var tagStore = TagStore()
    @State private var showAddSheet = false
    @State private var searchText = ""
    @State private var filterStatus: PatternStatus?
    @State private var filterTagIds: Set<UUID> = []

    private var filteredPatterns: [Pattern] {
        var result = store.patterns
        if let filterStatus {
            result = result.filter { $0.status == filterStatus }
        }
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.title.lowercased().contains(query) ||
                ($0.patternDescription?.lowercased().contains(query) ?? false)
            }
        }
        if !filterTagIds.isEmpty {
            result = result.filter { pattern in
                let patternTags = patternTagsMap[pattern.id] ?? []
                return !filterTagIds.isDisjoint(with: patternTags)
            }
        }
        return result
    }

    @State private var patternTagsMap: [UUID: Set<UUID>] = [:]

    var body: some View {
        NavigationStack {
            Group {
                if let error = store.errorMessage, !store.isLoading {
                    VStack(spacing: Theme.Spacing.lg) {
                        SpriteMascotView.pouty(size: 100)
                        Text(error)
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.softCoral)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        Button("Try again") {
                            store.errorMessage = nil
                            if let userId = auth.currentUserId {
                                Task { await store.load(userId: userId) }
                            }
                        }
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.deepPlum)
                    }
                    .padding(.top, 60)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if store.isLoading {
                    VStack(spacing: Theme.Spacing.lg) {
                        SpriteMascotView.walking(size: 100)
                        Text("Loading patterns...")
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.deepPlum.opacity(0.6))
                    }
                    .padding(.top, 60)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if store.patterns.isEmpty {
                    VStack(spacing: Theme.Spacing.lg) {
                        SpriteMascotView.idle(size: 120)
                        Text("No patterns yet")
                            .font(Theme.Typography.title)
                            .foregroundStyle(Theme.deepPlum)
                        Text("Tap + to add your first pattern.")
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.deepPlum.opacity(0.6))
                    }
                    .padding(.top, 60)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: Theme.Spacing.md) {
                            // Status filter chips
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: Theme.Spacing.sm) {
                                    filterChip("All", isSelected: filterStatus == nil) {
                                        filterStatus = nil
                                    }
                                    ForEach(PatternStatus.allCases, id: \.self) { s in
                                        filterChip(s.displayName, isSelected: filterStatus == s) {
                                            filterStatus = filterStatus == s ? nil : s
                                        }
                                    }
                                }
                                .padding(.horizontal, Theme.Spacing.lg)
                            }

                            // Tag filter chips
                            if !tagStore.allTags.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 6) {
                                        ForEach(tagStore.allTags) { tag in
                                            Button {
                                                if filterTagIds.contains(tag.id) {
                                                    filterTagIds.remove(tag.id)
                                                } else {
                                                    filterTagIds.insert(tag.id)
                                                }
                                            } label: {
                                                Text(tag.name)
                                                    .tagPill(isSelected: filterTagIds.contains(tag.id))
                                            }
                                        }
                                    }
                                    .padding(.horizontal, Theme.Spacing.lg)
                                }
                            }

                            // 2-column card grid
                            LazyVGrid(
                                columns: [
                                    GridItem(.flexible(), spacing: Theme.Spacing.md),
                                    GridItem(.flexible(), spacing: Theme.Spacing.md)
                                ],
                                spacing: Theme.Spacing.md
                            ) {
                                ForEach(Array(filteredPatterns.enumerated()), id: \.element.id) { index, pattern in
                                    NavigationLink(destination: PatternDetailView(store: store, pattern: pattern)) {
                                        PatternCardView(
                                            pattern: pattern,
                                            isFavorite: pattern.status == .wantToMake,
                                            isNew: isRecentlyAdded(pattern)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .staggeredAppear(index: index)
                                }
                            }
                            .padding(.horizontal, Theme.Spacing.lg)
                        }
                        .padding(.top, Theme.Spacing.sm)
                    }
                    .searchable(text: $searchText, prompt: "Search patterns")
                }
            }
            .background(Theme.warmCream)
            .navigationTitle("Patterns")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddSheet, onDismiss: {
                sharedURL = nil
            }) {
                AddPatternView(store: store, prefillURL: sharedURL)
            }
            .refreshable {
                if let userId = auth.currentUserId {
                    await store.load(userId: userId)
                }
            }
            .task {
                if store.patterns.isEmpty, let userId = auth.currentUserId {
                    await store.load(userId: userId)
                }
                await tagStore.loadAllTags()
                await loadPatternTagsMap()
            }
            .onChange(of: sharedURL) { _, newURL in
                if newURL != nil {
                    showAddSheet = true
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active, let userId = auth.currentUserId {
                    Task {
                        await store.load(userId: userId)
                        await loadPatternTagsMap()
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .patternListShouldRefresh)) { _ in
                if let userId = auth.currentUserId {
                    Task { await store.load(userId: userId) }
                }
            }
        }
    }

    @ViewBuilder
    private func filterChip(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .tagPill(isSelected: isSelected)
        }
    }

    private func isRecentlyAdded(_ pattern: Pattern) -> Bool {
        pattern.createdAt > Date().addingTimeInterval(-7 * 24 * 60 * 60)
    }

    private func loadPatternTagsMap() async {
        let repo = TagRepository()
        var map: [UUID: Set<UUID>] = [:]
        for pattern in store.patterns {
            if let tags = try? await repo.fetchTags(forPatternId: pattern.id) {
                map[pattern.id] = Set(tags.map(\.id))
            }
        }
        patternTagsMap = map
    }
}
