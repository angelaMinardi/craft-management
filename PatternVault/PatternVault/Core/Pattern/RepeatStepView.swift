//
//  RepeatStepView.swift
//  PatternVault
//
//  Displays an interactive cycling interface when the user reaches a repeat step.
//  Shows the referenced rows, cycle counter, stitch progress, and advance controls.
//

import SwiftUI

struct RepeatStepView: View {
    let repeatInfo: RepeatInfo
    let referencedSteps: [PatternStep]     // the actual steps being cycled through
    let stepLabel: String                   // e.g. "Increase for toe"
    let patternId: UUID
    let makeId: UUID?
    let stepBody: String                   // the original instruction text to display
    let startingStitchesAllSizes: [Int]?  // [28, 32, 36] for multi-size
    let startingStitches: Int?             // fallback single value

    /// Returns starting stitches for the selected size
    private var startingStitchesForSize: Int? {
        if let allSizes = startingStitchesAllSizes, selectedSizeIndex < allSizes.count {
            return allSizes[selectedSizeIndex]
        }
        return startingStitches
    }

    @ObservedObject private var rowCounterStore = RowCounterStore.shared
    @ObservedObject private var progressStore = PatternProgressStore.shared

    @State private var isSetUp = false
    @State private var showCompleteBanner = false
    @State private var selectedSizeIndex: Int = 0

    /// Number of sizes available from the repeat's target stitch counts
    private var sizeCount: Int {
        repeatInfo.targetStitchCounts?.count ?? 1
    }

    /// Whether this repeat has multiple sizes to choose from
    private var hasMultipleSizes: Bool {
        sizeCount > 1
    }

    /// Default size labels based on count (patterns don't store explicit names)
    private var sizeLabels: [String] {
        switch sizeCount {
        case 2: return ["Small", "Large"]
        case 3: return ["Small", "Medium", "Large"]
        case 4: return ["XS", "S", "M", "L"]
        case 5: return ["XS", "S", "M", "L", "XL"]
        case 6: return ["XS", "S", "M", "L", "XL", "XXL"]
        default: return (0..<sizeCount).map { "Size \($0 + 1)" }
        }
    }

    private var activeRepeat: ActiveRepeatState? {
        progressStore.progress(for: patternId, makeId: makeId)?.activeRepeat
    }

    private var cycleCounter: SecondaryCounter? {
        guard let counterId = activeRepeat?.cycleCounterId else { return nil }
        let state = rowCounterStore.state(for: patternId, makeId: makeId)
        return state.secondaryCounters.first { $0.id == counterId }
    }

    private var currentCycleNumber: Int {
        (cycleCounter?.totalResets ?? 0) + 1
    }

    private var totalCycles: Int? {
        activeRepeat?.estimatedTotalCycles
    }

    private var currentCycleRow: Int {
        activeRepeat?.currentCycleRow ?? 0
    }

    /// True when this is a simple "work N rounds" counter (no sub-step cycling)
    private var isSimpleCounter: Bool {
        referencedSteps.isEmpty && repeatInfo.fixedRepeatCount != nil
    }

    private var cycleLength: Int {
        if isSimpleCounter { return 1 }
        return max(1, referencedSteps.count)
    }

    private var isComplete: Bool {
        activeRepeat?.isComplete ?? false
    }

    private var targetStitches: Int? {
        activeRepeat?.targetStitchCount
    }

    private var currentStitchEstimate: Int? {
        activeRepeat?.currentStitchEstimate
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            // Size picker (only shown for multi-size patterns)
            if hasMultipleSizes {
                sizePickerRow
            }

            if isSimpleCounter {
                // Show instruction text + simple round counter
                FormattedStepBodyView(stepBody: stepBody, craftType: nil)
                simpleRoundCounter
            } else {
                // Full cycle view with referenced rows
                cycleHeader
                referencedRowsList
                cycleControls
            }

            if isComplete || showCompleteBanner {
                completeBanner
            }
        }
        .task {
            let key = "repeatSizeIndex_\(patternId.uuidString)"
            selectedSizeIndex = UserDefaults.standard.integer(forKey: key)
            setupRepeatIfNeeded()
        }
        .onAppear {
            // If navigating back to this step, check if the active repeat is stale
            let currentStepIdx = progressStore.progress(for: patternId, makeId: makeId)?.currentStepIndex ?? -1
            if let existing = activeRepeat, existing.repeatStepIndex != currentStepIdx {
                // Stale state from a different step — reset and recreate
                isSetUp = false
                showCompleteBanner = false
                setupRepeatIfNeeded()
            }
        }
    }

    // MARK: - Simple Round Counter

    private var simpleRoundCounter: some View {
        let total = repeatInfo.fixedRepeatCount ?? 1
        // Show progress as fraction: round 1 of 4 = 25%, round 4 of 4 = 100%
        let progressFrac = min(1.0, Double(currentCycleNumber) / Double(total))
        return VStack(spacing: Theme.Spacing.sm) {
            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Theme.deepPlum.opacity(0.1))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Theme.sageGreen)
                        .frame(width: geo.size.width * progressFrac)
                }
            }
            .frame(height: 6)

            HStack(spacing: Theme.Spacing.lg) {
                Spacer()

                Button {
                    goBack()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(currentCycleNumber > 1 ? Theme.deepPlum : Theme.deepPlum.opacity(0.2))
                }
                .disabled(currentCycleNumber <= 1)

                VStack(spacing: 2) {
                    Text("Round \(currentCycleNumber) of \(total)")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.deepPlum)
                        .contentTransition(.numericText())
                }

                Button {
                    advance()
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(!isComplete ? Theme.deepPlum : Theme.deepPlum.opacity(0.2))
                }
                .disabled(isComplete)

                Spacer()
            }

        }
        .padding(Theme.Spacing.sm)
        .background(Theme.sageGreen.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.small))
    }

    // MARK: - Size Picker

    private var sizePickerRow: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "ruler")
                .font(.system(size: 12))
                .foregroundStyle(Theme.deepPlum.opacity(0.5))
            Text("Your size:")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.deepPlum.opacity(0.7))

            Picker("Size", selection: $selectedSizeIndex) {
                ForEach(0..<sizeCount, id: \.self) { i in
                    HStack(spacing: 4) {
                        Text(sizeLabels[i])
                        if let counts = repeatInfo.targetStitchCounts, i < counts.count {
                            Text("(\(counts[i]) sts)")
                                .foregroundStyle(Theme.deepPlum.opacity(0.5))
                        }
                    }
                    .tag(i)
                }
            }
            .pickerStyle(.menu)
            .tint(Theme.dustyBlue)

            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .onChange(of: selectedSizeIndex) { _, newIndex in
            // Persist the choice
            UserDefaults.standard.set(newIndex, forKey: "repeatSizeIndex_\(patternId.uuidString)")
            // Reset the repeat counter with the new size
            rowCounterStore.clearActiveRepeat(patternId: patternId, makeId: makeId)
            isSetUp = false
            showCompleteBanner = false
            setupRepeatIfNeeded()
        }
    }

    // MARK: - Cycle Header

    private var cycleHeader: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.dustyBlue)
                    if let refStart = repeatInfo.referencedStartRow,
                       let refEnd = repeatInfo.referencedEndRow {
                        Text("Repeat Rows \(refStart)–\(refEnd)")
                            .font(Theme.Typography.captionSemibold)
                            .foregroundStyle(Theme.deepPlum)
                    } else {
                        Text("Repeat")
                            .font(Theme.Typography.captionSemibold)
                            .foregroundStyle(Theme.deepPlum)
                    }
                }

                Spacer()

                if let total = totalCycles {
                    Text("Cycle \(currentCycleNumber) of ~\(total)")
                        .font(Theme.Typography.captionSemibold)
                        .foregroundStyle(Theme.dustyBlue)
                } else {
                    Text("Cycle \(currentCycleNumber)")
                        .font(Theme.Typography.captionSemibold)
                        .foregroundStyle(Theme.dustyBlue)
                }
            }

            // Stitch progress bar (if target available)
            if let target = targetStitches {
                HStack(spacing: Theme.Spacing.xs) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Theme.deepPlum.opacity(0.1))
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Theme.dustyBlue)
                                .frame(width: geo.size.width * stitchProgressFraction)
                        }
                    }
                    .frame(height: 6)

                    if let current = currentStitchEstimate {
                        Text("\(current)/\(target) sts")
                            .font(Theme.Typography.caption2)
                            .foregroundStyle(Theme.deepPlum.opacity(0.6))
                    }
                }
            }

            // Cycle progress bar
            if let total = totalCycles, total > 0 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Theme.deepPlum.opacity(0.1))
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Theme.sageGreen)
                            .frame(width: geo.size.width * Double(currentCycleNumber - 1) / Double(total))
                    }
                }
                .frame(height: 4)
            }
        }
        .padding(Theme.Spacing.sm)
        .background(Theme.dustyBlue.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.small))
    }

    // MARK: - Referenced Rows

    private var referencedRowsList: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(referencedSteps.enumerated()), id: \.offset) { idx, step in
                let isCurrent = idx == currentCycleRow && !isComplete
                HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                    if isCurrent {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.honey)
                            .frame(width: 14)
                    } else {
                        Text("")
                            .frame(width: 14)
                    }

                    Text("Row \(idx + 1):")
                        .font(Theme.Typography.captionSemibold)
                        .foregroundStyle(isCurrent ? Theme.deepPlum : Theme.deepPlum.opacity(0.5))
                        .frame(width: 48, alignment: .leading)

                    Text(step.body)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(isCurrent ? Theme.deepPlum : Theme.deepPlum.opacity(0.5))
                        .lineLimit(2)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, Theme.Spacing.xs)
                .background(isCurrent ? Theme.honey.opacity(0.12) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
    }

    // MARK: - Cycle Controls

    private var cycleControls: some View {
        HStack(spacing: Theme.Spacing.lg) {
            Spacer()

            Button {
                goBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(canGoBack ? Theme.deepPlum : Theme.deepPlum.opacity(0.2))
            }
            .disabled(!canGoBack)

            VStack(spacing: 2) {
                Text("Row \(currentCycleRow + 1) of \(cycleLength)")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.deepPlum)
                    .contentTransition(.numericText())
            }

            Button {
                advance()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(!isComplete ? Theme.deepPlum : Theme.deepPlum.opacity(0.2))
            }
            .disabled(isComplete)

            Spacer()
        }
        .padding(.vertical, Theme.Spacing.xs)
    }

    // MARK: - Complete Banner

    private var completeBanner: some View {
        VStack(spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.sageGreen)
                Text("Repeat Complete!")
                    .font(Theme.Typography.bodySemibold)
                    .foregroundStyle(Theme.deepPlum)
            }

            if let target = targetStitches {
                Text("\(target) stitches reached")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.deepPlum.opacity(0.6))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Spacing.md)
        .background(Theme.sageGreen.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.small))
    }

    // MARK: - Helpers

    private var canGoBack: Bool {
        guard let repeat_ = activeRepeat else { return false }
        return repeat_.currentCycleRow > 0 || currentCycleNumber > 1
    }

    private var stitchProgressFraction: Double {
        guard let target = targetStitches, target > 0,
              let current = currentStitchEstimate else { return 0 }
        return min(1, max(0, Double(current) / Double(target)))
    }

    private func setupRepeatIfNeeded() {
        guard !isSetUp else { return }
        isSetUp = true

        let currentStepIdx = progressStore.progress(for: patternId, makeId: makeId)?.currentStepIndex ?? -1
        let expectedRefCount = isSimpleCounter ? 1 : max(1, referencedSteps.count)

        // Enrich repeatInfo with stitchesPerCycle from referenced steps if needed
        var enrichedInfo = repeatInfo
        if enrichedInfo.stitchesPerCycle == nil {
            enrichedInfo = enrichWithStitchesPerCycle(enrichedInfo)
        }

        // Check if the current activeRepeat belongs to THIS step — if so, resume it
        if let existing = activeRepeat,
           existing.repeatStepIndex == currentStepIdx,
           existing.referencedStepIndices.count == expectedRefCount {
            if existing.isComplete { showCompleteBanner = true }
            return
        }

        // Different step or no state — clear and create fresh for this step
        rowCounterStore.clearActiveRepeat(patternId: patternId, makeId: makeId)

        let refIndices = isSimpleCounter ? [0] : Array(0..<max(1, referencedSteps.count))

        rowCounterStore.createRepeatCounter(
            patternId: patternId, makeId: makeId,
            repeatInfo: enrichedInfo, sizeIndex: selectedSizeIndex,
            stepIndex: currentStepIdx, referencedStepIndices: refIndices,
            stepLabel: stepLabel, startingStitches: startingStitchesForSize
        )
    }

    /// Extracts stitchesPerCycle from the referenced step bodies and the repeat step's own body.
    /// Looks for "(N sts inc)", "(N sts increase)", "N sts inc", "N st inc" patterns.
    private func enrichWithStitchesPerCycle(_ info: RepeatInfo) -> RepeatInfo {
        var totalChange = 0

        // Multiple regex patterns to catch different notation styles
        let patterns = [
            #"\((\d+)\s*sts?\s*inc(?:rease)?(?:d)?\)"#,    // (4 sts inc) or (4 sts increased)
            #"(\d+)\s*sts?\s*inc(?:rease)?(?:d)?"#,         // 4 sts inc (without parens)
            #"\((\d+)\s*sts?\s*dec(?:rease)?(?:d)?\)"#,     // (2 sts dec)
            #"(\d+)\s*sts?\s*dec(?:rease)?(?:d)?"#,         // 2 sts dec
        ]
        let isDecrease = [false, false, true, true]

        // Search in referenced steps AND the repeat instruction itself
        var allTexts = referencedSteps.map(\.body)
        allTexts.append(stepBody) // also check the repeat step's own text

        for (patternStr, isDec) in zip(patterns, isDecrease) {
            guard let regex = try? NSRegularExpression(pattern: patternStr, options: .caseInsensitive) else { continue }
            for text in allTexts {
                let range = NSRange(text.startIndex..., in: text)
                if let match = regex.firstMatch(in: text, range: range),
                   let r = Range(match.range(at: 1), in: text),
                   let val = Int(text[r]) {
                    totalChange += isDec ? -val : val
                }
            }
            if totalChange != 0 { break } // Found it, stop looking
        }

        guard totalChange != 0 else { return info }

        return RepeatInfo(
            type: info.type,
            referencedStartRow: info.referencedStartRow,
            referencedEndRow: info.referencedEndRow,
            fixedRepeatCount: info.fixedRepeatCount,
            targetStitchCounts: info.targetStitchCounts,
            targetMeasurement: info.targetMeasurement,
            stitchesPerCycle: totalChange,
            asteriskBody: info.asteriskBody
        )
    }

    private func advance() {
        let result = rowCounterStore.advanceCycleRow(patternId: patternId, makeId: makeId)
        switch result {
        case .nextRow:
            HapticService.lightImpact()
        case .nextCycle:
            HapticService.success()
        case .complete:
            showCompleteBanner = true
            HapticService.success()
        }
    }

    private func goBack() {
        guard var progress = progressStore.progress(for: patternId, makeId: makeId),
              var repeat_ = progress.activeRepeat else { return }

        if repeat_.currentCycleRow > 0 {
            repeat_.currentCycleRow -= 1
        } else if currentCycleNumber > 1 {
            // Go back to previous cycle's last row
            repeat_.currentCycleRow = cycleLength - 1
            // Decrement the secondary counter
            var rowState = rowCounterStore.state(for: patternId, makeId: makeId)
            if let idx = rowState.secondaryCounters.firstIndex(where: { $0.id == repeat_.cycleCounterId }) {
                var counter = rowState.secondaryCounters[idx]
                counter.totalResets = max(0, counter.totalResets - 1)
                counter.currentCount = counter.resetAfter
                counter.isActive = true
                rowState.secondaryCounters[idx] = counter
                rowCounterStore.updateSecondaryCounter(patternId: patternId, makeId: makeId, counter: counter)
            }

            // Update stitch estimate
            if let perCycle = repeatInfo.stitchesPerCycle,
               let current = repeat_.currentStitchEstimate {
                repeat_.currentStitchEstimate = current - perCycle
            }
        }

        repeat_.isComplete = false
        showCompleteBanner = false
        progress.activeRepeat = repeat_
        progressStore.write(patternId: patternId, makeId: makeId, progress)
        progressStore.saveToDefaults()
        progressStore.objectWillChange.send()
        HapticService.lightImpact()
    }
}
