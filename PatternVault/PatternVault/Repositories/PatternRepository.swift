//
//  PatternRepository.swift
//  PatternVault
//

import Foundation
import Supabase

@MainActor
final class PatternRepository: ObservableObject {
    private let client = SupabaseManager.client

    func fetchPatterns(userId: UUID) async throws -> [Pattern] {
        let response: [Pattern] = try await client
            .from("patterns")
            .select()
            .eq("user_id", value: userId.uuidString)
            .order("updated_at", ascending: false)
            .execute()
            .value
        return response
    }

    func fetchPatterns(userId: UUID, status: PatternStatus) async throws -> [Pattern] {
        let response: [Pattern] = try await client
            .from("patterns")
            .select()
            .eq("user_id", value: userId.uuidString)
            .eq("status", value: status.rawValue)
            .order("updated_at", ascending: false)
            .execute()
            .value
        return response
    }

    func fetchPattern(id: UUID, userId: UUID) async throws -> Pattern? {
        let response: [Pattern] = try await client
            .from("patterns")
            .select()
            .eq("id", value: id.uuidString)
            .eq("user_id", value: userId.uuidString)
            .limit(1)
            .execute()
            .value
        return response.first
    }

    struct InsertPayload: Encodable {
        let id: String
        let user_id: String
        let title: String
        let description: String?
        let source_url: String
        let source_platform: String?
        let status: String
        let thumbnail_url: String?
        let difficulty: String?
        let materials: String?
        let craft_type: String?
        let source_content: String?
        let pdf_url: String?
        let video_url: String?
        let gauge: String?
        let needle_hook_sizes: String?
        let yarn_weight_yardage: String?
        let techniques: String?
        let parsed_steps: String?
    }

    func addPattern(userId: UUID, title: String, description: String?, sourceUrl: String, sourcePlatform: String?, status: PatternStatus, thumbnailUrl: String? = nil, difficulty: String? = nil, materials: String? = nil, craftType: String? = nil, sourceContent: String? = nil, pdfUrl: String? = nil, videoUrl: String? = nil, gauge: String? = nil, needleHookSizes: String? = nil, yarnWeightYardage: String? = nil, techniques: String? = nil, parsedSteps: String? = nil) async throws -> Pattern {
        let id = UUID()
        let payload = InsertPayload(
            id: id.uuidString,
            user_id: userId.uuidString,
            title: title,
            description: description,
            source_url: sourceUrl,
            source_platform: sourcePlatform,
            status: status.rawValue,
            thumbnail_url: thumbnailUrl,
            difficulty: difficulty,
            materials: materials,
            craft_type: craftType,
            source_content: sourceContent,
            pdf_url: pdfUrl,
            video_url: videoUrl,
            gauge: gauge,
            needle_hook_sizes: needleHookSizes,
            yarn_weight_yardage: yarnWeightYardage,
            techniques: techniques,
            parsed_steps: parsedSteps
        )
        let response: Pattern = try await client
            .from("patterns")
            .insert(payload)
            .select()
            .single()
            .execute()
            .value
        return response
    }

    struct UpdatePayload: Encodable {
        let title: String?
        let description: String?
        let status: String?
        let difficulty: String?
        let materials: String?
        let craft_type: String?
        let pdf_url: String?
        let video_url: String?
        let gauge: String?
        let needle_hook_sizes: String?
        let yarn_weight_yardage: String?
        let techniques: String?
        let source_content: String?
        let parsed_steps: String?
        let updated_at: String

        enum CodingKeys: String, CodingKey {
            case title, description, status
            case difficulty, materials, craft_type
            case pdf_url, video_url, gauge, needle_hook_sizes, yarn_weight_yardage, techniques
            case source_content, parsed_steps, updated_at
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encodeIfPresent(title, forKey: .title)
            try c.encodeIfPresent(description, forKey: .description)
            try c.encodeIfPresent(status, forKey: .status)
            try c.encodeIfPresent(difficulty, forKey: .difficulty)
            try c.encodeIfPresent(materials, forKey: .materials)
            try c.encodeIfPresent(craft_type, forKey: .craft_type)
            try c.encodeIfPresent(pdf_url, forKey: .pdf_url)
            try c.encodeIfPresent(video_url, forKey: .video_url)
            try c.encodeIfPresent(gauge, forKey: .gauge)
            try c.encodeIfPresent(needle_hook_sizes, forKey: .needle_hook_sizes)
            try c.encodeIfPresent(yarn_weight_yardage, forKey: .yarn_weight_yardage)
            try c.encodeIfPresent(techniques, forKey: .techniques)
            try c.encodeIfPresent(source_content, forKey: .source_content)
            try c.encodeIfPresent(parsed_steps, forKey: .parsed_steps)
            try c.encode(updated_at, forKey: .updated_at)
        }
    }

    func updatePattern(id: UUID, userId: UUID, title: String?, description: String?, status: PatternStatus?, difficulty: String? = nil, materials: String? = nil, craftType: String? = nil, pdfUrl: String? = nil, videoUrl: String? = nil, gauge: String? = nil, needleHookSizes: String? = nil, yarnWeightYardage: String? = nil, techniques: String? = nil, sourceContent: String? = nil, parsedSteps: String? = nil) async throws -> Pattern {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let payload = UpdatePayload(
            title: title,
            description: description,
            status: status?.rawValue,
            difficulty: difficulty,
            materials: materials,
            craft_type: craftType,
            pdf_url: pdfUrl,
            video_url: videoUrl,
            gauge: gauge,
            needle_hook_sizes: needleHookSizes,
            yarn_weight_yardage: yarnWeightYardage,
            techniques: techniques,
            source_content: sourceContent,
            parsed_steps: parsedSteps,
            updated_at: formatter.string(from: Date())
        )
        let response: Pattern = try await client
            .from("patterns")
            .update(payload)
            .eq("id", value: id.uuidString)
            .eq("user_id", value: userId.uuidString)
            .select()
            .single()
            .execute()
            .value
        return response
    }

    func updateStatus(patternId: UUID, userId: UUID, status: PatternStatus) async throws -> Pattern {
        try await updatePattern(id: patternId, userId: userId, title: nil, description: nil, status: status)
    }

    func updatePdfUrl(patternId: UUID, userId: UUID, pdfUrl: String?) async throws -> Pattern {
        try await updatePattern(id: patternId, userId: userId, title: nil, description: nil, status: nil, pdfUrl: pdfUrl)
    }

    func updateParsedSteps(patternId: UUID, userId: UUID, parsedSteps: String?) async throws -> Pattern {
        try await updatePattern(id: patternId, userId: userId, title: nil, description: nil, status: nil, parsedSteps: parsedSteps)
    }

    func deletePattern(id: UUID, userId: UUID) async throws {
        try await client
            .from("patterns")
            .delete()
            .eq("id", value: id.uuidString)
            .eq("user_id", value: userId.uuidString)
            .execute()
    }

    /// Deletes multiple patterns for the user. RLS ensures only own rows are removed.
    func deletePatterns(ids: [UUID], userId: UUID) async throws {
        for id in ids {
            try await deletePattern(id: id, userId: userId)
        }
    }

    /// Uploads PDF to pattern-pdfs bucket. Path: userId/patternId/uuid.pdf. Returns public URL.
    func uploadPdf(pdfData: Data, patternId: UUID, userId: UUID) async throws -> String {
        let path = "\(userId.uuidString)/\(patternId.uuidString)/\(UUID().uuidString).pdf"
        try await client.storage
            .from("pattern-pdfs")
            .upload(path, data: pdfData, options: .init(contentType: "application/pdf"))
        let url = try client.storage
            .from("pattern-pdfs")
            .getPublicURL(path: path)
        return url.absoluteString
    }
}
