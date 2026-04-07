//
//  MascotInteractionStore.swift
//  PatternVault
//
//  Local-first mascot interaction state for dashboard pet/treat behavior.
//

import Foundation
import SwiftUI
import UIKit

@MainActor
final class MascotInteractionStore: ObservableObject {
    static let shared = MascotInteractionStore()

    enum Pose {
        case idle
        case knitting
        case jumping
        case pouty
        case petting
    }

    struct TreatItem: Identifiable, Codable, Hashable {
        let id: String
        let title: String
        let iconAssetName: String
    }

    private static let appGroupId = "group.com.patternvault.app"
    private static let nameKey = "mascot_name"
    private static let onboardingNameKey = "onboarding_companion_name"
    private static let heartsKey = "mascot_hearts_current"
    private static let streakKey = "mascot_streak_count"
    private static let inventoryKey = "mascot_treat_inventory"
    private static let lastPetKey = "mascot_last_interaction_at"
    private static let currencyKey = "mascot_thread_points"
    private static let explainKey = "mascot_has_seen_explanation"
    private static let decorationKey = "mascot_selected_decoration"
    private static let ownedDecorationsKey = "mascot_owned_decorations"

    private let defaults: UserDefaults
    private let heartCap = 5
    private let petCooldownSeconds: TimeInterval = 12

    let availableTreats: [TreatItem] = MascotEconomyCatalog.storeItemsWithCustomArt.compactMap { item in
        guard let iconAssetName = item.iconAssetName else { return nil }
        return TreatItem(id: item.id, title: item.title, iconAssetName: iconAssetName)
    }

    @Published var mascotName: String
    @Published var heartsCurrent: Int
    @Published var streakCount: Int
    @Published var pose: Pose = .idle
    @Published var transientMessage: String?
    @Published private(set) var treatInventory: [String: Int]
    @Published var threadPoints: Int
    @Published var hasSeenExplanations: Bool
    @Published var selectedDecorationId: String?
    @Published private(set) var ownedDecorationIds: Set<String>

    private init() {
        defaults = UserDefaults(suiteName: Self.appGroupId) ?? .standard
        let onboardingName = UserDefaults.standard.string(forKey: Self.onboardingNameKey)
            ?? defaults.string(forKey: Self.onboardingNameKey)
        let existingMascotName = defaults.string(forKey: Self.nameKey)
        if let onboardingName, !onboardingName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            mascotName = onboardingName
            defaults.set(onboardingName, forKey: Self.nameKey)
        } else {
            mascotName = existingMascotName ?? "Pip"
        }
        let storedHearts = defaults.integer(forKey: Self.heartsKey)
        heartsCurrent = storedHearts > 0 ? min(storedHearts, heartCap) : 4
        streakCount = max(0, defaults.integer(forKey: Self.streakKey))
        threadPoints = max(0, defaults.integer(forKey: Self.currencyKey))
        hasSeenExplanations = defaults.bool(forKey: Self.explainKey)
        selectedDecorationId = defaults.string(forKey: Self.decorationKey)
        if let data = defaults.data(forKey: Self.inventoryKey),
           let decoded = try? JSONDecoder().decode([String: Int].self, from: data) {
            treatInventory = decoded
        } else {
            treatInventory = ["yarn_treat": 2, "button_treat": 2, "thimble_treat": 1]
        }
        if let data = defaults.data(forKey: Self.ownedDecorationsKey),
           let decoded = try? JSONDecoder().decode(Set<String>.self, from: data) {
            ownedDecorationIds = decoded
        } else {
            ownedDecorationIds = []
        }
    }

    var heartsMax: Int { heartCap }

    func setName(_ value: String) {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        mascotName = String(cleaned.prefix(20))
        defaults.set(mascotName, forKey: Self.nameKey)
        UserDefaults.standard.set(mascotName, forKey: Self.onboardingNameKey)
        defaults.set(mascotName, forKey: Self.onboardingNameKey)
    }

    func syncFallbackCounts(patterns: [Pattern]) {
        if streakCount == 0 {
            let fallback = patterns.filter { $0.status == .inProgress }.count
            if fallback > 0 {
                streakCount = fallback
                defaults.set(streakCount, forKey: Self.streakKey)
            }
        }
    }

    func pet() {
        let now = Date()
        if let last = defaults.object(forKey: Self.lastPetKey) as? Date,
           now.timeIntervalSince(last) < petCooldownSeconds {
            return
        }

        defaults.set(now, forKey: Self.lastPetKey)
        heartsCurrent = min(heartCap, heartsCurrent + 1)
        defaults.set(heartsCurrent, forKey: Self.heartsKey)
        addThreadPoints(1)
        DailyRewardStore.shared.recordInteraction()

        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        transientMessage = "\(mascotName) likes that!"
        animateTemporaryPose(.petting)
    }

    func feed(treatId: String) {
        guard let qty = treatInventory[treatId], qty > 0 else {
            transientMessage = "\(mascotName) wants a different treat."
            animateTemporaryPose(.pouty)
            return
        }

        treatInventory[treatId] = qty - 1
        persistInventory()

        let heartBonus = MascotEconomyCatalog.item(for: treatId)?.heartBonus ?? 1
        heartsCurrent = min(heartCap, heartsCurrent + heartBonus)
        defaults.set(heartsCurrent, forKey: Self.heartsKey)
        streakCount += 1
        defaults.set(streakCount, forKey: Self.streakKey)
        addThreadPoints(2)
        AchievementStore.shared.incrementFeedCount()
        DailyRewardStore.shared.recordInteraction()

        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        let bonusText = heartBonus > 1 ? " (+\(heartBonus) hearts!)" : ""
        transientMessage = "Yum! \(mascotName) feels encouraged.\(bonusText)"
        animateTemporaryPose(.knitting)
    }

    func markExplanationsSeen() {
        hasSeenExplanations = true
        defaults.set(true, forKey: Self.explainKey)
    }

    func purchaseTreat(_ itemId: String, cost: Int) -> Bool {
        guard threadPoints >= cost else { return false }
        threadPoints -= cost
        defaults.set(threadPoints, forKey: Self.currencyKey)
        treatInventory[itemId, default: 0] += 1
        persistInventory()
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        transientMessage = "Purchased \(displayName(for: itemId))."
        return true
    }

    func purchaseDecoration(_ itemId: String, cost: Int) -> Bool {
        guard threadPoints >= cost else { return false }
        guard !ownedDecorationIds.contains(itemId) else { return false }
        threadPoints -= cost
        defaults.set(threadPoints, forKey: Self.currencyKey)
        ownedDecorationIds.insert(itemId)
        persistOwnedDecorations()
        selectedDecorationId = itemId
        defaults.set(itemId, forKey: Self.decorationKey)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        let name = NestDecorationCatalog.allDecorations.first(where: { $0.id == itemId })?.title ?? "decoration"
        transientMessage = "Added \(name) to the nest!"
        return true
    }

    func selectDecoration(_ id: String?) {
        selectedDecorationId = id
        if let id {
            defaults.set(id, forKey: Self.decorationKey)
        } else {
            defaults.removeObject(forKey: Self.decorationKey)
        }
    }

    func rewardForPatternCompletion() {
        addThreadPoints(10)
    }

    func rewardForPatternSaved() {
        addThreadPoints(3)
    }

    func rewardForNoteSaved() {
        addThreadPoints(2)
    }

    func rewardForRowProgress() {
        addThreadPoints(1)
    }

    /// Called by DailyRewardStore to apply daily check-in bonus.
    func grantDailyReward(_ points: Int) {
        addThreadPoints(points)
    }

    /// Called by DailyRewardStore when hearts should decay due to inactivity.
    func applyHeartDecay(_ amount: Int) {
        let newHearts = max(0, heartsCurrent - amount)
        guard newHearts != heartsCurrent else { return }
        heartsCurrent = newHearts
        defaults.set(heartsCurrent, forKey: Self.heartsKey)
    }

    /// Called by DailyRewardStore when streak should reset due to 48h+ inactivity.
    func resetStreak() {
        guard streakCount > 0 else { return }
        streakCount = 0
        defaults.set(streakCount, forKey: Self.streakKey)
    }

    private func addThreadPoints(_ delta: Int) {
        guard delta > 0 else { return }
        threadPoints = min(threadPoints + delta, 9_999)
        defaults.set(threadPoints, forKey: Self.currencyKey)
        AchievementStore.shared.incrementTotalPointsEarned(by: delta)
    }

    private func displayName(for itemId: String) -> String {
        availableTreats.first(where: { $0.id == itemId })?.title
            ?? MascotEconomyCatalog.item(for: itemId)?.title
            ?? "treat"
    }

    private func persistInventory() {
        if let encoded = try? JSONEncoder().encode(treatInventory) {
            defaults.set(encoded, forKey: Self.inventoryKey)
        }
    }

    private func persistOwnedDecorations() {
        if let encoded = try? JSONEncoder().encode(ownedDecorationIds) {
            defaults.set(encoded, forKey: Self.ownedDecorationsKey)
        }
    }

    private func animateTemporaryPose(_ temporary: Pose) {
        pose = temporary
        let poseDuration = temporaryPoseDuration(for: temporary)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: poseDuration)
            pose = .idle
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            if transientMessage != nil {
                transientMessage = nil
            }
        }
    }

    private func temporaryPoseDuration(for pose: Pose) -> UInt64 {
        switch pose {
        case .petting:
            // 36 frames at ~15 FPS.
            return 2_400_000_000
        case .jumping:
            return 2_400_000_000
        case .knitting:
            return 2_400_000_000
        case .pouty:
            return 2_400_000_000
        case .idle:
            return 1_000_000_000
        }
    }
}
