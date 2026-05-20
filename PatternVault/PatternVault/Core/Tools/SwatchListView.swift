//
//  SwatchListView.swift
//  PatternVault
//
//  User's swatch library: photo + gauge + notes for knit/crochet swatches.
//

import SwiftUI

struct SwatchListView: View {
    @EnvironmentObject var auth: AuthService
    @StateObject private var swatchStore = SwatchStore()
    @State private var showAddSheet = false
    @State private var itemToEdit: Swatch?
    @State private var itemToDelete: Swatch?
    @State private var showDeleteConfirm = false

    var body: some View {
        Group {
            if swatchStore.isLoading && swatchStore.items.isEmpty {
                loadingView
            } else if swatchStore.items.isEmpty {
                emptyView
            } else {
                listView
            }
        }
        .background(Theme.screenGradient.ignoresSafeArea())
        .navigationTitle("Swatches")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            if let userId = auth.currentUserId {
                await swatchStore.load(userId: userId)
            }
        }
        .task {
            if swatchStore.items.isEmpty, let userId = auth.currentUserId {
                await swatchStore.load(userId: userId)
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
                .accessibilityLabel("Add swatch")
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddSwatchView(swatchStore: swatchStore, existingItem: itemToEdit)
                .onDisappear { itemToEdit = nil }
        }
        .confirmationDialog("Remove swatch?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                if let item = itemToDelete {
                    Task { await swatchStore.delete(item: item) }
                }
                itemToDelete = nil
            }
            Button("Cancel", role: .cancel) { itemToDelete = nil }
        } message: {
            if let item = itemToDelete {
                Text("\(item.displayTitle) will be removed from your swatch library.")
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer().frame(height: 60)
            SpriteMascotView.thinking(size: 100)
            Text("Loading your swatches...")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Semantic.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer().frame(height: 40)
            TappableMascotView(size: 120)
            Text("No swatches yet")
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.deepPlum)
            Text("Save a photo, the needles you used, and your gauge so you never forget.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Semantic.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.xl)
            Button {
                showAddSheet = true
            } label: {
                Label("Add swatch", systemImage: "plus.circle.fill")
                    .font(Theme.Typography.headline)
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.top, Theme.Spacing.sm)
        }
        .frame(maxWidth: .infinity)
    }

    private var listView: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: Theme.Spacing.md) {
                if let error = swatchStore.errorMessage {
                    VStack(spacing: Theme.Spacing.sm) {
                        Text(error)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.softCoral)
                        Button("Try Again") {
                            guard let userId = auth.currentUserId else { return }
                            Task { await swatchStore.load(userId: userId) }
                        }
                        .font(Theme.Typography.captionSemibold)
                        .foregroundStyle(Theme.deepPlum)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Theme.Spacing.lg)
                }

                ForEach(swatchStore.items) { item in
                    Button {
                        itemToEdit = item
                        showAddSheet = true
                    } label: {
                        swatchRow(item)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.top, Theme.Spacing.lg)
            .padding(.bottom, 100)
        }
    }

    @ViewBuilder
    private func swatchThumbnail(url: String?) -> some View {
        if let urlString = url, let u = URL(string: urlString) {
            AsyncImage(url: u) { phase in
                switch phase {
                case .empty:
                    placeholderThumb
                        .overlay(ProgressView().scaleEffect(0.8))
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    placeholderThumb
                @unknown default:
                    placeholderThumb
                }
            }
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
        } else {
            placeholderThumb
                .frame(width: 72, height: 72)
        }
    }

    private var placeholderThumb: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                .fill(Theme.dustyBlue.opacity(0.14))
            Image(systemName: "square.grid.3x3.fill")
                .font(.system(size: 22))
                .foregroundStyle(Theme.dustyBlue)
        }
    }

    private func swatchRow(_ item: Swatch) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            swatchThumbnail(url: item.photoUrl)
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(item.displayTitle)
                    .font(Theme.Typography.callout)
                    .foregroundStyle(Theme.deepPlum)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let gauge = item.gaugeSummary {
                    Text(gauge)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.sageGreen)
                }
                if let needle = item.needleSummary {
                    Label(needle, systemImage: "scissors")
                        .font(Theme.Typography.caption2)
                        .foregroundStyle(Theme.Semantic.textTertiary)
                }
                if let yarn = item.yarnSummary {
                    Label(yarn, systemImage: "archivebox")
                        .font(Theme.Typography.caption2)
                        .foregroundStyle(Theme.Semantic.textTertiary)
                        .lineLimit(1)
                }
                if item.blocked || item.washed {
                    HStack(spacing: Theme.Spacing.xs) {
                        if item.blocked {
                            Text("Blocked")
                                .font(Theme.Typography.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Theme.sageGreen.opacity(0.14))
                                .foregroundStyle(Theme.sageGreen)
                                .clipShape(Capsule())
                        }
                        if item.washed {
                            Text("Washed")
                                .font(Theme.Typography.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Theme.dustyBlue.opacity(0.14))
                                .foregroundStyle(Theme.dustyBlue)
                                .clipShape(Capsule())
                        }
                    }
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
                    .foregroundStyle(Theme.Semantic.textMuted)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("Options")
        }
        .padding(Theme.Spacing.md)
        .borderedCard()
    }
}
