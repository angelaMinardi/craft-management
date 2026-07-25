//
//  GridAlignmentEditor.swift
//  PatternVault
//
//  Visual grid alignment editor with drag handles for adjusting grid insets.
//  Shows chart image with grid overlay and draggable edges/corners.
//

import SwiftUI

struct GridAlignmentEditor: View {
    @Binding var highlight: ChartHighlight
    @Environment(\.dismiss) private var dismiss

    @State private var imageSize: CGSize = .zero
    @State private var initialInsets: (left: Double, top: Double, right: Double, bottom: Double) = (0, 0, 0, 0)
    @State private var showPreciseSheet = false
    @State private var isSelectingGrid = false
    @State private var lassoStart: CGPoint?
    @State private var lassoEnd: CGPoint?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                gridControls
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.top, Theme.Spacing.sm)

                GeometryReader { geo in
                    let chartImage = chartUIImage
                    if let chartImage {
                        chartWithOverlay(image: chartImage, containerSize: geo.size)
                    } else {
                        emptyState
                    }
                }
                .padding(Theme.Spacing.md)
            }
            .background(Theme.warmCream)
            .navigationTitle("Align Grid")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showPreciseSheet) {
                PreciseGridFitSheet(highlight: $highlight)
            }
            .onAppear {
                initialInsets = (highlight.gridInsetLeft, highlight.gridInsetTop, highlight.gridInsetRight, highlight.gridInsetBottom)
            }
        }
    }

    // MARK: - Grid Controls

    @ViewBuilder
    private var gridControls: some View {
        VStack(spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.md) {
                gridDimensionControl(title: "Rows", value: highlight.rows) {
                    highlight.rows = max(1, highlight.rows - 1)
                    highlight.currentRow = min(highlight.currentRow, highlight.rows)
                } increment: {
                    highlight.rows = min(999, highlight.rows + 1)
                }
                gridDimensionControl(title: "Cols", value: highlight.columns) {
                    highlight.columns = max(1, highlight.columns - 1)
                    highlight.currentColumn = min(highlight.currentColumn, highlight.columns)
                } increment: {
                    highlight.columns = min(999, highlight.columns + 1)
                }
            }

            HStack(spacing: Theme.Spacing.sm) {
                Button("Reset") {
                    highlight.gridInsetLeft = initialInsets.left
                    highlight.gridInsetTop = initialInsets.top
                    highlight.gridInsetRight = initialInsets.right
                    highlight.gridInsetBottom = initialInsets.bottom
                }
                .buttonStyle(.bordered)
                .font(Theme.Typography.caption)

                Button("Precise") {
                    showPreciseSheet = true
                }
                .buttonStyle(.bordered)
                .font(Theme.Typography.caption)

                Button {
                    isSelectingGrid.toggle()
                    if !isSelectingGrid {
                        lassoStart = nil
                        lassoEnd = nil
                    }
                } label: {
                    Label("Select", systemImage: "rectangle.dashed")
                }
                .buttonStyle(.bordered)
                .font(Theme.Typography.caption)
                .tint(isSelectingGrid ? Theme.softCoral : nil)

                Spacer()

                Text(isSelectingGrid ? "Draw rectangle around grid" : "Drag edges to align grid")
                    .font(Theme.Typography.caption2)
                    .foregroundStyle(Theme.deepPlum.opacity(0.5))
            }
        }
    }

    // MARK: - Chart with Overlay

    private func fittedSize(for image: UIImage, in containerSize: CGSize) -> CGSize {
        let imageAspect = image.size.width / image.size.height
        let containerAspect = containerSize.width / containerSize.height
        if imageAspect > containerAspect {
            return CGSize(width: containerSize.width, height: containerSize.width / imageAspect)
        } else {
            return CGSize(width: containerSize.height * imageAspect, height: containerSize.height)
        }
    }

    @ViewBuilder
    private func chartWithOverlay(image: UIImage, containerSize: CGSize) -> some View {
        let displaySize = fittedSize(for: image, in: containerSize)

        ZStack {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: displaySize.width, height: displaySize.height)

            // Grid overlay
            ChartHighlighterOverlayView(
                highlight: fullFrameHighlight,
                rowValue: min(max(highlight.currentRow, 1), max(1, highlight.rows)),
                columnValue: min(max(highlight.currentColumn, 1), max(1, highlight.columns))
            )
            .frame(width: displaySize.width, height: displaySize.height)

            if isSelectingGrid {
                // Lasso selection overlay
                lassoOverlay(displaySize: displaySize)
                    .frame(width: displaySize.width, height: displaySize.height)
            } else {
                // Drag handles
                gridDragHandles(displaySize: displaySize)
                    .frame(width: displaySize.width, height: displaySize.height)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Lasso Selection

    @ViewBuilder
    private func lassoOverlay(displaySize: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            // Full-area gesture target
            Color.clear
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 5)
                    .onChanged { value in
                        lassoStart = value.startLocation
                        lassoEnd = value.location
                    }
                    .onEnded { value in
                        guard let start = lassoStart else { return }
                        let end = value.location
                        let minX = max(0, min(start.x, end.x))
                        let maxX = min(displaySize.width, max(start.x, end.x))
                        let minY = max(0, min(start.y, end.y))
                        let maxY = min(displaySize.height, max(start.y, end.y))
                        let wFrac = (maxX - minX) / displaySize.width
                        let hFrac = (maxY - minY) / displaySize.height
                        if wFrac > 0.05, hFrac > 0.05 {
                            let roughLeft = Double(minX / displaySize.width)
                            let roughRight = max(0, 1.0 - Double(maxX / displaySize.width))
                            let roughTop = Double(minY / displaySize.height)
                            let roughBottom = max(0, 1.0 - Double(maxY / displaySize.height))
                            // Apply raw lasso immediately for instant feedback
                            highlight.gridInsetLeft = min(0.85, roughLeft)
                            highlight.gridInsetRight = min(0.85, roughRight)
                            highlight.gridInsetTop = min(0.85, roughTop)
                            highlight.gridInsetBottom = min(0.85, roughBottom)
                            // Then refine in the background: lattice solver first
                            // (instant, deterministic), AI region refinement as fallback.
                            let img = chartUIImage
                            let rows = highlight.rows
                            let cols = highlight.columns
                            Task {
                                guard let img else { return }
                                let prior = ChartGridSolver.PriorRegion(
                                    xMin: roughLeft, yMin: roughTop,
                                    xMax: 1 - roughRight, yMax: 1 - roughBottom
                                )
                                let solved = await Task.detached(priority: .userInitiated) {
                                    ChartGridSolver.solve(
                                        image: img, expectedRows: rows, expectedColumns: cols, prior: prior
                                    )
                                }.value
                                if let solved, solved.confidence >= 0.6 {
                                    highlight.gridInsetLeft = min(0.85, solved.insetLeft)
                                    highlight.gridInsetRight = min(0.85, solved.insetRight)
                                    highlight.gridInsetTop = min(0.85, solved.insetTop)
                                    highlight.gridInsetBottom = min(0.85, solved.insetBottom)
                                    highlight.rows = solved.rows
                                    highlight.columns = solved.columns
                                } else if let refined = await ChartGridDetector.refineWithinRegion(
                                    image: img,
                                    regionLeft: roughLeft,
                                    regionTop: roughTop,
                                    regionRight: roughRight,
                                    regionBottom: roughBottom,
                                    expectedRows: rows,
                                    expectedCols: cols
                                ) {
                                    await MainActor.run {
                                        highlight.gridInsetLeft = min(0.85, refined.left)
                                        highlight.gridInsetRight = min(0.85, refined.right)
                                        highlight.gridInsetTop = min(0.85, refined.top)
                                        highlight.gridInsetBottom = min(0.85, refined.bottom)
                                    }
                                }
                            }
                        }
                        isSelectingGrid = false
                        lassoStart = nil
                        lassoEnd = nil
                    })

            // Dashed rectangle preview during drag
            if let start = lassoStart, let end = lassoEnd {
                let rect = CGRect(
                    x: min(start.x, end.x),
                    y: min(start.y, end.y),
                    width: abs(end.x - start.x),
                    height: abs(end.y - start.y)
                )
                Rectangle()
                    .stroke(Theme.softCoral, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
            }
        }
    }

    // MARK: - Drag Handles

    @ViewBuilder
    private func gridDragHandles(displaySize: CGSize) -> some View {
        let gridLeft = displaySize.width * highlight.gridInsetLeft
        let gridTop = displaySize.height * highlight.gridInsetTop
        let gridRight = displaySize.width * (1 - highlight.gridInsetRight)
        let gridBottom = displaySize.height * (1 - highlight.gridInsetBottom)

        ZStack(alignment: .topLeading) {
            // Left edge handle
            edgeHandle(
                x: gridLeft,
                y: (gridTop + gridBottom) / 2,
                orientation: .vertical,
                height: gridBottom - gridTop
            )
            .gesture(DragGesture(minimumDistance: 1)
                .onChanged { value in
                    let newInset = max(0, min(0.85, Double(value.location.x / displaySize.width)))
                    if newInset + highlight.gridInsetRight < 0.9 {
                        highlight.gridInsetLeft = newInset
                    }
                })

            // Right edge handle
            edgeHandle(
                x: gridRight,
                y: (gridTop + gridBottom) / 2,
                orientation: .vertical,
                height: gridBottom - gridTop
            )
            .gesture(DragGesture(minimumDistance: 1)
                .onChanged { value in
                    let newInset = max(0, min(0.85, 1.0 - Double(value.location.x / displaySize.width)))
                    if highlight.gridInsetLeft + newInset < 0.9 {
                        highlight.gridInsetRight = newInset
                    }
                })

            // Top edge handle
            edgeHandle(
                x: (gridLeft + gridRight) / 2,
                y: gridTop,
                orientation: .horizontal,
                height: gridRight - gridLeft
            )
            .gesture(DragGesture(minimumDistance: 1)
                .onChanged { value in
                    let newInset = max(0, min(0.85, Double(value.location.y / displaySize.height)))
                    if newInset + highlight.gridInsetBottom < 0.9 {
                        highlight.gridInsetTop = newInset
                    }
                })

            // Bottom edge handle
            edgeHandle(
                x: (gridLeft + gridRight) / 2,
                y: gridBottom,
                orientation: .horizontal,
                height: gridRight - gridLeft
            )
            .gesture(DragGesture(minimumDistance: 1)
                .onChanged { value in
                    let newInset = max(0, min(0.85, 1.0 - Double(value.location.y / displaySize.height)))
                    if highlight.gridInsetTop + newInset < 0.9 {
                        highlight.gridInsetBottom = newInset
                    }
                })

            // Corner handles
            cornerHandle(x: gridLeft, y: gridTop)
                .gesture(DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let newLeft = max(0, min(0.85, Double(value.location.x / displaySize.width)))
                        let newTop = max(0, min(0.85, Double(value.location.y / displaySize.height)))
                        if newLeft + highlight.gridInsetRight < 0.9 { highlight.gridInsetLeft = newLeft }
                        if newTop + highlight.gridInsetBottom < 0.9 { highlight.gridInsetTop = newTop }
                    })

            cornerHandle(x: gridRight, y: gridTop)
                .gesture(DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let newRight = max(0, min(0.85, 1.0 - Double(value.location.x / displaySize.width)))
                        let newTop = max(0, min(0.85, Double(value.location.y / displaySize.height)))
                        if highlight.gridInsetLeft + newRight < 0.9 { highlight.gridInsetRight = newRight }
                        if newTop + highlight.gridInsetBottom < 0.9 { highlight.gridInsetTop = newTop }
                    })

            cornerHandle(x: gridLeft, y: gridBottom)
                .gesture(DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let newLeft = max(0, min(0.85, Double(value.location.x / displaySize.width)))
                        let newBottom = max(0, min(0.85, 1.0 - Double(value.location.y / displaySize.height)))
                        if newLeft + highlight.gridInsetRight < 0.9 { highlight.gridInsetLeft = newLeft }
                        if highlight.gridInsetTop + newBottom < 0.9 { highlight.gridInsetBottom = newBottom }
                    })

            cornerHandle(x: gridRight, y: gridBottom)
                .gesture(DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let newRight = max(0, min(0.85, 1.0 - Double(value.location.x / displaySize.width)))
                        let newBottom = max(0, min(0.85, 1.0 - Double(value.location.y / displaySize.height)))
                        if highlight.gridInsetLeft + newRight < 0.9 { highlight.gridInsetRight = newRight }
                        if highlight.gridInsetTop + newBottom < 0.9 { highlight.gridInsetBottom = newBottom }
                    })
        }
    }

    @ViewBuilder
    private func edgeHandle(x: CGFloat, y: CGFloat, orientation: EdgeOrientation, height: CGFloat) -> some View {
        switch orientation {
        case .vertical:
            Rectangle()
                .fill(Theme.softCoral.opacity(0.5))
                .frame(width: 3, height: height)
                .padding(.horizontal, 20)
                .contentShape(Rectangle())
                .position(x: x, y: y)
        case .horizontal:
            Rectangle()
                .fill(Theme.softCoral.opacity(0.5))
                .frame(width: height, height: 3)
                .padding(.vertical, 20)
                .contentShape(Rectangle())
                .position(x: x, y: y)
        }
    }

    @ViewBuilder
    private func cornerHandle(x: CGFloat, y: CGFloat) -> some View {
        Circle()
            .fill(Theme.softCoral)
            .frame(width: 16, height: 16)
            .overlay(Circle().stroke(Color.white, lineWidth: 2))
            .padding(14)
            .contentShape(Rectangle())
            .position(x: x, y: y)
    }

    // MARK: - Helpers

    private var chartUIImage: UIImage? {
        guard let data = highlight.extractedChartPNGData else { return nil }
        return UIImage(data: data)
    }

    private var fullFrameHighlight: ChartHighlight {
        if let imageId = highlight.imageId {
            return ChartHighlight(
                id: highlight.id,
                patternId: highlight.patternId,
                makeId: highlight.makeId,
                imageId: imageId,
                minX: 0, minY: 0, maxX: 1, maxY: 1,
                rows: highlight.rows,
                columns: highlight.columns,
                chartType: highlight.chartType,
                isSideways: highlight.isSideways,
                isC2C: highlight.isC2C,
                rowCounterLink: highlight.rowCounterLink,
                columnCounterLink: highlight.columnCounterLink,
                rowColorName: highlight.rowColorName,
                columnColorName: highlight.columnColorName,
                gridInsetLeft: highlight.gridInsetLeft,
                gridInsetTop: highlight.gridInsetTop,
                gridInsetRight: highlight.gridInsetRight,
                gridInsetBottom: highlight.gridInsetBottom,
                isAIExtracted: highlight.isAIExtracted
            )
        }
        return ChartHighlight(
            id: highlight.id,
            patternId: highlight.patternId,
            makeId: highlight.makeId,
            pdfPageIndex: highlight.pdfPageIndex ?? 0,
            minX: 0, minY: 0, maxX: 1, maxY: 1,
            rows: highlight.rows,
            columns: highlight.columns,
            chartType: highlight.chartType,
            isSideways: highlight.isSideways,
            isC2C: highlight.isC2C,
            rowCounterLink: highlight.rowCounterLink,
            columnCounterLink: highlight.columnCounterLink,
            rowColorName: highlight.rowColorName,
            columnColorName: highlight.columnColorName,
            gridInsetLeft: highlight.gridInsetLeft,
            gridInsetTop: highlight.gridInsetTop,
            gridInsetRight: highlight.gridInsetRight,
            gridInsetBottom: highlight.gridInsetBottom,
            isAIExtracted: highlight.isAIExtracted
        )
    }

    @ViewBuilder
    private func gridDimensionControl(title: String, value: Int, decrement: @escaping () -> Void, increment: @escaping () -> Void) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            Text("\(title): \(value)")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.deepPlum)
            Button(action: decrement) {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(Theme.deepPlum)
            }
            Button(action: increment) {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(Theme.deepPlum)
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "photo.badge.exclamationmark")
                .font(.system(size: 36))
                .foregroundStyle(Theme.softCoral)
            Text("No chart image available")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.deepPlum)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Precise Grid Fit Sheet (slider-based, same as original GridFitSheet)

private struct PreciseGridFitSheet: View {
    @Binding var highlight: ChartHighlight
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Grid dimensions") {
                    Stepper("Rows: \(max(1, highlight.rows))", value: rowsBinding, in: 1...999)
                    Stepper("Columns: \(max(1, highlight.columns))", value: columnsBinding, in: 1...999)
                }

                Section("Grid insets") {
                    insetSlider("Left", value: gridInsetLeftBinding)
                    insetSlider("Top", value: gridInsetTopBinding)
                    insetSlider("Right", value: gridInsetRightBinding)
                    insetSlider("Bottom", value: gridInsetBottomBinding)
                }
            }
            .navigationTitle("Precise Grid Fit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var rowsBinding: Binding<Int> {
        Binding(
            get: { max(1, highlight.rows) },
            set: {
                highlight.rows = max(1, $0)
                highlight.currentRow = min(max(1, highlight.currentRow), highlight.rows)
            }
        )
    }

    private var columnsBinding: Binding<Int> {
        Binding(
            get: { max(1, highlight.columns) },
            set: {
                highlight.columns = max(1, $0)
                highlight.currentColumn = min(max(1, highlight.currentColumn), highlight.columns)
            }
        )
    }

    private var gridInsetLeftBinding: Binding<Double> {
        Binding(get: { highlight.gridInsetLeft }, set: { highlight.gridInsetLeft = clamp($0, opposite: highlight.gridInsetRight) })
    }

    private var gridInsetTopBinding: Binding<Double> {
        Binding(get: { highlight.gridInsetTop }, set: { highlight.gridInsetTop = clamp($0, opposite: highlight.gridInsetBottom) })
    }

    private var gridInsetRightBinding: Binding<Double> {
        Binding(get: { highlight.gridInsetRight }, set: { highlight.gridInsetRight = clamp($0, opposite: highlight.gridInsetLeft) })
    }

    private var gridInsetBottomBinding: Binding<Double> {
        Binding(get: { highlight.gridInsetBottom }, set: { highlight.gridInsetBottom = clamp($0, opposite: highlight.gridInsetTop) })
    }

    private func clamp(_ value: Double, opposite: Double) -> Double {
        min(max(value, 0), max(0, 0.9 - opposite))
    }

    @ViewBuilder
    private func insetSlider(_ title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(value.wrappedValue * 100))%")
                    .font(Theme.Typography.caption2)
                    .foregroundStyle(Theme.deepPlum.opacity(0.65))
            }
            Slider(value: value, in: 0...0.85, step: 0.005)
        }
    }
}

private enum EdgeOrientation {
    case vertical, horizontal
}
