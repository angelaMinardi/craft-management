//
//  LifetimeOfferService.swift
//  PatternVault
//
//  Reads app_config.lifetime_offer_enabled / lifetime_buyer_count from Supabase.
//  The launch lifetime SKU is available May 1, 2026 → Nov 1, 2026 or until the
//  buyer cap is hit. When the flag is false the PaywallView hides the lifetime card.
//
//  Mirrors the caching pattern from AIKillSwitchService (10-min TTL, App Group backed).
//

import Foundation
import Supabase

private struct LifetimeConfigRow: Decodable {
    let lifetimeOfferEnabled: Bool
    let lifetimeBuyerCount: Int
    let lifetimeBuyerCap: Int
    let lifetimeOfferStartsAt: Date
    let lifetimeOfferEndsAt: Date
    enum CodingKeys: String, CodingKey {
        case lifetimeOfferEnabled = "lifetime_offer_enabled"
        case lifetimeBuyerCount = "lifetime_buyer_count"
        case lifetimeBuyerCap = "lifetime_buyer_cap"
        case lifetimeOfferStartsAt = "lifetime_offer_starts_at"
        case lifetimeOfferEndsAt = "lifetime_offer_ends_at"
    }
}

/// Snapshot of the current lifetime offer state, suitable for paywall display.
struct LifetimeOfferState: Equatable {
    let isAvailable: Bool
    let buyerCount: Int
    let buyerCap: Int
    let startsAt: Date
    let endsAt: Date

    /// Days remaining until the offer ends (min 0). Only surface in the final 14 days.
    var daysRemaining: Int {
        let seconds = endsAt.timeIntervalSinceNow
        return max(0, Int(seconds / 86_400))
    }

    /// Whether the offer has started (window is time-gated on the front edge too).
    var hasStarted: Bool {
        Date() >= startsAt
    }

    /// What to show in the paywall — returns nil when offer isn't available to the user.
    var displayAvailability: Bool {
        isAvailable && hasStarted
    }

    static let unavailable = LifetimeOfferState(
        isAvailable: false,
        buyerCount: 0,
        buyerCap: 1000,
        startsAt: .distantFuture,
        endsAt: .distantFuture
    )
}

enum LifetimeOfferService {
    private static let appGroupId = "group.com.corvidcraft.app"
    private static let cacheKeyEnabled = "lifetime_offer_enabled"
    private static let cacheKeyBuyerCount = "lifetime_offer_buyer_count"
    private static let cacheKeyBuyerCap = "lifetime_offer_buyer_cap"
    private static let cacheKeyStarts = "lifetime_offer_starts_at"
    private static let cacheKeyEnds = "lifetime_offer_ends_at"
    private static let cacheKeyUpdated = "lifetime_offer_updated"
    private static let cacheTTL: TimeInterval = 10 * 60

    private static let lock = NSLock()
    private static var inMemory: LifetimeOfferState?
    private static var inMemoryUpdated: Date?

    /// Current cached state. Defaults to `.unavailable` if never fetched — fails
    /// closed so the lifetime card never shows when we can't confirm availability.
    static var currentState: LifetimeOfferState {
        lock.withLock {
            if let value = inMemory, let updated = inMemoryUpdated, Date().timeIntervalSince(updated) < cacheTTL {
                return value
            }
            if let disk = readFromAppGroup() {
                inMemory = disk.state
                inMemoryUpdated = disk.updated
                return disk.state
            }
            return .unavailable
        }
    }

    /// Fetch from Supabase and update caches. Safe to call on every app launch / foreground.
    @MainActor
    static func refresh() async {
        do {
            // Server-side expiry check first (no-op if already expired)
            _ = try? await SupabaseManager.client
                .rpc("expire_lifetime_offer_if_past_end_date")
                .execute()

            let rows: [LifetimeConfigRow] = try await SupabaseManager.client
                .from("app_config")
                .select("lifetime_offer_enabled, lifetime_buyer_count, lifetime_buyer_cap, lifetime_offer_starts_at, lifetime_offer_ends_at")
                .eq("id", value: 1)
                .execute()
                .value

            guard let row = rows.first else { return }
            let state = LifetimeOfferState(
                isAvailable: row.lifetimeOfferEnabled,
                buyerCount: row.lifetimeBuyerCount,
                buyerCap: row.lifetimeBuyerCap,
                startsAt: row.lifetimeOfferStartsAt,
                endsAt: row.lifetimeOfferEndsAt
            )
            lock.withLock {
                inMemory = state
                inMemoryUpdated = Date()
            }
            writeToAppGroup(state: state, updated: Date())
        } catch {
            #if DEBUG
            print("[LifetimeOffer] Refresh failed: \(error); leaving cache as-is")
            #endif
        }
    }

    /// Called after a successful lifetime purchase — increments the server counter,
    /// auto-disables when the cap is hit, and returns the new state.
    @MainActor
    @discardableResult
    static func recordPurchase() async -> LifetimeOfferState? {
        struct RecordResult: Decodable {
            let buyerCount: Int
            let offerEnabled: Bool
            enum CodingKeys: String, CodingKey {
                case buyerCount = "buyer_count"
                case offerEnabled = "offer_enabled"
            }
        }
        do {
            let rows: [RecordResult] = try await SupabaseManager.client
                .rpc("record_lifetime_purchase")
                .execute()
                .value
            guard let row = rows.first else { return nil }
            await refresh()
            return LifetimeOfferState(
                isAvailable: row.offerEnabled,
                buyerCount: row.buyerCount,
                buyerCap: currentState.buyerCap,
                startsAt: currentState.startsAt,
                endsAt: currentState.endsAt
            )
        } catch {
            #if DEBUG
            print("[LifetimeOffer] Record purchase failed: \(error)")
            #endif
            return nil
        }
    }

    // MARK: - App Group cache

    private static func readFromAppGroup() -> (state: LifetimeOfferState, updated: Date)? {
        let d = UserDefaults(suiteName: appGroupId)
        guard let updated = d?.object(forKey: cacheKeyUpdated) as? Date,
              Date().timeIntervalSince(updated) < cacheTTL else {
            return nil
        }
        let starts = d?.object(forKey: cacheKeyStarts) as? Date ?? .distantFuture
        let ends = d?.object(forKey: cacheKeyEnds) as? Date ?? .distantFuture
        let state = LifetimeOfferState(
            isAvailable: d?.bool(forKey: cacheKeyEnabled) ?? false,
            buyerCount: d?.integer(forKey: cacheKeyBuyerCount) ?? 0,
            buyerCap: d?.integer(forKey: cacheKeyBuyerCap) ?? 1000,
            startsAt: starts,
            endsAt: ends
        )
        return (state, updated)
    }

    private static func writeToAppGroup(state: LifetimeOfferState, updated: Date) {
        let d = UserDefaults(suiteName: appGroupId)
        d?.set(state.isAvailable, forKey: cacheKeyEnabled)
        d?.set(state.buyerCount, forKey: cacheKeyBuyerCount)
        d?.set(state.buyerCap, forKey: cacheKeyBuyerCap)
        d?.set(state.startsAt, forKey: cacheKeyStarts)
        d?.set(state.endsAt, forKey: cacheKeyEnds)
        d?.set(updated, forKey: cacheKeyUpdated)
        d?.synchronize()
    }
}
