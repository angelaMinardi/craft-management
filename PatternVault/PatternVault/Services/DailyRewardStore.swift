//
//  DailyRewardStore.swift
//  PatternVault
//
//  Daily check-in rewards and hearts/streak decay for re-engagement.
//

import Foundation

struct DailyRewardResult {
    let pointsGranted: Int
    let consecutiveDay: Int
}

@MainActor
final class DailyRewardStore: ObservableObject {
    static let shared = DailyRewardStore()

    private static let appGroupId = "group.com.patternvault.app"
    private static let lastClaimKey = "daily_reward_last_claim_date"
    private static let consecutiveKey = "daily_reward_consecutive_days"
    private static let lastInteractionKey = "daily_reward_last_interaction_date"

    @Published private(set) var consecutiveDays: Int

    private let defaults: UserDefaults
    private let calendar = Calendar.current

    private init() {
        defaults = UserDefaults(suiteName: Self.appGroupId) ?? .standard
        consecutiveDays = max(0, defaults.integer(forKey: Self.consecutiveKey))
    }

    /// Call once per app launch. Returns reward info if daily bonus hasn't been claimed today.
    func checkIn() -> DailyRewardResult? {
        let today = calendar.startOfDay(for: Date())

        if let lastClaim = defaults.object(forKey: Self.lastClaimKey) as? Date {
            let lastDay = calendar.startOfDay(for: lastClaim)
            if lastDay == today {
                return nil // already claimed today
            }
            let daysBetween = calendar.dateComponents([.day], from: lastDay, to: today).day ?? 0
            if daysBetween == 1 {
                consecutiveDays += 1
            } else {
                consecutiveDays = 1
            }
        } else {
            consecutiveDays = 1
        }

        defaults.set(today, forKey: Self.lastClaimKey)
        defaults.set(consecutiveDays, forKey: Self.consecutiveKey)

        let bonus = min(5 + (consecutiveDays - 1), 10)
        return DailyRewardResult(pointsGranted: bonus, consecutiveDay: consecutiveDays)
    }

    /// Reduce hearts if user hasn't interacted recently. Call on app foreground.
    func applyHeartsDecay(mascotStore: MascotInteractionStore) {
        guard let lastInteraction = defaults.object(forKey: Self.lastInteractionKey) as? Date else { return }
        let hours = Date().timeIntervalSince(lastInteraction) / 3600
        if hours > 48 {
            mascotStore.applyHeartDecay(2)
        } else if hours > 24 {
            mascotStore.applyHeartDecay(1)
        }
    }

    /// Reset streak if user hasn't interacted in 48+ hours.
    func applyStreakDecay(mascotStore: MascotInteractionStore) {
        guard let lastInteraction = defaults.object(forKey: Self.lastInteractionKey) as? Date else { return }
        let hours = Date().timeIntervalSince(lastInteraction) / 3600
        if hours > 48 {
            mascotStore.resetStreak()
        }
    }

    /// Record a pet or feed interaction timestamp.
    func recordInteraction() {
        defaults.set(Date(), forKey: Self.lastInteractionKey)
    }
}
