//
//  ChartGridSolver.swift
//  PatternVault
//
//  Deterministic grid solver for knitting charts.
//
//  Models the chart as a periodic lattice: cell spacing is recovered by
//  autocorrelation of a color-edge projection profile, lattice alignment
//  (phase) by comb fitting, and the grid boundary by finding the contiguous
//  run of lattice positions with gridline support. Labels, titles, and
//  legends are rejected because they are not periodic at lattice positions —
//  no absolute density thresholds are involved, which is what made the
//  earlier per-chart threshold tuning a zero-sum game.
//
//  The solver verifies its own output: cells are sampled at five interior
//  points each, and the fraction of cells whose samples agree (cell
//  coherence) is a direct measurement of grid alignment quality. Confidence
//  is computed, not asserted. All steps are deterministic — the same image
//  always produces the same grid.
//

import UIKit

struct ChartGridSolver {

    /// Normalized (0...1) region of the image the grid is expected to be in.
    /// Used as a search prior (e.g. from AI detection); the solver refines it.
    struct PriorRegion {
        let xMin: Double
        let yMin: Double
        let xMax: Double
        let yMax: Double

        init?(xMin: Double, yMin: Double, xMax: Double, yMax: Double) {
            guard xMin >= 0, yMin >= 0, xMax <= 1, yMax <= 1,
                  xMax - xMin > 0.05, yMax - yMin > 0.05 else { return nil }
            self.xMin = xMin
            self.yMin = yMin
            self.xMax = xMax
            self.yMax = yMax
        }
    }

    struct Solution {
        let insetLeft: Double
        let insetTop: Double
        let insetRight: Double
        let insetBottom: Double
        let rows: Int
        let columns: Int
        /// 0...1 measured confidence (cell coherence + gridline support + hint agreement).
        let confidence: Double
        /// Fraction of cells whose interior samples agree — direct alignment quality measure.
        let cellCoherence: Double
        /// Mean normalized gridline support at lattice positions.
        let lineSupport: Double
        /// Per-cell colors, when the chart resolves to a small yarn palette.
        let colorwork: ColorworkGrid?
    }

    /// Analysis resolution cap. Larger images are downsampled; all outputs are
    /// normalized so the cap does not affect coordinates.
    private static let maxAnalysisDimension = 1200

    // MARK: - Public API

    static func solve(
        image: UIImage,
        expectedRows: Int? = nil,
        expectedColumns: Int? = nil,
        prior: PriorRegion? = nil
    ) -> Solution? {
        guard let buffer = PixelBuffer(image: image, maxDimension: maxAnalysisDimension) else { return nil }

        // Expand the prior — AI boundaries are ~85-90% accurate and often clip
        // the outermost cells; the lattice run detection re-tightens precisely.
        let region: PriorRegion
        if let prior, let expanded = PriorRegion(
            xMin: max(0, prior.xMin - 0.08),
            yMin: max(0, prior.yMin - 0.08),
            xMax: min(1, prior.xMax + 0.08),
            yMax: min(1, prior.yMax + 0.08)
        ) {
            region = expanded
        } else {
            region = PriorRegion(xMin: 0, yMin: 0, xMax: 1, yMax: 1)!
        }
        let edges = buffer.colorEdgeMap()

        guard let xLattice = solveAxis(
            edges: edges, buffer: buffer, axis: .x,
            region: region, expectedCells: expectedColumns
        ), let yLattice = solveAxis(
            edges: edges, buffer: buffer, axis: .y,
            region: region, expectedCells: expectedRows
        ) else { return nil }

        var cols = xLattice.cells
        var rows = yLattice.cells
        guard cols >= 2, rows >= 2 else { return nil }

        var xStart = xLattice.start
        var xEnd = xLattice.end
        var yStart = yLattice.start
        var yEnd = yLattice.end
        let cellW = (xEnd - xStart) / Double(cols)
        let cellH = (yEnd - yStart) / Double(rows)

        // 2D lattice consistency: a real chart row contains the vertical
        // gridlines running through it; a title or label strip that fooled the
        // 1D projection does not. (And symmetrically for columns.) Only applied
        // when most rows/cols pass — charts without interior gridlines opt out.
        let coverage: (_ vertical: Bool, _ linePos: Double, _ from: Double, _ to: Double) -> Double = { vertical, linePos, from, to in
            let li = Int(linePos.rounded())
            let limit = vertical ? buffer.width : buffer.height
            guard li >= 1, li < limit - 1 else { return 0 }
            let a = max(0, Int(from.rounded()))
            let b = min((vertical ? buffer.height : buffer.width) - 1, Int(to.rounded()))
            guard b > a else { return 0 }
            var covered = 0
            for t in a...b {
                var m = 0.0
                for d in -1...1 {
                    let idx = vertical ? (t * buffer.width + li + d) : ((li + d) * buffer.width + t)
                    m = max(m, edges[idx])
                }
                if m > 0.08 { covered += 1 }
            }
            return Double(covered) / Double(b - a + 1)
        }

        func rowGridlikeness(_ r: Int) -> Double {
            guard cols >= 2 else { return 0 }
            let y0 = yStart + (Double(r) + 0.15) * cellH
            let y1 = yStart + (Double(r) + 0.85) * cellH
            var present = 0
            for i in 1..<cols where coverage(true, xStart + Double(i) * cellW, y0, y1) >= 0.5 {
                present += 1
            }
            return Double(present) / Double(cols - 1)
        }

        func colGridlikeness(_ c: Int) -> Double {
            guard rows >= 2 else { return 0 }
            let x0 = xStart + (Double(c) + 0.15) * cellW
            let x1 = xStart + (Double(c) + 0.85) * cellW
            var present = 0
            for i in 1..<rows where coverage(false, yStart + Double(i) * cellH, x0, x1) >= 0.5 {
                present += 1
            }
            return Double(present) / Double(rows - 1)
        }

        let rowScores = (0..<rows).map(rowGridlikeness)
        if rowScores.filter({ $0 >= 0.5 }).count * 10 >= rows * 6 {
            while rows > 3, rowGridlikeness(0) < 0.5 {
                yStart += cellH
                rows -= 1
            }
            while rows > 3, rowGridlikeness(rows - 1) < 0.5 {
                yEnd -= cellH
                rows -= 1
            }
        }
        let colScores = (0..<cols).map(colGridlikeness)
        if colScores.filter({ $0 >= 0.5 }).count * 10 >= cols * 6 {
            while cols > 3, colGridlikeness(0) < 0.5 {
                xStart += cellW
                cols -= 1
            }
            while cols > 3, colGridlikeness(cols - 1) < 0.5 {
                xEnd -= cellW
                cols -= 1
            }
        }

        let insetLeft = xStart / Double(buffer.width)
        let insetRight = 1.0 - xEnd / Double(buffer.width)
        let insetTop = yStart / Double(buffer.height)
        let insetBottom = 1.0 - yEnd / Double(buffer.height)

        // Sample cell colors and measure alignment quality.
        let sampling = sampleCells(
            buffer: buffer,
            xStart: xStart, xEnd: xEnd, cols: cols,
            yStart: yStart, yEnd: yEnd, rows: rows
        )

        let (palette, assignments) = clusterColors(sampling.cellMeans)

        var colorwork: ColorworkGrid?
        if palette.count >= 2, palette.count <= 8, sampling.coherence >= 0.75 {
            var cellColors: [[Int]] = []
            cellColors.reserveCapacity(rows)
            for r in 0..<rows {
                cellColors.append(Array(assignments[(r * cols)..<((r + 1) * cols)]))
            }
            let yarns = palette.enumerated().map { i, rgb in
                ColorworkGrid.YarnColor(red: rgb.r, green: rgb.g, blue: rgb.b, name: i == 0 ? "MC" : "CC\(i)")
            }
            colorwork = ColorworkGrid(rows: rows, columns: cols, palette: yarns, cellColors: cellColors)
        }

        let lineSupport = (xLattice.meanSupport + yLattice.meanSupport) / 2

        let hintAgreement: Double
        switch (expectedRows, expectedColumns) {
        case (nil, nil):
            hintAgreement = 0.5
        case let (er, ec):
            let rowOK = er.map { abs($0 - rows) <= 1 } ?? true
            let colOK = ec.map { abs($0 - cols) <= 1 } ?? true
            hintAgreement = (rowOK && colOK) ? 1.0 : 0.0
        }

        let confidence = min(1.0, 0.55 * sampling.coherence + 0.35 * min(1.0, lineSupport) + 0.10 * hintAgreement)

        #if DEBUG
        print("""
        [GridSolver] \(rows)x\(cols) grid (hints: \(expectedRows.map(String.init) ?? "-")x\(expectedColumns.map(String.init) ?? "-"))
          insets = (L:\(String(format: "%.3f", insetLeft)), T:\(String(format: "%.3f", insetTop)), R:\(String(format: "%.3f", insetRight)), B:\(String(format: "%.3f", insetBottom)))
          coherence=\(String(format: "%.2f", sampling.coherence)) lineSupport=\(String(format: "%.2f", lineSupport)) confidence=\(String(format: "%.2f", confidence)) palette=\(palette.count)
        """)
        #endif

        return Solution(
            insetLeft: insetLeft,
            insetTop: insetTop,
            insetRight: insetRight,
            insetBottom: insetBottom,
            rows: rows,
            columns: cols,
            confidence: confidence,
            cellCoherence: sampling.coherence,
            lineSupport: lineSupport,
            colorwork: colorwork
        )
    }

    // MARK: - Pixel Buffer

    private struct PixelBuffer {
        let width: Int
        let height: Int
        let pixels: [UInt8]  // RGBA, premultiplied last

        init?(image: UIImage, maxDimension: Int) {
            guard let cgImage = image.cgImage else { return nil }
            let srcW = cgImage.width
            let srcH = cgImage.height
            guard srcW > 20, srcH > 20 else { return nil }

            let scale = min(1.0, Double(maxDimension) / Double(max(srcW, srcH)))
            let w = max(20, Int(Double(srcW) * scale))
            let h = max(20, Int(Double(srcH) * scale))

            var buf = [UInt8](repeating: 0, count: w * h * 4)
            let ok = buf.withUnsafeMutableBytes { raw -> Bool in
                guard let ctx = CGContext(
                    data: raw.baseAddress, width: w, height: h,
                    bitsPerComponent: 8, bytesPerRow: w * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ) else { return false }
                ctx.setFillColor(UIColor.white.cgColor)
                ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
                ctx.interpolationQuality = .high
                ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
                return true
            }
            guard ok else { return nil }

            width = w
            height = h
            pixels = buf
        }

        func rgb(x: Int, y: Int) -> (r: Double, g: Double, b: Double) {
            let off = (y * width + x) * 4
            return (Double(pixels[off]) / 255.0, Double(pixels[off + 1]) / 255.0, Double(pixels[off + 2]) / 255.0)
        }

        /// Per-pixel color-gradient magnitude (Sobel summed over RGB channels).
        /// Detects boundaries between differently colored cells even at equal
        /// luminance, where grayscale edge detection fails.
        func colorEdgeMap() -> [Double] {
            var map = [Double](repeating: 0, count: width * height)
            let bpr = width * 4
            pixels.withUnsafeBufferPointer { p in
                for y in 1..<(height - 1) {
                    for x in 1..<(width - 1) {
                        var total = 0.0
                        for c in 0..<3 {
                            let tl = Double(p[(y - 1) * bpr + (x - 1) * 4 + c])
                            let ml = Double(p[y * bpr + (x - 1) * 4 + c])
                            let bl = Double(p[(y + 1) * bpr + (x - 1) * 4 + c])
                            let tc = Double(p[(y - 1) * bpr + x * 4 + c])
                            let bc = Double(p[(y + 1) * bpr + x * 4 + c])
                            let tr = Double(p[(y - 1) * bpr + (x + 1) * 4 + c])
                            let mr = Double(p[y * bpr + (x + 1) * 4 + c])
                            let br = Double(p[(y + 1) * bpr + (x + 1) * 4 + c])
                            let gx = (-tl - 2 * ml - bl + tr + 2 * mr + br) / 255.0
                            let gy = (-tl - 2 * tc - tr + bl + 2 * bc + br) / 255.0
                            total += (gx * gx + gy * gy).squareRoot()
                        }
                        map[y * width + x] = total / 3.0
                    }
                }
            }
            return map
        }
    }

    // MARK: - Axis Lattice Solve

    private enum Axis { case x, y }

    private struct AxisLattice {
        let start: Double     // pixel position of first gridline (analysis scale)
        let end: Double       // pixel position of last gridline
        let cells: Int
        let meanSupport: Double  // mean normalized line support across the run
    }

    private static func solveAxis(
        edges: [Double],
        buffer: PixelBuffer,
        axis: Axis,
        region: PriorRegion,
        expectedCells: Int?
    ) -> AxisLattice? {
        let len = axis == .x ? buffer.width : buffer.height
        let crossLen = axis == .x ? buffer.height : buffer.width

        // Region bounds along this axis and the cross axis (analysis pixels).
        let lo = max(0, Int((axis == .x ? region.xMin : region.yMin) * Double(len)))
        let hi = min(len, Int((axis == .x ? region.xMax : region.yMax) * Double(len)))
        let crossLoRaw = max(0, Int((axis == .x ? region.yMin : region.xMin) * Double(crossLen)))
        let crossHiRaw = min(crossLen, Int((axis == .x ? region.yMax : region.xMax) * Double(crossLen)))
        guard hi - lo > 20, crossHiRaw - crossLoRaw > 20 else { return nil }

        // Inner 60% of the cross axis: excludes row/column number strips that
        // would otherwise contaminate the projection.
        let crossSpan = crossHiRaw - crossLoRaw
        let crossLo = crossLoRaw + crossSpan / 5
        let crossHi = crossHiRaw - crossSpan / 5

        // Projection profile of edge magnitude along the FULL axis (the prior
        // only windows the cross axis and anchors the search) — the lattice run
        // may extend past a misplaced prior to recover clipped cells.
        var profile = [Double](repeating: 0, count: len)
        let w = buffer.width
        for i in 0..<len {
            var sum = 0.0
            for j in crossLo..<crossHi {
                let idx = axis == .x ? (j * w + i) : (i * w + j)
                sum += edges[idx]
            }
            profile[i] = sum / Double(crossHi - crossLo)
        }

        // Light smoothing so 1px gridlines register at slightly-off positions.
        profile = smoothed(profile, radius: 1)

        // Candidate spacings from autocorrelation peaks (+ hint-derived candidate).
        let candidates = spacingCandidates(
            profile: profile, lo: lo, hi: hi, expectedCells: expectedCells
        )
        guard !candidates.isEmpty else { return nil }

        // Jointly optimize (spacing, phase) by the strength of the best lattice
        // run each candidate produces.
        var best: (lattice: AxisLattice, score: Double)?
        for spacing in candidates {
            guard let fit = fitLattice(
                profile: profile, lo: lo, hi: hi,
                spacing: spacing, expectedCells: expectedCells
            ) else { continue }
            if best == nil || fit.score > best!.score {
                best = fit
            }
        }
        return best?.lattice
    }

    private static func smoothed(_ values: [Double], radius: Int) -> [Double] {
        guard radius > 0 else { return values }
        var out = values
        for i in 0..<values.count {
            let a = max(0, i - radius)
            let b = min(values.count - 1, i + radius)
            out[i] = values[a...b].reduce(0, +) / Double(b - a + 1)
        }
        return out
    }

    /// Autocorrelation peaks of the profile within [lo, hi), plus a candidate
    /// derived from the expected cell count. Deterministic, at most 6 candidates.
    private static func spacingCandidates(
        profile: [Double], lo: Int, hi: Int, expectedCells: Int?
    ) -> [Double] {
        let span = hi - lo
        let segment = Array(profile[lo..<hi])
        let mean = segment.reduce(0, +) / Double(span)
        let variance = segment.reduce(0.0) { $0 + ($1 - mean) * ($1 - mean) }
        guard variance > 0 else { return [] }

        let minLag = 4
        let maxLag = span / 2
        guard maxLag > minLag else { return [] }

        var autocorr = [Double](repeating: 0, count: maxLag)
        for lag in minLag..<maxLag {
            var sum = 0.0
            for i in 0..<(span - lag) {
                sum += (segment[i] - mean) * (segment[i + lag] - mean)
            }
            autocorr[lag] = sum / variance
        }

        // Local maxima above a weak floor, strongest first.
        var peaks: [(lag: Int, value: Double)] = []
        for lag in (minLag + 1)..<(maxLag - 1) {
            let v = autocorr[lag]
            if v > 0.03, v >= autocorr[lag - 1], v >= autocorr[lag + 1] {
                peaks.append((lag, v))
            }
        }
        peaks.sort { $0.value > $1.value }

        var candidates: [Double] = []
        for peak in peaks.prefix(4) {
            // Sub-pixel parabolic refinement around the peak.
            let l = peak.lag
            var spacing = Double(l)
            if l > 0, l < maxLag - 1 {
                let ym1 = autocorr[l - 1], y0 = autocorr[l], yp1 = autocorr[l + 1]
                let denom = 2 * (2 * y0 - ym1 - yp1)
                if abs(denom) > 1e-9 {
                    spacing += (ym1 - yp1) / denom
                }
            }
            // Include sub-harmonics: colorwork blocks spanning 2-3 cells make
            // the block period dominate autocorrelation even though the true
            // cell spacing is a fraction of it. Run scoring picks the winner.
            for divisor in [1.0, 2.0, 3.0] {
                let sub = spacing / divisor
                if sub >= Double(minLag) {
                    candidates.append(sub)
                }
            }
        }

        // Hint-derived candidate: prior span divided by the expected count.
        if let n = expectedCells, n >= 2 {
            let hintSpacing = Double(span) / Double(n)
            if hintSpacing >= Double(minLag), hintSpacing < Double(maxLag) {
                candidates.append(hintSpacing)
            }
        }

        // Dedupe near-equal candidates (within 5%).
        var unique: [Double] = []
        for c in candidates where !unique.contains(where: { abs($0 - c) / $0 < 0.05 }) {
            unique.append(c)
        }
        return unique
    }

    /// Interpolated profile value at a fractional position.
    private static func interp(_ profile: [Double], _ pos: Double) -> Double {
        guard pos >= 0, pos < Double(profile.count - 1) else { return 0 }
        let i = Int(pos)
        let f = pos - Double(i)
        return profile[i] * (1 - f) + profile[i + 1] * f
    }

    /// Strongest profile peak within ±radius of center, with sub-pixel refinement.
    private static func localPeak(
        _ profile: [Double], center: Double, radius: Double
    ) -> (pos: Double, value: Double)? {
        let lo = max(1, Int((center - radius).rounded()))
        let hi = min(profile.count - 2, Int((center + radius).rounded()))
        guard hi >= lo else { return nil }
        var bestI = lo
        var bestV = -1.0
        for i in lo...hi where profile[i] > bestV {
            bestV = profile[i]
            bestI = i
        }
        guard bestV > 0 else { return nil }
        var pos = Double(bestI)
        let ym1 = profile[bestI - 1], y0 = profile[bestI], yp1 = profile[bestI + 1]
        let denom = 2 * (2 * y0 - ym1 - yp1)
        if abs(denom) > 1e-9 {
            let d = (ym1 - yp1) / denom
            if abs(d) <= 1 { pos += d }
        }
        return (pos, bestV)
    }

    /// For a given spacing, finds the phase and the contiguous lattice-line run
    /// that best explains the profile. Returns the lattice plus a comparable score.
    private static func fitLattice(
        profile: [Double], lo: Int, hi: Int,
        spacing: Double, expectedCells: Int?
    ) -> (lattice: AxisLattice, score: Double)? {
        guard spacing >= 4 else { return nil }

        // Normalization reference: typical gridline strength, estimated as the
        // median of the top-K profile values where K ≈ the number of gridlines
        // this spacing implies. (Percentile-of-everything fails on clean charts
        // where the profile is near zero between lines.)
        let span = hi - lo
        let sortedDesc = Array(profile[lo..<hi]).sorted(by: >)
        guard !sortedDesc.isEmpty else { return nil }
        let approxLines = max(4, Int(Double(span) / spacing) + 1)
        let topK = Array(sortedDesc.prefix(approxLines))
        let reference = topK[topK.count / 2]
        guard reference > 1e-9 else { return nil }

        // Phase search: maximize mean lattice-position support.
        let phaseStep = max(0.25, spacing / 40)
        var bestPhase = 0.0
        var bestPhaseScore = -1.0
        var phase = 0.0
        while phase < spacing {
            var sum = 0.0
            var count = 0
            var pos = Double(lo) + phase
            while pos < Double(hi) {
                sum += interp(profile, pos)
                count += 1
                pos += spacing
            }
            if count >= 3 {
                let score = sum / Double(count)
                if score > bestPhaseScore {
                    bestPhaseScore = score
                    bestPhase = phase
                }
            }
            phase += phaseStep
        }
        guard bestPhaseScore > 0 else { return nil }

        // Refine spacing + phase: autocorrelation spacing carries ~1-2% error,
        // which drifts several pixels across the grid and makes far lines miss
        // their lattice positions. Snap each line to its local profile peak and
        // least-squares fit position = anchor + k·spacing.
        let len = profile.count
        var refinedSpacing = spacing
        var anchor = Double(lo) + bestPhase
        for _ in 0..<2 {
            let searchR = max(2.0, refinedSpacing / 4)
            var ks: [Double] = []
            var ps: [Double] = []
            let kLo = Int(ceil((1.0 - anchor) / refinedSpacing))
            let kHi = Int(floor((Double(len - 2) - anchor) / refinedSpacing))
            guard kHi >= kLo else { break }
            for k in kLo...kHi {
                let center = anchor + Double(k) * refinedSpacing
                if let peak = localPeak(profile, center: center, radius: searchR),
                   peak.value > 0.15 * reference {
                    ks.append(Double(k))
                    ps.append(peak.pos)
                }
            }
            guard ks.count >= 4 else { break }
            let n = Double(ks.count)
            let kMean = ks.reduce(0, +) / n
            let pMean = ps.reduce(0, +) / n
            var num = 0.0, den = 0.0
            for i in 0..<ks.count {
                num += (ks[i] - kMean) * (ps[i] - pMean)
                den += (ks[i] - kMean) * (ks[i] - kMean)
            }
            guard den > 1e-9 else { break }
            let newSpacing = num / den
            // Reject degenerate fits (e.g. adjacent half-spacing windows
            // snapping to the same real line collapse the slope).
            guard abs(newSpacing - spacing) < 0.15 * spacing else { break }
            refinedSpacing = newSpacing
            anchor = pMean - refinedSpacing * kMean
        }

        // Support at each refined lattice position across the full axis (not
        // just the prior) so clipped outer cells can be recovered. Normalize by
        // the 75th percentile of on-lattice values within the prior — this is
        // self-normalizing: real gridlines land near 1, half-spacing harmonics
        // put mid-cell positions near 0.
        var positions: [Double] = []
        var rawSupports: [Double] = []
        let kMin = Int(ceil((1.0 - anchor) / refinedSpacing))
        let kMax = Int(floor((Double(len - 2) - anchor) / refinedSpacing))
        guard kMax >= kMin else { return nil }
        for k in kMin...kMax {
            let pos = anchor + Double(k) * refinedSpacing
            positions.append(pos)
            rawSupports.append(interp(profile, pos))
        }
        guard positions.count >= 4 else { return nil }

        let inPrior = zip(positions, rawSupports)
            .filter { $0.0 >= Double(lo) && $0.0 < Double(hi) }
            .map { $0.1 }
            .sorted()
        guard inPrior.count >= 3 else { return nil }
        let refP75 = inPrior[min(inPrior.count - 1, (inPrior.count * 3) / 4)]
        guard refP75 > 1e-9 else { return nil }
        let supports = rawSupports.map { min(1.5, $0 / refP75) }

        // A lattice line is "present" when its support clears a fraction of the
        // regional strong value AND a profile ridge actually peaks there — a
        // sub-spacing harmonic puts mid-cell positions on the flank of a wide
        // smoothed line ridge, which has value but is not a peak. Interior gaps
        // of up to 2 lines are bridged — rows of a single color can have faint
        // interior gridlines.
        let peakTol = max(1.5, refinedSpacing / 8)
        var presence: [Bool] = []
        presence.reserveCapacity(positions.count)
        for (i, pos) in positions.enumerated() {
            var isLine = false
            if supports[i] >= 0.35,
               let pk = localPeak(profile, center: pos, radius: max(2.0, refinedSpacing / 3)),
               abs(pk.pos - pos) <= peakTol {
                isLine = true
            }
            presence.append(isLine)
        }
        guard let run = longestBridgedRun(presence: presence, maxGap: 2) else { return nil }
        var startIdx = run.lowerBound
        var endIdx = run.upperBound
        var cells = endIdx - startIdx
        guard cells >= 3 else { return nil }

        // Reconcile with the expected count: extend when a faint outermost
        // border line was clipped, trim the weaker end when the run overshoots
        // the hint.
        if let n = expectedCells {
            while cells < n, startIdx > 0, supports[startIdx - 1] >= 0.20 {
                startIdx -= 1
                cells += 1
            }
            while cells < n, endIdx < positions.count - 1, supports[endIdx + 1] >= 0.20 {
                endIdx += 1
                cells += 1
            }

            let median = supports[startIdx...endIdx].sorted()[(endIdx - startIdx) / 2]
            while cells > n {
                let startWeak = supports[startIdx] < 0.6 * median
                let endWeak = supports[endIdx] < 0.6 * median
                if startWeak && (!endWeak || supports[startIdx] <= supports[endIdx]) {
                    startIdx += 1
                } else if endWeak {
                    endIdx -= 1
                } else {
                    break
                }
                cells -= 1
            }
        }

        let runSupports = supports[startIdx...endIdx]
        let meanSupport = runSupports.reduce(0, +) / Double(runSupports.count)

        let lattice = AxisLattice(
            start: positions[startIdx],
            end: positions[endIdx],
            cells: cells,
            meanSupport: meanSupport
        )

        // Score for comparing spacing candidates: reward present lines, punish
        // absent interior ones. A half-spacing harmonic doubles the line count
        // but every other line is absent, so it loses to the true spacing;
        // a block-spacing harmonic (2x) has fewer lines, so it also loses.
        var presentSum = 0.0
        var absent = 0
        for s in runSupports {
            if s >= 0.35 {
                presentSum += s
            } else {
                absent += 1
            }
        }
        var score = presentSum - 0.35 * Double(absent)
        if let n = expectedCells, abs(n - cells) <= 1 {
            score *= 1.3
        }
        return (lattice, score)
    }

    /// Longest run of `true` values allowing interior gaps of up to `maxGap`
    /// consecutive `false` values (gaps must be flanked by `true`).
    private static func longestBridgedRun(presence: [Bool], maxGap: Int) -> ClosedRange<Int>? {
        var best: ClosedRange<Int>?
        var runStart: Int?
        var gap = 0
        var lastTrue = -1

        for (i, present) in presence.enumerated() {
            if present {
                if runStart == nil { runStart = i }
                gap = 0
                lastTrue = i
            } else if runStart != nil {
                gap += 1
                if gap > maxGap {
                    if let s = runStart, lastTrue >= s {
                        if best == nil || (lastTrue - s) > (best!.upperBound - best!.lowerBound) {
                            best = s...lastTrue
                        }
                    }
                    runStart = nil
                    gap = 0
                }
            }
        }
        if let s = runStart, lastTrue >= s {
            if best == nil || (lastTrue - s) > (best!.upperBound - best!.lowerBound) {
                best = s...lastTrue
            }
        }
        return best
    }

    // MARK: - Cell Sampling & Verification

    private typealias RGB = (r: Double, g: Double, b: Double)

    private struct CellSampling {
        let cellMeans: [RGB]   // row-major, rows*cols
        let coherence: Double  // fraction of cells whose samples agree
    }

    /// Samples five interior points per cell (center + four diagonal offsets).
    /// A cell is coherent when all five samples agree — misaligned grids place
    /// samples across cell boundaries and fail this check, making coherence a
    /// direct measurement of alignment quality.
    private static func sampleCells(
        buffer: PixelBuffer,
        xStart: Double, xEnd: Double, cols: Int,
        yStart: Double, yEnd: Double, rows: Int
    ) -> CellSampling {
        let cellW = (xEnd - xStart) / Double(cols)
        let cellH = (yEnd - yStart) / Double(rows)

        // Keep samples off the gridlines; pull offsets in for small cells.
        let offsetFrac = min(0.28, max(0.15, (cellW - 3) / (2 * cellW)))
        let offsets: [(Double, Double)] = [
            (0, 0),
            (-offsetFrac, -offsetFrac), (offsetFrac, -offsetFrac),
            (-offsetFrac, offsetFrac), (offsetFrac, offsetFrac),
        ]

        var means: [RGB] = []
        means.reserveCapacity(rows * cols)
        var coherent = 0

        for r in 0..<rows {
            for c in 0..<cols {
                let cx = xStart + (Double(c) + 0.5) * cellW
                let cy = yStart + (Double(r) + 0.5) * cellH

                var samples: [RGB] = []
                for (dx, dy) in offsets {
                    let px = Int((cx + dx * cellW).rounded())
                    let py = Int((cy + dy * cellH).rounded())
                    guard px >= 0, px < buffer.width, py >= 0, py < buffer.height else { continue }
                    samples.append(buffer.rgb(x: px, y: py))
                }
                guard !samples.isEmpty else {
                    means.append((0, 0, 0))
                    continue
                }

                let n = Double(samples.count)
                let mean: RGB = (
                    samples.reduce(0) { $0 + $1.r } / n,
                    samples.reduce(0) { $0 + $1.g } / n,
                    samples.reduce(0) { $0 + $1.b } / n
                )
                means.append(mean)

                let maxDev = samples.map { distance($0, mean) }.max() ?? 0
                if maxDev <= 0.15 {
                    coherent += 1
                }
            }
        }

        let coherence = means.isEmpty ? 0 : Double(coherent) / Double(means.count)
        return CellSampling(cellMeans: means, coherence: coherence)
    }

    private static func distance(_ a: RGB, _ b: RGB) -> Double {
        let dr = a.r - b.r, dg = a.g - b.g, db = a.b - b.b
        return (dr * dr + dg * dg + db * db).squareRoot()
    }

    // MARK: - Deterministic Palette Clustering

    /// K-means with deterministic maximin initialization (no randomness — the
    /// same chart always produces the same palette, so re-imports are stable).
    /// Clusters closer than 0.10 are merged; palette is sorted darkest-first.
    private static func clusterColors(_ colors: [RGB]) -> (palette: [RGB], assignments: [Int]) {
        guard !colors.isEmpty else { return ([], []) }

        let n = Double(colors.count)
        let globalMean: RGB = (
            colors.reduce(0) { $0 + $1.r } / n,
            colors.reduce(0) { $0 + $1.g } / n,
            colors.reduce(0) { $0 + $1.b } / n
        )

        // Estimate k from distinct quantized colors (3 bits/channel).
        var quantized = Set<Int>()
        for c in colors {
            quantized.insert(Int(c.r * 7) * 64 + Int(c.g * 7) * 8 + Int(c.b * 7))
        }
        let k = min(8, max(1, quantized.count))

        // Maximin init: first centroid = farthest from global mean, then each
        // next = point maximizing distance to its nearest centroid. Ties break
        // by lowest index — fully deterministic.
        var centroids: [RGB] = []
        var firstIdx = 0
        var firstDist = -1.0
        for (i, c) in colors.enumerated() {
            let d = distance(c, globalMean)
            if d > firstDist { firstDist = d; firstIdx = i }
        }
        centroids.append(colors[firstIdx])

        while centroids.count < k {
            var bestIdx = -1
            var bestDist = -1.0
            for (i, c) in colors.enumerated() {
                let d = centroids.map { distance(c, $0) }.min() ?? 0
                if d > bestDist { bestDist = d; bestIdx = i }
            }
            guard bestIdx >= 0, bestDist > 0.10 else { break }  // no meaningfully new color left
            centroids.append(colors[bestIdx])
        }

        var assignments = [Int](repeating: 0, count: colors.count)
        for _ in 0..<20 {
            var changed = false
            for (i, c) in colors.enumerated() {
                var bestC = 0
                var bestD = Double.greatestFiniteMagnitude
                for (j, cent) in centroids.enumerated() {
                    let d = distance(c, cent)
                    if d < bestD { bestD = d; bestC = j }
                }
                if assignments[i] != bestC {
                    assignments[i] = bestC
                    changed = true
                }
            }

            var newCentroids: [RGB] = []
            var remap = [Int](repeating: 0, count: centroids.count)
            for j in 0..<centroids.count {
                let members = colors.indices.filter { assignments[$0] == j }
                if members.isEmpty { remap[j] = -1; continue }
                let m = Double(members.count)
                remap[j] = newCentroids.count
                newCentroids.append((
                    members.reduce(0) { $0 + colors[$1].r } / m,
                    members.reduce(0) { $0 + colors[$1].g } / m,
                    members.reduce(0) { $0 + colors[$1].b } / m
                ))
            }
            if newCentroids.count < centroids.count {
                for i in 0..<assignments.count {
                    let r = remap[assignments[i]]
                    assignments[i] = max(0, r)
                }
            }
            centroids = newCentroids
            if !changed { break }
        }

        // Merge near-duplicate centroids.
        var merged = true
        while merged, centroids.count > 1 {
            merged = false
            outer: for i in 0..<centroids.count {
                for j in (i + 1)..<centroids.count {
                    if distance(centroids[i], centroids[j]) < 0.10 {
                        let members = assignments.indices.filter { assignments[$0] == i || assignments[$0] == j }
                        let m = Double(members.count)
                        let combined: RGB = (
                            members.reduce(0) { $0 + colors[$1].r } / m,
                            members.reduce(0) { $0 + colors[$1].g } / m,
                            members.reduce(0) { $0 + colors[$1].b } / m
                        )
                        centroids[i] = combined
                        centroids.remove(at: j)
                        for idx in assignments.indices {
                            if assignments[idx] == j { assignments[idx] = i }
                            else if assignments[idx] > j { assignments[idx] -= 1 }
                        }
                        merged = true
                        break outer
                    }
                }
            }
        }

        // Sort darkest-first for stable MC/CC naming.
        let order = centroids.indices.sorted {
            luminance(centroids[$0]) < luminance(centroids[$1])
        }
        var indexMap = [Int](repeating: 0, count: centroids.count)
        for (newIdx, oldIdx) in order.enumerated() {
            indexMap[oldIdx] = newIdx
        }
        return (order.map { centroids[$0] }, assignments.map { indexMap[$0] })
    }

    private static func luminance(_ c: RGB) -> Double {
        0.299 * c.r + 0.587 * c.g + 0.114 * c.b
    }
}
