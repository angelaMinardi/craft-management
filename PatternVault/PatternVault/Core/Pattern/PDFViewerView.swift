//
//  PDFViewerView.swift
//  PatternVault
//
//  PDFKit-backed viewer with chart overlay/highlighter support.
//

import PDFKit
import PencilKit
import SwiftUI

struct PDFViewerView: View {
    let url: URL
    let patternId: UUID
    let makeId: UUID?
    var onDetectCharts: (() -> Void)?

    @State private var document: PDFDocument?
    @State private var errorMessage: String?
    @State private var currentPageIndex = 0
    @State private var showChartSetup = false
    @State private var workspaceHighlight: ChartHighlight?
    @State private var selectedPageHighlightId: UUID?

    @ObservedObject private var chartStore = ChartHighlightStore.shared
    @ObservedObject private var rowCounterStore = RowCounterStore.shared

    var body: some View {
        ZStack {
            if let document {
                PDFChartViewRepresentable(
                    document: document,
                    highlight: nil,
                    rowValue: 1,
                    columnValue: 1,
                    currentPageIndex: $currentPageIndex
                )
                .ignoresSafeArea(edges: .bottom)
            } else if let errorMessage {
                VStack(spacing: Theme.Spacing.md) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(Theme.softCoral)
                    Text(errorMessage)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.deepPlum)
                        .multilineTextAlignment(.center)
                }
                .padding(Theme.Spacing.xl)
            } else {
                ProgressView("Loading PDF…")
            }

            if document != nil {
                VStack {
                    HStack {
                        if !pageHighlights.isEmpty {
                            Text(pageHighlights.count == 1 ? "1 chart linked" : "\(pageHighlights.count) charts linked")
                                .font(Theme.Typography.caption2.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Theme.sageGreen.opacity(0.9))
                                .clipShape(Capsule())
                                .padding(.leading, Theme.Spacing.md)
                                .padding(.top, Theme.Spacing.md)
                        }
                        Spacer()
                        if let onDetectCharts,
                           chartStore.aiExtractedHighlights(patternId: patternId).isEmpty {
                            Button {
                                onDetectCharts()
                            } label: {
                                Label("Detect Charts", systemImage: "wand.and.stars")
                                    .font(Theme.Typography.captionSemibold)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Theme.sageGreen)
                                    .clipShape(Capsule())
                            }
                            .padding(.trailing, Theme.Spacing.xs)
                            .padding(.top, Theme.Spacing.md)
                        }
                        Button {
                            showChartSetup = true
                        } label: {
                            Image(systemName: "highlighter")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(10)
                                .background(Theme.dustyBlue)
                                .clipShape(Circle())
                        }
                        .padding(.trailing, Theme.Spacing.md)
                        .padding(.top, Theme.Spacing.md)
                    }
                    Spacer()
                    Text("Page \(currentPageIndex + 1)")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.deepPlum.opacity(0.75))
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.vertical, Theme.Spacing.xs)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .padding(.bottom, Theme.Spacing.md)

                    if !pageHighlights.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: Theme.Spacing.sm) {
                                ForEach(pageHighlights) { highlight in
                                    let isSelected = highlight.id == selectedHighlight?.id
                                    Button {
                                        selectedPageHighlightId = highlight.id
                                        workspaceHighlight = highlight
                                    } label: {
                                        ZStack(alignment: .topTrailing) {
                                            if let data = highlight.extractedChartPNGData,
                                               let chartImage = UIImage(data: data) {
                                                Image(uiImage: chartImage)
                                                    .resizable()
                                                    .aspectRatio(contentMode: .fill)
                                                    .frame(width: 84, height: 84)
                                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                            } else {
                                                RoundedRectangle(cornerRadius: 10)
                                                    .fill(Theme.cardBackground)
                                                    .frame(width: 84, height: 84)
                                            }

                                            Text("#\(chartOrdinal(for: highlight))")
                                                .font(Theme.Typography.caption2.weight(.semibold))
                                                .foregroundStyle(.white)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 3)
                                                .background(Theme.deepPlum.opacity(0.75))
                                                .clipShape(Capsule())
                                                .padding(6)
                                        }
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .stroke(isSelected ? Theme.softCoral : Theme.Semantic.borderStrong, lineWidth: 2)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.bottom, Theme.Spacing.md)
                        }
                    }
                }
            }
        }
        .task {
            if document == nil && errorMessage == nil {
                await loadDocument()
            }
        }
        .sheet(isPresented: $showChartSetup) {
            PDFChartHighlighterSetupSheet(
                patternId: patternId,
                makeId: makeId,
                pageIndex: currentPageIndex,
                pagePreviewImage: currentPagePreviewImage,
                existing: nil,
                secondaryCounters: rowCounterStore.state(for: patternId, makeId: makeId).secondaryCounters,
                onSave: { chartStore.save($0) },
                onDelete: {
                    chartStore.delete(patternId: patternId, makeId: makeId, pdfPageIndex: currentPageIndex)
                }
            )
        }
        .sheet(item: $workspaceHighlight) { highlight in
            ExtractedChartWorkspaceView(
                highlight: highlight,
                patternId: patternId,
                makeId: makeId,
                onSave: { chartStore.save($0) }
            )
        }
    }

    private var pageHighlight: ChartHighlight? {
        chartStore.highlight(patternId: patternId, makeId: makeId, pdfPageIndex: currentPageIndex)
    }

    private var pageHighlights: [ChartHighlight] {
        chartStore.highlightsForPDFPage(patternId: patternId, makeId: makeId, pdfPageIndex: currentPageIndex)
            .filter { $0.extractedChartPNGData != nil }
    }

    private var selectedHighlight: ChartHighlight? {
        if let id = selectedPageHighlightId,
           let found = pageHighlights.first(where: { $0.id == id }) {
            return found
        }
        return pageHighlights.first
    }

    private var currentPagePreviewImage: UIImage? {
        guard let page = document?.page(at: currentPageIndex) else { return nil }
        return page.thumbnail(of: CGSize(width: 1200, height: 1600), for: .mediaBox)
    }

    private func loadDocument() async {
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                errorMessage = "Could not open PDF (HTTP \(http.statusCode))."
                return
            }
            guard let document = PDFDocument(data: data) else {
                errorMessage = "Could not parse this PDF."
                return
            }
            self.document = document
        } catch {
            errorMessage = "Could not load PDF. Check your connection and try again."
        }
    }

    private func chartOrdinal(for highlight: ChartHighlight) -> Int {
        let ids = pageHighlights.map(\.id)
        return (ids.firstIndex(of: highlight.id) ?? 0) + 1
    }
}

private struct PDFChartViewRepresentable: UIViewRepresentable {
    let document: PDFDocument
    let highlight: ChartHighlight?
    let rowValue: Int
    let columnValue: Int
    @Binding var currentPageIndex: Int

    func makeUIView(context: Context) -> PDFChartContainerUIView {
        let view = PDFChartContainerUIView()
        view.pdfView.document = document
        view.pdfView.autoScales = true
        view.pdfView.displayMode = .singlePageContinuous
        view.pdfView.displayDirection = .vertical
        view.pdfView.displaysPageBreaks = true

        context.coordinator.attach(to: view.pdfView, document: document)
        view.updateOverlay(highlight: highlight, rowValue: rowValue, columnValue: columnValue)
        return view
    }

    func updateUIView(_ uiView: PDFChartContainerUIView, context: Context) {
        if uiView.pdfView.document !== document {
            uiView.pdfView.document = document
            context.coordinator.attach(to: uiView.pdfView, document: document)
        }
        context.coordinator.parent = self
        uiView.updateOverlay(highlight: highlight, rowValue: rowValue, columnValue: columnValue)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject {
        var parent: PDFChartViewRepresentable
        private weak var pdfView: PDFView?
        private weak var document: PDFDocument?
        private var observer: NSObjectProtocol?

        init(parent: PDFChartViewRepresentable) {
            self.parent = parent
        }

        deinit {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        func attach(to pdfView: PDFView, document: PDFDocument) {
            self.pdfView = pdfView
            self.document = document
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
            observer = NotificationCenter.default.addObserver(
                forName: Notification.Name.PDFViewPageChanged,
                object: pdfView,
                queue: .main
            ) { [weak self] _ in
                guard let self, let page = pdfView.currentPage else { return }
                let index = document.index(for: page)
                self.parent.currentPageIndex = max(0, index)
            }

            if let page = pdfView.currentPage {
                parent.currentPageIndex = max(0, document.index(for: page))
            } else {
                parent.currentPageIndex = 0
            }
        }
    }
}

private final class PDFChartContainerUIView: UIView {
    let pdfView = PDFView()
    private let overlayView = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(pdfView)
        addSubview(overlayView)
        overlayView.isUserInteractionEnabled = false
        overlayView.backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        pdfView.frame = bounds
        overlayView.frame = bounds
    }

    func updateOverlay(highlight: ChartHighlight?, rowValue: Int, columnValue: Int) {
        overlayView.layer.sublayers?.forEach { $0.removeFromSuperlayer() }
        guard let highlight,
              let page = pdfView.currentPage,
              let pageIndex = highlight.pdfPageIndex,
              let document = pdfView.document,
              pageIndex == document.index(for: page) else {
            return
        }

        let pageBounds = page.bounds(for: pdfView.displayBox)
        let pageRect = pdfView.convert(pageBounds, from: page)
        if pageRect.isNull || pageRect.isEmpty { return }

        let rect = CGRect(
            x: pageRect.minX + pageRect.width * CGFloat(highlight.minX),
            y: pageRect.minY + pageRect.height * CGFloat(highlight.minY),
            width: pageRect.width * CGFloat(max(0.001, highlight.maxX - highlight.minX)),
            height: pageRect.height * CGFloat(max(0.001, highlight.maxY - highlight.minY))
        )

        let border = CAShapeLayer()
        border.path = UIBezierPath(rect: rect).cgPath
        border.strokeColor = UIColor(Theme.deepPlum.opacity(0.55)).cgColor
        border.fillColor = UIColor.clear.cgColor
        border.lineWidth = 2
        overlayView.layer.addSublayer(border)

        let clampedRow = min(max(rowValue, 1), max(1, highlight.rows))
        let clampedCol = min(max(columnValue, 1), max(1, highlight.columns))
        let rowHeight = rect.height / CGFloat(max(1, highlight.rows))
        let colWidth = rect.width / CGFloat(max(1, highlight.columns))

        if highlight.isC2C {
            let x = rect.minX + colWidth * CGFloat(clampedCol - 1)
            let y = rect.maxY - rowHeight * CGFloat(clampedRow)
            let path = UIBezierPath()
            path.move(to: CGPoint(x: x, y: y + rowHeight))
            path.addLine(to: CGPoint(x: x + colWidth, y: y))
            let line = CAShapeLayer()
            line.path = path.cgPath
            line.strokeColor = UIColor(Theme.honey).cgColor
            line.lineWidth = 6
            overlayView.layer.addSublayer(line)
        } else {
            let rowLayer = CAShapeLayer()
            rowLayer.path = UIBezierPath(rect: CGRect(
                x: rect.minX,
                y: rect.minY + rowHeight * CGFloat(clampedRow - 1),
                width: rect.width,
                height: rowHeight
            )).cgPath
            rowLayer.fillColor = UIColor(Theme.honey.opacity(0.35)).cgColor
            overlayView.layer.addSublayer(rowLayer)

            let colLayer = CAShapeLayer()
            colLayer.path = UIBezierPath(rect: CGRect(
                x: rect.minX + colWidth * CGFloat(clampedCol - 1),
                y: rect.minY,
                width: colWidth,
                height: rect.height
            )).cgPath
            colLayer.fillColor = UIColor(Theme.softCoral.opacity(0.25)).cgColor
            overlayView.layer.addSublayer(colLayer)
        }
    }
}

private struct PDFChartHighlighterSetupSheet: View {
    let patternId: UUID
    let makeId: UUID?
    let pageIndex: Int
    let pagePreviewImage: UIImage?
    let existing: ChartHighlight?
    let secondaryCounters: [SecondaryCounter]
    let onSave: (ChartHighlight) -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var minX: Double = 0.1
    @State private var minY: Double = 0.1
    @State private var maxX: Double = 0.9
    @State private var maxY: Double = 0.9
    @State private var rows: Int = 40
    @State private var columns: Int = 40
    @State private var chartType: ChartHighlight.ChartType = .workedFlat
    @State private var isSideways = false
    @State private var isC2C = false
    @State private var rowLinkSelection = "global"
    @State private var colLinkSelection = "global"
    @State private var activeHandle: CornerHandle?
    @State private var extractedChartData: Data?
    @State private var editorZoom: Double = 1.0

    private enum CornerHandle {
        case topLeft
        case topRight
        case bottomLeft
        case bottomRight
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Chart area (current page)") {
                    Text("Drag corner handles directly on the page preview. Zoom and pan for precise placement.")
                        .font(Theme.Typography.caption2)
                        .foregroundStyle(Theme.deepPlum.opacity(0.6))
                    visualRegionEditor
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "minus.magnifyingglass")
                            .foregroundStyle(Color.primary.opacity(0.75))
                        Slider(value: $editorZoom, in: 1...4, step: 0.1)
                        Image(systemName: "plus.magnifyingglass")
                            .foregroundStyle(Color.primary.opacity(0.75))
                        Text("\(editorZoom, specifier: "%.1f")x")
                            .font(Theme.Typography.caption2)
                            .foregroundStyle(Color.primary.opacity(0.8))
                            .frame(width: 42, alignment: .trailing)
                    }
                    slider("Left", value: $minX)
                    slider("Top", value: $minY)
                    slider("Right", value: $maxX)
                    slider("Bottom", value: $maxY)
                }
                Section("Extract chart") {
                    Button("Extract Chart From Selection") {
                        extractChartFromSelection()
                    }
                    .disabled(pagePreviewImage == nil)

                    if let extractedChartData, let chartImage = UIImage(data: extractedChartData) {
                        Image(uiImage: chartImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 220)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
                    }
                }
                Section("Grid") {
                    Stepper("Rows: \(rows)", value: $rows, in: 1...999)
                    Stepper("Columns: \(columns)", value: $columns, in: 1...999)
                    Picker("Chart type", selection: $chartType) {
                        Text("Worked flat").tag(ChartHighlight.ChartType.workedFlat)
                        Text("Worked in the round").tag(ChartHighlight.ChartType.workedInRound)
                    }
                    Toggle("Displayed sideways", isOn: $isSideways)
                    Toggle("Corner to corner (C2C)", isOn: $isC2C)
                }
                Section("Counter links") {
                    Picker("Row link", selection: $rowLinkSelection) {
                        Text("Global counter").tag("global")
                        ForEach(secondaryCounters) { c in
                            Text(c.title).tag(c.id.uuidString)
                        }
                    }
                    Picker("Column link", selection: $colLinkSelection) {
                        Text("Global counter").tag("global")
                        ForEach(secondaryCounters) { c in
                            Text(c.title).tag(c.id.uuidString)
                        }
                    }
                }
                if existing != nil {
                    Section {
                        Button("Delete chart highlighter", role: .destructive) {
                            onDelete()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("PDF Chart Highlighter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let autoExtracted = extractChartDataFromSelection()
                        let highlight = ChartHighlight(
                            id: existing?.id ?? UUID(),
                            patternId: patternId,
                            makeId: makeId,
                            pdfPageIndex: pageIndex,
                            minX: min(minX, maxX),
                            minY: min(minY, maxY),
                            maxX: max(minX, maxX),
                            maxY: max(minY, maxY),
                            rows: rows,
                            columns: columns,
                            chartType: chartType,
                            isSideways: isSideways,
                            isC2C: isC2C,
                            rowCounterLink: resolveLink(rowLinkSelection),
                            columnCounterLink: resolveLink(colLinkSelection),
                            rowColorName: "honey",
                            columnColorName: "softCoral",
                            extractedChartPNGData: autoExtracted ?? extractedChartData ?? existing?.extractedChartPNGData,
                            annotationDrawingData: existing?.annotationDrawingData,
                            currentRow: existing?.currentRow ?? 1,
                            currentColumn: existing?.currentColumn ?? 1,
                            annotations: existing?.annotations ?? [],
                            gridInsetLeft: existing?.gridInsetLeft ?? 0,
                            gridInsetTop: existing?.gridInsetTop ?? 0,
                            gridInsetRight: existing?.gridInsetRight ?? 0,
                            gridInsetBottom: existing?.gridInsetBottom ?? 0
                        )
                        onSave(highlight)
                        dismiss()
                    }
                }
            }
            .onAppear {
                guard let existing else { return }
                minX = existing.minX
                minY = existing.minY
                maxX = existing.maxX
                maxY = existing.maxY
                rows = existing.rows
                columns = existing.columns
                chartType = existing.chartType
                isSideways = existing.isSideways
                isC2C = existing.isC2C
                rowLinkSelection = selection(from: existing.rowCounterLink)
                colLinkSelection = selection(from: existing.columnCounterLink ?? .global)
                extractedChartData = existing.extractedChartPNGData
            }
        }
    }

    private func slider(_ title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title)
            Slider(value: value, in: 0...1)
            Text("\(Int(value.wrappedValue * 100))%")
                .font(Theme.Typography.caption2)
                .foregroundStyle(Theme.deepPlum.opacity(0.6))
                .frame(width: 44, alignment: .trailing)
        }
    }

    private var visualRegionEditor: some View {
        GeometryReader { geo in
            let containerSize = geo.size
            let zoom = CGFloat(editorZoom)
            let canvasSize = CGSize(
                width: max(1, containerSize.width * zoom),
                height: max(1, containerSize.height * zoom)
            )
            let contentFrame = contentFrame(in: canvasSize)
            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                ZStack {
                    if let pagePreviewImage {
                        Image(uiImage: pagePreviewImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: canvasSize.width, height: canvasSize.height)
                    } else {
                        RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                            .fill(Theme.cardBackground)
                            .overlay {
                                VStack(spacing: Theme.Spacing.xs) {
                                    Image(systemName: "doc.richtext")
                                        .font(.title2)
                                        .foregroundStyle(Theme.deepPlum.opacity(0.35))
                                    Text("Page \(pageIndex + 1)")
                                        .font(Theme.Typography.caption)
                                        .foregroundStyle(Theme.deepPlum.opacity(0.65))
                                }
                            }
                    }

                    regionOverlay(in: canvasSize, contentFrame: contentFrame)
                }
                .frame(width: canvasSize.width, height: canvasSize.height)
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
        }
        .frame(height: 320)
    }

    @ViewBuilder
    private func regionOverlay(in size: CGSize, contentFrame: CGRect) -> some View {
        let rect = CGRect(
            x: contentFrame.minX + contentFrame.width * minX,
            y: contentFrame.minY + contentFrame.height * minY,
            width: contentFrame.width * max(0.001, maxX - minX),
            height: contentFrame.height * max(0.001, maxY - minY)
        )

        ZStack {
            Path { path in
                path.addRect(CGRect(origin: .zero, size: size))
                path.addRect(rect)
            }
            .fill(Color.black.opacity(0.18), style: FillStyle(eoFill: true))

            RoundedRectangle(cornerRadius: 8)
                .stroke(Theme.honey, lineWidth: 2)
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)

            editorHandle(in: size, contentFrame: contentFrame, x: rect.minX, y: rect.minY, handle: .topLeft)
            editorHandle(in: size, contentFrame: contentFrame, x: rect.maxX, y: rect.minY, handle: .topRight)
            editorHandle(in: size, contentFrame: contentFrame, x: rect.minX, y: rect.maxY, handle: .bottomLeft)
            editorHandle(in: size, contentFrame: contentFrame, x: rect.maxX, y: rect.maxY, handle: .bottomRight)
        }
    }

    @ViewBuilder
    private func editorHandle(in size: CGSize, contentFrame: CGRect, x: CGFloat, y: CGFloat, handle: CornerHandle) -> some View {
        Circle()
            .fill(Theme.softCoral)
            .frame(width: 18, height: 18)
            .overlay(Circle().stroke(Theme.Semantic.textPrimary, lineWidth: 2))
            .position(x: x, y: y)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        activeHandle = handle
                        updateHandle(handle, location: value.location, in: contentFrame)
                    }
                    .onEnded { _ in
                        activeHandle = nil
                    }
            )
    }

    private func updateHandle(_ handle: CornerHandle, location: CGPoint, in contentFrame: CGRect) {
        guard contentFrame.width > 0, contentFrame.height > 0 else { return }
        let nx = min(max(Double((location.x - contentFrame.minX) / contentFrame.width), 0), 1)
        let ny = min(max(Double((location.y - contentFrame.minY) / contentFrame.height), 0), 1)
        let minGap = 0.03

        switch handle {
        case .topLeft:
            minX = min(nx, maxX - minGap)
            minY = min(ny, maxY - minGap)
        case .topRight:
            maxX = max(nx, minX + minGap)
            minY = min(ny, maxY - minGap)
        case .bottomLeft:
            minX = min(nx, maxX - minGap)
            maxY = max(ny, minY + minGap)
        case .bottomRight:
            maxX = max(nx, minX + minGap)
            maxY = max(ny, minY + minGap)
        }
    }

    private func resolveLink(_ selection: String) -> ChartHighlight.CounterLink {
        if selection == "global" { return .global }
        if let id = UUID(uuidString: selection) { return .secondary(id) }
        return .global
    }

    private func selection(from link: ChartHighlight.CounterLink) -> String {
        switch link {
        case .global: return "global"
        case .secondary(let id): return id.uuidString
        }
    }

    private func extractChartFromSelection() {
        extractedChartData = extractChartDataFromSelection()
    }

    private func extractChartDataFromSelection() -> Data? {
        guard let pagePreviewImage else { return nil }
        guard let cropped = cropImage(
            pagePreviewImage,
            minX: min(minX, maxX),
            minY: min(minY, maxY),
            maxX: max(minX, maxX),
            maxY: max(minY, maxY)
        ) else { return nil }
        return cropped.pngData()
    }

    private func contentFrame(in containerSize: CGSize) -> CGRect {
        guard containerSize.width > 0, containerSize.height > 0 else { return .zero }
        guard let pagePreviewImage else {
            return CGRect(origin: .zero, size: containerSize)
        }
        return aspectFitRect(contentSize: pagePreviewImage.size, in: containerSize)
    }

    private func aspectFitRect(contentSize: CGSize, in containerSize: CGSize) -> CGRect {
        guard contentSize.width > 0, contentSize.height > 0,
              containerSize.width > 0, containerSize.height > 0 else {
            return CGRect(origin: .zero, size: containerSize)
        }
        let scale = min(containerSize.width / contentSize.width, containerSize.height / contentSize.height)
        let width = contentSize.width * scale
        let height = contentSize.height * scale
        let origin = CGPoint(
            x: (containerSize.width - width) / 2,
            y: (containerSize.height - height) / 2
        )
        return CGRect(origin: origin, size: CGSize(width: width, height: height))
    }

    private func cropImage(_ image: UIImage, minX: Double, minY: Double, maxX: Double, maxY: Double) -> UIImage? {
        guard let cg = image.cgImage else { return nil }
        let width = CGFloat(cg.width)
        let height = CGFloat(cg.height)
        let rect = CGRect(
            x: width * CGFloat(minX),
            y: height * CGFloat(minY),
            width: width * CGFloat(max(0.001, maxX - minX)),
            height: height * CGFloat(max(0.001, maxY - minY))
        ).integral
        guard let cropped = cg.cropping(to: rect) else { return nil }
        return UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
    }
}

struct ExtractedChartWorkspaceView: View {
    let patternId: UUID
    let makeId: UUID?
    let onSave: (ChartHighlight) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var workingHighlight: ChartHighlight
    @State private var drawingData: Data?
    @StateObject private var canvasController = PencilCanvasController()
    @State private var annotations: [ChartSurfaceAnnotation]
    @State private var selectedAnnotationId: UUID?
    @State private var editingAnnotation: ChartSurfaceAnnotation?
    @State private var showAddNoteSheet = false
    @State private var showGridFitSheet = false
    @State private var pendingNoteTitle = ""
    @State private var pendingNoteBody = ""
    @State private var placementKind: ChartSurfaceAnnotation.Kind?
    @State private var showAnnotations = true

    init(
        highlight: ChartHighlight,
        patternId: UUID,
        makeId: UUID?,
        onSave: @escaping (ChartHighlight) -> Void
    ) {
        self.patternId = patternId
        self.makeId = makeId
        self.onSave = onSave
        _workingHighlight = State(initialValue: highlight)
        _drawingData = State(initialValue: highlight.annotationDrawingData)
        _annotations = State(initialValue: highlight.annotations)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let chartImage = extractedChartImage {
                    VStack(spacing: Theme.Spacing.md) {
                        chartToolbar
                        ExtractedChartCanvasSurface(
                            image: chartImage,
                            highlight: fullFrameHighlight,
                            rowValue: rowValue,
                            columnValue: columnValue,
                            drawingData: $drawingData,
                            canvasController: canvasController,
                            annotations: $annotations,
                            selectedAnnotationId: $selectedAnnotationId,
                            placementKind: placementKind,
                            showAnnotations: showAnnotations,
                            onSelectAnnotation: handleSelectAnnotation,
                            onPlaceAnnotation: handlePlaceAnnotation
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Theme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
                    }
                    .padding(Theme.Spacing.md)
                    .background(Theme.warmCream)
                } else {
                    VStack(spacing: Theme.Spacing.md) {
                        Image(systemName: "photo.badge.exclamationmark")
                            .font(.system(size: 36))
                            .foregroundStyle(Theme.softCoral)
                        Text("No extracted chart found for this page.")
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.deepPlum)
                    }
                }
            }
            .navigationTitle("Chart Workspace")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        persistChanges()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        persistChanges()
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showAddNoteSheet) {
                NavigationStack {
                    Form {
                        Section("Note") {
                            TextField("Title", text: $pendingNoteTitle)
                            TextField("Details", text: $pendingNoteBody, axis: .vertical)
                                .lineLimit(3...6)
                        }
                    }
                    .navigationTitle("Add Note Marker")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                pendingNoteTitle = ""
                                pendingNoteBody = ""
                                showAddNoteSheet = false
                            }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Add") {
                                placementKind = .note
                                showAddNoteSheet = false
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $showGridFitSheet) {
                GridAlignmentEditor(highlight: $workingHighlight)
            }
            .sheet(item: $editingAnnotation) { annotation in
                AnnotationEditSheet(
                    annotation: annotation,
                    onSave: { updated in
                        if let idx = annotations.firstIndex(where: { $0.id == updated.id }) {
                            annotations[idx] = updated
                        }
                    },
                    onDelete: {
                        annotations.removeAll { $0.id == annotation.id }
                    }
                )
            }
        }
    }

    private var extractedChartImage: UIImage? {
        guard let data = workingHighlight.extractedChartPNGData else { return nil }
        return UIImage(data: data)
    }

    private var fullFrameHighlight: ChartHighlight {
        if let imageId = workingHighlight.imageId {
            return ChartHighlight(
                id: workingHighlight.id,
                patternId: workingHighlight.patternId,
                makeId: workingHighlight.makeId,
                imageId: imageId,
                minX: 0,
                minY: 0,
                maxX: 1,
                maxY: 1,
                rows: workingHighlight.rows,
                columns: workingHighlight.columns,
                chartType: workingHighlight.chartType,
                isSideways: workingHighlight.isSideways,
                isC2C: workingHighlight.isC2C,
                rowCounterLink: workingHighlight.rowCounterLink,
                columnCounterLink: workingHighlight.columnCounterLink,
                rowColorName: workingHighlight.rowColorName,
                columnColorName: workingHighlight.columnColorName,
                extractedChartPNGData: workingHighlight.extractedChartPNGData,
                annotationDrawingData: drawingData,
                currentRow: workingHighlight.currentRow,
                currentColumn: workingHighlight.currentColumn,
                annotations: annotations,
                gridInsetLeft: workingHighlight.gridInsetLeft,
                gridInsetTop: workingHighlight.gridInsetTop,
                gridInsetRight: workingHighlight.gridInsetRight,
                gridInsetBottom: workingHighlight.gridInsetBottom,
                isAIExtracted: workingHighlight.isAIExtracted
            )
        }

        return ChartHighlight(
            id: workingHighlight.id,
            patternId: workingHighlight.patternId,
            makeId: workingHighlight.makeId,
            pdfPageIndex: workingHighlight.pdfPageIndex ?? 0,
            minX: 0,
            minY: 0,
            maxX: 1,
            maxY: 1,
            rows: workingHighlight.rows,
            columns: workingHighlight.columns,
            chartType: workingHighlight.chartType,
            isSideways: workingHighlight.isSideways,
            isC2C: workingHighlight.isC2C,
            rowCounterLink: workingHighlight.rowCounterLink,
            columnCounterLink: workingHighlight.columnCounterLink,
            rowColorName: workingHighlight.rowColorName,
            columnColorName: workingHighlight.columnColorName,
            extractedChartPNGData: workingHighlight.extractedChartPNGData,
            annotationDrawingData: drawingData,
            currentRow: workingHighlight.currentRow,
            currentColumn: workingHighlight.currentColumn,
            annotations: annotations,
            gridInsetLeft: workingHighlight.gridInsetLeft,
            gridInsetTop: workingHighlight.gridInsetTop,
            gridInsetRight: workingHighlight.gridInsetRight,
            gridInsetBottom: workingHighlight.gridInsetBottom,
            isAIExtracted: workingHighlight.isAIExtracted
        )
    }

    private var rowValue: Int {
        min(max(workingHighlight.currentRow, 1), max(1, workingHighlight.rows))
    }

    private var columnValue: Int {
        min(max(workingHighlight.currentColumn, 1), max(1, workingHighlight.columns))
    }

    @ViewBuilder
    private var chartToolbar: some View {
        VStack(spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.md) {
                rowColumnControl(
                    title: "Row",
                    current: rowValue,
                    total: max(1, workingHighlight.rows),
                    decrement: { workingHighlight.currentRow = max(1, rowValue - 1) },
                    increment: { workingHighlight.currentRow = min(max(1, workingHighlight.rows), rowValue + 1) }
                )
                rowColumnControl(
                    title: "Col",
                    current: columnValue,
                    total: max(1, workingHighlight.columns),
                    decrement: { workingHighlight.currentColumn = max(1, columnValue - 1) },
                    increment: { workingHighlight.currentColumn = min(max(1, workingHighlight.columns), columnValue + 1) }
                )
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.sm) {
                    Button {
                        canvasController.undo()
                    } label: {
                        Label("Undo", systemImage: "arrow.uturn.backward")
                            .font(Theme.Typography.caption)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!canvasController.canUndo)

                    Button {
                        canvasController.redo()
                    } label: {
                        Label("Redo", systemImage: "arrow.uturn.forward")
                            .font(Theme.Typography.caption)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!canvasController.canRedo)

                    Button("Clear Ink") {
                        drawingData = nil
                        canvasController.clear()
                    }
                    .buttonStyle(.bordered)

                    Button {
                        placeAnnotationImmediately(kind: .pin)
                    } label: {
                        Label("Pin", systemImage: "mappin.circle.fill")
                            .font(Theme.Typography.caption)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        showAddNoteSheet = true
                    } label: {
                        Label("Note", systemImage: "note.text.badge.plus")
                            .font(Theme.Typography.caption)
                    }
                    .buttonStyle(.bordered)

                    Menu {
                        Button("Increase", systemImage: "plus.circle.fill") {
                            placeAnnotationImmediately(kind: .increase)
                        }
                        Button("Decrease", systemImage: "minus.circle.fill") {
                            placeAnnotationImmediately(kind: .decrease)
                        }
                        Button("Repeat", systemImage: "arrow.clockwise.circle.fill") {
                            placeAnnotationImmediately(kind: .repeatSection)
                        }
                        Button("Caution", systemImage: "exclamationmark.triangle.fill") {
                            placeAnnotationImmediately(kind: .caution)
                        }
                    } label: {
                        Label("Marker", systemImage: "tag.circle")
                            .font(Theme.Typography.caption)
                    }
                    .buttonStyle(.bordered)

                    Button("Align Grid") {
                        showGridFitSheet = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.softCoral)

                    Button {
                        showAnnotations.toggle()
                    } label: {
                        Label(showAnnotations ? "Hide markers" : "Show markers", systemImage: showAnnotations ? "eye.slash" : "eye")
                            .font(Theme.Typography.caption)
                    }
                    .buttonStyle(.bordered)
                }
            }

            HStack(spacing: Theme.Spacing.md) {
                gridAdjustControl(
                    title: "Grid rows",
                    value: max(1, workingHighlight.rows),
                    decrement: {
                        workingHighlight.rows = max(1, workingHighlight.rows - 1)
                        workingHighlight.currentRow = min(max(1, workingHighlight.currentRow), workingHighlight.rows)
                    },
                    increment: {
                        workingHighlight.rows = min(999, workingHighlight.rows + 1)
                    }
                )
                gridAdjustControl(
                    title: "Grid cols",
                    value: max(1, workingHighlight.columns),
                    decrement: {
                        workingHighlight.columns = max(1, workingHighlight.columns - 1)
                        workingHighlight.currentColumn = min(max(1, workingHighlight.currentColumn), workingHighlight.columns)
                    },
                    increment: {
                        workingHighlight.columns = min(999, workingHighlight.columns + 1)
                    }
                )
            }

            HStack {
                Text("\(annotations.count) markers")
                    .font(Theme.Typography.caption2)
                    .foregroundStyle(Theme.deepPlum.opacity(0.6))
                Spacer()
                if !showAnnotations {
                    Text("Hidden")
                        .font(Theme.Typography.caption2)
                        .foregroundStyle(Theme.deepPlum.opacity(0.45))
                }
                if placementKind == .note {
                    Text("Tap chart to place note")
                        .font(Theme.Typography.caption2)
                        .foregroundStyle(Theme.softCoral)
                }
            }
        }
    }

    @ViewBuilder
    private func rowColumnControl(
        title: String,
        current: Int,
        total: Int,
        decrement: @escaping () -> Void,
        increment: @escaping () -> Void
    ) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            Button(action: decrement) {
                Image(systemName: title == "Row" ? "minus.circle.fill" : "arrow.left.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.deepPlum)
            }
            .buttonStyle(.plain)

            Text("\(title) \(current)/\(total)")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.deepPlum)
                .frame(minWidth: 90, alignment: .center)

            Button(action: increment) {
                Image(systemName: title == "Row" ? "plus.circle.fill" : "arrow.right.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.deepPlum)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xs)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.small))
    }

    @ViewBuilder
    private func gridAdjustControl(
        title: String,
        value: Int,
        decrement: @escaping () -> Void,
        increment: @escaping () -> Void
    ) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            Text("\(title): \(value)")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.deepPlum.opacity(0.85))
            Spacer(minLength: 4)
            Button(action: decrement) {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.deepPlum)
            }
            .buttonStyle(.plain)
            Button(action: increment) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.deepPlum)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xs)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.small))
    }

    private func persistChanges() {
        workingHighlight.annotationDrawingData = drawingData
        workingHighlight.currentRow = rowValue
        workingHighlight.currentColumn = columnValue
        workingHighlight.annotations = annotations
        onSave(workingHighlight)
    }

    private func handlePlaceAnnotation(normalizedX _: Double, normalizedY _: Double) {
        guard let kind = placementKind else { return }
        let snapped = currentRowColumnIntersection()
        let newAnnotation = buildAnnotation(kind: kind, position: snapped)
        annotations.append(newAnnotation)
        selectedAnnotationId = newAnnotation.id
        placementKind = nil
        if kind == .note {
            editingAnnotation = newAnnotation
        }
        pendingNoteTitle = ""
        pendingNoteBody = ""
    }

    private func placeAnnotationImmediately(kind: ChartSurfaceAnnotation.Kind) {
        let snapped = currentRowColumnIntersection()
        let newAnnotation = buildAnnotation(kind: kind, position: snapped)
        annotations.append(newAnnotation)
        selectedAnnotationId = newAnnotation.id
    }

    private func buildAnnotation(kind: ChartSurfaceAnnotation.Kind, position: (x: Double, y: Double)) -> ChartSurfaceAnnotation {
        ChartSurfaceAnnotation(
            kind: kind,
            normalizedX: position.x,
            normalizedY: position.y,
            title: defaultTitle(for: kind),
            note: kind == .note ? (pendingNoteBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : pendingNoteBody) : nil
        )
    }

    private func handleSelectAnnotation(_ annotation: ChartSurfaceAnnotation) {
        if selectedAnnotationId == annotation.id {
            editingAnnotation = annotation
        } else {
            selectedAnnotationId = annotation.id
        }
    }

    private func defaultTitle(for kind: ChartSurfaceAnnotation.Kind) -> String? {
        switch kind {
        case .note:
            let cleaned = pendingNoteTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? "Note" : cleaned
        case .pin: return "Pin"
        case .increase: return "Increase"
        case .decrease: return "Decrease"
        case .repeatSection: return "Repeat"
        case .caution: return "Caution"
        }
    }

    private func currentRowColumnIntersection() -> (x: Double, y: Double) {
        let left = workingHighlight.gridInsetLeft
        let top = workingHighlight.gridInsetTop
        let right = workingHighlight.gridInsetRight
        let bottom = workingHighlight.gridInsetBottom
        let gridWidth = max(0.001, 1 - left - right)
        let gridHeight = max(0.001, 1 - top - bottom)
        let cols = max(1, workingHighlight.columns)
        let rows = max(1, workingHighlight.rows)
        let colIndex = min(cols, max(1, columnValue))
        let rowIndex = min(rows, max(1, rowValue))
        let x = left + ((Double(colIndex) - 0.5) / Double(cols)) * gridWidth
        let y = top + ((Double(rowIndex) - 0.5) / Double(rows)) * gridHeight
        return (x, y)
    }
}

private struct ExtractedChartCanvasSurface: View {
    let image: UIImage
    let highlight: ChartHighlight
    let rowValue: Int
    let columnValue: Int
    @Binding var drawingData: Data?
    @ObservedObject var canvasController: PencilCanvasController
    @Binding var annotations: [ChartSurfaceAnnotation]
    @Binding var selectedAnnotationId: UUID?
    let placementKind: ChartSurfaceAnnotation.Kind?
    let showAnnotations: Bool
    let onSelectAnnotation: (ChartSurfaceAnnotation) -> Void
    let onPlaceAnnotation: (Double, Double) -> Void

    private var showEdgeLabels: Bool { !highlight.isAIExtracted }

    var body: some View {
        GeometryReader { geo in
            let rightGutter: CGFloat = showEdgeLabels ? 28 : 0
            let bottomGutter: CGFloat = showEdgeLabels ? 20 : 0
            let contentSize = CGSize(
                width: max(1, geo.size.width - rightGutter),
                height: max(1, geo.size.height - bottomGutter)
            )
            let frame = aspectFitRect(contentSize: image.size, in: contentSize)
            let centeredY = frame.height / 2 + max(0, (contentSize.height - frame.height) * 0.05)
            ZStack {
                Color.clear

                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: centeredY)

                ChartHighlighterOverlayView(
                    highlight: highlight,
                    rowValue: rowValue,
                    columnValue: columnValue
                )
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: centeredY)

                PencilDrawingCanvas(drawingData: $drawingData, controller: canvasController)
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: centeredY)

                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: centeredY)
                    .gesture(
                        SpatialTapGesture()
                            .onEnded { value in
                                guard placementKind != nil else { return }
                                let nx = Double(value.location.x / max(1, frame.width))
                                let ny = Double(value.location.y / max(1, frame.height))
                                onPlaceAnnotation(nx, ny)
                            }
                    )

                ChartAnnotationOverlay(
                    annotations: $annotations,
                    selectedAnnotationId: $selectedAnnotationId,
                    onSelectAnnotation: onSelectAnnotation,
                    placementKind: placementKind,
                    isVisible: showAnnotations
                )
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: centeredY)

                if showEdgeLabels {
                    ChartEdgeLabelsOverlay(
                        highlight: highlight,
                        rowValue: rowValue,
                        columnValue: columnValue
                    )
                    .frame(width: frame.width + rightGutter, height: frame.height + bottomGutter)
                    .position(x: frame.midX + rightGutter / 2, y: centeredY + bottomGutter / 2)
                }
            }
        }
    }
}

private struct ChartAnnotationOverlay: View {
    @Binding var annotations: [ChartSurfaceAnnotation]
    @Binding var selectedAnnotationId: UUID?
    let onSelectAnnotation: (ChartSurfaceAnnotation) -> Void
    let placementKind: ChartSurfaceAnnotation.Kind?
    let isVisible: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(isVisible ? annotations : []) { annotation in
                    annotationView(annotation)
                        .position(
                            x: CGFloat(annotation.normalizedX) * geo.size.width,
                            y: CGFloat(annotation.normalizedY) * geo.size.height
                        )
                        .onTapGesture {
                            guard placementKind == nil else { return }
                            selectedAnnotationId = annotation.id
                            onSelectAnnotation(annotation)
                        }
                }
            }
        }
    }

    @ViewBuilder
    private func annotationView(_ annotation: ChartSurfaceAnnotation) -> some View {
        let isSelected = annotation.id == selectedAnnotationId
        VStack(spacing: 4) {
            Image(systemName: annotation.kind.symbolName)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(color(for: annotation.kind))
                .padding(5)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
                .overlay(Circle().stroke(Theme.Semantic.borderStrong, lineWidth: 1))
                .overlay(
                    Circle()
                        .stroke(isSelected ? Theme.softCoral : Color.clear, lineWidth: 2)
                )

            if isSelected, let title = annotation.title ?? annotation.note {
                VStack(spacing: 2) {
                    Text(title)
                        .font(Theme.Typography.caption2.weight(.semibold))
                        .foregroundStyle(Theme.deepPlum)
                        .lineLimit(1)
                    if let note = annotation.note, !note.isEmpty, note != title {
                        Text(note)
                            .font(Theme.Typography.caption2)
                            .foregroundStyle(Theme.deepPlum.opacity(0.8))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .frame(maxWidth: 130)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func color(for kind: ChartSurfaceAnnotation.Kind) -> Color {
        switch kind {
        case .pin: return Theme.dustyBlue
        case .note: return Theme.sageGreen
        case .increase: return Theme.sageGreen
        case .decrease: return Theme.softCoral
        case .repeatSection: return Theme.honey
        case .caution: return Theme.softCoral
        }
    }
}

private struct ChartEdgeLabelsOverlay: View {
    let highlight: ChartHighlight
    let rowValue: Int
    let columnValue: Int

    var body: some View {
        GeometryReader { geo in
            let chartWidth = max(1, geo.size.width - 28)
            let chartHeight = max(1, geo.size.height - 20)
            let rect = CGRect(x: 0, y: 0, width: chartWidth, height: chartHeight)
            let gridRect = CGRect(
                x: rect.minX + rect.width * highlight.gridInsetLeft,
                y: rect.minY + rect.height * highlight.gridInsetTop,
                width: rect.width * max(0.001, 1 - highlight.gridInsetLeft - highlight.gridInsetRight),
                height: rect.height * max(0.001, 1 - highlight.gridInsetTop - highlight.gridInsetBottom)
            )
            let rows = max(1, highlight.rows)
            let cols = max(1, highlight.columns)
            let rowHeight = gridRect.height / CGFloat(rows)
            let colWidth = gridRect.width / CGFloat(cols)
            let activeRow = min(max(rowValue, 1), rows)
            let activeCol = min(max(columnValue, 1), cols)

            ZStack(alignment: .topLeading) {
                ForEach(sampledLabels(total: rows, cellSize: rowHeight, minSpacing: 13), id: \.self) { row in
                    Text("\(row)")
                        .font(Theme.Typography.caption2)
                        .foregroundStyle(Theme.deepPlum.opacity(0.62))
                        .frame(width: 24, alignment: .leading)
                        .position(
                            x: gridRect.maxX + 14,
                            y: gridRect.minY + rowHeight * (CGFloat(row) - 0.5)
                        )
                }

                ForEach(sampledLabels(total: cols, cellSize: colWidth, minSpacing: 16), id: \.self) { col in
                    Text("\(col)")
                        .font(Theme.Typography.caption2)
                        .foregroundStyle(Theme.deepPlum.opacity(0.62))
                        .frame(width: 16, alignment: .center)
                        .position(
                            x: gridRect.minX + colWidth * (CGFloat(col) - 0.5),
                            y: gridRect.maxY + 10
                        )
                }

                Text("\(activeRow)")
                    .font(Theme.Typography.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Theme.deepPlum.opacity(0.85))
                    .clipShape(Capsule())
                    .position(
                        x: gridRect.maxX + 14,
                        y: gridRect.minY + rowHeight * (CGFloat(activeRow) - 0.5)
                    )

                Text("\(activeCol)")
                    .font(Theme.Typography.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Theme.deepPlum.opacity(0.85))
                    .clipShape(Capsule())
                    .position(
                        x: gridRect.minX + colWidth * (CGFloat(activeCol) - 0.5),
                        y: gridRect.maxY + 10
                    )
            }
        }
        .allowsHitTesting(false)
    }

    private func sampledLabels(total: Int, cellSize: CGFloat, minSpacing: CGFloat) -> [Int] {
        guard total > 0 else { return [] }
        let spacingDrivenStep = max(1, Int(ceil(minSpacing / max(1, cellSize))))
        let densityStep = max(1, total / 60)
        let step = max(spacingDrivenStep, densityStep)
        var values = Set(stride(from: 1, through: total, by: step).map { $0 })
        values.insert(total)
        return values.sorted()
    }
}

private struct AnnotationEditSheet: View {
    let annotation: ChartSurfaceAnnotation
    let onSave: (ChartSurfaceAnnotation) -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var note: String

    init(
        annotation: ChartSurfaceAnnotation,
        onSave: @escaping (ChartSurfaceAnnotation) -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.annotation = annotation
        self.onSave = onSave
        self.onDelete = onDelete
        _title = State(initialValue: annotation.title ?? "")
        _note = State(initialValue: annotation.note ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Marker") {
                    Label(annotation.kind.rawValue.capitalized, systemImage: annotation.kind.symbolName)
                }
                Section("Details") {
                    TextField("Title", text: $title)
                    TextField("Note", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                }
                Section {
                    Button("Delete marker", role: .destructive) {
                        onDelete()
                        dismiss()
                    }
                }
            }
            .navigationTitle("Edit Marker")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var updated = annotation
                        updated.title = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : title
                        updated.note = note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note
                        onSave(updated)
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct GridFitSheet: View {
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
            .navigationTitle("Grid Fit")
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
            set: { newValue in
                highlight.rows = max(1, newValue)
                highlight.currentRow = min(max(1, highlight.currentRow), highlight.rows)
            }
        )
    }

    private var columnsBinding: Binding<Int> {
        Binding(
            get: { max(1, highlight.columns) },
            set: { newValue in
                highlight.columns = max(1, newValue)
                highlight.currentColumn = min(max(1, highlight.currentColumn), highlight.columns)
            }
        )
    }

    private var gridInsetLeftBinding: Binding<Double> {
        Binding(
            get: { highlight.gridInsetLeft },
            set: { highlight.gridInsetLeft = clampInset($0, opposite: highlight.gridInsetRight) }
        )
    }

    private var gridInsetTopBinding: Binding<Double> {
        Binding(
            get: { highlight.gridInsetTop },
            set: { highlight.gridInsetTop = clampInset($0, opposite: highlight.gridInsetBottom) }
        )
    }

    private var gridInsetRightBinding: Binding<Double> {
        Binding(
            get: { highlight.gridInsetRight },
            set: { highlight.gridInsetRight = clampInset($0, opposite: highlight.gridInsetLeft) }
        )
    }

    private var gridInsetBottomBinding: Binding<Double> {
        Binding(
            get: { highlight.gridInsetBottom },
            set: { highlight.gridInsetBottom = clampInset($0, opposite: highlight.gridInsetTop) }
        )
    }

    private func clampInset(_ value: Double, opposite: Double) -> Double {
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
            Slider(value: value, in: 0...0.45, step: 0.005)
        }
    }
}

private struct PencilDrawingCanvas: UIViewRepresentable {
    @Binding var drawingData: Data?
    let controller: PencilCanvasController

    func makeCoordinator() -> Coordinator {
        Coordinator(drawingData: $drawingData, controller: controller)
    }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.drawingPolicy = .anyInput
        canvas.delegate = context.coordinator
        canvas.tool = PKInkingTool(.pen, color: UIColor(Theme.deepPlum), width: 4)
        controller.attach(canvas: canvas)
        if let drawingData, let drawing = try? PKDrawing(data: drawingData) {
            canvas.drawing = drawing
        }
        return canvas
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        controller.attach(canvas: uiView)
        if let drawingData,
           let drawing = try? PKDrawing(data: drawingData),
           uiView.drawing.dataRepresentation() != drawingData {
            uiView.drawing = drawing
        } else if drawingData == nil, !uiView.drawing.bounds.isEmpty {
            uiView.drawing = PKDrawing()
        }
        controller.refreshUndoState()
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        @Binding var drawingData: Data?
        private let controller: PencilCanvasController

        init(drawingData: Binding<Data?>, controller: PencilCanvasController) {
            _drawingData = drawingData
            self.controller = controller
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            let data = canvasView.drawing.dataRepresentation()
            drawingData = data.isEmpty ? nil : data
            controller.refreshUndoState()
        }
    }
}

final class PencilCanvasController: ObservableObject {
    fileprivate weak var canvas: PKCanvasView?
    @Published var canUndo = false
    @Published var canRedo = false

    func attach(canvas: PKCanvasView) {
        self.canvas = canvas
        refreshUndoState()
    }

    func undo() {
        canvas?.undoManager?.undo()
        refreshUndoState()
    }

    func redo() {
        canvas?.undoManager?.redo()
        refreshUndoState()
    }

    func clear() {
        guard let canvas else { return }
        let previousDrawing = canvas.drawing
        canvas.undoManager?.registerUndo(withTarget: canvas) { target in
            target.drawing = previousDrawing
        }
        canvas.undoManager?.setActionName("Clear Ink")
        canvas.drawing = PKDrawing()
        refreshUndoState()
    }

    func refreshUndoState() {
        canUndo = canvas?.undoManager?.canUndo ?? false
        canRedo = canvas?.undoManager?.canRedo ?? false
    }
}

private func aspectFitRect(contentSize: CGSize, in containerSize: CGSize) -> CGRect {
    guard contentSize.width > 0, contentSize.height > 0,
          containerSize.width > 0, containerSize.height > 0 else {
        return CGRect(origin: .zero, size: containerSize)
    }
    let scale = min(containerSize.width / contentSize.width, containerSize.height / contentSize.height)
    let width = contentSize.width * scale
    let height = contentSize.height * scale
    let origin = CGPoint(
        x: (containerSize.width - width) / 2,
        y: (containerSize.height - height) / 2
    )
    return CGRect(origin: origin, size: CGSize(width: width, height: height))
}
