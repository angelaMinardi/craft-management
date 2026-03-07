//
//  PatternImageStore.swift
//  PatternVault
//

import Foundation

@MainActor
final class PatternImageStore: ObservableObject {
    @Published var images: [PatternImage] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let repo = PatternImageRepository()

    func load(patternId: UUID) async {
        isLoading = true
        defer { isLoading = false }
        do {
            images = try await repo.fetchImages(patternId: patternId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addFromData(patternId: UUID, userId: UUID, imageData: Data, displayOrder: Int) async -> Bool {
        do {
            let url = try await repo.uploadImage(imageData: imageData, patternId: patternId)
            let image = try await repo.addImage(
                patternId: patternId,
                userId: userId,
                imageUrl: url,
                displayOrder: displayOrder
            )
            images.append(image)
            images.sort { $0.displayOrder < $1.displayOrder }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func delete(imageId: UUID) async {
        do {
            try await repo.deleteImage(id: imageId)
            images.removeAll { $0.id == imageId }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
