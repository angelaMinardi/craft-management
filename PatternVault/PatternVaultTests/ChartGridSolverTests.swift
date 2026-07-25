//
//  ChartGridSolverTests.swift
//  PatternVaultTests
//
//  Renders synthetic knitting colorwork charts (grid + row/column number
//  labels + title + legend) with known ground truth, then verifies the
//  deterministic lattice solver recovers dimensions, boundary, and per-cell
//  colors — including that its confidence score is honest.
//

import XCTest
@testable import CorvidCraft

final class ChartGridSolverTests: XCTestCase {

    // MARK: - Synthetic Chart Rendering

    private struct SyntheticChart {
        let rows: Int
        let cols: Int
        let cellSize: CGFloat
        let palette: [UIColor]
        /// Palette index per cell, row-major, top-left origin.
        let cellIndex: (_ row: Int, _ col: Int) -> Int
        var marginLeft: CGFloat = 10
        var marginTop: CGFloat = 44      // room for a title
        var marginRight: CGFloat = 34    // room for row numbers
        var marginBottom: CGFloat = 26   // room for column numbers
        var drawInteriorGridlines = true
        var drawLegend = false
        var labelDensity: Int = 1        // label every Nth row/column

        var gridRect: CGRect {
            CGRect(
                x: marginLeft, y: marginTop,
                width: CGFloat(cols) * cellSize, height: CGFloat(rows) * cellSize
            )
        }

        var imageSize: CGSize {
            CGSize(
                width: marginLeft + CGFloat(cols) * cellSize + marginRight + (drawLegend ? 120 : 0),
                height: marginTop + CGFloat(rows) * cellSize + marginBottom
            )
        }

        func render() -> UIImage {
            let size = imageSize
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let renderer = UIGraphicsImageRenderer(size: size, format: format)
            return renderer.image { ctx in
                let cg = ctx.cgContext
                cg.setFillColor(UIColor.white.cgColor)
                cg.fill(CGRect(origin: .zero, size: size))

                let grid = gridRect

                // Title
                draw(text: "Synthetic Sampler Chart", at: CGPoint(x: grid.minX, y: 10), size: 14, bold: true)

                // Cells
                for r in 0..<rows {
                    for c in 0..<cols {
                        let color = palette[cellIndex(r, c)]
                        cg.setFillColor(color.cgColor)
                        cg.fill(CGRect(
                            x: grid.minX + CGFloat(c) * cellSize,
                            y: grid.minY + CGFloat(r) * cellSize,
                            width: cellSize, height: cellSize
                        ))
                    }
                }

                // Gridlines
                cg.setStrokeColor(UIColor(white: 0.25, alpha: 1).cgColor)
                cg.setLineWidth(1)
                for r in 0...rows {
                    guard drawInteriorGridlines || r == 0 || r == rows else { continue }
                    let y = grid.minY + CGFloat(r) * cellSize
                    cg.move(to: CGPoint(x: grid.minX, y: y))
                    cg.addLine(to: CGPoint(x: grid.maxX, y: y))
                }
                for c in 0...cols {
                    guard drawInteriorGridlines || c == 0 || c == cols else { continue }
                    let x = grid.minX + CGFloat(c) * cellSize
                    cg.move(to: CGPoint(x: x, y: grid.minY))
                    cg.addLine(to: CGPoint(x: x, y: grid.maxY))
                }
                cg.strokePath()

                // Row numbers (right edge, chart-style bottom-up numbering)
                for r in stride(from: 0, to: rows, by: labelDensity) {
                    let y = grid.minY + CGFloat(r) * cellSize + cellSize / 2 - 5
                    draw(text: "\(rows - r)", at: CGPoint(x: grid.maxX + 4, y: y), size: 9, bold: false)
                }

                // Column numbers (bottom edge)
                for c in stride(from: 0, to: cols, by: labelDensity) {
                    let x = grid.minX + CGFloat(c) * cellSize + 1
                    draw(text: "\(cols - c)", at: CGPoint(x: x, y: grid.maxY + 4), size: 8, bold: false)
                }

                // Legend: swatch boxes + labels to the right of the row numbers
                if drawLegend {
                    let legendX = grid.maxX + marginRight + 8
                    for (i, color) in palette.enumerated() {
                        let y = grid.minY + CGFloat(i) * 26
                        cg.setFillColor(color.cgColor)
                        cg.fill(CGRect(x: legendX, y: y, width: 16, height: 16))
                        cg.setStrokeColor(UIColor.black.cgColor)
                        cg.stroke(CGRect(x: legendX, y: y, width: 16, height: 16))
                        draw(text: i == 0 ? "K with MC" : "K with C\(i)", at: CGPoint(x: legendX + 22, y: y + 2), size: 10, bold: false)
                    }
                }
            }
        }

        private func draw(text: String, at point: CGPoint, size: CGFloat, bold: Bool) {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: bold ? UIFont.boldSystemFont(ofSize: size) : UIFont.systemFont(ofSize: size),
                .foregroundColor: UIColor.black,
            ]
            (text as NSString).draw(at: point, withAttributes: attrs)
        }
    }

    private func rgb(_ color: UIColor) -> (r: Double, g: Double, b: Double) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b))
    }

    /// Fraction of cells whose solver-assigned palette color matches the
    /// ground-truth cell color (nearest-color matching).
    private func cellAccuracy(chart: SyntheticChart, colorwork: ColorworkGrid) -> Double {
        guard colorwork.rows == chart.rows, colorwork.columns == chart.cols else { return 0 }
        var correct = 0
        for r in 0..<chart.rows {
            for c in 0..<chart.cols {
                guard let got = colorwork.color(atRow: r, column: c) else { continue }
                let truth = rgb(chart.palette[chart.cellIndex(r, c)])
                let d = sqrt(
                    pow(got.red - truth.r, 2) + pow(got.green - truth.g, 2) + pow(got.blue - truth.b, 2)
                )
                if d < 0.25 { correct += 1 }
            }
        }
        return Double(correct) / Double(chart.rows * chart.cols)
    }

    private func assertBoundary(
        _ solution: ChartGridSolver.Solution,
        matches chart: SyntheticChart,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let size = chart.imageSize
        let grid = chart.gridRect
        let tolX = max(0.015, Double(chart.cellSize) / Double(size.width) * 0.5)
        let tolY = max(0.015, Double(chart.cellSize) / Double(size.height) * 0.5)

        XCTAssertEqual(solution.insetLeft, Double(grid.minX / size.width), accuracy: tolX, "left inset", file: file, line: line)
        XCTAssertEqual(solution.insetRight, Double(1 - grid.maxX / size.width), accuracy: tolX, "right inset", file: file, line: line)
        XCTAssertEqual(solution.insetTop, Double(grid.minY / size.height), accuracy: tolY, "top inset", file: file, line: line)
        XCTAssertEqual(solution.insetBottom, Double(1 - grid.maxY / size.height), accuracy: tolY, "bottom inset", file: file, line: line)
    }

    // MARK: - Fixtures

    /// Small two-color chart similar to the "Skull Sampler Toe" (11 rows × 8 cols).
    private var smallChart: SyntheticChart {
        SyntheticChart(
            rows: 11, cols: 8, cellSize: 24,
            palette: [UIColor(white: 0.15, alpha: 1), UIColor(red: 0.85, green: 0.55, blue: 0.55, alpha: 1)],
            cellIndex: { r, c in (r / 2 + c / 3) % 2 }
        )
    }

    /// Large dense chart similar to the "Skull Sampler Leg" (40 rows × 36 cols)
    /// with dense edge labels — the case that broke threshold-based detection.
    private var largeChart: SyntheticChart {
        SyntheticChart(
            rows: 40, cols: 36, cellSize: 14,
            palette: [
                UIColor(white: 0.1, alpha: 1),
                UIColor(red: 0.75, green: 0.2, blue: 0.25, alpha: 1),
                UIColor(red: 0.9, green: 0.85, blue: 0.7, alpha: 1),
            ],
            cellIndex: { r, c in (r * 5 + c * 3) / 7 % 3 }
        )
    }

    // MARK: - Tests

    func testSmallChart_dimensionsAndBoundary() throws {
        let chart = smallChart
        let solution = try XCTUnwrap(ChartGridSolver.solve(
            image: chart.render(), expectedRows: chart.rows, expectedColumns: chart.cols
        ))

        XCTAssertEqual(solution.rows, chart.rows)
        XCTAssertEqual(solution.columns, chart.cols)
        assertBoundary(solution, matches: chart)
        XCTAssertGreaterThanOrEqual(solution.confidence, 0.7, "clean chart should be high confidence")
    }

    func testSmallChart_withoutHints() throws {
        let chart = smallChart
        let solution = try XCTUnwrap(ChartGridSolver.solve(image: chart.render()))

        XCTAssertEqual(solution.rows, chart.rows)
        XCTAssertEqual(solution.columns, chart.cols)
        assertBoundary(solution, matches: chart)
    }

    func testSmallChart_cellColors() throws {
        let chart = smallChart
        let solution = try XCTUnwrap(ChartGridSolver.solve(
            image: chart.render(), expectedRows: chart.rows, expectedColumns: chart.cols
        ))

        let colorwork = try XCTUnwrap(solution.colorwork, "two-color chart should yield a colorwork grid")
        XCTAssertEqual(colorwork.palette.count, 2)
        XCTAssertGreaterThanOrEqual(cellAccuracy(chart: chart, colorwork: colorwork), 0.97)
    }

    func testLargeDenseChart_dimensionsBoundaryAndColors() throws {
        let chart = largeChart
        let solution = try XCTUnwrap(ChartGridSolver.solve(
            image: chart.render(), expectedRows: chart.rows, expectedColumns: chart.cols
        ))

        XCTAssertEqual(solution.rows, chart.rows)
        XCTAssertEqual(solution.columns, chart.cols)
        assertBoundary(solution, matches: chart)

        let colorwork = try XCTUnwrap(solution.colorwork)
        XCTAssertEqual(colorwork.palette.count, 3)
        XCTAssertGreaterThanOrEqual(cellAccuracy(chart: chart, colorwork: colorwork), 0.97)
    }

    func testChartWithLegend_excludesLegendFromGrid() throws {
        var chart = smallChart
        chart.drawLegend = true
        let solution = try XCTUnwrap(ChartGridSolver.solve(
            image: chart.render(), expectedRows: chart.rows, expectedColumns: chart.cols
        ))

        XCTAssertEqual(solution.columns, chart.cols, "legend swatches must not extend the grid")
        assertBoundary(solution, matches: chart)
    }

    func testMisleadingPrior_stillFindsBoundary() throws {
        let chart = smallChart
        let size = chart.imageSize
        let grid = chart.gridRect
        // Prior shifted well off the true grid on two edges.
        let prior = try XCTUnwrap(ChartGridSolver.PriorRegion(
            xMin: Double(grid.minX / size.width) + 0.10,
            yMin: Double(grid.minY / size.height) + 0.10,
            xMax: min(1, Double(grid.maxX / size.width) + 0.10),
            yMax: min(1, Double(grid.maxY / size.height) + 0.10)
        ))
        let solution = try XCTUnwrap(ChartGridSolver.solve(
            image: chart.render(), expectedRows: chart.rows, expectedColumns: chart.cols, prior: prior
        ))

        XCTAssertEqual(solution.rows, chart.rows)
        XCTAssertEqual(solution.columns, chart.cols)
        assertBoundary(solution, matches: chart)
    }

    func testDeterminism_sameImageSameResult() throws {
        let chart = largeChart
        let image = chart.render()
        let a = try XCTUnwrap(ChartGridSolver.solve(image: image, expectedRows: chart.rows, expectedColumns: chart.cols))
        let b = try XCTUnwrap(ChartGridSolver.solve(image: image, expectedRows: chart.rows, expectedColumns: chart.cols))

        XCTAssertEqual(a.rows, b.rows)
        XCTAssertEqual(a.columns, b.columns)
        XCTAssertEqual(a.insetLeft, b.insetLeft)
        XCTAssertEqual(a.insetTop, b.insetTop)
        XCTAssertEqual(a.insetRight, b.insetRight)
        XCTAssertEqual(a.insetBottom, b.insetBottom)
        XCTAssertEqual(a.confidence, b.confidence)
        XCTAssertEqual(a.colorwork, b.colorwork)
    }

    /// Honest-confidence contract: when the solver claims high confidence, its
    /// dimensions must be right. A chart with no interior gridlines is allowed
    /// to fail or return low confidence — it must not confidently return
    /// wrong dimensions.
    func testNoInteriorGridlines_confidenceIsHonest() {
        var chart = smallChart
        chart.drawInteriorGridlines = false
        let solution = ChartGridSolver.solve(
            image: chart.render(), expectedRows: chart.rows, expectedColumns: chart.cols
        )

        if let solution, solution.confidence >= 0.7 {
            XCTAssertEqual(solution.rows, chart.rows)
            XCTAssertEqual(solution.columns, chart.cols)
        }
    }

    func testTinyOrEmptyImage_returnsNil() {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let tiny = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10), format: format)
            .image { ctx in
                ctx.cgContext.setFillColor(UIColor.white.cgColor)
                ctx.cgContext.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
            }
        XCTAssertNil(ChartGridSolver.solve(image: tiny))

        let blank = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 300), format: format)
            .image { ctx in
                ctx.cgContext.setFillColor(UIColor.white.cgColor)
                ctx.cgContext.fill(CGRect(x: 0, y: 0, width: 300, height: 300))
            }
        XCTAssertNil(ChartGridSolver.solve(image: blank), "featureless image must not produce a grid")
    }
}
