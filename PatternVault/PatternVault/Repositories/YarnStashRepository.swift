//
//  YarnStashRepository.swift
//  PatternVault
//

import Foundation
import Supabase

@MainActor
final class YarnStashRepository: ObservableObject {
    private let client = SupabaseManager.client

    func fetchAll(userId: UUID) async throws -> [YarnStashItem] {
        let response: [YarnStashItem] = try await client
            .from("yarn_stash")
            .select()
            .eq("user_id", value: userId.uuidString)
            .order("updated_at", ascending: false)
            .execute()
            .value
        return response
    }

    struct InsertPayload: Encodable {
        let id: String
        let user_id: String
        let brand_name: String
        let color_name: String?
        let weight: String?
        let yardage_per_skein: Int?
        let skeins_owned: Double
        let location: String?
        let notes: String?
    }

    struct UpdatePayload: Encodable {
        let brand_name: String
        let color_name: String?
        let weight: String?
        let yardage_per_skein: Int?
        let skeins_owned: Double
        let location: String?
        let notes: String?
    }

    func add(userId: UUID, brandName: String, colorName: String?, weight: String?, yardagePerSkein: Int?, skeinsOwned: Double, location: String?, notes: String?) async throws -> YarnStashItem {
        let id = UUID()
        let payload = InsertPayload(
            id: id.uuidString,
            user_id: userId.uuidString,
            brand_name: brandName,
            color_name: colorName?.isEmpty == true ? nil : colorName,
            weight: weight?.isEmpty == true ? nil : weight,
            yardage_per_skein: yardagePerSkein,
            skeins_owned: max(0, skeinsOwned),
            location: location?.isEmpty == true ? nil : location,
            notes: notes?.isEmpty == true ? nil : notes
        )
        let response: YarnStashItem = try await client
            .from("yarn_stash")
            .insert(payload)
            .select()
            .single()
            .execute()
            .value
        return response
    }

    func update(_ item: YarnStashItem) async throws -> YarnStashItem {
        let payload = UpdatePayload(
            brand_name: item.brandName,
            color_name: item.colorName?.isEmpty == true ? nil : item.colorName,
            weight: item.weight?.isEmpty == true ? nil : item.weight,
            yardage_per_skein: item.yardagePerSkein,
            skeins_owned: max(0, item.skeinsOwned),
            location: item.location?.isEmpty == true ? nil : item.location,
            notes: item.notes?.isEmpty == true ? nil : item.notes
        )
        let response: YarnStashItem = try await client
            .from("yarn_stash")
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
            .from("yarn_stash")
            .delete()
            .eq("id", value: id.uuidString)
            .eq("user_id", value: userId.uuidString)
            .execute()
    }
}
