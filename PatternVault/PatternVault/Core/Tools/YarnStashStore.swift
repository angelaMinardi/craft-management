//
//  YarnStashStore.swift
//  PatternVault
//

import Foundation

@MainActor
final class YarnStashStore: ObservableObject {
    @Published private(set) var items: [YarnStashItem] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let repo = YarnStashRepository()

    func load(userId: UUID) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            items = try await repo.fetchAll(userId: userId)
        } catch {
            #if DEBUG
            print("[YarnStashStore] load failed: \(error)")
            #endif
            errorMessage = "Could not load your yarn stash. Please try again."
        }
    }

    func add(userId: UUID, brandName: String, colorName: String?, weight: String?, yardagePerSkein: Int?, skeinsOwned: Double, location: String?, notes: String?, barcode: String? = nil, dyeLot: String? = nil, fiberContent: String? = nil) async {
        errorMessage = nil
        guard !brandName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        do {
            let item = try await repo.add(userId: userId, brandName: brandName.trimmingCharacters(in: .whitespaces), colorName: colorName?.trimmingCharacters(in: .whitespaces), weight: weight?.trimmingCharacters(in: .whitespaces), yardagePerSkein: yardagePerSkein, skeinsOwned: max(0, skeinsOwned), location: location?.trimmingCharacters(in: .whitespaces), notes: notes?.trimmingCharacters(in: .whitespaces), barcode: barcode?.trimmingCharacters(in: .whitespaces), dyeLot: dyeLot?.trimmingCharacters(in: .whitespaces), fiberContent: fiberContent?.trimmingCharacters(in: .whitespaces))
            items.insert(item, at: 0)
        } catch {
            #if DEBUG
            print("[YarnStashStore] add failed: \(error)")
            #endif
            errorMessage = "Could not save yarn. Please try again."
        }
    }

    func update(_ item: YarnStashItem) async {
        errorMessage = nil
        do {
            let updated = try await repo.update(item)
            if let idx = items.firstIndex(where: { $0.id == updated.id }) {
                items[idx] = updated
            }
        } catch {
            #if DEBUG
            print("[YarnStashStore] update failed: \(error)")
            #endif
            errorMessage = "Could not update yarn. Please try again."
        }
    }

    func delete(item: YarnStashItem) async {
        errorMessage = nil
        do {
            try await repo.delete(id: item.id, userId: item.userId)
            items.removeAll { $0.id == item.id }
        } catch {
            #if DEBUG
            print("[YarnStashStore] delete failed: \(error)")
            #endif
            errorMessage = "Could not delete yarn. Please try again."
        }
    }
}
