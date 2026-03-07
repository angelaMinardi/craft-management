//
//  PatternStore.swift
//  PatternVault
//

import Foundation

@MainActor
final class PatternStore: ObservableObject {
    @Published var patterns: [Pattern] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let repo = PatternRepository()

    var wantToMakeCount: Int { patterns.filter { $0.status == .wantToMake }.count }
    var inProgressCount: Int { patterns.filter { $0.status == .inProgress }.count }
    var completedCount: Int { patterns.filter { $0.status == .completed }.count }

    func load(userId: UUID) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            patterns = try await repo.fetchPatterns(userId: userId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func add(userId: UUID, title: String, description: String?, sourceUrl: String, status: PatternStatus, thumbnailUrl: String? = nil, difficulty: String? = nil, materials: String? = nil, craftType: String? = nil, sourceContent: String? = nil, pdfUrl: String? = nil, videoUrl: String? = nil, gauge: String? = nil, needleHookSizes: String? = nil, yarnWeightYardage: String? = nil, techniques: String? = nil) async -> Bool {
        errorMessage = nil
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
            errorMessage = error.localizedDescription
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
            errorMessage = error.localizedDescription
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
            errorMessage = error.localizedDescription
        }
    }

    func delete(pattern: Pattern, userId: UUID) async {
        errorMessage = nil
        do {
            try await repo.deletePattern(id: pattern.id, userId: userId)
            patterns.removeAll { $0.id == pattern.id }
        } catch {
            errorMessage = error.localizedDescription
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
            errorMessage = error.localizedDescription
        }
    }
}
