//
//  NeedleHookRepository.swift
//  PatternVault
//

import Foundation
import Supabase

@MainActor
final class NeedleHookRepository: ObservableObject {
    private let client = SupabaseManager.client

    func fetchAll(userId: UUID) async throws -> [NeedleHookItem] {
        let response: [NeedleHookItem] = try await client
            .from("needle_hook_inventory")
            .select()
            .eq("user_id", value: userId.uuidString)
            .order("type")
            .order("size")
            .execute()
            .value
        return response
    }

    struct InsertPayload: Encodable {
        let id: String
        let user_id: String
        let type: String
        let size: String
        let length_cm: Double?
        let notes: String?
    }

    struct UpdatePayload: Encodable {
        let type: String
        let size: String
        let length_cm: Double?
        let notes: String?
    }

    func add(userId: UUID, type: String, size: String, lengthCm: Double?, notes: String?) async throws -> NeedleHookItem {
        let id = UUID()
        let payload = InsertPayload(
            id: id.uuidString,
            user_id: userId.uuidString,
            type: type.trimmingCharacters(in: .whitespaces),
            size: size.trimmingCharacters(in: .whitespaces),
            length_cm: lengthCm,
            notes: notes?.isEmpty == true ? nil : notes
        )
        let response: NeedleHookItem = try await client
            .from("needle_hook_inventory")
            .insert(payload)
            .select()
            .single()
            .execute()
            .value
        return response
    }

    func update(_ item: NeedleHookItem) async throws -> NeedleHookItem {
        let payload = UpdatePayload(
            type: item.type.trimmingCharacters(in: .whitespaces),
            size: item.size.trimmingCharacters(in: .whitespaces),
            length_cm: item.lengthCm,
            notes: item.notes?.isEmpty == true ? nil : item.notes
        )
        let response: NeedleHookItem = try await client
            .from("needle_hook_inventory")
            .update(payload)
            .eq("id", value: item.id.uuidString)
            .eq("user_id", value: item.userId.uuidString)
            .select()
            .single()
            .execute()
            .value
        return response
    }

    func delete(id: UUID, userId: UUID) async throws {
        try await client
            .from("needle_hook_inventory")
            .delete()
            .eq("id", value: id.uuidString)
            .eq("user_id", value: userId.uuidString)
            .execute()
    }
}
