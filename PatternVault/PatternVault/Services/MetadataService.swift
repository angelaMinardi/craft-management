//
//  MetadataService.swift
//  PatternVault
//

import Foundation
import LinkPresentation

struct PatternMetadata: Sendable {
    let title: String?
    let description: String?
    let imageUrl: String?
}

enum MetadataService {

    // MARK: - Public

    static func fetch(urlString: String) async -> PatternMetadata? {
        guard let url = URL(string: urlString) else { return nil }

        if isRavelryURL(url) {
            if let metadata = await fetchRavelryMetadata(url: url) {
                return metadata
            }
        }

        return await fetchLinkPresentation(url: url)
    }

    // MARK: - LinkPresentation (general)

    private static func fetchLinkPresentation(url: URL) async -> PatternMetadata? {
        let provider = LPMetadataProvider()
        provider.timeout = 10

        do {
            let metadata = try await provider.startFetchingMetadata(for: url)
            let title = metadata.title
            let description = metadata.value(forKey: "summary") as? String

            var imageUrl: String?
            if let imageProvider = metadata.imageProvider {
                imageUrl = await extractImageUrl(from: imageProvider)
            }

            if title == nil && description == nil && imageUrl == nil {
                return nil
            }
            return PatternMetadata(title: title, description: description, imageUrl: imageUrl)
        } catch {
            return nil
        }
    }

    private static func extractImageUrl(from provider: NSItemProvider) async -> String? {
        // LPMetadataProvider gives us an NSItemProvider for the image.
        // We load it as Data, upload to Supabase Storage, and return the public URL.
        // For now, we skip uploading and just return nil for the image
        // since AsyncImage can't load from NSItemProvider directly.
        // A future enhancement could upload to Supabase storage.
        return nil
    }

    // MARK: - Ravelry API

    private static func isRavelryURL(_ url: URL) -> Bool {
        url.host?.lowercased().contains("ravelry") == true
    }

    private static func extractPermalink(from url: URL) -> String? {
        // URL format: https://www.ravelry.com/patterns/library/cozy-cardigan
        let components = url.pathComponents
        guard let libraryIndex = components.firstIndex(of: "library"),
              libraryIndex + 1 < components.count else { return nil }
        return components[libraryIndex + 1]
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

    private static func fetchRavelryMetadata(url: URL) async -> PatternMetadata? {
        guard let permalink = extractPermalink(from: url),
              let creds = ravelryCredentials() else { return nil }

        // Search by permalink
        guard let searchUrl = URL(string: "https://api.ravelry.com/patterns/search.json?query=\(permalink)") else { return nil }

        var request = URLRequest(url: searchUrl)
        let authString = "\(creds.accessKey):\(creds.personalKey)"
        if let authData = authString.data(using: .utf8) {
            request.setValue("Basic \(authData.base64EncodedString())", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return nil }

            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let patterns = json?["patterns"] as? [[String: Any]],
                  let first = patterns.first(where: { ($0["permalink"] as? String) == permalink }) else {
                return nil
            }

            let patternId = first["id"] as? Int
            let name = first["name"] as? String

            // If we got an ID, fetch full details
            if let patternId {
                return await fetchRavelryPatternDetail(id: patternId, creds: creds, fallbackName: name)
            }

            // Fallback to search result
            let photoUrl = extractRavelryPhotoUrl(from: first)
            return PatternMetadata(title: name, description: nil, imageUrl: photoUrl)
        } catch {
            return nil
        }
    }

    private static func fetchRavelryPatternDetail(id: Int, creds: (accessKey: String, personalKey: String), fallbackName: String?) async -> PatternMetadata? {
        guard let url = URL(string: "https://api.ravelry.com/patterns/\(id).json") else { return nil }

        var request = URLRequest(url: url)
        let authString = "\(creds.accessKey):\(creds.personalKey)"
        if let authData = authString.data(using: .utf8) {
            request.setValue("Basic \(authData.base64EncodedString())", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return nil }

            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let pattern = json?["pattern"] as? [String: Any] else { return nil }

            let name = pattern["name"] as? String ?? fallbackName
            let notes = pattern["notes_html"] as? String ?? pattern["notes"] as? String
            let description = cleanHTML(notes)
            let photoUrl = extractRavelryPhotoUrl(from: pattern)

            return PatternMetadata(title: name, description: description, imageUrl: photoUrl)
        } catch {
            return nil
        }
    }

    private static func extractRavelryPhotoUrl(from json: [String: Any]) -> String? {
        if let firstPhoto = (json["photos"] as? [[String: Any]])?.first,
           let mediumUrl = firstPhoto["medium_url"] as? String {
            return mediumUrl
        }
        if let firstPhoto = (json["photos"] as? [[String: Any]])?.first,
           let medium2Url = firstPhoto["medium2_url"] as? String {
            return medium2Url
        }
        return nil
    }

    private static func cleanHTML(_ html: String?) -> String? {
        guard let html, !html.isEmpty else { return nil }
        guard let data = html.data(using: .utf8),
              let attributed = try? NSAttributedString(
                  data: data,
                  options: [.documentType: NSAttributedString.DocumentType.html,
                            .characterEncoding: String.Encoding.utf8.rawValue],
                  documentAttributes: nil
              ) else { return html }
        let plain = attributed.string.trimmingCharacters(in: .whitespacesAndNewlines)
        // Truncate very long descriptions
        if plain.count > 500 {
            return String(plain.prefix(500)) + "..."
        }
        return plain.isEmpty ? nil : plain
    }
}
