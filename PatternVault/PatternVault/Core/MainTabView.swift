//
//  MainTabView.swift
//  PatternVault
//

import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var auth: AuthService
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = PatternStore()
    @StateObject private var tutorialStore = AppTutorialStore()
    @Binding var sharedURL: String?
    @Binding var savedPatternId: UUID?
    @State private var showAddSheet = false
    @State private var selectedTab = 0
    @State private var patternsCraftFilter: String?
    @State private var anchorFrames = TutorialAnchorFrames()
    @StateObject private var ravelryAutoSync = RavelryImportStore()

    private var tabSelection: Binding<Int> {
        Binding(
            get: { tutorialStore.isActive ? tutorialStore.tabForCurrentStep : selectedTab },
            set: { new in selectedTab = new }
        )
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                TabView(selection: tabSelection) {
                    DashboardView(store: store, tutorialStore: tutorialStore, onSelectCraft: { craft in
                        patternsCraftFilter = craft
                        selectedTab = 1
                    })
                        .tabItem { Label("Home", systemImage: "house.fill") }
                        .tag(0)
                    PatternListView(store: store, tutorialStore: tutorialStore, sharedURL: $sharedURL, craftFilter: $patternsCraftFilter, savedPatternId: $savedPatternId)
                        .tabItem { Label("Patterns", systemImage: "square.grid.2x2.fill") }
                        .tag(1)
                    StashAndToolsView(tutorialStore: tutorialStore, store: store)
                        .tabItem { Label("Stash", systemImage: "archivebox.fill") }
                        .tag(2)
                    SettingsView(store: store, tutorialStore: tutorialStore)
                        .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                        .tag(3)
                }
                .tint(Theme.softCoral)

                if !SubscriptionStore.shared.isPremium {
                    AdBannerView()
                }
            }

            if tutorialStore.isActive {
                AppTutorialOverlayView(store: tutorialStore, anchorFrames: anchorFrames)
            }
        }
        .onPreferenceChange(TutorialAnchorPreferenceKey.self) { anchorFrames = $0 }
        .onChange(of: tutorialStore.currentStep) { _, _ in
            if tutorialStore.isActive {
                selectedTab = tutorialStore.tabForCurrentStep
            }
        }
        .onChange(of: tutorialStore.isActive) { _, isActive in
            if isActive {
                selectedTab = tutorialStore.tabForCurrentStep
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task {
                    await AIKillSwitchService.refresh()
                }
                if let userId = auth.currentUserId {
                    Task {
                        await store.load(userId: userId)
                        await SubscriptionStore.shared.refreshUsage(userId: userId)
                        await SubscriptionStore.shared.updateSubscriptionStatus(userId: userId)
                        SubscriptionStore.syncPatternCountToAppGroup(store.patterns.count)
                    }
                }
                let defaults = UserDefaults(suiteName: "group.com.patternvault.app")
                if defaults?.string(forKey: "pendingRavelryCallbackURL") != nil {
                    NotificationCenter.default.post(name: .processPendingRavelryCallback, object: nil)
                }
                if let userId = auth.currentUserId,
                   RavelryOAuthService.shared.isConnected(userId: userId),
                   ravelryAutoSync.shouldAutoSync,
                   !ravelryAutoSync.isImporting {
                    Task {
                        await ravelryAutoSync.importLibrary(userId: userId, patternStore: store)
                    }
                }
            }
        }
        .onChange(of: store.patterns.count) { _, _ in
            SubscriptionStore.syncPatternCountToAppGroup(store.patterns.count)
        }
        .onReceive(NotificationCenter.default.publisher(for: .patternListShouldRefresh)) { _ in
            if let userId = auth.currentUserId {
                Task {
                    await store.load(userId: userId)
                    await SubscriptionStore.shared.refreshUsage(userId: userId)
                    SubscriptionStore.syncPatternCountToAppGroup(store.patterns.count)
                }
            }
        }
        .onAppear {
            if !tutorialStore.hasSeenAppTutorial {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    tutorialStore.start()
                }
            }
            let tabBarAppearance = UITabBarAppearance()
            tabBarAppearance.configureWithDefaultBackground()
            tabBarAppearance.backgroundColor = Theme.uiWarmCream
            tabBarAppearance.shadowColor = UIColor.black.withAlphaComponent(0.06)
            tabBarAppearance.shadowImage = nil
            UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance
            UITabBar.appearance().standardAppearance = tabBarAppearance

            let navAppearance = UINavigationBarAppearance()
            navAppearance.configureWithDefaultBackground()
            navAppearance.backgroundColor = Theme.uiWarmCream
            navAppearance.titleTextAttributes = [.foregroundColor: Theme.uiDeepPlum]
            navAppearance.largeTitleTextAttributes = [.foregroundColor: Theme.uiDeepPlum]
            UINavigationBar.appearance().standardAppearance = navAppearance
            UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
        }
        .onChange(of: sharedURL) { _, newURL in
            if newURL != nil {
                selectedTab = 1
            }
        }
        .onChange(of: savedPatternId) { _, newId in
            if newId != nil {
                selectedTab = 1
            }
        }
    }
}
