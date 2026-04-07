//
//  PatternImageRepository.swift
//  PatternVault
//

import Foundation
import Supabase

@MainActor
final class PatternImageRepository: ObservableObject {
    private let client = SupabaseManager.client

    func fetchImages(patternId: UUID) async throws -> [PatternImage] {
        let response: [PatternImage] = try await client
            .from("pattern_images")
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
        let image_url: String
        let display_order: Int
    }

    func addImage(patternId: UUID, userId: UUID, imageUrl: String, displayOrder: Int) async throws -> PatternImage {
        let payload = InsertPayload(
            id: UUID().uuidString,
            pattern_id: patternId.uuidString,
            user_id: userId.uuidString,
            image_url: imageUrl,
            display_order: displayOrder
        )
        let response: PatternImage = try await client
            .from("pattern_images")
            .insert(payload)
            .select()
            .single()
            .execute()
            .value
        return response
    }

    func deleteImage(id: UUID, userId: UUID) async throws {
        try await client
            .from("pattern_images")
            .delete()
            .eq("id", value: id.uuidString)
            .eq("user_id", value: userId.uuidString)
            .execute()
    }

    func uploadImage(imageData: Data, patternId: UUID, userId: UUID? = nil) async throws -> String {
        let userFolder = (userId ?? UUID()).uuidString.lowercased()
        let path = "\(userFolder)/\(patternId.uuidString.lowercased())/\(UUID().uuidString.lowercased()).jpg"
        try await client.storage
            .from("pattern-images")
            .upload(path, data: imageData, options: .init(contentType: "image/jpeg"))
        let url = try client.storage
            .from("pattern-images")
            .getPublicURL(path: path)
        return url.absoluteString
    }
}
