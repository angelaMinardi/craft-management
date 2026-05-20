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

    @ObservedObject private var networkMonitor = NetworkMonitor.shared

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                if !networkMonitor.isConnected {
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "wifi.slash")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Offline — using cached data")
                            .font(Theme.Typography.caption)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Theme.honey)
                }
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
                Task {
                    await AdsKillSwitchService.refresh()
                    await AdService.shared.initialize()
                    await SubscriptionStore.shared.refreshLifetimeOffer()
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
                let defaults = UserDefaults(suiteName: "group.com.corvidcraft.app")
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
            if pattern.status == .completed || pattern.status == .frogged {
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
        defaults = UserDefaults(suiteName: "group.com.corvidcraft.app") ?? .standard
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
    @ObservedObject private var progressStore = PatternProgressStore.shared
    @ObservedObject private var rowCounterStore = RowCounterStore.shared
    @State private var showPicker = false
    @State private var workspaceHighlight: ChartHighlight?
    @State private var appeared = false
    @State private var showGoalSheet = false
    @State private var showProgressShare = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    if let pattern = currentPattern {
                        heroCard(pattern)
                            .staggeredAppear(index: 0)
                        progressSection(pattern)
                            .staggeredAppear(index: 1)
                        quickActionsRow(pattern)
                            .staggeredAppear(index: 2)
                        extractedChartsSection(pattern)
                            .staggeredAppear(index: 3)
                    } else {
                        emptySelectionCard
                    }
                }
                .padding(Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.xl)
            }
            .background(Theme.screenGradient.ignoresSafeArea())
            .navigationTitle("Current Project")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { showPicker = true } label: {
                            Label(currentPattern == nil ? "Choose Project" : "Change Project", systemImage: "arrow.triangle.swap")
                        }
                        if currentPattern != nil {
                            Button(role: .destructive) { currentProjectStore.clearCurrentPattern() } label: {
                                Label("Clear Current", systemImage: "xmark.circle")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(Theme.deepPlum)
                    }
                }
            }
        }
        .sheet(isPresented: $showGoalSheet) {
            if let pattern = currentPattern {
                let stepNames = progressStore.progress(for: pattern.id)?.customStepLayout?.stepTitles ?? []
                GoalSettingView(
                    patternId: pattern.id,
                    makeId: nil,
                    stepNames: stepNames,
                    progressStore: progressStore
                )
            }
        }
        .sheet(isPresented: $showProgressShare) {
            if let pattern = currentPattern {
                ProgressShareCardView(
                    pattern: pattern,
                    progressStore: progressStore,
                    rowCounterStore: rowCounterStore
                )
            }
        }
        .sheet(isPresented: $showPicker) {
            CurrentProjectPickerSheet(
                patterns: store.patterns.filter { $0.status != .completed && $0.status != .frogged },
                currentPatternId: currentProjectStore.currentPatternId,
                onSelect: { currentProjectStore.setCurrentPattern($0.id) },
                onClear: { currentProjectStore.clearCurrentPattern() }
            )
        }
        // Chart workspace removed — annotations are now in the PDF viewer
    }

    private var currentPattern: Pattern? {
        guard let id = currentProjectStore.currentPatternId else { return nil }
        return store.patterns.first(where: { $0.id == id && $0.status != .completed && $0.status != .frogged })
    }

    // MARK: - Hero Card

    @ViewBuilder
    private func heroCard(_ pattern: Pattern) -> some View {
        VStack(spacing: 0) {
            // Thumbnail or gradient header
            ZStack(alignment: .bottomLeading) {
                if let thumbnailUrl = pattern.thumbnailUrl,
                   let imageURL = URL(string: thumbnailUrl) {
                    CachedAsyncImage(url: imageURL, userId: nil) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(maxWidth: .infinity)
                                .frame(height: 180)
                                .clipped()
                                .overlay(
                                    LinearGradient(
                                        colors: [.clear, Color.black.opacity(0.45)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                        default:
                            heroPlaceholder(pattern)
                        }
                    }
                } else {
                    heroPlaceholder(pattern)
                }

                // Status badge on image
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: Theme.statusIcon(for: pattern.status))
                        .font(.system(size: 10, weight: .bold))
                    Text(pattern.status.displayName)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, Theme.Spacing.xs)
                .background(Theme.statusColor(for: pattern.status).opacity(0.9))
                .clipShape(Capsule())
                .padding(Theme.Spacing.md)
            }
            .frame(height: 180)

            // Title + metadata below image
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text(pattern.title)
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.deepPlum)
                    .lineLimit(2)

                // Metadata chips
                HStack(spacing: Theme.Spacing.sm) {
                    if let craft = pattern.craftType, !craft.isEmpty {
                        metadataChip(icon: "scissors", text: craft.capitalized)
                    }
                    if let difficulty = pattern.difficulty, !difficulty.isEmpty {
                        metadataChip(icon: "gauge.medium", text: difficulty.capitalized)
                    }
                    if let yarn = pattern.yarnWeightYardage, !yarn.isEmpty {
                        metadataChip(icon: "line.3.horizontal.decrease", text: yarn)
                    }
                }

                if let desc = pattern.patternDescription, !desc.isEmpty {
                    Text(desc)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.deepPlum.opacity(0.65))
                        .lineLimit(2)
                        .lineSpacing(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.lg)
        }
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.large))
        .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 4)
    }

    private func heroPlaceholder(_ pattern: Pattern) -> some View {
        ZStack {
            LinearGradient(
                colors: [Theme.softCoral.opacity(0.15), Theme.dustyBlue.opacity(0.12)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image("CrowMascot")
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 80)
                .opacity(0.6)
        }
        .frame(height: 180)
    }

    private func metadataChip(icon: String, text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
            Text(text)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .lineLimit(1)
        }
        .foregroundStyle(Theme.deepPlum.opacity(0.6))
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, 3)
        .background(Theme.warmCream)
        .clipShape(Capsule())
    }

    // MARK: - Progress Section

    @ViewBuilder
    private func progressSection(_ pattern: Pattern) -> some View {
        let rowState = rowCounterStore.state(for: pattern.id, makeId: nil)
        let fraction = progressStore.progressFraction(for: pattern.id)
        let hasRowData = rowState.totalRows != nil && rowState.totalRows! > 0
        let goal = progressStore.progress(for: pattern.id)?.goal

        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeaderView(title: "Progress")

            HStack(spacing: Theme.Spacing.lg) {
                // Progress ring
                ZStack {
                    Circle()
                        .stroke(Theme.deepPlum.opacity(0.08), lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: reduceMotion ? fraction : fraction)
                        .stroke(
                            Theme.sageGreen,
                            style: StrokeStyle(lineWidth: 6, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .animation(reduceMotion ? nil : Theme.Motion.spring, value: fraction)
                    Text("\(Int(fraction * 100))%")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.deepPlum)
                        .contentTransition(.numericText())
                }
                .frame(width: 64, height: 64)

                // Stats
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    if hasRowData {
                        progressStat(
                            label: "Row",
                            value: "\(rowState.globalRow)",
                            total: "\(rowState.totalRows ?? 0)",
                            color: Theme.dustyBlue
                        )
                    }
                    if let stepData = progressStore.progress(for: pattern.id),
                       let stepCount = stepData.stepCount, stepCount > 0 {
                        progressStat(
                            label: "Step",
                            value: "\(stepData.currentStepIndex + 1)",
                            total: "\(stepCount)",
                            color: Theme.honey
                        )
                    }
                    if !hasRowData && progressStore.progress(for: pattern.id) == nil {
                        Text("No progress yet — open to start tracking")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.deepPlum.opacity(0.5))
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(Theme.Spacing.lg)
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.large))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.large)
                    .stroke(Theme.deepPlum.opacity(0.06), lineWidth: 1)
            )

            // Inline row counter
            if hasRowData {
                HStack(spacing: Theme.Spacing.md) {
                    Button {
                        rowCounterStore.decrementGlobal(patternId: pattern.id, makeId: nil, patternTitle: pattern.title)
                    } label: {
                        Image(systemName: "chevron.down.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(Theme.deepPlum)
                    }
                    .buttonStyle(.plain)

                    Text("Row \(rowState.globalRow)")
                        .font(Theme.Typography.cardTitle)
                        .foregroundStyle(Theme.deepPlum)
                        .contentTransition(.numericText())
                        .frame(maxWidth: .infinity)

                    Button {
                        rowCounterStore.incrementGlobal(patternId: pattern.id, makeId: nil, patternTitle: pattern.title)
                    } label: {
                        Image(systemName: "chevron.up.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(Theme.sageGreen)
                    }
                    .buttonStyle(.plain)
                }
                .padding(Theme.Spacing.md)
                .background(Theme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                        .stroke(Theme.deepPlum.opacity(0.06), lineWidth: 1)
                )
            }

            // Goal & deadline
            if let goal {
                goalSummaryCard(goal)
            }
        }
    }

    @ViewBuilder
    private func goalSummaryCard(_ goal: ProjectGoal) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            if let days = goal.daysRemaining {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: days > 0 ? "calendar.badge.clock" : "exclamationmark.triangle.fill")
                        .foregroundStyle(days > 3 ? Theme.sageGreen : (days > 0 ? Theme.honey : Theme.softCoral))
                    Text(days > 0 ? "\(days) days remaining" : (days == 0 ? "Due today!" : "\(abs(days)) days overdue"))
                        .font(Theme.Typography.bodySemibold)
                        .foregroundStyle(Theme.deepPlum)
                }
            }

            if let next = goal.nextMilestone {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "flag.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.honey)
                    Text("Next: \(next.stepName)")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.deepPlum.opacity(0.7))
                    Spacer()
                    Text(next.targetDate, format: .dateTime.month(.abbreviated).day())
                        .font(Theme.Typography.caption2)
                        .foregroundStyle(Theme.deepPlum.opacity(0.5))
                }
            }

            if !goal.stepMilestones.isEmpty {
                let completed = goal.stepMilestones.filter(\.isCompleted).count
                let total = goal.stepMilestones.count
                ProgressView(value: Double(completed), total: Double(total))
                    .tint(Theme.sageGreen)
                Text("\(completed)/\(total) milestones complete")
                    .font(Theme.Typography.caption2)
                    .foregroundStyle(Theme.deepPlum.opacity(0.5))
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.honey.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
    }

    private func progressStat(label: String, value: String, total: String, color: Color) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.deepPlum.opacity(0.6))
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.deepPlum)
                .contentTransition(.numericText())
            Text("/ \(total)")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.deepPlum.opacity(0.45))
        }
    }

    // MARK: - Quick Actions

    @ViewBuilder
    private func quickActionsRow(_ pattern: Pattern) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeaderView(title: "Quick Actions")

            HStack(spacing: Theme.Spacing.md) {
                NavigationLink {
                    PatternDetailView(store: store, pattern: pattern)
                } label: {
                    quickActionButton(icon: "doc.text.fill", label: "Pattern", color: Theme.dustyBlue)
                }
                .buttonStyle(.plain)

                Button { showGoalSheet = true } label: {
                    quickActionButton(icon: "flag.fill", label: "Goal", color: Theme.honey)
                }
                .buttonStyle(.plain)

                Button { showProgressShare = true } label: {
                    quickActionButton(icon: "square.and.arrow.up", label: "Share", color: Theme.sageGreen)
                }
                .buttonStyle(.plain)

                Button { showPicker = true } label: {
                    quickActionButton(icon: "arrow.triangle.swap", label: "Switch", color: Theme.deepPlum.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func quickActionButton(icon: String, label: String, color: Color) -> some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.deepPlum.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.lg)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                .stroke(Theme.deepPlum.opacity(0.06), lineWidth: 1)
        )
        .fullRowTapTarget()
    }

    // MARK: - Chart Workspaces

    @ViewBuilder
    private func extractedChartsSection(_ pattern: Pattern) -> some View {
        let highlights = chartStore.extractedHighlights(patternId: pattern.id, makeId: nil)
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeaderView(title: "Chart Workspaces")

            if highlights.isEmpty {
                HStack(spacing: Theme.Spacing.md) {
                    Image(systemName: "square.grid.3x3")
                        .font(.system(size: 28))
                        .foregroundStyle(Theme.dustyBlue.opacity(0.4))
                        .frame(width: 48, height: 48)
                        .background(Theme.dustyBlue.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.small))

                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text("No chart workspaces yet")
                            .font(Theme.Typography.callout)
                            .foregroundStyle(Theme.deepPlum)
                        Text("Open this pattern and save a chart area to create your first workspace.")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.deepPlum.opacity(0.55))
                            .lineSpacing(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.Spacing.lg)
                .background(Theme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                        .stroke(Theme.deepPlum.opacity(0.06), lineWidth: 1)
                )
            } else {
                ForEach(Array(highlights.enumerated()), id: \.element.id) { index, highlight in
                    Button {
                        workspaceHighlight = highlight
                    } label: {
                        HStack(spacing: Theme.Spacing.md) {
                            if let data = highlight.extractedChartPNGData, let image = UIImage(data: data) {
                                Image(uiImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 56, height: 56)
                                    .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.small))
                            } else {
                                RoundedRectangle(cornerRadius: Theme.CornerRadius.small)
                                    .fill(Theme.warmCream)
                                    .frame(width: 56, height: 56)
                                    .overlay(
                                        Image(systemName: "square.grid.3x3")
                                            .foregroundStyle(Theme.deepPlum.opacity(0.2))
                                    )
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(label(for: highlight))
                                    .font(Theme.Typography.callout)
                                    .foregroundStyle(Theme.deepPlum)
                                HStack(spacing: Theme.Spacing.sm) {
                                    progressPill(label: "Row", current: highlight.currentRow, total: max(1, highlight.rows))
                                    progressPill(label: "Col", current: highlight.currentColumn, total: max(1, highlight.columns))
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.deepPlum.opacity(0.3))
                        }
                        .padding(Theme.Spacing.md)
                        .background(Theme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                                .stroke(Theme.deepPlum.opacity(0.06), lineWidth: 1)
                        )
                        .fullRowTapTarget()
                    }
                    .buttonStyle(.plain)
                    .staggeredAppear(index: min(4 + index, 10))
                }
            }
        }
    }

    private func progressPill(label: String, current: Int, total: Int) -> some View {
        Text("\(label) \(current)/\(total)")
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(Theme.deepPlum.opacity(0.5))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Theme.warmCream)
            .clipShape(Capsule())
    }

    // MARK: - Empty State

    private var emptySelectionCard: some View {
        VStack(spacing: Theme.Spacing.xl) {
            SpriteMascotView.thinking(size: 100)

            VStack(spacing: Theme.Spacing.sm) {
                Text("Pick your focus project")
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.deepPlum)
                Text("Choose one pattern to keep front and center for chart tracking and quick access.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.deepPlum.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }

            Button { showPicker = true } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "target")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Choose Primary Project")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                }
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.large))
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
        .padding(.top, Theme.Spacing.xxl)
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
                                        .font(Theme.Typography.callout)
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
