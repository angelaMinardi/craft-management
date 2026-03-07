//
//  PatternYarnLinkRepository.swift
//  PatternVault
//

import Foundation
import Supabase

@MainActor
final class PatternYarnLinkRepository: ObservableObject {
    private let client = SupabaseManager.client

    func fetchLinks(patternId: UUID) async throws -> [PatternYarnLink] {
        let response: [PatternYarnLink] = try await client
            .from("pattern_yarn_links")
            .select()
            .eq("pattern_id", value: patternId.uuidString)
            .order("display_order", ascending: true)
            .execute()
            .value
        return response
    }

    struct InsertPayload: Encodable {
        let id: String
        let pattern_id: String
        let user_id: String
        let brand_name: String
        let official_url: String?
        let store_url: String?
        let display_order: Int
    }

    func addLinks(patternId: UUID, userId: UUID, links: [(brandName: String, officialUrl: String?, storeUrl: String?)]) async throws {
        guard !links.isEmpty else { return }
        for (index, link) in links.enumerated() {
            let payload = InsertPayload(
                id: UUID().uuidString,
                pattern_id: patternId.uuidString,
                user_id: userId.uuidString,
                brand_name: link.brandName,
                official_url: link.officialUrl,
                store_url: link.storeUrl,
                display_order: index
            )
            try await client
                .from("pattern_yarn_links")
                .insert(payload)
                .execute()
        }
    }
}
