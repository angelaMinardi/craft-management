//
//  AdBannerView.swift
//  PatternVault
//
//  Shows a banner ad for free users only. Premium users never see ads.
//  Requires Google Mobile Ads SDK and GADApplicationIdentifier in Info.plist.
//

import SwiftUI
import GoogleMobileAds

/// Banner ad shown at bottom of main content when user is not Premium.
struct AdBannerView: View {
    /// Set from Info.plist GADBannerAdUnitID, or use test ID when nil.
    static var bannerAdUnitID: String? {
        Bundle.main.object(forInfoDictionaryKey: "GADBannerAdUnitID") as? String
    }
    /// Test banner unit ID (Google sample) when no plist value.
    private static let testBannerAdUnitID = "ca-app-pub-3940256099942544/2934735716"

    var body: some View {
        AdBannerRepresentable(adUnitID: Self.bannerAdUnitID ?? Self.testBannerAdUnitID)
            .frame(height: 50)
            .background(Color(.systemBackground))
    }
}

private struct AdBannerRepresentable: UIViewControllerRepresentable {
    let adUnitID: String

    func makeUIViewController(context: Context) -> UIViewController {
        let vc = UIViewController()
        vc.view.backgroundColor = .clear
        let banner = GADBannerView(adSize: GADAdSizeBanner)
        banner.adUnitID = adUnitID
        banner.rootViewController = vc
        banner.translatesAutoresizingMaskIntoConstraints = false
        vc.view.addSubview(banner)
        NSLayoutConstraint.activate([
            banner.centerXAnchor.constraint(equalTo: vc.view.centerXAnchor),
            banner.centerYAnchor.constraint(equalTo: vc.view.centerYAnchor),
        ])
        context.coordinator.banner = banner
        banner.load(GADRequest())
        return vc
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var banner: GADBannerView?
    }
}

#Preview {
    AdBannerView()
}
