//
//  PatternStore.swift
//  PatternVault
//

import Foundation
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
    private var chartExtractionInFlight: Set<UUID> = []

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
            for pattern in pending {
                try? await repo.requestEnrichment(patternId: pattern.id)
            }

            var remaining = Set(pending.map(\.id))
            for _ in 0..<36 {
                guard !Task.isCancelled else { return }
                try? await Task.sleep(for: .seconds(5))
                for id in remaining {
                    await refreshPattern(id: id, userId: userId)
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
        let candidates = patterns.filter { pattern in
            !pattern.isEnriching
            && !pattern.enrichmentFailed
            && pattern.pdfUrl != nil && !(pattern.pdfUrl?.isEmpty ?? true)
            && pattern.decodedParsedInstructions?.isEmpty == false
            && chartStore.aiExtractedHighlights(patternId: pattern.id).isEmpty
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

        Task.detached(priority: .utility) { [weak self] in
            defer { Task { @MainActor in self?.chartExtractionInFlight.remove(patternId) } }
            #if DEBUG
            print("[ChartExtraction] Starting automatic chart detection for: \(pattern.title)")
            #endif

            guard let pdfURL = URL(string: pdfUrlString) else { return }
            guard let (pdfData, response) = try? await URLSession.shared.data(from: pdfURL),
                  let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return
            }

            let pages = PDFPageRenderer.renderPages(from: pdfData, maxPages: 10, scale: 2.0, jpegQuality: 0.7)
            let images = pages.map(\.imageData)
            guard !images.isEmpty else { return }

            do {
                let detected = try await AIStepParserService.detectCharts(
                    sectionNames: sectionNames,
                    images: images
                )
                #if DEBUG
                print("[ChartExtraction] Detected \(detected.count) chart(s)")
                #endif
                guard !detected.isEmpty else { return }

                await MainActor.run {
                    Self.createChartHighlights(
                        from: detected,
                        images: images,
                        patternId: patternId
                    )
                }
            } catch {
                #if DEBUG
                print("[ChartExtraction] Error: \(error.localizedDescription)")
                #endif
            }
        }
    }

    /// Creates ChartHighlight objects from AI-detected chart metadata and saves them to ChartHighlightStore.
    /// Crops each full page image to the AI-detected grid_boundary so the stored image is tightly
    /// focused on the grid. Heuristic insets compensate for printed row/column numbers that the AI
    /// inevitably includes — approximately one cell's width on each edge. Falls back to chart_crop
    /// if grid_boundary is missing.
    @MainActor
    static func createChartHighlights(
        from detectedCharts: [AIStepParserService.DetectedChart],
        images: [Data],
        patternId: UUID
    ) {
        let store = ChartHighlightStore.shared
        store.deleteAIExtracted(patternId: patternId)

        var created = 0
        for chart in detectedCharts {
            guard chart.chartImageIndex >= 0, chart.chartImageIndex < images.count else { continue }
            let pageImageData = images[chart.chartImageIndex]

            let cropRegion = chart.gridBoundary ?? chart.chartCrop
            let chartImageData: Data
            if ChartImageProcessor.isCropFullImage(cropRegion) {
                chartImageData = pageImageData
            } else if let cropped = ChartImageProcessor.cropImageExact(data: pageImageData, rect: cropRegion) {
                chartImageData = cropped
            } else {
                chartImageData = pageImageData
            }

            let rows = max(1, chart.chartRows)
            let cols = max(1, chart.chartColumns)
            let insets = Self.heuristicLabelInsets(rows: rows, columns: cols)

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
                gridInsetLeft: insets.horizontal,
                gridInsetTop: insets.vertical,
                gridInsetRight: insets.horizontal,
                gridInsetBottom: insets.vertical,
                chartLabel: chart.chartLabel,
                isAIExtracted: true
            )
            store.save(highlight)
            created += 1
        }
        #if DEBUG
        print("[ChartExtraction] Created \(created) ChartHighlight(s) for pattern \(patternId)")
        #endif
    }

    /// Estimates grid insets to skip printed row/column number labels that the AI typically
    /// includes in its grid_boundary. Labels plus spacing occupy roughly 1.5 cells on each edge.
    private static func heuristicLabelInsets(rows: Int, columns: Int) -> (horizontal: Double, vertical: Double) {
        let h = min(0.18, max(0.04, 1.8 / Double(columns + 2)))
        let v = min(0.18, max(0.04, 1.8 / Double(rows + 2)))
        return (h, v)
    }

    /// Adds a pattern (persists pdf_url via repo). UI shows "Download Pattern" / "View PDF" and wand when pattern.pdfUrl != nil.
    func add(userId: UUID, title: String, description: String?, sourceUrl: String, status: PatternStatus, thumbnailUrl: String? = nil, difficulty: String? = nil, materials: String? = nil, craftType: String? = nil, sourceContent: String? = nil, pdfUrl: String? = nil, videoUrl: String? = nil, gauge: String? = nil, needleHookSizes: String? = nil, yarnWeightYardage: String? = nil, techniques: String? = nil) async -> Bool {
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
                techniques: techniques
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
