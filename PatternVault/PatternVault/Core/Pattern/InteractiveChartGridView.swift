//
//  InteractiveChartGridView.swift
//  PatternVault
//
//  Interactive knitting mode for chart highlights.
//  Displays the chart image (or clean colorwork grid) with row-by-row
//  progress tracking, auto-scroll, direction indicators, and row counter sync.
//

import SwiftUI
import UIKit

// MARK: - ZoomableScrollView

/// UIKit-backed pinch-to-zoom + pan container.
/// Uses UIScrollView which natively supports smooth zoom + pan together.
struct ZoomableScrollView<Content: View>: UIViewRepresentable {
    let content: () -> Content

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 5.0
        scrollView.showsHorizontalScrollIndicator = true
        scrollView.showsVerticalScrollIndicator = true
        scrollView.bouncesZoom = true
        scrollView.backgroundColor = .clear

        let hostView = context.coordinator.hostView
        hostView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(hostView)

        NSLayoutConstraint.activate([
            hostView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            hostView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            hostView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            hostView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            hostView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
        ])

        // Double-tap to zoom
        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.hostView.rootView = AnyView(content())
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(content: content)
    }

    class Coordinator: NSObject, UIScrollViewDelegate {
        let hostView: _UIHostingView<AnyView>

        init(content: () -> Content) {
            hostView = _UIHostingView(rootView: AnyView(content()))
            hostView.backgroundColor = .clear
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { hostView }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView = gesture.view as? UIScrollView else { return }
            if scrollView.zoomScale > 1.0 {
                scrollView.setZoomScale(1.0, animated: true)
            } else {
                let point = gesture.location(in: scrollView)
                let newScale: CGFloat = 2.5
                let size = CGSize(width: scrollView.bounds.width / newScale, height: scrollView.bounds.height / newScale)
                let origin = CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2)
                scrollView.zoom(to: CGRect(origin: origin, size: size), animated: true)
            }
        }
    }
}

// MARK: - _UIHostingView (internal UIKit helper)

/// Exposes UIHostingController's view directly for embedding in UIScrollView.
class _UIHostingView<Content: View>: UIView {
    var rootView: Content {
        didSet {
            hostController.rootView = rootView
        }
    }
    private let hostController: UIHostingController<Content>

    init(rootView: Content) {
        self.rootView = rootView
        self.hostController = UIHostingController(rootView: rootView)
        hostController.view.backgroundColor = .clear
        super.init(frame: .zero)
        addSubview(hostController.view)
        hostController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostController.view.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostController.view.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostController.view.topAnchor.constraint(equalTo: topAnchor),
            hostController.view.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: CGSize {
        hostController.view.intrinsicContentSize
    }
}

// MARK: - InteractiveChartGridView

struct InteractiveChartGridView: View {
    let highlight: ChartHighlight
    let patternId: UUID
    let makeId: UUID?

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var chartStore = ChartHighlightStore.shared
    @ObservedObject private var rowCounterStore = RowCounterStore.shared
    @State private var progress: ChartProgressState
    @State private var colorworkGrid: ColorworkGrid?
    @State private var showCleanGrid = false
    @State private var isExtracting = false
    @State private var showGridAlign = false
    @State private var showClearConfirm = false
    @State private var workingHighlight: ChartHighlight
    @State private var showRowNoteSheet = false
    @State private var rowNoteText = ""

    init(highlight: ChartHighlight, patternId: UUID, makeId: UUID?) {
        self.highlight = highlight
        self.patternId = patternId
        self.makeId = makeId
        _progress = State(initialValue:
            ChartHighlightStore.shared.loadProgress(for: highlight.id) ?? ChartProgressState()
        )
        _colorworkGrid = State(initialValue:
            ChartHighlightStore.shared.loadColorworkGrid(for: highlight.id)
        )
        _workingHighlight = State(initialValue: highlight)
    }

    private var totalRows: Int { highlight.rows }

    private var hasNoteForCurrentRow: Bool {
        guard let note = progress.rowNotes[progress.knittingModeRow] else { return false }
        return !note.isEmpty
    }

    private var completionPercent: Double {
        guard totalRows > 0 else { return 0 }
        return Double(progress.completedRows.count) / Double(totalRows) * 100
    }

    private var currentDirection: String {
        guard highlight.chartType == .workedFlat else { return "→" }
        return progress.knittingModeRow % 2 == 1 ? "←" : "→"
    }

    private var currentSideLabel: String {
        guard highlight.chartType == .workedFlat else { return "" }
        return progress.knittingModeRow % 2 == 1 ? "RS" : "WS"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                chartContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                knittingModeBar
            }
            .background(Theme.warmCream)
            .navigationTitle("Knitting Mode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        chartStore.saveProgressImmediately(progress, for: highlight.id)
                        dismiss()
                    }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    if colorworkGrid != nil {
                        Button {
                            showCleanGrid.toggle()
                        } label: {
                            Image(systemName: showCleanGrid ? "photo" : "squareshape.split.3x3")
                        }
                    }
                    Menu {
                        Button {
                            extractColorwork()
                        } label: {
                            Label("Extract Colors", systemImage: "paintpalette")
                        }
                        Button {
                            showGridAlign = true
                        } label: {
                            Label("Align Grid", systemImage: "square.grid.3x3")
                        }
                        Button(role: .destructive) {
                            showClearConfirm = true
                        } label: {
                            Label("Clear Progress", systemImage: "arrow.counterclockwise")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showGridAlign) {
                GridAlignmentEditor(highlight: $workingHighlight)
            }
            .onChange(of: workingHighlight) { _, updated in
                chartStore.save(updated)
            }
            .alert("Clear Progress?", isPresented: $showClearConfirm) {
                Button("Clear", role: .destructive) {
                    progress = ChartProgressState()
                    chartStore.saveProgressImmediately(progress, for: highlight.id)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will reset all completed rows and return to row 1.")
            }
            .sheet(isPresented: $showRowNoteSheet) {
                rowNoteSheet
            }
        }
    }

    // MARK: - Row Note Sheet

    private var rowNoteSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text("Row \(progress.knittingModeRow)")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.deepPlum)

                TextField("Add a note for this row...", text: $rowNoteText, axis: .vertical)
                    .font(Theme.Typography.body)
                    .lineLimit(3...8)
                    .textFieldStyle(.roundedBorder)

                if !progress.rowNotes.isEmpty {
                    Divider()
                    Text("All Row Notes")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.deepPlum.opacity(0.5))

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            ForEach(progress.rowNotes.keys.sorted(), id: \.self) { row in
                                if let note = progress.rowNotes[row], !note.isEmpty {
                                    HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                                        Text("Row \(row)")
                                            .font(Theme.Typography.caption)
                                            .fontWeight(.semibold)
                                            .foregroundStyle(Theme.honey)
                                            .frame(width: 50, alignment: .leading)
                                        Text(note)
                                            .font(Theme.Typography.caption)
                                            .foregroundStyle(Theme.deepPlum)
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        }
                    }
                }

                Spacer()
            }
            .padding(Theme.Spacing.md)
            .navigationTitle("Row Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showRowNoteSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if rowNoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            progress.rowNotes.removeValue(forKey: progress.knittingModeRow)
                        } else {
                            progress.rowNotes[progress.knittingModeRow] = rowNoteText.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                        chartStore.saveProgress(progress, for: highlight.id)
                        showRowNoteSheet = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Chart Content

    @ViewBuilder
    private var chartContent: some View {
        let h = chartStore.highlights.first(where: { $0.id == highlight.id }) ?? highlight

        ZoomableScrollView {
            Group {
                if showCleanGrid, let grid = colorworkGrid {
                    cleanGridCanvas(grid: grid, highlight: h)
                } else if let data = h.extractedChartPNGData, let img = UIImage(data: data) {
                    imageBackedGrid(image: img, highlight: h)
                } else {
                    Text("No chart image available")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.deepPlum.opacity(0.5))
                }
            }
        }
        .overlay {
            if isExtracting {
                ZStack {
                    Color.black.opacity(0.3)
                    VStack(spacing: Theme.Spacing.sm) {
                        ProgressView()
                            .tint(.white)
                        Text("Extracting colors...")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(.white)
                    }
                    .padding(Theme.Spacing.lg)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
                }
            }
        }
    }

    // MARK: - Image-Backed Grid

    /// Avoid a root `GeometryReader` here: inside `ZoomableScrollView` the hosted view gets a
    /// definite width but not height, so the reader collapses and the chart draws at zero size.
    private func imageBackedGrid(image: UIImage, highlight h: ChartHighlight) -> some View {
        Image(uiImage: image)
            .resizable()
            .interpolation(.none)
            .scaledToFit()
            .frame(maxWidth: .infinity)
            .overlay {
                GeometryReader { geo in
                    Canvas { context, size in
                        drawGridOverlay(
                            context: &context, size: size,
                            highlight: h, rows: h.rows, cols: h.columns
                        )
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        handleRowTap(location: location, highlight: h, size: geo.size)
                    }
                }
            }
    }

    // MARK: - Clean Colorwork Grid

    private func cleanGridCanvas(grid: ColorworkGrid, highlight h: ChartHighlight) -> some View {
        let cols = CGFloat(grid.columns)
        let rows = CGFloat(grid.rows)

        return Color.clear
            .aspectRatio(cols / rows, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay {
                GeometryReader { geo in
                    Canvas { context, size in
                        let cw = size.width / CGFloat(grid.columns)
                        let ch = size.height / CGFloat(grid.rows)

                        for row in 0..<grid.rows {
                            for col in 0..<grid.columns {
                                let displayRow = h.usesBottomRightIndexing ? (grid.rows - 1 - row) : row
                                if let yarn = grid.color(atRow: displayRow, column: col) {
                                    let rect = CGRect(x: CGFloat(col) * cw, y: CGFloat(row) * ch, width: cw, height: ch)
                                    context.fill(Path(rect), with: .color(yarn.color))
                                }
                            }
                        }

                        context.stroke(
                            gridLinesPath(rows: grid.rows, cols: grid.columns, cellW: cw, cellH: ch, inSize: size),
                            with: .color(Color.black.opacity(0.2)),
                            lineWidth: 0.5
                        )

                        drawRowHighlightAndCompletion(
                            context: &context, rows: grid.rows,
                            yOffset: 0, gridHeight: size.height, gridWidth: size.width,
                            rowHeight: ch
                        )
                    }
                    .border(Theme.deepPlum.opacity(0.3), width: 1)
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        let ch = geo.size.height / CGFloat(grid.rows)
                        let tappedVisualRow = Int(location.y / ch)
                        let knittingRow = highlight.usesBottomRightIndexing
                            ? (grid.rows - tappedVisualRow)
                            : (tappedVisualRow + 1)
                        if knittingRow >= 1 && knittingRow <= totalRows {
                            progress.knittingModeRow = knittingRow
                            syncRowCounter()
                            HapticService.lightImpact()
                        }
                    }
                }
            }
    }

    // MARK: - Grid Overlay Drawing

    private func drawGridOverlay(
        context: inout GraphicsContext, size: CGSize,
        highlight h: ChartHighlight, rows: Int, cols: Int
    ) {
        // Compute grid rect from insets
        let gridX = h.gridInsetLeft * size.width
        let gridY = h.gridInsetTop * size.height
        let gridW = size.width * (1 - h.gridInsetLeft - h.gridInsetRight)
        let gridH = size.height * (1 - h.gridInsetTop - h.gridInsetBottom)
        let cellW = gridW / CGFloat(cols)
        let cellH = gridH / CGFloat(rows)

        // Grid lines
        var gridPath = Path()
        for r in 0...rows {
            let y = gridY + CGFloat(r) * cellH
            gridPath.move(to: CGPoint(x: gridX, y: y))
            gridPath.addLine(to: CGPoint(x: gridX + gridW, y: y))
        }
        for c in 0...cols {
            let x = gridX + CGFloat(c) * cellW
            gridPath.move(to: CGPoint(x: x, y: gridY))
            gridPath.addLine(to: CGPoint(x: x, y: gridY + gridH))
        }
        context.stroke(gridPath, with: .color(Theme.deepPlum.opacity(0.15)), lineWidth: 0.5)

        // Row highlight and completion
        drawRowHighlightAndCompletion(
            context: &context,
            rows: rows,
            yOffset: gridY, gridHeight: gridH, gridWidth: gridW,
            rowHeight: cellH,
            xOffset: gridX
        )
    }

    private func drawRowHighlightAndCompletion(
        context: inout GraphicsContext,
        rows: Int,
        yOffset: CGFloat, gridHeight: CGFloat, gridWidth: CGFloat,
        rowHeight: CGFloat,
        xOffset: CGFloat = 0
    ) {
        for row in 1...rows {
            let visualRow: Int
            if highlight.usesBottomRightIndexing {
                visualRow = rows - row  // row 1 at bottom → visual row (rows-1)
            } else {
                visualRow = row - 1     // row 1 at top → visual row 0
            }

            let y = yOffset + CGFloat(visualRow) * rowHeight

            if progress.completedRows.contains(row) {
                // Completed row: dim overlay
                let rect = CGRect(x: xOffset, y: y, width: gridWidth, height: rowHeight)
                context.fill(Path(rect), with: .color(Color.black.opacity(0.12)))
            }

            if row == progress.knittingModeRow {
                // Current row: honey highlight
                let rect = CGRect(x: xOffset, y: y, width: gridWidth, height: rowHeight)
                context.fill(Path(rect), with: .color(Theme.honey.opacity(0.35)))

                // Row number label
                let text = Text("\(row)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.deepPlum)
                context.draw(text, at: CGPoint(x: xOffset - 14, y: y + rowHeight / 2))
            }
        }
    }

    private func gridLinesPath(rows: Int, cols: Int, cellW: CGFloat, cellH: CGFloat, inSize size: CGSize) -> Path {
        var path = Path()
        for r in 0...rows {
            let y = CGFloat(r) * cellH
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
        }
        for c in 0...cols {
            let x = CGFloat(c) * cellW
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
        }
        return path
    }

    // MARK: - Row Tap Handling

    private func handleRowTap(location: CGPoint, highlight h: ChartHighlight, size: CGSize) {
        let gridY = h.gridInsetTop * size.height
        let gridH = size.height * (1 - h.gridInsetTop - h.gridInsetBottom)
        let cellH = gridH / CGFloat(h.rows)

        let visualRow = Int((location.y - gridY) / cellH)
        guard visualRow >= 0, visualRow < h.rows else { return }

        let knittingRow: Int
        if h.usesBottomRightIndexing {
            knittingRow = h.rows - visualRow
        } else {
            knittingRow = visualRow + 1
        }

        guard knittingRow >= 1, knittingRow <= totalRows else { return }
        progress.knittingModeRow = knittingRow
        syncRowCounter()
        HapticService.lightImpact()
    }

    // MARK: - Knitting Mode Bar

    private var knittingModeBar: some View {
        VStack(spacing: Theme.Spacing.xs) {
            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Theme.deepPlum.opacity(0.1))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Theme.sageGreen)
                        .frame(width: geo.size.width * completionPercent / 100)
                }
            }
            .frame(height: 6)
            .padding(.horizontal, Theme.Spacing.md)

            HStack(spacing: Theme.Spacing.lg) {
                // Previous row
                Button {
                    previousRow()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(progress.knittingModeRow > 1 ? Theme.deepPlum : Theme.deepPlum.opacity(0.3))
                }
                .disabled(progress.knittingModeRow <= 1)

                // Row display
                VStack(spacing: 2) {
                    HStack(spacing: Theme.Spacing.xs) {
                        if highlight.chartType == .workedFlat {
                            Text(currentSideLabel)
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(Theme.dustyBlue)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Theme.dustyBlue.opacity(0.15))
                                .clipShape(Capsule())
                        }
                        Text("Row \(progress.knittingModeRow)")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.deepPlum)
                            .contentTransition(.numericText())
                        Text(currentDirection)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Theme.deepPlum.opacity(0.5))
                    }
                    Text("of \(totalRows) \u{00B7} \(Int(completionPercent))% done")
                        .font(Theme.Typography.caption2)
                        .foregroundStyle(Theme.deepPlum.opacity(0.5))
                }

                // Next row
                Button {
                    nextRow()
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(progress.knittingModeRow < totalRows ? Theme.deepPlum : Theme.deepPlum.opacity(0.3))
                }
                .disabled(progress.knittingModeRow >= totalRows)
            }
            .padding(.vertical, Theme.Spacing.sm)
            .padding(.horizontal, Theme.Spacing.md)

            // Row note indicator + button
            HStack(spacing: Theme.Spacing.xs) {
                Button {
                    rowNoteText = progress.rowNotes[progress.knittingModeRow] ?? ""
                    showRowNoteSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: hasNoteForCurrentRow ? "note.text" : "note.text.badge.plus")
                            .font(.system(size: 13))
                        Text(hasNoteForCurrentRow ? "View Note" : "Add Note")
                            .font(Theme.Typography.caption2)
                    }
                    .foregroundStyle(hasNoteForCurrentRow ? Theme.honey : Theme.deepPlum.opacity(0.5))
                }

                if hasNoteForCurrentRow,
                   let note = progress.rowNotes[progress.knittingModeRow] {
                    Text(note)
                        .font(Theme.Typography.caption2)
                        .foregroundStyle(Theme.deepPlum.opacity(0.7))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Spacer()
            }
            .padding(.horizontal, Theme.Spacing.md)
        }
        .padding(.bottom, Theme.Spacing.sm)
        .background(Theme.cardBackground)
        .shadow(color: .black.opacity(0.05), radius: 4, y: -2)
    }

    // MARK: - Row Navigation

    private func nextRow() {
        guard progress.knittingModeRow < totalRows else { return }
        progress.completedRows.insert(progress.knittingModeRow)
        progress.knittingModeRow += 1
        syncRowCounter()
        chartStore.saveProgress(progress, for: highlight.id)
        HapticService.lightImpact()
    }

    private func previousRow() {
        guard progress.knittingModeRow > 1 else { return }
        progress.knittingModeRow -= 1
        progress.completedRows.remove(progress.knittingModeRow)
        syncRowCounter()
        chartStore.saveProgress(progress, for: highlight.id)
        HapticService.lightImpact()
    }

    private func syncRowCounter() {
        guard let link = highlight.rowCounterLink as ChartHighlight.CounterLink? else { return }
        switch link {
        case .global:
            rowCounterStore.jumpToRow(patternId: patternId, makeId: makeId, row: progress.knittingModeRow)
        case .secondary:
            // Secondary counter sync handled by RowCounterStore internally
            rowCounterStore.jumpToRow(patternId: patternId, makeId: makeId, row: progress.knittingModeRow)
        }
    }

    // MARK: - Colorwork Extraction

    private func extractColorwork() {
        guard let data = highlight.extractedChartPNGData,
              let image = UIImage(data: data) else { return }

        isExtracting = true
        Task.detached {
            let result = ColorworkGridDetector.detect(
                image: image,
                expectedRows: highlight.rows,
                expectedCols: highlight.columns
            )

            await MainActor.run {
                isExtracting = false
                if let result {
                    colorworkGrid = result.grid
                    chartStore.saveColorworkGrid(result.grid, for: highlight.id)

                    // Only update grid insets if the existing ones are defaults (all near zero).
                    // If the border line detector or user already set good insets, keep them.
                    var updated = chartStore.highlights.first(where: { $0.id == highlight.id }) ?? highlight
                    let hasExistingInsets = updated.gridInsetLeft > 0.01 || updated.gridInsetTop > 0.01
                        || updated.gridInsetRight > 0.01 || updated.gridInsetBottom > 0.01
                    if !hasExistingInsets {
                        updated.gridInsetLeft = result.gridInsets.left
                        updated.gridInsetTop = result.gridInsets.top
                        updated.gridInsetRight = result.gridInsets.right
                        updated.gridInsetBottom = result.gridInsets.bottom
                    }
                    updated.rows = result.detectedRows
                    updated.columns = result.detectedColumns
                    updated.isColorwork = true
                    chartStore.save(updated)

                    showCleanGrid = true
                    HapticService.success()
                }
            }
        }
    }
}
