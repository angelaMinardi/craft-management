//
//  OfflineCacheService.swift
//  PatternVault
//
//  Generic JSON file cache in app group container for offline access.
//  Follows the same pattern as PatternListCacheService.
//

import Foundation

enum OfflineCacheService {
    private static let suiteName = "group.com.patternvault.app"

    private static func fileURL(key: String) -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: suiteName)?
            .appendingPathComponent("offline_cache_\(key).json")
    }

    static func save<T: Encodable>(_ data: T, key: String) {
        guard let url = fileURL(key: key),
              let encoded = try? JSONEncoder().encode(data) else { return }
        try? encoded.write(to: url)
    }

    static func load<T: Decodable>(key: String, as type: T.Type) -> T? {
        guard let url = fileURL(key: key),
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(T.self, from: data) else { return nil }
        return decoded
    }

    static func remove(key: String) {
        guard let url = fileURL(key: key) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
