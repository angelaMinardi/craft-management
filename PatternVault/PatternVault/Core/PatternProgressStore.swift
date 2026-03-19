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

    func setRows(patternId: UUID, makeId: UUID? = nil, completed: Int, total: Int?) {
        var data = resolve(patternId: patternId, makeId: makeId) ?? PatternProgressData(currentStepIndex: 0, stepCount: nil, rowsCompleted: nil, totalRows: nil, yarnColorName: nil, customStepLayout: nil)
        data.rowsCompleted = completed
        data.totalRows = total
        write(patternId: patternId, makeId: makeId, data)
        saveToDefaults()
        objectWillChange.send()
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
