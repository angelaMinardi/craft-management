//
//  SupabaseExtensionClient.swift
//  SaveToPatternVault
//
//  Lightweight Supabase REST client for the share extension.
//  Uses raw URLSession instead of the Supabase SDK to minimize extension memory.
//

import Foundation
import UIKit
import Security

/// Result from the extract-pattern-from-video Edge Function (YouTube).
struct VideoExtractionResult {
    let title: String
    let summary: String
    let tags: [String]
    let craftType: String?
    let difficulty: String?
    let materials: String?
    let sourceContent: String?
    let videoUrl: String?
    let gauge: String?
    let needleHookSizes: String?
    let yarnWeightYardage: String?
    let techniques: String?
    let yarnLinks: [(brandName: String, officialUrl: String?, storeUrl: String?)]
    /// JSON string of steps: [{"title":"...", "body":"..."}]
    let parsedSteps: String?

    static func from(json: [String: Any]?, sourceURL: String) -> VideoExtractionResult? {
        guard let j = json, let title = j["title"] as? String, !title.isEmpty else { return nil }
        let summary = j["summary"] as? String ?? ""
        let tags = j["tags"] as? [String] ?? []
        let yarnLinksRaw = j["yarn_links"] as? [[String: Any]] ?? []
        let yarnLinks = yarnLinksRaw.compactMap { item -> (String, String?, String?)? in
            guard let name = item["brand_name"] as? String, !name.isEmpty else { return nil }
            return (name, item["official_url"] as? String, item["store_url"] as? String)
        }
        return VideoExtractionResult(
            title: title,
            summary: summary,
            tags: tags,
            craftType: j["craft_type"] as? String,
            difficulty: j["difficulty"] as? String,
            materials: j["materials"] as? String,
            sourceContent: j["cleaned_content"] as? String,
            videoUrl: j["video_url"] as? String ?? sourceURL,
            gauge: j["gauge"] as? String,
            needleHookSizes: j["needle_hook_sizes"] as? String,
            yarnWeightYardage: j["yarn_weight_yardage"] as? String,
            techniques: j["techniques"] as? String,
            yarnLinks: yarnLinks,
            parsedSteps: j["parsed_steps"] as? String
        )
    }
}

struct SavePatternResult {
    let patternId: String
    let warnings: [String]
}

enum SupabaseExtensionError: Error, LocalizedError {
    case notAuthenticated
    case sessionExpired
    case missingConfig
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "Please sign in to Pattern Vault first."
        case .sessionExpired: return "Your sign-in session expired."
        case .missingConfig: return "Supabase configuration missing."
        case .saveFailed(let msg): return msg
        }
    }

    /// User-friendly message for network/DNS errors so the share sheet suggests opening the app first.
    static func messageForNetworkError(_ error: Error) -> String {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed:
                return "Could not reach the server. Open Pattern Vault once, then try saving again. If it still fails, check your internet connection."
            case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost:
                return "No internet connection. Check Wi‑Fi or cellular and try again."
            case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateHasBadDate:
                return "Connection was not secure. Open Pattern Vault and try again."
            default:
                break
            }
        }
        return error.localizedDescription
    }
}

enum SupabaseExtensionClient {

    private static let appGroupId = "group.com.patternvault.app"
    private static let keychainService = "com.patternvault.app.supabase"
    private static let keychainTokenAccount = "supabase_access_token"
    private static let keychainUserIdAccount = "supabase_user_id"
    private static let keychainRefreshTokenAccount = "supabase_refresh_token"

    struct AuthInfo {
        let accessToken: String
        let userId: String
    }

    /// Reads shared auth credentials from Keychain (preferred) with UserDefaults fallback.
    /// Note: this returns the cached access token even if it has expired. For network calls,
    /// use `freshAuthInfo()` to refresh stale tokens before hitting Supabase.
    static func authInfo() -> AuthInfo? {
        // Try Keychain first (secure, shared via App Group access group)
        if let token = readFromSharedKeychain(account: keychainTokenAccount),
           !token.isEmpty {
            let keychainUserId = readFromSharedKeychain(account: keychainUserIdAccount)
            let jwtUserId = jwtSub(from: token)
            if let userId = jwtUserId ?? keychainUserId, !userId.isEmpty {
                return AuthInfo(accessToken: token, userId: userId)
            }
        }
        // Fallback to UserDefaults for users who haven't re-launched the main app yet
        let defaults = UserDefaults(suiteName: appGroupId)
        guard let token = defaults?.string(forKey: "supabase_access_token"),
              !token.isEmpty else {
            return nil
        }
        let defaultsUserId = defaults?.string(forKey: "supabase_user_id")
        guard let userId = jwtSub(from: token) ?? defaultsUserId, !userId.isEmpty else {
            return nil
        }
        return AuthInfo(accessToken: token, userId: userId)
    }

    /// Returns auth credentials, refreshing the access token via Supabase's token endpoint
    /// if the cached one has expired or is within `expiryMargin` seconds of expiring.
    /// The Supabase SDK only refreshes tokens while the main app is running, so the share
    /// extension must do its own refresh to avoid 401s on cold-shared content.
    static func freshAuthInfo(expiryMargin: TimeInterval = 60) async -> AuthInfo? {
        guard let current = authInfo() else { return nil }
        if !isAccessTokenExpired(current.accessToken, withMargin: expiryMargin) {
            return current
        }
        guard let refreshToken = readFromSharedKeychain(account: keychainRefreshTokenAccount),
              !refreshToken.isEmpty,
              let cfg = config(),
              let refreshed = await refreshAccessToken(refreshToken: refreshToken, config: cfg) else {
            return nil
        }
        saveToSharedKeychain(account: keychainTokenAccount, value: refreshed.accessToken)
        saveToSharedKeychain(account: keychainRefreshTokenAccount, value: refreshed.refreshToken)
        let userId = jwtSub(from: refreshed.accessToken) ?? current.userId
        return AuthInfo(accessToken: refreshed.accessToken, userId: userId)
    }

    private struct RefreshedSession {
        let accessToken: String
        let refreshToken: String
    }

    private static func isAccessTokenExpired(_ token: String, withMargin: TimeInterval) -> Bool {
        guard let exp = jwtExp(from: token) else {
            // Treat tokens we can't parse as expired so we attempt a refresh rather than 401.
            return true
        }
        return Date().timeIntervalSince1970 + withMargin >= exp
    }

    private static func jwtExp(from token: String) -> TimeInterval? {
        let segments = token.split(separator: ".")
        guard segments.count >= 2 else { return nil }
        var payload = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = payload.count % 4
        if remainder > 0 {
            payload += String(repeating: "=", count: 4 - remainder)
        }
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let exp = json["exp"] as? TimeInterval { return exp }
        if let expInt = json["exp"] as? Int { return TimeInterval(expInt) }
        return nil
    }

    private static func refreshAccessToken(
        refreshToken: String,
        config: (url: String, anonKey: String)
    ) async -> RefreshedSession? {
        guard let url = URL(string: "\(config.url)/auth/v1/token?grant_type=refresh_token") else {
            return nil
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["refresh_token": refreshToken])
        request.timeoutInterval = 15
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                #if DEBUG
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                NSLog("[SaveToPatternVault] token refresh failed HTTP %ld", code)
                #endif
                return nil
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let accessToken = json["access_token"] as? String,
                  let newRefresh = json["refresh_token"] as? String,
                  !accessToken.isEmpty, !newRefresh.isEmpty else {
                return nil
            }
            return RefreshedSession(accessToken: accessToken, refreshToken: newRefresh)
        } catch {
            return nil
        }
    }

    private static func saveToSharedKeychain(account: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: appGroupId
        ]
        SecItemDelete(query as CFDictionary)
        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    // MARK: - Shared Keychain read (minimal inline helper — cannot import main app's KeychainHelper)

    private static func readFromSharedKeychain(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: appGroupId,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    /// Extracts JWT subject (`sub`) from a Supabase access token.
    /// Using `sub` avoids stale cached user-id mismatches in extension storage paths.
    private static func jwtSub(from token: String) -> String? {
        let segments = token.split(separator: ".")
        guard segments.count >= 2 else { return nil }
        var payload = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = payload.count % 4
        if remainder > 0 {
            payload += String(repeating: "=", count: 4 - remainder)
        }
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sub = json["sub"] as? String,
              !sub.isEmpty else {
            return nil
        }
        return sub
    }

    /// URL for the extract-pattern-from-video Edge Function (YouTube transcript + Claude).
    static func videoExtractionFunctionURL() -> URL? {
        guard let config = config() else { return nil }
        return URL(string: "\(config.url)/functions/v1/extract-pattern-from-video")
    }

    /// Calls the Edge Function to extract pattern metadata from a YouTube video. Returns nil if not configured or request fails.
    static func extractPatternFromVideo(videoURL: String) async -> VideoExtractionResult? {
        guard let auth = await freshAuthInfo(),
              let url = videoExtractionFunctionURL() else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(auth.accessToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["url": videoURL])
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return nil }
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            return VideoExtractionResult.from(json: json, sourceURL: videoURL)
        } catch {
            return nil
        }
    }

    /// Reads Supabase config from the extension's shared App Group or falls back to Info.plist (from xcconfig).
    private static func config() -> (url: String, anonKey: String)? {
        let defaults = UserDefaults(suiteName: appGroupId)
        if let url = defaults?.string(forKey: "supabase_url"),
           let key = defaults?.string(forKey: "supabase_anon_key"),
           !url.isEmpty, !key.isEmpty,
           !url.contains("$("), !key.contains("$(") {
            let normalized = url.hasSuffix("/") ? String(url.dropLast()) : url
            if let parsed = URL(string: normalized),
               let scheme = parsed.scheme?.lowercased(),
               (scheme == "https" || scheme == "http"),
               parsed.host != nil {
                #if DEBUG
                let host = parsed.host ?? "invalid"
                NSLog("[SaveToPatternVault] config from App Group, host: %@", host)
                #endif
                return (normalized, key)
            } else {
                // Stale/invalid value in shared defaults; clear it so plist fallback can be used.
                defaults?.removeObject(forKey: "supabase_url")
            }
        }
        // Fallback: read from extension's Info.plist (SUPABASE_URL/SUPABASE_ANON_KEY from Config.xcconfig)
        if let url = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
           let key = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String,
           !url.isEmpty, !key.isEmpty,
           !url.contains("$("), !key.contains("$(") { // reject unsubstituted xcconfig vars
            let normalized = url.hasSuffix("/") ? String(url.dropLast()) : url
            if let parsed = URL(string: normalized),
               let scheme = parsed.scheme?.lowercased(),
               (scheme == "https" || scheme == "http"),
               parsed.host != nil {
                #if DEBUG
                let host = parsed.host ?? "invalid"
                NSLog("[SaveToPatternVault] config from Info.plist, host: %@", host)
                #endif
                return (normalized, key)
            }
        }
        #if DEBUG
        NSLog("[SaveToPatternVault] config nil: no App Group keys and no plist SUPABASE_URL/SUPABASE_ANON_KEY")
        #endif
        return nil
    }

    /// Lightweight debug snapshot for extension networking issues.
    static func connectionDiagnostics() -> String {
        let defaults = UserDefaults(suiteName: appGroupId)
        let appGroupURL = defaults?.string(forKey: "supabase_url") ?? "nil"
        let appGroupHost = URL(string: appGroupURL)?.host ?? "invalid"
        let hasAuth = authInfo() != nil
        let hasConfig = config() != nil
        return "auth=\(hasAuth) config=\(hasConfig) appGroupHost=\(appGroupHost)"
    }

    /// Saves a pattern directly to Supabase via REST API.
    static func savePattern(
        title: String,
        description: String?,
        sourceUrl: String,
        sourcePlatform: String?,
        thumbnailUrl: String?,
        status: String = "want_to_make",
        tags: [String] = [],
        difficulty: String? = nil,
        materials: String? = nil,
        craftType: String? = nil,
        sourceContent: String? = nil,
        videoUrl: String? = nil,
        gauge: String? = nil,
        needleHookSizes: String? = nil,
        yarnWeightYardage: String? = nil,
        techniques: String? = nil,
        parsedSteps: String? = nil,
        pdfUrl: String? = nil,
        pdfDataToUpload: Data? = nil,
        yarnLinks: [(brandName: String, officialUrl: String?, storeUrl: String?)] = [],
        imageUrls: [String] = [],
        enrichmentStatus: String? = nil,
        progressCallback: ((String) -> Void)? = nil
    ) async throws -> SavePatternResult {
        guard let auth = await freshAuthInfo() else { throw SupabaseExtensionError.notAuthenticated }
        guard let config = config() else { throw SupabaseExtensionError.missingConfig }

        let patternId = UUID().uuidString

        var warnings: [String] = []

        // If PDF was shared, upload it first and set pdf_url.
        // Do not fail the entire save if PDF upload fails; save metadata and warn instead.
        // Exception: if the failure is an expired session, surface it so the user knows to
        // re-auth rather than getting a partially-saved pattern.
        var pdfUrlToUse: String? = pdfUrl
        if let pdfData = pdfDataToUpload, !pdfData.isEmpty {
            progressCallback?("Uploading PDF...")
            do {
                let uploaded = try await uploadPdfToStorage(pdfData: pdfData, patternId: patternId, auth: auth, config: config)
                pdfUrlToUse = uploaded
            } catch SupabaseExtensionError.sessionExpired {
                throw SupabaseExtensionError.sessionExpired
            } catch {
                warnings.append("PDF upload failed (\(error.localizedDescription)), but the pattern was still saved.")
            }
        }

        // Build pattern payload
        var payload: [String: Any] = [
            "id": patternId,
            "user_id": auth.userId,
            "title": title,
            "source_url": sourceUrl,
            "status": status
        ]
        if let description, !description.isEmpty { payload["description"] = description }
        if let sourcePlatform { payload["source_platform"] = sourcePlatform }
        if let thumbnailUrl, !thumbnailUrl.isEmpty { payload["thumbnail_url"] = thumbnailUrl }
        if let difficulty, !difficulty.isEmpty { payload["difficulty"] = difficulty }
        if let materials, !materials.isEmpty { payload["materials"] = materials }
        if let craftType, !craftType.isEmpty { payload["craft_type"] = craftType }
        if let sourceContent, !sourceContent.isEmpty { payload["source_content"] = sourceContent }
        if let videoUrl, !videoUrl.isEmpty { payload["video_url"] = videoUrl }
        if let gauge, !gauge.isEmpty { payload["gauge"] = gauge }
        if let needleHookSizes, !needleHookSizes.isEmpty { payload["needle_hook_sizes"] = needleHookSizes }
        if let yarnWeightYardage, !yarnWeightYardage.isEmpty { payload["yarn_weight_yardage"] = yarnWeightYardage }
        if let techniques, !techniques.isEmpty { payload["techniques"] = techniques }
        if let parsedSteps, !parsedSteps.isEmpty { payload["parsed_steps"] = parsedSteps }
        if let pdfUrlToUse, !pdfUrlToUse.isEmpty { payload["pdf_url"] = pdfUrlToUse }
        if let enrichmentStatus, !enrichmentStatus.isEmpty { payload["enrichment_status"] = enrichmentStatus }

        // Insert pattern (retry once on network failure)
        try await postToSupabase(
            config: config,
            auth: auth,
            table: "patterns",
            payload: payload,
            retryOnFailure: true
        )

        // Insert yarn links if any
        for (index, link) in yarnLinks.enumerated() {
            var linkPayload: [String: Any] = [
                "id": UUID().uuidString,
                "pattern_id": patternId,
                "user_id": auth.userId,
                "brand_name": link.brandName,
                "display_order": index
            ]
            if let u = link.officialUrl, !u.isEmpty { linkPayload["official_url"] = u }
            if let u = link.storeUrl, !u.isEmpty { linkPayload["store_url"] = u }
            do {
                try await postToSupabase(
                    config: config,
                    auth: auth,
                    table: "pattern_yarn_links",
                    payload: linkPayload
                )
            } catch {
                warnings.append("Some yarn links could not be saved.")
                break
            }
        }

        // Link tags that already exist in public.tags.
        // The tags table is read-only for clients; inserting here can fail by design.
        for tagName in tags {
            guard let tagId = try await fetchExistingTagId(
                config: config,
                auth: auth,
                tagName: tagName
            ) else {
                continue
            }
            let linkPayload: [String: Any] = [
                "pattern_id": patternId,
                "tag_id": tagId
            ]
            do {
                try await postToSupabase(
                    config: config,
                    auth: auth,
                    table: "pattern_tags",
                    payload: linkPayload
                )
            } catch {
                warnings.append("Some tags could not be linked to the pattern.")
            }
        }

        // Upload pattern images (max 5, compressed)
        if !imageUrls.isEmpty {
            let maxImages = min(imageUrls.count, 5)
            for (index, imageUrlString) in imageUrls.prefix(maxImages).enumerated() {
                progressCallback?("Saving images (\(index + 1)/\(maxImages))...")
                guard let imageUrl = URL(string: imageUrlString) else { continue }
                do {
                    let (data, _) = try await URLSession.shared.data(from: imageUrl)
                    guard let compressed = compressImage(data) else { continue }
                    let storagePath = "\(patternId)/\(UUID().uuidString).jpg"
                    let publicUrl = try await uploadToStorage(
                        config: config,
                        auth: auth,
                        bucket: "pattern-images",
                        path: storagePath,
                        data: compressed,
                        contentType: "image/jpeg"
                    )
                    let imagePayload: [String: Any] = [
                        "id": UUID().uuidString,
                        "pattern_id": patternId,
                        "user_id": auth.userId,
                        "image_url": publicUrl,
                        "display_order": index
                    ]
                    do {
                        try await postToSupabase(
                            config: config,
                            auth: auth,
                            table: "pattern_images",
                            payload: imagePayload
                        )
                    } catch {
                        warnings.append("Some images could not be saved.")
                    }
                } catch {
                    warnings.append("Some images could not be downloaded.")
                    continue
                }
            }
        }

        return SavePatternResult(patternId: patternId, warnings: Array(Set(warnings)))
    }

    // MARK: - Image Helpers

    private static func compressImage(_ data: Data, maxWidth: CGFloat = 1200, quality: CGFloat = 0.7) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let scale = min(1.0, maxWidth / image.size.width)
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        return resized.jpegData(compressionQuality: quality)
    }

    private static func uploadToStorage(
        config: (url: String, anonKey: String),
        auth: AuthInfo,
        bucket: String,
        path: String,
        data: Data,
        contentType: String,
        upsert: Bool = false
    ) async throws -> String {
        guard let url = URL(string: "\(config.url)/storage/v1/object/\(bucket)/\(path)") else {
            throw SupabaseExtensionError.saveFailed("Invalid storage URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = data
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(auth.accessToken)", forHTTPHeaderField: "Authorization")
        if upsert {
            request.setValue("true", forHTTPHeaderField: "x-upsert")
        }
        request.timeoutInterval = 30

        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if code == 401 { throw SupabaseExtensionError.sessionExpired }
            let responseText = String(data: responseData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if responseText.isEmpty {
                throw SupabaseExtensionError.saveFailed("Storage upload HTTP \(code)")
            }
            throw SupabaseExtensionError.saveFailed("Storage upload HTTP \(code): \(responseText)")
        }

        return "\(config.url)/storage/v1/object/public/\(bucket)/\(path)"
    }

    /// Uploads a chart image to the pattern-images bucket. Called by ExtensionChartProcessor.
    /// - Parameters:
    ///   - imageData: JPEG data for the chart.
    ///   - storagePath: Path within pattern-images bucket (e.g. "patternId/chart_uuid.jpg").
    /// - Returns: Public URL of the uploaded chart image.
    static func uploadChartImage(imageData: Data, storagePath: String) async throws -> String {
        guard let auth = await freshAuthInfo() else {
            throw SupabaseExtensionError.saveFailed("Not authenticated")
        }
        guard let cfg = config() else {
            throw SupabaseExtensionError.saveFailed("Missing Supabase config")
        }
        return try await uploadToStorage(
            config: cfg,
            auth: auth,
            bucket: "pattern-images",
            path: storagePath,
            data: imageData,
            contentType: "image/jpeg"
        )
    }

    /// Uploads PDF to pattern-pdfs bucket. Path: userId/patternId/uuid.pdf. Returns public URL.
    private static func uploadPdfToStorage(
        pdfData: Data,
        patternId: String,
        auth: AuthInfo,
        config: (url: String, anonKey: String)
    ) async throws -> String {
        let bucket = "pattern-pdfs"
        let path = "\(auth.userId.lowercased())/\(patternId.lowercased())/\(UUID().uuidString.lowercased()).pdf"
        do {
            return try await uploadToStorage(
                config: config,
                auth: auth,
                bucket: bucket,
                path: path,
                data: pdfData,
                contentType: "application/pdf"
            )
        } catch SupabaseExtensionError.sessionExpired {
            // Auth failure won't be fixed by retrying with a different content-type.
            throw SupabaseExtensionError.sessionExpired
        } catch {
            // Retry once with permissive content type + upsert for stricter bucket settings.
            do {
                return try await uploadToStorage(
                    config: config,
                    auth: auth,
                    bucket: bucket,
                    path: path,
                    data: pdfData,
                    contentType: "application/octet-stream",
                    upsert: true
                )
            } catch SupabaseExtensionError.sessionExpired {
                throw SupabaseExtensionError.sessionExpired
            } catch {
                throw SupabaseExtensionError.saveFailed(
                    "PDF upload failed in bucket '\(bucket)' at path '\(path)'. " +
                    "Verify Storage RLS policies for pattern-pdfs are applied (migration 016). " +
                    "Underlying error: \(error.localizedDescription)"
                )
            }
        }
    }

    private static func postToSupabase(
        config: (url: String, anonKey: String),
        auth: AuthInfo,
        table: String,
        payload: [String: Any],
        prefer: String? = nil,
        retryOnFailure: Bool = false
    ) async throws {
        guard let url = URL(string: "\(config.url)/rest/v1/\(table)"),
              let bodyData = try? JSONSerialization.data(withJSONObject: payload) else {
            throw SupabaseExtensionError.saveFailed("Invalid request")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(auth.accessToken)", forHTTPHeaderField: "Authorization")
        if let prefer {
            request.setValue(prefer, forHTTPHeaderField: "Prefer")
        }
        request.timeoutInterval = 25

        let maxAttempts = retryOnFailure ? 2 : 1
        var lastError: Error?
        for attempt in 1...maxAttempts {
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else {
                    let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                    if code == 401 { throw SupabaseExtensionError.sessionExpired }
                    throw SupabaseExtensionError.saveFailed("HTTP \(code)")
                }
                return
            } catch SupabaseExtensionError.sessionExpired {
                // Don't retry — refreshing once at the start of savePattern is enough; if the
                // server still rejects the JWT, the refresh token is also invalid.
                throw SupabaseExtensionError.sessionExpired
            } catch {
                lastError = error
                if attempt < maxAttempts {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                }
            }
        }
        throw lastError ?? SupabaseExtensionError.saveFailed("Save failed after retries")
    }

    private static func fetchExistingTagId(
        config: (url: String, anonKey: String),
        auth: AuthInfo,
        tagName: String
    ) async throws -> String? {
        let normalized = tagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }

        var components = URLComponents(string: "\(config.url)/rest/v1/tags")
        components?.queryItems = [
            URLQueryItem(name: "select", value: "id,name"),
            URLQueryItem(name: "name", value: "ilike.\(normalized)"),
            URLQueryItem(name: "limit", value: "1")
        ]
        guard let url = components?.url else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(auth.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 12

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return nil
        }
        guard let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let first = rows.first,
              let id = first["id"] as? String,
              !id.isEmpty else {
            return nil
        }
        return id
    }

    /// Fire-and-forget request to the enrich-pattern Edge Function.
    /// The function runs AI analysis server-side and updates the pattern row.
    static func requestEnrichment(patternId: String) async {
        guard let auth = await freshAuthInfo(), let config = config() else { return }
        guard let url = URL(string: "\(config.url)/functions/v1/enrich-pattern") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(auth.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["pattern_id": patternId])
        request.timeoutInterval = 10
        _ = try? await URLSession.shared.data(for: request)
    }

    /// Calls RPC increment_ai_usage for the current user. Returns true if increment succeeded (used for entitlement).
    static func incrementAIUsage() async -> Bool {
        guard let auth = await freshAuthInfo(), let config = config() else { return false }
        guard let url = URL(string: "\(config.url)/rest/v1/rpc/increment_ai_usage") else { return false }
        let payload: [String: Any] = ["p_user_id": auth.userId]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: payload) else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(auth.accessToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return false }
            if let json = try? JSONSerialization.jsonObject(with: data) as? Int, json >= 0 { return true }
            return false
        } catch {
            return false
        }
    }
}
