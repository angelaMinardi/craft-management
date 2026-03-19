//
//  EntitlementRepository.swift
//  PatternVault
//
//  Freemium: fetches and updates user_entitlements (usage + is_premium) via RPCs.
//

import Foundation
import Supabase

enum EntitlementError: Error {
    case noRow
}

struct UserEntitlement: Decodable {
    let userId: UUID
    let isPremium: Bool
    let aiUsageThisMonth: Int
    let youtubeImportsThisMonth: Int
    let usageMonth: String
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case isPremium = "is_premium"
        case aiUsageThisMonth = "ai_usage_this_month"
        case youtubeImportsThisMonth = "youtube_imports_this_month"
        case usageMonth = "usage_month"
        case updatedAt = "updated_at"
    }
}

@MainActor
final class EntitlementRepository: ObservableObject {
    private let client = SupabaseManager.client

    /// Ensures row exists and returns current usage (month resets handled in DB).
    func getOrCreateUsage(userId: UUID) async throws -> UserEntitlement {
        struct Params: Encodable {
            let p_user_id: String
        }
        let response: [UserEntitlement] = try await client
            .rpc("get_or_create_usage", params: Params(p_user_id: userId.uuidString))
            .execute()
            .value
        guard let row = response.first else { throw EntitlementError.noRow }
        return row
    }

    /// Increments AI usage. Returns new count, or nil if denied (free limit reached).
    func incrementAIUsage(userId: UUID) async throws -> Int? {
        struct Params: Encodable {
            let p_user_id: String
        }
        let count: Int = try await client
            .rpc("increment_ai_usage", params: Params(p_user_id: userId.uuidString))
            .execute()
            .value
        return count >= 0 ? count : nil
    }

    /// Increments YouTube imports. Returns new count, or nil if denied (free limit reached).
    func incrementYouTubeImports(userId: UUID) async throws -> Int? {
        struct Params: Encodable {
            let p_user_id: String
        }
        let count: Int = try await client
            .rpc("increment_youtube_imports", params: Params(p_user_id: userId.uuidString))
            .execute()
            .value
        return count >= 0 ? count : nil
    }

    /// Updates is_premium for the user (e.g. from StoreKit subscription status). Ensures row exists first.
    func setPremium(userId: UUID, isPremium: Bool) async throws {
        _ = try await getOrCreateUsage(userId: userId)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        struct SetPremiumPayload: Encodable {
            let is_premium: Bool
            let updated_at: String
        }
        let payload = SetPremiumPayload(is_premium: isPremium, updated_at: formatter.string(from: Date()))
        try await client
            .from("user_entitlements")
            .update(payload)
            .eq("user_id", value: userId.uuidString)
            .execute()
    }
}
