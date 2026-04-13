//
//  ColorworkGrid.swift
//  PatternVault
//
//  Represents a colorwork knitting chart as a grid of colored cells.
//  Extracted from chart images using ColorworkGridDetector.
//

import SwiftUI

struct ColorworkGrid: Codable, Equatable {
    let rows: Int
    let columns: Int
    let palette: [YarnColor]
    let cellColors: [[Int]]  // 2D grid of palette indices, [row][column]

    struct YarnColor: Codable, Equatable, Hashable {
        let red: Double    // 0-1
        let green: Double  // 0-1
        let blue: Double   // 0-1
        var name: String?  // user-editable label ("MC", "CC1", etc.)

        var color: Color {
            Color(red: red, green: green, blue: blue)
        }

        var uiColor: UIColor {
            UIColor(red: red, green: green, blue: blue, alpha: 1)
        }

        func distance(to other: YarnColor) -> Double {
            let dr = red - other.red
            let dg = green - other.green
            let db = blue - other.blue
            return sqrt(dr * dr + dg * dg + db * db)
        }
    }

    func color(atRow row: Int, column col: Int) -> YarnColor? {
        guard row >= 0, row < rows, col >= 0, col < columns else { return nil }
        let idx = cellColors[row][col]
        guard idx >= 0, idx < palette.count else { return nil }
        return palette[idx]
    }
}
