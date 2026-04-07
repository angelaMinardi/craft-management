//
//  ChartHighlightStore.swift
//  PatternVault
//

import Foundation

@MainActor
final class ChartHighlightStore: ObservableObject {
    static let shared = ChartHighlightStore()

    @Published private(set) var highlights: [ChartHighlight] = []

    private let defaultsKey = "chart_highlights_v1"
    private let defaults: UserDefaults

    private init() {
        defaults = UserDefaults(suiteName: "group.com.patternvault.app") ?? .standard
        load()
    }

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

    func save(_ highlight: ChartHighlight) {
        if let idx = highlights.firstIndex(where: { $0.id == highlight.id }) {
            highlights[idx] = highlight
        } else if let idx = highlights.firstIndex(where: { isSameSurface($0, highlight) }) {
            highlights[idx] = highlight
        } else {
            highlights.append(highlight)
        }
        persist()
    }

    func delete(patternId: UUID, makeId: UUID?, imageId: UUID) {
        highlights.removeAll {
            $0.patternId == patternId &&
            $0.makeId == makeId &&
            $0.imageId == imageId
        }
        persist()
    }

    func delete(patternId: UUID, makeId: UUID?, pdfPageIndex: Int) {
        highlights.removeAll {
            $0.patternId == patternId &&
            $0.makeId == makeId &&
            $0.pdfPageIndex == pdfPageIndex
        }
        persist()
    }

    func delete(highlightId: UUID) {
        highlights.removeAll { $0.id == highlightId }
        persist()
    }

    func deleteAIExtracted(patternId: UUID) {
        highlights.removeAll { $0.patternId == patternId && $0.isAIExtracted }
        persist()
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

    private func load() {
        guard let data = defaults.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([ChartHighlight].self, from: data) else {
            return
        }
        highlights = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(highlights) else { return }
        defaults.set(data, forKey: defaultsKey)
    }

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
}
