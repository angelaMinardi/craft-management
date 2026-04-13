//
//  Collection.swift
//  PatternVault
//

import Foundation

struct PatternCollection: Identifiable, Codable, Sendable {
    let id: UUID
    let userId: UUID
    var name: String
    var icon: String
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name, icon
        case userId = "user_id"
        case sortOrder = "sort_order"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
