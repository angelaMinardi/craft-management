//
//  CollectionRepository.swift
//  PatternVault
//

import Foundation
import Supabase

@MainActor
final class CollectionRepository {
    private let client = SupabaseManager.client

    func fetchAll(userId: UUID) async throws -> [PatternCollection] {
        let response: [PatternCollection] = try await client
            .from("collections")
            .select()
            .eq("user_id", value: userId.uuidString)
            .order("sort_order")
            .order("name")
            .execute()
            .value
        return response
    }

    struct InsertPayload: Encodable {
        let user_id: String
        let name: String
        let icon: String
        let sort_order: Int
    }

    func create(name: String, icon: String, sortOrder: Int, userId: UUID) async throws -> PatternCollection {
        let payload = InsertPayload(
            user_id: userId.uuidString,
            name: name,
            icon: icon,
            sort_order: sortOrder
        )
        let response: PatternCollection = try await client
            .from("collections")
            .insert(payload)
            .select()
            .single()
            .execute()
            .value
        return response
    }

    struct UpdatePayload: Encodable {
        let name: String?
        let icon: String?
    }

    func update(id: UUID, name: String?, icon: String?) async throws -> PatternCollection {
        var payload: [String: String] = [:]
        if let name { payload["name"] = name }
        if let icon { payload["icon"] = icon }
        let response: PatternCollection = try await client
            .from("collections")
            .update(payload)
            .eq("id", value: id.uuidString)
            .select()
            .single()
            .execute()
            .value
        return response
    }

    func delete(id: UUID) async throws {
        try await client
            .from("collections")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }

    private struct MovePayload: Encodable {
        let collectionId: String?
        enum CodingKeys: String, CodingKey { case collectionId = "collection_id" }
    }

    func movePattern(patternId: UUID, collectionId: UUID?) async throws {
        try await client
            .from("patterns")
            .update(MovePayload(collectionId: collectionId?.uuidString))
            .eq("id", value: patternId.uuidString)
            .execute()
    }
}
