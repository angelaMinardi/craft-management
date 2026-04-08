//
//  PatternDetailView.swift
//  PatternVault
//

import SwiftUI
import WebKit
import UIKit

struct PatternDetailView: View {
    @EnvironmentObject var auth: AuthService
    @ObservedObject var store: PatternStore
    let pattern: Pattern

    @StateObject private var noteStore = ProjectNoteStore()
    @StateObject private var tagStore = TagStore()
    @StateObject private var imageStore = PatternImageStore()
    @StateObject private var yarnLinkStore = PatternYarnLinkStore()
    @State private var isEditingTitle = false
    @State private var editTitle = ""
    @State private var editDescription = ""
    @State private var showDeleteConfirm = false
    @State private var showAddNote = false
    @State private var showTagPicker = false
    @State private var showWebView = false
    @State private var showPdfViewer = false
    @State private var makes: [PatternMake] = []
    @State private var selectedMakeId: UUID?
    @State private var showAddMakeSheet = false
    @State private var showPremiumPaywall = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let makeRepo = PatternMakeRepository()
    @ObservedObject private var progressStore = PatternProgressStore.shared

    var current: Pattern {
        store.patterns.first(where: { $0.id == pattern.id }) ?? pattern
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            GeometryReader { geo in
                let contentWidth = max(geo.size.width, 1)
                ScrollView {
                    VStack(spacing: 0) {
                        // MARK: - Hero
                        heroSection
                            .frame(width: contentWidth)

                        // MARK: - Pattern header card (mascot + title + Download)
                        patternHeaderCard
                            .frame(width: contentWidth)

                        // MARK: - Main content (padded)
                        VStack(spacing: Theme.Spacing.xl) {
                            nextActionSummary
                            titleSection
                            statusPicker
                            if current.status == .wantToMake {
                                startProjectBanner
                            }
                            makePickerSection

                            // MARK: - Step 1 / Progress (mockup-style)
                            PatternStepSectionView(
                                pattern: current,
                                store: store,
                                noteStore: noteStore,
                                progressStore: progressStore,
                                selectedMakeId: $selectedMakeId
                            )

                            PatternChartsSectionView(pattern: current)

                        if hasPatternInfo {
                            patternInfoSection
                        }

                        if !yarnLinkStore.links.isEmpty {
                            yarnLinksSection
                        }
                        if !similarPatterns.isEmpty {
                            similarInVaultSection
                        }
                        }
                        .padding(.horizontal, Theme.Spacing.lg)
                        .frame(width: contentWidth)
                        .padding(.top, Theme.Spacing.xl)

                        // MARK: - Photo gallery (full-bleed horizontal scroll)
                        if !imageStore.images.isEmpty {
                            photoGallery
                                .padding(.top, Theme.Spacing.xl)
                        }

                        // MARK: - Bottom sections (padded)
                        VStack(spacing: Theme.Spacing.xl) {
                            sourceSection
                            tagsSection
                            notesSection

                            if let error = noteStore.errorMessage {
                                Text(error)
                                    .font(Theme.Typography.caption)
                                    .foregroundStyle(Theme.softCoral)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            deleteButton
                        }
                        .padding(.horizontal, Theme.Spacing.lg)
                        .frame(width: contentWidth)
                        .padding(.top, Theme.Spacing.xl)
                        .padding(.bottom, 120)
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: 84)
            }
            .background(Theme.screenGradient.ignoresSafeArea())

            // Floating tool palette + mascot peek (mockup-style)
            FloatingToolPaletteView(
                pattern: current,
                noteStore: noteStore,
                progressStore: progressStore,
                selectedMakeId: $selectedMakeId
            )
        }
        .navigationTitle(current.title)
        .navigationBarTitleDisplayMode(.inline)
        .modifier(PatternDetailToolbar(
            pattern: current,
            showWebView: $showWebView,
            showPdfViewer: $showPdfViewer
        ))
        .confirmationDialog("Delete Pattern", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) { deletePattern() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will also delete all notes. This cannot be undone.")
        }
        .sheet(isPresented: $showAddNote) {
            AddNoteView(noteStore: noteStore, patternId: current.id)
        }
        .sheet(isPresented: $showTagPicker) {
            TagPickerView(tagStore: tagStore, patternId: current.id)
        }
        .sheet(isPresented: $showWebView) {
            NavigationStack {
                if let url = URL(string: current.sourceUrl) {
                    InAppWebView(url: url)
                        .navigationTitle("Pattern Page")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") { showWebView = false }
                            }
                            ToolbarItem(placement: .primaryAction) {
                                Link(destination: url) {
                                    Image(systemName: "safari")
                                }
                            }
                        }
                } else {
                    Text("Invalid URL")
                        .foregroundColor(.secondary)
                }
            }
        }
        .sheet(isPresented: $showPdfViewer) {
            if let pdfUrlString = current.pdfUrl, let pdfURL = URL(string: pdfUrlString) {
                NavigationStack {
                    PDFViewerView(
                        url: pdfURL,
                        patternId: current.id,
                        makeId: selectedMakeId,
                        onDetectCharts: { store.extractChartsFromPDF(patternId: current.id) }
                    )
                        .navigationTitle("Pattern PDF")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") { showPdfViewer = false }
                            }
                        }
                }
            }
        }
        .sheet(isPresented: $showAddMakeSheet) {
            AddPatternMakeView(patternId: current.id, existingCount: makes.count) { newMake in
                makes.append(newMake)
                selectedMakeId = newMake.id
            }
        }
        .sheet(isPresented: $showPremiumPaywall) {
            PaywallView(source: .settings)
        }
        .task {
            async let notes: () = noteStore.load(patternId: current.id)
            async let tags: () = tagStore.loadPatternTags(patternId: current.id)
            _ = await (notes, tags)

            async let allTags: () = tagStore.loadAllTags()
            async let images: () = imageStore.load(patternId: current.id)
            if let userId = auth.currentUserId {
                async let yarnLinks: () = yarnLinkStore.load(patternId: current.id, userId: userId)
                async let makesLoad: () = loadMakes()
                _ = await (allTags, images, yarnLinks, makesLoad)
            } else {
                async let makesLoad: () = loadMakes()
                _ = await (allTags, images, makesLoad)
            }
        }
        .refreshable {
            if let userId = auth.currentUserId {
                await store.refreshPattern(id: current.id, userId: userId)
            }
            await noteStore.load(patternId: current.id)
            await tagStore.loadPatternTags(patternId: current.id)
            await imageStore.load(patternId: current.id)
            if let userId = auth.currentUserId {
                await yarnLinkStore.load(patternId: current.id, userId: userId)
            }
            await loadMakes()
        }
        .task(id: current.enrichmentStatus) {
            guard current.isEnriching, let userId = auth.currentUserId else { return }
            // Poll for enrichment completion
            for _ in 0..<12 {
                try? await Task.sleep(for: .seconds(5))
                await store.refreshPattern(id: current.id, userId: userId)
                if !current.isEnriching { break }
            }
        }
    }

    private func loadMakes() async {
        guard let userId = auth.currentUserId else { return }
        do {
            makes = try await makeRepo.fetchMakes(patternId: current.id, userId: userId)
            if selectedMakeId != nil && !makes.contains(where: { $0.id == selectedMakeId }) {
                selectedMakeId = nil
            }
        } catch { }
    }

    // MARK: - Hero Image

    private var heroSection: some View {
        ZStack(alignment: .bottom) {
            if let thumbnailUrl = current.thumbnailUrl, let imageURL = URL(string: thumbnailUrl) {
                CachedAsyncImage(url: imageURL, userId: auth.currentUserId) { phase in
                    switch phase {
                    case .loading:
                        Rectangle()
                            .fill(Theme.warmCream)
                            .frame(height: 260)
                            .overlay { ProgressView() }
                    case .success(let image):
                        image.resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(height: 260)
                            .clipped()
                    case .failure:
                        heroPlaceholder
                    }
                }
            } else {
                heroPlaceholder
            }

            // Bottom gradient for overlaid elements
            LinearGradient(
                colors: [.clear, .clear, .black.opacity(0.45)],
                startPoint: .top,
                endPoint: .bottom
            )

            // Overlaid status + source platform
            HStack(alignment: .bottom) {
                StatusBadge(status: current.status)
                Spacer()
                if let platform = current.sourcePlatform ?? domainFromURL(current.sourceUrl) {
                    Text(platform)
                        .font(Theme.Typography.caption2)
                        .foregroundStyle(Theme.Semantic.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Theme.warmCream.opacity(0.94))
                        )
                        .overlay(
                            Capsule()
                                .stroke(Theme.Semantic.borderStandard, lineWidth: 1)
                        )
                        .clipShape(Capsule())
                }
            }
            .padding(Theme.Spacing.lg)
        }
        .frame(height: current.thumbnailUrl != nil ? 260 : 140)
        .clipped()
    }

    private var heroPlaceholder: some View {
        LinearGradient(
            colors: [
                Theme.softCoral.opacity(0.15),
                Theme.deepPlum.opacity(0.08),
                Theme.dustyBlue.opacity(0.1)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .frame(height: 140)
        .overlay {
            HStack(spacing: 20) {
                Image(systemName: "scissors")
                    .font(.system(size: 28))
                    .foregroundStyle(Theme.deepPlum.opacity(0.12))
                Image(systemName: "ruler")
                    .font(.system(size: 24))
                    .foregroundStyle(Theme.softCoral.opacity(0.12))
                Image(systemName: "tag")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.deepPlum.opacity(0.1))
            }
        }
    }

    // MARK: - Pattern header card (mascot on card, title, meta, Download)

    private var patternHeaderCard: some View {
        ZStack(alignment: .top) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text(current.title)
                    .font(Theme.Typography.titleBold)
                    .foregroundStyle(Theme.deepPlum)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 52)

                HStack(spacing: 6) {
                    if let platform = current.sourcePlatform ?? domainFromURL(current.sourceUrl) {
                        Text(platform)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.deepPlum.opacity(0.6))
                    }
                    if let diff = current.difficulty, !diff.isEmpty {
                        if current.sourcePlatform != nil || domainFromURL(current.sourceUrl) != nil {
                            Text("•")
                                .foregroundStyle(Theme.deepPlum.opacity(0.4))
                        }
                        Text(diff.capitalized)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.deepPlum.opacity(0.6))
                    }
                }

                if current.isEnriching {
                    enrichmentBanner(
                        icon: "sparkles",
                        text: "Finishing AI extraction… We'll notify you when it's ready.",
                        color: Theme.dustyBlue,
                        showSpinner: true
                    )
                } else if current.enrichmentFailed {
                    Button {
                        Task {
                            guard let userId = auth.currentUserId else { return }
                            await store.retryEnrichment(pattern: current, userId: userId)
                        }
                    } label: {
                        enrichmentBanner(
                            icon: "exclamationmark.triangle.fill",
                            text: "Details incomplete — tap to retry",
                            color: Theme.softCoral,
                            showSpinner: false
                        )
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    if current.pdfUrl != nil { showPdfViewer = true }
                    else if current.sourceContent != nil { showWebView = true }
                    else { showWebView = true }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: current.pdfUrl != nil ? "arrow.down.circle.fill" : "globe")
                            .font(.system(size: 18))
                        Text(
                            current.pdfUrl != nil ? "Download Pattern" :
                            current.sourceContent != nil ? "View Pattern" : "Open in Browser"
                        )
                        .font(Theme.Typography.headline)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.sageGreen)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(current.pdfUrl != nil ? "Download Pattern" : current.sourceContent != nil ? "View Pattern" : "Open in Browser")
                .accessibilityHint("Opens the pattern PDF or source in browser")
            }
            .padding(Theme.Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.large))
            .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 4)
            .padding(.horizontal, Theme.Spacing.lg)
            .offset(y: -24)

            SpriteMascotView.idle(size: 72)
                .offset(y: -36)
        }
        .padding(.bottom, Theme.Spacing.sm)
    }

    // MARK: - Enrichment Banner

    private func enrichmentBanner(icon: String, text: String, color: Color, showSpinner: Bool) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            if showSpinner {
                ProgressView()
                    .controlSize(.small)
                    .tint(color)
            } else {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(color)
            }
            Text(text)
                .font(Theme.Typography.footnoteSemibold)
                .foregroundStyle(Theme.deepPlum.opacity(0.8))
            Spacer()
        }
        .padding(.vertical, Theme.Spacing.sm)
        .padding(.horizontal, Theme.Spacing.md)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.small))
    }

    // MARK: - Title & Description

    private var nextActionSummary: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "sparkles")
                .font(.system(size: 13))
                .foregroundStyle(Theme.honey)
            VStack(alignment: .leading, spacing: 2) {
                Text(nextActionTitle)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.deepPlum)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Text(nextActionReward)
                    .font(Theme.Typography.caption2)
                    .foregroundStyle(Theme.deepPlum.opacity(0.55))
                    .lineLimit(3)
                    .minimumScaleFactor(0.85)
            }
            Spacer()
        }
        .padding(.vertical, Theme.Spacing.sm)
        .padding(.horizontal, Theme.Spacing.md)
        .background(Theme.honey.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
        .accessibilityElement(children: .combine)
    }

    private var nextActionTitle: String {
        switch current.status {
        case .wantToMake:
            return "Next: start this project"
        case .inProgress:
            return "Next: log your latest progress"
        case .completed:
            return "Nice work - share or save notes for your next make"
        }
    }

    private var nextActionReward: String {
        switch current.status {
        case .wantToMake:
            return "Starting now unlocks row tracking and milestone celebrations."
        case .inProgress:
            return "Small updates keep momentum and make the next session easier."
        case .completed:
            return "Captured wins help you repeat success faster on future projects."
        }
    }

    private var titleSection: some View {
        Group {
            if isEditingTitle {
                editTitleCard
            } else {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    if let desc = current.patternDescription, !desc.isEmpty {
                        Text(desc)
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.deepPlum.opacity(0.6))
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if hasQuickInfo {
                        HStack(spacing: Theme.Spacing.sm) {
                            if let craftType = current.craftType, !craftType.isEmpty {
                                quickInfoPill(icon: "scissors", text: craftType.capitalized)
                            }
                            if let difficulty = current.difficulty, !difficulty.isEmpty {
                                quickInfoPill(icon: "chart.bar", text: difficulty.capitalized)
                            }
                        }
                    }
                    Text("Tap to edit title and description")
                        .font(Theme.Typography.caption2)
                        .foregroundStyle(Theme.deepPlum.opacity(0.4))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    editTitle = current.title
                    editDescription = current.patternDescription ?? ""
                    isEditingTitle = true
                }
            }
        }
    }

    private var editTitleCard: some View {
        VStack(spacing: Theme.Spacing.md) {
            TextField("Title", text: $editTitle)
                .font(Theme.Typography.sectionTitle)
                .foregroundStyle(Theme.deepPlum)

            TextField("Description", text: $editDescription, axis: .vertical)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.deepPlum.opacity(0.7))
                .lineLimit(2...6)

            HStack(spacing: Theme.Spacing.md) {
                Button { saveEdit() } label: {
                    Text("Save")
                        .font(Theme.Typography.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(Theme.softCoral)
                        .clipShape(Capsule())
                }
                Button { isEditingTitle = false } label: {
                    Text("Cancel")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.deepPlum.opacity(0.5))
                }
                Spacer()
            }
        }
        .padding(Theme.Spacing.lg)
        .borderedCard(borderColor: Theme.softCoral.opacity(0.3))
    }

    // MARK: - Start project (when status is Want to Make)

    private var startProjectBanner: some View {
        Button {
            changeStatus(to: .inProgress)
        } label: {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: "hammer.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.honey)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Start project")
                        .font(Theme.Typography.callout)
                        .foregroundStyle(Theme.deepPlum)
                    Text("Track rows, keep momentum, and unlock your next celebration.")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.deepPlum.opacity(0.65))
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.deepPlum.opacity(0.4))
            }
            .padding(Theme.Spacing.md)
            .background(Theme.honey.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                    .stroke(Theme.honey.opacity(0.35), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Status Picker (horizontal pills)

    private var statusPicker: some View {
        HStack(spacing: Theme.Spacing.sm) {
            ForEach(PatternStatus.allCases, id: \.self) { status in
                Button { changeStatus(to: status) } label: {
                    HStack(spacing: 5) {
                        Image(systemName: Theme.statusIcon(for: status))
                            .font(.system(size: 11, weight: .bold))
                        Text(status.displayName)
                            .font(Theme.Typography.captionSemibold)
                    }
                    .foregroundStyle(
                        current.status == status ? .white : Theme.statusColor(for: status)
                    )
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(
                        current.status == status
                            ? Theme.statusColor(for: status)
                            : Theme.statusColor(for: status).opacity(0.1)
                    )
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().stroke(
                            current.status == status
                                ? Color.clear
                                : Theme.statusColor(for: status).opacity(0.25),
                            lineWidth: 1
                        )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Make Picker (multiple projects per pattern)

    private var makePickerSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Make")
                .font(Theme.Typography.footnoteSemibold)
                .foregroundStyle(Theme.deepPlum.opacity(0.6))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.sm) {
                    Button {
                        selectedMakeId = nil
                    } label: {
                        Text("Default")
                            .font(Theme.Typography.captionSemibold)
                            .foregroundStyle(selectedMakeId == nil ? .white : Theme.dustyBlue)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(selectedMakeId == nil ? Theme.dustyBlue : Theme.dustyBlue.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    ForEach(makes) { make in
                        Button {
                            selectedMakeId = make.id
                        } label: {
                            Text(make.name)
                                .font(Theme.Typography.captionSemibold)
                                .foregroundStyle(selectedMakeId == make.id ? .white : Theme.deepPlum)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(selectedMakeId == make.id ? Theme.softCoral : Theme.softCoral.opacity(0.12))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    Button {
                        if SubscriptionStore.shared.isPremium {
                            showAddMakeSheet = true
                        } else {
                            showPremiumPaywall = true
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: SubscriptionStore.shared.isPremium ? "plus.circle.fill" : "lock.fill")
                                .font(.system(size: 12))
                            Text("Add make")
                                .font(Theme.Typography.captionSemibold)
                        }
                        .foregroundStyle(SubscriptionStore.shared.isPremium ? Theme.sageGreen : Theme.deepPlum.opacity(0.45))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background((SubscriptionStore.shared.isPremium ? Theme.sageGreen : Theme.deepPlum).opacity(0.12))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Pattern Info (bordered card with rows + dividers)

    private struct InfoItem: Identifiable {
        let id = UUID()
        let icon: String
        let label: String
        let value: String
    }

    private var hasPatternInfo: Bool {
        !patternInfoItems.isEmpty || hasVideoUrl
    }

    private var hasVideoUrl: Bool {
        guard let v = current.videoUrl else { return false }
        return !v.isEmpty
    }

    private var similarPatterns: [SimilarPatternResult] {
        PatternSimilarityHelper.similar(to: current, in: store.patterns, limit: 5)
    }

    private var similarInVaultSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeaderView(title: "Similar in your vault")
            VStack(spacing: Theme.Spacing.sm) {
                ForEach(similarPatterns) { result in
                    NavigationLink(value: result.pattern) {
                        HStack(alignment: .top, spacing: Theme.Spacing.md) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(result.pattern.title)
                                    .font(Theme.Typography.cardTitle)
                                    .foregroundStyle(Theme.deepPlum)
                                    .lineLimit(2)
                                if !result.reason.isEmpty {
                                    Text(result.reason)
                                        .font(Theme.Typography.caption2)
                                        .foregroundStyle(Theme.deepPlum.opacity(0.5))
                                }
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.deepPlum.opacity(0.3))
                        }
                        .padding(Theme.Spacing.md)
                        .borderedCard()
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var patternInfoItems: [InfoItem] {
        var items: [InfoItem] = []
        if let m = current.materials, !m.isEmpty { items.append(.init(icon: "basket", label: "Materials", value: m)) }
        if let g = current.gauge, !g.isEmpty { items.append(.init(icon: "ruler", label: "Gauge", value: g)) }
        if let n = current.needleHookSizes, !n.isEmpty { items.append(.init(icon: "hammer", label: "Needles / Hook", value: n)) }
        if let y = current.yarnWeightYardage, !y.isEmpty { items.append(.init(icon: "spool", label: "Yarn & Yardage", value: y)) }
        if let t = current.techniques, !t.isEmpty { items.append(.init(icon: "list.bullet", label: "Techniques", value: t)) }
        return items
    }

    private var patternInfoSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeaderView(title: "Pattern Info")

            VStack(spacing: 0) {
                let items = patternInfoItems

                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        HStack(spacing: Theme.Spacing.sm) {
                            Image(systemName: item.icon)
                                .font(.system(size: 14))
                                .foregroundStyle(Theme.softCoral)
                                .frame(width: 22)
                            Text(item.label)
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.deepPlum.opacity(0.5))
                        }
                        Text(item.value)
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.deepPlum)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.leading, 30)
                    }
                    .padding(.vertical, Theme.Spacing.md)
                    .padding(.horizontal, Theme.Spacing.lg)

                    if index < items.count - 1 || hasVideoUrl {
                        infoDivider
                    }
                }

                // Video link row
                if hasVideoUrl, let videoUrl = current.videoUrl, let url = URL(string: videoUrl) {
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "play.rectangle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.softCoral)
                            .frame(width: 22)
                        Link("Watch tutorial video", destination: url)
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.softCoral)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.softCoral.opacity(0.4))
                    }
                    .padding(.vertical, Theme.Spacing.md)
                    .padding(.horizontal, Theme.Spacing.lg)
                }
            }
            .borderedCard()
        }
    }

    // MARK: - Materials & Supplies

    private var yarnLinksSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeaderView(title: "Materials & supplies")
            Text("Yarn, leather, beads, or other supplies")
                .font(Theme.Typography.caption2)
                .foregroundStyle(Theme.deepPlum.opacity(0.5))

            VStack(spacing: Theme.Spacing.sm) {
                ForEach(yarnLinkStore.links) { link in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(link.brandName)
                                .font(Theme.Typography.headline)
                                .foregroundStyle(Theme.deepPlum)
                            HStack(spacing: Theme.Spacing.md) {
                                if let official = link.officialUrl, !official.isEmpty, let url = URL(string: official) {
                                    Link(destination: url) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "globe").font(.system(size: 10))
                                            Text("Official").font(Theme.Typography.caption)
                                        }
                                        .foregroundStyle(Theme.softCoral)
                                    }
                                }
                                if let storeUrl = link.storeUrl, !storeUrl.isEmpty, let url = URL(string: storeUrl) {
                                    Link(destination: url) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "cart").font(.system(size: 10))
                                            Text("Buy").font(Theme.Typography.caption)
                                        }
                                        .foregroundStyle(Theme.softCoral)
                                    }
                                }
                            }
                        }
                        Spacer()
                    }
                    .padding(Theme.Spacing.lg)
                    .borderedCard()
                }
            }
        }
    }

    // MARK: - Photo Gallery (edge-to-edge horizontal scroll)

    private var photoGallery: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeaderView(title: "Photos")
                .padding(.horizontal, Theme.Spacing.lg)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.sm) {
                    ForEach(imageStore.images) { img in
                        CachedAsyncImage(url: URL(string: img.imageUrl), userId: auth.currentUserId) { phase in
                            switch phase {
                            case .loading:
                                RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                                    .fill(Theme.warmCream)
                                    .frame(width: 160, height: 160)
                                    .overlay { ProgressView() }
                            case .success(let image):
                                image.resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 160, height: 160)
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
                            case .failure:
                                RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                                    .fill(Theme.warmCream)
                                    .frame(width: 160, height: 160)
                                    .overlay {
                                        Image(systemName: "photo")
                                            .font(.title2)
                                            .foregroundStyle(Theme.deepPlum.opacity(0.2))
                                    }
                            }
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)
            }
        }
    }

    // MARK: - Source (bordered card with chevron action rows)

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeaderView(title: "Source")

            VStack(spacing: 0) {
                if let pdfUrlString = current.pdfUrl, !pdfUrlString.isEmpty,
                   URL(string: pdfUrlString) != nil {
                    actionRow(icon: "doc.fill", label: "View PDF", color: Theme.softCoral) {
                        showPdfViewer = true
                    }
                    infoDivider
                }

                if let src = current.sourceContent, !src.isEmpty, !PatternStepParser.looksLikeRavelryChrome(src) {
                    NavigationLink {
                        PatternContentView(pattern: current, store: store)
                    } label: {
                        HStack(spacing: Theme.Spacing.sm) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 14))
                                .foregroundStyle(Theme.dustyBlue)
                                .frame(width: 22)
                            Text("View Pattern Content")
                                .font(Theme.Typography.body)
                                .foregroundStyle(Theme.deepPlum)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.deepPlum.opacity(0.2))
                        }
                        .padding(.vertical, Theme.Spacing.md)
                        .padding(.horizontal, Theme.Spacing.lg)
                    }
                    .accessibilityLabel("View Pattern Content")
                    .accessibilityHint("Opens extracted pattern instructions and details")
                    infoDivider
                }

                actionRow(icon: "globe", label: "Open in Browser", color: Theme.sageGreen) {
                    showWebView = true
                }

                infoDivider

                // Source platform
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "link")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.deepPlum.opacity(0.3))
                        .frame(width: 22)
                    Text(current.sourcePlatform ?? domainFromURL(current.sourceUrl) ?? "Web")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.deepPlum.opacity(0.4))
                    Spacer()
                }
                .padding(.vertical, Theme.Spacing.sm)
                .padding(.horizontal, Theme.Spacing.lg)
            }
            .borderedCard()
        }
    }

    // MARK: - Tags

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeaderView(title: "Tags", trailing: "Edit", action: { showTagPicker = true })

            if tagStore.patternTags.isEmpty {
                Button { showTagPicker = true } label: {
                    HStack(spacing: Theme.Spacing.md) {
                        Image("MascotCurious")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 44, height: 44)
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            Text("Add tags to organize this pattern")
                                .font(Theme.Typography.body)
                                .foregroundStyle(Theme.deepPlum.opacity(0.6))
                            Text("Tap to add tags")
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.deepPlum.opacity(0.4))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(Theme.softCoral)
                    }
                    .padding(Theme.Spacing.lg)
                    .borderedCard()
                }
                .buttonStyle(.plain)
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(tagStore.patternTags) { tag in
                        Text(tag.name)
                            .font(Theme.Typography.footnoteSemibold)
                            .foregroundStyle(Theme.deepPlum)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Theme.chipFill)
                            .clipShape(Capsule())
                    }
                }
                .onTapGesture { showTagPicker = true }
            }
        }
    }

    // MARK: - Notes

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeaderView(title: "Notes (\(noteStore.notes.count))", trailing: "Add", action: { showAddNote = true })

            if noteStore.isLoading {
                HStack {
                    Spacer()
                    ProgressView("Loading notes...")
                        .font(Theme.Typography.caption)
                    Spacer()
                }
                .padding(.vertical, Theme.Spacing.xl)
            } else if noteStore.notes.isEmpty {
                VStack(spacing: Theme.Spacing.lg) {
                    SpriteMascotView.pouty(size: 64)
                    Text("No notes yet")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.deepPlum.opacity(0.6))
                    Text("Tap \"Add\" to create your first note")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.deepPlum.opacity(0.4))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.xl)
                .borderedCard()
            } else {
                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(noteStore.notes) { note in
                        NavigationLink {
                            NoteDetailView(
                                noteStore: noteStore,
                                note: note,
                                patternId: current.id
                            )
                        } label: {
                            NoteRowView(note: note)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Delete

    private var deleteButton: some View {
        Button { showDeleteConfirm = true } label: {
            HStack(spacing: 6) {
                Image(systemName: "trash")
                    .font(.system(size: 13))
                Text("Delete Pattern")
                    .font(Theme.Typography.footnoteSemibold)
            }
            .foregroundStyle(Theme.Semantic.error.opacity(0.5))
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.md)
        }
        .buttonStyle(.plain)
        .padding(.top, Theme.Spacing.md)
    }

    // MARK: - Reusable Helpers

    @ViewBuilder
    private func actionRow(icon: String, label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(color)
                    .frame(width: 22)
                Text(label)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.deepPlum)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.deepPlum.opacity(0.2))
            }
            .padding(.vertical, Theme.Spacing.md)
            .padding(.horizontal, Theme.Spacing.lg)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private func quickInfoPill(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(text)
                .font(Theme.Typography.caption)
        }
        .foregroundStyle(Theme.deepPlum.opacity(0.6))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Theme.deepPlum.opacity(0.06))
        .clipShape(Capsule())
    }

    private var infoDivider: some View {
        Divider()
            .overlay(Theme.deepPlum.opacity(0.06))
            .padding(.leading, 54)
    }

    private var hasQuickInfo: Bool {
        let ct = current.craftType ?? ""
        let diff = current.difficulty ?? ""
        return !ct.isEmpty || !diff.isEmpty
    }

    // MARK: - Actions

    private func changeStatus(to status: PatternStatus) {
        guard let userId = auth.currentUserId else { return }
        Task {
            await store.updateStatus(pattern: current, userId: userId, status: status)
            if status == .inProgress || status == .completed {
                GrowthOrchestrator.shared.registerPositiveEvent(.progressLogged)
                if status == .completed {
                    GrowthOrchestrator.shared.registerPositiveEvent(.patternCompleted)
                }
                GrowthOrchestrator.shared.requestReviewIfEligible()
            }
        }
    }

    private func saveEdit() {
        guard let userId = auth.currentUserId else { return }
        isEditingTitle = false
        Task {
            await store.update(
                pattern: current, userId: userId,
                title: editTitle,
                description: editDescription.isEmpty ? nil : editDescription
            )
        }
    }

    private func deletePattern() {
        guard let userId = auth.currentUserId else { return }
        Task {
            await store.delete(pattern: current, userId: userId)
            dismiss()
        }
    }

    func domainFromURL(_ urlString: String) -> String? {
        guard let url = URL(string: urlString),
              let host = url.host else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

// MARK: - PatternDetailToolbar

private struct PatternDetailToolbar: ViewModifier {
    let pattern: Pattern
    @Binding var showWebView: Bool
    @Binding var showPdfViewer: Bool

    @State private var shareFinishedImage: UIImage?
    @ObservedObject private var progressStore = PatternProgressStore.shared

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(pattern.title)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.deepPlum)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        if pattern.status == .completed {
                            Button {
                                presentFinishedProjectShareCard()
                            } label: {
                                Label("Share finished project", systemImage: "square.and.arrow.up")
                            }
                        }
                        if let url = URL(string: pattern.sourceUrl) {
                            ShareLink(item: url, subject: Text(pattern.title), preview: SharePreview(pattern.title, image: Image(systemName: "doc.text"))) {
                                Label("Share this pattern", systemImage: "link")
                            }
                        }
                        Button {
                            printCurrentStep()
                        } label: {
                            Label("Print current step", systemImage: "printer")
                        }
                        if pattern.sourceContent != nil {
                            Button {
                                printFullContent()
                            } label: {
                                Label("Print full pattern", systemImage: "doc.text")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: Binding(get: { shareFinishedImage != nil }, set: { if !$0 { shareFinishedImage = nil } })) {
                if let img = shareFinishedImage {
                    ShareSheet(image: img)
                }
            }
    }

    private func escapeHtml(_ s: String) -> String {
        s
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "\n", with: "<br>")
    }

    private func printCurrentStep() {
        let contentForSteps = PatternStepParser.truncateAtEndOfPattern(pattern.sourceContent) ?? pattern.sourceContent
        let layout = progressStore.customStepLayout(for: pattern.id)
        let aiInstructions = pattern.decodedParsedInstructions
        let aiSteps = pattern.decodedParsedSteps
        let steps = PatternStepSectionView.computePatternStepsStatic(
            sourceContent: contentForSteps,
            patternDescription: pattern.patternDescription,
            layout: layout,
            aiSteps: aiSteps,
            aiInstructions: aiInstructions
        )
        let index = min(max(0, progressStore.progress(for: pattern.id)?.currentStepIndex ?? 0), max(0, steps.count - 1))
        let title = escapeHtml(pattern.title)
        let source = escapeHtml(pattern.sourceUrl)
        let body: String
        if steps.isEmpty {
            body = "<p><em>No steps yet. Analyze this pattern to split it into steps.</em></p>"
        } else {
            let step = steps[index]
            let stepTitle = escapeHtml(step.title)
            let stepBody = escapeHtml(step.body)
            body = """
            <h2>\(stepTitle)</h2>
            <p>Step \(index + 1) of \(steps.count)</p>
            <div>\(stepBody)</div>
            """
        }
        let html = """
        <!DOCTYPE html><html><head><meta charset="utf-8"><title>\(title)</title></head><body>
        <h1>\(title)</h1>
        <p><small>Source: \(source)</small></p>
        <hr>
        \(body)
        </body></html>
        """
        presentPrintController(html: html)
    }

    private func printFullContent() {
        let title = escapeHtml(pattern.title)
        let source = escapeHtml(pattern.sourceUrl)
        let content = pattern.sourceContent.map { escapeHtml($0) } ?? "<p><em>No content available.</em></p>"
        let html = """
        <!DOCTYPE html><html><head><meta charset="utf-8"><title>\(title)</title></head><body>
        <h1>\(title)</h1>
        <p><small>Source: \(source)</small></p>
        <hr>
        <div>\(content)</div>
        </body></html>
        """
        presentPrintController(html: html)
    }

    private func presentPrintController(html: String) {
        let formatter = UIMarkupTextPrintFormatter(markupText: html)
        let printController = UIPrintInteractionController.shared
        printController.printFormatter = formatter
        printController.present(animated: true)
    }

    private func presentFinishedProjectShareCard() {
        let yarn = progressStore.progress(for: pattern.id)?.yarnColorName
        let card = FinishedProjectShareCardView(
            patternTitle: pattern.title,
            yarnUsed: yarn,
            needleSize: pattern.needleHookSizes,
            notes: nil
        )
        let renderer = ImageRenderer(content: card)
        renderer.proposedSize = .init(width: 400, height: 500)
        renderer.scale = UIScreen.main.scale
        if let img = renderer.uiImage {
            shareFinishedImage = img
        }
    }
}

// MARK: - PatternChartsSectionView

private struct PatternChartsSectionView: View {
    let pattern: Pattern
    @ObservedObject private var chartStore = ChartHighlightStore.shared
    @ObservedObject private var rowCounterStore = RowCounterStore.shared
    @State private var selectedWorkspaceHighlight: ChartHighlight?

    private var aiCharts: [ChartHighlight] {
        chartStore.aiExtractedHighlights(patternId: pattern.id)
    }

    private var legacyCharts: [(url: URL, label: String)] {
        guard aiCharts.isEmpty, let instructions = pattern.decodedParsedInstructions else { return [] }
        var seen = Set<String>()
        var result: [(url: URL, label: String)] = []
        for inst in instructions {
            guard let urlStr = inst.chartImageUrl, let url = URL(string: urlStr) else { continue }
            guard seen.insert(urlStr).inserted else { continue }
            result.append((url: url, label: inst.chartLabel ?? inst.section))
        }
        return result
    }

    var body: some View {
        let interactive = aiCharts
        let legacy = legacyCharts
        if !interactive.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                SectionHeaderView(title: "Charts")

                ForEach(interactive) { highlight in
                    interactiveChartCard(highlight)
                }
            }
            .sheet(item: $selectedWorkspaceHighlight) { highlight in
                ExtractedChartWorkspaceView(
                    highlight: highlight,
                    patternId: pattern.id,
                    makeId: nil,
                    onSave: { chartStore.save($0) }
                )
            }
        } else if !legacy.isEmpty {
            legacyChartsView(legacy)
        }
    }

    @ViewBuilder
    private func interactiveChartCard(_ highlight: ChartHighlight) -> some View {
        let counterState = rowCounterStore.state(for: pattern.id, makeId: nil)
        let rowVal = counterValue(for: highlight.rowCounterLink, state: counterState, fallback: highlight.currentRow)
        let colVal = counterValue(for: highlight.columnCounterLink, state: counterState, fallback: highlight.currentColumn)

        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "chart.bar.doc.horizontal")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.dustyBlue)
                Text(highlight.chartLabel ?? "Chart")
                    .font(Theme.Typography.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.deepPlum)
                Spacer()
                Text("\(highlight.rows) x \(highlight.columns)")
                    .font(Theme.Typography.caption2)
                    .foregroundStyle(Theme.deepPlum.opacity(0.5))
            }

            if let data = highlight.extractedChartPNGData, let uiImage = UIImage(data: data) {
                ZStack {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.small))

                    ChartHighlighterOverlayView(
                        highlight: highlight,
                        rowValue: rowVal,
                        columnValue: colVal
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.small))
                }
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.small)
                        .stroke(Theme.deepPlum.opacity(0.15), lineWidth: 1)
                )
                .onTapGesture { selectedWorkspaceHighlight = highlight }
            }

            HStack(spacing: Theme.Spacing.sm) {
                Label("Row \(rowVal)", systemImage: "arrow.right")
                    .font(Theme.Typography.caption2)
                    .foregroundStyle(Theme.honey)
                Label("Col \(colVal)", systemImage: "arrow.down")
                    .font(Theme.Typography.caption2)
                    .foregroundStyle(Theme.softCoral)
                Spacer()
                Text("Tap to open workspace")
                    .font(Theme.Typography.caption2)
                    .foregroundStyle(Theme.deepPlum.opacity(0.4))
            }
        }
        .cardStyle()
    }

    private func counterValue(for link: ChartHighlight.CounterLink?, state: RowCounterState, fallback: Int) -> Int {
        guard let link else { return fallback }
        switch link {
        case .global:
            return max(1, state.globalRow)
        case .secondary(let id):
            return max(1, state.secondaryCounters.first(where: { $0.id == id })?.currentCount ?? fallback)
        }
    }

    @ViewBuilder
    private func legacyChartsView(_ charts: [(url: URL, label: String)]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeaderView(title: "Charts")
            ForEach(Array(charts.enumerated()), id: \.offset) { _, chart in
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    HStack(spacing: Theme.Spacing.xs) {
                        Image(systemName: "chart.bar.doc.horizontal")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.dustyBlue)
                        Text(chart.label)
                            .font(Theme.Typography.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.deepPlum)
                    }
                    AsyncImage(url: chart.url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.small))
                                .overlay(
                                    RoundedRectangle(cornerRadius: Theme.CornerRadius.small)
                                        .stroke(Theme.deepPlum.opacity(0.15), lineWidth: 1)
                                )
                        case .failure:
                            HStack(spacing: Theme.Spacing.xs) {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundStyle(Theme.softCoral)
                                Text("Couldn't load chart")
                                    .font(Theme.Typography.caption)
                                    .foregroundStyle(Theme.deepPlum.opacity(0.5))
                            }
                            .padding(Theme.Spacing.md)
                        default:
                            ProgressView()
                                .tint(Theme.softCoral)
                                .frame(maxWidth: .infinity, minHeight: 80)
                        }
                    }
                }
                .cardStyle()
            }
        }
    }
}

// MARK: - PatternStepSectionView

private struct PatternStepSectionView: View {
    @EnvironmentObject var auth: AuthService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let pattern: Pattern
    @ObservedObject var store: PatternStore
    @ObservedObject var noteStore: ProjectNoteStore
    @ObservedObject var progressStore: PatternProgressStore
    @ObservedObject private var rowCounterStore = RowCounterStore.shared
    @Binding var selectedMakeId: UUID?

    @State private var stepTabSelection: Int = 0
    @State private var parsedStepsCache: [PatternStep] = []
    @State private var isLoadingStepContent = true
    @State private var isAnalyzingSteps = false
    @State private var aiStepErrorMessage: String?
    @State private var showStepEditor = false
    @State private var showWandTip = false
    @State private var showUpdateProgressSheet = false
    @State private var updateRowsCompleted = ""
    @State private var updateTotalRows = ""
    @State private var showPaywall = false
    @State private var aiStepErrorIsEntitlement = false

    private static let hasSeenWandTipKey = "PatternVaultHasSeenWandTip"

    /// True when the user can tap the wand to analyze steps (has saved content or a PDF to fetch).
    private var canShowAnalyzeStepsWand: Bool {
        let trimmed = pattern.sourceContent?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty { return true }
        if let url = pattern.pdfUrl, !url.isEmpty, URL(string: url) != nil { return true }
        return false
    }

    private var patternSteps: [PatternStep] { parsedStepsCache }

    private var currentStepIndex: Int {
        let steps = patternSteps
        let stored = progressStore.progress(for: pattern.id, makeId: selectedMakeId)?.currentStepIndex ?? 0
        return min(max(0, stored), max(0, steps.count - 1))
    }

    private var stepProgressFraction: Double {
        let data = progressStore.progress(for: pattern.id)
        let steps = patternSteps
        if let rc = data?.rowsCompleted, let tr = data?.totalRows, tr > 0 {
            return min(1, max(0, Double(rc) / Double(tr)))
        }
        let stepCount = max(1, steps.count)
        let index = currentStepIndex
        return Double(index + 1) / Double(stepCount)
    }

    private var currentStepRows: [ParsedRow] {
        let steps = patternSteps
        guard !steps.isEmpty else { return [] }
        if let aiRows = pattern.decodedParsedRows, !aiRows.isEmpty {
            return aiRows.sorted(by: { $0.id < $1.id })
        }
        return PatternRowParser.parseRows(from: steps[currentStepIndex].body)
    }

    var body: some View {
        let steps = patternSteps
        let index = currentStepIndex
        Group {
            if showWandTip {
                wandTipBanner
            }

            if isLoadingStepContent {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    SectionHeaderView(title: "Steps")
                    HStack(spacing: Theme.Spacing.sm) {
                        ProgressView()
                            .tint(Theme.softCoral)
                        Text("Preparing steps...")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.deepPlum.opacity(0.6))
                    }
                    .padding(Theme.Spacing.lg)
                    .cardStyle()
                }
            } else if isAnalyzingSteps && pattern.parsedSteps == nil {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    SectionHeaderView(title: "Steps")
                    VStack(spacing: Theme.Spacing.md) {
                        ProgressView()
                            .tint(Theme.softCoral)
                        Text("Analyzing pattern steps...")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.deepPlum.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(Theme.Spacing.xl)
                    .cardStyle()
                }
            } else if steps.isEmpty {
                if canShowAnalyzeStepsWand && !isAnalyzingSteps {
                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        HStack {
                            SectionHeaderView(title: "Steps")
                            Spacer()
                            Button {
                                markWandTipSeen()
                                showWandTip = false
                                analyzeStepsWithAI()
                            } label: {
                                Image(systemName: "wand.and.stars")
                                    .font(.system(size: 20))
                                    .foregroundStyle(Theme.dustyBlue)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Analyze steps with AI")
                        }
                        Text("No steps yet. Tap the wand to analyze this pattern into steps.")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.deepPlum.opacity(0.6))
                    }
                } else if isAnalyzingSteps {
                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        SectionHeaderView(title: "Steps")
                        ProgressView()
                            .tint(Theme.softCoral)
                        Text("Analyzing pattern steps...")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.deepPlum.opacity(0.6))
                    }
                } else {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        SectionHeaderView(title: "Steps")
                        Text("No pattern content or PDF. Save content via Share, paste in Edit steps, or import a pattern with a PDF to analyze steps.")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.deepPlum.opacity(0.6))
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        HStack {
                            SectionHeaderView(title: steps.count > 1 ? "Step \(index + 1) of \(steps.count)" : "Step 1")
                                .accessibilityAddTraits(.isHeader)
                            Spacer()
                            if canShowAnalyzeStepsWand && !isAnalyzingSteps {
                                Button {
                                    markWandTipSeen()
                                    showWandTip = false
                                    analyzeStepsWithAI()
                                } label: {
                                    Image(systemName: "wand.and.stars")
                                        .font(.system(size: 20))
                                        .foregroundStyle(Theme.dustyBlue)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(pattern.parsedSteps == nil ? "Analyze steps with AI" : "Re-analyze steps with AI")
                            }
                            Button {
                                saveHeuristicRowsForCurrentStep()
                            } label: {
                                Image(systemName: "list.number")
                                    .font(.system(size: 20))
                                    .foregroundStyle(Theme.honey)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Generate row reader for this step")
                            if isAnalyzingSteps {
                                ProgressView()
                                    .tint(Theme.softCoral)
                            }
                            Button {
                                showStepEditor = true
                            } label: {
                                Image(systemName: "pencil.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(Theme.softCoral)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Edit steps")
                            if steps.count > 1 {
                                HStack(spacing: Theme.Spacing.xs) {
                                    Button {
                                        withAnimation(reduceMotion ? .none : .default) { stepTabSelection = max(0, index - 1) }
                                    } label: {
                                        Image(systemName: "chevron.left.circle.fill")
                                            .font(.system(size: 22))
                                            .foregroundStyle(index > 0 ? Theme.softCoral : Theme.deepPlum.opacity(0.2))
                                    }
                                    .disabled(index <= 0)
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Previous step")
                                    .accessibilityHint("Step \(index) of \(steps.count)")
                                    Button {
                                        withAnimation(reduceMotion ? .none : .default) { stepTabSelection = min(steps.count - 1, index + 1) }
                                    } label: {
                                        Image(systemName: "chevron.right.circle.fill")
                                            .font(.system(size: 22))
                                            .foregroundStyle(index < steps.count - 1 ? Theme.softCoral : Theme.deepPlum.opacity(0.2))
                                    }
                                    .disabled(index >= steps.count - 1)
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Next step")
                                    .accessibilityHint("Step \(index + 2) of \(steps.count)")
                                }
                            }
                        }
                        if steps[index].title != "Step \(index + 1)" {
                            Text(steps[index].title)
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.deepPlum.opacity(0.7))
                        }
                    }

                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        ProgressView(value: stepProgressFraction, total: 1)
                            .tint(Theme.softCoral)
                            .accessibilityValue("\(Int(stepProgressFraction * 100)) percent complete")
                        if !currentStepRows.isEmpty {
                            InteractiveRowReaderView(
                                rows: currentStepRows,
                                patternId: pattern.id,
                                makeId: selectedMakeId,
                                patternTitle: pattern.title
                            )
                        } else {
                            FormattedStepBodyView(stepBody: steps[index].body, craftType: pattern.craftType)
                        }

                        HStack(spacing: Theme.Spacing.sm) {
                            Text("\(Int(stepProgressFraction * 100))%")
                                .font(Theme.Typography.captionSemibold)
                                .foregroundStyle(Theme.softCoral)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Theme.softCoral.opacity(0.12))
                                .clipShape(Capsule())
                            Text(index < steps.count - 1 ? "In progress" : "Complete")
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.deepPlum.opacity(0.5))
                        }
                    }
                    .padding(Theme.Spacing.lg)
                    .modifier(StepCardStyle(isCurrentStep: index == currentStepIndex))
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 20)
                            .onEnded { value in
                                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                                if value.translation.width <= -60, index < steps.count - 1 {
                                    let next = index + 1
                                    withAnimation(reduceMotion ? .none : .spring(response: 0.25, dampingFraction: 0.9)) {
                                        stepTabSelection = next
                                    }
                                    progressStore.setCurrentStep(patternId: pattern.id, makeId: selectedMakeId, index: next, stepCount: steps.count)
                                } else if value.translation.width >= 60, index > 0 {
                                    let prev = index - 1
                                    withAnimation(reduceMotion ? .none : .spring(response: 0.25, dampingFraction: 0.9)) {
                                        stepTabSelection = prev
                                    }
                                    progressStore.setCurrentStep(patternId: pattern.id, makeId: selectedMakeId, index: prev, stepCount: steps.count)
                                }
                            }
                    )

                    if index == currentStepIndex, index < steps.count - 1 {
                        Button {
                            withAnimation(reduceMotion ? .none : .default) { stepTabSelection = index + 1 }
                        } label: {
                            HStack(spacing: Theme.Spacing.xs) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 14))
                                Text("Mark step complete")
                                    .font(Theme.Typography.caption)
                            }
                            .foregroundStyle(Theme.sageGreen)
                        }
                        .buttonStyle(.plain)
                    }

                    Button { showUpdateProgressSheet = true } label: {
                        HStack(spacing: Theme.Spacing.sm) {
                            Image(systemName: "chart.bar.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(Theme.sageGreen)
                            Text("Update progress")
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.deepPlum.opacity(0.7))
                            Spacer()
                            if let data = progressStore.progress(for: pattern.id, makeId: selectedMakeId), let rc = data.rowsCompleted, let tr = data.totalRows, tr > 0 {
                                Text("\(rc) of \(tr)")
                                    .font(Theme.Typography.caption2)
                                    .foregroundStyle(Theme.deepPlum.opacity(0.5))
                            }
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.deepPlum.opacity(0.3))
                        }
                        .padding(Theme.Spacing.md)
                        .background(Theme.sageGreen.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Update progress")
                    .accessibilityHint("Set progress; use rows for knitting/crochet or leave blank and use notes")

                }
            }
        }
        .sheet(isPresented: $showUpdateProgressSheet) {
            updateProgressSheet
        }
        .sheet(isPresented: $showStepEditor) {
            StepEditorView(pattern: pattern, progressStore: progressStore, isPresented: $showStepEditor)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(source: .aiLimit)
        }
        .alert("Analyze steps", isPresented: Binding(get: { aiStepErrorMessage != nil }, set: { if !$0 { aiStepErrorMessage = nil } })) {
            Button("OK") { aiStepErrorMessage = nil }
            if aiStepErrorIsEntitlement {
                Button(Theme.Premium.seePremiumTitle) {
                    aiStepErrorMessage = nil
                    if GrowthOrchestrator.shared.canShowPaywall(source: .aiLimit) {
                        showPaywall = true
                    }
                }
            }
        } message: {
            if let msg = aiStepErrorMessage { Text(msg) }
        }
        .task {
            refreshPatternSteps()
            stepTabSelection = currentStepIndex
            if canShowAnalyzeStepsWand && !UserDefaults.standard.bool(forKey: Self.hasSeenWandTipKey) {
                showWandTip = true
            }
        }
        .onChange(of: showStepEditor) { _, isShowing in
            if !isShowing {
                refreshPatternSteps()
                stepTabSelection = currentStepIndex
            }
        }
        .onChange(of: pattern.parsedSteps) { _, _ in
            refreshPatternSteps()
            stepTabSelection = currentStepIndex
        }
        .onChange(of: stepTabSelection) { _, newIndex in
            let steps = patternSteps
            guard !steps.isEmpty else { return }
            progressStore.setCurrentStep(patternId: pattern.id, makeId: selectedMakeId, index: newIndex, stepCount: steps.count)
            let rows = PatternRowParser.parseRows(from: steps[newIndex].body)
            if !rows.isEmpty {
                rowCounterStore.setTotalRows(patternId: pattern.id, makeId: selectedMakeId, totalRows: rows.count)
            }
        }
    }

    // MARK: - Step Section Helpers

    private var wandTipBanner: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 18))
                .foregroundStyle(Theme.honey)
            Text("Tap the wand to split this pattern into steps.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.deepPlum)
            Spacer(minLength: 8)
            Button("Got it") {
                markWandTipSeen()
                showWandTip = false
            }
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.sageGreen)
        }
        .padding(Theme.Spacing.md)
        .background(Theme.honey.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.small))
    }

    private func markWandTipSeen() {
        UserDefaults.standard.set(true, forKey: Self.hasSeenWandTipKey)
    }

    private func refreshPatternSteps() {
        let contentForSteps = PatternStepParser.truncateAtEndOfPattern(pattern.sourceContent) ?? pattern.sourceContent
        let layout = progressStore.customStepLayout(for: pattern.id)
        let aiInstructions = pattern.decodedParsedInstructions
        let aiSteps = pattern.decodedParsedSteps
        isLoadingStepContent = true
        Task {
            // Yield so the push animation can complete before heavier parsing work.
            await Task.yield()
            parsedStepsCache = Self.computePatternStepsStatic(
                sourceContent: contentForSteps,
                patternDescription: pattern.patternDescription,
                layout: layout,
                aiSteps: aiSteps,
                aiInstructions: aiInstructions
            )
            stepTabSelection = min(max(0, stepTabSelection), max(0, parsedStepsCache.count - 1))
            isLoadingStepContent = false
        }
    }

    /// Static step computation — shared by PatternStepSectionView and PatternDetailToolbar (for print).
    /// Priority: CustomStepLayout > v2 ParsedInstruction > v1 ParsedStep > heuristic parser.
    static func computePatternStepsStatic(
        sourceContent: String?,
        patternDescription: String?,
        layout: CustomStepLayout?,
        aiSteps: [ParsedStep]?,
        aiInstructions: [ParsedInstruction]? = nil
    ) -> [PatternStep] {
        let hash = contentHashForStepLayout(sourceContent)
        if let layout = layout, layout.contentHash == hash, let content = sourceContent, !content.isEmpty {
            let allBlocks = ContentBlockParser.parse(content)
            let blocks = allBlocks.filter { $0.kind != .paragraphBreak }
            let layoutSteps = buildStepsFromLayoutStatic(layout, blocks: blocks)
            if !layoutSteps.isEmpty { return layoutSteps }
        }
        if let aiInstructions, !aiInstructions.isEmpty {
            return aiInstructions.map { $0.toPatternStep() }
        }
        if let aiSteps, !aiSteps.isEmpty {
            return aiSteps.map { PatternStep(title: $0.title, body: $0.body) }
        }
        return PatternStepParser.parseSteps(sourceContent: sourceContent, patternDescription: patternDescription)
    }

    private static func buildStepsFromLayoutStatic(_ layout: CustomStepLayout, blocks: [ContentBlock]) -> [PatternStep] {
        let excluded = Set(layout.excludedBlockIndices)
        let includedBlocks = blocks.enumerated().filter { !excluded.contains($0.offset) }.map(\.element)
        let starts = layout.stepStartIndices
        let titles = layout.stepTitles
        guard starts.count == titles.count, !starts.isEmpty, !includedBlocks.isEmpty else { return [] }
        var result: [PatternStep] = []
        for i in 0..<starts.count {
            let begin = starts[i]
            let end = i + 1 < starts.count ? starts[i + 1] : includedBlocks.count
            guard begin >= 0, end <= includedBlocks.count, begin < end else { return [] }
            let stepBlocks = includedBlocks[begin..<end]
            let body = stepBlocks.map(\.text).joined(separator: "\n")
            let title = i < titles.count ? titles[i] : "Step \(i + 1)"
            result.append(PatternStep(title: title, body: body.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        return result
    }

    private func analyzeStepsWithAI() {
        guard let userId = auth.currentUserId else {
            aiStepErrorMessage = "You must be signed in to analyze steps."
            return
        }
        if !SubscriptionStore.shared.canUseAI() {
            aiStepErrorMessage = "You've used your 5 free AI analyses this month. Upgrade to Premium for unlimited."
            aiStepErrorIsEntitlement = true
            return
        }
        isAnalyzingSteps = true
        aiStepErrorMessage = nil
        aiStepErrorIsEntitlement = false
        #if DEBUG
        print("[AISteps] Starting AI analysis for pattern: \(pattern.title)")
        #endif
        Task {
            do {
                let existingContent = PatternStepParser.truncateAtEndOfPattern(pattern.sourceContent) ?? pattern.sourceContent
                let trimmedExisting = existingContent?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                var contentToUse: String
                var contentCameFromPdf = false
                var pdfData: Data?

                if !trimmedExisting.isEmpty {
                    contentToUse = trimmedExisting
                    if let pdfUrlString = pattern.pdfUrl, !pdfUrlString.isEmpty, let pdfURL = URL(string: pdfUrlString) {
                        pdfData = try? await URLSession.shared.data(from: pdfURL).0
                    }
                } else if let pdfUrlString = pattern.pdfUrl, !pdfUrlString.isEmpty, let pdfURL = URL(string: pdfUrlString) {
                    let (data, urlResponse) = try await URLSession.shared.data(from: pdfURL)
                    guard let http = urlResponse as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                        aiStepErrorMessage = "Couldn't download the pattern PDF. Check your connection and try again."
                        aiStepErrorIsEntitlement = false
                        GrowthOrchestrator.shared.registerFrictionEvent(.networkRetryError)
                        isAnalyzingSteps = false
                        return
                    }
                    guard let extracted = PDFTextExtractor.extractText(from: data), !extracted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        aiStepErrorMessage = "Couldn't extract text from the PDF. The file may be scanned images only."
                        aiStepErrorIsEntitlement = false
                        GrowthOrchestrator.shared.registerFrictionEvent(.importOrParsingFailure)
                        isAnalyzingSteps = false
                        return
                    }
                    contentToUse = extracted.trimmingCharacters(in: .whitespacesAndNewlines)
                    contentCameFromPdf = true
                    pdfData = data
                } else {
                    aiStepErrorMessage = "No pattern content to analyze. Open the pattern in a browser and use Share to save it with content, paste content in Edit steps, or add a pattern that has a PDF."
                    aiStepErrorIsEntitlement = false
                    GrowthOrchestrator.shared.registerFrictionEvent(.importOrParsingFailure)
                    isAnalyzingSteps = false
                    return
                }

                // Collect images for chart detection
                var analysisImages: [Data] = []
                if let pdfData {
                    let pages = PDFPageRenderer.renderPages(from: pdfData, maxPages: 10, scale: 2.0, jpegQuality: 0.7)
                    analysisImages = pages.map(\.imageData)
                    #if DEBUG
                    print("[AISteps] Rendered \(pages.count) PDF pages for chart detection")
                    #endif
                }

                let instructions: [ParsedInstruction]
                var detectedCharts: [AIStepParserService.DetectedChart] = []
                if !analysisImages.isEmpty {
                    let result = try await AIStepParserService.parseInstructionsWithCharts(
                        from: contentToUse,
                        images: analysisImages
                    )
                    instructions = result.instructions
                    detectedCharts = result.detectedCharts
                } else {
                    instructions = try await AIStepParserService.parseInstructions(from: contentToUse)
                }

                #if DEBUG
                print("[AISteps] Got \(instructions.count) instructions, \(detectedCharts.count) chart(s) detected")
                #endif
                if !instructions.isEmpty {
                    await store.saveParsedInstructions(pattern: pattern, userId: userId, instructions: instructions)
                    _ = await SubscriptionStore.shared.recordAIUse(userId: userId)
                    progressStore.clearCustomStepLayout(patternId: pattern.id)
                    if contentCameFromPdf {
                        await store.updateSourceContent(pattern: pattern, userId: userId, newContent: contentToUse)
                    }
                    if !detectedCharts.isEmpty {
                        await PatternStore.createChartHighlights(
                            from: detectedCharts,
                            images: analysisImages,
                            pdfData: pdfData,
                            patternId: pattern.id
                        )
                    }
                    #if DEBUG
                    print("[AISteps] Saved to DB successfully, \(detectedCharts.count) chart highlight(s) created")
                    #endif
                } else {
                    aiStepErrorMessage = "AI didn't return any instructions. Try editing steps manually with the pencil icon."
                    aiStepErrorIsEntitlement = false
                    GrowthOrchestrator.shared.registerFrictionEvent(.importOrParsingFailure)
                }
            } catch {
                #if DEBUG
                print("[AISteps] ERROR: \(error.localizedDescription)")
                #endif
                aiStepErrorMessage = error.localizedDescription
                aiStepErrorIsEntitlement = false
                GrowthOrchestrator.shared.registerFrictionEvent(.networkRetryError)
            }
            isAnalyzingSteps = false
        }
    }

    private var updateProgressSheet: some View {
        let data = progressStore.progress(for: pattern.id, makeId: selectedMakeId)
        return NavigationStack {
            Form {
                Section {
                    TextField("Rows completed", text: $updateRowsCompleted)
                        .keyboardType(.numberPad)
                    TextField("Total rows (optional)", text: $updateTotalRows)
                        .keyboardType(.numberPad)
                } header: {
                    Text("Row progress")
                } footer: {
                    Text("Use rows for knitting/crochet, or leave blank and use notes. Progress bar uses rows when set.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.screenGradient.ignoresSafeArea())
            .navigationTitle("Update Progress")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showUpdateProgressSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveUpdateProgress() }
                        .disabled(updateRowsCompleted.isEmpty)
                }
            }
            .onAppear {
                if let rc = data?.rowsCompleted { updateRowsCompleted = "\(rc)" }
                if let tr = data?.totalRows { updateTotalRows = "\(tr)" }
            }
        }
    }

    private func saveUpdateProgress() {
        guard let completed = Int(updateRowsCompleted.trimmingCharacters(in: .whitespaces)), completed >= 0 else { return }
        let total = Int(updateTotalRows.trimmingCharacters(in: .whitespaces))
        progressStore.setRows(patternId: pattern.id, makeId: selectedMakeId, completed: completed, total: total, patternTitle: pattern.title)
        GrowthOrchestrator.shared.registerPositiveEvent(.progressLogged)
        GrowthOrchestrator.shared.requestReviewIfEligible()
        if let userId = auth.currentUserId, let total = total, total > 0 {
            let content = "\(completed) of \(total) rows completed"
            Task {
                _ = await noteStore.add(patternId: pattern.id, userId: userId, noteType: .progressUpdate, content: content, photoData: nil)
            }
        }
        showUpdateProgressSheet = false
    }

    private func saveHeuristicRowsForCurrentStep() {
        guard let userId = auth.currentUserId else { return }
        let steps = patternSteps
        guard !steps.isEmpty else { return }
        let rows = PatternRowParser.parseRows(from: steps[currentStepIndex].body)
        guard !rows.isEmpty else {
            aiStepErrorMessage = "No row-style instructions found in this step."
            aiStepErrorIsEntitlement = false
            return
        }
        rowCounterStore.setTotalRows(patternId: pattern.id, makeId: selectedMakeId, totalRows: rows.count)
        Task {
            await store.saveParsedRows(pattern: pattern, userId: userId, rows: rows)
        }
    }
}

// MARK: - FloatingToolPaletteView

private struct FloatingToolPaletteView: View {
    @EnvironmentObject var auth: AuthService
    let pattern: Pattern
    @ObservedObject var noteStore: ProjectNoteStore
    @ObservedObject var progressStore: PatternProgressStore
    @ObservedObject private var rowCounterStore = RowCounterStore.shared
    @Binding var selectedMakeId: UUID?

    @State private var showLogTimeSheet = false
    @State private var logTimeNote = ""
    @State private var logTimeHours = 0
    @State private var logTimeMinutes = 0
    @State private var showYarnColorSheet = false
    @State private var showVoiceRowSheet = false
    @State private var voiceRowSuccessMessage: String?
    @StateObject private var voiceRowService = VoiceRowService()

    private static let yarnColorOptions = ["Warm", "DUSTY BLUE", "Sage", "Coral", "Plum", "Honey", "Clear"]
    private static let logMinuteOptions = Array(stride(from: 0, through: 55, by: 5))

    var body: some View {
        let yarnLabel = progressStore.progress(for: pattern.id, makeId: selectedMakeId)?.yarnColorName ?? "Color"
        HStack(alignment: .bottom, spacing: 0) {
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: Theme.Spacing.sm) {
                HStack(spacing: Theme.Spacing.sm) {
                    Button { showLogTimeSheet = true } label: {
                        toolPaletteChip(icon: "clock", label: "Log time")
                    }
                    .buttonStyle(.plain)
                    Button { showVoiceRowSheet = true } label: {
                        toolPaletteChip(icon: "mic.fill", label: "Progress")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Log progress by voice")
                    .accessibilityHint("Say your current row, round, step number, or percent")
                    Button { showYarnColorSheet = true } label: {
                        toolPaletteChip(icon: "paintpalette.fill", label: yarnLabel)
                    }
                    .buttonStyle(.plain)
                }
                .padding(Theme.Spacing.sm)
                .background(Theme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
                .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 2)
                .padding(.trailing, Theme.Spacing.md)
                .padding(.bottom, Theme.Spacing.sm)

                Image("CrowMascot")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 56, height: 56)
                    .padding(.trailing, 8)
                    .accessibilityHidden(true)
            }
            .padding(.bottom, 100)
        }
        .padding(.trailing, Theme.Spacing.lg)
        .sheet(isPresented: $showLogTimeSheet) { logTimeSheet }
        .sheet(isPresented: $showYarnColorSheet) { yarnColorSheet }
        .sheet(isPresented: $showVoiceRowSheet) { voiceRowSheet }
    }

    private func toolPaletteChip(icon: String, label: String) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Theme.dustyBlue)
            if !label.isEmpty {
                Text(label)
                    .font(Theme.Typography.caption2.weight(.semibold))
                    .foregroundStyle(Theme.deepPlum.opacity(0.7))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .frame(minWidth: 44, maxWidth: 56, minHeight: 40)
    }

    // MARK: Log Time Sheet

    private var logTimeSheet: some View {
        NavigationStack {
            Form {
                Section("Duration") {
                    HStack {
                        Picker("Hours", selection: $logTimeHours) {
                            ForEach(0...12, id: \.self) { hour in
                                Text("\(hour) h").tag(hour)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(maxWidth: .infinity)
                        .onChange(of: logTimeHours) { _, _ in
                            HapticService.selection()
                        }

                        Picker("Minutes", selection: $logTimeMinutes) {
                            ForEach(Self.logMinuteOptions, id: \.self) { minute in
                                Text("\(minute) m").tag(minute)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(maxWidth: .infinity)
                        .onChange(of: logTimeMinutes) { _, _ in
                            HapticService.selection()
                        }
                    }
                    .frame(height: 140)

                    Text(logTimeDurationSummary)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.deepPlum.opacity(0.7))
                }

                Section("Total logged") {
                    Text(totalLoggedDurationSummary)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.deepPlum)
                }

                Section {
                    TextField("What did you work on?", text: $logTimeNote, axis: .vertical)
                        .lineLimit(2...4)
                } header: {
                    Text("Optional note")
                } footer: {
                    Text("Saves as a progress update note.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.screenGradient.ignoresSafeArea())
            .navigationTitle("Log Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showLogTimeSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log") { saveLogTime() }
                        .disabled(totalLoggedMinutes == 0)
                }
            }
        }
    }

    private func saveLogTime() {
        guard totalLoggedMinutes > 0 else { return }
        let trimmedNote = logTimeNote.trimmingCharacters(in: .whitespacesAndNewlines)
        let content = trimmedNote.isEmpty
            ? "Logged \(logTimeDurationSummary)"
            : "Logged \(logTimeDurationSummary) - \(trimmedNote)"
        guard let userId = auth.currentUserId else { showLogTimeSheet = false; return }
        Task {
            _ = await noteStore.add(
                patternId: pattern.id,
                userId: userId,
                noteType: .progressUpdate,
                content: content,
                photoData: nil,
                durationMinutes: totalLoggedMinutes
            )
        }
        HapticService.success()
        logTimeNote = ""
        logTimeHours = 0
        logTimeMinutes = 0
        showLogTimeSheet = false
    }

    private var totalLoggedMinutes: Int {
        (logTimeHours * 60) + logTimeMinutes
    }

    private var logTimeDurationSummary: String {
        switch (logTimeHours, logTimeMinutes) {
        case (0, 0):
            return "0m"
        case (0, let m):
            return "\(m)m"
        case (let h, 0):
            return "\(h)h"
        case (let h, let m):
            return "\(h)h \(m)m"
        }
    }

    private var totalLoggedDurationSummary: String {
        let total = noteStore.notes.reduce(0) { partial, note in
            partial + trackedDurationMinutes(for: note)
        }
        let hours = total / 60
        let minutes = total % 60
        switch (hours, minutes) {
        case (0, 0):
            return "No tracked time yet"
        case (0, let m):
            return "\(m)m"
        case (let h, 0):
            return "\(h)h"
        default:
            return "\(hours)h \(minutes)m"
        }
    }

    private func trackedDurationMinutes(for note: ProjectNote) -> Int {
        if let structured = note.durationMinutes, structured > 0 {
            return structured
        }
        guard note.noteType == .progressUpdate else { return 0 }
        return parsedDurationMinutes(from: note.content) ?? 0
    }

    private func parsedDurationMinutes(from content: String) -> Int? {
        // Supports legacy strings like "Logged 2h" and "Logged 1h 30m - ...".
        let lower = content.lowercased()
        let pattern = "(\\d+)\\s*h|(?:(\\d+)\\s*m)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = lower as NSString
        let matches = regex.matches(in: lower, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return nil }

        var hours = 0
        var minutes = 0
        for match in matches {
            if match.range(at: 1).location != NSNotFound,
               let value = Int(ns.substring(with: match.range(at: 1))) {
                hours = value
            }
            if match.range(at: 2).location != NSNotFound,
               let value = Int(ns.substring(with: match.range(at: 2))) {
                minutes = value
            }
        }
        let total = (hours * 60) + minutes
        return total > 0 ? total : nil
    }

    // MARK: Yarn Color Sheet

    private var yarnColorSheet: some View {
        NavigationStack {
            List {
                ForEach(Self.yarnColorOptions, id: \.self) { name in
                    Button {
                        progressStore.setYarnColor(patternId: pattern.id, makeId: selectedMakeId, colorName: name == "Clear" ? nil : name)
                        showYarnColorSheet = false
                    } label: {
                        HStack {
                            Text(name)
                                .foregroundStyle(Theme.deepPlum)
                            if progressStore.progress(for: pattern.id, makeId: selectedMakeId)?.yarnColorName == name {
                                Spacer()
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Theme.sageGreen)
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.screenGradient.ignoresSafeArea())
            .navigationTitle("Current color")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { showYarnColorSheet = false }
                }
            }
        }
    }

    // MARK: Voice Row Sheet

    private var voiceRowSheet: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.xl) {
                if voiceRowService.authorizationStatus != .authorized {
                    VStack(spacing: Theme.Spacing.lg) {
                        Image(systemName: "mic.slash")
                            .font(.system(size: 44))
                            .foregroundStyle(Theme.deepPlum.opacity(0.4))
                        Text("Voice row counting needs microphone and speech recognition.")
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.deepPlum)
                            .multilineTextAlignment(.center)
                        if let msg = voiceRowService.errorMessage {
                            Text(msg)
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.softCoral)
                                .multilineTextAlignment(.center)
                        }
                        Button("Allow access") {
                            Task { await voiceRowService.requestAuthorization() }
                        }
                        .font(Theme.Typography.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Theme.sageGreen)
                        .clipShape(Capsule())
                    }
                    .padding(Theme.Spacing.xl)
                } else if let success = voiceRowSuccessMessage {
                    VStack(spacing: Theme.Spacing.md) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(Theme.sageGreen)
                        Text(success)
                            .font(Theme.Typography.title)
                            .foregroundStyle(Theme.deepPlum)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: Theme.Spacing.xl) {
                        if voiceRowService.isListening {
                            Image(systemName: "waveform")
                                .font(.system(size: 56))
                                .foregroundStyle(Theme.softCoral)
                                .symbolEffect(.variableColor.iterative)
                            Text("Listening…")
                                .font(Theme.Typography.title)
                                .foregroundStyle(Theme.deepPlum)
                            Text("Say \"row 12\" or \"round 5\"")
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.deepPlum.opacity(0.6))
                        } else if let err = voiceRowService.errorMessage, !voiceRowService.isListening {
                            Text(err)
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.softCoral)
                                .multilineTextAlignment(.center)
                            Text("Say \"row 12\" or \"round 5\"")
                                .font(Theme.Typography.caption2)
                                .foregroundStyle(Theme.deepPlum.opacity(0.5))
                            Button("Try again") {
                                Task { await runVoiceRowListening() }
                            }
                            .font(Theme.Typography.headline)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Theme.softCoral)
                            .clipShape(Capsule())
                        } else {
                            Text("Say your current row or round number")
                                .font(Theme.Typography.body)
                                .foregroundStyle(Theme.deepPlum.opacity(0.7))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.screenGradient.ignoresSafeArea())
            .navigationTitle("Voice row")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        voiceRowService.stopListening()
                        showVoiceRowSheet = false
                        voiceRowSuccessMessage = nil
                    }
                }
            }
            .onAppear {
                voiceRowSuccessMessage = nil
                if voiceRowService.authorizationStatus == .authorized {
                    Task { await runVoiceRowListening() }
                }
            }
        }
    }

    private func runVoiceRowListening() async {
        let n = await voiceRowService.listenForRowNumber()
        guard let n = n else {
            return
        }
        rowCounterStore.jumpToRow(patternId: pattern.id, makeId: selectedMakeId, row: n, patternTitle: pattern.title)
        if let userId = auth.currentUserId {
            let content = "Row \(n)"
            Task {
                _ = await noteStore.add(patternId: pattern.id, userId: userId, noteType: .progressUpdate, content: content, photoData: nil)
            }
        }
        voiceRowSuccessMessage = "Got it, row \(n)!"
        voiceRowService.speakConfirmation("Got it, row \(n)")
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        showVoiceRowSheet = false
        voiceRowSuccessMessage = nil
    }
}

// MARK: - Step card highlight (current step gets accent border)

private struct StepCardStyle: ViewModifier {
    let isCurrentStep: Bool
    @ViewBuilder
    func body(content: Content) -> some View {
        if isCurrentStep {
            content.accentBorderedCard()
        } else {
            content.borderedCard()
        }
    }
}
