//
//  Swatch.swift
//  PatternVault
//
//  A knit/crochet swatch log entry: photo + needles/yarn used + gauge.
//

import Foundation

struct Swatch: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    let userId: UUID
    var title: String?
    var craft: String?
    var photoUrl: String?
    var needleSize: String?
    var needleHookId: UUID?
    var yarnName: String?
    var yarnStashId: UUID?
    var stitchesPer4in: Double?
    var rowsPer4in: Double?
    var stitchPattern: String?
    var blocked: Bool
    var washed: Bool
    var notes: String?
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case title
        case craft
        case photoUrl = "photo_url"
        case needleSize = "needle_size"
        case needleHookId = "needle_hook_id"
        case yarnName = "yarn_name"
        case yarnStashId = "yarn_stash_id"
        case stitchesPer4in = "stitches_per_4in"
        case rowsPer4in = "rows_per_4in"
        case stitchPattern = "stitch_pattern"
        case blocked
        case washed
        case notes
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    /// Title if set, otherwise falls back to "Stockinette swatch", "Knit swatch", or "Swatch".
    var displayTitle: String {
        if let t = title?.trimmingCharacters(in: .whitespaces), !t.isEmpty { return t }
        if let sp = stitchPattern?.trimmingCharacters(in: .whitespaces), !sp.isEmpty {
            return "\(sp) swatch"
        }
        if let c = craft?.trimmingCharacters(in: .whitespaces), !c.isEmpty {
            return "\(c.prefix(1).uppercased())\(c.dropFirst().lowercased()) swatch"
        }
        return "Swatch"
    }

    /// One-line summary for list rows: gauge + needle size when available.
    var gaugeSummary: String? {
        var parts: [String] = []
        if let s = stitchesPer4in, s > 0 {
            let stitchesStr = s == s.rounded() ? "\(Int(s))" : String(format: "%.1f", s)
            parts.append("\(stitchesStr) sts/4\"")
        }
        if let r = rowsPer4in, r > 0 {
            let rowsStr = r == r.rounded() ? "\(Int(r))" : String(format: "%.1f", r)
            parts.append("\(rowsStr) rows/4\"")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var needleSummary: String? {
        let trimmed = needleSize?.trimmingCharacters(in: .whitespaces)
        return (trimmed?.isEmpty == false) ? trimmed : nil
    }

    var yarnSummary: String? {
        let trimmed = yarnName?.trimmingCharacters(in: .whitespaces)
        return (trimmed?.isEmpty == false) ? trimmed : nil
    }
}
