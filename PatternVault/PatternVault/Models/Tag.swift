//
//  Tag.swift
//  PatternVault
//

import Foundation

struct Tag: Identifiable, Codable, Sendable {
    let id: UUID
    var name: String
    var category: String?
    var createdAt: Date?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case category
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
