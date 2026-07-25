//
//  OfflineCacheService.swift
//  PatternVault
//
//  Generic JSON file cache in app group container for offline access.
//  Follows the same pattern as PatternListCacheService.
//

import Foundation

enum OfflineCacheService {
    private static let suiteName = "group.com.corvidcraft.app"
    private static let defaultTTL: TimeInterval = 24 * 60 * 60

    private struct CacheEnvelope<T: Codable>: Codable {
        let cachedAt: Date
        let value: T
    }

    private static func fileURL(key: String) -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: suiteName)?
            .appendingPathComponent("offline_cache_\(key).json")
    }

    static func save<T: Codable>(_ data: T, key: String) {
        guard let url = fileURL(key: key) else { return }
        do {
            let envelope = CacheEnvelope(cachedAt: Date(), value: data)
            let encoded = try JSONEncoder().encode(envelope)
            try encoded.write(to: url, options: .atomic)
        } catch {
            NSLog("[OfflineCache] Failed to save \(key): \(error)")
        }
    }

    static func load<T: Codable>(key: String, as type: T.Type, ttl: TimeInterval = defaultTTL) -> T? {
        guard let url = fileURL(key: key),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            if let envelope = try? JSONDecoder().decode(CacheEnvelope<T>.self, from: data) {
                guard Date().timeIntervalSince(envelope.cachedAt) <= ttl else {
                    try? FileManager.default.removeItem(at: url)
                    return nil
                }
                return envelope.value
            }
            let legacy = try JSONDecoder().decode(T.self, from: data)
            save(legacy, key: key)
            return legacy
        } catch {
            NSLog("[OfflineCache] Failed to load \(key): \(error)")
            return nil
        }
    }

    static func remove(key: String) {
        guard let url = fileURL(key: key) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
