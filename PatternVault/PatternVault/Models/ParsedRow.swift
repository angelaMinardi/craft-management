//
//  ParsedRow.swift
//  PatternVault
//
//  Structured row data extracted from pattern content by AI or heuristic parser.
//

import Foundation

struct ParsedRow: Codable, Identifiable, Equatable, Sendable {
    let id: Int              // row number (1-based)
    let instruction: String  // "K2, P2 across, K2"
    let stitchCount: Int?    // optional stitch count
    let isRepeatStart: Bool  // marks beginning of a repeat section
    let repeatCount: Int?    // "repeat 6 times" -> 6
    let note: String?        // inline note/reminder (e.g. "Switch to Color B")

    init(id: Int, instruction: String, stitchCount: Int? = nil, isRepeatStart: Bool = false, repeatCount: Int? = nil, note: String? = nil) {
        self.id = id
        self.instruction = instruction
        self.stitchCount = stitchCount
        self.isRepeatStart = isRepeatStart
        self.repeatCount = repeatCount
        self.note = note
    }
}
