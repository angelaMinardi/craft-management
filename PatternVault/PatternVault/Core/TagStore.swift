//
//  TagStore.swift
//  PatternVault
//

import Foundation

@MainActor
final class TagStore: ObservableObject {
    @Published var allTags: [Tag] = []
    @Published var patternTags: [Tag] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let repo = TagRepository()

    /// Tags grouped by category
    var tagsByCategory: [String: [Tag]] {
        Dictionary(grouping: allTags) { $0.category ?? "other" }
    }

    static let categoryDisplayNames: [String: String] = [
        "craft_type": "Craft Type",
        "difficulty": "Difficulty",
        "project_type": "Project Type",
        "purpose": "Purpose",
        "other": "Other"
    ]

    static let categoryOrder = ["craft_type", "difficulty", "project_type", "purpose", "other"]

    func loadAllTags() async {
        guard allTags.isEmpty else { return }
        do {
            allTags = try await repo.fetchAllTags()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadPatternTags(patternId: UUID) async {
        isLoading = true
        defer { isLoading = false }
        do {
            patternTags = try await repo.fetchTags(forPatternId: patternId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setTags(patternId: UUID, tagIds: Set<UUID>) async {
        errorMessage = nil
        do {
            try await repo.setTags(patternId: patternId, tagIds: tagIds)
            patternTags = allTags.filter { tagIds.contains($0.id) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
