//
//  ContentBlockParser.swift
//  PatternVault
//
//  Splits pattern sourceContent into fine-grained, independently addressable blocks
//  for the content cleanup edit mode. Each block (sentence, bullet, table row, heading)
//  can be individually removed by the user.
//

import Foundation

// MARK: - Models

enum ContentBlockKind: Equatable {
    case heading
    case sentence
    case bullet
    case tableRow
    /// Invisible marker used to track paragraph boundaries for reassembly.
    case paragraphBreak
}

struct ContentBlock: Identifiable, Equatable {
    let id: Int
    let text: String
    let kind: ContentBlockKind
    /// Which original paragraph group (split by \n\n) this block came from.
    /// Used during reassembly to know when to insert \n\n vs space.
    let groupIndex: Int
}

// MARK: - Parser

enum ContentBlockParser {

    /// Parses raw `sourceContent` into atomic blocks that can each be independently removed.
    static func parse(_ content: String) -> [ContentBlock] {
        let decoded = decodeHTMLEntities(content)
        let rawGroups = decoded.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var blocks: [ContentBlock] = []
        var nextId = 0

        for (groupIdx, group) in rawGroups.enumerated() {
            // Insert paragraph break marker between groups (not before first)
            if groupIdx > 0 {
                blocks.append(ContentBlock(id: nextId, text: "", kind: .paragraphBreak, groupIndex: groupIdx))
                nextId += 1
            }

            let lines = group.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

            // Detect block type
            let pipeLines = lines.filter { $0.contains(" | ") || $0.hasPrefix("| ") }
            let bulletLines = lines.filter { $0.hasPrefix("- ") }

            if pipeLines.count >= 2 {
                // Table: each row is its own block
                for line in lines {
                    blocks.append(ContentBlock(id: nextId, text: line, kind: .tableRow, groupIndex: groupIdx))
                    nextId += 1
                }
            } else if bulletLines.count > 0 {
                // Bullet list: each bullet is its own block
                for line in lines {
                    if line.hasPrefix("- ") {
                        blocks.append(ContentBlock(id: nextId, text: line, kind: .bullet, groupIndex: groupIdx))
                    } else {
                        // Non-bullet line in a bullet context (e.g. a heading before the list)
                        blocks.append(ContentBlock(id: nextId, text: line, kind: .sentence, groupIndex: groupIdx))
                    }
                    nextId += 1
                }
            } else if lines.count == 1 && lines[0].count < 60
                        && !lines[0].hasSuffix(".") && !lines[0].hasSuffix(",")
                        && !lines[0].hasSuffix("!") && !lines[0].hasSuffix("?") {
                // Heading: single short line without trailing punctuation
                blocks.append(ContentBlock(id: nextId, text: lines[0], kind: .heading, groupIndex: groupIdx))
                nextId += 1
            } else {
                // Paragraph: split into individual lines, then further split long lines into sentences
                for line in lines {
                    if line.count > 200 {
                        let sentences = splitIntoSentences(line)
                        for sentence in sentences {
                            let trimmed = sentence.trimmingCharacters(in: .whitespaces)
                            if !trimmed.isEmpty {
                                blocks.append(ContentBlock(id: nextId, text: trimmed, kind: .sentence, groupIndex: groupIdx))
                                nextId += 1
                            }
                        }
                    } else {
                        blocks.append(ContentBlock(id: nextId, text: line, kind: .sentence, groupIndex: groupIdx))
                        nextId += 1
                    }
                }
            }
        }

        return blocks
    }

    /// Reassembles content from blocks, excluding the given IDs.
    static func reassemble(blocks: [ContentBlock], excluding removedIds: Set<Int>) -> String {
        let kept = blocks.filter { !removedIds.contains($0.id) && $0.kind != .paragraphBreak }
        if kept.isEmpty { return "" }

        var result: [String] = []
        var currentGroup = kept[0].groupIndex
        var currentGroupLines: [String] = []

        for block in kept {
            if block.groupIndex != currentGroup {
                // New group — flush previous
                if !currentGroupLines.isEmpty {
                    result.append(joinGroupLines(currentGroupLines))
                    currentGroupLines = []
                }
                currentGroup = block.groupIndex
            }
            currentGroupLines.append(block.text)
        }
        // Flush last group
        if !currentGroupLines.isEmpty {
            result.append(joinGroupLines(currentGroupLines))
        }

        return result.joined(separator: "\n\n")
    }

    /// Counts how many pattern-content indicators a text block matches.
    /// If ≥2, the block likely contains real pattern instructions and the user should be warned before removal.
    static func patternContentIndicatorCount(_ text: String) -> Int {
        let lower = text.lowercased()
        var count = 0

        // Stitch abbreviations
        let stitchAbbrevs = ["k2tog", "ssk", "sl st", "yo ", " sc", " dc", " hdc", " ch ", " inc", " dec", " pm", " sm"]
        let boCoPattern = #"\b(BO|CO)\b"#
        if stitchAbbrevs.contains(where: { lower.contains($0) }) { count += 1 }
        if text.range(of: boCoPattern, options: .regularExpression) != nil { count += 1 }

        // Row/round instructions
        let rowPattern = #"(?i)^(Row|Round|Rnd|R)\s*\d+"#
        let repeatPattern = #"(?i)repeat\s+.*\s+times"#
        if text.range(of: rowPattern, options: .regularExpression) != nil { count += 1 }
        if text.range(of: repeatPattern, options: .regularExpression) != nil { count += 1 }

        // Stitch counts in parens
        let stitchCountPattern = #"\(\d+\s*(st|sts|stitches)\)"#
        if text.range(of: stitchCountPattern, options: .regularExpression) != nil { count += 1 }

        // Gauge-like text
        let gaugePattern = #"\d+\s*(sts?|rows?)\s*=\s*\d+"#
        if text.range(of: gaugePattern, options: .regularExpression) != nil { count += 1 }

        // Size references
        let sizePattern = #"(?i)\b(XS|XXL)\b|\d+\"\s*chest"#
        if text.range(of: sizePattern, options: .regularExpression) != nil { count += 1 }

        // Measurements
        let measurePattern = #"\d+(\.\d+)?\s*(cm|mm|in|inch|yards?|yds?|meters?|grams?|oz)\b"#
        if text.range(of: measurePattern, options: .regularExpression) != nil { count += 1 }

        return count
    }

    // MARK: - Private Helpers

    /// Splits a long line into sentences at `. `, `? `, `! ` boundaries.
    private static func splitIntoSentences(_ text: String) -> [String] {
        // Use regex to split at sentence boundaries while keeping the delimiter with the preceding sentence
        var sentences: [String] = []
        var current = ""

        let chars = Array(text)
        var i = 0
        while i < chars.count {
            current.append(chars[i])

            // Check for sentence boundary: punctuation followed by space and uppercase letter (or end)
            if (chars[i] == "." || chars[i] == "?" || chars[i] == "!") {
                let nextIdx = i + 1
                if nextIdx >= chars.count {
                    // End of text
                    sentences.append(current)
                    current = ""
                } else if chars[nextIdx] == " " {
                    // Check if next non-space char is uppercase or it's a clear sentence break
                    let afterSpace = nextIdx + 1
                    if afterSpace < chars.count && chars[afterSpace].isUppercase {
                        sentences.append(current)
                        current = ""
                        i += 1 // skip the space
                    }
                    // Otherwise, might be abbreviation (e.g., "St. Patrick") — don't split
                }
            }
            i += 1
        }

        if !current.trimmingCharacters(in: .whitespaces).isEmpty {
            sentences.append(current)
        }

        return sentences
    }

    private static func joinGroupLines(_ lines: [String]) -> String {
        // If all lines are bullets, join with newline
        if lines.allSatisfy({ $0.hasPrefix("- ") }) {
            return lines.joined(separator: "\n")
        }
        // If lines contain pipe separators (table), join with newline
        if lines.contains(where: { $0.contains(" | ") || $0.hasPrefix("| ") }) {
            return lines.joined(separator: "\n")
        }
        // Otherwise join with newline (preserving line structure within a paragraph)
        return lines.joined(separator: "\n")
    }

    private static func decodeHTMLEntities(_ text: String) -> String {
        var result = text
        let entities: [(String, String)] = [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"),
            ("&nbsp;", " "), ("&hellip;", "…"), ("&mdash;", "—"), ("&ndash;", "–")
        ]
        for (entity, replacement) in entities {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        return result
    }
}
