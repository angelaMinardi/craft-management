//
//  RepeatInfo.swift
//  PatternVault
//
//  Structured metadata for pattern repeat instructions.
//  Extracted by AI from instructions like "Rep rnds 1 & 2 until 28 (32, 36) sts"
//  or asterisk-delimited repeats like "*K1, kfb* rep from *".
//

import Foundation

struct RepeatInfo: Codable, Equatable, Sendable {

    enum RepeatType: String, Codable, Sendable {
        case rowRange      // "Repeat rows 3-4"
        case untilCount    // "Rep until you have 28 sts"
        case untilMeasure  // "Continue until piece measures 7 inches"
        case fixedCount    // "Repeat 6 times"
        case asterisk      // "*K1, kfb* rep from *"
    }

    let type: RepeatType

    /// Row numbers referenced by the repeat (e.g., 1 and 2 in "rep rnds 1 & 2").
    /// These are section-relative row numbers matching startRow/endRow on other instructions.
    let referencedStartRow: Int?
    let referencedEndRow: Int?

    /// For fixedCount: how many times to repeat. For asterisk: how many times the * block runs.
    let fixedRepeatCount: Int?

    /// Target stitch counts for multi-size patterns. Index 0 = smallest size.
    /// Example: "28 (32, 36) sts" → [28, 32, 36]
    let targetStitchCounts: [Int]?

    /// Target measurement for untilMeasure type.
    /// Example: "7 inches" or "18 cm"
    let targetMeasurement: String?

    /// Net stitch change per complete cycle of the referenced rows.
    /// Positive = increase, negative = decrease. Example: +4 for "increase 4 sts per rnd"
    let stitchesPerCycle: Int?

    /// The text content between asterisk markers.
    /// Example: "K1, kfb, k to last 2 sts, kfb, k1" from "*K1, kfb, k to last 2 sts, kfb, k1*"
    let asteriskBody: String?

    enum CodingKeys: String, CodingKey {
        case type
        case referencedStartRow = "referenced_start_row"
        case referencedEndRow = "referenced_end_row"
        case fixedRepeatCount = "fixed_repeat_count"
        case targetStitchCounts = "target_stitch_counts"
        case targetMeasurement = "target_measurement"
        case stitchesPerCycle = "stitches_per_cycle"
        case asteriskBody = "asterisk_body"
    }

    // MARK: - Size Helpers

    /// Returns the target stitch count for the given size index (0-based).
    /// Falls back to the first (smallest) size if index is nil or out of range.
    func targetStitchCount(forSizeIndex index: Int?) -> Int? {
        guard let counts = targetStitchCounts, !counts.isEmpty else { return nil }
        let i = min(index ?? 0, counts.count - 1)
        return counts[max(0, i)]
    }

    /// Estimates how many complete cycles are needed to reach the target stitch count.
    /// Returns nil if insufficient information (no target, no stitchesPerCycle, or stitchesPerCycle == 0).
    func estimatedCycles(startingStitches: Int, sizeIndex: Int?) -> Int? {
        guard let target = targetStitchCount(forSizeIndex: sizeIndex),
              let perCycle = stitchesPerCycle, perCycle != 0 else { return nil }
        let remaining = target - startingStitches
        guard remaining > 0 else { return 0 }
        return Int(ceil(Double(remaining) / Double(abs(perCycle))))
    }

    /// The number of rows in one complete cycle of the repeat.
    var cycleLength: Int? {
        guard let start = referencedStartRow, let end = referencedEndRow else { return nil }
        return max(1, end - start + 1)
    }

    // MARK: - Heuristic Detection from Text

    /// Attempts to parse repeat metadata from instruction text.
    /// Handles patterns like:
    ///   "Rep rnds 1 & 2 until you have 28 (32, 36) sts"
    ///   "Repeat rows 3-4, 6 times"
    ///   "Continue in pattern until piece measures 7 inches"
    static func detect(from text: String) -> RepeatInfo? {
        let lower = text.lowercased()

        // Extract row references first (shared across patterns)
        let rowRefPattern = #"(?:rep(?:eat)?)\s+(?:rnds?|rounds?|rows?)\s+(\d+)\s*(?:&|and|-|–)\s*(\d+)"#
        let rowRefRegex = try? NSRegularExpression(pattern: rowRefPattern, options: .caseInsensitive)
        let rowRefMatch = rowRefRegex?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
        let refStartRow = rowRefMatch.flatMap { extractInt(from: text, match: $0, group: 1) }
        let refEndRow = rowRefMatch.flatMap { extractInt(from: text, match: $0, group: 2) }

        // Extract ALL "N (M, L) sts" groups from the text — use the LAST one as the target.
        // "28 (32, 36) sts on each needle for a total of 56 (64, 72) sts" → we want [56, 64, 72]
        let stsGroupPattern = #"(\d+)\s*\((\d+),\s*(\d+)\)\s*sts"#
        var allStitchGroups: [[Int]] = []
        if let stsRegex = try? NSRegularExpression(pattern: stsGroupPattern, options: .caseInsensitive) {
            let matches = stsRegex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches {
                let vals = [
                    extractInt(from: text, match: match, group: 1),
                    extractInt(from: text, match: match, group: 2),
                    extractInt(from: text, match: match, group: 3)
                ].compactMap { $0 }
                if !vals.isEmpty { allStitchGroups.append(vals) }
            }
        }

        // Also try "total of N sts" for single-size patterns
        let totalStsPattern = #"total\s+(?:of\s+)?(\d+)\s*sts"#
        let singleTotalSts: Int? = {
            guard let regex = try? NSRegularExpression(pattern: totalStsPattern, options: .caseInsensitive),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
            return extractInt(from: text, match: match, group: 1)
        }()

        // Pattern 1: "rep rnds X & Y until ... sts" (with or without multi-size)
        if lower.contains("until") && refStartRow != nil {
            // Use the LAST stitch group (which is usually the total), or fall back to single total
            let targetCounts: [Int]? = {
                if let last = allStitchGroups.last { return last }
                if let single = singleTotalSts { return [single] }
                // Fall back to single "N sts" at end of text
                let simpleStsPattern = #"(\d+)\s*sts"#
                if let regex = try? NSRegularExpression(pattern: simpleStsPattern, options: .caseInsensitive) {
                    let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
                    if let last = matches.last, let val = extractInt(from: text, match: last, group: 1) {
                        return [val]
                    }
                }
                return nil
            }()

            // Try to extract stitches per cycle from the referenced round instructions
            // Look for "(N sts inc)" or "(N sts dec)" patterns
            let perCyclePattern = #"\((\d+)\s*sts?\s*(?:inc(?:rease)?|dec(?:rease)?)\)"#
            let perCycle: Int? = {
                guard let regex = try? NSRegularExpression(pattern: perCyclePattern, options: .caseInsensitive),
                      let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
                return extractInt(from: text, match: match, group: 1)
            }()

            return RepeatInfo(
                type: .untilCount,
                referencedStartRow: refStartRow,
                referencedEndRow: refEndRow,
                fixedRepeatCount: nil,
                targetStitchCounts: targetCounts,
                targetMeasurement: nil,
                stitchesPerCycle: perCycle,
                asteriskBody: nil
            )
        }

        // Pattern 2: "repeat rows X-Y, N times" or "repeat rows X-Y N times"
        let repFixedPattern = #"(?:rep(?:eat)?)\s+(?:rnds?|rounds?|rows?)\s+(\d+)\s*[-–&]\s*(\d+)[,\s]+(\d+)\s*(?:times|x)"#
        if let regex = try? NSRegularExpression(pattern: repFixedPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
            let startRow = extractInt(from: text, match: match, group: 1)
            let endRow = extractInt(from: text, match: match, group: 2)
            let count = extractInt(from: text, match: match, group: 3)
            if let s = startRow, let e = endRow {
                return RepeatInfo(
                    type: .fixedCount,
                    referencedStartRow: s,
                    referencedEndRow: e,
                    fixedRepeatCount: count,
                    targetStitchCounts: nil,
                    targetMeasurement: nil,
                    stitchesPerCycle: nil,
                    asteriskBody: nil
                )
            }
        }

        // Pattern 3: "continue ... until piece measures X inches/cm"
        let measurePattern = #"(?:continue|work|rep(?:eat)?)\s+.*?until\s+.*?measures?\s+([\d.]+\s*(?:inches?|in|cm|centimeters?))"#
        if let regex = try? NSRegularExpression(pattern: measurePattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let range = Range(match.range(at: 1), in: text) {
            return RepeatInfo(
                type: .untilMeasure,
                referencedStartRow: nil,
                referencedEndRow: nil,
                fixedRepeatCount: nil,
                targetStitchCounts: nil,
                targetMeasurement: String(text[range]),
                stitchesPerCycle: nil,
                asteriskBody: nil
            )
        }

        // Pattern 4: "knit/work N (more) rnds/rows" — a multi-round instruction
        // Matches: "Knit 4 more rnds", "Work 6 rounds", "K 10 rnds", "Knit 4 more rnds st st in C1"
        let workNPattern = #"(?:knit|work|k)\s+(\d+)\s+(?:more\s+)?(?:rnds?|rounds?|rows?)"#
        if let regex = try? NSRegularExpression(pattern: workNPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let count = extractInt(from: text, match: match, group: 1), count >= 2 {
            return RepeatInfo(
                type: .fixedCount,
                referencedStartRow: nil,
                referencedEndRow: nil,
                fixedRepeatCount: count,
                targetStitchCounts: nil,
                targetMeasurement: nil,
                stitchesPerCycle: nil,
                asteriskBody: nil
            )
        }

        // Pattern 5: "work/complete rnds X – Y" or "work rows X-Y" — a range of rounds to work
        // Matches: "work rnds 1 – 17 of the Skull Sampler Leg Chart"
        //          "complete rnds 18 – 39", "work rows 1-11", "work rounds 1 – 39"
        let workRangePattern = #"(?:work|complete)\s+(?:all\s+)?(?:rnds?|rounds?|rows?)\s+(\d+)\s*[-–]\s*(\d+)"#
        if let regex = try? NSRegularExpression(pattern: workRangePattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
            let startRnd = extractInt(from: text, match: match, group: 1)
            let endRnd = extractInt(from: text, match: match, group: 2)
            if let s = startRnd, let e = endRnd, e > s {
                let count = e - s + 1
                return RepeatInfo(
                    type: .fixedCount,
                    referencedStartRow: nil,
                    referencedEndRow: nil,
                    fixedRepeatCount: count,
                    targetStitchCounts: nil,
                    targetMeasurement: nil,
                    stitchesPerCycle: nil,
                    asteriskBody: nil
                )
            }
        }

        // Pattern 6: "work all rounds of the [Chart Name]" — needs chart row count from context
        // We detect the pattern and mark it as a chart-based repeat; the view resolves the count
        // from chart metadata. For now, look for a row count in the same text like "11 rows" or "39 rows".
        if lower.contains("work all rounds of") || lower.contains("work all rnds of") {
            // Try to find a row/round count nearby: "The chart is 11 rows" or chart dimensions
            let chartRowPattern = #"(\d+)\s*(?:rows?|rnds?|rounds?)\s*(?:×|x|\*)\s*\d+"#
            let simpleCountPattern = #"chart.*?(\d+)\s*(?:rows?|rnds?|rounds?)"#
            var chartRounds: Int?
            if let regex = try? NSRegularExpression(pattern: chartRowPattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
                chartRounds = extractInt(from: text, match: match, group: 1)
            }
            if chartRounds == nil,
               let regex = try? NSRegularExpression(pattern: simpleCountPattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
                chartRounds = extractInt(from: text, match: match, group: 1)
            }
            if let count = chartRounds, count >= 2 {
                return RepeatInfo(
                    type: .fixedCount,
                    referencedStartRow: nil,
                    referencedEndRow: nil,
                    fixedRepeatCount: count,
                    targetStitchCounts: nil,
                    targetMeasurement: nil,
                    stitchesPerCycle: nil,
                    asteriskBody: nil
                )
            }
        }

        // Pattern 7: "rep rnds X & Y" without explicit condition (open-ended)
        let repOpenPattern = #"(?:rep(?:eat)?)\s+(?:rnds?|rounds?|rows?)\s+(\d+)\s*(?:&|and|-|–)\s*(\d+)"#
        if let regex = try? NSRegularExpression(pattern: repOpenPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
            let startRow = extractInt(from: text, match: match, group: 1)
            let endRow = extractInt(from: text, match: match, group: 2)
            if let s = startRow, let e = endRow {
                return RepeatInfo(
                    type: .rowRange,
                    referencedStartRow: s,
                    referencedEndRow: e,
                    fixedRepeatCount: nil,
                    targetStitchCounts: nil,
                    targetMeasurement: nil,
                    stitchesPerCycle: nil,
                    asteriskBody: nil
                )
            }
        }

        return nil
    }

    private static func extractInt(from text: String, match: NSTextCheckingResult, group: Int) -> Int? {
        guard let range = Range(match.range(at: group), in: text) else { return nil }
        return Int(text[range])
    }
}
