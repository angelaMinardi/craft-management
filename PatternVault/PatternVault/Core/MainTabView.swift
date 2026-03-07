//
//  MainTabView.swift
//  PatternVault
//

import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var auth: AuthService
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = PatternStore()
    @Binding var sharedURL: String?
    @State private var showAddSheet = false
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView(store: store)
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(0)
            PatternListView(store: store, sharedURL: $sharedURL)
                .tabItem { Label("Patterns", systemImage: "square.grid.2x2.fill") }
                .tag(1)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(2)
        }
        .tint(Theme.softCoral)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active, let userId = auth.currentUserId {
                Task { await store.load(userId: userId) }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .patternListShouldRefresh)) { _ in
            if let userId = auth.currentUserId {
                Task { await store.load(userId: userId) }
            }
        }
        .onAppear {
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
    }
}
