//
//  ChartHighlight.swift
//  PatternVault
//

import Foundation

struct ChartSurfaceAnnotation: Codable, Identifiable, Equatable {
    enum Kind: String, Codable, CaseIterable {
        case pin
        case note
        case increase
        case decrease
        case repeatSection
        case caution

        var symbolName: String {
            switch self {
            case .pin: return "mappin.circle.fill"
            case .note: return "note.text"
            case .increase: return "plus.circle.fill"
            case .decrease: return "minus.circle.fill"
            case .repeatSection: return "arrow.clockwise.circle.fill"
            case .caution: return "exclamationmark.triangle.fill"
            }
        }
    }

    let id: UUID
    var kind: Kind
    var normalizedX: Double
    var normalizedY: Double
    var title: String?
    var note: String?

    init(
        id: UUID = UUID(),
        kind: Kind,
        normalizedX: Double,
        normalizedY: Double,
        title: String? = nil,
        note: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.normalizedX = min(max(normalizedX, 0), 1)
        self.normalizedY = min(max(normalizedY, 0), 1)
        self.title = title
        self.note = note
    }
}

struct ChartHighlight: Identifiable, Codable, Equatable {
    enum ChartType: String, Codable, CaseIterable {
        case workedFlat
        case workedInRound
    }

    enum CounterLink: Codable, Equatable {
        case global
        case secondary(UUID)

        enum CodingKeys: String, CodingKey {
            case kind
            case id
        }

        enum Kind: String, Codable {
            case global
            case secondary
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let kind = try c.decode(Kind.self, forKey: .kind)
            switch kind {
            case .global:
                self = .global
            case .secondary:
                let id = try c.decode(UUID.self, forKey: .id)
                self = .secondary(id)
            }
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .global:
                try c.encode(Kind.global, forKey: .kind)
            case .secondary(let id):
                try c.encode(Kind.secondary, forKey: .kind)
                try c.encode(id, forKey: .id)
            }
        }
    }

    let id: UUID
    let patternId: UUID
    let makeId: UUID?
    let imageId: UUID?
    let pdfPageIndex: Int?

    // Normalized coordinates (0...1) within the rendered image bounds.
    var minX: Double
    var minY: Double
    var maxX: Double
    var maxY: Double

    var rows: Int
    var columns: Int
    var chartType: ChartType
    var isSideways: Bool
    var isC2C: Bool

    var rowCounterLink: CounterLink
    var columnCounterLink: CounterLink?
    var rowColorName: String
    var columnColorName: String
    var extractedChartPNGData: Data?
    var annotationDrawingData: Data?
    var currentRow: Int
    var currentColumn: Int
    var annotations: [ChartSurfaceAnnotation]
    var gridInsetLeft: Double
    var gridInsetTop: Double
    var gridInsetRight: Double
    var gridInsetBottom: Double
    var chartLabel: String?
    var isAIExtracted: Bool

    init(
        id: UUID = UUID(),
        patternId: UUID,
        makeId: UUID?,
        imageId: UUID,
        minX: Double,
        minY: Double,
        maxX: Double,
        maxY: Double,
        rows: Int,
        columns: Int,
        chartType: ChartType,
        isSideways: Bool,
        isC2C: Bool,
        rowCounterLink: CounterLink,
        columnCounterLink: CounterLink?,
        rowColorName: String = "honey",
        columnColorName: String = "softCoral",
        extractedChartPNGData: Data? = nil,
        annotationDrawingData: Data? = nil,
        currentRow: Int = 1,
        currentColumn: Int = 1,
        annotations: [ChartSurfaceAnnotation] = [],
        gridInsetLeft: Double = 0,
        gridInsetTop: Double = 0,
        gridInsetRight: Double = 0,
        gridInsetBottom: Double = 0,
        chartLabel: String? = nil,
        isAIExtracted: Bool = false
    ) {
        self.id = id
        self.patternId = patternId
        self.makeId = makeId
        self.imageId = imageId
        self.pdfPageIndex = nil
        self.minX = minX
        self.minY = minY
        self.maxX = maxX
        self.maxY = maxY
        self.rows = max(1, rows)
        self.columns = max(1, columns)
        self.chartType = chartType
        self.isSideways = isSideways
        self.isC2C = isC2C
        self.rowCounterLink = rowCounterLink
        self.columnCounterLink = columnCounterLink
        self.rowColorName = rowColorName
        self.columnColorName = columnColorName
        self.extractedChartPNGData = extractedChartPNGData
        self.annotationDrawingData = annotationDrawingData
        self.currentRow = currentRow
        self.currentColumn = currentColumn
        self.annotations = annotations
        self.gridInsetLeft = min(max(gridInsetLeft, 0), 0.45)
        self.gridInsetTop = min(max(gridInsetTop, 0), 0.45)
        self.gridInsetRight = min(max(gridInsetRight, 0), 0.45)
        self.gridInsetBottom = min(max(gridInsetBottom, 0), 0.45)
        self.chartLabel = chartLabel
        self.isAIExtracted = isAIExtracted
    }

    init(
        id: UUID = UUID(),
        patternId: UUID,
        makeId: UUID?,
        pdfPageIndex: Int,
        minX: Double,
        minY: Double,
        maxX: Double,
        maxY: Double,
        rows: Int,
        columns: Int,
        chartType: ChartType,
        isSideways: Bool,
        isC2C: Bool,
        rowCounterLink: CounterLink,
        columnCounterLink: CounterLink?,
        rowColorName: String = "honey",
        columnColorName: String = "softCoral",
        extractedChartPNGData: Data? = nil,
        annotationDrawingData: Data? = nil,
        currentRow: Int = 1,
        currentColumn: Int = 1,
        annotations: [ChartSurfaceAnnotation] = [],
        gridInsetLeft: Double = 0,
        gridInsetTop: Double = 0,
        gridInsetRight: Double = 0,
        gridInsetBottom: Double = 0,
        chartLabel: String? = nil,
        isAIExtracted: Bool = false
    ) {
        self.id = id
        self.patternId = patternId
        self.makeId = makeId
        self.imageId = nil
        self.pdfPageIndex = max(0, pdfPageIndex)
        self.minX = minX
        self.minY = minY
        self.maxX = maxX
        self.maxY = maxY
        self.rows = max(1, rows)
        self.columns = max(1, columns)
        self.chartType = chartType
        self.isSideways = isSideways
        self.isC2C = isC2C
        self.rowCounterLink = rowCounterLink
        self.columnCounterLink = columnCounterLink
        self.rowColorName = rowColorName
        self.columnColorName = columnColorName
        self.extractedChartPNGData = extractedChartPNGData
        self.annotationDrawingData = annotationDrawingData
        self.currentRow = currentRow
        self.currentColumn = currentColumn
        self.annotations = annotations
        self.gridInsetLeft = min(max(gridInsetLeft, 0), 0.45)
        self.gridInsetTop = min(max(gridInsetTop, 0), 0.45)
        self.gridInsetRight = min(max(gridInsetRight, 0), 0.45)
        self.gridInsetBottom = min(max(gridInsetBottom, 0), 0.45)
        self.chartLabel = chartLabel
        self.isAIExtracted = isAIExtracted
    }

    enum CodingKeys: String, CodingKey {
        case id
        case patternId
        case makeId
        case imageId
        case pdfPageIndex
        case minX
        case minY
        case maxX
        case maxY
        case rows
        case columns
        case chartType
        case isSideways
        case isC2C
        case rowCounterLink
        case columnCounterLink
        case rowColorName
        case columnColorName
        case extractedChartPNGData
        case annotationDrawingData
        case currentRow
        case currentColumn
        case annotations
        case gridInsetLeft
        case gridInsetTop
        case gridInsetRight
        case gridInsetBottom
        case chartLabel
        case isAIExtracted
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        patternId = try c.decode(UUID.self, forKey: .patternId)
        makeId = try c.decodeIfPresent(UUID.self, forKey: .makeId)
        imageId = try c.decodeIfPresent(UUID.self, forKey: .imageId)
        pdfPageIndex = try c.decodeIfPresent(Int.self, forKey: .pdfPageIndex)
        minX = try c.decode(Double.self, forKey: .minX)
        minY = try c.decode(Double.self, forKey: .minY)
        maxX = try c.decode(Double.self, forKey: .maxX)
        maxY = try c.decode(Double.self, forKey: .maxY)
        rows = max(1, try c.decode(Int.self, forKey: .rows))
        columns = max(1, try c.decode(Int.self, forKey: .columns))
        chartType = try c.decode(ChartType.self, forKey: .chartType)
        isSideways = try c.decode(Bool.self, forKey: .isSideways)
        isC2C = try c.decode(Bool.self, forKey: .isC2C)
        rowCounterLink = try c.decode(CounterLink.self, forKey: .rowCounterLink)
        columnCounterLink = try c.decodeIfPresent(CounterLink.self, forKey: .columnCounterLink)
        rowColorName = try c.decode(String.self, forKey: .rowColorName)
        columnColorName = try c.decode(String.self, forKey: .columnColorName)
        extractedChartPNGData = try c.decodeIfPresent(Data.self, forKey: .extractedChartPNGData)
        annotationDrawingData = try c.decodeIfPresent(Data.self, forKey: .annotationDrawingData)
        currentRow = max(1, try c.decodeIfPresent(Int.self, forKey: .currentRow) ?? 1)
        currentColumn = max(1, try c.decodeIfPresent(Int.self, forKey: .currentColumn) ?? 1)
        annotations = try c.decodeIfPresent([ChartSurfaceAnnotation].self, forKey: .annotations) ?? []
        gridInsetLeft = min(max(try c.decodeIfPresent(Double.self, forKey: .gridInsetLeft) ?? 0, 0), 0.45)
        gridInsetTop = min(max(try c.decodeIfPresent(Double.self, forKey: .gridInsetTop) ?? 0, 0), 0.45)
        gridInsetRight = min(max(try c.decodeIfPresent(Double.self, forKey: .gridInsetRight) ?? 0, 0), 0.45)
        gridInsetBottom = min(max(try c.decodeIfPresent(Double.self, forKey: .gridInsetBottom) ?? 0, 0), 0.45)
        chartLabel = try c.decodeIfPresent(String.self, forKey: .chartLabel)
        isAIExtracted = try c.decodeIfPresent(Bool.self, forKey: .isAIExtracted) ?? false
    }
}
