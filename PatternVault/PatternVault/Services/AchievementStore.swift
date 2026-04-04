//
//  AchievementStore.swift
//  PatternVault
//
//  Singleton store managing badge evaluation and unlock state.
//

import Foundation

@MainActor
final class AchievementStore: ObservableObject {
    static let shared = AchievementStore()

    private static let appGroupId = "group.com.patternvault.app"
    private static let progressKey = "achievement_progress"

    @Published private(set) var progress: AchievementProgress
    @Published var showBadgeUnlockedBanner = false

    private let defaults: UserDefaults

    private init() {
        defaults = UserDefaults(suiteName: Self.appGroupId) ?? .standard
        if let data = defaults.data(forKey: Self.progressKey),
           let decoded = try? JSONDecoder().decode(AchievementProgress.self, from: data) {
            progress = decoded
        } else {
            progress = AchievementProgress()
        }
    }

    func evaluateUnlocks(
        savedCount: Int,
        completedCount: Int,
        streak: Int,
        hasAnyNote: Bool
    ) {
        tryUnlock("first_stitch", condition: savedCount >= 1)
        tryUnlock("hat_trick", condition: completedCount >= 3)
        tryUnlock("stash_buster", condition: savedCount >= 10)
        tryUnlock("collector", condition: savedCount >= 25)
        tryUnlock("streak_starter", condition: streak >= 3)
        tryUnlock("week_warrior", condition: streak >= 7)
        tryUnlock("fortnight_friend", condition: streak >= 14)
        tryUnlock("note_taker", condition: hasAnyNote)
        tryUnlock("treat_master", condition: progress.totalFeedCount >= 20)
        tryUnlock("thread_baron", condition: progress.totalThreadPointsEarned >= 100)
    }

    func incrementFeedCount() {
        progress.totalFeedCount += 1
        persist()
    }

    func incrementTotalPointsEarned(by delta: Int) {
        guard delta > 0 else { return }
        progress.totalThreadPointsEarned += delta
        persist()
    }

    func markSeen(badgeId: String) {
        if progress.pendingBadgeId == badgeId {
            progress.pendingBadgeId = nil
            showBadgeUnlockedBanner = false
            persist()
        }
    }

    func badge(for id: String?) -> AchievementBadge? {
        guard let id else { return nil }
        return AchievementCatalog.allBadges.first(where: { $0.id == id })
    }

    #if DEBUG
    func resetForDebug() {
        progress = AchievementProgress()
        showBadgeUnlockedBanner = false
        persist()
    }
    #endif

    private func tryUnlock(_ badgeId: String, condition: Bool) {
        guard condition else { return }
        guard !progress.unlockedIds.contains(badgeId) else { return }
        progress.unlockedIds.insert(badgeId)
        progress.unlockedDates[badgeId] = Date()
        progress.pendingBadgeId = badgeId
        showBadgeUnlockedBanner = true
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(progress) {
            defaults.set(data, forKey: Self.progressKey)
        }
    }
}
