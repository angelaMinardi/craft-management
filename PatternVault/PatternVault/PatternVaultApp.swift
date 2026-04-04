//
//  PatternVaultApp.swift
//  PatternVault
//
//  Pattern Vault — personal craft library (iOS).
//  Freemium: AdMob (banner for free users), optional Firebase (Analytics + Crashlytics) when GoogleService-Info.plist is present.
//

import SwiftUI
import GoogleMobileAds
import FirebaseCore
import FirebaseCrashlytics

@main
struct PatternVaultApp: App {
    init() {
        if Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
            FirebaseApp.configure()
        }
        if Self.hasValidAdMobAppId {
            DispatchQueue.main.async {
                GADMobileAds.sharedInstance().start(completionHandler: nil)
            }
        }
    }
    @StateObject private var auth = AuthService.shared
    @State private var sharedURL: String?
    @State private var savedPatternId: UUID?
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView(sharedURL: $sharedURL, savedPatternId: $savedPatternId)
                .environmentObject(auth)
                .onOpenURL { url in
                    if url.scheme == "patternvault", url.path.contains("ravelry") || url.host == "oauth" {
                        let defaults = UserDefaults(suiteName: "group.com.patternvault.app")
                        defaults?.set(url.absoluteString, forKey: "pendingRavelryCallbackURL")
                        defaults?.synchronize()
                        NotificationCenter.default.post(name: .ravelryOAuthCallback, object: url)
                    } else if (url.scheme == "patternvault" || url.scheme == "com.patternvault.app") && url.host == "pattern" {
                        let uuidString = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                        if let id = UUID(uuidString: uuidString) {
                            savedPatternId = id
                        }
                    } else if url.scheme == "com.patternvault.app" && url.host == "share" {
                        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                           let urlParam = components.queryItems?.first(where: { $0.name == "url" })?.value {
                            sharedURL = urlParam
                        }
                    } else {
                        Task { await auth.session(from: url) }
                    }
                }
                .onAppear { checkForSharedURL() }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        NotificationCenter.default.post(name: .patternListShouldRefresh, object: nil)
                        let defaults = UserDefaults(suiteName: "group.com.patternvault.app")
                        if let idString = defaults?.string(forKey: "savedPatternId"), let id = UUID(uuidString: idString) {
                            savedPatternId = id
                            defaults?.removeObject(forKey: "savedPatternId")
                            defaults?.removeObject(forKey: "savedPatternTitle")
                            defaults?.synchronize()
                        }
                    }
                }
        }
    }

    private func checkForSharedURL() {
        let defaults = UserDefaults(suiteName: "group.com.patternvault.app")
        if let url = defaults?.string(forKey: "sharedURL") {
            sharedURL = url
            defaults?.removeObject(forKey: "sharedURL")
            defaults?.removeObject(forKey: "sharedTitle")
            defaults?.synchronize()
        }
    }

    private static var hasValidAdMobAppId: Bool {
        let raw = Bundle.main.object(forInfoDictionaryKey: "GADApplicationIdentifier") as? String
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !trimmed.isEmpty && !trimmed.contains("$(")
    }
}

extension Notification.Name {
    static let patternListShouldRefresh = Notification.Name("patternListShouldRefresh")
    static let ravelryOAuthCallback = Notification.Name("ravelryOAuthCallback")
    static let processPendingRavelryCallback = Notification.Name("processPendingRavelryCallback")
}
