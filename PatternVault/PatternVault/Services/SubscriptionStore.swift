//
//  SubscriptionStore.swift
//  PatternVault
//
//  Freemium: StoreKit 2 subscription status + Supabase usage. Exposes limits and syncs to App Group for Share Extension.
//

import Foundation
import StoreKit

/// Freemium limits (free tier).
enum EntitlementLimits {
    static let freePatternLimit = 30
    static let freeAIPerMonth = 5
    static let freeYouTubePerMonth = 3
    static let freeNotePhotos = 20
}

@MainActor
final class SubscriptionStore: ObservableObject {
    static let shared = SubscriptionStore()

    @Published private(set) var isPremium = false
    @Published private(set) var entitlement: UserEntitlement?
    @Published private(set) var products: [Product] = []
    @Published private(set) var productsLoading = false
    @Published private(set) var productsLoadError: String?
    @Published private(set) var isLoading = false
    @Published private(set) var purchaseError: String?

    private let entitlementRepo = EntitlementRepository()
    private static let appGroupId = "group.com.patternvault.app"

    /// Product IDs — configure in App Store Connect to match.
    static let monthlyProductId = "com.patternvault.premium.monthly"
    static let yearlyProductId = "com.patternvault.premium.yearly"

    private init() {
        Task { await loadProducts() }
        Task { await updateSubscriptionStatus() }
    }

    // MARK: - Limits (call these to gate features)

    func canAddPattern(currentPatternCount: Int) -> Bool {
        if isPremium { return true }
        return currentPatternCount < EntitlementLimits.freePatternLimit
    }

    func canUseAI() -> Bool {
        if isPremium { return true }
        guard let e = entitlement else { return false }
        return e.aiUsageThisMonth < EntitlementLimits.freeAIPerMonth
    }

    func canImportYouTube() -> Bool {
        if isPremium { return true }
        guard let e = entitlement else { return false }
        return e.youtubeImportsThisMonth < EntitlementLimits.freeYouTubePerMonth
    }

    func canAddNotePhoto(currentNotePhotoCount: Int) -> Bool {
        if isPremium { return true }
        return currentNotePhotoCount < EntitlementLimits.freeNotePhotos
    }

    /// Free-tier pattern limit (for UI: "X / 30 patterns").
    var patternLimit: Int { EntitlementLimits.freePatternLimit }
    /// Free-tier AI uses remaining this month (nil if premium).
    var aiUsesRemaining: Int? {
        guard !isPremium, let e = entitlement else { return nil }
        return max(0, EntitlementLimits.freeAIPerMonth - e.aiUsageThisMonth)
    }
    /// Free-tier YouTube imports remaining this month (nil if premium).
    var youtubeImportsRemaining: Int? {
        guard !isPremium, let e = entitlement else { return nil }
        return max(0, EntitlementLimits.freeYouTubePerMonth - e.youtubeImportsThisMonth)
    }

    // MARK: - Load usage from Supabase (call when user is logged in)

    func refreshUsage(userId: UUID) async {
        do {
            let usage = try await entitlementRepo.getOrCreateUsage(userId: userId)
            entitlement = usage
            syncToAppGroup(entitlement: usage, isPremium: isPremium)
        } catch {
            entitlement = nil
        }
    }

    /// Call after a successful AI use (Share Extension or main app). Returns true if increment succeeded.
    func recordAIUse(userId: UUID) async -> Bool {
        do {
            if let _ = try await entitlementRepo.incrementAIUsage(userId: userId) {
                await refreshUsage(userId: userId)
                return true
            }
            return false
        } catch {
            return false
        }
    }

    /// Call after a successful YouTube import (Edge Function or app). Returns true if increment succeeded.
    func recordYouTubeImport(userId: UUID) async -> Bool {
        do {
            if let _ = try await entitlementRepo.incrementYouTubeImports(userId: userId) {
                await refreshUsage(userId: userId)
                return true
            }
            return false
        } catch {
            return false
        }
    }

    /// Sync subscription status from StoreKit and write is_premium to Supabase when userId is available.
    func updateSubscriptionStatus(userId: UUID? = nil) async {
        let hasEntitlement = await checkCurrentEntitlements()
        isPremium = hasEntitlement
        if let uid = userId {
            do {
                try await entitlementRepo.setPremium(userId: uid, isPremium: hasEntitlement)
            } catch { }
            if let e = entitlement {
                syncToAppGroup(entitlement: e, isPremium: isPremium)
            }
        } else {
            syncToAppGroup(entitlement: entitlement, isPremium: isPremium)
        }
    }

    private func checkCurrentEntitlements() async -> Bool {
        for await result in Transaction.currentEntitlements {
            if case .verified(_) = result {
                return true
            }
        }
        return false
    }

    private func loadProducts() async {
        productsLoading = true
        productsLoadError = nil
        defer { productsLoading = false }
        do {
            products = try await Product.products(for: [Self.monthlyProductId, Self.yearlyProductId])
        } catch {
            products = []
            productsLoadError = error.localizedDescription
        }
    }

    /// Call from PaywallView to load or retry loading products.
    func refreshProducts() async {
        await loadProducts()
    }

    func purchase(_ product: Product) async -> Bool {
        isLoading = true
        purchaseError = nil
        defer { isLoading = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(_):
                    await updateSubscriptionStatus()
                    return true
                case .unverified(_, _):
                    purchaseError = "Purchase could not be verified."
                    return false
                }
            case .userCancelled:
                return false
            case .pending:
                purchaseError = "Purchase is pending approval."
                return false
            @unknown default:
                return false
            }
        } catch {
            purchaseError = error.localizedDescription
            return false
        }
    }

    func restorePurchases() async {
        isLoading = true
        purchaseError = nil
        defer { isLoading = false }
        do {
            try await AppStore.sync()
            await updateSubscriptionStatus()
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    private func syncToAppGroup(entitlement: UserEntitlement?, isPremium: Bool) {
        let defaults = UserDefaults(suiteName: Self.appGroupId)
        defaults?.set(isPremium, forKey: "entitlement_is_premium")
        defaults?.set(entitlement?.aiUsageThisMonth ?? 0, forKey: "entitlement_ai_usage_this_month")
        defaults?.set(entitlement?.youtubeImportsThisMonth ?? 0, forKey: "entitlement_youtube_imports_this_month")
        defaults?.set(entitlement?.usageMonth ?? "", forKey: "entitlement_usage_month")
        defaults?.synchronize()
    }

    /// Share Extension: read cached entitlement from App Group (no network).
    static func cachedCanUseAI() -> Bool {
        let defaults = UserDefaults(suiteName: appGroupId)
        let isPremium = defaults?.bool(forKey: "entitlement_is_premium") ?? false
        if isPremium { return true }
        let used = defaults?.integer(forKey: "entitlement_ai_usage_this_month") ?? 0
        let month = defaults?.string(forKey: "entitlement_usage_month") ?? ""
        let currentMonth = monthForNow()
        if month != currentMonth { return true }
        return used < EntitlementLimits.freeAIPerMonth
    }

    /// Pass explicit count when available; otherwise reads from App Group (main app writes when loading patterns).
    static func cachedCanAddPattern(patternCount: Int? = nil) -> Bool {
        let defaults = UserDefaults(suiteName: appGroupId)
        if defaults?.bool(forKey: "entitlement_is_premium") == true { return true }
        let count = patternCount ?? defaults?.integer(forKey: "entitlement_pattern_count") ?? 0
        return count < EntitlementLimits.freePatternLimit
    }

    /// Main app should call this when pattern list is loaded so Share Extension can enforce cap.
    static func syncPatternCountToAppGroup(_ count: Int) {
        UserDefaults(suiteName: appGroupId)?.set(count, forKey: "entitlement_pattern_count")
        UserDefaults(suiteName: appGroupId)?.synchronize()
    }

    private static func monthForNow() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: Date())
    }
}
