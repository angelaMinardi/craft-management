//
//  YarnStashListView.swift
//  PatternVault
//

import SwiftUI

struct YarnStashListView: View {
    @EnvironmentObject var auth: AuthService
    @ObservedObject var store: PatternStore
    @StateObject private var stashStore = YarnStashStore()
    @State private var showAddSheet = false
    @State private var itemToEdit: YarnStashItem?
    @State private var itemToDelete: YarnStashItem?
    @State private var showDeleteConfirm = false
    @State private var showPaywall = false

    var body: some View {
        Group {
            if stashStore.isLoading && stashStore.items.isEmpty {
                loadingView
            } else if stashStore.items.isEmpty {
                emptyView
            } else {
                listView
            }
        }
        .background(Theme.screenGradient.ignoresSafeArea())
        .navigationTitle("Stash")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            if let userId = auth.currentUserId {
                await stashStore.load(userId: userId)
            }
        }
        .task {
            if stashStore.items.isEmpty, let userId = auth.currentUserId {
                await stashStore.load(userId: userId)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    itemToEdit = nil
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(Theme.sageGreen)
                }
                .accessibilityLabel("Add to stash")
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddYarnStashView(stashStore: stashStore, existingItem: itemToEdit)
                .onDisappear { itemToEdit = nil }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(source: .settings)
        }
        .confirmationDialog("Remove from stash?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                if let item = itemToDelete {
                    Task { await stashStore.delete(item: item) }
                }
                itemToDelete = nil
            }
            Button("Cancel", role: .cancel) { itemToDelete = nil }
        } message: {
            if let item = itemToDelete {
                Text("\(item.brandName)\(item.colorName.map { " · \($0)" } ?? "") will be removed from your stash.")
            }
        }
        .navigationDestination(for: Pattern.self) { pattern in
            PatternDetailView(store: store, pattern: pattern)
        }
    }

    private var loadingView: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer().frame(height: 60)
            SpriteMascotView.thinking(size: 100)
            Text("Loading your stash...")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Semantic.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer().frame(height: 40)
            TappableMascotView(size: 120)
            Text("No materials yet")
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.deepPlum)
            Text("Nothing here yet—add something when you're ready.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Semantic.textTertiary)
            Text("Tap + to add yarn, fabric, or other materials. Track brand, color, weight, and amount.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Semantic.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.xl)
            Button {
                showAddSheet = true
            } label: {
                Label("Add material", systemImage: "plus.circle.fill")
                    .font(Theme.Typography.headline)
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.top, Theme.Spacing.sm)
        }
        .frame(maxWidth: .infinity)
    }

    private var listView: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: Theme.Spacing.sm) {
                if let error = stashStore.errorMessage {
                    VStack(spacing: Theme.Spacing.sm) {
                        Text(error)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.softCoral)
                        Button("Try Again") {
                            guard let userId = auth.currentUserId else { return }
                            Task { await stashStore.load(userId: userId) }
                        }
                        .font(Theme.Typography.captionSemibold)
                        .foregroundStyle(Theme.deepPlum)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Theme.Spacing.lg)
                }

                ForEach(stashStore.items) { item in
                    yarnStashRow(item)
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.top, Theme.Spacing.lg)
            .padding(.bottom, 100)
        }
    }

    private func yarnStashRow(_ item: YarnStashItem) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(item.brandName)
                    .font(Theme.Typography.callout)
                    .foregroundStyle(Theme.deepPlum)
                let yardagePart = item.totalYardage.map { ["\($0) yd"] }
                let qtyPart: [String]? = yardagePart == nil && item.skeinsOwned != 0
                    ? [item.skeinsOwned == floor(item.skeinsOwned) ? "Qty: \(Int(item.skeinsOwned))" : "Qty: \(item.skeinsOwned)"]
                    : nil
                let subtitleParts = [item.colorName, item.weight].compactMap { $0 }.filter { !$0.isEmpty } + (yardagePart ?? qtyPart ?? [])
                if !subtitleParts.isEmpty {
                    Text(subtitleParts.joined(separator: " · "))
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Semantic.textTertiary)
                }
                if let loc = item.location, !loc.isEmpty {
                    Text(loc)
                        .font(Theme.Typography.caption2)
                        .foregroundStyle(Theme.dustyBlue)
                }
            }
            Spacer(minLength: 0)
            if let yd = item.totalYardage {
                Text("\(yd) yd")
                    .font(Theme.Typography.footnoteSemibold)
                    .foregroundStyle(Theme.sageGreen)
            } else if item.skeinsOwned != 0 {
                Text(item.skeinsOwned == floor(item.skeinsOwned) ? "\(Int(item.skeinsOwned))" : "\(item.skeinsOwned)")
                    .font(Theme.Typography.footnoteSemibold)
                    .foregroundStyle(Theme.sageGreen)
            }
            Menu {
                Button {
                    itemToEdit = item
                    showAddSheet = true
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                if SubscriptionStore.shared.isPremium {
                    NavigationLink {
                        StashMatchPatternsView(store: store, stashItem: item)
                    } label: {
                        Label("Match patterns", systemImage: "magnifyingglass")
                    }
                } else {
                    Button {
                        showPaywall = true
                    } label: {
                        Label("Match patterns", systemImage: "lock.fill")
                    }
                }
                Button(role: .destructive) {
                    itemToDelete = item
                    showDeleteConfirm = true
                } label: {
                    Label("Remove from stash", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.Semantic.textMuted)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("Options")
        }
        .padding(Theme.Spacing.md)
        .borderedCard()
    }
}
