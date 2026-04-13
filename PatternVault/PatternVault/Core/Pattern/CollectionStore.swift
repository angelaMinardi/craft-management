//
//  CollectionStore.swift
//  PatternVault
//

import Foundation

@MainActor
final class CollectionStore: ObservableObject {
    @Published var collections: [PatternCollection] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let repo = CollectionRepository()

    func load(userId: UUID) async {
        isLoading = true
        defer { isLoading = false }
        do {
            collections = try await repo.fetchAll(userId: userId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func create(name: String, userId: UUID, icon: String = "folder.fill") async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            let collection = try await repo.create(
                name: trimmed,
                icon: icon,
                sortOrder: collections.count,
                userId: userId
            )
            collections.append(collection)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func rename(id: UUID, name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            let updated = try await repo.update(id: id, name: trimmed, icon: nil)
            if let idx = collections.firstIndex(where: { $0.id == id }) {
                collections[idx] = updated
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(id: UUID) async {
        do {
            try await repo.delete(id: id)
            collections.removeAll { $0.id == id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func movePattern(patternId: UUID, collectionId: UUID?) async {
        do {
            try await repo.movePattern(patternId: patternId, collectionId: collectionId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
