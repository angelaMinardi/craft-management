//
//  PatternVaultApp.swift
//  PatternVault
//
//  Pattern Vault — personal craft library (iOS)
//

import SwiftUI

@main
struct PatternVaultApp: App {
    @StateObject private var auth = AuthService.shared
    @State private var sharedURL: String?
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView(sharedURL: $sharedURL)
                .environmentObject(auth)
                .onOpenURL { url in
                    if url.scheme == "com.patternvault.app" && url.host == "share" {
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
                        // Post notification so PatternListView can refresh
                        // (picks up patterns saved by the share extension)
                        NotificationCenter.default.post(name: .patternListShouldRefresh, object: nil)
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
}

extension Notification.Name {
    static let patternListShouldRefresh = Notification.Name("patternListShouldRefresh")
}
