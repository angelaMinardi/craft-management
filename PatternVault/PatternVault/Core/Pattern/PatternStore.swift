//
//  PatternStore.swift
//  PatternVault
//

import Foundation
import UIKit
import UserNotifications

@MainActor
final class PatternStore: ObservableObject {

    /// Don't show task or request cancellation as an error to the user.
    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        if error.localizedDescription.lowercased().contains("cancelled") { return true }
        return false
    }

    private enum ErrorContext { case load, save, other }

    /// User-friendly error message instead of raw server/API text.
    private static func userFacingMessage(for error: Error, context: ErrorContext) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return "We couldn't load your patterns. Check your connection and try again."
            case .timedOut:
                return "The request timed out. Check your connection and try again."
            default:
                break
            }
        }
        switch context {
        case .load:
            return "We couldn't load your patterns. Check your connection and try again."
        case .save:
            return "We couldn't save the pattern. Please try again."
        case .other:
            return "Something went wrong. Please try again."
        }
    }

    @Published var patterns: [Pattern] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let repo = PatternRepository()
    @Published private(set) var chartExtractionInFlight: Set<UUID> = []
    /// Pattern IDs where automatic chart extraction failed (for UI feedback).
    @Published private(set) var chartExtractionFailed: Set<UUID> = []

    var wantToMakeCount: Int { patterns.filter { $0.status == .wantToMake }.count }
    var inProgressCount: Int { patterns.filter { $0.status == .inProgress }.count }
    var completedCount: Int { patterns.filter { $0.status == .completed }.count }

    private var enrichmentPollingTask: Task<Void, Never>?

    func load(userId: UUID) async {
        if let cached = PatternListCacheService.loadCachedPatterns(userId: userId) {
            patterns = cached
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let fetched = try await repo.fetchPatterns(userId: userId)
            patterns = fetched
            PatternListCacheService.saveCachedPatterns(userId: userId, patterns: fetched)
        } catch {
            if Self.isCancellation(error) { return }
            errorMessage = Self.userFacingMessage(for: error, context: .load)
        }

        triggerPendingEnrichments(userId: userId)
        triggerPendingChartExtractions(userId: userId)
    }

    /// Kicks off enrichment for any patterns still pending/stuck and polls until complete.
    /// Treats "processing" patterns the same as "pending" — the edge function is
    /// idempotent so re-triggering a stuck one is safe.
    private func triggerPendingEnrichments(userId: UUID) {
        let pending = patterns.filter { $0.isEnriching }
        guard !pending.isEmpty else { return }

        enrichmentPollingTask?.cancel()
        enrichmentPollingTask = Task {
            // Stagger initial enrichment requests to avoid flooding the server
            for pattern in pending {
                guard !Task.isCancelled else { return }
                try? await repo.requestEnrichment(patternId: pattern.id)
                if pending.count > 3 { try? await Task.sleep(for: .milliseconds(500)) }
            }

            var remaining = Set(pending.map(\.id))
            for _ in 0..<36 {
                guard !Task.isCancelled else { return }
                try? await Task.sleep(for: .seconds(5))
                // Refresh in batches of 3 to limit concurrent requests
                for batch in stride(from: 0, to: remaining.count, by: 3) {
                    let batchIds = Array(remaining.sorted(by: { $0.uuidString < $1.uuidString }))[batch..<min(batch + 3, remaining.count)]
                    await withTaskGroup(of: Void.self) { group in
                        for id in batchIds {
                            group.addTask { await self.refreshPattern(id: id, userId: userId) }
                        }
                    }
                }
                let stillProcessing = remaining.filter { id in
                    patterns.first(where: { $0.id == id })?.isEnriching == true
                }
                let justCompleted = remaining.subtracting(stillProcessing)
                for id in justCompleted {
                    if let p = patterns.first(where: { $0.id == id }) {
                        sendEnrichmentNotification(for: p)
                        processChartsIfNeeded(pattern: p)
                    }
                }
                remaining = stillProcessing
                if remaining.isEmpty { break }
            }
        }
    }

    private func sendEnrichmentNotification(for pattern: Pattern) {
        let content = UNMutableNotificationContent()
        if pattern.enrichmentFailed {
            content.title = "Pattern processing incomplete"
            content.body = "\"\(pattern.title)\" couldn't be fully analyzed. Open it to retry."
        } else {
            content.title = "Pattern ready!"
            content.body = "\"\(pattern.title)\" has been fully analyzed and is ready to view."
        }
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "enrichment-\(pattern.id.uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Automatic Chart Extraction

    /// Scans all loaded patterns for enriched PDF patterns that have instructions
    /// but no ChartHighlight objects yet, and triggers chart detection for each.
    private func triggerPendingChartExtractions(userId: UUID) {
        let chartStore = ChartHighlightStore.shared

        // Adopt orphaned highlights: when a pattern is re-imported with a new UUID,
        // find existing highlights on disk and reassign them to the current pattern ID.
        let ownedPatternIds = Set(patterns.map(\.id))
        let orphanedHighlights = chartStore.highlights.filter { h in
            h.isAIExtracted && !ownedPatternIds.contains(h.patternId)
        }

        if !orphanedHighlights.isEmpty {
            // Group orphans by chartLabel, keep only one per label
            var bestByLabel: [String: ChartHighlight] = [:]
            for h in orphanedHighlights {
                let key = h.chartLabel ?? "page_\(h.pdfPageIndex ?? 0)"
                if let existing = bestByLabel[key] {
                    chartStore.delete(highlightId: existing.id)
                }
                bestByLabel[key] = h
            }

            // Try to assign to a matching pattern (one that has a PDF and no charts yet)
            for pattern in patterns {
                guard chartStore.aiExtractedHighlights(patternId: pattern.id).isEmpty,
                      pattern.pdfUrl != nil, !(pattern.pdfUrl?.isEmpty ?? true) else { continue }

                for var h in bestByLabel.values {
                    h.patternId = pattern.id
                    chartStore.save(h)
                }
                #if DEBUG
                print("[ChartExtraction] Adopted \(bestByLabel.count) orphaned highlight(s) for \(pattern.title)")
                #endif
                break // Only assign to one pattern
            }

            // Delete any remaining duplicates across ALL patterns
            var seenByPatternAndLabel: Set<String> = []
            for h in chartStore.highlights where h.isAIExtracted {
                let key = "\(h.patternId)_\(h.chartLabel ?? "page_\(h.pdfPageIndex ?? 0)")"
                if seenByPatternAndLabel.contains(key) {
                    chartStore.delete(highlightId: h.id)
                } else {
                    seenByPatternAndLabel.insert(key)
                }
            }
        }

        // After orphan adoption, rebuild which pattern IDs now have charts.
        let patternsWithCharts = Set(chartStore.highlights.filter(\.isAIExtracted).map(\.patternId))

        // Map pdfUrl → patternId for patterns that already have charts.
        // Used to adopt charts to duplicate records (same PDF re-imported → new UUID)
        // rather than re-extracting and potentially producing different insets.
        var pdfUrlToSourcePatternId: [String: UUID] = [:]
        for pattern in patterns where patternsWithCharts.contains(pattern.id) {
            if let url = pattern.pdfUrl, !url.isEmpty {
                pdfUrlToSourcePatternId[url] = pattern.id
            }
        }

        // For patterns that have the same pdfUrl as a pattern with charts but a different UUID
        // (duplicate Supabase records from re-import), adopt the existing charts instead of
        // running a fresh extraction that could produce different insets.
        for pattern in patterns {
            guard chartStore.aiExtractedHighlights(patternId: pattern.id).isEmpty,
                  !patternsWithCharts.contains(pattern.id),
                  let url = pattern.pdfUrl, !url.isEmpty,
                  let sourceId = pdfUrlToSourcePatternId[url],
                  sourceId != pattern.id else { continue }

            let sourceHighlights = chartStore.aiExtractedHighlights(patternId: sourceId)
            guard !sourceHighlights.isEmpty else { continue }
            for h in sourceHighlights {
                guard let pageIndex = h.pdfPageIndex else { continue }
                let copy = ChartHighlight(
                    patternId: pattern.id,
                    makeId: h.makeId,
                    pdfPageIndex: pageIndex,
                    minX: h.minX, minY: h.minY, maxX: h.maxX, maxY: h.maxY,
                    rows: h.rows, columns: h.columns,
                    chartType: h.chartType,
                    isSideways: h.isSideways,
                    isC2C: h.isC2C,
                    rowCounterLink: h.rowCounterLink,
                    columnCounterLink: h.columnCounterLink,
                    rowColorName: h.rowColorName,
                    columnColorName: h.columnColorName,
                    extractedChartPNGData: h.extractedChartPNGData,
                    gridInsetLeft: h.gridInsetLeft,
                    gridInsetTop: h.gridInsetTop,
                    gridInsetRight: h.gridInsetRight,
                    gridInsetBottom: h.gridInsetBottom,
                    chartLabel: h.chartLabel,
                    isAIExtracted: true,
                    isColorwork: h.isColorwork
                )
                chartStore.save(copy)
            }
            #if DEBUG
            print("[ChartExtraction] Copied \(sourceHighlights.count) chart(s) from duplicate source (\(sourceId)) to \(pattern.title) (\(pattern.id))")
            #endif
        }

        let candidates = patterns.filter { pattern in
            !pattern.isEnriching
            && !pattern.enrichmentFailed
            && pattern.pdfUrl != nil && !(pattern.pdfUrl?.isEmpty ?? true)
            && pattern.decodedParsedInstructions?.isEmpty == false
            && chartStore.aiExtractedHighlights(patternId: pattern.id).isEmpty
            && !patternsWithCharts.contains(pattern.id)
            && !chartExtractionFailed.contains(pattern.id)
            && !chartStore.hasNoChartsMarker(patternId: pattern.id)
            && pdfUrlToSourcePatternId[pattern.pdfUrl!] == nil
        }

        guard !candidates.isEmpty else { return }
        #if DEBUG
        print("[ChartExtraction] Found \(candidates.count) pattern(s) needing chart detection")
        #endif
        for pattern in candidates {
            processChartsIfNeeded(pattern: pattern)
        }
    }

    /// Downloads the PDF, renders pages, runs chart-detection AI, and creates ChartHighlight objects.
    private func processChartsIfNeeded(pattern: Pattern) {
        guard !pattern.enrichmentFailed else { return }
        guard let pdfUrlString = pattern.pdfUrl, !pdfUrlString.isEmpty,
              URL(string: pdfUrlString) != nil else { return }
        guard let instructions = pattern.decodedParsedInstructions, !instructions.isEmpty else { return }
        guard AIStepParserService.isAIStepAnalysisAvailable else { return }
        guard !chartExtractionInFlight.contains(pattern.id) else { return }
        chartExtractionInFlight.insert(pattern.id)

        let patternId = pattern.id
        let sectionNames = Array(Set(instructions.map(\.section))).sorted()

        Task(priority: .utility) { [weak self] in
            guard let self else { return }
            defer { self.chartExtractionInFlight.remove(patternId) }
            #if DEBUG
            print("[ChartExtraction] Starting automatic chart detection for: \(pattern.title)")
            #endif

            guard let pdfURL = URL(string: pdfUrlString) else {
                self.chartExtractionFailed.insert(patternId)
                return
            }
            guard let (pdfData, response) = try? await URLSession.shared.data(from: pdfURL),
                  let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                self.chartExtractionFailed.insert(patternId)
                return
            }

            let pages = PDFPageRenderer.renderPages(from: pdfData, maxPages: 10, scale: 2.0, jpegQuality: 0.7)
            let images = pages.map(\.imageData)
            guard !images.isEmpty else {
                self.chartExtractionFailed.insert(patternId)
                return
            }

            do {
                let detected = try await AIStepParserService.detectCharts(
                    sectionNames: sectionNames,
                    images: images
                )
                #if DEBUG
                print("[ChartExtraction] Detected \(detected.count) chart(s)")
                #endif
                guard !detected.isEmpty else {
                    // Mark as "attempted but no charts found" so we don't re-scan every launch
                    self.chartExtractionFailed.insert(patternId)
                    ChartHighlightStore.shared.setNoChartsMarker(patternId: patternId)
                    return
                }

                await Self.createChartHighlights(
                    from: detected,
                    images: images,
                    pdfData: pdfData,
                    patternId: patternId
                )
            } catch {
                #if DEBUG
                print("[ChartExtraction] Error: \(error.localizedDescription)")
                #endif
                self.chartExtractionFailed.insert(patternId)
            }
        }
    }

    /// Standalone chart extraction: downloads PDF, detects charts via AI, creates ChartHighlight objects.
    /// Does NOT require parsed instructions — works with any pattern that has a PDF URL.
    func extractChartsFromPDF(patternId: UUID) {
        guard let pattern = patterns.first(where: { $0.id == patternId }),
              let pdfUrlString = pattern.pdfUrl, !pdfUrlString.isEmpty,
              let pdfURL = URL(string: pdfUrlString) else { return }
        guard AIStepParserService.isAIStepAnalysisAvailable else { return }
        guard !chartExtractionInFlight.contains(patternId) else { return }
        chartExtractionInFlight.insert(patternId)
        chartExtractionFailed.remove(patternId)
        ChartHighlightStore.shared.clearNoChartsMarker(patternId: patternId)

        let sectionNames: [String]
        if let instructions = pattern.decodedParsedInstructions, !instructions.isEmpty {
            sectionNames = Array(Set(instructions.map(\.section))).sorted()
        } else {
            sectionNames = []
        }

        Task(priority: .utility) { [weak self] in
            guard let self else { return }
            defer { self.chartExtractionInFlight.remove(patternId) }
            #if DEBUG
            print("[ChartExtraction] Standalone chart detection for: \(pattern.title)")
            #endif

            guard let (pdfData, response) = try? await URLSession.shared.data(from: pdfURL),
                  let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                self.chartExtractionFailed.insert(patternId)
                return
            }

            let pages = PDFPageRenderer.renderPages(from: pdfData, maxPages: 10, scale: 2.0, jpegQuality: 0.7)
            let images = pages.map(\.imageData)
            guard !images.isEmpty else {
                self.chartExtractionFailed.insert(patternId)
                return
            }

            do {
                let detected = try await AIStepParserService.detectCharts(
                    sectionNames: sectionNames,
                    images: images
                )
                #if DEBUG
                print("[ChartExtraction] Standalone detected \(detected.count) chart(s)")
                #endif
                guard !detected.isEmpty else { return }

                await Self.createChartHighlights(
                    from: detected,
                    images: images,
                    pdfData: pdfData,
                    patternId: patternId
                )
            } catch {
                #if DEBUG
                print("[ChartExtraction] Standalone error: \(error.localizedDescription)")
                #endif
                self.chartExtractionFailed.insert(patternId)
            }
        }
    }

    /// Creates ChartHighlight objects from AI-detected chart metadata and saves them to ChartHighlightStore.
    /// When `pdfData` is provided, re-renders chart pages at high quality (3x PNG) for crisp images.
    /// Falls back to the AI-detection JPEG images when PDF re-rendering is unavailable.
    /// Crops each page image to `chart_crop` (the generous bounding box including labels/legend),
    /// then derives per-side grid insets from `grid_boundary` so the overlay knows where the actual
    /// grid cells live within the image. Falls back to an asymmetric heuristic when `grid_boundary`
    /// is missing (labels are typically on the right for row numbers and bottom for column numbers).
    @MainActor
    static func createChartHighlights(
        from detectedCharts: [AIStepParserService.DetectedChart],
        images: [Data],
        pdfData: Data? = nil,
        patternId: UUID
    ) async {
        let store = ChartHighlightStore.shared
        store.deleteAIExtracted(patternId: patternId)

        // Position-aware heuristic for grid insets when AI grid_boundary is missing or invalid.
        // Uses max(fixed minimum, proportional estimate) — fixed minimums prevent large charts
        // from underestimating label space, while proportional estimates handle small charts
        // where labels are proportionally larger relative to the grid.
        func heuristicInsets(
            rows: Int, cols: Int, chart: AIStepParserService.DetectedChart
        ) -> (left: Double, top: Double, right: Double, bottom: Double) {
            // Proportional estimates (scale with cell count — better for small charts)
            let propH = min(0.18, max(0.04, 1.8 / Double(cols + 2)))
            let propV = min(0.18, max(0.04, 1.8 / Double(rows + 2)))

            // Fixed minimums (label space is physical, not proportional — better for large charts)
            let minLabelH: Double = 0.05
            let minLabelV: Double = 0.04
            let minTitle: Double = 0.05

            // Use the larger of fixed minimum or proportional estimate
            let labelH = max(minLabelH, propH)
            let labelV = max(minLabelV, propV * 0.6)
            let titleV = max(minTitle, propV * 0.5)

            let leftInset: Double
            let rightInset: Double
            switch chart.rowNumberPosition {
            case "both":  leftInset = labelH * 0.5; rightInset = labelH * 0.5
            case "left":  leftInset = labelH; rightInset = 0
            case "right": leftInset = 0; rightInset = labelH
            default:      leftInset = labelH * 0.3; rightInset = labelH * 0.3
            }

            let topInset: Double
            let bottomInset: Double
            switch chart.colNumberPosition {
            case "both":  topInset = labelV + titleV; bottomInset = labelV
            case "top":   topInset = labelV + titleV; bottomInset = 0
            case "bottom": topInset = titleV; bottomInset = labelV
            default:      topInset = titleV + labelV * 0.5; bottomInset = labelV * 0.5
            }

            var adjRight = rightInset
            var adjBottom = bottomInset
            if chart.hasLegend {
                switch chart.legendPosition {
                case "right":  adjRight = min(0.40, rightInset + 0.20)
                case "bottom": adjBottom = min(0.40, bottomInset + 0.15)
                default:       adjRight = min(0.40, rightInset + 0.15)
                }
            }

            return (left: leftInset, top: topInset, right: adjRight, bottom: adjBottom)
        }

        // Cache high-quality page renders to avoid re-rendering the same page
        var highQualityPages: [Int: Data] = [:]

        var created = 0
        for chart in detectedCharts {
            guard chart.chartImageIndex >= 0, chart.chartImageIndex < images.count else { continue }

            // Prefer high-quality PNG rendering from PDF, fall back to AI-detection JPEG
            let pageImageData: Data
            if let pdfData {
                if let cached = highQualityPages[chart.chartImageIndex] {
                    pageImageData = cached
                } else if let hqData = PDFPageRenderer.renderPageHighQuality(
                    from: pdfData, pageIndex: chart.chartImageIndex, scale: 3.0
                ) {
                    highQualityPages[chart.chartImageIndex] = hqData
                    pageImageData = hqData
                } else {
                    pageImageData = images[chart.chartImageIndex]
                }
            } else {
                pageImageData = images[chart.chartImageIndex]
            }

            // Always crop to chart_crop (full chart region including labels).
            // Grid insets below tell the overlay where the actual grid cells are.
            let cropRegion = chart.chartCrop
            let chartImageData: Data
            if ChartImageProcessor.isCropFullImage(cropRegion) {
                chartImageData = pageImageData
            } else if let cropped = ChartImageProcessor.cropImageExact(data: pageImageData, rect: cropRegion) {
                chartImageData = cropped
            } else {
                chartImageData = pageImageData
            }

            let hintRows = max(1, chart.chartRows)
            let hintCols = max(1, chart.chartColumns)
            var rows = hintRows
            var cols = hintCols

            // Derive per-side insets using a priority chain:
            // 1. Deterministic lattice solver (measured confidence; no network,
            //    same image always produces the same grid) seeded by the
            //    first-pass grid_boundary when available
            // 2. Lattice solver re-run with the AI second-pass boundary as prior
            // 3. Raw AI second-pass boundary
            // 4. First-pass AI grid_boundary (if valid)
            // 5. Formula heuristic (last resort)
            let rawInsets: (left: Double, top: Double, right: Double, bottom: Double)
            var solution: ChartGridSolver.Solution?
            var aiBoundary: ChartGridDetector.DetectedBoundary?

            if let chartImage = UIImage(data: chartImageData) {
                var prior: ChartGridSolver.PriorRegion?
                if let gb = chart.gridBoundary,
                   AIStepParserService.isGridBoundaryValid(chartCrop: chart.chartCrop, gridBoundary: gb) {
                    let i = AIStepParserService.computeGridInsets(chartCrop: chart.chartCrop, gridBoundary: gb)
                    prior = ChartGridSolver.PriorRegion(
                        xMin: i.left, yMin: i.top, xMax: 1 - i.right, yMax: 1 - i.bottom
                    )
                }
                let firstPrior = prior
                solution = await Task.detached(priority: .utility) {
                    ChartGridSolver.solve(
                        image: chartImage, expectedRows: hintRows, expectedColumns: hintCols, prior: firstPrior
                    )
                }.value

                // Below the confidence gate: fetch a fresh semantic prior from the
                // AI second pass and give the solver one retry with it.
                if (solution?.confidence ?? 0) < 0.7 {
                    aiBoundary = await ChartGridDetector.detectGridBoundary(
                        image: chartImage, expectedRows: hintRows, expectedCols: hintCols
                    )
                    if let detected = aiBoundary,
                       let aiPrior = ChartGridSolver.PriorRegion(
                           xMin: detected.left, yMin: detected.top,
                           xMax: 1 - detected.right, yMax: 1 - detected.bottom
                       ) {
                        let retry = await Task.detached(priority: .utility) {
                            ChartGridSolver.solve(
                                image: chartImage, expectedRows: hintRows, expectedColumns: hintCols, prior: aiPrior
                            )
                        }.value
                        if (retry?.confidence ?? 0) > (solution?.confidence ?? 0) {
                            solution = retry
                        }
                    }
                }
            }

            if let solved = solution, solved.confidence >= 0.7 {
                rawInsets = (solved.insetLeft, solved.insetTop, solved.insetRight, solved.insetBottom)
                rows = solved.rows
                cols = solved.columns
                #if DEBUG
                print("[ChartExtraction] \(chart.chartLabel): using lattice solver (confidence: \(String(format:"%.2f",solved.confidence)))")
                #endif
            } else if let detected = aiBoundary, detected.confidence > 0.3 {
                rawInsets = (detected.left, detected.top, detected.right, detected.bottom)
                #if DEBUG
                print("[ChartExtraction] \(chart.chartLabel): using AI second-pass detection (solver unconfident)")
                #endif
            } else if let gb = chart.gridBoundary,
                      AIStepParserService.isGridBoundaryValid(chartCrop: chart.chartCrop, gridBoundary: gb) {
                rawInsets = AIStepParserService.computeGridInsets(
                    chartCrop: chart.chartCrop,
                    gridBoundary: gb
                )
                #if DEBUG
                print("[ChartExtraction] \(chart.chartLabel): using first-pass AI grid_boundary (second-pass failed)")
                #endif
            } else {
                rawInsets = heuristicInsets(rows: rows, cols: cols, chart: chart)
                #if DEBUG
                print("[ChartExtraction] \(chart.chartLabel): using formula heuristic fallback")
                #endif
            }

            // Sanity check: if insets consume >90% of either axis, use heuristic instead.
            let insets: (left: Double, top: Double, right: Double, bottom: Double)
            if rawInsets.left + rawInsets.right > 0.9 || rawInsets.top + rawInsets.bottom > 0.9 {
                insets = heuristicInsets(rows: rows, cols: cols, chart: chart)
            } else {
                insets = rawInsets
            }

            #if DEBUG
            let gbDesc: String
            if let gb = chart.gridBoundary {
                gbDesc = "(x:\(String(format:"%.3f",gb.x)), y:\(String(format:"%.3f",gb.y)), w:\(String(format:"%.3f",gb.w)), h:\(String(format:"%.3f",gb.h)))"
            } else {
                gbDesc = "nil"
            }
            let sanityClamped = (rawInsets.left != insets.left || rawInsets.top != insets.top
                || rawInsets.right != insets.right || rawInsets.bottom != insets.bottom)
            print("""
            [ChartExtraction] "\(chart.chartLabel)":
              chart_crop = (x:\(String(format:"%.3f",chart.chartCrop.x)), y:\(String(format:"%.3f",chart.chartCrop.y)), w:\(String(format:"%.3f",chart.chartCrop.w)), h:\(String(format:"%.3f",chart.chartCrop.h)))
              grid_boundary = \(gbDesc)
              rows=\(rows), cols=\(cols)
              rawInsets = (L:\(String(format:"%.3f",rawInsets.left)), T:\(String(format:"%.3f",rawInsets.top)), R:\(String(format:"%.3f",rawInsets.right)), B:\(String(format:"%.3f",rawInsets.bottom)))
              finalInsets = (L:\(String(format:"%.3f",insets.left)), T:\(String(format:"%.3f",insets.top)), R:\(String(format:"%.3f",insets.right)), B:\(String(format:"%.3f",insets.bottom)))
              sanityClamped = \(sanityClamped)
            """)
            #endif

            let highlight = ChartHighlight(
                patternId: patternId,
                makeId: nil,
                pdfPageIndex: chart.chartImageIndex,
                minX: 0,
                minY: 0,
                maxX: 1,
                maxY: 1,
                rows: rows,
                columns: cols,
                chartType: .workedFlat,
                isSideways: false,
                isC2C: false,
                rowCounterLink: .global,
                columnCounterLink: .global,
                extractedChartPNGData: chartImageData,
                gridInsetLeft: insets.left,
                gridInsetTop: insets.top,
                gridInsetRight: insets.right,
                gridInsetBottom: insets.bottom,
                chartLabel: chart.chartLabel,
                isAIExtracted: true,
                isColorwork: (solution?.confidence ?? 0) >= 0.7 && solution?.colorwork != nil
            )
            store.save(highlight)
            // Persist per-cell colors so knitting mode offers the clean colorwork
            // grid immediately — no manual "Extract Colors" step needed.
            if let solved = solution, solved.confidence >= 0.7, let colorwork = solved.colorwork {
                store.saveColorworkGrid(colorwork, for: highlight.id)
            }
            created += 1
        }
        #if DEBUG
        print("[ChartExtraction] Created \(created) ChartHighlight(s) for pattern \(patternId)")
        #endif
    }

    /// Adds a pattern (persists pdf_url via repo). UI shows "Download Pattern" / "View PDF" and wand when pattern.pdfUrl != nil.
    func add(userId: UUID, title: String, description: String?, sourceUrl: String, status: PatternStatus, thumbnailUrl: String? = nil, difficulty: String? = nil, materials: String? = nil, craftType: String? = nil, sourceContent: String? = nil, pdfUrl: String? = nil, videoUrl: String? = nil, gauge: String? = nil, needleHookSizes: String? = nil, yarnWeightYardage: String? = nil, techniques: String? = nil, enrichmentStatus: String? = nil) async -> Bool {
        errorMessage = nil
        if !SubscriptionStore.shared.canAddPattern(currentPatternCount: patterns.count) {
            errorMessage = "Pattern limit reached. Upgrade to Premium for unlimited patterns."
            return false
        }
        let platform = SourcePlatformHelper.platform(for: sourceUrl)
        do {
            let pattern = try await repo.addPattern(
                userId: userId,
                title: title,
                description: description,
                sourceUrl: sourceUrl,
                sourcePlatform: platform,
                status: status,
                thumbnailUrl: thumbnailUrl,
                difficulty: difficulty,
                materials: materials,
                craftType: craftType,
                sourceContent: sourceContent,
                pdfUrl: pdfUrl,
                videoUrl: videoUrl,
                gauge: gauge,
                needleHookSizes: needleHookSizes,
                yarnWeightYardage: yarnWeightYardage,
                techniques: techniques,
                enrichmentStatus: enrichmentStatus
            )
            patterns.insert(pattern, at: 0)
            return true
        } catch {
            if !Self.isCancellation(error) { errorMessage = Self.userFacingMessage(for: error, context: .save) }
            return false
        }
    }

    func updateStatus(pattern: Pattern, userId: UUID, status: PatternStatus) async {
        errorMessage = nil
        do {
            let updated = try await repo.updateStatus(patternId: pattern.id, userId: userId, status: status)
            if let idx = patterns.firstIndex(where: { $0.id == pattern.id }) {
                patterns[idx] = updated
            }
        } catch {
            if !Self.isCancellation(error) { errorMessage = Self.userFacingMessage(for: error, context: .other) }
        }
    }

    func update(pattern: Pattern, userId: UUID, title: String, description: String?) async {
        errorMessage = nil
        do {
            let updated = try await repo.updatePattern(
                id: pattern.id, userId: userId,
                title: title, description: description, status: nil
            )
            if let idx = patterns.firstIndex(where: { $0.id == pattern.id }) {
                patterns[idx] = updated
            }
        } catch {
            if !Self.isCancellation(error) { errorMessage = Self.userFacingMessage(for: error, context: .other) }
        }
    }

    func updateSourceContent(pattern: Pattern, userId: UUID, newContent: String) async {
        errorMessage = nil
        do {
            let updated = try await repo.updatePattern(
                id: pattern.id, userId: userId,
                title: nil, description: nil, status: nil,
                sourceContent: newContent
            )
            if let idx = patterns.firstIndex(where: { $0.id == pattern.id }) {
                patterns[idx] = updated
            }
        } catch {
            if !Self.isCancellation(error) { errorMessage = Self.userFacingMessage(for: error, context: .other) }
        }
    }

    func delete(pattern: Pattern, userId: UUID) async {
        errorMessage = nil
        do {
            try await repo.deletePattern(id: pattern.id, userId: userId)
            patterns.removeAll { $0.id == pattern.id }

            // Clean up local chart state and cached PDFs for this pattern.
            ChartHighlightStore.shared.deleteAll(patternId: pattern.id)
            PDFCacheService.removeAllCachedPDFs(for: pattern.id)
        } catch {
            if !Self.isCancellation(error) { errorMessage = Self.userFacingMessage(for: error, context: .other) }
        }
    }

    /// Deletes multiple patterns. Updates in-memory list and cache on success.
    func deletePatterns(ids: Set<UUID>, userId: UUID) async {
        guard !ids.isEmpty else { return }
        errorMessage = nil
        do {
            try await repo.deletePatterns(ids: Array(ids), userId: userId)
            patterns.removeAll { ids.contains($0.id) }
            let chartStore = ChartHighlightStore.shared
            for id in ids {
                chartStore.deleteAll(patternId: id)
                PDFCacheService.removeAllCachedPDFs(for: id)
            }
            if let _ = PatternListCacheService.loadCachedPatterns(userId: userId) {
                PatternListCacheService.saveCachedPatterns(userId: userId, patterns: patterns)
            }
        } catch {
            if !Self.isCancellation(error) { errorMessage = Self.userFacingMessage(for: error, context: .other) }
        }
    }

    func saveParsedSteps(pattern: Pattern, userId: UUID, steps: [ParsedStep]) async {
        errorMessage = nil
        do {
            let data = try JSONEncoder().encode(steps)
            let json = String(data: data, encoding: .utf8)
            let updated = try await repo.updateParsedSteps(patternId: pattern.id, userId: userId, parsedSteps: json)
            if let idx = patterns.firstIndex(where: { $0.id == pattern.id }) {
                patterns[idx] = updated
            }
        } catch {
            if !Self.isCancellation(error) { errorMessage = Self.userFacingMessage(for: error, context: .other) }
        }
    }

    /// Saves v2 instruction-level parsed data into the parsed_steps column.
    func saveParsedInstructions(pattern: Pattern, userId: UUID, instructions: [ParsedInstruction]) async {
        errorMessage = nil
        do {
            let data = try JSONEncoder().encode(instructions)
            let json = String(data: data, encoding: .utf8)
            let updated = try await repo.updateParsedSteps(patternId: pattern.id, userId: userId, parsedSteps: json)
            if let idx = patterns.firstIndex(where: { $0.id == pattern.id }) {
                patterns[idx] = updated
            }
        } catch {
            if !Self.isCancellation(error) { errorMessage = Self.userFacingMessage(for: error, context: .other) }
        }
    }

    func saveParsedRows(pattern: Pattern, userId: UUID, rows: [ParsedRow]) async {
        errorMessage = nil
        do {
            let data = try JSONEncoder().encode(rows)
            let json = String(data: data, encoding: .utf8)
            let updated = try await repo.updateParsedRows(patternId: pattern.id, userId: userId, parsedRows: json)
            if let idx = patterns.firstIndex(where: { $0.id == pattern.id }) {
                patterns[idx] = updated
            }
        } catch {
            if !Self.isCancellation(error) { errorMessage = Self.userFacingMessage(for: error, context: .other) }
        }
    }

    /// Refreshes a single pattern from the server (e.g. after enrichment completes).
    func refreshPattern(id: UUID, userId: UUID) async {
        do {
            if let updated = try await repo.fetchPattern(id: id, userId: userId) {
                if let idx = patterns.firstIndex(where: { $0.id == id }) {
                    patterns[idx] = updated
                }
            }
        } catch {
            if Self.isCancellation(error) { return }
        }
    }

    /// Re-requests server-side AI enrichment for a failed pattern.
    func retryEnrichment(pattern: Pattern, userId: UUID) async {
        errorMessage = nil
        if let idx = patterns.firstIndex(where: { $0.id == pattern.id }) {
            patterns[idx].enrichmentStatus = "pending"
            patterns[idx].enrichmentError = nil
        }
        do {
            try await repo.requestEnrichment(patternId: pattern.id)
            await refreshPattern(id: pattern.id, userId: userId)
        } catch {
            if !Self.isCancellation(error) {
                errorMessage = "Couldn't start enrichment. Please try again."
                await refreshPattern(id: pattern.id, userId: userId)
            }
        }
    }

    /// Uploads PDF and sets pattern's pdf_url. Call after creating a pattern to attach a PDF.
    func attachPdf(pattern: Pattern, userId: UUID, pdfData: Data) async {
        errorMessage = nil
        do {
            let pdfUrl = try await repo.uploadPdf(pdfData: pdfData, patternId: pattern.id, userId: userId)
            let updated = try await repo.updatePdfUrl(patternId: pattern.id, userId: userId, pdfUrl: pdfUrl)
            if let idx = patterns.firstIndex(where: { $0.id == pattern.id }) {
                patterns[idx] = updated
            }
        } catch {
            if !Self.isCancellation(error) { errorMessage = Self.userFacingMessage(for: error, context: .other) }
        }
    }
}
