//
//  SourcePlatformHelper.swift
//  PatternVault
//

import Foundation

enum SourcePlatformHelper {
    static func platform(for urlString: String) -> String? {
        guard let url = URL(string: urlString),
              let host = url.host?.lowercased() else { return nil }
        if host.contains("ravelry") { return "Ravelry" }
        if host.contains("etsy.com") { return "Etsy" }
        if host.contains("tiktok.com") { return "TikTok" }
        if host.contains("youtube.com") || host.contains("youtu.be") { return "YouTube" }
        if host.contains("pinterest") { return "Pinterest" }
        if host.contains("instagram") { return "Instagram" }
        return "Web"
    }
}
