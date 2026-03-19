//
//  PatternContentView.swift
//  PatternVault
//
//  Displays extracted pattern content with an edit mode that lets users
//  surgically remove individual sentences, bullets, and table rows.
//  Removed blocks are learned as junk phrases for future import filtering.
//

import SwiftUI

struct PatternContentView: View {
    let pattern: Pattern
    @ObservedObject var store: PatternStore
    @EnvironmentObject var auth: AuthService

    // MARK: - Edit mode state

    @State private var isEditMode = false
    @State private var contentBlocks: [ContentBlock] = []
    @State private var removedBlockIds: Set<Int> = []
    @State private var showPatternContentWarning = false
    @State private var pendingRemovalId: Int?
    @State private var showEmptyWarning = false
    @State private var showSaveConfirmation = false
    @State private var savedRemovalCount = 0
    @StateObject private var imageStore = PatternImageStore()

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    metadataSection

                    if !imageStore.images.isEmpty {
                        photosFromPatternSection
                    }

                    if isEditMode {
                        editModeContent
                    } else {
                        normalModeContent
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
        }
        .navigationTitle("Pattern Content")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: Theme.Spacing.md) {
                    if hasEffectiveContent {
                        Button {
                            if isEditMode {
                                cancelEdit()
                            } else {
                                enterEditMode()
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
                        CachedAsyncImage(url: URL(string: img.imageUrl), userId: auth.currentUserId) { phase in
                            switch phase {
                            case .loading:
                                RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                                    .fill(Theme.cardBackground)
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
                                    .fill(Theme.cardBackground)
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
            }
        }
        .padding(.horizontal)
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
                                Text(line)
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
                    Text(section.text)
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
        .animation(.easeInOut(duration: 0.2), value: isRemoved)
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
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
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
        .animation(.spring(response: 0.3), value: removedBlockIds.isEmpty)
    }

    // MARK: - Save Confirmation Toast

    private var saveConfirmationToast: some View {
        VStack {
            Spacer()
            HStack(spacing: Theme.Spacing.sm) {
                SpriteMascotView.idle(size: 40)
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.sageGreen)
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
        .animation(.spring(response: 0.4), value: showSaveConfirmation)
    }

    // MARK: - Empty State

    private var emptyContentView: some View {
        VStack(spacing: Theme.Spacing.xl) {
            SpriteMascotView.idle(size: 100)
            Text("No extracted content available")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
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

        // Learn from removed blocks
        let removedBlocks = contentBlocks.filter { removedBlockIds.contains($0.id) }
        for block in removedBlocks {
            JunkPhraseStore.shared.addPhrase(
                text: block.text,
                patternId: pattern.id,
                fullText: block.text
            )
        }

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
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            showSaveConfirmation = false
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
