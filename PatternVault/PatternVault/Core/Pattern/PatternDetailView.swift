//
//  PatternDetailView.swift
//  PatternVault
//

import SwiftUI
import WebKit
import UIKit
import PhotosUI

struct PatternDetailView: View {
    @EnvironmentObject var auth: AuthService
    @ObservedObject var store: PatternStore
    let pattern: Pattern

    @StateObject private var noteStore = ProjectNoteStore()
    @StateObject private var tagStore = TagStore()
    @StateObject private var collectionStore = CollectionStore()
    @StateObject private var imageStore = PatternImageStore()
    @StateObject private var yarnLinkStore = PatternYarnLinkStore()
    @State private var isEditingTitle = false
    @State private var editTitle = ""
    @State private var editDescription = ""
    @State private var showDeleteConfirm = false
    @State private var showAddNote = false
    @State private var showCollectionPicker = false
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

    /// Size labels for the pattern's multi-size repeat instructions (e.g. ["Small", "Medium", "Large"]).
    /// Returns empty array if the pattern has no multi-size data.
    private var patternSizeOptions: [String] {
        guard let instructions = current.decodedParsedInstructions else { return [] }
        for instruction in instructions {
            guard let counts = instruction.repeatInfo?.targetStitchCounts, counts.count > 1 else { continue }
            switch counts.count {
            case 2: return ["Small", "Large"]
            case 3: return ["Small", "Medium", "Large"]
            case 4: return ["XS", "S", "M", "L"]
            case 5: return ["XS", "S", "M", "L", "XL"]
            case 6: return ["XS", "S", "M", "L", "XL", "XXL"]
            default: return (0..<counts.count).map { "Size \($0 + 1)" }
            }
        }
        return []
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

                            // MARK: - PDF Workspace
                            if let pdfUrlString = current.pdfUrl, !pdfUrlString.isEmpty,
                               URL(string: pdfUrlString) != nil {
                                pdfWorkspaceCard
                            }

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
                        .padding(.bottom, 150)
                    }
                }
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
            showPdfViewer: $showPdfViewer,
            showCollectionPicker: $showCollectionPicker
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
        .sheet(isPresented: $showCollectionPicker) {
            CollectionPickerView(
                collectionStore: collectionStore,
                currentCollectionId: current.collectionId,
                onSelect: { collectionId in
                    Task {
                        await collectionStore.movePattern(patternId: current.id, collectionId: collectionId)
                        if let userId = auth.currentUserId {
                            await store.load(userId: userId)
                        }
                    }
                }
            )
        }
        .sheet(isPresented: $showWebView) {
            if let url = URL(string: current.sourceUrl), SafariView.canOpen(url) {
                SafariView(url: url)
                    .ignoresSafeArea()
            } else {
                NavigationStack {
                    Text("This pattern doesn't have a valid web link.")
                        .foregroundColor(.secondary)
                        .padding()
                        .navigationTitle("Pattern Page")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") { showWebView = false }
                            }
                        }
                }
            }
        }
        .sheet(isPresented: $showPdfViewer) {
            if let pdfUrlString = current.pdfUrl, let pdfURL = URL(string: pdfUrlString) {
                NavigationStack {
                    PDFViewerView(
                        url: pdfURL,
                        patternId: current.id,
                        makeId: selectedMakeId
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
            AddPatternMakeView(
                patternId: current.id,
                existingCount: makes.count,
                sizeOptions: patternSizeOptions
            ) { newMake in
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
                async let collections: () = collectionStore.load(userId: userId)
                _ = await collections
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
        case .frogged:
            return "This one got frogged — cast on again when you're ready"
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
        case .frogged:
            return "Frogging is part of the craft. Keep the pattern for next time."
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
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(PatternStatus.allCases, id: \.self) { status in
                    Button { changeStatus(to: status) } label: {
                        HStack(spacing: 5) {
                            Image(systemName: Theme.statusIcon(for: status))
                                .font(.system(size: 11, weight: .bold))
                            Text(status.displayName)
                                .font(Theme.Typography.captionSemibold)
                                .fixedSize()
                        }
                        .foregroundStyle(
                            current.status == status ? .white : Theme.statusColor(for: status)
                        )
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
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

    // MARK: - PDF Workspace Card

    private var pdfWorkspaceCard: some View {
        Button {
            showPdfViewer = true
        } label: {
            HStack(spacing: Theme.Spacing.lg) {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                        .fill(Theme.softCoral.opacity(0.12))
                        .frame(width: 48, height: 48)
                    Image(systemName: "pencil.and.ruler.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.softCoral)
                }
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Pattern PDF")
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.deepPlum)
                    Text("View, highlight, and annotate")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Semantic.textMuted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Semantic.iconFaint)
            }
            .padding(Theme.Spacing.lg)
            .borderedCard(borderColor: Theme.softCoral.opacity(0.25))
        }
        .buttonStyle(CardPressStyle())
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

                    // TikTok creator link
                    if current.sourcePlatform?.lowercased() == "tiktok",
                       let handle = tiktokHandle(from: current.sourceUrl),
                       let profileUrl = URL(string: "https://www.tiktok.com/@\(handle)") {
                        infoDivider
                        HStack(spacing: Theme.Spacing.sm) {
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(Theme.dustyBlue)
                                .frame(width: 22)
                            Link("View @\(handle) on TikTok", destination: profileUrl)
                                .font(Theme.Typography.body)
                                .foregroundStyle(Theme.dustyBlue)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.dustyBlue.opacity(0.4))
                        }
                        .padding(.vertical, Theme.Spacing.md)
                        .padding(.horizontal, Theme.Spacing.lg)
                    }
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

    /// Extracts the TikTok handle (without @) from a URL like `tiktok.com/@username/video/...`
    func tiktokHandle(from urlString: String) -> String? {
        guard let url = URL(string: urlString),
              let host = url.host?.lowercased(), host.contains("tiktok") else { return nil }
        let path = url.path
        guard let atRange = path.range(of: "@") else { return nil }
        let afterAt = path[atRange.upperBound...]
        let handle = afterAt.prefix(while: { $0 != "/" })
        return handle.isEmpty ? nil : String(handle)
    }
}

// MARK: - PatternDetailToolbar

private struct PatternDetailToolbar: ViewModifier {
    let pattern: Pattern
    @Binding var showWebView: Bool
    @Binding var showPdfViewer: Bool
    @Binding var showCollectionPicker: Bool

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
                        Button {
                            showCollectionPicker = true
                        } label: {
                            Label("Move to folder…", systemImage: "folder")
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
    @State private var knittingModeHighlight: ChartHighlight?

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
            .fullScreenCover(item: $knittingModeHighlight) { highlight in
                InteractiveChartGridView(
                    highlight: highlight,
                    patternId: pattern.id,
                    makeId: nil
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
                .contextMenu {
                    Button {
                        knittingModeHighlight = highlight
                    } label: {
                        Label("Knitting Mode", systemImage: "chart.bar.doc.horizontal")
                    }
                    Button {
                        selectedWorkspaceHighlight = highlight
                    } label: {
                        Label("Open Workspace", systemImage: "pencil.and.outline")
                    }
                }
            }

            HStack(spacing: Theme.Spacing.sm) {
                Label("Row \(rowVal)", systemImage: "arrow.right")
                    .font(Theme.Typography.caption2)
                    .foregroundStyle(Theme.honey)
                Label("Col \(colVal)", systemImage: "arrow.down")
                    .font(Theme.Typography.caption2)
                    .foregroundStyle(Theme.softCoral)
                Spacer()
                Button {
                    knittingModeHighlight = highlight
                } label: {
                    Label("Knit", systemImage: "chart.bar.doc.horizontal")
                        .font(Theme.Typography.caption2)
                        .foregroundStyle(Theme.sageGreen)
                }
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

/// A display-level step that may group multiple consecutive single-row PatternSteps.
private struct DisplayStep: Identifiable {
    let id = UUID()
    let originalSteps: [PatternStep]       // 1 or more original steps
    let groupedRows: [ParsedRow]?          // non-nil when multiple rows are grouped
    let displayTitle: String?              // override title for grouped steps

    /// The primary step (first in group, or the only step)
    var primary: PatternStep { originalSteps[0] }

    /// Display title: section name for groups, original title for singles
    var title: String { displayTitle ?? primary.title }

    /// The body text — for singles, the original body. For groups, combined.
    var body: String { primary.body }

    /// Whether this is a grouped multi-row display step
    var isGrouped: Bool { groupedRows != nil }

    /// RepeatInfo from the primary step
    var repeatInfo: RepeatInfo? { primary.repeatInfo }
}

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
    /// Source passed to the paywall — set by the caller before flipping showPaywall.
    @State private var paywallSource: GrowthOrchestrator.PaywallSource = .aiLimit
    @State private var aiStepErrorIsEntitlement = false
    @State private var showStepNoteSheet = false
    @State private var stepNoteIndex: Int?
    @State private var showStepCounterSheet = false
    @State private var editingStepCounterId: UUID?
    @State private var stepCounterTargetIndex: Int?

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

    /// Navigates to a display step by computing the original step index for the first step in the group.
    private func navigateToDisplayStep(_ displayIdx: Int) {
        let grouped = groupedSteps
        guard displayIdx >= 0, displayIdx < grouped.count else { return }
        // Compute the original step index of the first step in the target display step
        var originalIdx = 0
        for i in 0..<displayIdx {
            originalIdx += grouped[i].originalSteps.count
        }
        let steps = patternSteps
        withAnimation(reduceMotion ? .none : .default) {
            stepTabSelection = min(max(0, originalIdx), max(0, steps.count - 1))
        }
        progressStore.setCurrentStep(patternId: pattern.id, makeId: selectedMakeId, index: originalIdx, stepCount: steps.count)
    }

    /// Groups consecutive single-row steps in the same section into one display step.
    /// Returns an array of DisplayStep, each containing one or more original PatternSteps.
    private var groupedSteps: [DisplayStep] {
        let steps = patternSteps
        guard !steps.isEmpty else { return [] }

        var result: [DisplayStep] = []
        var currentGroup: [PatternStep] = []
        var currentSection = ""

        func flushGroup() {
            guard !currentGroup.isEmpty else { return }
            if currentGroup.count >= 2 {
                // Group of consecutive rows — merge into one display step
                let title = currentGroup.first!.title.components(separatedBy: ":").first ?? currentGroup.first!.title
                let rows = currentGroup.enumerated().map { idx, step in
                    ParsedRow(
                        id: idx + 1,
                        instruction: step.body,
                        stitchCount: nil,
                        isRepeatStart: false,
                        repeatCount: nil,
                        note: nil
                    )
                }
                result.append(DisplayStep(
                    originalSteps: currentGroup,
                    groupedRows: rows,
                    displayTitle: title
                ))
            } else {
                // Single step — show as-is
                result.append(DisplayStep(
                    originalSteps: currentGroup,
                    groupedRows: nil,
                    displayTitle: nil
                ))
            }
            currentGroup = []
        }

        for step in steps {
            let section = step.title.components(separatedBy: ":").first?.trimmingCharacters(in: .whitespaces) ?? ""
            let hasRowLabel = step.title.lowercased().contains("row ") || step.title.lowercased().contains("rnd ")

            // A step is groupable if: it has a row label, no repeat info, and is a single-row instruction
            let isGroupable = hasRowLabel
                && step.repeatInfo == nil
                && RepeatInfo.detect(from: step.body) == nil

            if isGroupable && section == currentSection {
                // Continue the group
                currentGroup.append(step)
            } else {
                // Flush previous group and start fresh
                flushGroup()
                currentSection = section
                if isGroupable {
                    currentGroup = [step]
                } else {
                    // Non-groupable step — add directly
                    result.append(DisplayStep(
                        originalSteps: [step],
                        groupedRows: nil,
                        displayTitle: nil
                    ))
                    currentSection = ""
                }
            }
        }
        flushGroup()
        return result
    }

    /// Maps the original step index to the corresponding display step (which may be grouped)
    private var currentDisplayStep: DisplayStep? {
        let grouped = groupedSteps
        let originalIdx = currentStepIndex
        // Find which display step contains the original step at originalIdx
        var originalCounter = 0
        for ds in grouped {
            let count = ds.originalSteps.count
            if originalIdx < originalCounter + count {
                return ds
            }
            originalCounter += count
        }
        return grouped.last
    }

    /// Display step index (for grouped navigation)
    private var currentDisplayStepIndex: Int {
        let grouped = groupedSteps
        let originalIdx = currentStepIndex
        var originalCounter = 0
        for (i, ds) in grouped.enumerated() {
            let count = ds.originalSteps.count
            if originalIdx < originalCounter + count {
                return i
            }
            originalCounter += count
        }
        return max(0, grouped.count - 1)
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
                            SectionHeaderView(title: {
                                let displayCount = groupedSteps.count
                                let displayIdx = currentDisplayStepIndex
                                return displayCount > 1 ? "Step \(displayIdx + 1) of \(displayCount)" : "Step 1"
                            }())
                                .accessibilityAddTraits(.isHeader)
                            Spacer()
                            if canShowAnalyzeStepsWand && !isAnalyzingSteps {
                                Menu {
                                    Button {
                                        markWandTipSeen()
                                        showWandTip = false
                                        analyzeStepsOnly()
                                    } label: {
                                        Label("Re-analyze Steps", systemImage: "text.badge.star")
                                    }
                                    Button {
                                        markWandTipSeen()
                                        showWandTip = false
                                        analyzeChartsOnly()
                                    } label: {
                                        Label("Re-detect Charts", systemImage: "chart.bar.doc.horizontal")
                                    }
                                    Divider()
                                    Button {
                                        markWandTipSeen()
                                        showWandTip = false
                                        analyzeStepsWithAI()
                                    } label: {
                                        Label("Re-analyze Everything", systemImage: "wand.and.stars")
                                    }
                                } label: {
                                    Image(systemName: "wand.and.stars")
                                        .font(.system(size: 20))
                                        .foregroundStyle(Theme.dustyBlue)
                                }
                                .buttonStyle(.plain)
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
                            if groupedSteps.count > 1 {
                                let dsIdx = currentDisplayStepIndex
                                let dsCount = groupedSteps.count
                                HStack(spacing: Theme.Spacing.xs) {
                                    Button {
                                        navigateToDisplayStep(dsIdx - 1)
                                    } label: {
                                        Image(systemName: "chevron.left.circle.fill")
                                            .font(.system(size: 22))
                                            .foregroundStyle(dsIdx > 0 ? Theme.softCoral : Theme.deepPlum.opacity(0.2))
                                    }
                                    .disabled(dsIdx <= 0)
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Previous step")
                                    Button {
                                        navigateToDisplayStep(dsIdx + 1)
                                    } label: {
                                        Image(systemName: "chevron.right.circle.fill")
                                            .font(.system(size: 22))
                                            .foregroundStyle(dsIdx < dsCount - 1 ? Theme.softCoral : Theme.deepPlum.opacity(0.2))
                                    }
                                    .disabled(dsIdx >= dsCount - 1)
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Next step")
                                }
                            }
                        }
                        if let ds = currentDisplayStep {
                            let displayTitle = ds.title
                            if displayTitle != "Step \(currentDisplayStepIndex + 1)" {
                                Text(displayTitle)
                                    .font(Theme.Typography.caption)
                                    .foregroundStyle(Theme.deepPlum.opacity(0.7))
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        ProgressView(value: stepProgressFraction, total: 1)
                            .tint(Theme.softCoral)
                            .accessibilityValue("\(Int(stepProgressFraction * 100)) percent complete")
                        if let repeatInfo = steps[index].repeatInfo ?? RepeatInfo.detect(from: steps[index].body) {
                            RepeatStepView(
                                repeatInfo: repeatInfo,
                                referencedSteps: resolveReferencedSteps(repeatInfo: repeatInfo, allSteps: steps, currentIndex: index),
                                stepLabel: steps[index].title,
                                patternId: pattern.id,
                                makeId: selectedMakeId,
                                stepBody: steps[index].body,
                                startingStitchesAllSizes: findStartingStitchesAllSizes(before: index, in: steps),
                                startingStitches: findStartingStitches(before: index, in: steps)
                            )
                            .id("repeat_\(index)")
                        } else if let displayStep = currentDisplayStep, displayStep.isGrouped,
                                  let groupedRows = displayStep.groupedRows {
                            // Grouped consecutive rows — show as interactive row reader
                            InteractiveRowReaderView(
                                rows: groupedRows,
                                patternId: pattern.id,
                                makeId: selectedMakeId,
                                patternTitle: pattern.title
                            )
                        } else if !currentStepRows.isEmpty {
                            InteractiveRowReaderView(
                                rows: currentStepRows,
                                patternId: pattern.id,
                                makeId: selectedMakeId,
                                patternTitle: pattern.title
                            )
                        } else {
                            FormattedStepBodyView(stepBody: steps[index].body, craftType: pattern.craftType)
                        }

                        // Per-step counters
                        stepCounterBar(stepIndex: index)

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

                        // Per-step notes
                        stepNotesSection(stepIndex: index)
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
        .sheet(isPresented: $showPaywall, onDismiss: { paywallSource = .aiLimit }) {
            PaywallView(source: paywallSource)
        }
        .sheet(isPresented: $showStepCounterSheet) {
            stepCounterConfigSheet
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

    // MARK: - Per-Step Notes

    @ViewBuilder
    private func stepNotesSection(stepIndex: Int) -> some View {
        let stepNotes = noteStore.notes.filter { $0.stepIndex == stepIndex }

        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            if !stepNotes.isEmpty {
                Divider().padding(.vertical, Theme.Spacing.xs)
                ForEach(stepNotes) { note in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "note.text")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.dustyBlue)
                            .padding(.top, 2)
                        Text(note.content)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.deepPlum.opacity(0.75))
                    }
                }
            }

            Button {
                stepNoteIndex = stepIndex
                showStepNoteSheet = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus.bubble")
                        .font(.system(size: 11))
                    Text("Add step note")
                        .font(Theme.Typography.caption)
                }
                .foregroundStyle(Theme.dustyBlue)
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $showStepNoteSheet) {
            if let idx = stepNoteIndex {
                AddNoteView(noteStore: noteStore, patternId: pattern.id, stepIndex: idx)
            }
        }
    }

    // MARK: - Per-Step Counters

    private func countersForStep(_ stepIndex: Int) -> [SecondaryCounter] {
        rowCounterStore.state(for: pattern.id, makeId: selectedMakeId)
            .secondaryCounters
            .filter { $0.stepIndex == stepIndex && $0.isActive }
    }

    @ViewBuilder
    private func stepCounterBar(stepIndex: Int) -> some View {
        let counters = countersForStep(stepIndex)
        HStack(spacing: Theme.Spacing.xs) {
            ForEach(counters.prefix(4)) { counter in
                stepCounterChip(counter)
            }
            Button {
                stepCounterTargetIndex = stepIndex
                editingStepCounterId = nil
                showStepCounterSheet = true
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 11))
                    if counters.isEmpty {
                        Text("Add counter")
                            .font(Theme.Typography.caption2)
                    }
                }
                .foregroundStyle(Theme.dustyBlue)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func stepCounterChip(_ counter: SecondaryCounter) -> some View {
        let title = counter.title.isEmpty ? "Counter" : counter.title
        let chipColor = stepCounterColor(counter.color)
        HStack(spacing: 4) {
            if counter.linkMode == .unlinked && counter.color == "dustyBlue" {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10, weight: .semibold))
                let cycleNum = counter.totalResets + 1
                Text(counter.maxResets != nil ? "Cycle \(cycleNum)/~\(counter.maxResets!)" : "Cycle \(cycleNum)")
                    .font(Theme.Typography.caption2.weight(.semibold))
            } else {
                Text("\(title): \(counter.currentCount)/\(counter.resetAfter)")
                    .font(Theme.Typography.caption2.weight(.semibold))
            }
        }
        .foregroundStyle(chipColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(chipColor.opacity(0.12))
        .clipShape(Capsule())
        .onTapGesture {
            rowCounterStore.incrementSecondary(patternId: pattern.id, makeId: selectedMakeId, counterId: counter.id)
        }
        .onLongPressGesture {
            stepCounterTargetIndex = counter.stepIndex
            editingStepCounterId = counter.id
            showStepCounterSheet = true
        }
    }

    private func stepCounterColor(_ name: String) -> Color {
        switch name {
        case "sageGreen": return Theme.sageGreen
        case "dustyBlue": return Theme.dustyBlue
        case "honey": return Theme.honey
        case "deepPlum": return Theme.deepPlum
        default: return Theme.softCoral
        }
    }

    private var editingStepCounter: SecondaryCounter? {
        guard let id = editingStepCounterId else { return nil }
        return rowCounterStore.state(for: pattern.id, makeId: selectedMakeId)
            .secondaryCounters.first { $0.id == id }
    }

    private var stepCounterConfigSheet: some View {
        SecondaryCounterConfigSheet(
            existing: editingStepCounter,
            onSave: { counter in
                if editingStepCounter != nil {
                    var updated = counter
                    updated.stepIndex = stepCounterTargetIndex
                    rowCounterStore.updateSecondaryCounter(patternId: pattern.id, makeId: selectedMakeId, counter: updated)
                } else {
                    rowCounterStore.addSecondaryCounter(
                        patternId: pattern.id,
                        makeId: selectedMakeId,
                        title: counter.title,
                        resetAfter: counter.resetAfter,
                        maxResets: counter.maxResets,
                        linkMode: counter.linkMode,
                        color: counter.color,
                        stepIndex: stepCounterTargetIndex
                    )
                }
            },
            onDelete: editingStepCounter == nil ? nil : {
                guard let id = editingStepCounterId else { return }
                rowCounterStore.removeSecondaryCounter(patternId: pattern.id, makeId: selectedMakeId, counterId: id)
            }
        )
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

    /// Resolves the referenced steps for a repeat instruction.
    /// E.g., "rep rnds 1 & 2" with referencedStartRow=1, referencedEndRow=2
    /// finds the steps in the same section whose startRow matches 1 and 2.
    private func resolveReferencedSteps(repeatInfo: RepeatInfo, allSteps: [PatternStep], currentIndex: Int) -> [PatternStep] {
        guard let refStart = repeatInfo.referencedStartRow,
              let refEnd = repeatInfo.referencedEndRow else {
            return []
        }

        // Get the current step's section (from the title prefix before ":")
        let currentTitle = allSteps[currentIndex].title
        let currentSection = currentTitle.components(separatedBy: ":").first?.trimmingCharacters(in: .whitespaces) ?? ""

        // Find steps BEFORE the current step in the same section whose row numbers match
        var matched: [PatternStep] = []
        for i in 0..<currentIndex {
            let step = allSteps[i]
            let stepSection = step.title.components(separatedBy: ":").first?.trimmingCharacters(in: .whitespaces) ?? ""
            guard stepSection == currentSection || currentSection.isEmpty else { continue }

            let titleLower = step.title.lowercased()
            for row in refStart...refEnd {
                if titleLower.contains("row \(row)") || titleLower.contains("rnd \(row)")
                    || titleLower.contains("round \(row)") {
                    matched.append(step)
                    break
                }
            }
        }

        // Deduplicate: if we matched more rows than expected (e.g., "Row 3" appears in multiple sub-sections),
        // take only the LAST N matches (closest to the repeat step)
        let expectedCount = refEnd - refStart + 1
        if matched.count > expectedCount {
            matched = Array(matched.suffix(expectedCount))
        }

        // If we couldn't match by title, try sequential offset: the N steps immediately before the repeat
        if matched.isEmpty {
            let cycleLength = refEnd - refStart + 1
            let startIdx = max(0, currentIndex - cycleLength)
            for i in startIdx..<currentIndex {
                matched.append(allSteps[i])
            }
        }

        return matched
    }

    /// Finds ALL size variants of the starting stitch count from steps before the current one.
    /// Example: "for 28 (32, 36) sts total" → [28, 32, 36]
    private func findStartingStitchesAllSizes(before index: Int, in steps: [PatternStep]) -> [Int]? {
        let multiSizePattern = #"(\d+)\s*\((\d+),\s*(\d+)\)\s*sts"#
        for i in stride(from: index - 1, through: 0, by: -1) {
            let body = steps[i].body
            // Skip stitch-change annotations
            if body.lowercased().contains("sts inc") || body.lowercased().contains("sts dec") {
                // Check if this body ALSO has a total count
                let lower = body.lowercased()
                if !lower.contains("total") && !lower.contains("for ") { continue }
            }
            if let regex = try? NSRegularExpression(pattern: multiSizePattern, options: .caseInsensitive) {
                let matches = regex.matches(in: body, range: NSRange(body.startIndex..., in: body))
                // Use the LAST multi-size group (most likely the total)
                if let match = matches.last {
                    let vals = [
                        Range(match.range(at: 1), in: body).flatMap { Int(body[$0]) },
                        Range(match.range(at: 2), in: body).flatMap { Int(body[$0]) },
                        Range(match.range(at: 3), in: body).flatMap { Int(body[$0]) }
                    ].compactMap { $0 }
                    if !vals.isEmpty { return vals }
                }
            }
        }
        return nil
    }

    /// Finds the TOTAL stitch count from steps before the current one (smallest size).
    /// Skips stitch-change annotations like "(4 sts inc)" or "(2 sts dec)".
    private func findStartingStitches(before index: Int, in steps: [PatternStep]) -> Int? {
        for i in stride(from: index - 1, through: 0, by: -1) {
            let body = steps[i].body

            // Look for "N sts total" or "total of N sts" or "for N (M, L) sts total"
            let totalPattern = #"(\d+)\s*(?:\(\d+,\s*\d+\)\s*)?sts\s*total"#
            if let regex = try? NSRegularExpression(pattern: totalPattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
               let range = Range(match.range(at: 1), in: body),
               let count = Int(body[range]) {
                return count
            }

            // Look for "for N (M, L) sts" at end of instruction (cast-on counts)
            let forStsPattern = #"for\s+(\d+)\s*\(\d+,\s*\d+\)\s*sts"#
            if let regex = try? NSRegularExpression(pattern: forStsPattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
               let range = Range(match.range(at: 1), in: body),
               let count = Int(body[range]) {
                return count
            }

            // Find "(N sts)" but EXCLUDE "(N sts inc)", "(N sts dec)", "(N sts increase)", "(N sts decrease)"
            // These are stitch-change annotations, not stitch counts
            let stsPattern = #"\((\d+)\s*(?:\(\d+,\s*\d+\)\s*)?sts\)"#
            if let regex = try? NSRegularExpression(pattern: stsPattern, options: .caseInsensitive) {
                let matches = regex.matches(in: body, range: NSRange(body.startIndex..., in: body))
                // Filter out matches followed by inc/dec
                for match in matches.reversed() {
                    guard let numRange = Range(match.range(at: 1), in: body),
                          let count = Int(body[numRange]) else { continue }
                    // Check the full match text doesn't contain inc/dec
                    if let fullRange = Range(match.range, in: body) {
                        let fullText = String(body[fullRange]).lowercased()
                        if fullText.contains("inc") || fullText.contains("dec") { continue }
                    }
                    return count
                }
            }
        }
        return nil
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

    /// Re-analyzes ONLY the steps (no chart detection). Preserves existing chart highlights.
    private func analyzeStepsOnly() {
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
        Task {
            do {
                let contentToUse = try await getPatternContent()
                guard let content = contentToUse else {
                    isAnalyzingSteps = false
                    return
                }
                // Steps only — no images, no chart detection
                let instructions = try await AIStepParserService.parseInstructions(from: content)
                if !instructions.isEmpty {
                    await store.saveParsedInstructions(pattern: pattern, userId: userId, instructions: instructions)
                    _ = await SubscriptionStore.shared.recordAIUse(userId: userId)
                    progressStore.clearCustomStepLayout(patternId: pattern.id)
                }
            } catch {
                aiStepErrorMessage = error.localizedDescription
            }
            isAnalyzingSteps = false
        }
    }

    /// Re-detects ONLY the charts (no step re-analysis). Preserves existing parsed steps.
    private func analyzeChartsOnly() {
        guard auth.currentUserId != nil else { return }
        store.extractChartsFromPDF(patternId: pattern.id)
    }

    /// Gets pattern content from source_content or PDF text extraction.
    private func getPatternContent() async throws -> String? {
        let existing = PatternStepParser.truncateAtEndOfPattern(pattern.sourceContent) ?? pattern.sourceContent
        let trimmed = existing?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty { return trimmed }

        if let pdfUrlString = pattern.pdfUrl, !pdfUrlString.isEmpty, let pdfURL = URL(string: pdfUrlString) {
            let (data, response) = try await URLSession.shared.data(from: pdfURL)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                aiStepErrorMessage = "Couldn't download the pattern PDF."
                return nil
            }
            guard let extracted = PDFTextExtractor.extractText(from: data),
                  !extracted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                aiStepErrorMessage = "Couldn't extract text from the PDF."
                return nil
            }
            return extracted.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        aiStepErrorMessage = "No pattern content available to analyze."
        return nil
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
    @State private var progressPhotoItem: PhotosPickerItem?

    // Live session timer
    @State private var isTimerRunning = false
    @State private var timerAccumulatedSeconds: Int = 0
    @State private var displayTimer: Timer?
    @State private var showVoiceRowSheet = false
    @State private var voiceRowSuccessMessage: String?
    @StateObject private var voiceRowService = VoiceRowService()
    @State private var showPaywall = false
    @State private var paywallSource: GrowthOrchestrator.PaywallSource = .voiceRowCounter

    private static let yarnColorOptions = ["Warm", "DUSTY BLUE", "Sage", "Coral", "Plum", "Honey", "Clear"]
    private static let logMinuteOptions = Array(stride(from: 0, through: 55, by: 5))

    var body: some View {
        let yarnLabel = progressStore.progress(for: pattern.id, makeId: selectedMakeId)?.yarnColorName ?? "Color"
        HStack(alignment: .bottom, spacing: 0) {
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: Theme.Spacing.sm) {
                HStack(spacing: Theme.Spacing.sm) {
                    Button { showLogTimeSheet = true } label: {
                        if isTimerRunning {
                            toolPaletteChip(icon: "stop.circle.fill", label: timerDisplay, tint: Theme.softCoral)
                        } else {
                            toolPaletteChip(icon: "clock", label: "Log time")
                        }
                    }
                    .buttonStyle(.plain)
                    Button {
                        // Premium gate: hands-free voice row counting is a Premium perk.
                        if SubscriptionStore.shared.isPremium {
                            showVoiceRowSheet = true
                        } else {
                            paywallSource = .voiceRowCounter
                            showPaywall = true
                        }
                    } label: {
                        toolPaletteChip(
                            icon: SubscriptionStore.shared.isPremium ? "mic.fill" : "mic.fill.badge.plus",
                            label: "Progress"
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Log progress by voice")
                    .accessibilityHint("Say your current row, round, step number, or percent")
                    Button { showYarnColorSheet = true } label: {
                        toolPaletteChip(icon: "paintpalette.fill", label: yarnLabel)
                    }
                    .buttonStyle(.plain)
                    PhotosPicker(selection: $progressPhotoItem, matching: .images) {
                        toolPaletteChip(icon: "camera.fill", label: "Photo")
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
            .padding(.bottom, 16)
        }
        .padding(.trailing, Theme.Spacing.lg)
        .sheet(isPresented: $showLogTimeSheet) { logTimeSheet }
        .sheet(isPresented: $showYarnColorSheet) { yarnColorSheet }
        .onChange(of: progressPhotoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let userId = auth.currentUserId {
                    let store = PatternImageStore()
                    _ = await store.addFromData(patternId: pattern.id, userId: userId, imageData: data, displayOrder: 999)
                    HapticService.success()
                }
                progressPhotoItem = nil
            }
        }
        .sheet(isPresented: $showVoiceRowSheet) { voiceRowSheet }
        .sheet(isPresented: $showPaywall, onDismiss: { paywallSource = .voiceRowCounter }) {
            PaywallView(source: paywallSource)
        }
    }

    private func toolPaletteChip(icon: String, label: String, tint: Color? = nil) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(tint ?? Theme.dustyBlue)
            if !label.isEmpty {
                Text(label)
                    .font(Theme.Typography.caption2.weight(.semibold))
                    .foregroundStyle(tint ?? Theme.deepPlum.opacity(0.7))
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .frame(minWidth: 44, minHeight: 40)
    }

    private var timerDisplay: String {
        let m = timerAccumulatedSeconds / 60
        let s = timerAccumulatedSeconds % 60
        return String(format: "%d:%02d", m, s)
    }

    // MARK: Log Time Sheet

    private var logTimeSheet: some View {
        NavigationStack {
            Form {
                // Live timer section
                Section("Session Timer") {
                    HStack(spacing: Theme.Spacing.md) {
                        Image(systemName: isTimerRunning ? "stop.circle.fill" : "play.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(isTimerRunning ? Theme.softCoral : Theme.sageGreen)

                        Text(liveTimerDisplay)
                            .font(.system(.title2, design: .monospaced, weight: .semibold))
                            .foregroundStyle(Theme.deepPlum)
                            .monospacedDigit()
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Button {
                            if isTimerRunning {
                                stopSessionTimer()
                            } else {
                                startSessionTimer()
                            }
                        } label: {
                            Text(isTimerRunning ? "Stop" : (timerAccumulatedSeconds > 0 ? "Resume" : "Start"))
                                .font(Theme.Typography.bodySemibold)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(isTimerRunning ? Theme.softCoral : Theme.sageGreen)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 4)

                    if timerAccumulatedSeconds > 0 && !isTimerRunning {
                        Button("Reset timer", role: .destructive) {
                            timerAccumulatedSeconds = 0
                        }
                        .font(Theme.Typography.caption)
                    }
                }

                // Manual fallback
                Section("Or log manually") {
                    HStack {
                        Picker("Hours", selection: $logTimeHours) {
                            ForEach(0...12, id: \.self) { hour in
                                Text("\(hour) h").tag(hour)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(maxWidth: .infinity)

                        Picker("Minutes", selection: $logTimeMinutes) {
                            ForEach(Self.logMinuteOptions, id: \.self) { minute in
                                Text("\(minute) m").tag(minute)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(maxWidth: .infinity)
                    }
                    .frame(height: 120)
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
                    Button("Cancel") {
                        // Don't stop timer on cancel — it keeps running
                        showLogTimeSheet = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveLogTime() }
                        .disabled(effectiveLogMinutes == 0)
                }
            }
        }
    }

    private func startSessionTimer() {
        isTimerRunning = true
        displayTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            timerAccumulatedSeconds += 1
        }
    }

    private func stopSessionTimer() {
        isTimerRunning = false
        displayTimer?.invalidate()
        displayTimer = nil
    }

    /// Timer display or manual picker — whichever has time
    private var effectiveLogMinutes: Int {
        let timerMinutes = timerAccumulatedSeconds / 60
        let manualMinutes = (logTimeHours * 60) + logTimeMinutes
        return max(timerMinutes, manualMinutes)
    }

    private var liveTimerDisplay: String {
        let h = timerAccumulatedSeconds / 3600
        let m = (timerAccumulatedSeconds % 3600) / 60
        let s = timerAccumulatedSeconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }

    private func saveLogTime() {
        stopSessionTimer()
        let totalMinutes = effectiveLogMinutes
        guard totalMinutes > 0 else { return }
        let durationLabel = totalMinutes >= 60 ? "\(totalMinutes / 60)h \(totalMinutes % 60)m" : "\(totalMinutes)m"
        let trimmedNote = logTimeNote.trimmingCharacters(in: .whitespacesAndNewlines)
        let content = trimmedNote.isEmpty
            ? "Logged \(durationLabel)"
            : "Logged \(durationLabel) - \(trimmedNote)"
        guard let userId = auth.currentUserId else { showLogTimeSheet = false; return }
        Task {
            _ = await noteStore.add(
                patternId: pattern.id,
                userId: userId,
                noteType: .progressUpdate,
                content: content,
                photoData: nil,
                durationMinutes: totalMinutes
            )
        }
        HapticService.success()
        logTimeNote = ""
        logTimeHours = 0
        logTimeMinutes = 0
        timerAccumulatedSeconds = 0
        showLogTimeSheet = false
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
