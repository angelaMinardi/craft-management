//
//  AppTutorialStore.swift
//  PatternVault
//
//  State and persistence for the in-app coach-mark tutorial (bubbles).
//

import SwiftUI

/// Anchor IDs for positioning tutorial bubbles. Tab bar anchors use fixed layout in the overlay.
enum TutorialAnchor: String, CaseIterable, Hashable {
    case welcome
    case tabBar
    case homeVault
    case homeCrafts
    case homeStats
    case tabPatterns
    case patternsAdd
    case patternsSearch
    case tabStash
    case stashCards
    case tabSettings
    case settingsTutorialRow
}

/// Step content and placement for the app tutorial overlay.
struct AppTutorialStep {
    let title: String
    let body: String
    let tabIndex: Int
    let anchorId: TutorialAnchor
}

@MainActor
final class AppTutorialStore: ObservableObject {
    @Published var isActive = false
    @Published var currentStep = 0

    /// Persisted: has the user completed (or skipped) the in-app tutorial at least once.
    var hasSeenAppTutorial: Bool {
        get { UserDefaults.standard.bool(forKey: Self.hasSeenAppTutorialKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.hasSeenAppTutorialKey) }
    }

    private static let hasSeenAppTutorialKey = "hasSeenAppTutorial"

    static let steps: [AppTutorialStep] = [
        AppTutorialStep(
            title: "Welcome",
            body: "We'll point to each spot as we go. Tap Next to continue or Skip to explore on your own.",
            tabIndex: 0,
            anchorId: .welcome
        ),
        AppTutorialStep(
            title: "Getting around",
            body: "Use these four tabs to get around: Home, Patterns, Stash, and Settings.",
            tabIndex: 0,
            anchorId: .tabBar
        ),
        AppTutorialStep(
            title: "Your Vault",
            body: "This is your vault summary—your greeting and how many patterns you've saved.",
            tabIndex: 0,
            anchorId: .homeVault
        ),
        AppTutorialStep(
            title: "Craft shortcuts",
            body: "Tap a craft to open your library filtered by that type.",
            tabIndex: 0,
            anchorId: .homeCrafts
        ),
        AppTutorialStep(
            title: "Status & recent",
            body: "Track patterns by status—want to make, in progress, completed—and see your recent patterns below.",
            tabIndex: 0,
            anchorId: .homeStats
        ),
        AppTutorialStep(
            title: "Patterns",
            body: "Patterns is your full library. Tap Next to switch there.",
            tabIndex: 1,
            anchorId: .tabPatterns
        ),
        AppTutorialStep(
            title: "Add to vault",
            body: "Share a link from Safari or any app and choose \"Save to Pattern Vault\" to add patterns to your vault.",
            tabIndex: 1,
            anchorId: .patternsAdd
        ),
        AppTutorialStep(
            title: "Search & filter",
            body: "Search and filter your library. Tap any pattern to open it.",
            tabIndex: 1,
            anchorId: .patternsSearch
        ),
        AppTutorialStep(
            title: "Stash",
            body: "Stash keeps your materials and tools in one place. Tap Next to switch there.",
            tabIndex: 2,
            anchorId: .tabStash
        ),
        AppTutorialStep(
            title: "Stash & tools",
            body: "Track yarn and materials in Stash; needles and hooks in Tools. You can open Ravelry in Safari from here to search for patterns.",
            tabIndex: 2,
            anchorId: .stashCards
        ),
        AppTutorialStep(
            title: "Settings",
            body: "Account, backup, and preferences. Tap Next to open Settings.",
            tabIndex: 3,
            anchorId: .tabSettings
        ),
        AppTutorialStep(
            title: "All set",
            body: "You can run this tour again anytime from here. You're all set!",
            tabIndex: 3,
            anchorId: .settingsTutorialRow
        ),
    ]

    var totalSteps: Int { Self.steps.count }
    var isLastStep: Bool { currentStep >= totalSteps - 1 }

    /// Tab index for the current step; used to drive TabView selection when tutorial is active.
    var tabForCurrentStep: Int {
        guard currentStep < Self.steps.count else { return 0 }
        return Self.steps[currentStep].tabIndex
    }

    /// Start or restart the tutorial (e.g. first launch or "Show app tutorial" in Settings).
    func start() {
        currentStep = 0
        isActive = true
    }

    /// Advance to the next step; finishes if past the last step.
    func next() {
        if currentStep + 1 >= totalSteps {
            finish()
        } else {
            currentStep += 1
        }
    }

    /// Skip the rest of the tutorial and mark as seen.
    func skip() {
        finish()
    }

    /// Mark tutorial as seen and hide overlay.
    private func finish() {
        hasSeenAppTutorial = true
        isActive = false
    }
}
