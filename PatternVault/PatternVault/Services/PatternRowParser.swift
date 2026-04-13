//
//  PatternRowParser.swift
//  PatternVault
//

import Foundation

enum PatternRowParser {
    static func parseRows(from text: String) -> [ParsedRow] {
        let lines = text.components(separatedBy: .newlines)
        let rowPattern = #"^\s*(?:row|rows|rnd|round|r)\s*(\d+)\s*[:.]?\s*(.+)$"#
        let stitchCountPattern = #"\((\d+)\s*sts?\)"#
        let repeatPattern = #"(?:repeat|rep)\s+(?:rows?|rounds?)\s+\d+\s*[-–]\s*\d+\s*(\d+)\s*(?:times|x)"#
        let asteriskPattern = #"\*(.+?)\*"#
        guard let rowRegex = try? NSRegularExpression(pattern: rowPattern, options: [.caseInsensitive]) else { return [] }
        let stitchRegex = try? NSRegularExpression(pattern: stitchCountPattern, options: [.caseInsensitive])
        let repeatRegex = try? NSRegularExpression(pattern: repeatPattern, options: [.caseInsensitive])
        let asteriskRegex = try? NSRegularExpression(pattern: asteriskPattern, options: [])

        var rows: [ParsedRow] = []
        for line in lines {
            let nsLine = line as NSString
            let fullRange = NSRange(location: 0, length: nsLine.length)
            guard let match = rowRegex.firstMatch(in: line, options: [], range: fullRange),
                  let idRange = Range(match.range(at: 1), in: line),
                  let instructionRange = Range(match.range(at: 2), in: line),
                  let id = Int(line[idRange]) else {
                continue
            }

            let instruction = String(line[instructionRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let stitchCount: Int? = {
                guard let stitchRegex,
                      let stitchMatch = stitchRegex.firstMatch(in: line, options: [], range: fullRange),
                      let range = Range(stitchMatch.range(at: 1), in: line) else { return nil }
                return Int(line[range])
            }()

            let repeatCount: Int? = {
                guard let repeatRegex,
                      let repeatMatch = repeatRegex.firstMatch(in: line, options: [], range: fullRange),
                      let range = Range(repeatMatch.range(at: 1), in: line) else { return nil }
                return Int(line[range])
            }()

            // Detect asterisk-delimited repeat sections: *K1, kfb*
            let hasAsteriskRepeat: Bool = {
                guard let asteriskRegex else { return false }
                return asteriskRegex.firstMatch(in: line, options: [], range: fullRange) != nil
            }()

            let isRepeat = repeatCount != nil || hasAsteriskRepeat

            rows.append(
                ParsedRow(
                    id: id,
                    instruction: instruction,
                    stitchCount: stitchCount,
                    isRepeatStart: isRepeat,
                    repeatCount: repeatCount,
                    note: nil
                )
            )
        }
        return rows.sorted(by: { $0.id < $1.id })
    }

    /// Extracts the text content between asterisk markers in an instruction.
    /// Example: "*K1, kfb, k to last 2 sts, kfb, k1*" → "K1, kfb, k to last 2 sts, kfb, k1"
    static func extractAsteriskBody(from text: String) -> String? {
        let pattern = #"\*(.+?)\*"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
