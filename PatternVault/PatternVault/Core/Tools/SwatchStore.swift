//
//  SwatchStore.swift
//  PatternVault
//

import Foundation

@MainActor
final class SwatchStore: ObservableObject {
    @Published private(set) var items: [Swatch] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let repo = SwatchRepository()

    func load(userId: UUID) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            items = try await repo.fetchAll(userId: userId)
        } catch {
            #if DEBUG
            print("[SwatchStore] load failed: \(error)")
            #endif
            errorMessage = "Could not load your swatches. Please try again."
        }
    }

    /// Add a swatch. If `photoData` is provided, it's uploaded first and the public URL stored on the row.
    @discardableResult
    func add(
        userId: UUID,
        title: String?,
        craft: String?,
        needleSize: String?,
        needleHookId: UUID?,
        yarnName: String?,
        yarnStashId: UUID?,
        stitchesPer4in: Double?,
        rowsPer4in: Double?,
        stitchPattern: String?,
        blocked: Bool,
        washed: Bool,
        notes: String?,
        photoData: Data?
    ) async -> Bool {
        errorMessage = nil
        let id = UUID()
        let now = Date()

        var photoUrl: String?
        if let data = photoData {
            do {
                photoUrl = try await repo.uploadPhoto(imageData: data, userId: userId, swatchId: id)
            } catch {
                #if DEBUG
                print("[SwatchStore] photo upload failed: \(error)")
                #endif
                errorMessage = "Could not upload photo. Swatch not saved."
                return false
            }
        }

        let draft = Swatch(
            id: id,
            userId: userId,
            title: title,
            craft: craft,
            photoUrl: photoUrl,
            needleSize: needleSize,
            needleHookId: needleHookId,
            yarnName: yarnName,
            yarnStashId: yarnStashId,
            stitchesPer4in: stitchesPer4in,
            rowsPer4in: rowsPer4in,
            stitchPattern: stitchPattern,
            blocked: blocked,
            washed: washed,
            notes: notes,
            createdAt: now,
            updatedAt: now
        )

        do {
            let saved = try await repo.add(draft)
            items.insert(saved, at: 0)
            return true
        } catch {
            #if DEBUG
            print("[SwatchStore] add failed: \(error)")
            #endif
            errorMessage = "Could not save swatch. Please try again."
            return false
        }
    }

    /// Update an existing swatch. If `newPhotoData` is provided, uploads and replaces `photoUrl` first.
    @discardableResult
    func update(_ swatch: Swatch, newPhotoData: Data? = nil) async -> Bool {
        errorMessage = nil
        var updated = swatch
        if let data = newPhotoData {
            do {
                updated.photoUrl = try await repo.uploadPhoto(imageData: data, userId: swatch.userId, swatchId: swatch.id)
            } catch {
                #if DEBUG
                print("[SwatchStore] photo upload failed: \(error)")
                #endif
                errorMessage = "Could not upload photo. Swatch not updated."
                return false
            }
        }

        do {
            let saved = try await repo.update(updated)
            if let idx = items.firstIndex(where: { $0.id == saved.id }) {
                items[idx] = saved
            }
            return true
        } catch {
            #if DEBUG
            print("[SwatchStore] update failed: \(error)")
            #endif
            errorMessage = "Could not update swatch. Please try again."
            return false
        }
    }

    func delete(item: Swatch) async {
        errorMessage = nil
        do {
            try await repo.delete(id: item.id, userId: item.userId)
            items.removeAll { $0.id == item.id }
        } catch {
            #if DEBUG
            print("[SwatchStore] delete failed: \(error)")
            #endif
            errorMessage = "Could not delete swatch. Please try again."
        }
    }
}
