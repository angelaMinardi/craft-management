//
//  YarnStashItem.swift
//  PatternVault
//

import Foundation

struct YarnStashItem: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    let userId: UUID
    var brandName: String
    var colorName: String?
    var weight: String?
    var yardagePerSkein: Int?
    var skeinsOwned: Double
    var location: String?
    var notes: String?
    var barcode: String?
    var dyeLot: String?
    var fiberContent: String?
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case brandName = "brand_name"
        case colorName = "color_name"
        case weight
        case yardagePerSkein = "yardage_per_skein"
        case skeinsOwned = "skeins_owned"
        case location
        case notes
        case barcode
        case dyeLot = "dye_lot"
        case fiberContent = "fiber_content"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var totalYardage: Int? {
        guard let ypp = yardagePerSkein, ypp > 0 else { return nil }
        return Int(Double(ypp) * skeinsOwned)
    }

    var displaySummary: String {
        var parts: [String] = [brandName]
        if let c = colorName, !c.isEmpty { parts.append(c) }
        if let w = weight, !w.isEmpty { parts.append(w) }
        if let y = totalYardage {
            parts.append("\(y) yd")
        } else if skeinsOwned != 0 {
            parts.append(skeinsOwned == floor(skeinsOwned) ? "Qty: \(Int(skeinsOwned))" : "Qty: \(skeinsOwned)")
        }
        return parts.joined(separator: " · ")
    }
}
