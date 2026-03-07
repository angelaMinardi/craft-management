//
//  PatternYarnLinkStore.swift
//  PatternVault
//

import Foundation

@MainActor
final class PatternYarnLinkStore: ObservableObject {
    @Published var links: [PatternYarnLink] = []
    @Published var isLoading = false

    private let repo = PatternYarnLinkRepository()

    func load(patternId: UUID) async {
        isLoading = true
        defer { isLoading = false }
        do {
            links = try await repo.fetchLinks(patternId: patternId)
        } catch {
            links = []
        }
    }
}
