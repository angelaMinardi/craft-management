//
//  PaywallView.swift
//  PatternVault
//
//  Freemium: Premium subscription benefits and purchase/restore.
//

import SwiftUI
import StoreKit

struct PaywallView: View {
    @ObservedObject private var subscriptionStore = SubscriptionStore.shared
    @Environment(\.dismiss) private var dismiss
    let source: GrowthOrchestrator.PaywallSource
    @State private var purchaseSucceeded = false

    init(source: GrowthOrchestrator.PaywallSource = .unknown) {
        self.source = source
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    if subscriptionStore.isPremium {
                        HStack(spacing: Theme.Spacing.sm) {
                            Image(systemName: "crown.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(Theme.honey)
                            Text("You're a Premium member")
                                .font(Theme.Typography.title)
                                .foregroundStyle(Theme.deepPlum)
                        }
                        .padding(.top, Theme.Spacing.lg)
                        Text("You have unlimited patterns, project mode, stash matching, Row Tracker widget, AI analyses, note photos, and an ad-free experience.")
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.deepPlum.opacity(0.8))
                        Spacer(minLength: 40)
                    } else {
                        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                            Text("Unlock Premium")
                                .font(Theme.Typography.largeTitle)
                                .foregroundStyle(Theme.deepPlum)
                            Text(Theme.Premium.tagline)
                                .font(Theme.Typography.body)
                                .foregroundStyle(Theme.deepPlum.opacity(0.8))
                        }
                        .padding(.top, Theme.Spacing.lg)

                        benefitRow(icon: "square.stack.3d.up.fill", text: "Unlimited patterns")
                        benefitRow(icon: "hammer.fill", text: "Project mode & multiple makes per pattern")
                        benefitRow(icon: "archivebox.fill", text: "Stash matching & yardage calculator")
                        benefitRow(icon: "gauge.with.dots.needle.33percent", text: "Row Tracker lock screen widget")
                        benefitRow(icon: "wand.and.stars", text: "Unlimited AI analyses per month")
                        benefitRow(icon: "photo.stack.fill", text: "Unlimited note photos")
                        benefitRow(icon: "nosign", text: "Ad-free experience")

                        if !displayProducts.isEmpty {
                            VStack(spacing: Theme.Spacing.sm) {
                                ForEach(displayProducts, id: \.id) { product in
                                    Button {
                                        Task {
                                            let success = await subscriptionStore.purchase(product)
                                            if success {
                                                purchaseSucceeded = true
                                                dismiss()
                                            } else if subscriptionStore.purchaseError != nil {
                                                GrowthOrchestrator.shared.registerFrictionEvent(.purchaseFailure)
                                            } else {
                                                GrowthOrchestrator.shared.registerFrictionEvent(.purchaseCancelled)
                                            }
                                        }
                                    } label: {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(product.displayName)
                                                    .font(Theme.Typography.headline)
                                                    .foregroundStyle(Theme.deepPlum)
                                                Text(product.description)
                                                    .font(Theme.Typography.caption2)
                                                    .foregroundStyle(Theme.deepPlum.opacity(0.6))
                                            }
                                            Spacer()
                                            Text(product.displayPrice)
                                                .font(Theme.Typography.headline)
                                                .foregroundStyle(Theme.sageGreen)
                                        }
                                        .padding(Theme.Spacing.lg)
                                        .background(Theme.cardBackground)
                                        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                                                .stroke(Theme.softCoral.opacity(0.3), lineWidth: 1)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(subscriptionStore.isLoading)
                                }
                            }
                            .padding(.vertical, Theme.Spacing.md)

                            if let err = subscriptionStore.purchaseError {
                                Text(err)
                                    .font(Theme.Typography.caption)
                                    .foregroundStyle(Theme.softCoral)
                            }

                            restorePurchasesButton
                        } else {
                            // Products didn't load: show error + retry, never leave user stuck
                            if subscriptionStore.productsLoading {
                                VStack(spacing: Theme.Spacing.md) {
                                    ProgressView()
                                        .tint(Theme.softCoral)
                                    Text("Loading subscription options…")
                                        .font(Theme.Typography.caption)
                                        .foregroundStyle(Theme.deepPlum.opacity(0.6))
                                }
                                .padding(.vertical, Theme.Spacing.xl)
                            } else {
                                VStack(spacing: Theme.Spacing.md) {
                                    if let err = subscriptionStore.productsLoadError {
                                        Text(err)
                                            .font(Theme.Typography.caption)
                                            .foregroundStyle(Theme.softCoral)
                                            .multilineTextAlignment(.center)
                                    }
#if DEBUG
                                    if let debug = subscriptionStore.productsDebugDetails, !debug.isEmpty {
                                        Text(debug)
                                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                                            .foregroundStyle(Theme.deepPlum.opacity(0.7))
                                            .multilineTextAlignment(.leading)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
#endif
                                    Button("Try again") {
                                        Task { await subscriptionStore.refreshProducts() }
                                    }
                                    .font(Theme.Typography.body)
                                    .foregroundStyle(Theme.softCoral)
                                }
                                .padding(.vertical, Theme.Spacing.md)
                            }
                            restorePurchasesButton
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, 40)
            }
            .background(Theme.screenGradient.ignoresSafeArea())
            .navigationTitle("Premium")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.softCoral)
                }
            }
        }
        .task {
            await subscriptionStore.updateSubscriptionStatus(userId: nil)
            await subscriptionStore.refreshProducts()
        }
        .onAppear {
            AnalyticsService.shared.track(
                .paywallShown,
                properties: [
                    AnalyticsService.Property.entrySurface: source.rawValue
                ]
            )
        }
        .onDisappear {
            if !purchaseSucceeded && !subscriptionStore.isPremium {
                GrowthOrchestrator.shared.registerPaywallDismissal(source: source)
            } else if purchaseSucceeded || subscriptionStore.isPremium {
                AnalyticsService.shared.track(
                    .paywallConverted,
                    properties: [
                        AnalyticsService.Property.entrySurface: source.rawValue
                    ]
                )
            }
        }
    }

    private var restorePurchasesButton: some View {
        Button {
            Task {
                await subscriptionStore.restorePurchases()
                if subscriptionStore.isPremium { dismiss() }
            }
        } label: {
            Text("Restore Purchases")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.sageGreen)
        }
        .disabled(subscriptionStore.isLoading)
        .padding(.top, Theme.Spacing.sm)
    }

    private func benefitRow(icon: String, text: String) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(Theme.sageGreen)
                .frame(width: 28)
            Text(text)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.deepPlum)
            Spacer()
        }
        .padding(.vertical, Theme.Spacing.sm)
        .padding(.horizontal, Theme.Spacing.md)
        .background(Theme.cardBackground.opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.small))
    }

    private var displayProducts: [Product] {
        let sorted = subscriptionStore.products.sorted {
            rank(for: $0.id) < rank(for: $1.id)
        }
        if GrowthOrchestrator.shared.paywallPresentationMode == .annualOnly {
            return sorted.filter { $0.id == SubscriptionStore.yearlyProductId }
        }
        return sorted
    }

    private func rank(for productId: String) -> Int {
        if productId == SubscriptionStore.yearlyProductId { return 0 }
        if productId == SubscriptionStore.monthlyProductId { return 1 }
        return 2
    }
}

#Preview {
    PaywallView()
}
