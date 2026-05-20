//
//  AdService.swift
//  PatternVault
//
//  Wraps Google Mobile Ads SDK v11.x for Corvid Craft's free-tier ads.
//  Respects the Premium entitlement + a remote kill switch via app_config.ads_enabled.
//

import Foundation
import SwiftUI
import UIKit
import GoogleMobileAds
import UserMessagingPlatform
#if canImport(AppTrackingTransparency)
import AppTrackingTransparency
#endif

@MainActor
final class AdService: ObservableObject {
    static let shared = AdService()

    /// Published because consent / ATT status can change at runtime and
    /// we want the ad surfaces to re-render when they do.
    @Published private(set) var canShowAds: Bool = false
    @Published private(set) var sdkInitialized: Bool = false
    /// True when the UMP consent request itself failed (usually because the
    /// AdMob account hasn't published consent forms yet). Distinct from
    /// `consentStatus == .required`: here we *tried* to fetch and hit a
    /// config error. We fall through and serve non-personalized ads so a
    /// half-configured AdMob account doesn't block the whole monetization line.
    @Published private(set) var consentRequestFailed: Bool = false

    // MARK: - Ad Unit IDs
    // Google's official TEST IDs. Replace with real AdMob IDs before production release.
    // Docs: https://developers.google.com/admob/ios/test-ads
    static let bannerAdUnitId = "ca-app-pub-3940256099942544/2934735716"
    static let nativeAdUnitId = "ca-app-pub-3940256099942544/3986624511"

    private init() {}

    /// Initializes the Google Mobile Ads SDK and requests consent. Idempotent.
    func initialize() async {
        guard !sdkInitialized else {
            recomputeCanShowAds()
            return
        }
        await requestConsentIfNeeded()

        // Start the SDK whenever consent is satisfied OR the UMP fetch itself
        // errored (AdMob account missing published consent forms). Real users
        // in the EEA will still be shown a form once it's configured.
        if consentStatusAllowsAds || consentRequestFailed {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                GADMobileAds.sharedInstance().start { _ in
                    continuation.resume()
                }
            }
            sdkInitialized = true
            recomputeCanShowAds()
        }
    }

    /// Called from views after Premium status or remote flag changes.
    func recomputeCanShowAds() {
        let isPremium = SubscriptionStore.shared.isPremium
        let remoteEnabled = AdsKillSwitchService.isAdsEnabled
        let hasConsent = consentStatusAllowsAds || consentRequestFailed
        canShowAds = sdkInitialized && !isPremium && remoteEnabled && hasConsent
        #if DEBUG
        print("[AdService] canShowAds=\(canShowAds) sdkInitialized=\(sdkInitialized) isPremium=\(isPremium) remoteEnabled=\(remoteEnabled) hasConsent=\(hasConsent) consentStatus=\(UMPConsentInformation.sharedInstance.consentStatus.rawValue) consentFailed=\(consentRequestFailed)")
        #endif
    }

    // MARK: - ATT (App Tracking Transparency)

    func requestTrackingAuthorizationIfNeeded() async {
        #if canImport(AppTrackingTransparency)
        guard ATTrackingManager.trackingAuthorizationStatus == .notDetermined else { return }
        _ = await ATTrackingManager.requestTrackingAuthorization()
        recomputeCanShowAds()
        #endif
    }

    // MARK: - UMP consent

    private var consentStatusAllowsAds: Bool {
        let status = UMPConsentInformation.sharedInstance.consentStatus
        return status == .notRequired || status == .obtained
    }

    private func requestConsentIfNeeded() async {
        let parameters = UMPRequestParameters()
        // Note: in DEBUG we previously forced .EEA geography to test the consent
        // flow, but that blocks ads from loading unless the form is actively
        // presented and consented to. Leave at the natural (US = .notRequired)
        // state so ads serve normally in development. Re-enable .EEA locally if
        // you specifically need to test the European consent UX.

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            UMPConsentInformation.sharedInstance.requestConsentInfoUpdate(with: parameters) { [weak self] error in
                if let error {
                    #if DEBUG
                    print("[AdService] Consent info update failed: \(error.localizedDescription)")
                    #endif
                    Task { @MainActor in
                        self?.consentRequestFailed = true
                    }
                    continuation.resume()
                    return
                }
                Task { @MainActor in
                    self?.consentRequestFailed = false
                    await Self.loadAndPresentConsentFormIfNeeded()
                    continuation.resume()
                }
            }
        }
    }

    @MainActor
    private static func loadAndPresentConsentFormIfNeeded() async {
        guard UMPConsentInformation.sharedInstance.formStatus == .available else { return }
        let status = UMPConsentInformation.sharedInstance.consentStatus
        guard status == .required else { return }
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let root = scene.keyWindow?.rootViewController else {
            return
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            UMPConsentForm.loadAndPresentIfRequired(from: root) { _ in
                continuation.resume()
            }
        }
    }
}

// MARK: - Ads Kill Switch (mirrors AIKillSwitchService)

enum AdsKillSwitchService {
    private static let appGroupId = "group.com.corvidcraft.app"
    private static let cacheKeyEnabled = "app_config_ads_enabled"
    private static let cacheKeyUpdated = "app_config_ads_enabled_updated"
    private static let cacheTTL: TimeInterval = 10 * 60

    private static let lock = NSLock()
    private static var inMemoryEnabled: Bool?
    private static var inMemoryUpdated: Date?

    /// Default true if never fetched — fail open so the business isn't
    /// silently broken when Supabase is unreachable.
    static var isAdsEnabled: Bool {
        lock.withLock {
            if let value = inMemoryEnabled,
               let updated = inMemoryUpdated,
               Date().timeIntervalSince(updated) < cacheTTL {
                return value
            }
            let defaults = UserDefaults(suiteName: appGroupId)
            if let updated = defaults?.object(forKey: cacheKeyUpdated) as? Date,
               Date().timeIntervalSince(updated) < cacheTTL,
               defaults?.object(forKey: cacheKeyEnabled) != nil {
                let value = defaults?.bool(forKey: cacheKeyEnabled) ?? true
                inMemoryEnabled = value
                inMemoryUpdated = updated
                return value
            }
            return true
        }
    }

    @MainActor
    static func refresh() async {
        struct AdsConfigRow: Decodable {
            let adsEnabled: Bool
            enum CodingKeys: String, CodingKey {
                case adsEnabled = "ads_enabled"
            }
        }
        do {
            let rows: [AdsConfigRow] = try await SupabaseManager.client
                .from("app_config")
                .select("ads_enabled")
                .eq("id", value: 1)
                .execute()
                .value
            let enabled = rows.first?.adsEnabled ?? true
            lock.withLock {
                inMemoryEnabled = enabled
                inMemoryUpdated = Date()
            }
            let defaults = UserDefaults(suiteName: appGroupId)
            defaults?.set(enabled, forKey: cacheKeyEnabled)
            defaults?.set(Date(), forKey: cacheKeyUpdated)
            defaults?.synchronize()
            AdService.shared.recomputeCanShowAds()
        } catch {
            #if DEBUG
            print("[AdsKillSwitch] Refresh failed: \(error); leaving cache as-is")
            #endif
        }
    }
}

private extension UIWindowScene {
    var keyWindow: UIWindow? {
        windows.first(where: \.isKeyWindow) ?? windows.first
    }
}
