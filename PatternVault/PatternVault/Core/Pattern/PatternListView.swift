//
//  PatternListView.swift
//  PatternVault
//
//  Pattern library with custom header, inline search, filter pills,
//  craft category chips, continue card, and trending grid.
//

import SwiftUI

struct PatternListView: View {
    @EnvironmentObject var auth: AuthService
    @ObservedObject var store: PatternStore
    @ObservedObject var tutorialStore: AppTutorialStore
    @Binding var sharedURL: String?
    @Binding var craftFilter: String?
    @Binding var savedPatternId: UUID?

    private var currentStepAnchor: TutorialAnchor? {
        guard tutorialStore.isActive, tutorialStore.currentStep < AppTutorialStore.steps.count else { return nil }
        return AppTutorialStore.steps[tutorialStore.currentStep].anchorId
    }

    @Environment(\.scenePhase) private var scenePhase
    @State private var patternToOpen: Pattern?
    @StateObject private var tagStore = TagStore()
    @State private var showAddSheet = false
    @State private var searchText = ""
    @State private var filterStatus: PatternStatus?
    @State private var filterTagIds: Set<UUID> = []
    @State private var patternTagsMap: [UUID: Set<UUID>] = [:]
    /// In-memory only; continue card reappears on next launch. Optionally persist in UserDefaults/App Group for session-long dismiss.
    private static let dismissedContinueKey = "dismissed_continue_pattern_ids"
    @State private var dismissedContinuePatternIds: Set<UUID> = []
    @State private var showFilterOptions = false
    @State private var filterDifficulty: String?
    @ObservedObject private var progressStore = PatternProgressStore.shared
    @StateObject private var continueNoteStore = ProjectNoteStore()
    @State private var noteBasedProgress: [UUID: Double] = [:]
    @State private var showPaywall = false
    @State private var isSelectionMode = false
    @State private var selectedPatternIds: Set<UUID> = []
    @State private var showMassDeleteConfirm = false
    @State private var filteredPatterns: [Pattern] = []
    @State private var searchDebounceTask: Task<Void, Never>?
    @AppStorage("onboarding_selected_first_win") private var onboardingFirstWin = "save_first_pattern"
    @AppStorage("onboarding_first_win_prompt_consumed") private var onboardingFirstWinPromptConsumed = false
    @State private var showEnrichingAlert = false
    @State private var enrichingAlertPatternId: UUID?

    private func recomputeFilteredPatterns() {
        var result = store.patterns
        if let filterStatus {
            result = result.filter { $0.status == filterStatus }
        }
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.title.lowercased().contains(query) ||
                ($0.patternDescription?.lowercased().contains(query) ?? false)
            }
        }
        if !filterTagIds.isEmpty {
            result = result.filter { pattern in
                let patternTags = patternTagsMap[pattern.id] ?? []
                return !filterTagIds.isDisjoint(with: patternTags)
            }
        }
        if let cf = craftFilter, !cf.isEmpty {
            result = result.filter { pattern in
                pattern.craftType?.lowercased() == cf.lowercased()
            }
        }
        if let diff = filterDifficulty, !diff.isEmpty {
            result = result.filter { pattern in
                Self.normalizedDifficulty(pattern.difficulty) == diff
            }
        }
        filteredPatterns = result
    }

    private func debouncedRecomputeFilteredPatterns() {
        searchDebounceTask?.cancel()
        searchDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            recomputeFilteredPatterns()
        }
    }

    /// Maps pattern.difficulty to a filter bucket: "beginner", "intermediate", "advanced".
    private static func normalizedDifficulty(_ difficulty: String?) -> String? {
        guard let d = difficulty?.lowercased().trimmingCharacters(in: .whitespaces), !d.isEmpty else { return nil }
        if d.contains("beginner") || d.contains("easy") { return "beginner" }
        if d.contains("intermediate") { return "intermediate" }
        if d.contains("advanced") || d.contains("expert") { return "advanced" }
        return nil
    }

    var body: some View {
        navigatedContent
    }

    private var navigatedContent: some View {
        navigationWithOnAppear
    }

    private var navigationWithPrimaryChanges: some View {
        AnyView(
            navigationWithLoadingActions
                .onChange(of: sharedURL) { _, newURL in
                    if newURL != nil { showAddSheet = true }
                }
                .onChange(of: savedPatternId) { _, id in
                    if let id, let pattern = store.patterns.first(where: { $0.id == id }) {
                        patternToOpen = pattern
                        savedPatternId = nil
                    }
                }
                .onChange(of: store.patterns.count) { _, _ in
                    if let id = savedPatternId, let pattern = store.patterns.first(where: { $0.id == id }) {
                        patternToOpen = pattern
                        savedPatternId = nil
                    }
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        Task { await loadPatternTagsMap() }
                    }
                }
        )
    }

    private var navigationWithFilterChanges: some View {
        AnyView(
            navigationWithPrimaryChanges
                .onChange(of: searchText) { _, _ in
                    debouncedRecomputeFilteredPatterns()
                }
                .onChange(of: filterStatus) { _, _ in
                    recomputeFilteredPatterns()
                }
                .onChange(of: filterTagIds) { _, _ in
                    recomputeFilteredPatterns()
                }
                .onChange(of: craftFilter) { _, _ in
                    recomputeFilteredPatterns()
                }
                .onChange(of: filterDifficulty) { _, _ in
                    recomputeFilteredPatterns()
                }
                .onChange(of: store.patterns) { _, _ in
                    recomputeFilteredPatterns()
                }
        )
    }

    private var navigationWithDestination: some View {
        AnyView(
            navigationWithFilterChanges
                .navigationDestination(item: $patternToOpen) { p in
                    PatternDetailView(store: store, pattern: p)
                }
        )
    }

    private var navigationWithOnAppear: some View {
        AnyView(
            navigationWithDestination
                .onAppear {
                    loadDismissedContinueIds()
                    if !onboardingFirstWinPromptConsumed && store.patterns.isEmpty {
                        if onboardingFirstWin == "save_first_pattern" || onboardingFirstWin == "import_from_link" {
                            showAddSheet = true
                        }
                        onboardingFirstWinPromptConsumed = true
                    }
                    // Clear stale "cancelled" error so list can show (e.g. after adding a pattern)
                    if store.errorMessage?.lowercased() == "cancelled" {
                        store.errorMessage = nil
                        if let userId = auth.currentUserId {
                            Task { await store.load(userId: userId) }
                        }
                    }
                }
        )
    }

    private var navigationWithLoadingActions: some View {
        navigationWithSheetsAndDialogs
            .refreshable {
                if let userId = auth.currentUserId {
                    await store.load(userId: userId)
                }
                await loadContinueCardProgressFallback()
            }
            .task {
                if store.patterns.isEmpty, let userId = auth.currentUserId {
                    await store.load(userId: userId)
                }
                recomputeFilteredPatterns()
                await tagStore.loadAllTags()
                await loadPatternTagsMap()
                await loadContinueCardProgressFallback()
            }
    }

    private var navigationWithSheetsAndDialogs: some View {
        navigationBase
            .sheet(isPresented: $showAddSheet, onDismiss: { sharedURL = nil }) {
                AddPatternView(store: store, prefillURL: sharedURL)
            }
            .sheet(isPresented: $showPaywall, onDismiss: {
                if !SubscriptionStore.shared.isPremium {
                    GrowthOrchestrator.shared.registerPaywallDismissal(source: .patternLimit)
                }
            }) {
                PaywallView(source: .patternLimit)
            }
            .confirmationDialog("Delete \(selectedPatternIds.count) pattern\(selectedPatternIds.count == 1 ? "" : "s")?", isPresented: $showMassDeleteConfirm, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    performMassDelete()
                }
                Button("Cancel", role: .cancel) {
                    showMassDeleteConfirm = false
                }
            } message: {
                Text("This will also delete all notes for these patterns. This cannot be undone.")
            }
            .alert("Still Processing", isPresented: $showEnrichingAlert) {
                Button("Retry Now") {
                    if let pid = enrichingAlertPatternId,
                       let pattern = store.patterns.first(where: { $0.id == pid }),
                       let userId = auth.currentUserId {
                        Task { await store.retryEnrichment(pattern: pattern, userId: userId) }
                    }
                }
                Button("OK", role: .cancel) { }
            } message: {
                Text("This pattern is still being analyzed. You'll get a notification when it's ready — feel free to leave and come back!")
            }
    }

    private var navigationBase: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    if let error = store.errorMessage, !store.isLoading {
                        errorView(error)
                    } else if store.isLoading {
                        loadingView
                    } else if store.patterns.isEmpty {
                        emptyView
                    } else {
                        populatedView
                    }
                }
                .padding(.bottom, 100)
            }
            .background(Theme.screenGradient.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func performMassDelete() {
        guard let userId = auth.currentUserId, !selectedPatternIds.isEmpty else { return }
        showMassDeleteConfirm = false
        Task {
            await store.deletePatterns(ids: selectedPatternIds, userId: userId)
            selectedPatternIds = []
            isSelectionMode = false
        }
    }

    private func loadDismissedContinueIds() {
        let defaults = UserDefaults(suiteName: "group.com.patternvault.app") ?? .standard
        let raw = defaults.stringArray(forKey: Self.dismissedContinueKey) ?? []
        dismissedContinuePatternIds = Set(raw.compactMap { UUID(uuidString: $0) })
    }

    private func dismissContinueCard(for patternId: UUID) {
        dismissedContinuePatternIds.insert(patternId)
        let defaults = UserDefaults(suiteName: "group.com.patternvault.app") ?? .standard
        defaults.set(dismissedContinuePatternIds.map { $0.uuidString }, forKey: Self.dismissedContinueKey)
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.md) {
            // Profile avatar
            ZStack {
                Circle()
                    .fill(Theme.sageGreen.opacity(0.15))
                    .frame(width: 40, height: 40)
                if let initial = userInitial {
                    Text(initial)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.sageGreen)
                } else {
                    Image(systemName: "person.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.sageGreen)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("My Patterns")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.deepPlum)
                if !SubscriptionStore.shared.isPremium {
                    Text("\(store.patterns.count) / \(SubscriptionStore.shared.patternLimit) patterns")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.deepPlum.opacity(0.5))
                }
            }

            Spacer()

            if isSelectionMode {
                Button("Cancel") {
                    isSelectionMode = false
                    selectedPatternIds = []
                }
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.deepPlum)

                if !selectedPatternIds.isEmpty {
                    Button {
                        showMassDeleteConfirm = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                            Text("Delete \(selectedPatternIds.count)")
                        }
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.red)
                    }
                }
            } else {
                // Add button
                Button { showAddSheet = true } label: {
                    ZStack {
                        Circle()
                            .fill(Theme.softCoral.opacity(0.12))
                            .frame(width: 40, height: 40)
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Theme.softCoral)
                    }
                }
                .accessibilityLabel("Add pattern")
                .accessibilityHint("Opens form to add a new pattern")

                // Select (mass delete) button
                Button {
                    isSelectionMode = true
                    selectedPatternIds = []
                } label: {
                    ZStack {
                        Circle()
                            .fill(Theme.deepPlum.opacity(0.08))
                            .frame(width: 40, height: 40)
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 18))
                            .foregroundStyle(Theme.deepPlum.opacity(0.7))
                    }
                }
                .accessibilityLabel("Select patterns")
                .accessibilityHint("Select multiple patterns to delete")
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.top, Theme.Spacing.sm)
    }

    // MARK: - Search Bar + Filter

    private var searchBar: some View {
        HStack(spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.deepPlum.opacity(0.35))

                TextField("Search patterns", text: $searchText)
                    .font(.system(size: 15, design: .rounded))
                    .foregroundStyle(Theme.deepPlum)

                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.deepPlum.opacity(0.3))
                    }
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, 11)
            .background(Theme.deepPlum.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                    .stroke(Theme.deepPlum.opacity(0.08), lineWidth: 1)
            )

            Button { showFilterOptions = true } label: {
                Image(systemName: "line.3.horizontal.decrease.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Theme.sageGreen)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Filters")
            .accessibilityHint("Opens filter options by status and difficulty")
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .sheet(isPresented: $showFilterOptions) {
            filterOptionsSheet
        }
    }

    private static let difficultyOptions: [(value: String?, label: String)] = [
        (nil, "All"),
        ("beginner", "Beginner"),
        ("intermediate", "Intermediate"),
        ("advanced", "Advanced")
    ]

    private var filterOptionsSheet: some View {
        NavigationStack {
            List {
                Section("Status") {
                    ForEach([nil] + PatternStatus.allCases, id: \.self) { status in
                        Button {
                            filterStatus = status
                            showFilterOptions = false
                        } label: {
                            HStack {
                                Text(status?.displayName ?? "All")
                                    .foregroundStyle(Theme.deepPlum)
                                Spacer()
                                if filterStatus == status {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Theme.softCoral)
                                }
                            }
                        }
                    }
                }
                Section("Difficulty") {
                    ForEach(Self.difficultyOptions, id: \.label) { option in
                        Button {
                            filterDifficulty = option.value
                            showFilterOptions = false
                        } label: {
                            HStack {
                                Text(option.label)
                                    .foregroundStyle(Theme.deepPlum)
                                Spacer()
                                if filterDifficulty == option.value {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Theme.softCoral)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { showFilterOptions = false }
                }
            }
        }
    }

    // MARK: - Status Filter Pills

    private var statusFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                statusPill("All", icon: nil, isSelected: filterStatus == nil) {
                    filterStatus = nil
                }
                statusPill("Want to Make", icon: "bookmark", isSelected: filterStatus == .wantToMake) {
                    filterStatus = filterStatus == .wantToMake ? nil : .wantToMake
                }
                statusPill("In Progress", icon: "hammer.fill", isSelected: filterStatus == .inProgress) {
                    filterStatus = filterStatus == .inProgress ? nil : .inProgress
                }
                statusPill("Done", icon: "checkmark.circle.fill", isSelected: filterStatus == .completed) {
                    filterStatus = filterStatus == .completed ? nil : .completed
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
        }
    }

    @ViewBuilder
    private func statusPill(_ label: String, icon: String?, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 10, weight: .semibold))
                }
                Text(label)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
            }
            .foregroundStyle(isSelected ? .white : Theme.deepPlum.opacity(0.65))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isSelected ? Theme.deepPlum : Color.clear)
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(
                    isSelected ? Color.clear : Theme.deepPlum.opacity(0.15),
                    lineWidth: 1.2
                )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Craft Category Chips with Counts

    private var craftCategoryChips: some View {
        let categories = craftTypeCounts
        if categories.isEmpty { return AnyView(EmptyView()) }

        return AnyView(
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.sm) {
                    ForEach(categories, id: \.type) { cat in
                        Button {
                            if craftFilter?.lowercased() == cat.type.lowercased() {
                                craftFilter = nil
                            } else {
                                craftFilter = cat.type
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: craftIcon(for: cat.type))
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(craftColor(for: cat.type))
                                Text("\(cat.count)")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundStyle(Theme.deepPlum)
                                Text(cat.type.capitalized)
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundStyle(Theme.deepPlum.opacity(0.55))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background((craftFilter?.lowercased() == cat.type.lowercased() ? craftColor(for: cat.type) : craftColor(for: cat.type).opacity(0.08)))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)
            }
        )
    }

    // MARK: - Tag Filter Chips

    private var tagFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(tagStore.allTags) { tag in
                    Button {
                        if filterTagIds.contains(tag.id) {
                            filterTagIds.remove(tag.id)
                        } else {
                            filterTagIds.insert(tag.id)
                        }
                    } label: {
                        Text(tag.name)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(filterTagIds.contains(tag.id) ? .white : Theme.deepPlum.opacity(0.55))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(filterTagIds.contains(tag.id) ? Theme.softCoral : Theme.softCoral.opacity(0.08))
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
        }
    }

    // MARK: - Continue In-Progress Card (progress bar + dismiss)

    private var inProgressPatterns: [Pattern] {
        store.patterns
            .filter { $0.status == .inProgress }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private func continueCardLabel(pattern: Pattern) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            ZStack {
                Circle()
                    .fill(Theme.softCoral.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: "heart.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.softCoral)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Continue \(pattern.title)")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.deepPlum)
                    .lineLimit(1)
                Text("\(Int(continueProgressPercent(for: pattern) * 100))%")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.deepPlum.opacity(0.45))
            }
        }
    }

    @ViewBuilder
    private func continueCard(pattern: Pattern) -> some View {
        if dismissedContinuePatternIds.contains(pattern.id) {
            EmptyView()
        } else {
            continueCardContent(pattern: pattern)
        }
    }

    private func continueCardContent(pattern: Pattern) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Theme.Spacing.md) {
                Group {
                    if pattern.isEnriching {
                        Button { enrichingAlertPatternId = pattern.id; showEnrichingAlert = true } label: {
                            continueCardLabel(pattern: pattern)
                        }
                    } else {
                        NavigationLink(destination: PatternDetailView(store: store, pattern: pattern)) {
                            continueCardLabel(pattern: pattern)
                        }
                    }
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)

                Button { dismissContinueCard(for: pattern.id) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.deepPlum.opacity(0.4))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss continue card")
                .accessibilityHint("Hides this card until the next app launch")
            }
            .padding(Theme.Spacing.lg)

            ProgressView(value: continueProgressPercent(for: pattern), total: 1)
                .tint(Theme.softCoral)
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.md)
        }
        .elevatedCardStyle()
        .padding(.horizontal, Theme.Spacing.lg)
    }

    private func continueProgressPercent(for pattern: Pattern) -> Double {
        let fromStore = progressStore.progressFraction(for: pattern.id)
        if fromStore > 0 { return fromStore }
        return noteBasedProgress[pattern.id] ?? 0
    }

    /// When progress store has no data, parse latest progress_update note (e.g. "10 of 100 rows") for continue cards.
    private func loadContinueCardProgressFallback() async {
        let inProgressList = store.patterns.filter { $0.status == .inProgress }
        for pattern in inProgressList where progressStore.progressFraction(for: pattern.id) == 0 {
            await continueNoteStore.load(patternId: pattern.id)
            let progressNotes = continueNoteStore.notes.filter { $0.noteType == .progressUpdate }
            guard let last = progressNotes.last else { continue }
            if let frac = Self.parseProgressFromNoteContent(last.content) {
                await MainActor.run { noteBasedProgress[pattern.id] = frac }
            }
        }
    }

    /// Parses "10 of 100", "10/100", or "50%" from note content → 0...1.
    private static func parseProgressFromNoteContent(_ content: String) -> Double? {
        let s = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return nil }
        if let percent = s.firstMatch(of: #/(\d+)\s*%/#), let n = Int(percent.1), n >= 0, n <= 100 {
            return Double(n) / 100
        }
        if let ofMatch = s.firstMatch(of: #/(\d+)\s+of\s+(\d+)/#), let a = Int(ofMatch.1), let b = Int(ofMatch.2), b > 0 {
            return min(1, max(0, Double(a) / Double(b)))
        }
        if let slashMatch = s.firstMatch(of: #/(\d+)\s*/\s*(\d+)/#), let a = Int(slashMatch.1), let b = Int(slashMatch.2), b > 0 {
            return min(1, max(0, Double(a) / Double(b)))
        }
        return nil
    }

    // MARK: - Recent Section

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .firstTextBaseline) {
                Text("Recent")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.deepPlum)
                Spacer()
                Text("Latest wins")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.deepPlum.opacity(0.45))
            }
            .padding(.horizontal, Theme.Spacing.lg)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.md) {
                    ForEach(Array(store.patterns.sorted { $0.createdAt > $1.createdAt }.prefix(6).enumerated()), id: \.element.id) { index, pattern in
                        Group {
                            if pattern.isEnriching {
                                Button { enrichingAlertPatternId = pattern.id; showEnrichingAlert = true } label: {
                                    PatternCardView(
                                        pattern: pattern,
                                        userId: auth.currentUserId,
                                        isFavorite: pattern.status == .wantToMake,
                                        isNew: isRecentlyAdded(pattern),
                                        elevated: true,
                                        subtitle: domainFromURL(pattern.sourceUrl) ?? pattern.sourcePlatform
                                    )
                                    .frame(width: 168)
                                }
                            } else {
                                NavigationLink(destination: PatternDetailView(store: store, pattern: pattern)) {
                                    PatternCardView(
                                        pattern: pattern,
                                        userId: auth.currentUserId,
                                        isFavorite: pattern.status == .wantToMake,
                                        isNew: isRecentlyAdded(pattern),
                                        elevated: true,
                                        subtitle: domainFromURL(pattern.sourceUrl) ?? pattern.sourcePlatform
                                    )
                                    .frame(width: 168)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .staggeredAppear(index: index)
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.xs)
            }
        }
    }

    // MARK: - All Patterns Grid

    private var allPatternsGrid: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            if isSelectionMode {
                Text("Tap patterns to select, then tap Delete")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.deepPlum.opacity(0.6))
                    .padding(.horizontal, Theme.Spacing.lg)
            } else if store.patterns.count > 6 || filterStatus != nil || !searchText.isEmpty {
                Text(filterStatus != nil || !searchText.isEmpty ? "Results" : "All Patterns")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.deepPlum)
                    .padding(.horizontal, Theme.Spacing.lg)
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: Theme.Spacing.md),
                    GridItem(.flexible(), spacing: Theme.Spacing.md)
                ],
                spacing: Theme.Spacing.md
            ) {
                ForEach(filteredPatterns, id: \.id) { pattern in
                    if isSelectionMode {
                        Button {
                            if selectedPatternIds.contains(pattern.id) {
                                selectedPatternIds.remove(pattern.id)
                            } else {
                                selectedPatternIds.insert(pattern.id)
                            }
                            HapticService.lightImpact()
                        } label: {
                            ZStack(alignment: .topTrailing) {
                                PatternCardView(
                                    pattern: pattern,
                                    userId: auth.currentUserId,
                                    isFavorite: pattern.status == .wantToMake,
                                    isNew: isRecentlyAdded(pattern)
                                )
                                .opacity(selectedPatternIds.contains(pattern.id) ? 0.85 : 1)
                                if selectedPatternIds.contains(pattern.id) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 24))
                                        .foregroundStyle(Theme.sageGreen)
                                        .background(Circle().fill(.white).padding(2))
                                        .padding(Theme.Spacing.sm)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    } else if pattern.isEnriching {
                        Button { enrichingAlertPatternId = pattern.id; showEnrichingAlert = true } label: {
                            PatternCardView(
                                pattern: pattern,
                                userId: auth.currentUserId,
                                isFavorite: pattern.status == .wantToMake,
                                isNew: isRecentlyAdded(pattern)
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                    } else {
                        NavigationLink(destination: PatternDetailView(store: store, pattern: pattern)) {
                            PatternCardView(
                                pattern: pattern,
                                userId: auth.currentUserId,
                                isFavorite: pattern.status == .wantToMake,
                                isNew: isRecentlyAdded(pattern)
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
        }
    }

    // MARK: - Populated View

    @ViewBuilder
    private var populatedView: some View {
        headerSection
            .tutorialAnchor(.patternsAdd, isActive: currentStepAnchor == .patternsAdd)
        nextActionBanner
        searchBar
            .tutorialAnchor(.patternsSearch, isActive: currentStepAnchor == .patternsSearch)
        statusFilters
        craftCategoryChips

        if !tagStore.allTags.isEmpty {
            tagFilters
        }

        ForEach(inProgressPatterns) { pattern in
            continueCard(pattern: pattern)
        }

        if store.patterns.count > 2 && filterStatus == nil && searchText.isEmpty && !isSelectionMode {
            recentSection
        }

        if !SubscriptionStore.shared.isPremium && store.patterns.count >= 25 {
            premiumNudgeRow
        }

        allPatternsGrid
    }

    private var premiumNudgeRow: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text("Nearing your free limit. Premium unlocks unlimited.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.deepPlum.opacity(0.55))
            Button(Theme.Premium.seePremiumTitle) {
                if GrowthOrchestrator.shared.canShowPaywall(source: .patternLimit) {
                    showPaywall = true
                }
            }
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.softCoral)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.xs)
    }

    private var nextActionBanner: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "sparkles")
                .font(.system(size: 14))
                .foregroundStyle(Theme.honey)
            VStack(alignment: .leading, spacing: 2) {
                Text(nextActionTitle)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.deepPlum)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Text(nextActionSubtitle)
                    .font(Theme.Typography.caption2)
                    .foregroundStyle(Theme.deepPlum.opacity(0.55))
                    .lineLimit(3)
                    .minimumScaleFactor(0.85)
            }
            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.lg)
    }

    private var nextActionTitle: String {
        if !inProgressPatterns.isEmpty {
            return "Next: continue your active project"
        }
        return "Next: add a pattern you'll make soon"
    }

    private var nextActionSubtitle: String {
        if !inProgressPatterns.isEmpty {
            return "A quick update now keeps your momentum and streak alive."
        }
        return "Small saves now make planning and progress tracking easier."
    }

    // MARK: - Loading State

    private var loadingView: some View {
        VStack(spacing: Theme.Spacing.lg) {
            headerSection
            Spacer().frame(height: 40)
            SpriteMascotView.thinking(size: 100)
                .accessibilityHidden(true)
            Text("Loading patterns...")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.deepPlum.opacity(0.6))
            Spacer().frame(height: 100)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Loading patterns")
    }

    // MARK: - Empty State (Welcome)

    private var emptyView: some View {
        VStack(spacing: 0) {
            headerSection

            Spacer().frame(height: 50)

            VStack(spacing: Theme.Spacing.xl) {
                TappableMascotView(size: 160)

                VStack(spacing: Theme.Spacing.sm) {
                    Text("Ready for your first save?")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.deepPlum)
                        .minimumScaleFactor(0.85)

                    Text("Add one pattern now, then come back to track rows and celebrate progress.")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.deepPlum.opacity(0.55))
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .minimumScaleFactor(0.9)
                }

                Button {
                    HapticService.lightImpact()
                    showAddSheet = true
                } label: {
                    Text("Save first pattern")
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 40)
                .accessibilityLabel("Save first pattern")
                .accessibilityHint("Add your first pattern")
            }
            .padding(.horizontal, Theme.Spacing.xl)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Ready for your first save. Add one pattern now, then track rows and celebrate progress.")
    }

    // MARK: - Error State

    @ViewBuilder
    private func errorView(_ error: String) -> some View {
        headerSection

        VStack(spacing: Theme.Spacing.lg) {
            Spacer().frame(height: 40)
            SpriteMascotView.pouty(size: 100)
                .accessibilityHidden(true)
            Text(error)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.softCoral)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Try again") {
                store.errorMessage = nil
                if let userId = auth.currentUserId {
                    Task { await store.load(userId: userId) }
                }
            }
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.deepPlum)
            .accessibilityLabel("Try again")
            .accessibilityHint("Reload your patterns")
            if error.localizedCaseInsensitiveContains("Premium") || error.localizedCaseInsensitiveContains("limit") {
                Button(Theme.Premium.seePremiumTitle) {
                    if GrowthOrchestrator.shared.canShowPaywall(source: .patternLimit) {
                        showPaywall = true
                    }
                }
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.softCoral)
                .accessibilityLabel(Theme.Premium.seePremiumTitle)
                .accessibilityHint("Opens Premium")
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error loading patterns. Try again button.")
    }

    // MARK: - Helpers

    private struct CraftTypeCount: Hashable {
        let type: String
        let count: Int
    }

    private var craftTypeCounts: [CraftTypeCount] {
        var counts: [String: Int] = [:]
        for p in store.patterns {
            if let ct = p.craftType, !ct.isEmpty {
                counts[ct.lowercased(), default: 0] += 1
            }
        }
        return counts.sorted { $0.value > $1.value }
            .prefix(5)
            .map { CraftTypeCount(type: $0.key, count: $0.value) }
    }

    private func craftIcon(for type: String) -> String {
        switch type.lowercased() {
        case let c where c.contains("knit"): return "scissors"
        case let c where c.contains("crochet"): return "hurricane"
        case let c where c.contains("sew"), let c where c.contains("quilt"): return "rectangle.split.2x2"
        case let c where c.contains("embroider"): return "paintbrush.pointed"
        case let c where c.contains("weav"): return "square.grid.3x3"
        case let c where c.contains("macram"): return "circle.grid.cross"
        case let c where c.contains("leather"): return "rectangle.3.group"
        case let c where c.contains("bead"): return "circle.hexagongrid.fill"
        case let c where c.contains("jewelry"), let c where c.contains("jewell"): return "diamond"
        case let c where c.contains("paper"): return "doc.fill"
        case let c where c.contains("wood"): return "hammer.fill"
        default: return "sparkles"
        }
    }

    private func craftColor(for type: String) -> Color {
        switch type.lowercased() {
        case let c where c.contains("knit"): return Theme.softCoral
        case let c where c.contains("crochet"): return Theme.deepPlum
        case let c where c.contains("sew"), let c where c.contains("quilt"): return Theme.sageGreen
        case let c where c.contains("embroider"): return Theme.honey
        case let c where c.contains("weav"): return Theme.dustyBlue
        case let c where c.contains("macram"): return Theme.softCoral
        case let c where c.contains("leather"): return Theme.deepPlum.opacity(0.9)
        case let c where c.contains("bead"): return Theme.dustyBlue
        case let c where c.contains("jewelry"), let c where c.contains("jewell"): return Theme.honey
        case let c where c.contains("paper"): return Theme.sageGreen
        case let c where c.contains("wood"): return Theme.softCoral
        default: return Theme.softCoral
        }
    }

    private var userInitial: String? {
        if let name = auth.displayName, let first = name.first {
            return String(first).uppercased()
        }
        if let email = auth.userEmail, let first = email.first {
            return String(first).uppercased()
        }
        return nil
    }

    private func domainFromURL(_ urlString: String) -> String? {
        guard let url = URL(string: urlString), let host = url.host else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private func isRecentlyAdded(_ pattern: Pattern) -> Bool {
        pattern.createdAt > Date().addingTimeInterval(-7 * 24 * 60 * 60)
    }

    private func loadPatternTagsMap() async {
        let repo = TagRepository()
        var map: [UUID: Set<UUID>] = [:]
        await withTaskGroup(of: (UUID, Set<UUID>)?.self) { group in
            for pattern in store.patterns {
                group.addTask {
                    if let tags = try? await repo.fetchTags(forPatternId: pattern.id) {
                        return (pattern.id, Set(tags.map(\.id)))
                    }
                    return nil
                }
            }
            for await result in group {
                if let (patternId, tagIds) = result {
                    map[patternId] = tagIds
                }
            }
        }
        patternTagsMap = map
    }
}
