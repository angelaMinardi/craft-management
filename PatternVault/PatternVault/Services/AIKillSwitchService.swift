//
//  AIKillSwitchService.swift
//  PatternVault
//
//  Reads app_config.ai_enabled from Supabase. When false, AI is disabled app-wide
//  (Share Extension + main app) to cap cost. Flip in Supabase Dashboard → Table Editor.
//

import Foundation
import Supabase

private struct AppConfigRow: Decodable {
    let aiEnabled: Bool
    enum CodingKeys: String, CodingKey {
        case aiEnabled = "ai_enabled"
    }
}

enum AIKillSwitchService {
    private static let appGroupId = "group.com.patternvault.app"
    private static let cacheKeyEnabled = "app_config_ai_enabled"
    private static let cacheKeyUpdated = "app_config_ai_enabled_updated"
    /// Cache valid for 10 minutes; refresh on app active.
    private static let cacheTTL: TimeInterval = 10 * 60

    private static let lock = NSLock()
    private static var inMemoryEnabled: Bool?
    private static var inMemoryUpdated: Date?

    /// Whether AI is allowed (kill switch off). Default true if never fetched or on error.
    static var isAIEnabled: Bool {
        lock.lock()
        defer { lock.unlock() }
        if let value = inMemoryEnabled, let updated = inMemoryUpdated, Date().timeIntervalSince(updated) < cacheTTL {
            return value
        }
        // Fallback: read from App Group (main app or extension may have written)
        let defaults = UserDefaults(suiteName: appGroupId)
        let updated = defaults?.object(forKey: cacheKeyUpdated) as? Date
        if let updated, Date().timeIntervalSince(updated) < cacheTTL,
           defaults?.object(forKey: cacheKeyEnabled) != nil {
            let value = defaults?.bool(forKey: cacheKeyEnabled) ?? true
            inMemoryEnabled = value
            inMemoryUpdated = updated
            return value
        }
        return true
    }

    /// Fetches from Supabase and updates cache + App Group. Call on app launch / foreground.
    @MainActor
    static func refresh() async {
        do {
            let rows: [AppConfigRow] = try await SupabaseManager.client
                .from("app_config")
                .select("ai_enabled")
                .eq("id", value: 1)
                .execute()
                .value
            let enabled = rows.first?.aiEnabled ?? true
            lock.lock()
            inMemoryEnabled = enabled
            inMemoryUpdated = Date()
            lock.unlock()
            let defaults = UserDefaults(suiteName: appGroupId)
            defaults?.set(enabled, forKey: cacheKeyEnabled)
            defaults?.set(Date(), forKey: cacheKeyUpdated)
            defaults?.synchronize()
        } catch {
            #if DEBUG
            print("[AIKillSwitch] Refresh failed: \(error); leaving cache as-is")
            #endif
        }
    }
}
