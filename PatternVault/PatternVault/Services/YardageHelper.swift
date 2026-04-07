//
//  YardageHelper.swift
//  PatternVault
//
//  Parses required yardage from pattern text and compares to stash for "enough / short / left".
//

import Foundation

/// Result of comparing stash yardage to pattern requirement.
enum YardageComparison {
    case enough
    case short(Int)
    case left(Int)
    case unknown

    var summary: String {
        switch self {
        case .enough: return "Enough"
        case .short(let n): return "~\(n) yd short"
        case .left(let n): return "~\(n) yd left"
        case .unknown: return "—"
        }
    }
}

enum YardageHelper {
    private static let yardagePattern = try? NSRegularExpression(
        pattern: #"(\d{1,6})\s*(?:yards?|yd\.?)\b"#,
        options: .caseInsensitive
    )

    /// Extract a single required yardage (e.g. "400 yards" or "400 yd") from pattern's yarnWeightYardage or materials.
    /// Returns the first number found, or nil if none.
    static func parseRequiredYardage(from pattern: Pattern) -> Int? {
        let sources = [pattern.yarnWeightYardage, pattern.materials].compactMap { $0 }.filter { !$0.isEmpty }
        for text in sources {
            if let yd = parseYardageFromText(text) { return yd }
        }
        return nil
    }

    private static func parseYardageFromText(_ text: String) -> Int? {
        guard let regex = yardagePattern else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let captureRange = Range(match.range(at: 1), in: text) else { return nil }
        return Int(text[captureRange])
    }

    /// Compare stash total yardage to pattern requirement. Returns .unknown if either side is missing.
    static func compare(stashYardage: Int?, requiredYardage: Int?) -> YardageComparison {
        guard let stash = stashYardage, let required = requiredYardage, required > 0 else { return .unknown }
        if stash >= required {
            return stash - required > 0 ? .left(stash - required) : .enough
        }
        return .short(required - stash)
    }
}
