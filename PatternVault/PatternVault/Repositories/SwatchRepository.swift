//
//  SwatchRepository.swift
//  PatternVault
//

import Foundation
import Supabase

@MainActor
final class SwatchRepository: ObservableObject {
    private let client = SupabaseManager.client

    func fetchAll(userId: UUID) async throws -> [Swatch] {
        let response: [Swatch] = try await client
            .from("swatches")
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
        let title: String?
        let craft: String?
        let photo_url: String?
        let needle_size: String?
        let needle_hook_id: String?
        let yarn_name: String?
        let yarn_stash_id: String?
        let stitches_per_4in: Double?
        let rows_per_4in: Double?
        let stitch_pattern: String?
        let blocked: Bool
        let washed: Bool
        let notes: String?
    }

    struct UpdatePayload: Encodable {
        let title: String?
        let craft: String?
        let photo_url: String?
        let needle_size: String?
        let needle_hook_id: String?
        let yarn_name: String?
        let yarn_stash_id: String?
        let stitches_per_4in: Double?
        let rows_per_4in: Double?
        let stitch_pattern: String?
        let blocked: Bool
        let washed: Bool
        let notes: String?

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            // Always encode all fields — including nils — so users can clear values.
            try c.encode(title, forKey: .title)
            try c.encode(craft, forKey: .craft)
            try c.encode(photo_url, forKey: .photo_url)
            try c.encode(needle_size, forKey: .needle_size)
            try c.encode(needle_hook_id, forKey: .needle_hook_id)
            try c.encode(yarn_name, forKey: .yarn_name)
            try c.encode(yarn_stash_id, forKey: .yarn_stash_id)
            try c.encode(stitches_per_4in, forKey: .stitches_per_4in)
            try c.encode(rows_per_4in, forKey: .rows_per_4in)
            try c.encode(stitch_pattern, forKey: .stitch_pattern)
            try c.encode(blocked, forKey: .blocked)
            try c.encode(washed, forKey: .washed)
            try c.encode(notes, forKey: .notes)
        }

        enum CodingKeys: String, CodingKey {
            case title, craft, photo_url, needle_size, needle_hook_id, yarn_name, yarn_stash_id
            case stitches_per_4in, rows_per_4in, stitch_pattern, blocked, washed, notes
        }
    }

    func add(_ swatch: Swatch) async throws -> Swatch {
        let payload = InsertPayload(
            id: swatch.id.uuidString,
            user_id: swatch.userId.uuidString,
            title: nullIfBlank(swatch.title),
            craft: nullIfBlank(swatch.craft),
            photo_url: nullIfBlank(swatch.photoUrl),
            needle_size: nullIfBlank(swatch.needleSize),
            needle_hook_id: swatch.needleHookId?.uuidString,
            yarn_name: nullIfBlank(swatch.yarnName),
            yarn_stash_id: swatch.yarnStashId?.uuidString,
            stitches_per_4in: swatch.stitchesPer4in,
            rows_per_4in: swatch.rowsPer4in,
            stitch_pattern: nullIfBlank(swatch.stitchPattern),
            blocked: swatch.blocked,
            washed: swatch.washed,
            notes: nullIfBlank(swatch.notes)
        )
        let response: Swatch = try await client
            .from("swatches")
            .insert(payload)
            .select()
            .single()
            .execute()
            .value
        return response
    }

    func update(_ swatch: Swatch) async throws -> Swatch {
        let payload = UpdatePayload(
            title: nullIfBlank(swatch.title),
            craft: nullIfBlank(swatch.craft),
            photo_url: nullIfBlank(swatch.photoUrl),
            needle_size: nullIfBlank(swatch.needleSize),
            needle_hook_id: swatch.needleHookId?.uuidString,
            yarn_name: nullIfBlank(swatch.yarnName),
            yarn_stash_id: swatch.yarnStashId?.uuidString,
            stitches_per_4in: swatch.stitchesPer4in,
            rows_per_4in: swatch.rowsPer4in,
            stitch_pattern: nullIfBlank(swatch.stitchPattern),
            blocked: swatch.blocked,
            washed: swatch.washed,
            notes: nullIfBlank(swatch.notes)
        )
        let response: Swatch = try await client
            .from("swatches")
            .update(payload)
            .eq("id", value: swatch.id.uuidString)
            .eq("user_id", value: swatch.userId.uuidString)
            .select()
            .single()
            .execute()
            .value
        return response
    }

    func delete(id: UUID, userId: UUID) async throws {
        try await client
            .from("swatches")
            .delete()
            .eq("id", value: id.uuidString)
            .eq("user_id", value: userId.uuidString)
            .execute()
    }

    /// Uploads a photo to `swatch-photos/<userId>/<swatchId>/<uuid>.jpg` and returns its public URL.
    /// Path prefix must be `<auth.uid()>/...` to satisfy the storage RLS policy.
    func uploadPhoto(imageData: Data, userId: UUID, swatchId: UUID) async throws -> String {
        let path = "\(userId.uuidString.lowercased())/\(swatchId.uuidString)/\(UUID().uuidString).jpg"
        try await client.storage
            .from("swatch-photos")
            .upload(path, data: imageData, options: .init(contentType: "image/jpeg"))
        let url = try client.storage
            .from("swatch-photos")
            .getPublicURL(path: path)
        return url.absoluteString
    }

    private func nullIfBlank(_ s: String?) -> String? {
        guard let trimmed = s?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
