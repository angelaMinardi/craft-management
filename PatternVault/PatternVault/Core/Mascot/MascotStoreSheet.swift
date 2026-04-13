//
//  MascotStoreSheet.swift
//  PatternVault
//

import SwiftUI

struct MascotStoreSheet: View {
    @ObservedObject var mascotStore: MascotInteractionStore
    @State private var selectedTab = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    balanceRow

                    Picker("Category", selection: $selectedTab) {
                        Text("Treats").tag(0)
                        Text("Decor").tag(1)
                    }
                    .pickerStyle(.segmented)

                    if selectedTab == 0 {
                        treatsSection
                    } else {
                        decorationsSection
                    }

                    Text("How it works: Petting, feeding, and pattern progress earn Thread Points. Tap a treat on the dashboard to feed \(mascotStore.mascotName).")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.deepPlum.opacity(0.6))
                }
                .padding(Theme.Spacing.lg)
            }
            .background(Theme.screenGradient.ignoresSafeArea())
            .navigationTitle("Mascot Store")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var balanceRow: some View {
        HStack {
            Label("Thread Points", systemImage: "sparkles")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.deepPlum.opacity(0.7))
            Spacer()
            Text("\(mascotStore.threadPoints)")
                .font(Theme.Typography.titleBold)
                .foregroundStyle(Theme.deepPlum)
        }
        .padding()
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
    }

    private var treatsSection: some View {
        let customTreats = MascotEconomyCatalog.storeItemsWithCustomArt
        return VStack(spacing: Theme.Spacing.sm) {
            ForEach(customTreats) { item in
                HStack(spacing: Theme.Spacing.md) {
                    if let iconAssetName = item.iconAssetName {
                        Image(iconAssetName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 36, height: 36)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(item.title)
                                .font(Theme.Typography.body)
                                .foregroundStyle(Theme.deepPlum)
                            if item.heartBonus > 1 {
                                Text("+\(item.heartBonus) ❤️")
                                    .font(Theme.Typography.caption2.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Theme.softCoral)
                                    .clipShape(Capsule())
                            }
                        }
                        Text(item.subtitle)
                            .font(Theme.Typography.caption2)
                            .foregroundStyle(Theme.deepPlum.opacity(0.6))
                    }
                    Spacer()
                    Button("Buy \(item.cost)") {
                        _ = mascotStore.purchaseTreat(item.id, cost: item.cost)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.softCoral)
                    .disabled(mascotStore.threadPoints < item.cost)
                }
                .padding()
                .background(Color.white.opacity(0.72))
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
            }
        }
    }

    private var decorationsSection: some View {
        let available = NestDecorationCatalog.availableNowWithCustomArt()
        return VStack(spacing: Theme.Spacing.sm) {
            ForEach(available) { deco in
                let owned = mascotStore.ownedDecorationIds.contains(deco.id)
                let selected = mascotStore.selectedDecorationId == deco.id
                HStack(spacing: Theme.Spacing.md) {
                    if let iconAssetName = deco.iconAssetName {
                        Image(iconAssetName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 36, height: 36)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(deco.title)
                                .font(Theme.Typography.body)
                                .foregroundStyle(Theme.deepPlum)
                            if deco.isSeasonal {
                                Text("Limited!")
                                    .font(Theme.Typography.caption2.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Theme.honey)
                                    .clipShape(Capsule())
                            }
                        }
                        Text(owned ? "Owned" : "\(deco.cost) pts")
                            .font(Theme.Typography.caption2)
                            .foregroundStyle(Theme.deepPlum.opacity(0.6))
                    }
                    Spacer()
                    if owned {
                        Button(selected ? "Selected" : "Select") {
                            mascotStore.selectDecoration(selected ? nil : deco.id)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(selected ? Theme.sageGreen : Theme.dustyBlue)
                    } else {
                        Button("Buy \(deco.cost)") {
                            _ = mascotStore.purchaseDecoration(deco.id, cost: deco.cost)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.softCoral)
                        .disabled(mascotStore.threadPoints < deco.cost)
                    }
                }
                .padding()
                .background(Color.white.opacity(0.72))
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
            }

            if available.isEmpty {
                Text("No decorations available this season. Check back later!")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.deepPlum.opacity(0.5))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.xxl)
            }
        }
    }
}
