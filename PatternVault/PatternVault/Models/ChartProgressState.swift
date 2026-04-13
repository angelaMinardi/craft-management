//
//  ChartProgressState.swift
//  PatternVault
//
//  Tracks knitting mode progress for a chart highlight.
//

import Foundation

struct ChartProgressState: Codable, Equatable {
    var completedRows: Set<Int> = []
    var knittingModeRow: Int = 1
    var rowNotes: [Int: String] = [:]  // row number → user note text
}
