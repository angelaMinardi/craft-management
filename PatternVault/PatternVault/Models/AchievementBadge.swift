//
//  AchievementBadge.swift
//  PatternVault
//

import Foundation

enum BadgeCategory: String, Codable, CaseIterable {
    case patterns, streaks, social, economy
}

struct AchievementBadge: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let description: String
    let emoji: String
    let hint: String
    let category: BadgeCategory
}

struct AchievementProgress: Codable {
    var unlockedIds: Set<String> = []
    var unlockedDates: [String: Date] = [:]
    var pendingBadgeId: String?
    var totalFeedCount: Int = 0
    var totalThreadPointsEarned: Int = 0
}

enum AchievementCatalog {
    static let allBadges: [AchievementBadge] = [
        AchievementBadge(id: "first_stitch", title: "First Stitch", description: "Save your first pattern", emoji: "🪡", hint: "Save a pattern to unlock", category: .patterns),
        AchievementBadge(id: "hat_trick", title: "Hat Trick", description: "Complete 3 patterns", emoji: "🎩", hint: "Complete more patterns", category: .patterns),
        AchievementBadge(id: "stash_buster", title: "Stash Buster", description: "Save 10 patterns", emoji: "🧶", hint: "Keep saving patterns", category: .patterns),
        AchievementBadge(id: "collector", title: "Collector", description: "Save 25 patterns", emoji: "📚", hint: "Build your collection", category: .patterns),
        AchievementBadge(id: "streak_starter", title: "Streak Starter", description: "Reach a 3-day streak", emoji: "🔥", hint: "Keep your streak going", category: .streaks),
        AchievementBadge(id: "week_warrior", title: "Week Warrior", description: "Reach a 7-day streak", emoji: "⚡", hint: "A full week of crafting", category: .streaks),
        AchievementBadge(id: "fortnight_friend", title: "Fortnight Friend", description: "Reach a 14-day streak", emoji: "🌟", hint: "Two weeks strong", category: .streaks),
        AchievementBadge(id: "note_taker", title: "Note Taker", description: "Write your first project note", emoji: "📝", hint: "Add a note to a pattern", category: .social),
        AchievementBadge(id: "treat_master", title: "Treat Master", description: "Feed your mascot 20 times", emoji: "🍬", hint: "Keep feeding treats", category: .economy),
        AchievementBadge(id: "thread_baron", title: "Thread Baron", description: "Earn 100 thread points total", emoji: "💰", hint: "Earn more thread points", category: .economy),
    ]
}
