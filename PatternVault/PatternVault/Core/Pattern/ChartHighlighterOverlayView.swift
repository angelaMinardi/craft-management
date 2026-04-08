//
//  ChartHighlighterOverlayView.swift
//  PatternVault
//

import SwiftUI
import UIKit

struct ChartHighlighterOverlayView: View {
    let highlight: ChartHighlight
    let rowValue: Int
    let columnValue: Int

    var body: some View {
        GeometryReader { geo in
            let scale = UIScreen.main.scale
            let rect = CGRect(
                x: geo.size.width * highlight.minX,
                y: geo.size.height * highlight.minY,
                width: geo.size.width * max(0.001, highlight.maxX - highlight.minX),
                height: geo.size.height * max(0.001, highlight.maxY - highlight.minY)
            )
            let gridRect = CGRect(
                x: rect.minX + rect.width * highlight.gridInsetLeft,
                y: rect.minY + rect.height * highlight.gridInsetTop,
                width: rect.width * max(0.001, 1 - highlight.gridInsetLeft - highlight.gridInsetRight),
                height: rect.height * max(0.001, 1 - highlight.gridInsetTop - highlight.gridInsetBottom)
            )

            let clampedRow = min(max(rowValue, 1), max(1, highlight.rows))
            let clampedCol = min(max(columnValue, 1), max(1, highlight.columns))
            let rowCount = max(1, highlight.rows)
            let colCount = max(1, highlight.columns)
            let rowHeight = gridRect.height / CGFloat(rowCount)
            let colWidth = gridRect.width / CGFloat(colCount)

            let snappedGridRect = snapRect(gridRect, scale: scale)
            // AI-extracted knitting charts are typically numbered from bottom-right:
            // row 1 starts at the bottom and column 1 starts at the right.
            // Manual highlights keep the legacy top-left indexing behavior.
            let usesBottomRightIndexing = highlight.isAIExtracted
            let rowMinY = usesBottomRightIndexing
                ? snap(snappedGridRect.maxY - rowHeight * CGFloat(clampedRow), scale: scale)
                : snap(snappedGridRect.minY + rowHeight * CGFloat(clampedRow - 1), scale: scale)
            let rowMaxY = usesBottomRightIndexing
                ? snap(snappedGridRect.maxY - rowHeight * CGFloat(clampedRow - 1), scale: scale)
                : snap(snappedGridRect.minY + rowHeight * CGFloat(clampedRow), scale: scale)
            let colMinX = usesBottomRightIndexing
                ? snap(snappedGridRect.maxX - colWidth * CGFloat(clampedCol), scale: scale)
                : snap(snappedGridRect.minX + colWidth * CGFloat(clampedCol - 1), scale: scale)
            let colMaxX = usesBottomRightIndexing
                ? snap(snappedGridRect.maxX - colWidth * CGFloat(clampedCol - 1), scale: scale)
                : snap(snappedGridRect.minX + colWidth * CGFloat(clampedCol), scale: scale)
            let snappedRowRect = CGRect(
                x: snappedGridRect.minX,
                y: rowMinY,
                width: snappedGridRect.width,
                height: max(1 / scale, rowMaxY - rowMinY)
            )
            let snappedColRect = CGRect(
                x: colMinX,
                y: snappedGridRect.minY,
                width: max(1 / scale, colMaxX - colMinX),
                height: snappedGridRect.height
            )

            ZStack(alignment: .topLeading) {
                Rectangle()
                    .path(in: rect)
                    .stroke(Theme.deepPlum.opacity(0.5), lineWidth: 2)

                Rectangle()
                    .path(in: snappedGridRect)
                    .stroke(Theme.deepPlum.opacity(0.3), lineWidth: 1)

                if highlight.isC2C {
                    Path { p in
                        let x = snappedGridRect.minX + colWidth * CGFloat(clampedCol - 1)
                        let y = snappedGridRect.maxY - rowHeight * CGFloat(clampedRow)
                        p.move(to: CGPoint(x: x, y: y + rowHeight))
                        p.addLine(to: CGPoint(x: x + colWidth, y: y))
                    }
                    .stroke(themeColor(highlight.rowColorName).opacity(0.9), lineWidth: 6)
                } else {
                    Rectangle()
                        .fill(themeColor(highlight.rowColorName).opacity(0.35))
                        .frame(width: snappedRowRect.width, height: snappedRowRect.height)
                        .position(
                            x: snappedRowRect.midX,
                            y: snappedRowRect.midY
                        )

                    Rectangle()
                        .fill(themeColor(highlight.columnColorName).opacity(0.25))
                        .frame(width: snappedColRect.width, height: snappedColRect.height)
                        .position(
                            x: snappedColRect.midX,
                            y: snappedColRect.midY
                        )
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func themeColor(_ name: String) -> Color {
        switch name {
        case "sageGreen": return Theme.sageGreen
        case "dustyBlue": return Theme.dustyBlue
        case "honey": return Theme.honey
        case "deepPlum": return Theme.deepPlum
        default: return Theme.softCoral
        }
    }

    private func snap(_ value: CGFloat, scale: CGFloat) -> CGFloat {
        (value * scale).rounded() / scale
    }

    private func snapRect(_ rect: CGRect, scale: CGFloat) -> CGRect {
        CGRect(
            x: snap(rect.minX, scale: scale),
            y: snap(rect.minY, scale: scale),
            width: max(1 / scale, snap(rect.width, scale: scale)),
            height: max(1 / scale, snap(rect.height, scale: scale))
        )
    }
}
