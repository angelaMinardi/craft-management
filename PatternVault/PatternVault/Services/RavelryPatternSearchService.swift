//
//  RavelryPatternSearchService.swift
//  PatternVault
//
//  Searches Ravelry's pattern API by materials (yarn weight, needle/hook size, craft)
//  and optional "free only". Uses same Basic auth as MetadataService.
//

import Foundation

struct RavelrySearchCriteria: Sendable {
    var query: String
    var yarnWeight: String?
    var needleSize: String?
    var craft: String?
    var freeOnly: Bool
}

@MainActor
enum RavelryPatternSearchService {

    /// Returns whether Ravelry API credentials are configured (search can run).
    static var isConfigured: Bool {
        ravelryCredentials() != nil
    }

    /// Search Ravelry patterns with the given criteria. Returns discovery results or nil if not configured / request failed.
    static func search(criteria: RavelrySearchCriteria) async -> [PatternDiscoveryResult]? {
        guard let creds = ravelryCredentials() else { return nil }

        var components = URLComponents(string: "https://api.ravelry.com/patterns/search.json")!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "query", value: criteria.query.isEmpty ? "pattern" : criteria.query),
            URLQueryItem(name: "page_size", value: "24"),
            URLQueryItem(name: "page", value: "1")
        ]
        if criteria.freeOnly {
            queryItems.append(URLQueryItem(name: "availability", value: "free"))
        }
        if let w = criteria.yarnWeight, !w.isEmpty {
            queryItems.append(URLQueryItem(name: "weight", value: w))
        }
        if let n = criteria.needleSize, !n.isEmpty {
            queryItems.append(URLQueryItem(name: "needle_size", value: n))
        }
        if let c = criteria.craft, !c.isEmpty {
            queryItems.append(URLQueryItem(name: "craft", value: c))
        }
        components.queryItems = queryItems

        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        let authString = "\(creds.accessKey):\(creds.personalKey)"
        if let authData = authString.data(using: .utf8) {
            request.setValue("Basic \(authData.base64EncodedString())", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let patterns = json?["patterns"] as? [[String: Any]] else { return [] }
            return patterns.compactMap { parsePattern($0) }
        } catch {
            return nil
        }
    }

    private static func ravelryCredentials() -> (accessKey: String, personalKey: String)? {
        guard let accessKey = Bundle.main.object(forInfoDictionaryKey: "RAVELRY_ACCESS_KEY") as? String,
              let personalKey = Bundle.main.object(forInfoDictionaryKey: "RAVELRY_PERSONAL_KEY") as? String,
              !accessKey.isEmpty, accessKey != "placeholder",
              !personalKey.isEmpty, personalKey != "placeholder" else {
            return nil
        }
        return (accessKey, personalKey)
    }

    private static func parsePattern(_ json: [String: Any]) -> PatternDiscoveryResult? {
        guard let id = json["id"] as? Int,
              let name = json["name"] as? String,
              let permalink = json["permalink"] as? String else { return nil }

        let sourceUrl = "https://www.ravelry.com/patterns/library/\(permalink)"
        let free = (json["free"] as? Bool) ?? false
        let craft = (json["craft"] as? [String: Any]).flatMap { $0["name"] as? String }

        var designer: String?
        if let design = json["designer"] as? [String: Any], let dName = design["name"] as? String {
            designer = dName
        }

        let patternDescription = json["pattern_author"] as? String ?? json["notes"] as? String

        let imageUrl: String?
        if let photos = json["photos"] as? [[String: Any]], let first = photos.first {
            imageUrl = (first["medium_url"] as? String) ?? (first["medium2_url"] as? String) ?? (first["small_url"] as? String)
        } else {
            imageUrl = nil
        }

        return PatternDiscoveryResult(
            id: "ravelry-\(id)",
            title: name,
            sourceUrl: sourceUrl,
            imageUrl: imageUrl,
            isFree: free,
            craftType: craft,
            designer: designer,
            patternDescription: patternDescription
        )
    }
}
