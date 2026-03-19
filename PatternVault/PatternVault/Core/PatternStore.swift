//
//  PatternStore.swift
//  PatternVault
//

import Foundation

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

    var wantToMakeCount: Int { patterns.filter { $0.status == .wantToMake }.count }
    var inProgressCount: Int { patterns.filter { $0.status == .inProgress }.count }
    var completedCount: Int { patterns.filter { $0.status == .completed }.count }

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
