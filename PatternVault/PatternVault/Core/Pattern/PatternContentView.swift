//
//  PatternContentView.swift
//  PatternVault
//
//  Displays extracted pattern content with an edit mode that lets users
//  surgically remove individual sentences, bullets, and table rows.
//  Removed blocks are learned as junk phrases for future import filtering.
//

import SwiftUI
import UIKit

struct PatternContentView: View {
    let pattern: Pattern
    @ObservedObject var store: PatternStore
    @EnvironmentObject var auth: AuthService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Edit mode state

    @State private var isEditMode = false
    @State private var contentBlocks: [ContentBlock] = []
    @State private var removedBlockIds: Set<Int> = []
    @State private var showPatternContentWarning = false
    @State private var pendingRemovalId: Int?
    @State private var showEmptyWarning = false
    @State private var showSaveConfirmation = false
    @State private var savedRemovalCount = 0
    @State private var checkDrawProgress: CGFloat = 0
    @StateObject private var imageStore = PatternImageStore()
    @ObservedObject private var chartStore = ChartHighlightStore.shared
    @ObservedObject private var rowCounterStore = RowCounterStore.shared
    @State private var configuringImage: PatternImage?

    // MARK: - Reading bar
    @AppStorage private var readingBarFraction: Double
    @State private var isDraggingBar = false

    init(pattern: Pattern, store: PatternStore) {
        self.pattern = pattern
        self.store = store
        self._readingBarFraction = AppStorage(
            wrappedValue: 0.3,
            "readingBarFraction_\(pattern.id.uuidString)"
        )
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                        metadataSection

                        if !imageStore.images.isEmpty {
                            photosFromPatternSection
                        }

                        if isEditMode {
                            editModeContent
                                .transition(.opacity)
                        } else {
                            normalModeContent
                                .transition(.opacity)
                        }
                    }
                    .padding(.vertical, Theme.Spacing.lg)
                    // Extra bottom padding when floating bar is visible
                    .padding(.bottom, isEditMode && !removedBlockIds.isEmpty ? 80 : 0)
                }
                .background(Theme.warmCream)

                // Floating save bar
                if isEditMode && !removedBlockIds.isEmpty {
                    floatingSaveBar
                }

                // Reading bar — draggable horizontal highlight line
                if !isEditMode {
                    readingBar(in: geo)
                }
            }
        }
        .navigationTitle("Pattern Content")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: Theme.Spacing.md) {
                    if hasEffectiveContent {
                        Button {
                            withAnimation(reduceMotion ? .none : Theme.Motion.spring) {
                                if isEditMode {
                                    cancelEdit()
                                } else {
                                    enterEditMode()
                                }
                            }
                        } label: {
                            Label(isEditMode ? "Cancel" : "Edit", systemImage: isEditMode ? "xmark" : "pencil")
                        }
                    }

                    if !isEditMode, let url = URL(string: pattern.sourceUrl) {
                        Link(destination: url) {
                            Label("Safari", systemImage: "safari")
                        }
                    }
                }
            }
        }
        .alert("Pattern Content Warning", isPresented: $showPatternContentWarning) {
            Button("Remove Anyway", role: .destructive) {
                if let id = pendingRemovalId {
                    removedBlockIds.insert(id)
                    pendingRemovalId = nil
                }
            }
            Button("Keep", role: .cancel) {
                pendingRemovalId = nil
            }
        } message: {
            Text("This block may contain pattern instructions (stitch counts, measurements, or abbreviations). Are you sure you want to remove it?")
        }
        .alert("Cannot Remove All", isPresented: $showEmptyWarning) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("You must keep at least one content block. Restore some blocks before saving.")
        }
        .overlay {
            if showSaveConfirmation {
                saveConfirmationToast
            }
        }
        .sheet(item: $configuringImage) { image in
            ChartHighlighterSetupSheet(
                patternId: pattern.id,
                image: image,
                existing: chartStore.highlight(patternId: pattern.id, makeId: nil, imageId: image.id),
                secondaryCounters: rowCounterStore.state(for: pattern.id, makeId: nil).secondaryCounters,
                onSave: { chartStore.save($0) },
                onDelete: {
                    chartStore.delete(patternId: pattern.id, makeId: nil, imageId: image.id)
                }
            )
        }
        .task {
            await imageStore.load(patternId: pattern.id)
        }
    }

    // MARK: - Photos from pattern (website images)

    private var photosFromPatternSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Photos from pattern")
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.deepPlum)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.sm) {
                    ForEach(imageStore.images) { img in
                        chartImageCard(img)
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private func chartImageCard(_ img: PatternImage) -> some View {
        let highlight = chartStore.highlight(patternId: pattern.id, makeId: nil, imageId: img.id)
        let rowValue = rowValueFor(highlight)
        let colValue = columnValueFor(highlight)

        ZStack(alignment: .topTrailing) {
            CachedAsyncImage(url: URL(string: img.imageUrl), userId: auth.currentUserId) { phase in
                switch phase {
                case .loading:
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                        .fill(Theme.cardBackground)
                        .frame(width: 220, height: 220)
                        .overlay { ProgressView() }
                case .success(let image):
                    ZStack {
                        image.resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 220, height: 220)
                            .clipped()
                        if let highlight {
                            ChartHighlighterOverlayView(
                                highlight: highlight,
                                rowValue: rowValue,
                                columnValue: colValue
                            )
                            .frame(width: 220, height: 220)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
                case .failure:
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                        .fill(Theme.cardBackground)
                        .frame(width: 220, height: 220)
                        .overlay {
                            Image(systemName: "photo")
                                .font(.title2)
                                .foregroundStyle(Theme.Semantic.textTertiary)
                        }
                }
            }

            Button {
                configuringImage = img
            } label: {
                Image(systemName: "highlighter")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(Theme.dustyBlue)
                    .clipShape(Circle())
            }
            .padding(8)
        }
        .overlay(alignment: .bottomLeading) {
            if highlight != nil {
                Text("Chart linked")
                    .font(Theme.Typography.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Theme.sageGreen.opacity(0.9))
                    .clipShape(Capsule())
                    .padding(8)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if let data = highlight?.extractedChartPNGData, let chartImage = UIImage(data: data) {
                Image(uiImage: chartImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Theme.Semantic.borderStrong, lineWidth: 2)
                    )
                    .padding(8)
            }
        }
    }

    private func rowValueFor(_ highlight: ChartHighlight?) -> Int {
        guard let highlight else { return 1 }
        return counterValue(for: highlight.rowCounterLink)
    }

    private func columnValueFor(_ highlight: ChartHighlight?) -> Int {
        guard let highlight else { return 1 }
        guard let link = highlight.columnCounterLink else { return rowValueFor(highlight) }
        return counterValue(for: link)
    }

    private func counterValue(for link: ChartHighlight.CounterLink) -> Int {
        let state = rowCounterStore.state(for: pattern.id, makeId: nil)
        switch link {
        case .global:
            return state.globalRow
        case .secondary(let id):
            return state.secondaryCounters.first(where: { $0.id == id })?.currentCount ?? 1
        }
    }

    // MARK: - Effective Content

    private var hasEffectiveContent: Bool {
        effectiveContent != nil
    }

    private var effectiveContent: String? {
        let c = PatternStepParser.truncateAtEndOfPattern(pattern.sourceContent) ?? pattern.sourceContent
        guard let c = c, !c.isEmpty else { return nil }
        let isRavelry = !pattern.sourceUrl.isEmpty && pattern.sourceUrl.lowercased().contains("ravelry")
        if isRavelry, PatternStepParser.looksLikeRavelryChrome(c) { return nil }
        return c
    }

    // MARK: - Metadata Section (unchanged — always visible)

    private var metadataSection: some View {
        Group {
            if let craftType = pattern.craftType, !craftType.isEmpty {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "scissors")
                        .foregroundStyle(Theme.softCoral)
                    Text(craftType.capitalized)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.deepPlum)

                    if let difficulty = pattern.difficulty, !difficulty.isEmpty {
                        Text("·")
                            .foregroundStyle(Theme.deepPlum.opacity(0.3))
                        Text(difficulty.capitalized)
                            .font(Theme.Typography.headline)
                            .foregroundStyle(Theme.deepPlum)
                    }
                }
                .padding(.horizontal)
            }

            if let materials = pattern.materials, !materials.isEmpty {
                contentInfoBlock(label: "Materials", value: materials, icon: nil)
            }
            if let gauge = pattern.gauge, !gauge.isEmpty {
                contentInfoBlock(label: "Gauge", value: gauge, icon: "ruler")
            }
            if let needleHook = pattern.needleHookSizes, !needleHook.isEmpty {
                contentInfoBlock(label: "Needles / Hook", value: needleHook, icon: "hammer")
            }
            if let yarnYardage = pattern.yarnWeightYardage, !yarnYardage.isEmpty {
                contentInfoBlock(label: "Yarn weight & yardage", value: yarnYardage, icon: "spool")
            }
            if let techniques = pattern.techniques, !techniques.isEmpty {
                contentInfoBlock(label: "Techniques", value: techniques, icon: "list.bullet")
            }
            if let videoUrl = pattern.videoUrl, !videoUrl.isEmpty, let url = URL(string: videoUrl) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Tutorial video")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.deepPlum.opacity(0.6))
                    Link(destination: url) {
                        HStack(spacing: Theme.Spacing.sm) {
                            Image(systemName: "play.rectangle.fill")
                                .foregroundStyle(Theme.softCoral)
                            Text("Watch video")
                                .font(Theme.Typography.body)
                                .foregroundStyle(Theme.softCoral)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(Theme.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.small))
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Normal Mode (read-only, unchanged rendering)

    @ViewBuilder
    private var normalModeContent: some View {
        if let content = effectiveContent {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Pattern Content")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.deepPlum)
                Divider()
                    .overlay(Theme.softCoral.opacity(0.3))
            }
            .padding(.horizontal)

            let sections = parseContent(decodeHTMLEntitiesInContent(content))
            ForEach(Array(sections.enumerated()), id: \.offset) { index, section in
                switch section.kind {
                case .heading:
                    Text(section.text)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.deepPlum)
                        .padding(.top, index > 0 ? Theme.Spacing.sm : 0)
                        .padding(.horizontal)

                case .bulletList:
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        ForEach(bulletLines(from: section.text), id: \.self) { line in
                            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 5))
                                    .foregroundStyle(Theme.softCoral)
                                    .padding(.top, 7)
                                Text(
                                    StitchAbbreviationLinkBuilder.linkedAttributedString(
                                        from: line,
                                        explicitCraftType: pattern.craftType,
                                        contextText: content
                                    )
                                )
                                    .font(Theme.Typography.body)
                                    .foregroundStyle(Theme.deepPlum)
                            }
                        }
                    }
                    .padding(Theme.Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.small))
                    .padding(.horizontal)

                case .table:
                    tableView(from: section.text)
                        .padding(.horizontal)

                case .paragraph:
                    Text(
                        StitchAbbreviationLinkBuilder.linkedAttributedString(
                            from: section.text,
                            explicitCraftType: pattern.craftType,
                            contextText: content
                        )
                    )
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.deepPlum)
                        .textSelection(.enabled)
                        .padding(.horizontal)
                }
            }
        } else {
            emptyContentView
        }
    }

    // MARK: - Edit Mode (block-level removal)

    @ViewBuilder
    private var editModeContent: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Text("Cleanup Mode")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.deepPlum)
                Spacer()
                Text("\(removedBlockIds.count) removed")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.softCoral)
            }
            .padding(.horizontal)

            Text("Tap the minus button to remove junk. Tap the plus button to restore.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.deepPlum.opacity(0.5))
                .padding(.horizontal)

            Divider()
                .overlay(Theme.softCoral.opacity(0.3))
                .padding(.horizontal)
        }

        ForEach(contentBlocks.filter { $0.kind != .paragraphBreak }) { block in
            editableBlockRow(block)
        }
    }

    @ViewBuilder
    private func editableBlockRow(_ block: ContentBlock) -> some View {
        let isRemoved = removedBlockIds.contains(block.id)

        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            // Remove / restore button
            Button {
                if isRemoved {
                    // Restore
                    removedBlockIds.remove(block.id)
                } else {
                    // Check if it looks like pattern content
                    let indicators = ContentBlockParser.patternContentIndicatorCount(block.text)
                    if indicators >= 2 {
                        pendingRemovalId = block.id
                        showPatternContentWarning = true
                    } else {
                        removedBlockIds.insert(block.id)
                    }
                }
            } label: {
                Image(systemName: isRemoved ? "plus.circle.fill" : "minus.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(isRemoved ? Theme.sageGreen : .red.opacity(0.7))
            }
            .buttonStyle(.plain)
            .padding(.top, 2)

            // Block content
            blockTextView(block)
                .strikethrough(isRemoved, color: Theme.deepPlum.opacity(0.4))
                .opacity(isRemoved ? 0.35 : 1.0)

            Spacer(minLength: 0)
        }
        .padding(.horizontal)
        .padding(.vertical, Theme.Spacing.xs)
        .background(
            isRemoved
                ? Color.red.opacity(0.04)
                : Color.clear
        )
        .animation(reduceMotion ? .none : .easeInOut(duration: 0.2), value: isRemoved)
    }

    @ViewBuilder
    private func blockTextView(_ block: ContentBlock) -> some View {
        switch block.kind {
        case .heading:
            Text(block.text)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.deepPlum)

        case .bullet:
            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                Image(systemName: "circle.fill")
                    .font(.system(size: 5))
                    .foregroundStyle(Theme.softCoral)
                    .padding(.top, 7)
                Text(block.text.hasPrefix("- ") ? String(block.text.dropFirst(2)) : block.text)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.deepPlum)
            }

        case .tableRow:
            Text(block.text)
                .font(.system(size: 13, weight: .regular, design: .monospaced))
                .foregroundStyle(Theme.deepPlum)

        case .sentence:
            Text(block.text)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.deepPlum)

        case .paragraphBreak:
            EmptyView()
        }
    }

    // MARK: - Floating Save Bar

    // MARK: - Reading Bar

    @ViewBuilder
    private func readingBar(in geo: GeometryProxy) -> some View {
        let barY = geo.size.height * readingBarFraction

        ZStack {
            // Semi-transparent highlight band
            Rectangle()
                .fill(Theme.honey.opacity(isDraggingBar ? 0.45 : 0.28))
                .frame(height: 28)
                .frame(maxWidth: .infinity)

            // Drag handle
            HStack {
                Spacer()
                Capsule()
                    .fill(Theme.honey.opacity(0.8))
                    .frame(width: 36, height: 5)
                    .padding(.trailing, Theme.Spacing.lg)
            }
        }
        .position(x: geo.size.width / 2, y: barY)
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    isDraggingBar = true
                    let newY = min(geo.size.height - 20, max(20, barY + value.translation.height))
                    readingBarFraction = Double(newY / geo.size.height)
                }
                .onEnded { _ in
                    isDraggingBar = false
                }
        )
        .accessibilityLabel("Reading bar")
        .accessibilityHint("Drag to mark your place in the pattern")
        .accessibilityValue("Position \(Int(readingBarFraction * 100))%")
    }

    private var floatingSaveBar: some View {
        HStack(spacing: Theme.Spacing.lg) {
            Button("Cancel") {
                cancelEdit()
            }
            .font(Theme.Typography.body)
            .foregroundStyle(Theme.deepPlum.opacity(0.6))

            Spacer()

            Text("\(removedBlockIds.count) block\(removedBlockIds.count == 1 ? "" : "s") removed")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.deepPlum.opacity(0.5))

            Button {
                saveChanges()
            } label: {
                Text("Save Changes")
                    .font(Theme.Typography.cardTitle)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(Theme.sageGreen)
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.large)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.1), radius: 8, y: -2)
        )
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.bottom, Theme.Spacing.sm)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(reduceMotion ? .none : .spring(response: 0.3), value: removedBlockIds.isEmpty)
    }

    // MARK: - Save Confirmation Toast

    private var saveConfirmationToast: some View {
        VStack {
            Spacer()
            HStack(spacing: Theme.Spacing.sm) {
                SpriteMascotView.idle(size: 40)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.sageGreen)
                    .scaleEffect(checkDrawProgress)
                Text("Cleaned up \(savedRemovalCount) block\(savedRemovalCount == 1 ? "" : "s")")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.deepPlum)
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.vertical, Theme.Spacing.md)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.1), radius: 6, y: 2)
            )
            .padding(.bottom, 40)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(reduceMotion ? .none : .spring(response: 0.4), value: showSaveConfirmation)
    }

    // MARK: - Empty State

    private var emptyContentView: some View {
        VStack(spacing: Theme.Spacing.xl) {
            SpriteMascotView.idle(size: 100)
            Text("No extracted content available")
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.deepPlum)
            Text("Try opening the original page in a browser and use Share to save it with content.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.deepPlum.opacity(0.55))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xxl)
        .padding(.horizontal, Theme.Spacing.xl)
        .borderedCard()
    }

    // MARK: - Edit Mode Actions

    private func enterEditMode() {
        guard let content = effectiveContent else { return }
        contentBlocks = ContentBlockParser.parse(content)
        removedBlockIds = []
        isEditMode = true
    }

    private func cancelEdit() {
        isEditMode = false
        removedBlockIds = []
        contentBlocks = []
        pendingRemovalId = nil
    }

    private func saveChanges() {
        // Check we're not removing everything
        let visibleBlocks = contentBlocks.filter { $0.kind != .paragraphBreak && !removedBlockIds.contains($0.id) }
        if visibleBlocks.isEmpty {
            showEmptyWarning = true
            return
        }

        let newContent = ContentBlockParser.reassemble(blocks: contentBlocks, excluding: removedBlockIds)
        let removedCount = removedBlockIds.count

        // Persist to Supabase
        guard let userId = auth.currentUserId else { return }
        Task {
            await store.updateSourceContent(pattern: pattern, userId: userId, newContent: newContent)
        }

        savedRemovalCount = removedCount
        isEditMode = false
        removedBlockIds = []
        contentBlocks = []

        // Show confirmation toast
        showSaveConfirmation = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        if reduceMotion {
            checkDrawProgress = 1.0
        } else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                checkDrawProgress = 1.0
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            showSaveConfirmation = false
            checkDrawProgress = 0
        }
    }

    // MARK: - Content Info Block Helper

    @ViewBuilder
    private func contentInfoBlock(label: String, value: String, icon: String?) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.sm) {
                if let icon {
                    Image(systemName: icon)
                        .foregroundStyle(Theme.softCoral)
                }
                Text(label)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.deepPlum.opacity(0.6))
            }
            Text(value)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.deepPlum)
        }
        .padding(.horizontal)
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.small))
        .padding(.horizontal)
    }

    /// Decodes common HTML entities in stored pattern content.
    private func decodeHTMLEntitiesInContent(_ text: String) -> String {
        var result = text
        let entities: [(String, String)] = [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"),
            ("&nbsp;", " "), ("&hellip;", "…"), ("&mdash;", "—"), ("&ndash;", "–")
        ]
        for (entity, replacement) in entities {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        return result
    }

    // MARK: - Content Parsing (for normal mode)

    private enum ContentKind {
        case heading, bulletList, paragraph, table
    }

    private struct ContentSection {
        let kind: ContentKind
        let text: String
    }

    private func parseContent(_ text: String) -> [ContentSection] {
        let blocks = text.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return blocks.map { block in
            let lines = block.components(separatedBy: "\n")
            let pipeLines = lines.filter { $0.contains(" | ") || $0.contains("| ") }
            if pipeLines.count >= 2 {
                return ContentSection(kind: .table, text: block)
            }
            if block.contains("\n- ") || block.hasPrefix("- ") {
                return ContentSection(kind: .bulletList, text: block)
            }
            if lines.count == 1 && block.count < 60
                && !block.hasSuffix(".") && !block.hasSuffix(",")
                && !block.hasSuffix("!") && !block.hasSuffix("?") {
                return ContentSection(kind: .heading, text: block)
            }
            return ContentSection(kind: .paragraph, text: block)
        }
    }

    private func bulletLines(from text: String) -> [String] {
        text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .map { $0.hasPrefix("- ") ? String($0.dropFirst(2)) : $0 }
            .filter { !$0.isEmpty }
    }

    // MARK: - Table Rendering

    @ViewBuilder
    private func tableView(from text: String) -> some View {
        let rows = parseTableRows(from: text)
        if rows.count >= 2 {
            VStack(spacing: 0) {
                let header = rows[0]
                HStack(spacing: 0) {
                    ForEach(Array(header.enumerated()), id: \.offset) { _, cell in
                        Text(cell)
                            .font(Theme.Typography.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.deepPlum)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 4)
                    }
                }
                .background(Theme.softCoral.opacity(0.15))

                ForEach(Array(rows.dropFirst().enumerated()), id: \.offset) { rowIdx, row in
                    HStack(spacing: 0) {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            Text(cell)
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.deepPlum)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 6)
                                .padding(.horizontal, 4)
                        }
                    }
                    .background(rowIdx % 2 == 0 ? Theme.cardBackground : Color.clear)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.small))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.small)
                    .stroke(Theme.deepPlum.opacity(0.1), lineWidth: 1)
            )
        }
    }

    private func parseTableRows(from text: String) -> [[String]] {
        text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { row in
                row.components(separatedBy: "|")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            }
            .filter { !$0.isEmpty }
    }
}

private struct ChartHighlighterSetupSheet: View {
    let patternId: UUID
    let image: PatternImage
    let existing: ChartHighlight?
    let secondaryCounters: [SecondaryCounter]
    let onSave: (ChartHighlight) -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var minX: Double = 0.1
    @State private var minY: Double = 0.1
    @State private var maxX: Double = 0.9
    @State private var maxY: Double = 0.9
    @State private var rows: Int = 40
    @State private var columns: Int = 40
    @State private var chartType: ChartHighlight.ChartType = .workedFlat
    @State private var isSideways = false
    @State private var isC2C = false
    @State private var rowLinkSelection = "global"
    @State private var colLinkSelection = "global"
    @State private var activeHandle: CornerHandle?
    @State private var sourceImage: UIImage?
    @State private var extractedChartData: Data?
    @State private var editorZoom: Double = 1.0

    private enum CornerHandle {
        case topLeft
        case topRight
        case bottomLeft
        case bottomRight
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Chart area") {
                    Text("Drag corner handles directly on the image. Zoom and pan for precise placement.")
                        .font(Theme.Typography.caption2)
                        .foregroundStyle(Theme.deepPlum.opacity(0.6))
                    visualRegionEditor
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "minus.magnifyingglass")
                            .foregroundStyle(Color.primary.opacity(0.75))
                        Slider(value: $editorZoom, in: 1...4, step: 0.1)
                        Image(systemName: "plus.magnifyingglass")
                            .foregroundStyle(Color.primary.opacity(0.75))
                        Text("\(editorZoom, specifier: "%.1f")x")
                            .font(Theme.Typography.caption2)
                            .foregroundStyle(Color.primary.opacity(0.8))
                            .frame(width: 42, alignment: .trailing)
                    }
                    slider("Left", value: $minX)
                    slider("Top", value: $minY)
                    slider("Right", value: $maxX)
                    slider("Bottom", value: $maxY)
                }

                Section("Extract chart") {
                    Button("Extract Chart From Selection") {
                        extractChartFromSelection()
                    }
                    .disabled(sourceImage == nil)

                    if let extractedChartData, let chartImage = UIImage(data: extractedChartData) {
                        Image(uiImage: chartImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 220)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
                    }
                }

                Section("Grid") {
                    Stepper("Rows: \(rows)", value: $rows, in: 1...999)
                    Stepper("Columns: \(columns)", value: $columns, in: 1...999)
                    Picker("Chart type", selection: $chartType) {
                        Text("Worked flat").tag(ChartHighlight.ChartType.workedFlat)
                        Text("Worked in the round").tag(ChartHighlight.ChartType.workedInRound)
                    }
                    Toggle("Displayed sideways", isOn: $isSideways)
                    Toggle("Corner to corner (C2C)", isOn: $isC2C)
                }

                Section("Counter links") {
                    Picker("Row link", selection: $rowLinkSelection) {
                        Text("Global counter").tag("global")
                        ForEach(secondaryCounters) { counter in
                            Text(counter.title).tag(counter.id.uuidString)
                        }
                    }
                    Picker("Column link", selection: $colLinkSelection) {
                        Text("Global counter").tag("global")
                        ForEach(secondaryCounters) { counter in
                            Text(counter.title).tag(counter.id.uuidString)
                        }
                    }
                }

                if existing != nil {
                    Section {
                        Button("Delete chart highlighter", role: .destructive) {
                            onDelete()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Chart Highlighter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let autoExtracted = extractChartDataFromSelection()
                        let chart = ChartHighlight(
                            id: existing?.id ?? UUID(),
                            patternId: patternId,
                            makeId: nil,
                            imageId: image.id,
                            minX: min(minX, maxX),
                            minY: min(minY, maxY),
                            maxX: max(minX, maxX),
                            maxY: max(minY, maxY),
                            rows: rows,
                            columns: columns,
                            chartType: chartType,
                            isSideways: isSideways,
                            isC2C: isC2C,
                            rowCounterLink: resolveLink(rowLinkSelection),
                            columnCounterLink: resolveLink(colLinkSelection),
                            rowColorName: "honey",
                            columnColorName: "softCoral",
                            extractedChartPNGData: autoExtracted ?? extractedChartData ?? existing?.extractedChartPNGData,
                            annotationDrawingData: existing?.annotationDrawingData,
                            currentRow: existing?.currentRow ?? 1,
                            currentColumn: existing?.currentColumn ?? 1,
                            annotations: existing?.annotations ?? [],
                            gridInsetLeft: existing?.gridInsetLeft ?? 0,
                            gridInsetTop: existing?.gridInsetTop ?? 0,
                            gridInsetRight: existing?.gridInsetRight ?? 0,
                            gridInsetBottom: existing?.gridInsetBottom ?? 0
                        )
                        onSave(chart)
                        dismiss()
                    }
                }
            }
            .onAppear {
                if sourceImage == nil {
                    Task { await loadSourceImage() }
                }
                guard let existing else { return }
                minX = existing.minX
                minY = existing.minY
                maxX = existing.maxX
                maxY = existing.maxY
                rows = existing.rows
                columns = existing.columns
                chartType = existing.chartType
                isSideways = existing.isSideways
                isC2C = existing.isC2C
                rowLinkSelection = selection(from: existing.rowCounterLink)
                colLinkSelection = selection(from: existing.columnCounterLink ?? .global)
                extractedChartData = existing.extractedChartPNGData
            }
        }
    }

    private func slider(_ title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title)
            Slider(value: value, in: 0...1)
            Text("\(Int(value.wrappedValue * 100))%")
                .font(Theme.Typography.caption2)
                .foregroundStyle(Theme.deepPlum.opacity(0.6))
                .frame(width: 44, alignment: .trailing)
        }
    }

    private var visualRegionEditor: some View {
        GeometryReader { geo in
            let containerSize = geo.size
            let zoom = CGFloat(editorZoom)
            let canvasSize = CGSize(
                width: max(1, containerSize.width * zoom),
                height: max(1, containerSize.height * zoom)
            )
            let contentFrame = contentFrame(in: canvasSize)
            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                ZStack {
                    if let sourceImage {
                        Image(uiImage: sourceImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: canvasSize.width, height: canvasSize.height)
                    } else {
                        AsyncImage(url: URL(string: image.imageUrl)) { phase in
                            switch phase {
                            case .success(let img):
                                img
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: canvasSize.width, height: canvasSize.height)
                            case .failure:
                                RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                                    .fill(Theme.cardBackground)
                                    .overlay {
                                        Image(systemName: "photo")
                                            .font(.title2)
                                            .foregroundStyle(Theme.deepPlum.opacity(0.3))
                                    }
                            default:
                                RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                                    .fill(Theme.cardBackground)
                                    .overlay { ProgressView() }
                            }
                        }
                    }
                    regionOverlay(in: canvasSize, contentFrame: contentFrame)
                }
                .frame(width: canvasSize.width, height: canvasSize.height)
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
        }
        .frame(height: 280)
    }

    @ViewBuilder
    private func regionOverlay(in size: CGSize, contentFrame: CGRect) -> some View {
        let rect = CGRect(
            x: contentFrame.minX + contentFrame.width * minX,
            y: contentFrame.minY + contentFrame.height * minY,
            width: contentFrame.width * max(0.001, maxX - minX),
            height: contentFrame.height * max(0.001, maxY - minY)
        )

        ZStack {
            Path { path in
                path.addRect(CGRect(origin: .zero, size: size))
                path.addRect(rect)
            }
            .fill(Color.black.opacity(0.18), style: FillStyle(eoFill: true))

            RoundedRectangle(cornerRadius: 8)
                .stroke(Theme.honey, lineWidth: 2)
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)

            editorHandle(in: size, contentFrame: contentFrame, x: rect.minX, y: rect.minY, handle: .topLeft)
            editorHandle(in: size, contentFrame: contentFrame, x: rect.maxX, y: rect.minY, handle: .topRight)
            editorHandle(in: size, contentFrame: contentFrame, x: rect.minX, y: rect.maxY, handle: .bottomLeft)
            editorHandle(in: size, contentFrame: contentFrame, x: rect.maxX, y: rect.maxY, handle: .bottomRight)
        }
    }

    @ViewBuilder
    private func editorHandle(in size: CGSize, contentFrame: CGRect, x: CGFloat, y: CGFloat, handle: CornerHandle) -> some View {
        Circle()
            .fill(Theme.softCoral)
            .frame(width: 18, height: 18)
            .overlay(Circle().stroke(Theme.Semantic.textPrimary, lineWidth: 2))
            .position(x: x, y: y)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        activeHandle = handle
                        updateHandle(handle, location: value.location, in: contentFrame)
                    }
                    .onEnded { _ in
                        activeHandle = nil
                    }
            )
    }

    private func updateHandle(_ handle: CornerHandle, location: CGPoint, in contentFrame: CGRect) {
        guard contentFrame.width > 0, contentFrame.height > 0 else { return }
        let nx = min(max(Double((location.x - contentFrame.minX) / contentFrame.width), 0), 1)
        let ny = min(max(Double((location.y - contentFrame.minY) / contentFrame.height), 0), 1)
        let minGap = 0.03

        switch handle {
        case .topLeft:
            minX = min(nx, maxX - minGap)
            minY = min(ny, maxY - minGap)
        case .topRight:
            maxX = max(nx, minX + minGap)
            minY = min(ny, maxY - minGap)
        case .bottomLeft:
            minX = min(nx, maxX - minGap)
            maxY = max(ny, minY + minGap)
        case .bottomRight:
            maxX = max(nx, minX + minGap)
            maxY = max(ny, minY + minGap)
        }
    }

    private func resolveLink(_ selection: String) -> ChartHighlight.CounterLink {
        if selection == "global" { return .global }
        if let id = UUID(uuidString: selection) { return .secondary(id) }
        return .global
    }

    private func selection(from link: ChartHighlight.CounterLink) -> String {
        switch link {
        case .global: return "global"
        case .secondary(let id): return id.uuidString
        }
    }

    private func loadSourceImage() async {
        guard let url = URL(string: image.imageUrl) else { return }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) { return }
            sourceImage = UIImage(data: data)
        } catch {
            return
        }
    }

    private func extractChartFromSelection() {
        extractedChartData = extractChartDataFromSelection()
    }

    private func extractChartDataFromSelection() -> Data? {
        guard let sourceImage else { return nil }
        guard let cropped = cropImage(
            sourceImage,
            minX: min(minX, maxX),
            minY: min(minY, maxY),
            maxX: max(minX, maxX),
            maxY: max(minY, maxY)
        ) else { return nil }
        return cropped.pngData()
    }

    private func contentFrame(in containerSize: CGSize) -> CGRect {
        guard containerSize.width > 0, containerSize.height > 0 else { return .zero }
        guard let sourceImage else {
            return CGRect(origin: .zero, size: containerSize)
        }
        return aspectFitRect(contentSize: sourceImage.size, in: containerSize)
    }

    private func aspectFitRect(contentSize: CGSize, in containerSize: CGSize) -> CGRect {
        guard contentSize.width > 0, contentSize.height > 0,
              containerSize.width > 0, containerSize.height > 0 else {
            return CGRect(origin: .zero, size: containerSize)
        }
        let scale = min(containerSize.width / contentSize.width, containerSize.height / contentSize.height)
        let width = contentSize.width * scale
        let height = contentSize.height * scale
        let origin = CGPoint(
            x: (containerSize.width - width) / 2,
            y: (containerSize.height - height) / 2
        )
        return CGRect(origin: origin, size: CGSize(width: width, height: height))
    }

    private func cropImage(_ image: UIImage, minX: Double, minY: Double, maxX: Double, maxY: Double) -> UIImage? {
        guard let cg = image.cgImage else { return nil }
        let width = CGFloat(cg.width)
        let height = CGFloat(cg.height)
        let rect = CGRect(
            x: width * CGFloat(minX),
            y: height * CGFloat(minY),
            width: width * CGFloat(max(0.001, maxX - minX)),
            height: height * CGFloat(max(0.001, maxY - minY))
        ).integral

        guard let cropped = cg.cropping(to: rect) else { return nil }
        return UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
    }
}
