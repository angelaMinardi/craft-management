//
//  NeedleHookItem.swift
//  PatternVault
//
//  Generic tool inventory item. Type is freeform (e.g. needle, hook, leather cutter).
//

import Foundation

struct NeedleHookItem: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    let userId: UUID
    var type: String
    var size: String
    var lengthCm: Double?
    var notes: String?
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case type
        case size
        case lengthCm = "length_cm"
        case notes
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    /// Display name for the tool type (capitalized).
    var typeDisplayName: String {
        let t = type.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return "Tool" }
        return t.prefix(1).uppercased() + t.dropFirst().lowercased()
    }

    /// SF Symbol name for the tool type (needle/hook keep familiar icons; others use generic tool).
    var typeSystemImage: String {
        switch type.lowercased() {
        case "needle": return "scissors"
        case "hook": return "circle.grid.cross"
        default: return "wrench.and.screwdriver"
        }
    }

    var displaySummary: String {
        var parts: [String] = [typeDisplayName, size]
        if let len = lengthCm, len > 0 { parts.append("\(Int(len)) cm") }
        return parts.joined(separator: " · ")
    }
}
