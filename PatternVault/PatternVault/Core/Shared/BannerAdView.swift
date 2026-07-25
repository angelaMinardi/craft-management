//
//  BannerAdView.swift
//  PatternVault
//
//  SwiftUI wrapper around the Google Mobile Ads banner view.
//  Renders nothing when the user is Premium, ads are disabled remotely, or
//  the SDK isn't initialized yet.
//

import SwiftUI
import UIKit
import GoogleMobileAds

/// A 320×50 banner ad. Silently collapses when it shouldn't show.
struct BannerAdView: View {
    @ObservedObject private var adService = AdService.shared
    @ObservedObject private var subscriptionStore = SubscriptionStore.shared

    var body: some View {
        Group {
            if shouldShow {
                AdBannerRepresentable()
                    .frame(height: 50)
                    .accessibilityLabel("Sponsored")
            } else {
                EmptyView()
            }
        }
        .task {
            // Safety net: ensure the SDK is initialized even on cold start when
            // MainTabView's scenePhase .active transition hasn't fired yet. The
            // AdService init is idempotent.
            if !subscriptionStore.isPremium {
                await adService.initialize()
            }
        }
    }

    private var shouldShow: Bool {
        !subscriptionStore.isPremium && adService.canShowAds
    }
}

private struct AdBannerRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> GADBannerView {
        let banner = GADBannerView(adSize: GADAdSizeBanner)
        if let adUnitId = AdService.bannerAdUnitId {
            banner.adUnitID = adUnitId
        }
        banner.rootViewController = Self.rootViewController()
        if banner.adUnitID != nil {
            banner.load(GADRequest())
        }
        return banner
    }

    func updateUIView(_ uiView: GADBannerView, context: Context) {
        if uiView.rootViewController == nil {
            uiView.rootViewController = Self.rootViewController()
        }
    }

    private static func rootViewController() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })?
            .windows
            .first(where: \.isKeyWindow)?
            .rootViewController
    }
}
