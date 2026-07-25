//
//  PatternListCacheService.swift
//  PatternVault
//
//  Caches pattern list to App Group for offline display; read on launch, write on successful fetch.
//

import Foundation

enum PatternListCacheService {
    private static let suiteName = "group.com.corvidcraft.app"
    private static let cacheFileNamePrefix = "pattern_list_cache_"
    private static let cacheTTL: TimeInterval = 24 * 60 * 60

    private struct CacheEnvelope: Codable {
        let cachedAt: Date
        let patterns: [Pattern]
    }

    static func loadCachedPatterns(userId: UUID) -> [Pattern]? {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: suiteName) else { return nil }
        let file = container.appendingPathComponent("\(cacheFileNamePrefix)\(userId.uuidString).json")
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        do {
            let data = try Data(contentsOf: file)
            if let envelope = try? JSONDecoder().decode(CacheEnvelope.self, from: data) {
                guard Date().timeIntervalSince(envelope.cachedAt) <= cacheTTL else {
                    try? FileManager.default.removeItem(at: file)
                    return nil
                }
                return envelope.patterns
            }
            let legacy = try JSONDecoder().decode([Pattern].self, from: data)
            saveCachedPatterns(userId: userId, patterns: legacy)
            return legacy
        } catch {
            NSLog("[PatternListCache] Failed to load cached patterns: \(error)")
            return nil
        }
    }

    static func saveCachedPatterns(userId: UUID, patterns: [Pattern]) {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: suiteName) else { return }
        let file = container.appendingPathComponent("\(cacheFileNamePrefix)\(userId.uuidString).json")
        do {
            let envelope = CacheEnvelope(cachedAt: Date(), patterns: patterns)
            let data = try JSONEncoder().encode(envelope)
            try data.write(to: file, options: .atomic)
        } catch {
            NSLog("[PatternListCache] Failed to save cached patterns: \(error)")
        }
    }
}
