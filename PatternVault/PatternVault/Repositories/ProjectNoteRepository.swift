//
//  ProjectNoteRepository.swift
//  PatternVault
//

import Foundation
import Supabase

@MainActor
final class ProjectNoteRepository: ObservableObject {
    private let client = SupabaseManager.client

    func fetchNotes(patternId: UUID) async throws -> [ProjectNote] {
        let response: [ProjectNote] = try await client
            .from("project_notes")
            .select()
            .eq("pattern_id", value: patternId.uuidString)
            .order("created_at", ascending: false)
            .execute()
            .value
        return response
    }

    struct InsertPayload: Encodable {
        let id: String
        let pattern_id: String
        let user_id: String
        let note_type: String
        let content: String
        let photo_url: String?
    }

    func addNote(patternId: UUID, userId: UUID, noteType: ProjectNoteType, content: String, photoUrl: String?) async throws -> ProjectNote {
        let id = UUID()
        let payload = InsertPayload(
            id: id.uuidString,
            pattern_id: patternId.uuidString,
            user_id: userId.uuidString,
            note_type: noteType.rawValue,
            content: content,
            photo_url: photoUrl
        )
        let response: ProjectNote = try await client
            .from("project_notes")
            .insert(payload)
            .select()
            .single()
            .execute()
            .value
        return response
    }

    struct UpdatePayload: Encodable {
        let content: String?
        let note_type: String?
        let photo_url: String?
        let updated_at: String

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encodeIfPresent(content, forKey: .content)
            try c.encodeIfPresent(note_type, forKey: .note_type)
            // photo_url can be explicitly set to nil (remove photo), so always encode it
            try c.encode(photo_url, forKey: .photo_url)
            try c.encode(updated_at, forKey: .updated_at)
        }

        enum CodingKeys: String, CodingKey {
            case content, note_type, photo_url, updated_at
        }
    }

    func updateNote(id: UUID, userId: UUID, content: String?, noteType: ProjectNoteType?, photoUrl: String?) async throws -> ProjectNote {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let payload = UpdatePayload(
            content: content,
            note_type: noteType?.rawValue,
            photo_url: photoUrl,
            updated_at: formatter.string(from: Date())
        )
        let response: ProjectNote = try await client
            .from("project_notes")
            .update(payload)
            .eq("id", value: id.uuidString)
            .eq("user_id", value: userId.uuidString)
            .select()
            .single()
            .execute()
            .value
        return response
    }

    func deleteNote(id: UUID, userId: UUID) async throws {
        try await client
            .from("project_notes")
            .delete()
            .eq("id", value: id.uuidString)
            .eq("user_id", value: userId.uuidString)
            .execute()
    }

    /// Returns the number of project notes that have a photo (for freemium limit).
    func countNotesWithPhoto(userId: UUID) async throws -> Int {
        struct Params: Encodable {
            let p_user_id: String
        }
        let count: Int = try await client
            .rpc("count_notes_with_photo", params: Params(p_user_id: userId.uuidString))
            .execute()
            .value
        return count
    }

    func uploadPhoto(imageData: Data, noteId: UUID) async throws -> String {
        let path = "\(noteId.uuidString)/\(UUID().uuidString).jpg"
        try await client.storage
            .from("note-photos")
            .upload(path, data: imageData, options: .init(contentType: "image/jpeg"))
        let url = try client.storage
            .from("note-photos")
            .getPublicURL(path: path)
        return url.absoluteString
    }
}
