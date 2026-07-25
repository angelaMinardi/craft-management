//
//  InAppWebView.swift
//  PatternVault
//
//  External pattern/source pages are shown in SFSafariViewController rather than a
//  bare WKWebView. SFSafariViewController runs out-of-process — it has no access to
//  the app's cookies, local storage, or Keychain — always shows the real URL
//  (anti-phishing), and provides Done / Share / Open-in-Safari chrome itself, so no
//  custom navigation wrapper is needed. See AUDIT.md P1-2.
//

import SwiftUI
import SafariServices

struct SafariView: UIViewControllerRepresentable {
    let url: URL

    /// SFSafariViewController only supports http/https. Guard before presenting it;
    /// any other scheme (or a malformed URL) should fall back to a plain message.
    static func canOpen(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        let controller = SFSafariViewController(url: url, configuration: config)
        controller.dismissButtonStyle = .done
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
