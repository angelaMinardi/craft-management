//
//  RowCounter.swift
//  PatternVault
//
//  State models for the global row counter and linked secondary counters.
//

import Foundation

struct RowCounterState: Codable, Equatable {
    var globalRow: Int = 1
    var totalRows: Int?
    var secondaryCounters: [SecondaryCounter] = []
}

struct SecondaryCounter: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    var currentCount: Int = 1
    var resetAfter: Int
    var totalResets: Int = 0
    var maxResets: Int?
    var isLinkedToGlobal: Bool = true
    var linkMode: LinkMode = .oneWay
    var color: String = "softCoral"
    var isActive: Bool = true

    enum LinkMode: String, Codable, CaseIterable {
        case oneWay     // global increments this
        case twoWay     // this also increments global
        case unlinked   // independent
    }

    init(id: UUID = UUID(), title: String, resetAfter: Int, maxResets: Int? = nil, linkMode: LinkMode = .oneWay, color: String = "softCoral") {
        self.id = id
        self.title = title
        self.resetAfter = resetAfter
        self.maxResets = maxResets
        self.isLinkedToGlobal = linkMode != .unlinked
        self.linkMode = linkMode
        self.color = color
    }
}
