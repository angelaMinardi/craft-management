//
//  NeedleHookStore.swift
//  PatternVault
//

import Foundation

@MainActor
final class NeedleHookStore: ObservableObject {
    @Published private(set) var items: [NeedleHookItem] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let repo = NeedleHookRepository()

    func load(userId: UUID) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            items = try await repo.fetchAll(userId: userId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func add(userId: UUID, type: String, size: String, lengthCm: Double?, notes: String?) async {
        errorMessage = nil
        let trimmedSize = size.trimmingCharacters(in: .whitespaces)
        let trimmedType = type.trimmingCharacters(in: .whitespaces)
        guard !trimmedSize.isEmpty, !trimmedType.isEmpty else { return }
        do {
            let item = try await repo.add(userId: userId, type: trimmedType, size: trimmedSize, lengthCm: lengthCm, notes: notes?.trimmingCharacters(in: .whitespaces))
            items.append(item)
            items.sort { ($0.type.lowercased(), $0.size) < ($1.type.lowercased(), $1.size) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func update(_ item: NeedleHookItem) async {
        errorMessage = nil
        do {
            let updated = try await repo.update(item)
            if let idx = items.firstIndex(where: { $0.id == updated.id }) {
                items[idx] = updated
            }
            items.sort { ($0.type.lowercased(), $0.size) < ($1.type.lowercased(), $1.size) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(item: NeedleHookItem) async {
        errorMessage = nil
        do {
            try await repo.delete(id: item.id, userId: item.userId)
            items.removeAll { $0.id == item.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    var needles: [NeedleHookItem] { items.filter { $0.type.lowercased() == "needle" } }
    var hooks: [NeedleHookItem] { items.filter { $0.type.lowercased() == "hook" } }
    var otherTools: [NeedleHookItem] { items.filter { let t = $0.type.lowercased(); return t != "needle" && t != "hook" } }
}
