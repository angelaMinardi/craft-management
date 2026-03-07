//
//  PatternProgressStore.swift
//  PatternVault
//
//  Persists per-pattern step progress (current step, optional rows) in UserDefaults.
//  Used by PatternDetailView and the continue card in PatternListView.
//

import Foundation

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
    private var cache: [UUID: PatternProgressData] = [:]

    private init() {
        loadFromDefaults()
    }

    func progress(for patternId: UUID) -> PatternProgressData? {
        cache[patternId]
    }

    /// Progress as 0...1 for the given pattern. Uses step index/count if no row data; otherwise rows completed/total. Returns 0 when no progress stored.
    func progressFraction(for patternId: UUID, stepCount: Int? = nil, rowsCompleted: Int? = nil, totalRows: Int? = nil) -> Double {
        let data = cache[patternId]
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
        cache[patternId]?.customStepLayout
    }

    func setCustomStepLayout(patternId: UUID, layout: CustomStepLayout) {
        var data = cache[patternId] ?? PatternProgressData(currentStepIndex: 0, stepCount: nil, rowsCompleted: nil, totalRows: nil, yarnColorName: nil, customStepLayout: nil)
        data.customStepLayout = layout
        data.currentStepIndex = 0
        data.stepCount = layout.stepStartIndices.count
        cache[patternId] = data
        saveToDefaults()
        objectWillChange.send()
    }

    func clearCustomStepLayout(patternId: UUID) {
        guard var data = cache[patternId] else { return }
        data.customStepLayout = nil
        data.currentStepIndex = 0
        cache[patternId] = data
        saveToDefaults()
        objectWillChange.send()
    }

    func setCurrentStep(patternId: UUID, index: Int, stepCount: Int) {
        let stepCount = max(1, stepCount)
        let clamped = min(max(0, index), stepCount - 1)
        var data = cache[patternId] ?? PatternProgressData(currentStepIndex: 0, stepCount: nil, rowsCompleted: nil, totalRows: nil, yarnColorName: nil, customStepLayout: nil)
        data.currentStepIndex = clamped
        data.stepCount = stepCount
        cache[patternId] = data
        saveToDefaults()
        objectWillChange.send()
    }

    func setRows(patternId: UUID, completed: Int, total: Int?) {
        var data = cache[patternId] ?? PatternProgressData(currentStepIndex: 0, stepCount: nil, rowsCompleted: nil, totalRows: nil, yarnColorName: nil, customStepLayout: nil)
        data.rowsCompleted = completed
        data.totalRows = total
        cache[patternId] = data
        saveToDefaults()
        objectWillChange.send()
    }

    func setYarnColor(patternId: UUID, colorName: String?) {
        var data = cache[patternId] ?? PatternProgressData(currentStepIndex: 0, stepCount: nil, rowsCompleted: nil, totalRows: nil, yarnColorName: nil, customStepLayout: nil)
        data.yarnColorName = colorName
        cache[patternId] = data
        saveToDefaults()
        objectWillChange.send()
    }

    func setProgress(patternId: UUID, currentStepIndex: Int, stepCount: Int? = nil, rowsCompleted: Int? = nil, totalRows: Int? = nil, yarnColorName: String? = nil) {
        var data = cache[patternId] ?? PatternProgressData(currentStepIndex: 0, stepCount: nil, rowsCompleted: nil, totalRows: nil, yarnColorName: nil, customStepLayout: nil)
        data.currentStepIndex = max(0, currentStepIndex)
        if let sc = stepCount { data.stepCount = sc }
        if let rc = rowsCompleted { data.rowsCompleted = rc }
        if let tr = totalRows { data.totalRows = tr }
        if let yc = yarnColorName { data.yarnColorName = yc }
        cache[patternId] = data
        saveToDefaults()
        objectWillChange.send()
    }

    private var defaults: UserDefaults {
        UserDefaults(suiteName: "group.com.patternvault.app") ?? .standard
    }

    private func loadFromDefaults() {
        guard let data = defaults.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([String: PatternProgressData].self, from: data) else {
            return
        }
        cache = decoded.compactMapKeys { UUID(uuidString: $0) }
    }

    private func saveToDefaults() {
        let encoded = cache.mapKeys { $0.uuidString }
        guard let data = try? JSONEncoder().encode(encoded) else { return }
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
