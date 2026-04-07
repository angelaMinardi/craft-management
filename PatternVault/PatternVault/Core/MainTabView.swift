//
//  MainTabView.swift
//  PatternVault
//

import SwiftUI
import WidgetKit

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
    @StateObject private var currentProjectStore = CurrentProjectStore.shared

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
                    }, onViewAllPatterns: {
                        patternsCraftFilter = nil
                        selectedTab = 1
                    })
                        .tabItem { Label("Home", systemImage: "house.fill") }
                        .tag(0)
                    PatternListView(store: store, tutorialStore: tutorialStore, sharedURL: $sharedURL, craftFilter: $patternsCraftFilter, savedPatternId: $savedPatternId)
                        .tabItem { Label("Patterns", systemImage: "square.grid.2x2.fill") }
                        .tag(1)
                    CurrentProjectTabView(store: store, currentProjectStore: currentProjectStore)
                        .tabItem { Label("Current", systemImage: "target") }
                        .tag(2)
                    StashAndToolsView(tutorialStore: tutorialStore, store: store)
                        .tabItem { Label("Stash", systemImage: "archivebox.fill") }
                        .tag(3)
                    SettingsView(store: store, tutorialStore: tutorialStore)
                        .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                        .tag(4)
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
                        syncWidgetData()
                        syncBackFromRowTrackerWidget()
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
            syncWidgetData()
        }
        .onChange(of: store.patterns) { _, newPatterns in
            guard let currentId = currentProjectStore.currentPatternId else { return }
            guard let pattern = newPatterns.first(where: { $0.id == currentId }) else {
                currentProjectStore.clearCurrentPattern()
                return
            }
            if pattern.status == .completed {
                currentProjectStore.clearCurrentPattern()
            }
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

    // MARK: - Widget Sync

    /// Write pattern summary data to App Group for the home screen widget.
    private func syncWidgetData() {
        let progressStore = PatternProgressStore.shared
        WidgetDataService.writeWidgetData(
            patterns: store.patterns,
            progressFraction: { patternId in
                progressStore.progressFraction(for: patternId)
            }
        )
    }

    /// Read any row changes made by the Row Tracker widget's +/- buttons and apply them to local progress.
    private func syncBackFromRowTrackerWidget() {
        guard let widgetData = WidgetDataService.readRowTrackerData(),
              let patternId = widgetData.patternId else { return }
        let progressStore = PatternProgressStore.shared
        let existing = progressStore.progress(for: patternId, makeId: widgetData.makeId)
        let existingRow = existing?.rowsCompleted ?? 0
        // Only update if the widget row differs from stored (widget +/- changed it)
        if widgetData.current != existingRow {
            let title = widgetData.title ?? store.patterns.first(where: { $0.id == patternId })?.title
            progressStore.setRows(
                patternId: patternId,
                makeId: widgetData.makeId,
                completed: widgetData.current,
                total: widgetData.total,
                patternTitle: title
            )
        }
    }

}

@MainActor
final class CurrentProjectStore: ObservableObject {
    static let shared = CurrentProjectStore()

    @Published private(set) var currentPatternId: UUID?
    private let defaults: UserDefaults
    private let defaultsKey = "current_primary_pattern_id"

    private init() {
        defaults = UserDefaults(suiteName: "group.com.patternvault.app") ?? .standard
        if let raw = defaults.string(forKey: defaultsKey) {
            currentPatternId = UUID(uuidString: raw)
        }
    }

    func setCurrentPattern(_ id: UUID) {
        currentPatternId = id
        defaults.set(id.uuidString, forKey: defaultsKey)
    }

    func clearCurrentPattern() {
        currentPatternId = nil
        defaults.removeObject(forKey: defaultsKey)
#if canImport(ActivityKit)
        Task { @MainActor in
            await LiveActivityService.endCounterActivity()
        }
#endif
    }
}

private struct CurrentProjectTabView: View {
    @ObservedObject var store: PatternStore
    @ObservedObject var currentProjectStore: CurrentProjectStore
    @ObservedObject private var chartStore = ChartHighlightStore.shared
    @State private var showPicker = false
    @State private var workspaceHighlight: ChartHighlight?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    sectionHeader
                    if let pattern = currentPattern {
                        currentProjectCard(pattern)
                        extractedChartsSection(pattern)
                    } else {
                        emptySelectionCard
                    }
                }
                .padding(Theme.Spacing.lg)
            }
            .background(Theme.screenGradient.ignoresSafeArea())
            .navigationTitle("Current Project")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(currentPattern == nil ? "Choose" : "Change") {
                        showPicker = true
                    }
                }
            }
        }
        .sheet(isPresented: $showPicker) {
            CurrentProjectPickerSheet(
                patterns: store.patterns.filter { $0.status != .completed },
                currentPatternId: currentProjectStore.currentPatternId,
                onSelect: { currentProjectStore.setCurrentPattern($0.id) },
                onClear: { currentProjectStore.clearCurrentPattern() }
            )
        }
        .sheet(item: $workspaceHighlight) { highlight in
            ExtractedChartWorkspaceView(
                highlight: highlight,
                patternId: highlight.patternId,
                makeId: highlight.makeId,
                onSave: { chartStore.save($0) }
            )
        }
    }

    private var currentPattern: Pattern? {
        guard let id = currentProjectStore.currentPatternId else { return nil }
        return store.patterns.first(where: { $0.id == id && $0.status != .completed })
    }

    private var sectionHeader: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Focus Mode")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.softCoral)
            Text("Keep your active chart front and center.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.deepPlum.opacity(0.7))
        }
    }

    @ViewBuilder
    private func currentProjectCard(_ pattern: Pattern) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Primary project")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.deepPlum.opacity(0.6))
            Text(pattern.title)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.deepPlum)
            Text("Jump into chart tracking and annotations for your active work.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.deepPlum.opacity(0.7))
                .lineSpacing(2)

            HStack(spacing: Theme.Spacing.sm) {
                Button("Change project") { showPicker = true }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.softCoral)
                Button("Clear") { currentProjectStore.clearCurrentPattern() }
                    .buttonStyle(.bordered)
            }
            .padding(.top, Theme.Spacing.xs)
        }
        .padding(Theme.Spacing.md)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.large))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.large)
                .stroke(Theme.softCoral.opacity(0.2), lineWidth: 1.5)
        )
    }

    @ViewBuilder
    private func extractedChartsSection(_ pattern: Pattern) -> some View {
        let highlights = chartStore.extractedHighlights(patternId: pattern.id, makeId: nil)
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Chart workspaces")
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.deepPlum)

            if highlights.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Label("No chart workspaces yet", systemImage: "square.grid.3x3")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.deepPlum)
                    Text("Open this pattern, choose a chart area, and save to create your first workspace.")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.deepPlum.opacity(0.65))
                        .lineSpacing(2)
                }
                .padding(Theme.Spacing.md)
                .background(Theme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
            } else {
                ForEach(highlights) { highlight in
                    Button {
                        workspaceHighlight = highlight
                    } label: {
                        HStack(spacing: Theme.Spacing.sm) {
                            if let data = highlight.extractedChartPNGData, let image = UIImage(data: data) {
                                Image(uiImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 56, height: 56)
                                    .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.small))
                            } else {
                                RoundedRectangle(cornerRadius: Theme.CornerRadius.small)
                                    .fill(Theme.cardBackground)
                                    .frame(width: 56, height: 56)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(label(for: highlight))
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Theme.deepPlum)
                                Text("Row \(highlight.currentRow)/\(max(1, highlight.rows))  •  Col \(highlight.currentColumn)/\(max(1, highlight.columns))")
                                    .font(Theme.Typography.caption)
                                    .foregroundStyle(Theme.deepPlum.opacity(0.6))
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(Theme.deepPlum.opacity(0.4))
                        }
                        .padding(Theme.Spacing.sm)
                        .background(Theme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                                .stroke(Theme.deepPlum.opacity(0.08), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var emptySelectionCard: some View {
        VStack(spacing: Theme.Spacing.md) {
            SpriteMascotView.thinking(size: 90)
            Text("Pick your current project")
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.deepPlum)
            Text("Choose one pattern to keep front-and-center for chart tracking and annotation.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.deepPlum.opacity(0.65))
                .multilineTextAlignment(.center)
                .lineSpacing(2)
            Button("Choose primary project") { showPicker = true }
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding(Theme.Spacing.md)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.large))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.large)
                .stroke(Theme.deepPlum.opacity(0.08), lineWidth: 1)
        )
    }

    private func label(for highlight: ChartHighlight) -> String {
        if let page = highlight.pdfPageIndex {
            return "PDF page \(page + 1)"
        }
        if highlight.imageId != nil {
            return "Pattern image chart"
        }
        return "Chart workspace"
    }
}

private struct CurrentProjectPickerSheet: View {
    let patterns: [Pattern]
    let currentPatternId: UUID?
    let onSelect: (Pattern) -> Void
    let onClear: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if patterns.isEmpty {
                    VStack(spacing: Theme.Spacing.md) {
                        Image(systemName: "tray")
                            .font(.system(size: 30))
                            .foregroundStyle(Theme.deepPlum.opacity(0.35))
                        Text("No active patterns available.")
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.deepPlum.opacity(0.75))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(patterns) { pattern in
                        Button {
                            onSelect(pattern)
                            dismiss()
                        } label: {
                            HStack(spacing: Theme.Spacing.sm) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(pattern.title)
                                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                                        .foregroundStyle(Theme.deepPlum)
                                        .multilineTextAlignment(.leading)
                                    Text(pattern.status.displayName)
                                        .font(Theme.Typography.caption)
                                        .foregroundStyle(Theme.deepPlum.opacity(0.6))
                                }
                                Spacer()
                                if currentPatternId == pattern.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Theme.sageGreen)
                                }
                            }
                            .padding(.vertical, Theme.Spacing.xs)
                        }
                        .listRowBackground(Theme.cardBackground)
                        .listRowSeparator(.hidden)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Theme.warmCream)
            .navigationTitle("Choose Current")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("Clear Current Project", role: .destructive) {
                        onClear()
                        dismiss()
                    }
                }
            }
        }
    }
}
