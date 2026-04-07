//
//  WidgetOnboardingStore.swift
//  PatternVault
//
//  Tracks row-counter use and whether we've shown the Row Tracker widget onboarding.
//

import Foundation

@MainActor
final class WidgetOnboardingStore: ObservableObject {
    static let shared = WidgetOnboardingStore()

    private let rowTrackerUseCountKey = "widgetOnboarding_rowTrackerUseCount"
    private let hasSeenWidgetOnboardingKey = "widgetOnboarding_hasSeen"

    var rowTrackerUseCount: Int {
        get { UserDefaults.standard.integer(forKey: rowTrackerUseCountKey) }
        set { UserDefaults.standard.set(newValue, forKey: rowTrackerUseCountKey) }
    }

    var hasSeenWidgetOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: hasSeenWidgetOnboardingKey) }
        set { UserDefaults.standard.set(newValue, forKey: hasSeenWidgetOnboardingKey) }
    }

    /// Call when the user updates row progress (tap or voice). Returns true if we should show the widget onboarding (e.g. 2nd or 3rd use).
    func recordRowTrackerUse() -> Bool {
        rowTrackerUseCount += 1
        let count = rowTrackerUseCount
        return count >= 2 && count <= 3 && !hasSeenWidgetOnboarding
    }

    /// Call when we've shown the widget onboarding so we don't show again.
    func markWidgetOnboardingSeen() {
        hasSeenWidgetOnboarding = true
    }

    /// Whether to show the "add widget" reminder (e.g. after 10+ row updates without having seen onboarding, or as a soft reminder).
    var shouldShowWidgetReminder: Bool {
        rowTrackerUseCount >= 10 && !hasSeenWidgetOnboarding
    }

    private init() {}
}
