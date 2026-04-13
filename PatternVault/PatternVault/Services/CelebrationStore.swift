//
//  CelebrationStore.swift
//  PatternVault
//
//  Optional milestone celebrations: one-time overlays with mascot when user hits
//  first pattern, vault of 10, first stash item, first tool, first note. Toggle in Settings.
//

import Foundation
import SwiftUI

/// Used for fullScreenCover(item:) so overlay content is stable.
struct PendingMilestone: Identifiable {
    var id: String { milestoneId }
    let milestoneId: String
}

@MainActor
final class CelebrationStore: ObservableObject {
    static let shared = CelebrationStore()

    private static let appGroupId = "group.com.patternvault.app"
    private static let unlockedKey = "CelebrationStore.unlockedMilestoneIds"
    private static let pendingKey = "CelebrationStore.pendingMilestoneId"
    private static let enabledKey = "CelebrationStore.celebrationsEnabled"

    private let defaults: UserDefaults

    @Published private(set) var unlockedMilestoneIds: Set<String> = []
    @Published var pendingMilestone: PendingMilestone? {
        didSet {
            defaults.set(pendingMilestone?.milestoneId, forKey: Self.pendingKey)
        }
    }

    var celebrationsEnabled: Bool {
        get {
            if defaults.object(forKey: Self.enabledKey) == nil { return true }
            return defaults.bool(forKey: Self.enabledKey)
        }
        set {
            defaults.set(newValue, forKey: Self.enabledKey)
            objectWillChange.send()
        }
    }

    private init() {
        defaults = UserDefaults(suiteName: Self.appGroupId) ?? .standard
        if let raw = defaults.array(forKey: Self.unlockedKey) as? [String] {
            unlockedMilestoneIds = Set(raw)
        }
        if let id = defaults.string(forKey: Self.pendingKey) {
            pendingMilestone = PendingMilestone(milestoneId: id)
        }
    }

    /// Call when a milestone is reached. Returns true only when this call unlocked it.
    @discardableResult
    func unlock(_ id: String) -> Bool {
        guard !id.isEmpty else { return false }
        guard !unlockedMilestoneIds.contains(id) else { return false }
        var next = unlockedMilestoneIds
        next.insert(id)
        unlockedMilestoneIds = next
        defaults.set(Array(unlockedMilestoneIds), forKey: Self.unlockedKey)
        if celebrationsEnabled {
            pendingMilestone = PendingMilestone(milestoneId: id)
        }
        return true
    }

    func clearPending() {
        pendingMilestone = nil
    }

    /// Title and subtitle for overlay. Nil if unknown id.
    static func title(for milestoneId: String) -> String? {
        switch milestoneId {
        case "first_pattern": return "The crow found another pattern!"
        case "vault_10": return "10 patterns!"
        case "stash_started": return "Stash started!"
        case "toolbox_ready": return "Toolbox ready!"
        case "first_note": return "First note!"
        case "progress_25": return "Quarter of the way there!"
        case "progress_50": return "Halfway point!"
        case "progress_75": return "Almost there!"
        case "progress_100": return "You finished!"
        default: return nil
        }
    }

    static func subtitle(for milestoneId: String) -> String? {
        switch milestoneId {
        case "first_pattern": return "Your vault is open."
        case "vault_10": return "Your vault is growing."
        case "stash_started": return "You're ready for the next project."
        case "toolbox_ready": return "Your first tool is in."
        case "first_note": return "You're tracking your makes."
        case "progress_25": return "Keep the momentum going."
        case "progress_50": return "The finish line is in sight."
        case "progress_75": return "You've got this!"
        case "progress_100": return "Time to celebrate your finished piece."
        default: return nil
        }
    }

    /// All known milestone ids in display order (for Settings "Unlocked" list).
    static let knownMilestoneIds: [String] = [
        "first_pattern",
        "vault_10",
        "stash_started",
        "toolbox_ready",
        "first_note",
        "progress_25",
        "progress_50",
        "progress_75",
        "progress_100"
    ]
}
