//
//  MascotEconomyState.swift
//  PatternVault
//

import Foundation

struct MascotStoreItem: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let emoji: String
    let iconAssetName: String?
    let cost: Int
    let heartBonus: Int

    init(id: String, title: String, subtitle: String, emoji: String, iconAssetName: String? = nil, cost: Int, heartBonus: Int = 1) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.emoji = emoji
        self.iconAssetName = iconAssetName
        self.cost = cost
        self.heartBonus = heartBonus
    }
}

enum MascotEconomyCatalog {
    static let storeItems: [MascotStoreItem] = [
        .init(id: "yarn_treat", title: "Yarn Puff", subtitle: "Soft and cozy", emoji: "🧶", iconAssetName: "store_yarn_treat", cost: 5),
        .init(id: "button_treat", title: "Button Bite", subtitle: "Shiny favorite", emoji: "🔘", iconAssetName: "store_button_treat", cost: 4),
        .init(id: "thimble_treat", title: "Thimble Snack", subtitle: "Rare delight", emoji: "🪡", iconAssetName: "store_thimble_treat", cost: 8),
        .init(id: "golden_yarn", title: "Golden Yarn", subtitle: "Premium yarn, +2 hearts", emoji: "✨", iconAssetName: "store_golden_yarn", cost: 12, heartBonus: 2),
        .init(id: "sparkle_button", title: "Sparkle Button", subtitle: "Dazzling, +2 hearts", emoji: "💎", cost: 15, heartBonus: 2),
        .init(id: "rainbow_thimble", title: "Rainbow Thimble", subtitle: "Rare find, +2 hearts", emoji: "🌈", cost: 20, heartBonus: 2),
    ]

    static var storeItemsWithCustomArt: [MascotStoreItem] {
        storeItems.filter { $0.iconAssetName != nil }
    }

    static func item(for id: String) -> MascotStoreItem? {
        storeItems.first(where: { $0.id == id })
    }
}

