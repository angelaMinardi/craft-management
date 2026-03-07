//
//  PatternDetailView.swift
//  PatternVault
//

import SwiftUI
import WebKit

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
    @State private var showUpdateProgressSheet = false
    @State private var updateRowsCompleted = ""
    @State private var updateTotalRows = ""
    @State private var showLogTimeSheet = false
    @State private var logTimeNote = ""
    @State private var showYarnColorSheet = false
    @State private var showStepEditor = false
    @State private var junkFeedbackMessage: String?
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var progressStore = PatternProgressStore.shared
    @ObservedObject private var junkStore = JunkPhraseStore.shared

    private var current: Pattern {
        store.patterns.first(where: { $0.id == pattern.id }) ?? pattern
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(spacing: 0) {
                    // MARK: - Hero
                    heroSection

                    // MARK: - Pattern header card (mascot + title + Download)
                    patternHeaderCard

                    // MARK: - Main content (padded)
                    VStack(spacing: Theme.Spacing.xl) {
                        titleSection
                        statusPicker

                        // MARK: - Step 1 / Progress (mockup-style)
                        patternStepSection

                    if hasPatternInfo {
                        patternInfoSection
                    }

                    if !yarnLinkStore.links.isEmpty {
                        yarnLinksSection
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)
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
                .padding(.top, Theme.Spacing.xl)
                .padding(.bottom, 100)
            }
            }
            .background(Theme.screenGradient.ignoresSafeArea())

            // Floating tool palette + mascot peek (mockup-style)
            floatingToolPalette
        }
        .navigationTitle(current.title)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete Pattern", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) { deletePattern() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will also delete all notes. This cannot be undone.")
        }
        .alert("Content cleanup", isPresented: Binding(get: { junkFeedbackMessage != nil }, set: { if !$0 { junkFeedbackMessage = nil } })) {
            Button("OK") { junkFeedbackMessage = nil }
        } message: {
            if let msg = junkFeedbackMessage { Text(msg) }
        }
        .sheet(isPresented: $showAddNote) {
            AddNoteView(noteStore: noteStore, patternId: current.id)
        }
        .sheet(isPresented: $showTagPicker) {
            TagPickerView(tagStore: tagStore, patternId: current.id)
        }
        .sheet(isPresented: $showWebView) {
            NavigationStack {
                InAppWebView(url: URL(string: current.sourceUrl)!)
                    .navigationTitle("Pattern Page")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showWebView = false }
                        }
                        ToolbarItem(placement: .primaryAction) {
                            if let url = URL(string: current.sourceUrl) {
                                Link(destination: url) {
                                    Image(systemName: "safari")
                                }
                            }
                        }
                    }
            }
        }
        .sheet(isPresented: $showPdfViewer) {
            if let pdfUrlString = current.pdfUrl, let pdfURL = URL(string: pdfUrlString) {
                NavigationStack {
                    PDFViewerView(url: pdfURL)
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
        .task {
            async let notes: () = noteStore.load(patternId: current.id)
            async let allTags: () = tagStore.loadAllTags()
            async let patternTags: () = tagStore.loadPatternTags(patternId: current.id)
            async let images: () = imageStore.load(patternId: current.id)
            async let yarnLinks: () = yarnLinkStore.load(patternId: current.id)
            _ = await (notes, allTags, patternTags, images, yarnLinks)
        }
        .refreshable {
            await noteStore.load(patternId: current.id)
            await tagStore.loadPatternTags(patternId: current.id)
            await imageStore.load(patternId: current.id)
            await yarnLinkStore.load(patternId: current.id)
        }
    }

    // MARK: - Hero Image

    private var heroSection: some View {
        ZStack(alignment: .bottom) {
            if let thumbnailUrl = current.thumbnailUrl, let imageURL = URL(string: thumbnailUrl) {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(height: 260)
                            .clipped()
                    case .failure:
                        heroPlaceholder
                    default:
                        Rectangle()
                            .fill(Theme.warmCream)
                            .frame(height: 260)
                            .overlay { ProgressView() }
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
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial)
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
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.deepPlum)
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

    // MARK: - Steps / progress (from PatternStepParser + PatternProgressStore)

    private var patternSteps: [PatternStep] {
        let layout = progressStore.customStepLayout(for: current.id)
        let content = current.sourceContent
        let hash = contentHashForStepLayout(content)
        if let layout = layout, layout.contentHash == hash, let content = content, !content.isEmpty {
            let allBlocks = ContentBlockParser.parse(content)
            let blocks = allBlocks.filter { $0.kind != .paragraphBreak }
            let steps = buildStepsFromLayout(layout, blocks: blocks)
            if !steps.isEmpty { return steps }
        }
        return PatternStepParser.parseSteps(sourceContent: current.sourceContent, patternDescription: current.patternDescription)
    }

    private func buildStepsFromLayout(_ layout: CustomStepLayout, blocks: [ContentBlock]) -> [PatternStep] {
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
        return result.isEmpty ? PatternStepParser.parseSteps(sourceContent: current.sourceContent, patternDescription: current.patternDescription) : result
    }

    private var currentStepIndex: Int {
        let steps = patternSteps
        let stored = progressStore.progress(for: current.id)?.currentStepIndex ?? 0
        return min(max(0, stored), max(0, steps.count - 1))
    }

    private var stepProgressFraction: Double {
        let data = progressStore.progress(for: current.id)
        let steps = patternSteps
        if let rc = data?.rowsCompleted, let tr = data?.totalRows, tr > 0 {
            return min(1, max(0, Double(rc) / Double(tr)))
        }
        let stepCount = max(1, steps.count)
        let index = currentStepIndex
        return Double(index + 1) / Double(stepCount)
    }

    private var patternStepSection: some View {
        let steps = patternSteps
        let index = currentStepIndex
        return Group {
            if steps.isEmpty {
                EmptyView()
            } else {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        HStack {
                            SectionHeaderView(title: steps.count > 1 ? "Step \(index + 1) of \(steps.count)" : "Step 1")
                                .accessibilityAddTraits(.isHeader)
                            Spacer()
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
                                    progressStore.setCurrentStep(patternId: current.id, index: index - 1, stepCount: steps.count)
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
                                    progressStore.setCurrentStep(patternId: current.id, index: index + 1, stepCount: steps.count)
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
                        Text(steps[index].body)
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.deepPlum)
                            .lineSpacing(4)
                        HStack(spacing: Theme.Spacing.sm) {
                            Text("\(Int(stepProgressFraction * 100))%")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
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
                    .borderedCard()
                    .contextMenu {
                        Button(role: .destructive) {
                            markStepAsNotPartOfPattern(stepIndex: index, steps: steps)
                        } label: {
                            Label("Not part of pattern", systemImage: "eye.slash")
                        }
                    }

                    Button { showUpdateProgressSheet = true } label: {
                        HStack(spacing: Theme.Spacing.sm) {
                            Image(systemName: "chart.bar.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(Theme.sageGreen)
                            Text("Update progress (rows)")
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.deepPlum.opacity(0.7))
                            Spacer()
                            if let data = progressStore.progress(for: current.id), let rc = data.rowsCompleted, let tr = data.totalRows, tr > 0 {
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
                    .accessibilityHint("Set rows completed and total rows for this pattern")
                }
            }
        }
        .sheet(isPresented: $showUpdateProgressSheet) {
            updateProgressSheet
        }
        .sheet(isPresented: $showStepEditor) {
            StepEditorView(pattern: current, progressStore: progressStore, isPresented: $showStepEditor)
        }
    }

    private var updateProgressSheet: some View {
        let data = progressStore.progress(for: current.id)
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
                    Text("Progress bar will use rows when set. Optionally saves a progress note.")
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
        progressStore.setRows(patternId: current.id, completed: completed, total: total)
        if let userId = auth.currentUserId, let total = total, total > 0 {
            let content = "\(completed) of \(total) rows completed"
            Task {
                _ = await noteStore.add(patternId: current.id, userId: userId, noteType: .progressUpdate, content: content, photoData: nil)
            }
        }
        showUpdateProgressSheet = false
    }

    private func markStepAsNotPartOfPattern(stepIndex: Int, steps: [PatternStep]) {
        guard stepIndex >= 0, stepIndex < steps.count else { return }
        let body = steps[stepIndex].body
        let firstLine = body.components(separatedBy: "\n").first?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? String(body.prefix(80))
        let added = junkStore.addPhrase(text: firstLine, patternId: current.id, fullText: body)
        junkFeedbackMessage = added
            ? "This phrase will be hidden in future pattern steps. You can manage removed phrases in Settings."
            : "This looks like pattern instructions; it wasn’t added. Remove only nav or ads."
    }

    // MARK: - Floating tool palette + mascot peek (tappable: Log time, Yarn color)

    private var floatingToolPalette: some View {
        let yarnLabel = progressStore.progress(for: current.id)?.yarnColorName ?? "Color"
        return HStack(alignment: .bottom, spacing: 0) {
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: Theme.Spacing.sm) {
                HStack(spacing: Theme.Spacing.sm) {
                    Button { showLogTimeSheet = true } label: {
                        toolPaletteChip(icon: "clock", label: "Log time")
                    }
                    .buttonStyle(.plain)
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

                SpriteMascotView.idle(size: 56)
                    .padding(.trailing, 8)
            }
            .padding(.bottom, 100)
        }
        .sheet(isPresented: $showLogTimeSheet) { logTimeSheet }
        .sheet(isPresented: $showYarnColorSheet) { yarnColorSheet }
    }

    private var logTimeSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What did you work on?", text: $logTimeNote, axis: .vertical)
                        .lineLimit(2...4)
                } header: {
                    Text("Log time")
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
                }
            }
        }
    }

    private func saveLogTime() {
        let content = logTimeNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Time logged \(Date().formatted(date: .abbreviated, time: .shortened))"
            : logTimeNote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let userId = auth.currentUserId else { showLogTimeSheet = false; return }
        Task {
            _ = await noteStore.add(patternId: current.id, userId: userId, noteType: .progressUpdate, content: content, photoData: nil)
        }
        logTimeNote = ""
        showLogTimeSheet = false
    }

    private static let yarnColorOptions = ["Warm", "DUSTY BLUE", "Sage", "Coral", "Plum", "Honey", "Clear"]

    private var yarnColorSheet: some View {
        NavigationStack {
            List {
                ForEach(Self.yarnColorOptions, id: \.self) { name in
                    Button {
                        progressStore.setYarnColor(patternId: current.id, colorName: name == "Clear" ? nil : name)
                        showYarnColorSheet = false
                    } label: {
                        HStack {
                            Text(name)
                                .foregroundStyle(Theme.deepPlum)
                            if progressStore.progress(for: current.id)?.yarnColorName == name {
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
            .navigationTitle("Yarn color")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { showYarnColorSheet = false }
                }
            }
        }
    }

    private func toolPaletteChip(icon: String, label: String) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Theme.dustyBlue)
            if !label.isEmpty {
                Text(label)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.deepPlum.opacity(0.7))
                    .lineLimit(1)
            }
        }
        .frame(minWidth: 44, minHeight: 40)
    }

    // MARK: - Title & Description

    private var titleSection: some View {
        Group {
            if isEditingTitle {
                editTitleCard
            } else {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text(current.title)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.deepPlum)

                    if let desc = current.patternDescription, !desc.isEmpty {
                        Text(desc)
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.deepPlum.opacity(0.6))
                            .lineSpacing(3)
                    }

                    // Quick-info pills (craft type + difficulty)
                    if hasQuickInfo {
                        HStack(spacing: Theme.Spacing.sm) {
                            if let craftType = current.craftType, !craftType.isEmpty {
                                quickInfoPill(icon: "scissors", text: craftType.capitalized)
                            }
                            if let difficulty = current.difficulty, !difficulty.isEmpty {
                                quickInfoPill(icon: "chart.bar", text: difficulty.capitalized)
                            }
                        }
                        .padding(.top, Theme.Spacing.xs)
                    }
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
                .font(.system(size: 20, weight: .semibold, design: .rounded))
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

    // MARK: - Status Picker (horizontal pills)

    private var statusPicker: some View {
        HStack(spacing: Theme.Spacing.sm) {
            ForEach(PatternStatus.allCases, id: \.self) { status in
                Button { changeStatus(to: status) } label: {
                    HStack(spacing: 5) {
                        Image(systemName: Theme.statusIcon(for: status))
                            .font(.system(size: 11, weight: .bold))
                        Text(status.displayName)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
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

    // MARK: - Yarn & Supplies

    private var yarnLinksSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeaderView(title: "Yarn & Supplies")

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
                        AsyncImage(url: URL(string: img.imageUrl)) { phase in
                            switch phase {
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
                            default:
                                RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                                    .fill(Theme.warmCream)
                                    .frame(width: 160, height: 160)
                                    .overlay { ProgressView() }
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
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "tag")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.deepPlum.opacity(0.3))
                        Text("Add tags to organize this pattern")
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.deepPlum.opacity(0.4))
                        Spacer()
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .semibold))
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
                            .font(.system(size: 13, weight: .medium, design: .rounded))
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
                VStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "note.text")
                        .font(.system(size: 28))
                        .foregroundStyle(Theme.deepPlum.opacity(0.15))
                    Text("No notes yet")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.deepPlum.opacity(0.4))
                    Text("Tap \"Add\" to create your first note")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.deepPlum.opacity(0.3))
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
                    .font(.system(size: 14, weight: .medium, design: .rounded))
            }
            .foregroundStyle(.red.opacity(0.5))
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
                .font(.system(size: 12, weight: .medium, design: .rounded))
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

    private func domainFromURL(_ urlString: String) -> String? {
        guard let url = URL(string: urlString),
              let host = url.host else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
