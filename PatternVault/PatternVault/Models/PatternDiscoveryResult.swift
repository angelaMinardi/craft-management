//
//  PatternDiscoveryResult.swift
//  PatternVault
//
//  Lightweight model for external pattern search results (e.g. Ravelry).
//  Not persisted; used only in memory for the discovery list.
//

import Foundation

struct PatternDiscoveryResult: Identifiable, Sendable {
    let id: String
    let title: String
    let sourceUrl: String
    let imageUrl: String?
    let isFree: Bool
    let craftType: String?
    let designer: String?
    let patternDescription: String?
}
