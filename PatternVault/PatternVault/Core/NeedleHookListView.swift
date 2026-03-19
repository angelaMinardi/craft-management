//
//  NeedleHookListView.swift
//  PatternVault
//

import SwiftUI

struct NeedleHookListView: View {
    @EnvironmentObject var auth: AuthService
    @StateObject private var needleHookStore = NeedleHookStore()
    @State private var showAddSheet = false
    @State private var itemToEdit: NeedleHookItem?
    @State private var itemToDelete: NeedleHookItem?
    @State private var showDeleteConfirm = false

    var body: some View {
        Group {
            if needleHookStore.isLoading && needleHookStore.items.isEmpty {
                loadingView
            } else if needleHookStore.items.isEmpty {
                emptyView
            } else {
                listView
            }
        }
        .background(Theme.screenGradient.ignoresSafeArea())
        .navigationTitle("Tools")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            if let userId = auth.currentUserId {
                await needleHookStore.load(userId: userId)
            }
        }
        .task {
            if needleHookStore.items.isEmpty, let userId = auth.currentUserId {
                await needleHookStore.load(userId: userId)
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
                .accessibilityLabel("Add tool")
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddNeedleHookView(needleHookStore: needleHookStore, existingItem: itemToEdit)
                .onDisappear { itemToEdit = nil }
        }
        .confirmationDialog("Remove from inventory?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Remove", role: .destructive) {
                if let item = itemToDelete {
                    Task { await needleHookStore.delete(item: item) }
                }
                itemToDelete = nil
            }
            Button("Cancel", role: .cancel) { itemToDelete = nil }
        } message: {
            if let item = itemToDelete {
                Text("\(item.typeDisplayName) \(item.size) will be removed from your tools.")
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer().frame(height: 60)
            SpriteMascotView.walking(size: 100)
            Text("Loading inventory...")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.deepPlum.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer().frame(height: 40)
            TappableMascotView(size: 120)
            Text("No tools yet")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.deepPlum)
            Text("Nothing here yet—add whatever tools you use when you're ready.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.deepPlum.opacity(0.6))
            Text("Track needles, hooks, cutters, and any other tools. Tap + to add.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.deepPlum.opacity(0.55))
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.xl)
            Button {
                showAddSheet = true
            } label: {
                Label("Add tool", systemImage: "plus.circle.fill")
                    .font(Theme.Typography.headline)
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.top, Theme.Spacing.sm)
        }
        .frame(maxWidth: .infinity)
    }

    private var listView: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                if let error = needleHookStore.errorMessage {
                    Text(error)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.softCoral)
                        .padding(.horizontal, Theme.Spacing.lg)
                }

                if !needleHookStore.needles.isEmpty {
                    sectionHeader("Needles")
                    ForEach(needleHookStore.needles) { item in
                        toolRow(item)
                    }
                }

                if !needleHookStore.hooks.isEmpty {
                    sectionHeader("Hooks")
                    ForEach(needleHookStore.hooks) { item in
                        toolRow(item)
                    }
                }

                if !needleHookStore.otherTools.isEmpty {
                    sectionHeader("Other tools")
                    ForEach(needleHookStore.otherTools) { item in
                        toolRow(item)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.top, Theme.Spacing.lg)
            .padding(.bottom, 100)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(Theme.deepPlum.opacity(0.6))
    }

    private func toolIconColor(_ type: String) -> Color {
        switch type.lowercased() {
        case "needle": return Theme.dustyBlue
        case "hook": return Theme.softCoral
        default: return Theme.sageGreen
        }
    }

    private func toolRow(_ item: NeedleHookItem) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Image(systemName: item.typeSystemImage)
                .font(.system(size: 18))
                .foregroundStyle(toolIconColor(item.type))
                .frame(width: 28, alignment: .center)
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(item.typeDisplayName)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.deepPlum.opacity(0.7))
                Text(item.size)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.deepPlum)
                if let len = item.lengthCm, len > 0 {
                    Text("\(Int(len)) cm")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.deepPlum.opacity(0.6))
                }
                if let n = item.notes, !n.isEmpty {
                    Text(n)
                        .font(Theme.Typography.caption2)
                        .foregroundStyle(Theme.deepPlum.opacity(0.5))
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            Menu {
                Button {
                    itemToEdit = item
                    showAddSheet = true
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    itemToDelete = item
                    showDeleteConfirm = true
                } label: {
                    Label("Remove", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.deepPlum.opacity(0.5))
            }
        }
        .padding(Theme.Spacing.md)
        .borderedCard()
    }
}
