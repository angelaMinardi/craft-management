//
//  PatternDuplicateHelper.swift
//  PatternVault
//
//  Detects duplicate and similar patterns in the vault.
//

import Foundation

enum PatternDuplicateHelper {
    /// Groups of patterns that are likely duplicates (same source URL, or same title + host).
    static func duplicateGroups(in patterns: [Pattern]) -> [[Pattern]] {
        var byExactUrl: [String: [Pattern]] = [:]
        for p in patterns {
            let key = p.sourceUrl.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !key.isEmpty {
                byExactUrl[key, default: []].append(p)
            }
        }
        var groups: [[Pattern]] = []
        for (_, list) in byExactUrl where list.count > 1 {
            groups.append(list.sorted { $0.updatedAt > $1.updatedAt })
        }
        let exactDupeIds = Set(groups.flatMap { $0.map(\.id) })
        var byHostTitle: [String: [Pattern]] = [:]
        for p in patterns where !exactDupeIds.contains(p.id) {
            guard let host = hostFromURL(p.sourceUrl), !host.isEmpty else { continue }
            let titleNorm = normalizeTitle(p.title)
            guard !titleNorm.isEmpty else { continue }
            let key = "\(host)|\(titleNorm)"
            byHostTitle[key, default: []].append(p)
        }
        for (_, list) in byHostTitle where list.count > 1 {
            groups.append(list.sorted { $0.updatedAt > $1.updatedAt })
        }
        return groups
    }

    /// Check if the vault already has a pattern with the same (or very similar) URL.
    static func existingMatch(for sourceUrl: String, in patterns: [Pattern], excludingId: UUID? = nil) -> Pattern? {
        let normalized = sourceUrl.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }
        for p in patterns {
            if let excl = excludingId, p.id == excl { continue }
            if p.sourceUrl.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalized {
                return p
            }
        }
        return nil
    }

    private static func hostFromURL(_ urlString: String) -> String? {
        guard let url = URL(string: urlString), let host = url.host else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private static func normalizeTitle(_ title: String) -> String {
        title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .components(separatedBy: .alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .prefix(8)
            .joined(separator: " ")
    }
}

struct SimilarPatternResult: Identifiable {
    var id: UUID { pattern.id }
    let pattern: Pattern
    let score: Int
    let reason: String
}

enum PatternSimilarityHelper {
    private static let minimumScore = 6

    /// Patterns from the list that are similar to the given pattern (excluding itself), sorted by relevance.
    /// Only returns results above the minimum score threshold so results feel intentional.
    static func similar(to pattern: Pattern, in patterns: [Pattern], limit: Int = 5) -> [SimilarPatternResult] {
        let others = patterns.filter { $0.id != pattern.id }
        let patternWords = Set(normalizeTitle(pattern.title).split(separator: " ").map(String.init))
        let craft = (pattern.craftType ?? "").lowercased()
        let weight = (pattern.yarnWeightYardage ?? "").lowercased()
        let techniques = Set((pattern.techniques ?? "").lowercased().components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
        let materials = (pattern.materials ?? "").lowercased()

        let scored: [(Pattern, Int, String)] = others.map { p in
            var score = 0
            var reasons: [String] = []

            let pWords = Set(normalizeTitle(p.title).split(separator: " ").map(String.init))
            let overlap = patternWords.intersection(pWords).count
            if overlap > 0 {
                score += overlap * 10
                reasons.append("Similar name")
            }

            if !craft.isEmpty, (p.craftType ?? "").lowercased() == craft {
                score += 5
                reasons.append("Same craft")
            }

            if !weight.isEmpty {
                let pWeight = (p.yarnWeightYardage ?? "").lowercased()
                if !pWeight.isEmpty && (pWeight.contains(weight) || weight.contains(pWeight)) {
                    score += 3
                    reasons.append("Similar yarn weight")
                }
            }

            if !techniques.isEmpty {
                let pTech = Set((p.techniques ?? "").lowercased().components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
                let techOverlap = techniques.intersection(pTech).count
                if techOverlap > 0 {
                    score += techOverlap * 4
                    if !reasons.contains("Similar techniques") { reasons.append("Similar techniques") }
                }
            }

            if !materials.isEmpty {
                let pMat = (p.materials ?? "").lowercased()
                if !pMat.isEmpty {
                    let matWords = Set(materials.components(separatedBy: .alphanumerics.inverted).filter { $0.count > 2 })
                    let pMatWords = Set(pMat.components(separatedBy: .alphanumerics.inverted).filter { $0.count > 2 })
                    let matOverlap = matWords.intersection(pMatWords).count
                    if matOverlap > 0 {
                        score += matOverlap * 3
                        reasons.append("Similar materials")
                    }
                }
            }

            let reason = reasons.isEmpty ? "" : reasons.prefix(2).joined(separator: " · ")
            return (p, score, reason)
        }

        return scored
            .filter { $0.1 >= minimumScore }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map { SimilarPatternResult(pattern: $0.0, score: $0.1, reason: $0.2) }
    }

    private static func normalizeTitle(_ title: String) -> String {
        title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .components(separatedBy: .alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
