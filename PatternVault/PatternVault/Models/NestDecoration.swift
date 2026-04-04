//
//  NestDecoration.swift
//  PatternVault
//

import Foundation

struct NestDecoration: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let emoji: String
    let iconAssetName: String?
    let cost: Int
    let isSeasonal: Bool
    let availableMonths: [Int]?
}

enum NestDecorationCatalog {
    static let allDecorations: [NestDecoration] = [
        NestDecoration(id: "cozy_blanket", title: "Cozy Blanket", emoji: "🛋️", iconAssetName: "store_deco_cozy_blanket", cost: 10, isSeasonal: false, availableMonths: nil),
        NestDecoration(id: "fairy_lights", title: "Fairy Lights", emoji: "✨", iconAssetName: "store_deco_fairy_lights", cost: 15, isSeasonal: false, availableMonths: nil),
        NestDecoration(id: "yarn_basket", title: "Yarn Basket", emoji: "🧺", iconAssetName: nil, cost: 8, isSeasonal: false, availableMonths: nil),
        NestDecoration(id: "pumpkin_patch", title: "Pumpkin Patch", emoji: "🎃", iconAssetName: nil, cost: 12, isSeasonal: true, availableMonths: [9, 10, 11]),
        NestDecoration(id: "snowflake_garland", title: "Snowflake Garland", emoji: "❄️", iconAssetName: nil, cost: 12, isSeasonal: true, availableMonths: [12, 1, 2]),
    ]

    static func availableNow() -> [NestDecoration] {
        let month = Calendar.current.component(.month, from: Date())
        return allDecorations.filter { !$0.isSeasonal || ($0.availableMonths?.contains(month) ?? true) }
    }

    static func availableNowWithCustomArt() -> [NestDecoration] {
        availableNow().filter { $0.iconAssetName != nil }
    }
}
