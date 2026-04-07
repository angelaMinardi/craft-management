//
//  PatternListCacheService.swift
//  PatternVault
//
//  Caches pattern list to App Group for offline display; read on launch, write on successful fetch.
//

import Foundation

enum PatternListCacheService {
    private static let suiteName = "group.com.patternvault.app"
    private static let cacheFileNamePrefix = "pattern_list_cache_"

    static func loadCachedPatterns(userId: UUID) -> [Pattern]? {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: suiteName) else { return nil }
        let file = container.appendingPathComponent("\(cacheFileNamePrefix)\(userId.uuidString).json")
        guard FileManager.default.fileExists(atPath: file.path),
              let data = try? Data(contentsOf: file),
              let decoded = try? JSONDecoder().decode([Pattern].self, from: data) else { return nil }
        return decoded
    }

    static func saveCachedPatterns(userId: UUID, patterns: [Pattern]) {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: suiteName),
              let data = try? JSONEncoder().encode(patterns) else { return }
        let file = container.appendingPathComponent("\(cacheFileNamePrefix)\(userId.uuidString).json")
        try? data.write(to: file)
    }
}
