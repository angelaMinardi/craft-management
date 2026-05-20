//
//  PDFViewerView.swift
//  PatternVault
//
//  PDFKit-backed viewer with PencilKit annotation, reading bar, and row counter.
//

import PDFKit
import PencilKit
import SwiftUI

struct PDFViewerView: View {
    let url: URL
    let patternId: UUID
    let makeId: UUID?

    @State private var document: PDFDocument?
    @State private var errorMessage: String?
    @AppStorage private var currentPageIndex: Int

    // Reading bar
    @AppStorage private var readingBarFraction: Double
    @AppStorage private var scrollDestinationY: Double
    @State private var isDraggingBar = false
    @State private var dragStartFraction: Double = 0

    // Annotation
    @State private var isAnnotating = false
    @State private var drawingData: Data?
    @StateObject private var canvasController = PencilCanvasController()

    // Counter + Timer
    @AppStorage private var counterValue: Int
    @AppStorage private var counterTotalRows: Int
    @State private var timerSeconds: Int = 0
    @State private var timerRunning = false
    @State private var timerTask: Task<Void, Never>?
    @State private var showCounterSettings = false

    init(url: URL, patternId: UUID, makeId: UUID?) {
        self.url = url
        self.patternId = patternId
        self.makeId = makeId
        self._readingBarFraction = AppStorage(
            wrappedValue: 0.3,
            "pdfReadingBarFraction_\(patternId.uuidString)"
        )
        self._currentPageIndex = AppStorage(
            wrappedValue: 0,
            "pdfCurrentPage_\(patternId.uuidString)"
        )
        self._scrollDestinationY = AppStorage(
            wrappedValue: 0,
            "pdfScrollDestY_\(patternId.uuidString)"
        )
        self._counterValue = AppStorage(
            wrappedValue: 0,
            "pdfCounter_\(patternId.uuidString)"
        )
        self._counterTotalRows = AppStorage(
            wrappedValue: 0,
            "pdfCounterTotal_\(patternId.uuidString)"
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if let document {
                    PDFAnnotationViewRepresentable(
                        document: document,
                        currentPageIndex: $currentPageIndex,
                        scrollOffsetY: $scrollDestinationY,
                        restoreScrollOffsetY: scrollDestinationY,
                        drawingData: $drawingData,
                        isAnnotating: isAnnotating,
                        canvasController: canvasController
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
                            Spacer()
                            // Annotation toggle button
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isAnnotating.toggle()
                                }
                            } label: {
                                Image(systemName: isAnnotating ? "pencil.tip.crop.circle.fill" : "pencil.tip.crop.circle")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(10)
                                    .background(isAnnotating ? Theme.honey : Theme.dustyBlue)
                                    .clipShape(Circle())
                            }
                            .padding(.trailing, Theme.Spacing.md)
                            .padding(.top, Theme.Spacing.md)
                        }

                        // Floating annotation toolbar
                        if isAnnotating {
                            annotationToolbar
                                .transition(.move(edge: .top).combined(with: .opacity))
                                .padding(.top, Theme.Spacing.xs)
                        }

                        Spacer()

                        Text("Page \(currentPageIndex + 1)")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.deepPlum.opacity(0.75))
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.vertical, Theme.Spacing.xs)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                            .padding(.bottom, Theme.Spacing.sm)
                    }
                }
            }
            .overlay {
                if document != nil {
                    GeometryReader { geo in
                        pdfReadingBar(in: geo)
                    }
                }
            }

            // Counter + timer bar at bottom
            if document != nil {
                pdfCounterTimerBar
            }
        }
        .task {
            if document == nil && errorMessage == nil {
                drawingData = PDFAnnotationStore.shared.load(patternId: patternId)
                await loadDocument()
            }
        }
        .onDisappear {
            PDFAnnotationStore.shared.saveImmediately(data: drawingData, patternId: patternId)
            timerTask?.cancel()
        }
    }

    // MARK: - Annotation Toolbar

    private var annotationToolbar: some View {
        HStack(spacing: Theme.Spacing.md) {
            toolButton(icon: "pencil.tip", tool: PKInkingTool(.pen, color: UIColor(Theme.deepPlum), width: 4), label: "Pen")
            toolButton(icon: "highlighter", tool: PKInkingTool(.marker, color: UIColor(Theme.honey.opacity(0.5)), width: 20), label: "Highlighter")
            toolButton(icon: "eraser", tool: PKEraserTool(.bitmap), label: "Eraser")

            Divider()
                .frame(height: 28)

            Button {
                canvasController.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(canvasController.canUndo ? Theme.deepPlum : Theme.deepPlum.opacity(0.3))
                    .frame(width: 40, height: 40)
            }
            .disabled(!canvasController.canUndo)
            .buttonStyle(.plain)

            Button {
                canvasController.redo()
            } label: {
                Image(systemName: "arrow.uturn.forward")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(canvasController.canRedo ? Theme.deepPlum : Theme.deepPlum.opacity(0.3))
                    .frame(width: 40, height: 40)
            }
            .disabled(!canvasController.canRedo)
            .buttonStyle(.plain)

            Divider()
                .frame(height: 28)

            Button(role: .destructive) {
                drawingData = nil
                canvasController.clear()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.softCoral)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.sm)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
        .padding(.horizontal, Theme.Spacing.md)
    }

    @ViewBuilder
    private func toolButton(icon: String, tool: PKTool, label: String) -> some View {
        Button {
            canvasController.setTool(tool)
        } label: {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.deepPlum)
                .frame(width: 40, height: 40)
                .background(Theme.warmCream.opacity(0.6))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: - Reading Bar

    @ViewBuilder
    private func pdfReadingBar(in geo: GeometryProxy) -> some View {
        let barY = geo.size.height * readingBarFraction
        ZStack {
            Rectangle()
                .fill(Theme.honey.opacity(isDraggingBar ? 0.45 : 0.28))
                .frame(height: 28)
                .frame(maxWidth: .infinity)
            HStack {
                Spacer()
                Capsule()
                    .fill(Theme.honey.opacity(0.8))
                    .frame(width: 36, height: 5)
                    .padding(.trailing, Theme.Spacing.lg)
            }
        }
        .position(x: geo.size.width / 2, y: barY)
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    if !isDraggingBar {
                        isDraggingBar = true
                        dragStartFraction = readingBarFraction
                    }
                    let startY = dragStartFraction * geo.size.height
                    let newY = min(geo.size.height - 20, max(20, startY + value.translation.height))
                    readingBarFraction = Double(newY / geo.size.height)
                }
                .onEnded { _ in isDraggingBar = false }
        )
        .accessibilityLabel("Reading bar")
        .accessibilityHint("Drag to mark your place in the PDF")
    }

    // MARK: - Counter + Timer Bar

    private var pdfCounterTimerBar: some View {
        HStack(spacing: 0) {
            // Minus button (smaller, for mistakes)
            Button {
                counterValue = max(0, counterValue - 1)
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.deepPlum.opacity(0.5))
                    .frame(width: 44, height: 80)
            }
            .buttonStyle(.plain)

            // Counter — tap to increment
            Button {
                counterValue += 1
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                VStack(spacing: 1) {
                    Text("Counter")
                        .font(Theme.Typography.caption2)
                        .foregroundStyle(Theme.deepPlum.opacity(0.5))
                    if counterTotalRows > 0 {
                        Text("\(counterValue)")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.deepPlum)
                        +
                        Text(" / \(counterTotalRows)")
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.deepPlum.opacity(0.45))
                    } else {
                        Text("\(counterValue)")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.deepPlum)
                    }
                }
                .contentTransition(.numericText())
                .animation(.spring(response: 0.2, dampingFraction: 0.7), value: counterValue)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.sm)
                .background(Theme.sageGreen.opacity(0.12))
            }
            .buttonStyle(.plain)

            // Settings gear
            Button {
                showCounterSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.deepPlum.opacity(0.45))
                    .frame(width: 36, height: 80)
            }
            .buttonStyle(.plain)

            Divider()
                .frame(height: 50)

            // Timer — tap to start/pause
            Button {
                timerRunning.toggle()
                if timerRunning {
                    startTimer()
                } else {
                    timerTask?.cancel()
                    timerTask = nil
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                VStack(spacing: 1) {
                    HStack(spacing: 4) {
                        Text("Timer")
                            .font(Theme.Typography.caption2)
                            .foregroundStyle(Theme.deepPlum.opacity(0.5))
                        Image(systemName: timerRunning ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(timerRunning ? Theme.softCoral : Theme.sageGreen)
                    }
                    Text(timerFormatted)
                        .font(.system(size: 24, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.deepPlum)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.sm)
                .background(timerRunning ? Theme.sageGreen.opacity(0.08) : Theme.warmCream.opacity(0.4))
                .animation(.easeInOut(duration: 0.2), value: timerRunning)
            }
            .buttonStyle(.plain)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                .stroke(Theme.deepPlum.opacity(0.08), lineWidth: 1)
        )
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.bottom, Theme.Spacing.xs)
        .sheet(isPresented: $showCounterSettings) {
            counterSettingsSheet
        }
    }

    // MARK: - Counter Settings Sheet

    private var counterSettingsSheet: some View {
        NavigationStack {
            Form {
                Section("Counter") {
                    HStack {
                        Text("Current count")
                        Spacer()
                        Text("\(counterValue)")
                            .foregroundStyle(Theme.deepPlum)
                            .font(Theme.Typography.cardTitle)
                    }
                    Stepper("Number of rows: \(counterTotalRows > 0 ? "\(counterTotalRows)" : "Not set")",
                            value: Binding(
                                get: { counterTotalRows },
                                set: { counterTotalRows = max(0, $0) }
                            ),
                            in: 0...9999)
                    .font(Theme.Typography.body)
                }

                Section {
                    Button {
                        counterValue = max(0, counterValue - 1)
                    } label: {
                        Label("Undo last count (−1)", systemImage: "minus.circle")
                    }
                    Button(role: .destructive) {
                        counterValue = 0
                    } label: {
                        Label("Reset counter to 0", systemImage: "arrow.counterclockwise")
                    }
                }

                Section("Timer") {
                    HStack {
                        Text("Elapsed")
                        Spacer()
                        Text(timerFormatted)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(Theme.deepPlum)
                    }
                    Button(role: .destructive) {
                        timerRunning = false
                        timerTask?.cancel()
                        timerTask = nil
                        timerSeconds = 0
                    } label: {
                        Label("Reset timer", systemImage: "arrow.counterclockwise")
                    }
                }
            }
            .navigationTitle("Counter Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showCounterSettings = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var timerFormatted: String {
        let h = timerSeconds / 3600
        let m = (timerSeconds % 3600) / 60
        let s = timerSeconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }

    private func startTimer() {
        timerTask?.cancel()
        timerTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { break }
                timerSeconds += 1
            }
        }
    }

    // MARK: - Document Loading

    private func loadDocument() async {
        if let cachedData = PDFCacheService.cachedPDF(for: patternId, sourceURL: url),
           let cachedDoc = PDFDocument(data: cachedData) {
            self.document = cachedDoc
            return
        }
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
            PDFCacheService.cachePDF(data: data, patternId: patternId, sourceURL: url)
            self.document = document
        } catch {
            errorMessage = "Could not load PDF. Check your connection and try again."
        }
    }
}

// MARK: - PencilKit Canvas Controller

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
        canvas.undoManager?.registerUndo(withTarget: canvas) { target in
            let old = target.drawing
            target.drawing = PKDrawing()
            target.undoManager?.registerUndo(withTarget: target) { t in
                t.drawing = old
            }
        }
        canvas.drawing = PKDrawing()
        refreshUndoState()
    }

    func setTool(_ tool: PKTool) {
        canvas?.tool = tool
    }

    func refreshUndoState() {
        canUndo = canvas?.undoManager?.canUndo ?? false
        canRedo = canvas?.undoManager?.canRedo ?? false
    }
}

// MARK: - PDF + Annotation UIViewRepresentable

private struct PDFAnnotationViewRepresentable: UIViewRepresentable {
    let document: PDFDocument
    @Binding var currentPageIndex: Int
    @Binding var scrollOffsetY: Double
    let restoreScrollOffsetY: Double
    @Binding var drawingData: Data?
    let isAnnotating: Bool
    let canvasController: PencilCanvasController

    func makeUIView(context: Context) -> PDFAnnotationContainerView {
        let view = PDFAnnotationContainerView()
        view.pdfView.document = document
        view.pdfView.displayMode = .singlePageContinuous
        view.pdfView.displayDirection = .vertical
        view.pdfView.displaysPageBreaks = true
        view.pdfView.pageBreakMargins = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)

        // Load initial drawing
        if let data = drawingData, let drawing = try? PKDrawing(data: data) {
            view.canvasView.drawing = drawing
        }
        view.canvasView.isUserInteractionEnabled = isAnnotating
        canvasController.attach(canvas: view.canvasView)

        context.coordinator.attach(to: view, document: document, restoreOffsetY: restoreScrollOffsetY)
        return view
    }

    func updateUIView(_ uiView: PDFAnnotationContainerView, context: Context) {
        if uiView.pdfView.document !== document {
            uiView.pdfView.document = document
            context.coordinator.attach(to: uiView, document: document)
        }
        context.coordinator.parent = self
        uiView.canvasView.isUserInteractionEnabled = isAnnotating
    }

    static func dismantleUIView(_ uiView: PDFAnnotationContainerView, coordinator: Coordinator) {
        coordinator.saveCurrentPosition()
        coordinator.saveDrawing()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UIScrollViewDelegate, PKCanvasViewDelegate {
        var parent: PDFAnnotationViewRepresentable
        private weak var pdfView: PDFView?
        private weak var scrollView: UIScrollView?
        private weak var canvasView: PKCanvasView?
        private weak var document: PDFDocument?
        private var observer: NSObjectProtocol?

        init(parent: PDFAnnotationViewRepresentable) {
            self.parent = parent
        }

        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }

        func attach(to container: PDFAnnotationContainerView, document: PDFDocument, restoreOffsetY: Double = 0) {
            let pdfView = container.pdfView
            self.pdfView = pdfView
            self.canvasView = container.canvasView
            self.document = document

            if let observer { NotificationCenter.default.removeObserver(observer) }

            // Page change observer
            observer = NotificationCenter.default.addObserver(
                forName: Notification.Name.PDFViewPageChanged,
                object: pdfView,
                queue: .main
            ) { [weak self] _ in
                self?.updatePageIndex()
            }

            // Find internal scroll view for scroll position save/restore
            if let sv = pdfView.subviews.compactMap({ $0 as? UIScrollView }).first {
                self.scrollView = sv
                sv.delegate = self
            }

            // Canvas delegate for drawing changes
            container.canvasView.delegate = self

            // Restore scroll position after layout
            container.onFirstLayout = { [weak self] in
                guard let self, restoreOffsetY > 0, let sv = self.scrollView else { return }
                let clamped = min(restoreOffsetY, Double(sv.contentSize.height - sv.bounds.height))
                if clamped > 0 {
                    sv.contentOffset.y = CGFloat(clamped)
                }
            }
        }

        private func updatePageIndex() {
            guard let pdfView, let document, let page = pdfView.currentPage else { return }
            parent.currentPageIndex = max(0, document.index(for: page))
        }

        func saveCurrentPosition() {
            guard let pdfView, let document else { return }
            if let page = pdfView.currentPage {
                parent.currentPageIndex = max(0, document.index(for: page))
            }
            if let sv = scrollView {
                parent.scrollOffsetY = Double(sv.contentOffset.y)
            }
        }

        func saveDrawing() {
            guard let canvasView else { return }
            let data = canvasView.drawing.dataRepresentation()
            parent.drawingData = data.isEmpty ? nil : data
        }

        // MARK: - UIScrollViewDelegate

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if !decelerate { saveCurrentPosition() }
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            saveCurrentPosition()
        }

        // MARK: - PKCanvasViewDelegate

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            let data = canvasView.drawing.dataRepresentation()
            parent.drawingData = data.isEmpty ? nil : data
            parent.canvasController.refreshUndoState()
        }
    }
}

// MARK: - PDF Container with Canvas Overlay

private final class PDFAnnotationContainerView: UIView {
    let pdfView = PDFView()
    let canvasView = PKCanvasView()
    private var didInitialScale = false
    private var didInstallCanvas = false
    private var contentSizeObservation: NSKeyValueObservation?
    var onFirstLayout: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(pdfView)

        // Configure canvas — will be added to PDF's document view in layoutSubviews
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        canvasView.drawingPolicy = .anyInput
        canvasView.tool = PKInkingTool(.pen, color: UIColor(Theme.deepPlum), width: 4)
        canvasView.isUserInteractionEnabled = false
        // Disable canvas's own scrolling so it doesn't fight with the PDF scroll view
        canvasView.isScrollEnabled = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        contentSizeObservation?.invalidate()
    }

    /// Install the canvas into the PDF's internal scroll view so it scrolls with the content.
    func installCanvasIfNeeded() {
        guard !didInstallCanvas else { return }
        guard let sv = pdfView.subviews.compactMap({ $0 as? UIScrollView }).first else { return }
        didInstallCanvas = true

        // Add on top of all PDF content inside the scroll view
        canvasView.frame = CGRect(origin: .zero, size: sv.contentSize)
        sv.addSubview(canvasView)

        // Keep canvas sized to content as user scrolls/zooms
        contentSizeObservation = sv.observe(\.contentSize, options: [.new]) { [weak self] scrollView, _ in
            guard let self else { return }
            self.canvasView.frame = CGRect(origin: .zero, size: scrollView.contentSize)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        pdfView.frame = bounds

        // Fit page width to view on first valid layout.
        if !didInitialScale, bounds.width > 0, pdfView.document != nil {
            didInitialScale = true
            if let firstPage = pdfView.document?.page(at: 0) {
                let pageWidth = firstPage.bounds(for: .mediaBox).width
                if pageWidth > 0 {
                    let fitScale = (bounds.width - 4) / pageWidth
                    pdfView.scaleFactor = fitScale
                    pdfView.minScaleFactor = fitScale * 0.5
                    pdfView.maxScaleFactor = fitScale * 4.0
                }
            }

            // Install canvas after scale is set so contentSize is correct
            installCanvasIfNeeded()

            DispatchQueue.main.async { [weak self] in
                self?.onFirstLayout?()
                self?.onFirstLayout = nil
            }
        }
    }
}
