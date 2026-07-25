//
//  ChartHighlightStore.swift
//  PatternVault
//
//  File-based persistence for ChartHighlight objects.
//  Each highlight is stored as a JSON file with chart image data
//  kept in a separate PNG file to avoid bloating the JSON.
//

import Foundation

@MainActor
final class ChartHighlightStore: ObservableObject {
    static let shared = ChartHighlightStore()

    @Published private(set) var highlights: [ChartHighlight] = []

    private let storageDir: URL
    private let legacyDefaultsKey = "chart_highlights_v1"
    private let legacyDefaults: UserDefaults?

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        storageDir = appSupport.appendingPathComponent("ChartHighlights", isDirectory: true)
        legacyDefaults = UserDefaults(suiteName: "group.com.corvidcraft.app")
        ensureDirectory()
        migrateFromUserDefaultsIfNeeded()
        load()
    }

    // MARK: - Queries

    func highlight(patternId: UUID, makeId: UUID?, imageId: UUID) -> ChartHighlight? {
        highlights.first(where: {
            $0.patternId == patternId &&
            $0.makeId == makeId &&
            $0.imageId == imageId
        })
    }

    func highlight(patternId: UUID, makeId: UUID?, pdfPageIndex: Int) -> ChartHighlight? {
        highlights.first(where: {
            $0.patternId == patternId &&
            $0.makeId == makeId &&
            $0.pdfPageIndex == pdfPageIndex
        })
    }

    func highlightsForPDFPage(patternId: UUID, makeId: UUID?, pdfPageIndex: Int) -> [ChartHighlight] {
        highlights
            .filter {
                $0.patternId == patternId &&
                $0.makeId == makeId &&
                $0.pdfPageIndex == pdfPageIndex
            }
            .sorted { lhs, rhs in
                lhs.id.uuidString < rhs.id.uuidString
            }
    }

    func extractedHighlights(patternId: UUID, makeId: UUID?) -> [ChartHighlight] {
        highlights
            .filter {
                $0.patternId == patternId &&
                $0.makeId == makeId &&
                $0.extractedChartPNGData != nil
            }
            .sorted { lhs, rhs in
                let lhsOrder = lhs.pdfPageIndex ?? Int.max
                let rhsOrder = rhs.pdfPageIndex ?? Int.max
                if lhsOrder != rhsOrder { return lhsOrder < rhsOrder }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    func aiExtractedHighlights(patternId: UUID) -> [ChartHighlight] {
        highlights
            .filter { $0.patternId == patternId && $0.isAIExtracted }
            .sorted { lhs, rhs in
                let lhsOrder = lhs.pdfPageIndex ?? Int.max
                let rhsOrder = rhs.pdfPageIndex ?? Int.max
                if lhsOrder != rhsOrder { return lhsOrder < rhsOrder }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    // MARK: - Mutations

    func save(_ highlight: ChartHighlight) {
        if let idx = highlights.firstIndex(where: { $0.id == highlight.id }) {
            highlights[idx] = highlight
        } else if let idx = highlights.firstIndex(where: { isSameSurface($0, highlight) }) {
            let replacedId = highlights[idx].id
            highlights[idx] = highlight
            if replacedId != highlight.id {
                removeFiles(for: replacedId)
            }
        } else {
            highlights.append(highlight)
        }
        persistHighlight(highlight)
    }

    func delete(patternId: UUID, makeId: UUID?, imageId: UUID) {
        let toRemove = highlights.filter {
            $0.patternId == patternId &&
            $0.makeId == makeId &&
            $0.imageId == imageId
        }
        highlights.removeAll { h in toRemove.contains(where: { $0.id == h.id }) }
        for h in toRemove { removeFiles(for: h.id) }
    }

    func delete(patternId: UUID, makeId: UUID?, pdfPageIndex: Int) {
        let toRemove = highlights.filter {
            $0.patternId == patternId &&
            $0.makeId == makeId &&
            $0.pdfPageIndex == pdfPageIndex
        }
        highlights.removeAll { h in toRemove.contains(where: { $0.id == h.id }) }
        for h in toRemove { removeFiles(for: h.id) }
    }

    func delete(highlightId: UUID) {
        highlights.removeAll { $0.id == highlightId }
        removeFiles(for: highlightId)
    }

    func deleteAIExtracted(patternId: UUID) {
        let toRemove = highlights.filter { $0.patternId == patternId && $0.isAIExtracted }
        highlights.removeAll { h in toRemove.contains(where: { $0.id == h.id }) }
        for h in toRemove { removeFiles(for: h.id) }
    }

    func deleteAll(patternId: UUID) {
        let toRemove = highlights.filter { $0.patternId == patternId }
        highlights.removeAll { h in toRemove.contains(where: { $0.id == h.id }) }
        for h in toRemove { removeFiles(for: h.id) }
    }

    // MARK: - No-Charts Markers

    /// Returns true if chart detection already ran for this pattern and found nothing.
    func hasNoChartsMarker(patternId: UUID) -> Bool {
        FileManager.default.fileExists(atPath: noChartsMarkerURL(patternId).path)
    }

    /// Persists the fact that chart detection found no charts for this pattern.
    func setNoChartsMarker(patternId: UUID) {
        FileManager.default.createFile(atPath: noChartsMarkerURL(patternId).path, contents: nil)
    }

    /// Clears the marker (e.g., when the user triggers re-analysis).
    func clearNoChartsMarker(patternId: UUID) {
        try? FileManager.default.removeItem(at: noChartsMarkerURL(patternId))
    }

    private func noChartsMarkerURL(_ patternId: UUID) -> URL {
        storageDir.appendingPathComponent("\(patternId.uuidString).nocharts")
    }

    // MARK: - File-Based Persistence

    private func ensureDirectory() {
        try? FileManager.default.createDirectory(at: storageDir, withIntermediateDirectories: true)
    }

    private func jsonURL(for id: UUID) -> URL {
        storageDir.appendingPathComponent("\(id.uuidString).json")
    }

    private func imageURL(for id: UUID) -> URL {
        storageDir.appendingPathComponent("\(id.uuidString).png")
    }

    private func drawingURL(for id: UUID) -> URL {
        storageDir.appendingPathComponent("\(id.uuidString).drawing")
    }

    private func colorworkURL(for id: UUID) -> URL {
        storageDir.appendingPathComponent("\(id.uuidString).colorwork")
    }

    private func progressURL(for id: UUID) -> URL {
        storageDir.appendingPathComponent("\(id.uuidString).progress")
    }

    // MARK: - Colorwork Grid I/O

    func loadColorworkGrid(for id: UUID) -> ColorworkGrid? {
        guard let data = try? Data(contentsOf: colorworkURL(for: id)) else { return nil }
        return try? JSONDecoder().decode(ColorworkGrid.self, from: data)
    }

    func saveColorworkGrid(_ grid: ColorworkGrid, for id: UUID) {
        if let data = try? JSONEncoder().encode(grid) {
            try? data.write(to: colorworkURL(for: id))
        }
    }

    // MARK: - Progress State I/O

    func loadProgress(for id: UUID) -> ChartProgressState? {
        guard let data = try? Data(contentsOf: progressURL(for: id)) else { return nil }
        return try? JSONDecoder().decode(ChartProgressState.self, from: data)
    }

    private var progressSaveTimers: [UUID: Timer] = [:]

    func saveProgress(_ state: ChartProgressState, for id: UUID) {
        // Debounce writes to avoid thrashing on rapid row advances
        progressSaveTimers[id]?.invalidate()
        progressSaveTimers[id] = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.progressSaveTimers.removeValue(forKey: id)
                if let data = try? JSONEncoder().encode(state) {
                    try? data.write(to: self.progressURL(for: id))
                }
            }
        }
    }

    /// Immediately persists progress (use on view dismiss).
    func saveProgressImmediately(_ state: ChartProgressState, for id: UUID) {
        progressSaveTimers[id]?.invalidate()
        progressSaveTimers.removeValue(forKey: id)
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: progressURL(for: id))
        }
    }

    private func load() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: storageDir, includingPropertiesForKeys: nil) else { return }
        let jsonFiles = files.filter { $0.pathExtension == "json" }

        var loadedBySurface: [String: (highlight: ChartHighlight, fileURL: URL)] = [:]
        let decoder = JSONDecoder()
        for file in jsonFiles.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let data: Data
            do {
                data = try Data(contentsOf: file)
            } catch {
                NSLog("[ChartHighlightStore] Failed to read \(file.lastPathComponent): \(error)")
                continue
            }
            var highlight: ChartHighlight
            do {
                highlight = try decoder.decode(ChartHighlight.self, from: data)
            } catch {
                NSLog("[ChartHighlightStore] Failed to decode \(file.lastPathComponent): \(error)")
                continue
            }

            // Load image data from separate file if not inline
            if highlight.extractedChartPNGData == nil {
                let imgFile = imageURL(for: highlight.id)
                if let imgData = try? Data(contentsOf: imgFile) {
                    highlight.extractedChartPNGData = imgData
                }
            }

            // Load drawing data from separate file if not inline
            if highlight.annotationDrawingData == nil {
                let drawFile = drawingURL(for: highlight.id)
                if let drawData = try? Data(contentsOf: drawFile) {
                    highlight.annotationDrawingData = drawData
                }
            }

            let surfaceKey = storageSurfaceKey(for: highlight)
            if let existing = loadedBySurface[surfaceKey] {
                removeFiles(for: existing.highlight.id)
                loadedBySurface[surfaceKey] = (highlight, file)
            } else {
                loadedBySurface[surfaceKey] = (highlight, file)
            }
        }
        highlights = loadedBySurface.values
            .map(\.highlight)
            .sorted { lhs, rhs in
                let lhsPage = lhs.pdfPageIndex ?? Int.max
                let rhsPage = rhs.pdfPageIndex ?? Int.max
                if lhsPage != rhsPage { return lhsPage < rhsPage }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    private func persistHighlight(_ highlight: ChartHighlight) {
        // Write image data to separate file, strip from JSON
        var stripped = highlight
        let imageData = stripped.extractedChartPNGData
        stripped.extractedChartPNGData = nil
        let drawingData = stripped.annotationDrawingData
        stripped.annotationDrawingData = nil

        do {
            let json = try JSONEncoder().encode(stripped)
            try json.write(to: jsonURL(for: highlight.id), options: .atomic)
        } catch {
            NSLog("[ChartHighlightStore] Failed to save \(highlight.id): \(error)")
        }
        if let imageData {
            do {
                try imageData.write(to: imageURL(for: highlight.id), options: .atomic)
            } catch {
                NSLog("[ChartHighlightStore] Failed to save image for \(highlight.id): \(error)")
            }
        } else {
            try? FileManager.default.removeItem(at: imageURL(for: highlight.id))
        }
        if let drawingData {
            do {
                try drawingData.write(to: drawingURL(for: highlight.id), options: .atomic)
            } catch {
                NSLog("[ChartHighlightStore] Failed to save drawing for \(highlight.id): \(error)")
            }
        } else {
            try? FileManager.default.removeItem(at: drawingURL(for: highlight.id))
        }
    }

    private func removeFiles(for id: UUID) {
        let fm = FileManager.default
        try? fm.removeItem(at: jsonURL(for: id))
        try? fm.removeItem(at: imageURL(for: id))
        try? fm.removeItem(at: drawingURL(for: id))
        try? fm.removeItem(at: colorworkURL(for: id))
        try? fm.removeItem(at: progressURL(for: id))
    }

    // MARK: - Migration from UserDefaults

    private func migrateFromUserDefaultsIfNeeded() {
        guard let defaults = legacyDefaults,
              let data = defaults.data(forKey: legacyDefaultsKey),
              let decoded = try? JSONDecoder().decode([ChartHighlight].self, from: data),
              !decoded.isEmpty else { return }

        #if DEBUG
        print("[ChartHighlightStore] Migrating \(decoded.count) highlights from UserDefaults to file storage")
        #endif

        for highlight in decoded {
            persistHighlight(highlight)
        }

        // Remove legacy data after successful migration
        defaults.removeObject(forKey: legacyDefaultsKey)
    }

    // MARK: - Helpers

    private func isSameSurface(_ lhs: ChartHighlight, _ rhs: ChartHighlight) -> Bool {
        guard lhs.patternId == rhs.patternId, lhs.makeId == rhs.makeId else { return false }
        if let lhsImage = lhs.imageId, let rhsImage = rhs.imageId {
            return lhsImage == rhsImage
        }
        if let lhsPage = lhs.pdfPageIndex, let rhsPage = rhs.pdfPageIndex {
            if lhsPage != rhsPage { return false }
            if lhs.chartLabel != nil || rhs.chartLabel != nil {
                return lhs.chartLabel == rhs.chartLabel
            }
            return true
        }
        return false
    }

    private func storageSurfaceKey(for highlight: ChartHighlight) -> String {
        if let imageId = highlight.imageId {
            return "\(highlight.patternId.uuidString)|\(highlight.makeId?.uuidString ?? "default")|image|\(imageId.uuidString)"
        }
        if let pageIndex = highlight.pdfPageIndex {
            let label = highlight.chartLabel ?? "page_\(pageIndex)"
            return "\(highlight.patternId.uuidString)|\(highlight.makeId?.uuidString ?? "default")|pdf|\(pageIndex)|\(label)"
        }
        return "\(highlight.patternId.uuidString)|\(highlight.id.uuidString)"
    }
}
