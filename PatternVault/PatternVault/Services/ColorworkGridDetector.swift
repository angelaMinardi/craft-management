//
//  ColorworkGridDetector.swift
//  PatternVault
//
//  Extracts colorwork chart data from a chart image using traditional
//  computer vision: K-means color clustering, color-based edge detection,
//  autocorrelation grid spacing, and per-cell color sampling.
//
//  This replaces ChartGridDetector's luminance-based pixel refinement
//  which fails on colorwork charts (colored cells have similar brightness).
//

import UIKit
import Accelerate

struct ColorworkGridDetector {

    struct DetectionResult {
        let grid: ColorworkGrid
        let gridInsets: (left: Double, top: Double, right: Double, bottom: Double)
        let detectedRows: Int
        let detectedColumns: Int
    }

    // MARK: - Public API

    /// Detects colorwork grid structure and extracts per-cell colors.
    /// `expectedRows`/`expectedCols` are hints from AI first-pass detection (optional).
    static func detect(
        image: UIImage,
        expectedRows: Int? = nil,
        expectedCols: Int? = nil
    ) -> DetectionResult? {
        guard let cgImage = image.cgImage else { return nil }

        let width = cgImage.width
        let height = cgImage.height
        guard width > 20, height > 20 else { return nil }

        // 1. Render to RGBA pixel buffer
        let bpp = 4
        let bytesPerRow = width * bpp
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        guard let ctx = CGContext(
            data: &pixels, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.setFillColor(UIColor.white.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // 2. Detect grid cell spacing via color-edge autocorrelation
        let edgeMap = computeColorEdgeMap(pixels: pixels, width: width, height: height, bpp: bpp)
        guard let cellWidth = detectSpacing(edgeMap: edgeMap, width: width, height: height, axis: .horizontal, expectedCount: expectedCols),
              let cellHeight = detectSpacing(edgeMap: edgeMap, width: width, height: height, axis: .vertical, expectedCount: expectedRows) else {
            #if DEBUG
            print("[ColorworkGrid] Failed to detect cell spacing")
            #endif
            return nil
        }

        // 3. Find grid boundaries from edge density
        let gridBounds = findGridBounds(
            edgeMap: edgeMap,
            width: width, height: height,
            cellWidth: cellWidth, cellHeight: cellHeight
        )

        // 4. Compute rows and columns from bounds and cell size
        let gridW = gridBounds.maxX - gridBounds.minX
        let gridH = gridBounds.maxY - gridBounds.minY
        var cols = max(1, Int(round(Double(gridW) / cellWidth)))
        var rows = max(1, Int(round(Double(gridH) / cellHeight)))

        // Use expected values if close to detected
        if let ec = expectedCols, abs(ec - cols) <= 2 { cols = ec }
        if let er = expectedRows, abs(er - rows) <= 2 { rows = er }

        // Recompute exact cell size from grid bounds and final row/col count
        let exactCellW = Double(gridW) / Double(cols)
        let exactCellH = Double(gridH) / Double(rows)

        // 5. Sample colors from cell centers
        let rawColors = sampleCellColors(
            pixels: pixels, width: width, height: height, bpp: bpp,
            gridBounds: gridBounds,
            rows: rows, cols: cols,
            cellWidth: exactCellW, cellHeight: exactCellH
        )

        // 6. K-means clustering to find the yarn palette
        let allColors = rawColors.flatMap { $0 }
        let maxK = min(8, max(2, Set(allColors.map { quantizeColor($0) }).count))
        let (palette, assignments) = kMeansCluster(colors: allColors, k: maxK)

        // Reshape assignments back to 2D grid
        var cellColors: [[Int]] = []
        var idx = 0
        for r in 0..<rows {
            var row: [Int] = []
            for _ in 0..<cols {
                row.append(idx < assignments.count ? assignments[idx] : 0)
                idx += 1
            }
            cellColors.append(row)
            _ = r  // silence unused warning
        }

        // Build palette
        let yarnPalette = palette.enumerated().map { (i, rgb) in
            ColorworkGrid.YarnColor(
                red: rgb.r, green: rgb.g, blue: rgb.b,
                name: i == 0 ? "MC" : "CC\(i)"
            )
        }

        let grid = ColorworkGrid(
            rows: rows,
            columns: cols,
            palette: yarnPalette,
            cellColors: cellColors
        )

        let insets = (
            left: Double(gridBounds.minX) / Double(width),
            top: Double(gridBounds.minY) / Double(height),
            right: 1.0 - Double(gridBounds.maxX) / Double(width),
            bottom: 1.0 - Double(gridBounds.maxY) / Double(height)
        )

        #if DEBUG
        print("[ColorworkGrid] Detected \(rows)x\(cols) grid, \(palette.count) colors, cell size \(String(format:"%.1f",exactCellW))x\(String(format:"%.1f",exactCellH))px")
        #endif

        return DetectionResult(
            grid: grid,
            gridInsets: insets,
            detectedRows: rows,
            detectedColumns: cols
        )
    }

    // MARK: - Color Edge Map

    /// Computes a color-based edge magnitude map.
    /// Uses Sobel-like gradient on RGB channels independently, then sums.
    /// This detects boundaries between differently-colored cells even when
    /// they have similar luminance (where grayscale edge detection fails).
    private static func computeColorEdgeMap(
        pixels: [UInt8], width: Int, height: Int, bpp: Int
    ) -> [Double] {
        let bytesPerRow = width * bpp
        var edgeMap = [Double](repeating: 0, count: width * height)

        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                var totalGrad = 0.0

                for channel in 0..<3 {
                    // Sobel horizontal gradient
                    let tl = Double(pixels[(y-1) * bytesPerRow + (x-1) * bpp + channel])
                    let ml = Double(pixels[y * bytesPerRow + (x-1) * bpp + channel])
                    let bl = Double(pixels[(y+1) * bytesPerRow + (x-1) * bpp + channel])
                    let tr = Double(pixels[(y-1) * bytesPerRow + (x+1) * bpp + channel])
                    let mr = Double(pixels[y * bytesPerRow + (x+1) * bpp + channel])
                    let br = Double(pixels[(y+1) * bytesPerRow + (x+1) * bpp + channel])

                    let gx = (-tl - 2*ml - bl + tr + 2*mr + br) / 255.0

                    // Sobel vertical gradient
                    let tc = Double(pixels[(y-1) * bytesPerRow + x * bpp + channel])
                    let bc = Double(pixels[(y+1) * bytesPerRow + x * bpp + channel])
                    let gy = (-tl - 2*tc - tr + bl + 2*bc + br) / 255.0

                    totalGrad += sqrt(gx * gx + gy * gy)
                }

                edgeMap[y * width + x] = totalGrad / 3.0  // average across channels
            }
        }

        return edgeMap
    }

    // MARK: - Grid Spacing Detection

    private enum Axis { case horizontal, vertical }

    /// Detects the repeating cell spacing using autocorrelation on edge projections.
    /// Returns the cell size in pixels, or nil if no clear periodic structure found.
    private static func detectSpacing(
        edgeMap: [Double], width: Int, height: Int,
        axis: Axis, expectedCount: Int?
    ) -> Double? {
        // Compute projection profile: sum edge values along the axis
        let profileLen: Int
        var profile: [Double]

        switch axis {
        case .horizontal:
            // Sum each column's edges → detect vertical grid lines → horizontal cell spacing
            profileLen = width
            profile = [Double](repeating: 0, count: profileLen)
            for x in 0..<width {
                // Use inner 60% of height to avoid title/legend edges
                let yLo = height / 5
                let yHi = height - height / 5
                for y in yLo..<yHi {
                    profile[x] += edgeMap[y * width + x]
                }
            }
        case .vertical:
            // Sum each row's edges → detect horizontal grid lines → vertical cell spacing
            profileLen = height
            profile = [Double](repeating: 0, count: profileLen)
            for y in 0..<height {
                let xLo = width / 5
                let xHi = width - width / 5
                for x in xLo..<xHi {
                    profile[y] += edgeMap[y * width + x]
                }
            }
        }

        // Autocorrelate the profile to find periodic spacing
        // Search for the first strong peak after lag 0
        let minLag = 3  // minimum cell size in pixels
        let maxLag = profileLen / 2

        var autocorr = [Double](repeating: 0, count: maxLag)
        let mean = profile.reduce(0, +) / Double(profileLen)
        let variance = profile.reduce(0.0) { $0 + ($1 - mean) * ($1 - mean) }
        guard variance > 0 else { return nil }

        for lag in minLag..<maxLag {
            var sum = 0.0
            for i in 0..<(profileLen - lag) {
                sum += (profile[i] - mean) * (profile[i + lag] - mean)
            }
            autocorr[lag] = sum / variance
        }

        // Find the first prominent peak
        // If we have an expected count, search near the expected cell size
        let expectedCellSize: Double? = expectedCount.map {
            Double(axis == .horizontal ? width : height) / Double($0 + 2)  // +2 for margins
        }

        var bestLag = 0
        var bestScore = 0.0

        for lag in minLag..<maxLag {
            let score = autocorr[lag]

            // Bonus if near expected cell size
            var adjustedScore = score
            if let expected = expectedCellSize {
                let dist = abs(Double(lag) - expected) / expected
                if dist < 0.3 {
                    adjustedScore *= 1.0 + (1.0 - dist) * 0.5
                }
            }

            // Must be a local maximum
            let prev = lag > 0 ? autocorr[lag - 1] : 0
            let next = lag < maxLag - 1 ? autocorr[lag + 1] : 0
            let isLocalMax = score >= prev && score >= next

            if isLocalMax && adjustedScore > bestScore && score > 0.05 {
                bestScore = adjustedScore
                bestLag = lag
            }
        }

        guard bestLag > 0 else { return nil }

        // Sub-pixel refinement: parabolic interpolation around the peak
        let spacing: Double
        if bestLag > 0 && bestLag < maxLag - 1 {
            let ym1 = autocorr[bestLag - 1]
            let y0 = autocorr[bestLag]
            let yp1 = autocorr[bestLag + 1]
            let denom = 2.0 * (2.0 * y0 - ym1 - yp1)
            if abs(denom) > 1e-6 {
                spacing = Double(bestLag) + (ym1 - yp1) / denom
            } else {
                spacing = Double(bestLag)
            }
        } else {
            spacing = Double(bestLag)
        }

        #if DEBUG
        let axisName = axis == .horizontal ? "horizontal" : "vertical"
        print("[ColorworkGrid] \(axisName) cell spacing: \(String(format:"%.1f",spacing))px (autocorr peak: \(String(format:"%.3f",bestScore)))")
        #endif

        return spacing
    }

    // MARK: - Grid Bounds Detection

    private struct GridBounds {
        let minX: Int, minY: Int, maxX: Int, maxY: Int
    }

    /// Finds the grid boundaries by analyzing where edge density starts/stops.
    /// Scans from chart center outward to find the edges of the grid region.
    private static func findGridBounds(
        edgeMap: [Double], width: Int, height: Int,
        cellWidth: Double, cellHeight: Double
    ) -> GridBounds {
        // Compute edge density projections
        var hProj = [Double](repeating: 0, count: height)
        var vProj = [Double](repeating: 0, count: width)

        // Use center 60% for cross-axis projections (avoid labels at edges)
        let xLo = width / 5, xHi = width - width / 5
        let yLo = height / 5, yHi = height - height / 5

        for y in 0..<height {
            for x in xLo..<xHi {
                hProj[y] += edgeMap[y * width + x]
            }
            hProj[y] /= Double(xHi - xLo)
        }
        for x in 0..<width {
            for y in yLo..<yHi {
                vProj[x] += edgeMap[y * width + x]
            }
            vProj[x] /= Double(yHi - yLo)
        }

        // Find grid edges by scanning from center outward
        let centerX = width / 2
        let centerY = height / 2

        let threshold = 0.02  // minimum edge density to be "in grid"

        let minY = scanEdge(profile: hProj, from: centerY, direction: -1, threshold: threshold)
        let maxY = scanEdge(profile: hProj, from: centerY, direction: 1, threshold: threshold)
        let minX = scanEdge(profile: vProj, from: centerX, direction: -1, threshold: threshold)
        let maxX = scanEdge(profile: vProj, from: centerX, direction: 1, threshold: threshold)

        // Snap to nearest cell boundary
        let snappedMinX = snapToGrid(value: minX, cellSize: cellWidth, direction: .inward)
        let snappedMinY = snapToGrid(value: minY, cellSize: cellHeight, direction: .inward)
        let snappedMaxX = snapToGrid(value: maxX, cellSize: cellWidth, direction: .outward)
        let snappedMaxY = snapToGrid(value: maxY, cellSize: cellHeight, direction: .outward)

        return GridBounds(
            minX: max(0, snappedMinX),
            minY: max(0, snappedMinY),
            maxX: min(width, snappedMaxX),
            maxY: min(height, snappedMaxY)
        )
    }

    private static func scanEdge(
        profile: [Double], from center: Int, direction: Int, threshold: Double
    ) -> Int {
        let count = profile.count
        var lastAbove = center
        let smoothRadius = 3

        var i = center
        while i >= 0 && i < count {
            let lo = max(0, i - smoothRadius)
            let hi = min(count - 1, i + smoothRadius)
            let smoothed = profile[lo...hi].reduce(0, +) / Double(hi - lo + 1)
            if smoothed >= threshold {
                lastAbove = i
            } else {
                break
            }
            i += direction
        }
        return lastAbove
    }

    private enum SnapDirection { case inward, outward }

    private static func snapToGrid(value: Int, cellSize: Double, direction: SnapDirection) -> Int {
        let cells = Double(value) / cellSize
        switch direction {
        case .inward: return Int(ceil(cells) * cellSize)
        case .outward: return Int(floor(cells) * cellSize)
        }
    }

    // MARK: - Cell Color Sampling

    private typealias RGB = (r: Double, g: Double, b: Double)

    private static func sampleCellColors(
        pixels: [UInt8], width: Int, height: Int, bpp: Int,
        gridBounds: GridBounds,
        rows: Int, cols: Int,
        cellWidth: Double, cellHeight: Double
    ) -> [[RGB]] {
        let bytesPerRow = width * bpp
        var result: [[RGB]] = []

        for row in 0..<rows {
            var rowColors: [RGB] = []
            for col in 0..<cols {
                // Sample from center of cell (3x3 average for robustness)
                let cx = Double(gridBounds.minX) + (Double(col) + 0.5) * cellWidth
                let cy = Double(gridBounds.minY) + (Double(row) + 0.5) * cellHeight
                let px = Int(cx)
                let py = Int(cy)

                var rSum = 0.0, gSum = 0.0, bSum = 0.0
                var count = 0

                for dy in -1...1 {
                    for dx in -1...1 {
                        let sx = px + dx
                        let sy = py + dy
                        guard sx >= 0, sx < width, sy >= 0, sy < height else { continue }
                        let off = sy * bytesPerRow + sx * bpp
                        rSum += Double(pixels[off])
                        gSum += Double(pixels[off + 1])
                        bSum += Double(pixels[off + 2])
                        count += 1
                    }
                }

                let r = rSum / Double(count) / 255.0
                let g = gSum / Double(count) / 255.0
                let b = bSum / Double(count) / 255.0
                rowColors.append((r: r, g: g, b: b))
            }
            result.append(rowColors)
        }

        return result
    }

    // MARK: - K-Means Clustering

    /// Runs K-means clustering on RGB colors. Returns (centroids, assignments).
    /// Automatically reduces K if clusters collapse (fewer distinct colors than K).
    private static func kMeansCluster(
        colors: [RGB], k initialK: Int
    ) -> ([RGB], [Int]) {
        guard !colors.isEmpty else { return ([], []) }

        var k = min(initialK, colors.count)
        guard k >= 2 else {
            let avg = averageColor(colors)
            return ([avg], [Int](repeating: 0, count: colors.count))
        }

        // Initialize centroids using k-means++ strategy
        var centroids = initializeCentroids(colors: colors, k: k)
        var assignments = [Int](repeating: 0, count: colors.count)

        for _ in 0..<20 {  // max iterations
            // Assign each color to nearest centroid
            var changed = false
            for i in 0..<colors.count {
                var bestDist = Double.greatestFiniteMagnitude
                var bestC = 0
                for c in 0..<centroids.count {
                    let d = colorDistance(colors[i], centroids[c])
                    if d < bestDist {
                        bestDist = d
                        bestC = c
                    }
                }
                if assignments[i] != bestC {
                    assignments[i] = bestC
                    changed = true
                }
            }
            if !changed { break }

            // Update centroids
            var newCentroids: [RGB] = []
            for c in 0..<centroids.count {
                let members = colors.indices.filter { assignments[$0] == c }
                if members.isEmpty {
                    // Dead cluster — drop it
                    continue
                }
                let memberColors = members.map { colors[$0] }
                newCentroids.append(averageColor(memberColors))
            }

            // If clusters collapsed, remap assignments
            if newCentroids.count < centroids.count {
                centroids = newCentroids
                k = centroids.count
                // Re-assign with fewer clusters
                for i in 0..<colors.count {
                    var bestDist = Double.greatestFiniteMagnitude
                    var bestC = 0
                    for c in 0..<centroids.count {
                        let d = colorDistance(colors[i], centroids[c])
                        if d < bestDist {
                            bestDist = d
                            bestC = c
                        }
                    }
                    assignments[i] = bestC
                }
            } else {
                centroids = newCentroids
            }
        }

        // Sort palette by brightness (darkest first) for consistent ordering
        let sortedIndices = centroids.indices.sorted {
            luminance(centroids[$0]) < luminance(centroids[$1])
        }
        let sortedCentroids = sortedIndices.map { centroids[$0] }
        var indexMap = [Int](repeating: 0, count: centroids.count)
        for (newIdx, oldIdx) in sortedIndices.enumerated() {
            indexMap[oldIdx] = newIdx
        }
        let sortedAssignments = assignments.map { indexMap[$0] }

        return (sortedCentroids, sortedAssignments)
    }

    /// K-means++ initialization: spread initial centroids apart
    private static func initializeCentroids(colors: [RGB], k: Int) -> [RGB] {
        guard !colors.isEmpty else { return [] }
        var centroids: [RGB] = []

        // First centroid: random
        centroids.append(colors[colors.count / 2])

        for _ in 1..<k {
            // Weight by squared distance to nearest centroid
            var weights = [Double](repeating: 0, count: colors.count)
            for i in 0..<colors.count {
                var minDist = Double.greatestFiniteMagnitude
                for c in centroids {
                    let d = colorDistance(colors[i], c)
                    minDist = min(minDist, d)
                }
                weights[i] = minDist * minDist
            }
            let totalWeight = weights.reduce(0, +)
            guard totalWeight > 0 else { break }

            // Weighted random selection
            var r = Double.random(in: 0..<totalWeight)
            var selected = 0
            for i in 0..<weights.count {
                r -= weights[i]
                if r <= 0 {
                    selected = i
                    break
                }
            }
            centroids.append(colors[selected])
        }

        return centroids
    }

    private static func colorDistance(_ a: RGB, _ b: RGB) -> Double {
        let dr = a.r - b.r
        let dg = a.g - b.g
        let db = a.b - b.b
        return sqrt(dr * dr + dg * dg + db * db)
    }

    private static func averageColor(_ colors: [RGB]) -> RGB {
        guard !colors.isEmpty else { return (0, 0, 0) }
        let n = Double(colors.count)
        return (
            r: colors.reduce(0) { $0 + $1.r } / n,
            g: colors.reduce(0) { $0 + $1.g } / n,
            b: colors.reduce(0) { $0 + $1.b } / n
        )
    }

    private static func luminance(_ c: RGB) -> Double {
        0.299 * c.r + 0.587 * c.g + 0.114 * c.b
    }

    /// Quantize color to reduce unique count for initial K estimation
    private static func quantizeColor(_ c: RGB) -> Int {
        let r = Int(c.r * 7)
        let g = Int(c.g * 7)
        let b = Int(c.b * 7)
        return r * 64 + g * 8 + b
    }
}
