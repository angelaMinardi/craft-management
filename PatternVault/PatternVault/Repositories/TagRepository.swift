//
//  TagRepository.swift
//  PatternVault
//

import Foundation
import Supabase

@MainActor
final class TagRepository: ObservableObject {
    private let client = SupabaseManager.client

    func fetchAllTags() async throws -> [Tag] {
        let response: [Tag] = try await client
            .from("tags")
            .select()
            .order("category")
            .order("name")
            .execute()
            .value
        return response
    }

    func fetchTags(forPatternId patternId: UUID) async throws -> [Tag] {
        // Query pattern_tags joined with tags
        let response: [PatternTagJoin] = try await client
            .from("pattern_tags")
            .select("tag_id, tags(*)")
            .eq("pattern_id", value: patternId.uuidString)
            .execute()
            .value
        return response.compactMap { $0.tags }
    }

    struct PatternTagJoin: Decodable {
        let tagId: UUID
        let tags: Tag?

        enum CodingKeys: String, CodingKey {
            case tagId = "tag_id"
            case tags
        }
    }

    struct PatternTagPayload: Encodable {
        let pattern_id: String
        let tag_id: String
    }

    func addTag(patternId: UUID, tagId: UUID) async throws {
        let payload = PatternTagPayload(
            pattern_id: patternId.uuidString,
            tag_id: tagId.uuidString
        )
        try await client
            .from("pattern_tags")
            .insert(payload)
            .execute()
    }

    func removeTag(patternId: UUID, tagId: UUID) async throws {
        try await client
            .from("pattern_tags")
            .delete()
            .eq("pattern_id", value: patternId.uuidString)
            .eq("tag_id", value: tagId.uuidString)
            .execute()
    }

    func setTags(patternId: UUID, tagIds: Set<UUID>) async throws {
        // Remove all existing tags for this pattern
        try await client
            .from("pattern_tags")
            .delete()
            .eq("pattern_id", value: patternId.uuidString)
            .execute()

        // Insert new tags
        if !tagIds.isEmpty {
            let payloads = tagIds.map { tagId in
                PatternTagPayload(
                    pattern_id: patternId.uuidString,
                    tag_id: tagId.uuidString
                )
            }
            try await client
                .from("pattern_tags")
                .insert(payloads)
                .execute()
        }
    }
}
