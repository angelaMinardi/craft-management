//
//  RavelryUserService.swift
//  PatternVault
//
//  Fetches current user and pattern library from Ravelry API using the user's OAuth 2.0 Bearer token.
//

import Foundation

struct RavelryCurrentUser: Sendable {
    let username: String
    let id: Int
}

struct RavelryStashEntry: Sendable {
    let name: String
    let colorway: String?
    let weightCategory: String?
    let yardage: Double?
    let skeins: Double
    let location: String?
}

struct RavelryLibraryEntry: Sendable {
    let patternId: Int
    let name: String
    let permalink: String
    var imageUrl: String?
    var craftName: String?
    var pdfUrl: String?
    var patternDescription: String?
    var difficulty: String?
    var gauge: String?
    var needleHookSizes: String?
    var yarnWeightYardage: String?
}

@MainActor
enum RavelryUserService {

    private static let apiBase = URL(string: "https://api.ravelry.com")!

    /// Requires user's Ravelry tokens from Keychain (OAuth 2.0: Bearer token).
    static func fetchCurrentUser(userId: UUID) async throws -> RavelryCurrentUser {
        guard let (accessToken, _) = RavelryOAuthService.shared.tokens(for: userId) else {
            throw RavelryUserError.notConnected
        }
        let url = apiBase.appendingPathComponent("current_user.json")
        let (data, _) = try await bearerGet(url: url, accessToken: accessToken)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let user = json["user"] as? [String: Any],
              let username = user["username"] as? String,
              let id = user["id"] as? Int else {
            throw RavelryUserError.invalidResponse
        }
        return RavelryCurrentUser(username: username, id: id)
    }

    /// Fetches the user's pattern library via library/search.json. Returns volumes (paginated). Per Ravelry API docs, library/search returns "volumes" and "paginator".
    static func fetchLibrary(userId: UUID, username: String, page: Int = 1, pageSize: Int = 50) async throws -> [RavelryLibraryEntry] {
        guard let (accessToken, _) = RavelryOAuthService.shared.tokens(for: userId) else {
            throw RavelryUserError.notConnected
        }
        guard let encodedUsername = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return [] }
        let path = "people/\(encodedUsername)/library/search.json"
        var comp = URLComponents(url: apiBase.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        comp.queryItems = [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "page_size", value: "\(pageSize)")
        ]
        guard let url = comp.url else { throw RavelryUserError.invalidResponse }

        let (data, response) = try await bearerGet(url: url, accessToken: accessToken)
        guard let http = response as? HTTPURLResponse else { throw RavelryUserError.invalidResponse }
        if http.statusCode == 404 { return [] }
        guard http.statusCode == 200 else { throw RavelryUserError.apiError(http.statusCode) }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RavelryUserError.invalidResponse
        }
        // Ravelry library/search returns "volumes" (Volume list), not "library" or "library_entries".
        let volumes = json["volumes"] as? [[String: Any]] ?? []
        return volumes.compactMap { parseVolumeEntry($0) }
    }

    private static func bearerGet(url: URL, accessToken: String) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode == 401 {
            throw RavelryUserError.tokenExpired
        }
        return (data, response)
    }

    /// Parse a Volume (list) from library/search.json. Volume has pattern_id, title, first_photo, small_image_url, etc.
    private static func parseVolumeEntry(_ volume: [String: Any]) -> RavelryLibraryEntry? {
        let patternId = volume["pattern_id"] as? Int ?? volume["id"] as? Int
        guard let patternId = patternId else { return nil }
        let name = volume["title"] as? String ?? "Pattern \(patternId)"
        let permalink = (volume["permalink"] as? String) ?? "pattern-\(patternId)"
        var imageUrl = volume["cover_image_url"] as? String ?? volume["small_image_url"] as? String ?? volume["square_image_url"] as? String
        if imageUrl == nil, let firstPhoto = volume["first_photo"] as? [String: Any] {
            imageUrl = (firstPhoto["medium_url"] as? String) ?? (firstPhoto["small_url"] as? String)
        }
        let craftName: String? = nil // Volume list doesn't include craft
        return RavelryLibraryEntry(patternId: patternId, name: name, permalink: permalink, imageUrl: imageUrl, craftName: craftName, pdfUrl: nil)
    }

    /// Fetches favorited patterns. GET people/{username}/favorites/list.json with types=pattern.
    static func fetchFavorites(userId: UUID, username: String, page: Int = 1, pageSize: Int = 50) async throws -> [RavelryLibraryEntry] {
        guard let (accessToken, _) = RavelryOAuthService.shared.tokens(for: userId) else {
            throw RavelryUserError.notConnected
        }
        guard let encodedUsername = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return [] }
        let path = "people/\(encodedUsername)/favorites/list.json"
        var comp = URLComponents(url: apiBase.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        comp.queryItems = [
            URLQueryItem(name: "types", value: "pattern"),
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "page_size", value: "\(pageSize)")
        ]
        guard let url = comp.url else { throw RavelryUserError.invalidResponse }
        let (data, response) = try await bearerGet(url: url, accessToken: accessToken)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            if (response as? HTTPURLResponse)?.statusCode == 404 { return [] }
            throw RavelryUserError.invalidResponse
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RavelryUserError.invalidResponse
        }
        let favorites = json["favorites"] as? [[String: Any]] ?? json["bookmarks"] as? [[String: Any]] ?? []
        return favorites.compactMap { parseFavoriteEntry($0) }
    }

    /// Fetches user's projects. GET projects/{username}/list.json.
    static func fetchProjects(userId: UUID, username: String, page: Int = 1, pageSize: Int = 50) async throws -> [RavelryLibraryEntry] {
        guard let (accessToken, _) = RavelryOAuthService.shared.tokens(for: userId) else {
            throw RavelryUserError.notConnected
        }
        guard let encodedUsername = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return [] }
        let path = "projects/\(encodedUsername)/list.json"
        var comp = URLComponents(url: apiBase.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        comp.queryItems = [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "page_size", value: "\(pageSize)")
        ]
        guard let url = comp.url else { throw RavelryUserError.invalidResponse }
        let (data, response) = try await bearerGet(url: url, accessToken: accessToken)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            if (response as? HTTPURLResponse)?.statusCode == 404 { return [] }
            throw RavelryUserError.invalidResponse
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RavelryUserError.invalidResponse
        }
        let projects = json["projects"] as? [[String: Any]] ?? []
        return projects.compactMap { parseProjectEntry($0) }
    }

    /// Fetches user's queued projects. GET people/{username}/queue/list.json.
    static func fetchQueue(userId: UUID, username: String, page: Int = 1, pageSize: Int = 50) async throws -> [RavelryLibraryEntry] {
        guard let (accessToken, _) = RavelryOAuthService.shared.tokens(for: userId) else {
            throw RavelryUserError.notConnected
        }
        guard let encodedUsername = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return [] }
        let path = "people/\(encodedUsername)/queue/list.json"
        var comp = URLComponents(url: apiBase.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        comp.queryItems = [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "page_size", value: "\(pageSize)")
        ]
        guard let url = comp.url else { throw RavelryUserError.invalidResponse }
        let (data, response) = try await bearerGet(url: url, accessToken: accessToken)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            if (response as? HTTPURLResponse)?.statusCode == 404 { return [] }
            throw RavelryUserError.invalidResponse
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RavelryUserError.invalidResponse
        }
        let queued = json["queued_projects"] as? [[String: Any]] ?? []
        return queued.compactMap { parseQueueEntry($0) }
    }

    private static func parseQueueEntry(_ entry: [String: Any]) -> RavelryLibraryEntry? {
        guard let patternId = entry["pattern_id"] as? Int else { return nil }
        let name = (entry["pattern_name"] as? String) ?? "Pattern \(patternId)"
        var imageUrl: String?
        if let photo = entry["best_photo"] as? [String: Any] {
            imageUrl = (photo["medium_url"] as? String) ?? (photo["small_url"] as? String)
        }
        let permalink = "pattern-\(patternId)"
        return RavelryLibraryEntry(patternId: patternId, name: name, permalink: permalink, imageUrl: imageUrl, craftName: nil, pdfUrl: nil)
    }

    /// Fetches user's Ravelry stash. GET people/{username}/stash/list.json.
    static func fetchStash(userId: UUID, username: String, page: Int = 1, pageSize: Int = 50) async throws -> [RavelryStashEntry] {
        guard let (accessToken, _) = RavelryOAuthService.shared.tokens(for: userId) else {
            throw RavelryUserError.notConnected
        }
        guard let encodedUsername = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return [] }
        let path = "people/\(encodedUsername)/stash/list.json"
        var comp = URLComponents(url: apiBase.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        comp.queryItems = [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "page_size", value: "\(pageSize)")
        ]
        guard let url = comp.url else { throw RavelryUserError.invalidResponse }
        let (data, response) = try await bearerGet(url: url, accessToken: accessToken)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            if (response as? HTTPURLResponse)?.statusCode == 404 { return [] }
            throw RavelryUserError.invalidResponse
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RavelryUserError.invalidResponse
        }
        let stash = json["stash"] as? [[String: Any]] ?? []
        return stash.compactMap { parseStashEntry($0) }
    }

    private static func parseStashEntry(_ entry: [String: Any]) -> RavelryStashEntry? {
        let name = entry["name"] as? String ?? entry["yarn_name"] as? String
        guard let name, !name.isEmpty else { return nil }
        let colorway = entry["colorway_name"] as? String ?? entry["color_family_name"] as? String
        let yarn = entry["yarn"] as? [String: Any]
        let yarnWeight = (yarn?["yarn_weight"] as? [String: Any])?["name"] as? String
        let yardage = entry["total_yardage"] as? Double ?? entry["total_meters"] as? Double
        let skeins = entry["skeins"] as? Double ?? entry["total_skeins"] as? Double ?? 1
        let location = entry["location"] as? String
        return RavelryStashEntry(
            name: name,
            colorway: colorway,
            weightCategory: yarnWeight,
            yardage: yardage,
            skeins: skeins,
            location: location
        )
    }

    /// Rich detail extracted from Ravelry batch pattern API.
    struct RavelryPatternDetail: Sendable {
        var imageUrl: String?
        var pdfUrl: String?
        var description: String?
        var difficulty: String?
        var gauge: String?
        var craftName: String?
        var needleHookSizes: String?
        var yarnWeightYardage: String?
    }

    /// Batch fetch full pattern details. GET /patterns.json?ids=1+2+3. Returns map patternId -> RavelryPatternDetail.
    /// Accepts both array and dictionary response shapes; uses free_pdf_url when pdf_url is nil.
    static func fetchPatternDetails(userId: UUID, patternIds: [Int]) async throws -> [Int: RavelryPatternDetail] {
        guard !patternIds.isEmpty else { return [:] }
        guard let (accessToken, _) = RavelryOAuthService.shared.tokens(for: userId) else {
            throw RavelryUserError.notConnected
        }
        let idsString = patternIds.prefix(50).map { String($0) }.joined(separator: "+")
        var comp = URLComponents(url: apiBase.appendingPathComponent("patterns.json"), resolvingAgainstBaseURL: false)!
        comp.queryItems = [URLQueryItem(name: "ids", value: idsString)]
        guard let url = comp.url else { return [:] }
        let (data, response) = try await bearerGet(url: url, accessToken: accessToken)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [:] }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        let result = parsePatternDetailsPayload(json["patterns"])
        #if DEBUG
        if let first = result.first {
            print("[Ravelry] fetchPatternDetails: count=\(result.count), first id=\(first.key), hasPdfUrl=\(first.value.pdfUrl != nil)")
        }
        #endif
        return result
    }

    /// Parses the "patterns" payload from Ravelry batch API (array or dictionary, flat or nested "pattern" wrapper).
    static func parsePatternDetailsPayload(_ patternsPayload: Any?) -> [Int: RavelryPatternDetail] {
        var result: [Int: RavelryPatternDetail] = [:]
        guard let payload = patternsPayload else { return result }
        if let arr = payload as? [[String: Any]] {
            for item in arr {
                let pattern = (item["pattern"] as? [String: Any]) ?? item
                guard let patternId = pattern["id"] as? Int else { continue }
                result[patternId] = extractPatternDetail(from: pattern)
            }
        } else if let patternsMap = payload as? [String: Any] {
            for (key, value) in patternsMap {
                guard let patternId = Int(key) else { continue }
                let raw = value as? [String: Any]
                let pattern = raw.flatMap { ($0["pattern"] as? [String: Any]) ?? $0 }
                guard let pattern = pattern else { continue }
                result[patternId] = extractPatternDetail(from: pattern)
            }
        }
        return result
    }

    private static func extractPatternDetail(from pattern: [String: Any]) -> RavelryPatternDetail {
        var imageUrl: String?
        if let photo = pattern["first_photo"] as? [String: Any] {
            imageUrl = (photo["medium_url"] as? String) ?? (photo["small_url"] as? String)
        }
        let pdfUrl = (pattern["pdf_url"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? (pattern["free_pdf_url"] as? String).flatMap { $0.isEmpty ? nil : $0 }

        // Description from notes (plain text preferred, strip HTML if needed)
        var description: String?
        if let notes = pattern["notes"] as? String, !notes.isEmpty {
            description = notes
        } else if let notesHtml = pattern["notes_html"] as? String, !notesHtml.isEmpty {
            description = stripHTML(notesHtml)
        }

        // Difficulty: Ravelry returns difficulty_average as a Float (1.0–10.0)
        var difficulty: String?
        if let avg = pattern["difficulty_average"] as? Double, avg > 0 {
            let level = Int(avg.rounded())
            switch level {
            case 1...2: difficulty = "Beginner"
            case 3...4: difficulty = "Easy"
            case 5...6: difficulty = "Intermediate"
            case 7...8: difficulty = "Advanced"
            case 9...10: difficulty = "Expert"
            default: difficulty = "Level \(level)/10"
            }
        }

        // Gauge
        let gauge = (pattern["gauge_description"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? (pattern["gauge"] as? String).flatMap { $0.isEmpty ? nil : $0 }

        // Craft name
        let craftName = (pattern["craft"] as? [String: Any])?["name"] as? String

        // Needle/hook sizes
        var needleHookSizes: String?
        if let needles = pattern["pattern_needle_sizes"] as? [[String: Any]], !needles.isEmpty {
            let sizes = needles.compactMap { needle -> String? in
                let name = needle["name"] as? String
                let us = needle["us"] as? String
                let metric = needle["metric"] as? Double
                if let name, !name.isEmpty { return name }
                if let us, !us.isEmpty, let metric {
                    return "US \(us) (\(String(format: "%g", metric))mm)"
                }
                if let metric { return "\(String(format: "%g", metric))mm" }
                return us.map { "US \($0)" }
            }
            if !sizes.isEmpty { needleHookSizes = sizes.joined(separator: ", ") }
        }

        // Yarn weight + yardage
        var yarnWeightYardage: String?
        let weightName = (pattern["yarn_weight"] as? [String: Any])?["name"] as? String
        let yardage = pattern["yardage"] as? Int ?? pattern["yardage_max"] as? Int
        if let weightName, !weightName.isEmpty {
            if let yardage {
                yarnWeightYardage = "\(weightName) — \(yardage) yards"
            } else {
                yarnWeightYardage = weightName
            }
        } else if let yardage {
            yarnWeightYardage = "\(yardage) yards"
        }

        return RavelryPatternDetail(
            imageUrl: imageUrl,
            pdfUrl: pdfUrl,
            description: description,
            difficulty: difficulty,
            gauge: gauge,
            craftName: craftName,
            needleHookSizes: needleHookSizes,
            yarnWeightYardage: yarnWeightYardage
        )
    }

    /// Strip basic HTML tags from a string.
    private static func stripHTML(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseFavoriteEntry(_ bookmark: [String: Any]) -> RavelryLibraryEntry? {
        guard (bookmark["type"] as? String) == "pattern" else { return nil }
        let pattern = bookmark["favorited"] as? [String: Any] ?? bookmark["pattern"] as? [String: Any]
        guard let pattern = pattern else { return nil }
        return parsePatternLikeEntry(pattern, fallbackId: bookmark["favorited_id"] as? Int)
    }

    private static func parseProjectEntry(_ project: [String: Any]) -> RavelryLibraryEntry? {
        guard let patternId = project["pattern_id"] as? Int else { return nil }
        let name = project["pattern_name"] as? String ?? "Pattern \(patternId)"
        var imageUrl: String?
        if let photo = project["first_photo"] as? [String: Any] {
            imageUrl = (photo["medium_url"] as? String) ?? (photo["small_url"] as? String)
        }
        let permalink = (project["pattern_permalink"] as? String) ?? "pattern-\(patternId)"
        return RavelryLibraryEntry(patternId: patternId, name: name, permalink: permalink, imageUrl: imageUrl, craftName: nil, pdfUrl: nil)
    }

    private static func parsePatternLikeEntry(_ pattern: [String: Any], fallbackId: Int?) -> RavelryLibraryEntry? {
        let patternId = pattern["id"] as? Int ?? fallbackId
        guard let patternId = patternId else { return nil }
        let name = pattern["name"] as? String ?? "Pattern \(patternId)"
        let permalink = pattern["permalink"] as? String ?? "pattern-\(patternId)"
        var imageUrl: String?
        if let photo = pattern["first_photo"] as? [String: Any] {
            imageUrl = (photo["medium_url"] as? String) ?? (photo["small_url"] as? String)
        }
        if imageUrl == nil {
            imageUrl = pattern["small_image_url"] as? String ?? pattern["square_image_url"] as? String
        }
        let craftName = (pattern["craft"] as? [String: Any])?["name"] as? String
        return RavelryLibraryEntry(patternId: patternId, name: name, permalink: permalink, imageUrl: imageUrl, craftName: craftName, pdfUrl: nil)
    }

    enum RavelryUserError: Error, LocalizedError {
        case notConnected
        case invalidResponse
        case apiError(Int)
        case tokenExpired
        var errorDescription: String? {
            switch self {
            case .notConnected: return "Ravelry account is not connected."
            case .invalidResponse: return "Invalid response from Ravelry."
            case .apiError(let code): return "Ravelry returned error \(code)."
            case .tokenExpired: return "Ravelry session expired. Please reconnect your account in Settings."
            }
        }
    }
}
