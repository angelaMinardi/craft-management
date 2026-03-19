//
//  WidgetDataService.swift
//  PatternVault
//
//  Writes summary data to App Group for the Home Screen widget and the lock-screen Row Tracker.
//

import Foundation
import WidgetKit

enum WidgetDataService {
    private static let suiteName = "group.com.patternvault.app"

    static let keyContinueTitle = "widgetContinueTitle"
    static let keyContinueProgress = "widgetContinueProgress"
    static let keyInProgressCount = "widgetInProgressCount"
    static let keyCompletedCount = "widgetCompletedCount"
    static let keyTotalCount = "widgetTotalCount"

    // Row Tracker (lock screen)
    static let keyActivePatternId = "widgetActivePatternId"
    static let keyActivePatternTitle = "widgetActivePatternTitle"
    static let keyWidgetRowCurrent = "widgetRowCurrent"
    static let keyWidgetRowTotal = "widgetRowTotal"
    static let keyWidgetActiveMakeId = "widgetActiveMakeId"
    // Pinned "use for widget" choice (optional; when set, widget shows this pattern+make instead of first in progress)
    static let keyWidgetPinnedPatternId = "widgetPinnedPatternId"
    static let keyWidgetPinnedMakeId = "widgetPinnedMakeId"

    /// Call after patterns load or when entering background. Writes continue pattern (first in progress) and counts.
    static func writeWidgetData(
        patterns: [Pattern],
        progressFraction: (UUID) -> Double
    ) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        let inProgress = patterns.filter { $0.status == .inProgress }
        let first = inProgress.first
        defaults.set(first?.title, forKey: keyContinueTitle)
        defaults.set(first.map { progressFraction($0.id) } ?? 0, forKey: keyContinueProgress)
        defaults.set(inProgress.count, forKey: keyInProgressCount)
        defaults.set(patterns.filter { $0.status == .completed }.count, forKey: keyCompletedCount)
        defaults.set(patterns.count, forKey: keyTotalCount)
        defaults.synchronize()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Writes Row Tracker data for the lock-screen widget. Call when row progress changes or when entering background.
    /// Pass the active project (e.g. first in-progress pattern with row data) so the widget shows pattern name and row X / Y.
    /// makeId: when provided, widget and sync-back use this make; otherwise default make.
    static func writeRowTrackerData(activePatternId: UUID?, title: String?, currentRow: Int?, totalRows: Int?, makeId: UUID? = nil) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        defaults.set(activePatternId?.uuidString, forKey: keyActivePatternId)
        defaults.set(title, forKey: keyActivePatternTitle)
        defaults.set(currentRow.map { max(0, $0) }, forKey: keyWidgetRowCurrent)
        defaults.set(totalRows.map { max(0, $0) }, forKey: keyWidgetRowTotal)
        defaults.set(makeId?.uuidString, forKey: keyWidgetActiveMakeId)
        defaults.synchronize()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Reads Row Tracker state (e.g. after widget +/-). Use to sync back into PatternProgressStore when app becomes active.
    static func readRowTrackerData() -> (patternId: UUID?, title: String?, current: Int, total: Int?, makeId: UUID?)? {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return nil }
        let idString = defaults.string(forKey: keyActivePatternId)
        let patternId = idString.flatMap { UUID(uuidString: $0) }
        let title = defaults.string(forKey: keyActivePatternTitle)
        let current = defaults.object(forKey: keyWidgetRowCurrent) as? Int ?? 0
        let total = defaults.object(forKey: keyWidgetRowTotal) as? Int
        let makeIdString = defaults.string(forKey: keyWidgetActiveMakeId)
        let makeId = makeIdString.flatMap { UUID(uuidString: $0) }
        return (patternId, title, max(0, current), total, makeId)
    }

    /// Pins the widget to a specific pattern (and optional make). When set, Row Tracker shows this project instead of "first in progress".
    static func setWidgetPinned(patternId: UUID?, makeId: UUID?) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        defaults.set(patternId?.uuidString, forKey: keyWidgetPinnedPatternId)
        defaults.set(makeId?.uuidString, forKey: keyWidgetPinnedMakeId)
        defaults.synchronize()
    }

    /// Returns the user's pinned "use for Row Tracker" choice, if any.
    static func getWidgetPinned() -> (patternId: UUID?, makeId: UUID?) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return (nil, nil) }
        let pid = defaults.string(forKey: keyWidgetPinnedPatternId).flatMap { UUID(uuidString: $0) }
        let mid = defaults.string(forKey: keyWidgetPinnedMakeId).flatMap { UUID(uuidString: $0) }
        return (pid, mid)
    }
}
