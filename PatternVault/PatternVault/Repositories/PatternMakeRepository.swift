//
//  PatternMakeRepository.swift
//  PatternVault
//

import Foundation
import Supabase

@MainActor
final class PatternMakeRepository: ObservableObject {
    private let client = SupabaseManager.client

    func fetchMakes(patternId: UUID, userId: UUID) async throws -> [PatternMake] {
        let response: [PatternMake] = try await client
            .from("pattern_makes")
            .select()
            .eq("pattern_id", value: patternId.uuidString)
            .eq("user_id", value: userId.uuidString)
            .order("created_at", ascending: true)
            .execute()
            .value
        return response
    }

    struct InsertPayload: Encodable {
        let id: String
        let pattern_id: String
        let user_id: String
        let name: String
        let size_name: String?
        let yardage_used: Int?
        let size_measurements: String?
    }

    struct UpdatePayload: Encodable {
        let name: String
        let size_name: String?
        let yardage_used: Int?
        let size_measurements: String?
    }

    func add(patternId: UUID, userId: UUID, name: String, sizeName: String?, yardageUsed: Int?, sizeMeasurements: String?) async throws -> PatternMake {
        let id = UUID()
        let payload = InsertPayload(
            id: id.uuidString,
            pattern_id: patternId.uuidString,
            user_id: userId.uuidString,
            name: name.trimmingCharacters(in: .whitespaces),
            size_name: sizeName?.isEmpty == true ? nil : sizeName,
            yardage_used: yardageUsed,
            size_measurements: sizeMeasurements?.isEmpty == true ? nil : sizeMeasurements
        )
        let response: PatternMake = try await client
            .from("pattern_makes")
            .insert(payload)
            .select()
            .single()
            .execute()
            .value
        return response
    }

    func update(_ make: PatternMake) async throws -> PatternMake {
        let payload = UpdatePayload(
            name: make.name.trimmingCharacters(in: .whitespaces),
            size_name: make.sizeName?.isEmpty == true ? nil : make.sizeName,
            yardage_used: make.yardageUsed,
            size_measurements: make.sizeMeasurements?.isEmpty == true ? nil : make.sizeMeasurements
        )
        let response: PatternMake = try await client
            .from("pattern_makes")
            .update(payload)
            .eq("id", value: make.id.uuidString)
            .eq("user_id", value: make.userId.uuidString)
            .select()
            .single()
            .execute()
            .value
        return response
    }

    func delete(makeId: UUID, userId: UUID) async throws {
        try await client
            .from("pattern_makes")
            .delete()
            .eq("id", value: makeId.uuidString)
            .eq("user_id", value: userId.uuidString)
            .execute()
    }
}
