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
                            Text("You're all set — Pip's delighted")
                                .font(Theme.Typography.title)
                                .foregroundStyle(Theme.deepPlum)
                        }
                        .padding(.top, Theme.Spacing.lg)
                        Text("Unlimited patterns, AI analyses, Ravelry library sync, voice row counter, Row Tracker widget, and no ads. Thanks for supporting Corvid Craft.")
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.deepPlum.opacity(0.8))
                        Spacer(minLength: 40)
                    } else {
                        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                            Text(headlineForSource(source))
                                .font(Theme.Typography.largeTitle)
                                .foregroundStyle(Theme.deepPlum)
                            Text(subheadlineForSource(source))
                                .font(Theme.Typography.body)
                                .foregroundStyle(Theme.deepPlum.opacity(0.8))
                        }
                        .padding(.top, Theme.Spacing.lg)

                        // Top 3 benefits reordered to lead with the Premium pillars (chart mode stays free).
                        benefitRow(icon: "wand.and.stars", text: "200 AI analyses per month")
                        benefitRow(icon: "arrow.triangle.2.circlepath", text: "Sync your entire Ravelry library")
                        benefitRow(icon: "gauge.with.dots.needle.33percent", text: "Row Tracker lock screen widget + Live Activity")
                        benefitRow(icon: "mic.fill", text: "Hands-free voice row counter")
                        benefitRow(icon: "square.stack.3d.up.fill", text: "Unlimited patterns & note photos")
                        benefitRow(icon: "hammer.fill", text: "Project mode & stash matching")
                        benefitRow(icon: "nosign", text: "No ads")
                        benefitRow(icon: "lock.shield.fill", text: "Your patterns stay yours — export anytime")

                        if let restoreMessage = subscriptionStore.restoreNoResultMessage {
                            Text(restoreMessage)
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.deepPlum.opacity(0.6))
                                .multilineTextAlignment(.center)
                                .padding(Theme.Spacing.sm)
                                .frame(maxWidth: .infinity)
                                .background(Theme.cardBackground.opacity(0.8))
                                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.small))
                        }

                        // `displayProducts` can be empty even when `subscriptionStore.products`
                        // has items (e.g. annualOnly mode leaves only yearly). Treat it the
                        // same as products-not-loaded so the user always gets a retry CTA
                        // instead of a silent dead end.
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
                                        productCard(for: product)
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

    /// Yearly (0) → Monthly (1). Matches the paywall emphasis.
    private func rank(for productId: String) -> Int {
        if productId == SubscriptionStore.yearlyProductId { return 0 }
        if productId == SubscriptionStore.monthlyProductId { return 1 }
        return 2
    }

    // MARK: - Source-specific copy

    /// Pip-led warm headline per paywall source. Limited to one mascot mention per screen.
    private func headlineForSource(_ source: GrowthOrchestrator.PaywallSource) -> String {
        switch source {
        case .patternLimit: return "Your vault's full"
        case .aiLimit: return "You've been busy this month"
        case .youtubeLimit: return "You're on a roll"
        case .notePhotoLimit: return "Run out of photo space"
        case .widgetSetup: return "Keep Pip on your lock screen"
        case .ravelryConnect: return "Bring your whole library"
        case .voiceRowCounter: return "Hands full?"
        case .settings, .dashboard, .unknown: return "Unlock Premium"
        }
    }

    private func subheadlineForSource(_ source: GrowthOrchestrator.PaywallSource) -> String {
        switch source {
        case .patternLimit:
            return "Upgrade to keep every pattern you love. \(Theme.Premium.tagline)"
        case .aiLimit:
            return "Keep Pip's help flowing with 200 AI analyses every month. \(Theme.Premium.tagline)"
        case .youtubeLimit:
            return "Import unlimited videos and more with Premium."
        case .notePhotoLimit:
            return "Add unlimited photos to your project notes."
        case .widgetSetup:
            return "Row Tracker Live Activity + lock screen widget are a Premium perk."
        case .ravelryConnect:
            return "Connect Ravelry and sync your full library in one tap."
        case .voiceRowCounter:
            return "Just tell Pip the row. Hands-free counting is Premium."
        case .settings, .dashboard, .unknown:
            return Theme.Premium.tagline
        }
    }

    // MARK: - Product card

    private func productCard(for product: Product) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Theme.Spacing.xs) {
                    Text(product.displayName)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.deepPlum)
                    if product.id == SubscriptionStore.yearlyProductId {
                        Text("BEST VALUE")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.sageGreen)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.sageGreen.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
                Text(descriptionForProduct(product))
                    .font(Theme.Typography.caption2)
                    .foregroundStyle(Theme.deepPlum.opacity(0.6))
                if let trialText = trialTextForProduct(product) {
                    Text(trialText)
                        .font(Theme.Typography.caption2)
                        .foregroundStyle(Theme.sageGreen)
                }
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
                .stroke(
                    product.id == SubscriptionStore.yearlyProductId
                        ? Theme.sageGreen.opacity(0.45)
                        : Theme.softCoral.opacity(0.3),
                    lineWidth: product.id == SubscriptionStore.yearlyProductId ? 2 : 1
                )
        )
    }

    /// Surface the active introductory offer on the card. Eligibility is checked
    /// up front against `SubscriptionStore.yearlyIntroEligible` so returning
    /// monthly-trialists don't see a "first year $X" line we can't actually honor.
    private func trialTextForProduct(_ product: Product) -> String? {
        guard let subscription = product.subscription,
              let intro = subscription.introductoryOffer else {
            return nil
        }
        // Today only yearly is gated by a stored eligibility flag; other products
        // would need their own equivalent before we surface intro copy.
        if product.id == SubscriptionStore.yearlyProductId, !subscriptionStore.yearlyIntroEligible {
            return nil
        }
        let label = periodLabel(subscription.subscriptionPeriod)
        if intro.paymentMode == .freeTrial {
            let days = daysInPeriod(intro.period)
            return "\(days)-day free trial, then \(product.displayPrice)/\(label)"
        }
        if intro.paymentMode == .payAsYouGo {
            let periods = intro.periodCount
            return "\(intro.displayPrice)/\(periodLabel(intro.period)) for \(periods) \(label), then \(product.displayPrice)/\(label)"
        }
        if intro.paymentMode == .payUpFront {
            return "\(intro.displayPrice) for the first \(label), then \(product.displayPrice)/\(label)"
        }
        return nil
    }

    private func descriptionForProduct(_ product: Product) -> String {
        product.description
    }

    private func daysInPeriod(_ period: Product.SubscriptionPeriod) -> Int {
        switch period.unit {
        case .day: return period.value
        case .week: return period.value * 7
        case .month: return period.value * 30
        case .year: return period.value * 365
        @unknown default: return period.value
        }
    }

    private func periodLabel(_ period: Product.SubscriptionPeriod) -> String {
        switch period.unit {
        case .day: return period.value == 1 ? "day" : "\(period.value) days"
        case .week: return period.value == 1 ? "week" : "\(period.value) weeks"
        case .month: return period.value == 1 ? "month" : "\(period.value) months"
        case .year: return period.value == 1 ? "year" : "\(period.value) years"
        @unknown default: return "period"
        }
    }

}

#Preview {
    PaywallView()
}
