//
//  SubscriptionStore.swift
//  PatternVault
//
//  Freemium: StoreKit 2 subscription status + Supabase usage. Exposes limits and syncs to App Group for Share Extension.
//

import Foundation
import StoreKit
import UIKit
import FirebaseAnalytics

/// Freemium limits (free tier) and premium soft caps.
enum EntitlementLimits {
    /// Free tier — patterns stored total.
    static let freePatternLimit = 25
    /// Free tier — AI uses per month (enrich + step-parse + chart-detect combined).
    static let freeAIPerMonth = 5
    /// Free tier — YouTube / TikTok video imports per month.
    static let freeYouTubePerMonth = 3
    /// Free tier — total note photos uploaded.
    static let freeNotePhotos = 20
    /// Premium — monthly AI soft cap to keep Gemini COGS bounded.
    /// Fair-use policy applies beyond this; users see a friendly notice, not a hard block.
    static let premiumAISoftCapPerMonth = 200
}

@MainActor
final class SubscriptionStore: ObservableObject {
    static let shared = SubscriptionStore()

    @Published private(set) var isPremium = false
    @Published private(set) var entitlement: UserEntitlement?
    @Published private(set) var products: [Product] = []
    @Published private(set) var productsLoading = false
    @Published private(set) var productsLoadError: String?
    @Published private(set) var productsDebugDetails: String?
    @Published private(set) var isLoading = false
    @Published private(set) var purchaseError: String?
    /// Per-subscription-group intro-offer eligibility. The Premium group shares
    /// monthly + yearly, so a returning monthly-trialist burns yearly's eligibility.
    /// Driving copy off this flag prevents "first year $X" lies for those users.
    @Published private(set) var yearlyIntroEligible = false
    /// One-shot info string surfaced when Restore Purchases returns no entitlements,
    /// so the user isn't left wondering whether anything happened.
    @Published var restoreNoResultMessage: String?

    private let entitlementRepo = EntitlementRepository()
    private static let appGroupId = "group.com.corvidcraft.app"
    private var transactionUpdatesTask: Task<Void, Never>?

    /// Product IDs — configure in App Store Connect to match.
    static let monthlyProductId = "com.corvidcraft.premium.monthly"
    static let yearlyProductId = "com.corvidcraft.premium.yearly"

    private init() {
        Task { await loadProducts() }
        Task { await updateSubscriptionStatus() }
        transactionUpdatesTask = Task { [weak self] in
            await self?.observeTransactionUpdates()
        }
    }

    // MARK: - Limits (call these to gate features)

    func canAddPattern(currentPatternCount: Int) -> Bool {
        if isPremium { return true }
        return currentPatternCount < EntitlementLimits.freePatternLimit
    }

    func canUseAI() -> Bool {
        // Bypass only in simulator DEBUG builds. Physical-device DEBUG builds
        // (which TestFlight testers can end up with) must still respect the cap.
        #if DEBUG && targetEnvironment(simulator)
        return true
        #else
        guard let e = entitlement else { return isPremium }
        if isPremium {
            return e.aiUsageThisMonth < EntitlementLimits.premiumAISoftCapPerMonth
        }
        return e.aiUsageThisMonth < EntitlementLimits.freeAIPerMonth
        #endif
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

    /// Premium AI uses remaining this month against the soft cap (nil if not premium).
    /// Surface only when <25 remain so casual premium users never see a counter.
    var premiumAIUsesRemaining: Int? {
        guard isPremium, let e = entitlement else { return nil }
        return max(0, EntitlementLimits.premiumAISoftCapPerMonth - e.aiUsageThisMonth)
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
            if case .verified(let transaction) = result {
                guard Self.premiumProductIds.contains(transaction.productID) else { continue }
                guard transaction.revocationDate == nil else { continue }
                if let expiration = transaction.expirationDate, expiration <= Date() {
                    continue
                }
                return true
            }
        }
        return false
    }

    private static let premiumProductIds: Set<String> = [
        monthlyProductId,
        yearlyProductId
    ]

    private func loadProducts() async {
        productsLoading = true
        productsLoadError = nil
        productsDebugDetails = nil
        defer { productsLoading = false }
        let requestedIds = [Self.monthlyProductId, Self.yearlyProductId]
        let bundleId = Bundle.main.bundleIdentifier ?? "unknown"
        var debugLines: [String] = []
        debugLines.append("bundle=\(bundleId)")
        debugLines.append("payments=\(AppStore.canMakePayments)")
        let schemeMarker = ProcessInfo.processInfo.environment["PV_SCHEME_MARKER"] ?? "missing"
        debugLines.append("schemeMarker=\(schemeMarker)")
        let args = ProcessInfo.processInfo.arguments
        if let markerIndex = args.firstIndex(of: "-PV_SCHEME_MARKER"), args.indices.contains(markerIndex + 1) {
            debugLines.append("argSchemeMarker=\(args[markerIndex + 1])")
        } else {
            debugLines.append("argSchemeMarker=missing")
        }
        let storekitArgs = args.filter { $0.localizedCaseInsensitiveContains("storekit") }
        debugLines.append("storekitArgs=\(storekitArgs.isEmpty ? "none" : storekitArgs.joined(separator: "|")))")
        let env = ProcessInfo.processInfo.environment
        let storekitEnvKeys = env.keys
            .filter { $0.localizedCaseInsensitiveContains("storekit") }
            .sorted()
        debugLines.append("storekitEnvKeys=\(storekitEnvKeys.isEmpty ? "none" : storekitEnvKeys.joined(separator: "|")))")
        debugLines.append("ids=\(requestedIds.joined(separator: ","))")

        do {
            // StoreKit can be briefly unavailable right after launch/installation.
            // Retry with short backoff before surfacing an empty-state failure.
            var fetched: [Product] = []
            let retryDelaysNs: [UInt64] = [
                0,
                400_000_000,
                800_000_000,
                1_200_000_000,
                1_600_000_000
            ]
            for (index, delay) in retryDelaysNs.enumerated() {
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: delay)
                }
                fetched = try await Product.products(for: requestedIds)
                debugLines.append("attempt\(index + 1)=count:\(fetched.count) ids:\(fetched.map(\.id).joined(separator: ","))")
                if !fetched.isEmpty { break }
            }

            products = fetched
            await refreshYearlyIntroEligibility()
            if fetched.isEmpty {
                debugLines.append("result=empty")
                productsDebugDetails = debugLines.joined(separator: "\n")
                #if DEBUG
                let debugSuffix = "\n\nDebug:\n\(productsDebugDetails ?? "")"
                #else
                let debugSuffix = ""
                #endif
                productsLoadError = """
                No subscription products were returned.
                Requested IDs: \(requestedIds.joined(separator: ", "))
                Bundle: \(bundleId)
                Verify StoreKit configuration is attached to this scheme Run action.
                If needed: Product > Scheme > Edit Scheme > Run > Options > StoreKit Configuration.
                \(debugSuffix)
                """
            } else {
                debugLines.append("result=success")
                productsDebugDetails = debugLines.joined(separator: "\n")
            }
        } catch {
            products = []
            debugLines.append("result=error")
            debugLines.append("error=\(error.localizedDescription)")
            productsDebugDetails = debugLines.joined(separator: "\n")
            #if DEBUG
            let debugSuffix = "\n\nDebug:\n\(productsDebugDetails ?? "")"
            #else
            let debugSuffix = ""
            #endif
            productsLoadError = """
            \(error.localizedDescription)
            Requested IDs: \(requestedIds.joined(separator: ", "))
            Bundle: \(bundleId)
            \(debugSuffix)
            """
        }
    }

    /// Call from PaywallView to load or retry loading products.
    func refreshProducts() async {
        await loadProducts()
    }

    /// Asks StoreKit whether the user is eligible for the yearly product's intro
    /// offer. Eligibility is per `subscriptionGroupID`, so trying the monthly
    /// trial burns yearly's intro eligibility (both share group `297B9B5E`).
    /// The result drives whether we show "first year $X" copy.
    private func refreshYearlyIntroEligibility() async {
        guard let yearly = products.first(where: { $0.id == Self.yearlyProductId }),
              let subscription = yearly.subscription else {
            yearlyIntroEligible = false
            return
        }
        if subscription.introductoryOffer == nil {
            yearlyIntroEligible = false
            return
        }
        yearlyIntroEligible = await subscription.isEligibleForIntroOffer
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
                case .verified(let transaction):
                    applyVerifiedTransaction(transaction)
                    await transaction.finish()
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
        restoreNoResultMessage = nil
        defer { isLoading = false }
        do {
            try await AppStore.sync()
            await updateSubscriptionStatus()
            if !isPremium {
                // Sync succeeded but the Apple ID has no active entitlement.
                // Tell the user so they aren't left wondering.
                restoreNoResultMessage = "No active subscriptions found on this Apple ID."
            }
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    private func observeTransactionUpdates() async {
        for await result in Transaction.updates {
            guard case .verified(let transaction) = result else { continue }
            applyVerifiedTransaction(transaction)
            await transaction.finish()
            await updateSubscriptionStatus()
        }
    }

    /// Apply known entitlement changes immediately, then reconcile with StoreKit.
    /// This avoids UI lag where currentEntitlements can take a moment to reflect
    /// a just-completed local StoreKit transaction.
    private func applyVerifiedTransaction(_ transaction: Transaction) {
        guard Self.premiumProductIds.contains(transaction.productID) else { return }
        guard transaction.revocationDate == nil else { return }
        if let expiration = transaction.expirationDate, expiration <= Date() {
            return
        }
        isPremium = true
        syncToAppGroup(entitlement: entitlement, isPremium: true)
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

@MainActor
final class GrowthOrchestrator {
    static let shared = GrowthOrchestrator()

    // Core pod contract: emit positive-moment events from UX milestones.
    // Growth pod consumes these signals to tune review/paywall timing externally.
    enum PositiveEvent: String {
        case onboardingComplete
        case firstSave
        case firstImport
        case progressLogged
        case patternCompleted
        case milestoneCelebration
    }

    enum FrictionEvent: String {
        case authFailure
        case networkRetryError
        case importOrParsingFailure
        case purchaseFailure
        case purchaseCancelled
        case recentPaywallDismissal
        case interruptionHeavyFlow
    }

    enum PaywallPresentationMode: String {
        case annualOnly
        case annualPlusMonthly
    }

    // Core pod owns placement-level paywall context only.
    // Offer strategy, frequency tuning, and fallback incentives belong to Growth pod.
    enum PaywallSource: String {
        case settings
        case aiLimit
        case patternLimit
        case youtubeLimit
        case notePhotoLimit
        case dashboard
        /// User tapped Row Tracker widget setup.
        case widgetSetup
        /// User tapped "Connect Ravelry" in Settings.
        case ravelryConnect
        /// User tapped the microphone on the row counter.
        case voiceRowCounter
        case unknown
    }

    enum SuppressionReason: String {
        case onboardingIncomplete
        case noPositiveEvent
        case recentFriction
        case reviewCooldown
        case reviewAlreadyShownToday
        case reviewAlreadyShownThisVersion
        case paywallRecentFriction
        case paywallDailyCap
        case paywallVersionCap
    }

    private struct Keys {
        static let hasSeenOnboarding = "hasSeenOnboarding"
        static let installDate = "Growth.installDate"
        static let lastPositiveEventDate = "Growth.lastPositiveEventDate"
        static let lastFrictionEventDate = "Growth.lastFrictionEventDate"
        static let lastReviewAskDate = "Growth.lastReviewAskDate"
        static let lastReviewAskedVersion = "Growth.lastReviewAskedVersion"
        static let reviewAsksTodayCount = "Growth.reviewAsksTodayCount"
        static let reviewAsksTodayDate = "Growth.reviewAsksTodayDate"
        static let paywallDismissesTodayCount = "Growth.paywallDismissesTodayCount"
        static let paywallDismissesTodayDate = "Growth.paywallDismissesTodayDate"
        static let paywallDismissesThisVersionCount = "Growth.paywallDismissesThisVersionCount"
        static let paywallDismissesVersion = "Growth.paywallDismissesVersion"
        static let paywallPresentationMode = "Growth.paywallPresentationMode"
    }

    private let defaults: UserDefaults
    private let calendar = Calendar.current

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.object(forKey: Keys.installDate) == nil {
            defaults.set(Date(), forKey: Keys.installDate)
        }
        resetDailyCountersIfNeeded()
        resetVersionCountersIfNeeded()
    }

    var paywallPresentationMode: PaywallPresentationMode {
        let raw = defaults.string(forKey: Keys.paywallPresentationMode) ?? PaywallPresentationMode.annualPlusMonthly.rawValue
        return PaywallPresentationMode(rawValue: raw) ?? .annualPlusMonthly
    }

    func markOnboardingCompleted() {
        defaults.set(true, forKey: Keys.hasSeenOnboarding)
        AnalyticsService.shared.track(
            .onboardingCompleted,
            properties: [:]
        )
    }

    func registerPositiveEvent(_ event: PositiveEvent) {
        defaults.set(Date(), forKey: Keys.lastPositiveEventDate)
        AnalyticsService.shared.track(
            .growthPositiveEvent,
            properties: [
                AnalyticsService.Property.eventName: event.rawValue
            ]
        )
    }

    func registerFrictionEvent(_ event: FrictionEvent) {
        defaults.set(Date(), forKey: Keys.lastFrictionEventDate)
        AnalyticsService.shared.track(
            .growthFrictionEvent,
            properties: [
                AnalyticsService.Property.eventName: event.rawValue
            ]
        )
    }

    func registerPaywallDismissal(source: PaywallSource) {
        resetDailyCountersIfNeeded()
        resetVersionCountersIfNeeded()
        defaults.set((defaults.integer(forKey: Keys.paywallDismissesTodayCount) + 1), forKey: Keys.paywallDismissesTodayCount)
        defaults.set((defaults.integer(forKey: Keys.paywallDismissesThisVersionCount) + 1), forKey: Keys.paywallDismissesThisVersionCount)
        registerFrictionEvent(.recentPaywallDismissal)
        AnalyticsService.shared.track(
            .paywallDismissed,
            properties: [
                AnalyticsService.Property.entrySurface: source.rawValue
            ]
        )
    }

    func canShowPaywall(source: PaywallSource) -> Bool {
        if let reason = paywallSuppressionReason(source: source) {
            AnalyticsService.shared.track(
                .paywallSuppressed,
                properties: [
                    AnalyticsService.Property.entrySurface: source.rawValue,
                    AnalyticsService.Property.suppressedReason: reason.rawValue
                ]
            )
            return false
        }
        return true
    }

    func paywallSuppressionReason(source: PaywallSource) -> SuppressionReason? {
        _ = source
        resetDailyCountersIfNeeded()
        resetVersionCountersIfNeeded()
        if recentlyHadFriction(withinHours: 2) {
            return .paywallRecentFriction
        }
        if defaults.integer(forKey: Keys.paywallDismissesTodayCount) >= 2 {
            return .paywallDailyCap
        }
        if defaults.integer(forKey: Keys.paywallDismissesThisVersionCount) >= 6 {
            return .paywallVersionCap
        }
        return nil
    }

    func requestReviewIfEligible() {
        if let reason = reviewSuppressionReason() {
            AnalyticsService.shared.track(
                .reviewSuppressed,
                properties: [
                    AnalyticsService.Property.suppressedReason: reason.rawValue
                ]
            )
            return
        }
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else {
            return
        }
        SKStoreReviewController.requestReview(in: scene)
        defaults.set(Date(), forKey: Keys.lastReviewAskDate)
        defaults.set(currentVersion(), forKey: Keys.lastReviewAskedVersion)
        defaults.set(defaults.integer(forKey: Keys.reviewAsksTodayCount) + 1, forKey: Keys.reviewAsksTodayCount)
        AnalyticsService.shared.track(.reviewShown, properties: [:])
    }

    private func reviewSuppressionReason() -> SuppressionReason? {
        resetDailyCountersIfNeeded()
        guard defaults.bool(forKey: Keys.hasSeenOnboarding) else { return .onboardingIncomplete }
        guard defaults.object(forKey: Keys.lastPositiveEventDate) != nil else { return .noPositiveEvent }
        guard !recentlyHadFriction(withinHours: 48) else { return .recentFriction }
        if let lastAsk = defaults.object(forKey: Keys.lastReviewAskDate) as? Date {
            if let minDate = calendar.date(byAdding: .day, value: 120, to: lastAsk), Date() < minDate {
                return .reviewCooldown
            }
        }
        if defaults.integer(forKey: Keys.reviewAsksTodayCount) >= 1 {
            return .reviewAlreadyShownToday
        }
        let version = currentVersion()
        if defaults.string(forKey: Keys.lastReviewAskedVersion) == version {
            return .reviewAlreadyShownThisVersion
        }
        return nil
    }

    private func recentlyHadFriction(withinHours hours: Int) -> Bool {
        guard let date = defaults.object(forKey: Keys.lastFrictionEventDate) as? Date else { return false }
        guard let threshold = calendar.date(byAdding: .hour, value: -hours, to: Date()) else { return false }
        return date >= threshold
    }

    private func resetDailyCountersIfNeeded() {
        let dayKey = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none)
        let reviewDay = defaults.string(forKey: Keys.reviewAsksTodayDate)
        if reviewDay != dayKey {
            defaults.set(dayKey, forKey: Keys.reviewAsksTodayDate)
            defaults.set(0, forKey: Keys.reviewAsksTodayCount)
        }
        let paywallDay = defaults.string(forKey: Keys.paywallDismissesTodayDate)
        if paywallDay != dayKey {
            defaults.set(dayKey, forKey: Keys.paywallDismissesTodayDate)
            defaults.set(0, forKey: Keys.paywallDismissesTodayCount)
        }
    }

    private func resetVersionCountersIfNeeded() {
        let version = currentVersion()
        if defaults.string(forKey: Keys.paywallDismissesVersion) != version {
            defaults.set(version, forKey: Keys.paywallDismissesVersion)
            defaults.set(0, forKey: Keys.paywallDismissesThisVersionCount)
        }
    }

    private func currentVersion() -> String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }
}

@MainActor
final class AnalyticsService {
    static let shared = AnalyticsService()

    enum Event: String {
        case onboardingCompleted = "onboarding_completed"
        case onboardingSlideViewed = "onboarding_slide_viewed"
        case onboardingSkipped = "onboarding_skipped"
        case growthPositiveEvent = "growth_positive_event"
        case growthFrictionEvent = "growth_friction_event"
        case reviewShown = "review_shown"
        case reviewSuppressed = "review_suppressed"
        case paywallShown = "paywall_shown"
        case paywallDismissed = "paywall_dismissed"
        case paywallConverted = "paywall_converted"
        case paywallSuppressed = "paywall_suppressed"
        case tutorialStarted = "tutorial_started"
        case tutorialStepViewed = "tutorial_step_viewed"
        case tutorialSkipped = "tutorial_skipped"
        case tutorialCompleted = "tutorial_completed"
        /// User redeemed a promo code from Settings.
        case offerCodeRedeemed = "offer_code_redeemed"
    }

    enum Property {
        static let eventName = "event_name"
        static let entrySurface = "entry_surface"
        static let suppressedReason = "suppressed_reason"
        static let stepId = "step_id"
        static let stepIndex = "step_index"
        static let isLastStep = "is_last_step"
        static let appVersion = "app_version"
    }

    private init() {}

    func track(_ event: Event, properties: [String: String]) {
        var payload = properties
        payload[Property.appVersion] = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        Analytics.logEvent(event.rawValue, parameters: payload)
    }
}
