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
    @Binding var sharedURL: String?

    @Environment(\.scenePhase) private var scenePhase
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
    @ObservedObject private var progressStore = PatternProgressStore.shared
    @StateObject private var continueNoteStore = ProjectNoteStore()
    @State private var noteBasedProgress: [UUID: Double] = [:]

    private var filteredPatterns: [Pattern] {
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
        return result
    }

    var body: some View {
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
            .sheet(isPresented: $showAddSheet, onDismiss: { sharedURL = nil }) {
                AddPatternView(store: store, prefillURL: sharedURL)
            }
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
                await tagStore.loadAllTags()
                await loadPatternTagsMap()
                await loadContinueCardProgressFallback()
            }
            .onChange(of: sharedURL) { _, newURL in
                if newURL != nil { showAddSheet = true }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    Task { await loadPatternTagsMap() }
                }
            }
            .onAppear { loadDismissedContinueIds() }
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

            Text("My Patterns")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.deepPlum)

            Spacer()

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
            .accessibilityHint("Opens filter options by status")
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .sheet(isPresented: $showFilterOptions) {
            filterOptionsSheet
        }
    }

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
                statusPill("Favorites", icon: "heart.fill", isSelected: filterStatus == .wantToMake) {
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
                        .background(craftColor(for: cat.type).opacity(0.08))
                        .clipShape(Capsule())
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
                NavigationLink(destination: PatternDetailView(store: store, pattern: pattern)) {
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

    /// When progress store has no data, parse latest progress_update note (e.g. "10 of 100 rows") for continue card.
    private func loadContinueCardProgressFallback() async {
        guard let inProgress = store.patterns.first(where: { $0.status == .inProgress }),
              progressStore.progressFraction(for: inProgress.id) == 0 else { return }
        await continueNoteStore.load(patternId: inProgress.id)
        let progressNotes = continueNoteStore.notes.filter { $0.noteType == .progressUpdate }
        guard let last = progressNotes.last else { return }
        if let frac = Self.parseProgressFromNoteContent(last.content) {
            noteBasedProgress[inProgress.id] = frac
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

    // MARK: - Trending Section

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .firstTextBaseline) {
                Text("Trending")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.deepPlum)
                Spacer()
                Button { showAddSheet = true } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                        Text("Add")
                            .font(Theme.Typography.caption)
                    }
                    .foregroundStyle(Theme.softCoral)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Theme.softCoral.opacity(0.12))
                    .clipShape(Capsule())
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.md) {
                    ForEach(Array(store.patterns.prefix(6).enumerated()), id: \.element.id) { index, pattern in
                        NavigationLink(destination: PatternDetailView(store: store, pattern: pattern)) {
                            PatternCardView(
                                pattern: pattern,
                                isFavorite: pattern.status == .wantToMake,
                                isNew: isRecentlyAdded(pattern),
                                elevated: true,
                                subtitle: domainFromURL(pattern.sourceUrl) ?? pattern.sourcePlatform
                            )
                            .frame(width: 168)
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
            if store.patterns.count > 6 || filterStatus != nil || !searchText.isEmpty {
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
                ForEach(Array(filteredPatterns.enumerated()), id: \.element.id) { index, pattern in
                    NavigationLink(destination: PatternDetailView(store: store, pattern: pattern)) {
                        PatternCardView(
                            pattern: pattern,
                            isFavorite: pattern.status == .wantToMake,
                            isNew: isRecentlyAdded(pattern)
                        )
                    }
                    .buttonStyle(.plain)
                    .staggeredAppear(index: index)
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
        }
    }

    // MARK: - Populated View

    @ViewBuilder
    private var populatedView: some View {
        headerSection
        searchBar
        statusFilters
        craftCategoryChips

        if !tagStore.allTags.isEmpty {
            tagFilters
        }

        if let inProgressPattern = store.patterns.first(where: { $0.status == .inProgress }) {
            continueCard(pattern: inProgressPattern)
        }

        if store.patterns.count > 2 && filterStatus == nil && searchText.isEmpty {
            recentSection
        }

        allPatternsGrid
    }

    // MARK: - Loading State

    private var loadingView: some View {
        VStack(spacing: Theme.Spacing.lg) {
            headerSection
            Spacer().frame(height: 40)
            SpriteMascotView.walking(size: 100)
            Text("Loading patterns...")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.deepPlum.opacity(0.6))
            Spacer().frame(height: 100)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Empty State (Welcome)

    private var emptyView: some View {
        VStack(spacing: 0) {
            headerSection

            Spacer().frame(height: 50)

            VStack(spacing: Theme.Spacing.xl) {
                SpriteMascotView.idle(size: 160)

                VStack(spacing: Theme.Spacing.sm) {
                    Text("Welcome to Pattern Vault!")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.deepPlum)

                    Text("Discover, organize, and manage\nyour patterns with ease.")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.deepPlum.opacity(0.55))
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }

                Button { showAddSheet = true } label: {
                    Text("Get Started")
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 40)
            }
            .padding(.horizontal, Theme.Spacing.xl)
        }
    }

    // MARK: - Error State

    @ViewBuilder
    private func errorView(_ error: String) -> some View {
        headerSection

        VStack(spacing: Theme.Spacing.lg) {
            Spacer().frame(height: 40)
            SpriteMascotView.pouty(size: 100)
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
        }
        .frame(maxWidth: .infinity)
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
        for pattern in store.patterns {
            if let tags = try? await repo.fetchTags(forPatternId: pattern.id) {
                map[pattern.id] = Set(tags.map(\.id))
            }
        }
        patternTagsMap = map
    }
}
