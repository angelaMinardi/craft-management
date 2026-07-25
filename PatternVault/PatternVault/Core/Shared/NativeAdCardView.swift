//
//  NativeAdCardView.swift
//  PatternVault
//
//  Native ad rendered as a card matching PatternCardView styling.
//  Inserted in the pattern list for free-tier users only.
//  Clearly labeled "Sponsored" to meet App Store + AdMob policy.
//

import SwiftUI
import UIKit
import GoogleMobileAds

struct NativeAdCardView: View {
    @ObservedObject private var adService = AdService.shared
    @ObservedObject private var subscriptionStore = SubscriptionStore.shared
    @StateObject private var loader = NativeAdLoader()

    var body: some View {
        Group {
            if !subscriptionStore.isPremium, adService.canShowAds, let ad = loader.loadedAd {
                NativeAdRepresentable(nativeAd: ad)
                    .frame(minHeight: 120, maxHeight: 180)
                    .background(Theme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                            .stroke(Theme.deepPlum.opacity(0.08), lineWidth: 1)
                    )
                    .overlay(alignment: .topLeading) {
                        Text("SPONSORED")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Theme.deepPlum.opacity(0.6))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Theme.warmCream)
                            .clipShape(Capsule())
                            .padding(8)
                    }
                    .accessibilityLabel("Sponsored ad")
            } else {
                EmptyView()
            }
        }
        .task {
            // Cold-start safety net: initialize the SDK here too, since the
            // MainTabView scenePhase .active handler only fires on transitions.
            if !subscriptionStore.isPremium {
                await adService.initialize()
            }
            if !subscriptionStore.isPremium, adService.canShowAds, loader.loadedAd == nil {
                loader.loadIfNeeded()
            }
        }
        .onChange(of: adService.canShowAds) { _, newValue in
            if newValue, loader.loadedAd == nil {
                loader.loadIfNeeded()
            }
        }
    }
}

private struct NativeAdRepresentable: UIViewRepresentable {
    let nativeAd: GADNativeAd

    func makeUIView(context: Context) -> GADNativeAdView {
        let view = GADNativeAdView()
        view.translatesAutoresizingMaskIntoConstraints = false

        let headline = UILabel()
        headline.font = .systemFont(ofSize: 15, weight: .semibold)
        headline.textColor = UIColor(Theme.deepPlum)
        headline.numberOfLines = 2
        headline.translatesAutoresizingMaskIntoConstraints = false
        view.headlineView = headline
        view.addSubview(headline)

        let body = UILabel()
        body.font = .systemFont(ofSize: 13)
        body.textColor = UIColor(Theme.deepPlum.opacity(0.75))
        body.numberOfLines = 2
        body.translatesAutoresizingMaskIntoConstraints = false
        view.bodyView = body
        view.addSubview(body)

        let cta = UIButton(type: .system)
        var ctaConfig = UIButton.Configuration.filled()
        ctaConfig.baseBackgroundColor = UIColor(Theme.sageGreen)
        ctaConfig.baseForegroundColor = .white
        ctaConfig.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
        ctaConfig.background.cornerRadius = 8
        ctaConfig.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
            return outgoing
        }
        cta.configuration = ctaConfig
        cta.translatesAutoresizingMaskIntoConstraints = false
        view.callToActionView = cta
        cta.isUserInteractionEnabled = false // NativeAdView handles taps
        view.addSubview(cta)

        NSLayoutConstraint.activate([
            headline.topAnchor.constraint(equalTo: view.topAnchor, constant: 34),
            headline.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            headline.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),

            body.topAnchor.constraint(equalTo: headline.bottomAnchor, constant: 6),
            body.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            body.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),

            cta.topAnchor.constraint(greaterThanOrEqualTo: body.bottomAnchor, constant: 8),
            cta.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            cta.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
            cta.heightAnchor.constraint(equalToConstant: 30)
        ])

        return view
    }

    func updateUIView(_ uiView: GADNativeAdView, context: Context) {
        uiView.nativeAd = nativeAd
        (uiView.headlineView as? UILabel)?.text = nativeAd.headline
        (uiView.bodyView as? UILabel)?.text = nativeAd.body
        if let button = uiView.callToActionView as? UIButton {
            button.configuration?.title = nativeAd.callToAction
        }
    }
}

// MARK: - Loader

@MainActor
final class NativeAdLoader: ObservableObject {
    @Published var loadedAd: GADNativeAd?
    private var adLoader: GADAdLoader?
    private lazy var delegate = Delegate(owner: self)

    func loadIfNeeded() {
        guard loadedAd == nil, adLoader == nil else { return }
        guard let root = Self.rootViewController() else { return }
        guard let adUnitId = AdService.nativeAdUnitId else { return }
        let loader = GADAdLoader(
            adUnitID: adUnitId,
            rootViewController: root,
            adTypes: [.native],
            options: nil
        )
        loader.delegate = delegate
        loader.load(GADRequest())
        adLoader = loader
    }

    private static func rootViewController() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })?
            .windows
            .first(where: \.isKeyWindow)?
            .rootViewController
    }

    private final class Delegate: NSObject, GADNativeAdLoaderDelegate {
        weak var owner: NativeAdLoader?
        init(owner: NativeAdLoader) { self.owner = owner }

        nonisolated func adLoader(_ adLoader: GADAdLoader, didReceive nativeAd: GADNativeAd) {
            Task { @MainActor in
                self.owner?.loadedAd = nativeAd
            }
        }

        nonisolated func adLoader(_ adLoader: GADAdLoader, didFailToReceiveAdWithError error: Error) {
            #if DEBUG
            print("[NativeAd] load failed: \(error.localizedDescription)")
            #endif
        }
    }
}
