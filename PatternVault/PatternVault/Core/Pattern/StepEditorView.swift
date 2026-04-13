//
//  StepEditorView.swift
//  PatternVault
//
//  Full-screen sheet to define custom step boundaries and titles for a pattern.
//  Uses ContentBlockParser blocks; user taps gaps to insert step dividers.
//

import SwiftUI

struct StepEditorView: View {
    let pattern: Pattern
    @ObservedObject var progressStore: PatternProgressStore
    @Binding var isPresented: Bool

    /// Visible content blocks (paragraph breaks excluded) for step boundaries.
    @State private var blocks: [ContentBlock] = []
    /// Included-block indices where a new step starts (not original indices). E.g. [2, 5] => step 2 starts at included index 2.
    @State private var stepBreakIndices: Set<Int> = []
    /// Step number (1-based) → custom title.
    @State private var stepTitles: [Int: String] = [:]
    /// Original block indices the user excluded from steps (tips, anecdotes, etc.).
    @State private var excludedBlockIndices: Set<Int> = []

    private var sortedStarts: [Int] {
        [0] + stepBreakIndices.sorted()
    }

    /// (block, originalIndex, includedIndex) for each block. includedIndex is nil when block is excluded.
    private var blocksWithIncludedIndex: [(block: ContentBlock, originalIndex: Int, includedIndex: Int?)] {
        var includedCount = 0
        return blocks.enumerated().map { originalIndex, block in
            let inc: Int? = excludedBlockIndices.contains(originalIndex) ? nil : includedCount
            if !excludedBlockIndices.contains(originalIndex) { includedCount += 1 }
            return (block, originalIndex, inc)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if blocks.isEmpty {
                    VStack(spacing: Theme.Spacing.xl) {
                        SpriteMascotView.idle(size: 100)
                        Text("No content to split")
                            .font(Theme.Typography.headline)
                            .foregroundStyle(Theme.deepPlum)
                        Text("This pattern has no instruction content. Add or refresh content to define steps.")
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.deepPlum.opacity(0.55))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.xxl)
                    .padding(.horizontal, Theme.Spacing.xl)
                    .borderedCard()
                    .padding(.horizontal, Theme.Spacing.lg)
                } else {
                    stepEditorList
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.screenGradient.ignoresSafeArea())
            .navigationTitle("Edit steps")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveAndDismiss() }
                        .disabled(blocks.isEmpty)
                }
            }
            .safeAreaInset(edge: .bottom) {
                bottomBar
            }
            .onAppear { prefillFromContentOrLayout() }
        }
    }

    private var stepEditorList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(blocksWithIncludedIndex.enumerated()), id: \.element.1) { idx, item in
                    let (block, originalIndex, includedIndex) = (item.block, item.originalIndex, item.includedIndex)
                    blockRow(block: block, originalIndex: originalIndex, isExcluded: includedIndex == nil)
                    if idx < blocksWithIncludedIndex.count - 1 {
                        if let inc = includedIndex {
                            gapOrDivider(nextIncludedStartIndex: inc + 1)
                        } else {
                            excludedSpacer
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.md)
        }
    }

    private func blockRow(block: ContentBlock, originalIndex: Int, isExcluded: Bool) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Text(block.text)
                .font(Theme.Typography.body)
                .foregroundStyle(isExcluded ? Theme.deepPlum.opacity(0.5) : Theme.deepPlum)
                .strikethrough(isExcluded)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                if isExcluded {
                    excludedBlockIndices.remove(originalIndex)
                } else {
                    excludedBlockIndices.insert(originalIndex)
                }
            } label: {
                Image(systemName: isExcluded ? "plus.circle.fill" : "minus.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(isExcluded ? Theme.sageGreen : Theme.softCoral)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExcluded ? "Include in steps" : "Exclude from steps")
        }
        .padding(Theme.Spacing.md)
        .background(isExcluded ? Theme.deepPlum.opacity(0.06) : Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
    }

    private var excludedSpacer: some View {
        Color.clear.frame(height: Theme.Spacing.xs)
    }

    private func gapOrDivider(nextIncludedStartIndex: Int) -> some View {
        let isDivider = stepBreakIndices.contains(nextIncludedStartIndex)
        let stepNum = stepNumber(forIncludedStartIndex: nextIncludedStartIndex)

        return Group {
            if isDivider {
                stepDividerRow(stepNumber: stepNum, includedStartIndex: nextIncludedStartIndex)
            } else {
                tappableGap(onTap: { stepBreakIndices.insert(nextIncludedStartIndex); ensureStepTitle(stepNum) })
            }
        }
    }

    private func stepDividerRow(stepNumber: Int, includedStartIndex: Int) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "scissors")
                .font(.system(size: 14))
                .foregroundStyle(Theme.softCoral)
            TextField("Step \(stepNumber) title", text: Binding(
                get: { stepTitles[stepNumber] ?? "Step \(stepNumber)" },
                set: { stepTitles[stepNumber] = $0 }
            ))
            .font(Theme.Typography.body)
            .foregroundStyle(Theme.deepPlum)
            Button {
                stepBreakIndices.remove(includedStartIndex)
                stepTitles.removeValue(forKey: stepNumber)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.deepPlum.opacity(0.4))
            }
            .buttonStyle(.plain)
        }
        .padding(Theme.Spacing.md)
        .background(Theme.softCoral.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
        .padding(.vertical, Theme.Spacing.xs)
    }

    private func tappableGap(onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 14))
                Text("Add step break")
                    .font(Theme.Typography.caption)
            }
            .foregroundStyle(Theme.softCoral.opacity(0.8))
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.sm)
        }
        .buttonStyle(.plain)
    }

    private var bottomBar: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Text("Tap − on a block to exclude it from steps (e.g. tips, anecdotes).")
                .font(Theme.Typography.caption2)
                .foregroundStyle(Theme.deepPlum.opacity(0.6))
                .multilineTextAlignment(.center)
            Button {
                progressStore.clearCustomStepLayout(patternId: pattern.id)
                isPresented = false
            } label: {
                Text("Reset to auto")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.deepPlum.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, Theme.Spacing.md)
        .frame(maxWidth: .infinity)
        .background(Theme.cardBackground.opacity(0.95))
    }

    private func stepNumber(forIncludedStartIndex includedStart: Int) -> Int {
        let starts = sortedStarts
        guard let idx = starts.firstIndex(of: includedStart) else { return 1 }
        return idx + 1
    }

    private func ensureStepTitle(_ stepNum: Int) {
        if stepTitles[stepNum] == nil {
            stepTitles[stepNum] = "Step \(stepNum)"
        }
    }

    private func prefillFromContentOrLayout() {
        let contentForSteps = PatternStepParser.truncateAtEndOfPattern(pattern.sourceContent) ?? pattern.sourceContent ?? ""
        let content = contentForSteps
        let allBlocks = ContentBlockParser.parse(content)
        blocks = allBlocks.filter { $0.kind != .paragraphBreak }

        let hash = contentHashForStepLayout(contentForSteps)
        // Priority 1: Existing custom layout
        if let layout = progressStore.customStepLayout(for: pattern.id), layout.contentHash == hash {
            stepBreakIndices = Set(layout.stepStartIndices.dropFirst())
            stepTitles = (1...layout.stepTitles.count).enumerated().reduce(into: [Int: String]()) { $0[$1.offset + 1] = layout.stepTitles[$1.offset] }
            excludedBlockIndices = Set(layout.excludedBlockIndices)
            return
        }

        excludedBlockIndices = []

        // Priority 2a: v2 AI-parsed instructions → approximate block indices
        if let aiInstructions = pattern.decodedParsedInstructions, aiInstructions.count > 1, !blocks.isEmpty {
            let patternSteps = aiInstructions.map { $0.toPatternStep() }
            stepBreakIndices = Set((1..<patternSteps.count).map { (blocks.count * $0) / patternSteps.count })
            stepTitles = (1...patternSteps.count).enumerated().reduce(into: [Int: String]()) { $0[$1.offset + 1] = patternSteps[$1.offset].title }
            return
        }

        // Priority 2b: v1 AI-parsed steps → approximate block indices
        if let aiSteps = pattern.decodedParsedSteps, aiSteps.count > 1, !blocks.isEmpty {
            stepBreakIndices = Set((1..<aiSteps.count).map { (blocks.count * $0) / aiSteps.count })
            stepTitles = (1...aiSteps.count).enumerated().reduce(into: [Int: String]()) { $0[$1.offset + 1] = aiSteps[$1.offset].title }
            return
        }

        // Priority 3: Heuristic parser
        let steps = PatternStepParser.parseSteps(sourceContent: contentForSteps, patternDescription: pattern.patternDescription)
        if steps.count <= 1 || blocks.isEmpty {
            stepBreakIndices = []
            stepTitles = [1: "Step 1"]
        } else {
            stepBreakIndices = Set((1..<steps.count).map { (blocks.count * $0) / steps.count })
            stepTitles = (1...steps.count).enumerated().reduce(into: [Int: String]()) { $0[$1.offset + 1] = steps[$1.offset].title }
        }
    }

    private func saveAndDismiss() {
        let starts = sortedStarts
        let titles = (1...starts.count).map { stepTitles[$0] ?? "Step \($0)" }
        let contentForSteps = PatternStepParser.truncateAtEndOfPattern(pattern.sourceContent) ?? pattern.sourceContent
        let hash = contentHashForStepLayout(contentForSteps)
        let layout = CustomStepLayout(
            stepStartIndices: starts,
            stepTitles: titles,
            contentHash: hash,
            excludedBlockIndices: Array(excludedBlockIndices).sorted()
        )
        progressStore.setCustomStepLayout(patternId: pattern.id, layout: layout)
        isPresented = false
    }
}
