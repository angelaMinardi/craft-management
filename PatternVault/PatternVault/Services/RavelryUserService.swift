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
        return try await URLSession.shared.data(for: request)
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

    /// Batch fetch full pattern details (first_photo, pdf_url). GET /patterns.json?ids=1+2+3. Returns map patternId -> (imageUrl, pdfUrl).
    /// Accepts both array and dictionary response shapes; uses free_pdf_url when pdf_url is nil.
    static func fetchPatternDetails(userId: UUID, patternIds: [Int]) async throws -> [Int: (imageUrl: String?, pdfUrl: String?)] {
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
        if let payload = json["patterns"] {
            if (payload as? [[String: Any]]) != nil { print("[Ravelry] fetchPatternDetails: patterns is array, count=\(result.count)") }
            else if (payload as? [String: Any]) != nil { print("[Ravelry] fetchPatternDetails: patterns is dictionary, count=\(result.count)") }
            else { print("[Ravelry] fetchPatternDetails: patterns is neither array nor dictionary, type=\(type(of: payload))") }
        }
        if let first = result.first {
            print("[Ravelry] first pattern id=\(first.key), hasPdfUrl=\(first.value.pdfUrl != nil)")
        }
        #endif
        return result
    }

    /// Parses the "patterns" payload from Ravelry batch API (array or dictionary, flat or nested "pattern" wrapper). Used by fetchPatternDetails; exposed for unit tests.
    static func parsePatternDetailsPayload(_ patternsPayload: Any?) -> [Int: (imageUrl: String?, pdfUrl: String?)] {
        var result: [Int: (imageUrl: String?, pdfUrl: String?)] = [:]
        guard let payload = patternsPayload else { return result }
        if let arr = payload as? [[String: Any]] {
            for item in arr {
                let pattern = (item["pattern"] as? [String: Any]) ?? item
                guard let patternId = pattern["id"] as? Int else { continue }
                result[patternId] = extractImageAndPdfUrl(from: pattern)
            }
        } else if let patternsMap = payload as? [String: Any] {
            for (key, value) in patternsMap {
                guard let patternId = Int(key) else { continue }
                let raw = value as? [String: Any]
                let pattern = raw.flatMap { ($0["pattern"] as? [String: Any]) ?? $0 }
                guard let pattern = pattern else { continue }
                result[patternId] = extractImageAndPdfUrl(from: pattern)
            }
        }
        return result
    }

    private static func extractImageAndPdfUrl(from pattern: [String: Any]) -> (imageUrl: String?, pdfUrl: String?) {
        var imageUrl: String?
        if let photo = pattern["first_photo"] as? [String: Any] {
            imageUrl = (photo["medium_url"] as? String) ?? (photo["small_url"] as? String)
        }
        let pdfUrl = (pattern["pdf_url"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? (pattern["free_pdf_url"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return (imageUrl, pdfUrl)
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
        var errorDescription: String? {
            switch self {
            case .notConnected: return "Ravelry account is not connected."
            case .invalidResponse: return "Invalid response from Ravelry."
            case .apiError(let code): return "Ravelry returned error \(code)."
            }
        }
    }
}
