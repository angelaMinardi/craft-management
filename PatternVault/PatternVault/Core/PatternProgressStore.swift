//
//  PatternProgressStore.swift
//  PatternVault
//
//  Persists per-pattern step progress (current step, optional rows) in UserDefaults.
//  Used by PatternDetailView and the continue card in PatternListView.
//

import Foundation
import WidgetKit

/// Stable hash of source content for invalidating custom step layout when content changes.
func contentHashForStepLayout(_ sourceContent: String?) -> Int {
    guard let s = sourceContent, !s.isEmpty else { return 0 }
    var h = 0
    for byte in s.utf8 { h = 31 &* h &+ Int(byte) }
    return h
}

/// User-defined step boundaries and titles. When set, PatternDetailView uses this instead of auto-parsed steps.
struct CustomStepLayout: Codable, Equatable {
    /// Indices (0-based) into the *included* block list where each step starts. Always starts with 0. E.g. [0, 5, 12] = 3 steps.
    var stepStartIndices: [Int]
    /// Title for each step. Count must match stepStartIndices.count.
    var stepTitles: [String]
    /// Hash of sourceContent used to create this layout. If content changes (cleanup, re-import), layout is invalidated.
    var contentHash: Int
    /// Original block indices (into full blocks array) that the user excluded from steps (e.g. tips, anecdotes).
    var excludedBlockIndices: [Int]

    init(stepStartIndices: [Int], stepTitles: [String], contentHash: Int, excludedBlockIndices: [Int] = []) {
        self.stepStartIndices = stepStartIndices
        self.stepTitles = stepTitles
        self.contentHash = contentHash
        self.excludedBlockIndices = excludedBlockIndices
    }

    enum CodingKeys: String, CodingKey {
        case stepStartIndices, stepTitles, contentHash, excludedBlockIndices
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        stepStartIndices = try c.decode([Int].self, forKey: .stepStartIndices)
        stepTitles = try c.decode([String].self, forKey: .stepTitles)
        contentHash = try c.decode(Int.self, forKey: .contentHash)
        excludedBlockIndices = try c.decodeIfPresent([Int].self, forKey: .excludedBlockIndices) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(stepStartIndices, forKey: .stepStartIndices)
        try c.encode(stepTitles, forKey: .stepTitles)
        try c.encode(contentHash, forKey: .contentHash)
        try c.encode(excludedBlockIndices, forKey: .excludedBlockIndices)
    }
}

struct PatternProgressData: Codable, Equatable {
    var currentStepIndex: Int
    var stepCount: Int?
    var rowsCompleted: Int?
    var totalRows: Int?
    var yarnColorName: String?
    var customStepLayout: CustomStepLayout?

    init(currentStepIndex: Int, stepCount: Int?, rowsCompleted: Int?, totalRows: Int?, yarnColorName: String?, customStepLayout: CustomStepLayout?) {
        self.currentStepIndex = currentStepIndex
        self.stepCount = stepCount
        self.rowsCompleted = rowsCompleted
        self.totalRows = totalRows
        self.yarnColorName = yarnColorName
        self.customStepLayout = customStepLayout
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        currentStepIndex = try c.decode(Int.self, forKey: .currentStepIndex)
        stepCount = try c.decodeIfPresent(Int.self, forKey: .stepCount)
        rowsCompleted = try c.decodeIfPresent(Int.self, forKey: .rowsCompleted)
        totalRows = try c.decodeIfPresent(Int.self, forKey: .totalRows)
        yarnColorName = try c.decodeIfPresent(String.self, forKey: .yarnColorName)
        customStepLayout = try c.decodeIfPresent(CustomStepLayout.self, forKey: .customStepLayout)
    }
}

@MainActor
final class PatternProgressStore: ObservableObject {

    static let shared = PatternProgressStore()

    private let defaultsKey = "pattern_progress"
    /// Key: "patternId" (legacy) or "patternId_default" or "patternId_makeId". Progress is per-pattern or per-make.
    private var cache: [String: PatternProgressData] = [:]
    private static let defaultMakeSuffix = "default"

    private init() {
        loadFromDefaults()
    }

    private func key(patternId: UUID, makeId: UUID?) -> String {
        if let makeId = makeId {
            return "\(patternId.uuidString)_\(makeId.uuidString)"
        }
        return "\(patternId.uuidString)_\(Self.defaultMakeSuffix)"
    }

    /// Resolve progress: prefer key with makeId; fall back to legacy single-UUID key for old installs.
    private func resolve(patternId: UUID, makeId: UUID?) -> PatternProgressData? {
        let k = key(patternId: patternId, makeId: makeId)
        if let v = cache[k] { return v }
        // Legacy: key was patternId.uuidString only (no suffix)
        return cache[patternId.uuidString]
    }

    private func write(patternId: UUID, makeId: UUID?, _ data: PatternProgressData) {
        cache[key(patternId: patternId, makeId: makeId)] = data
    }

    func progress(for patternId: UUID, makeId: UUID? = nil) -> PatternProgressData? {
        resolve(patternId: patternId, makeId: makeId)
    }

    /// Progress as 0...1 for the given pattern (and optional make). Uses step index/count if no row data; otherwise rows completed/total. Returns 0 when no progress stored.
    func progressFraction(for patternId: UUID, makeId: UUID? = nil, stepCount: Int? = nil, rowsCompleted: Int? = nil, totalRows: Int? = nil) -> Double {
        let data = resolve(patternId: patternId, makeId: makeId)
        if let rc = data?.rowsCompleted ?? rowsCompleted, let tr = data?.totalRows ?? totalRows, tr > 0 {
            return min(1, max(0, Double(rc) / Double(tr)))
        }
        guard let data else { return 0 }
        let count = stepCount ?? data.stepCount ?? 1
        let steps = max(1, count)
        let current = data.currentStepIndex
        return min(1, max(0, Double(current + 1) / Double(steps)))
    }

    func customStepLayout(for patternId: UUID) -> CustomStepLayout? {
        // Step layout is shared across makes; use default key.
        resolve(patternId: patternId, makeId: nil)?.customStepLayout
    }

    func setCustomStepLayout(patternId: UUID, layout: CustomStepLayout) {
        var data = resolve(patternId: patternId, makeId: nil) ?? PatternProgressData(currentStepIndex: 0, stepCount: nil, rowsCompleted: nil, totalRows: nil, yarnColorName: nil, customStepLayout: nil)
        data.customStepLayout = layout
        data.currentStepIndex = 0
        data.stepCount = layout.stepStartIndices.count
        write(patternId: patternId, makeId: nil, data)
        saveToDefaults()
        objectWillChange.send()
    }

    func clearCustomStepLayout(patternId: UUID) {
        guard var data = resolve(patternId: patternId, makeId: nil) else { return }
        data.customStepLayout = nil
        data.currentStepIndex = 0
        write(patternId: patternId, makeId: nil, data)
        saveToDefaults()
        objectWillChange.send()
    }

    func setCurrentStep(patternId: UUID, makeId: UUID? = nil, index: Int, stepCount: Int) {
        let stepCount = max(1, stepCount)
        let clamped = min(max(0, index), stepCount - 1)
        var data = resolve(patternId: patternId, makeId: makeId) ?? PatternProgressData(currentStepIndex: 0, stepCount: nil, rowsCompleted: nil, totalRows: nil, yarnColorName: nil, customStepLayout: nil)
        data.currentStepIndex = clamped
        data.stepCount = stepCount
        write(patternId: patternId, makeId: makeId, data)
        saveToDefaults()
        objectWillChange.send()
    }

    func setRows(patternId: UUID, makeId: UUID? = nil, completed: Int, total: Int?, patternTitle: String? = nil) {
        var data = resolve(patternId: patternId, makeId: makeId) ?? PatternProgressData(currentStepIndex: 0, stepCount: nil, rowsCompleted: nil, totalRows: nil, yarnColorName: nil, customStepLayout: nil)
        data.rowsCompleted = completed
        data.totalRows = total
        write(patternId: patternId, makeId: makeId, data)
        saveToDefaults()
        objectWillChange.send()
        // Sync to Row Tracker widget
        WidgetDataService.writeRowTrackerData(
            activePatternId: patternId,
            title: patternTitle,
            currentRow: completed,
            totalRows: total,
            makeId: makeId,
            secondaryTitle: nil,
            secondaryCurrent: nil,
            secondaryResetAfter: nil
        )
    }

    func setYarnColor(patternId: UUID, makeId: UUID? = nil, colorName: String?) {
        var data = resolve(patternId: patternId, makeId: makeId) ?? PatternProgressData(currentStepIndex: 0, stepCount: nil, rowsCompleted: nil, totalRows: nil, yarnColorName: nil, customStepLayout: nil)
        data.yarnColorName = colorName
        write(patternId: patternId, makeId: makeId, data)
        saveToDefaults()
        objectWillChange.send()
    }

    func setProgress(patternId: UUID, makeId: UUID? = nil, currentStepIndex: Int, stepCount: Int? = nil, rowsCompleted: Int? = nil, totalRows: Int? = nil, yarnColorName: String? = nil) {
        var data = resolve(patternId: patternId, makeId: makeId) ?? PatternProgressData(currentStepIndex: 0, stepCount: nil, rowsCompleted: nil, totalRows: nil, yarnColorName: nil, customStepLayout: nil)
        data.currentStepIndex = max(0, currentStepIndex)
        if let sc = stepCount { data.stepCount = sc }
        if let rc = rowsCompleted { data.rowsCompleted = rc }
        if let tr = totalRows { data.totalRows = tr }
        if let yc = yarnColorName { data.yarnColorName = yc }
        write(patternId: patternId, makeId: makeId, data)
        saveToDefaults()
        objectWillChange.send()
    }

    private var defaults: UserDefaults {
        UserDefaults(suiteName: "group.com.patternvault.app") ?? .standard
    }

    private func loadFromDefaults() {
        guard let data = defaults.data(forKey: defaultsKey) else { return }
        // Support legacy [UUID string: Value] and new [composite key: Value]
        if let decoded = try? JSONDecoder().decode([String: PatternProgressData].self, from: data) {
            var migrated: [String: PatternProgressData] = [:]
            for (k, v) in decoded {
                if k.contains("_") {
                    migrated[k] = v
                } else {
                    migrated["\(k)_\(Self.defaultMakeSuffix)"] = v
                }
            }
            cache = migrated
            if migrated.count != decoded.count || decoded.keys.contains(where: { !$0.contains("_") }) {
                saveToDefaults()
            }
        }
    }

    private func saveToDefaults() {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        defaults.set(data, forKey: defaultsKey)
    }
}

private extension Dictionary {
    func compactMapKeys<K: Hashable>(_ transform: (Key) -> K?) -> [K: Value] {
        reduce(into: [K: Value]()) { result, pair in
            if let k = transform(pair.key) { result[k] = pair.value }
        }
    }
    func mapKeys<K: Hashable>(_ transform: (Key) -> K) -> [K: Value] {
        reduce(into: [K: Value]()) { result, pair in
            result[transform(pair.key)] = pair.value
        }
    }
}

@MainActor
final class RowCounterStore: ObservableObject {
    static let shared = RowCounterStore()

    @Published private(set) var states: [String: RowCounterState] = [:]

    private let defaultsKey = "row_counter_states"
    private let defaults: UserDefaults
    private static let defaultMakeSuffix = "default"

    private init() {
        defaults = UserDefaults(suiteName: "group.com.patternvault.app") ?? .standard
        loadFromDefaults()
    }

    private func key(patternId: UUID, makeId: UUID?) -> String {
        if let makeId {
            return "\(patternId.uuidString)_\(makeId.uuidString)"
        }
        return "\(patternId.uuidString)_\(Self.defaultMakeSuffix)"
    }

    func state(for patternId: UUID, makeId: UUID?) -> RowCounterState {
        states[key(patternId: patternId, makeId: makeId)] ?? RowCounterState()
    }

    func setTotalRows(patternId: UUID, makeId: UUID?, totalRows: Int?) {
        var current = state(for: patternId, makeId: makeId)
        current.totalRows = totalRows
        setState(current, patternId: patternId, makeId: makeId)
    }

    func jumpToRow(patternId: UUID, makeId: UUID?, row: Int, patternTitle: String? = nil) {
        var current = state(for: patternId, makeId: makeId)
        let maxRow = max(current.totalRows ?? row, 1)
        current.globalRow = min(max(1, row), maxRow)
        setState(current, patternId: patternId, makeId: makeId)
        syncProgress(patternId: patternId, makeId: makeId, patternTitle: patternTitle)
    }

    func incrementGlobal(patternId: UUID, makeId: UUID?, patternTitle: String? = nil) {
        var current = state(for: patternId, makeId: makeId)
        let maxRow = max(current.totalRows ?? (current.globalRow + 1), 1)
        current.globalRow = min(maxRow, current.globalRow + 1)
        current.secondaryCounters = current.secondaryCounters.map { counter in
            guard counter.isActive, counter.linkMode != .unlinked else { return counter }
            return Self.advance(counter: counter)
        }
        setState(current, patternId: patternId, makeId: makeId)
        syncProgress(patternId: patternId, makeId: makeId, patternTitle: patternTitle)
    }

    func decrementGlobal(patternId: UUID, makeId: UUID?, patternTitle: String? = nil) {
        var current = state(for: patternId, makeId: makeId)
        current.globalRow = max(1, current.globalRow - 1)
        setState(current, patternId: patternId, makeId: makeId)
        syncProgress(patternId: patternId, makeId: makeId, patternTitle: patternTitle)
    }

    func addSecondaryCounter(
        patternId: UUID,
        makeId: UUID?,
        title: String,
        resetAfter: Int,
        maxResets: Int?,
        linkMode: SecondaryCounter.LinkMode,
        color: String
    ) {
        var current = state(for: patternId, makeId: makeId)
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let counter = SecondaryCounter(
            title: trimmed,
            resetAfter: max(1, resetAfter),
            maxResets: maxResets,
            linkMode: linkMode,
            color: color
        )
        current.secondaryCounters.append(counter)
        setState(current, patternId: patternId, makeId: makeId)
    }

    func removeSecondaryCounter(patternId: UUID, makeId: UUID?, counterId: UUID) {
        var current = state(for: patternId, makeId: makeId)
        current.secondaryCounters.removeAll { $0.id == counterId }
        setState(current, patternId: patternId, makeId: makeId)
    }

    func updateSecondaryCounter(patternId: UUID, makeId: UUID?, counter: SecondaryCounter) {
        var current = state(for: patternId, makeId: makeId)
        guard let idx = current.secondaryCounters.firstIndex(where: { $0.id == counter.id }) else { return }
        current.secondaryCounters[idx] = counter
        setState(current, patternId: patternId, makeId: makeId)
    }

    func incrementSecondary(
        patternId: UUID,
        makeId: UUID?,
        counterId: UUID,
        patternTitle: String? = nil
    ) {
        var current = state(for: patternId, makeId: makeId)
        guard let idx = current.secondaryCounters.firstIndex(where: { $0.id == counterId }) else { return }
        var counter = current.secondaryCounters[idx]
        guard counter.isActive else { return }
        counter = Self.advance(counter: counter)
        current.secondaryCounters[idx] = counter

        if counter.linkMode == .twoWay {
            let maxRow = max(current.totalRows ?? (current.globalRow + 1), 1)
            current.globalRow = min(maxRow, current.globalRow + 1)
        }
        setState(current, patternId: patternId, makeId: makeId)
        syncProgress(patternId: patternId, makeId: makeId, patternTitle: patternTitle)
    }

    private static func advance(counter: SecondaryCounter) -> SecondaryCounter {
        var next = counter
        next.currentCount += 1
        guard next.currentCount >= max(1, next.resetAfter) else { return next }
        next.currentCount = 1
        next.totalResets += 1
        if let maxResets = next.maxResets, next.totalResets >= maxResets {
            next.isActive = false
        }
        return next
    }

    private func syncProgress(patternId: UUID, makeId: UUID?, patternTitle: String?) {
        let current = state(for: patternId, makeId: makeId)
        let primarySecondary = current.secondaryCounters.first(where: { $0.isActive })
        PatternProgressStore.shared.setRows(
            patternId: patternId,
            makeId: makeId,
            completed: current.globalRow,
            total: current.totalRows,
            patternTitle: patternTitle
        )
        WidgetDataService.writeRowTrackerData(
            activePatternId: patternId,
            title: patternTitle,
            currentRow: current.globalRow,
            totalRows: current.totalRows,
            makeId: makeId,
            secondaryTitle: primarySecondary?.title,
            secondaryCurrent: primarySecondary?.currentCount,
            secondaryResetAfter: primarySecondary?.resetAfter
        )
#if canImport(ActivityKit)
        if let title = patternTitle {
            Task { @MainActor in
                await LiveActivityService.updateCounterActivity(
                    patternId: patternId,
                    patternTitle: title,
                    rowCurrent: current.globalRow,
                    rowTotal: current.totalRows,
                    secondaryTitle: primarySecondary?.title,
                    secondaryCurrent: primarySecondary?.currentCount,
                    secondaryResetAfter: primarySecondary?.resetAfter
                )
            }
        }
#endif
        MascotInteractionStore.shared.rewardForRowProgress()
    }

    private func setState(_ state: RowCounterState, patternId: UUID, makeId: UUID?) {
        states[key(patternId: patternId, makeId: makeId)] = state
        saveToDefaults()
        objectWillChange.send()
    }

    private func loadFromDefaults() {
        guard let data = defaults.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([String: RowCounterState].self, from: data) else {
            return
        }
        states = decoded
    }

    private func saveToDefaults() {
        guard let data = try? JSONEncoder().encode(states) else { return }
        defaults.set(data, forKey: defaultsKey)
    }
}
