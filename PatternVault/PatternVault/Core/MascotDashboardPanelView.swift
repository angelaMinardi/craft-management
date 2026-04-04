//
//  MascotDashboardPanelView.swift
//  PatternVault
//

import SwiftUI
import UniformTypeIdentifiers

struct MascotDashboardPanelView: View {
    @ObservedObject var store: MascotInteractionStore
    var onOpenSettings: () -> Void
    var onOpenStore: () -> Void = { }
    var showLabels: Bool = false

    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.mascotName)
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.deepPlum)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    heartsRow
                    if showLabels {
                        Text("Bond level")
                            .font(Theme.Typography.caption2)
                            .foregroundStyle(Theme.deepPlum.opacity(0.55))
                    }
                }
                Spacer()
                Button(action: onOpenSettings) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Theme.deepPlum.opacity(0.9))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Rename mascot")
            }

            ZStack(alignment: .bottom) {
                Image("MascotHeroBackground")
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, minHeight: 290, maxHeight: 290)
                    .offset(y: -22)
                    .mask(
                        LinearGradient(
                            colors: [.white, .white, .white.opacity(0.8), .white.opacity(0.5)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 28)
                            .stroke(Color.white.opacity(0.82), lineWidth: 2)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 28))

                if let decoId = store.selectedDecorationId,
                   let deco = NestDecorationCatalog.allDecorations.first(where: { $0.id == decoId }) {
                    if let iconAssetName = deco.iconAssetName {
                        VStack {
                            HStack {
                                Spacer()
                                Image(iconAssetName)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 88, height: 88)
                                    .padding(.top, Theme.Spacing.md)
                                    .padding(.trailing, Theme.Spacing.md)
                                    .shadow(color: Theme.deepPlum.opacity(0.18), radius: 5, x: 0, y: 2)
                            }
                            Spacer()
                        }
                        .transition(.opacity.combined(with: .scale))
                    }
                }

                mascotView
                    .frame(height: 170)
                    .padding(.bottom, 10)
                    .offset(y: 16)
                    .scaleEffect(isDropTargeted ? 1.04 : 1.0)
                    .animation(.easeInOut(duration: 0.2), value: isDropTargeted)

                utilityRow
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.bottom, Theme.Spacing.sm)
            }
            .onTapGesture {
                store.pet()
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        store.pet()
                    }
            )
            .onDrop(of: [UTType.text], isTargeted: $isDropTargeted) { providers in
                handleDrop(providers)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(store.mascotName), interactive mascot")
            .accessibilityHint("Tap to pet, or drag a treat onto the mascot")

            treatRow
            if showLabels {
                Text("Tap a treat to feed \(store.mascotName)")
                    .font(Theme.Typography.caption2)
                    .foregroundStyle(Theme.deepPlum.opacity(0.55))
            }

            if let msg = store.transientMessage {
                Text(msg)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.deepPlum.opacity(0.65))
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .transition(.opacity)
            }
        }
        .padding(Theme.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.large)
                .fill(Color.white.opacity(0.2))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.large)
                .stroke(Theme.deepPlum.opacity(0.08), lineWidth: 1)
        )
    }

    private var utilityRow: some View {
        HStack {
            Button(action: onOpenStore) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Image(systemName: "storefront.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.deepPlum.opacity(0.8))
                        Text("Store")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.deepPlum.opacity(0.85))
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()

            HStack(spacing: 5) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.softCoral)
                Text("\(store.streakCount)")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.deepPlum)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.6))
            .clipShape(Capsule())
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Streak \(store.streakCount)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var heartsRow: some View {
        HStack(spacing: 3) {
            ForEach(0..<store.heartsMax, id: \.self) { idx in
                Image(systemName: idx < store.heartsCurrent ? "heart.fill" : "heart")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(idx < store.heartsCurrent ? Theme.softCoral : Theme.deepPlum.opacity(0.2))
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Hearts \(store.heartsCurrent) out of \(store.heartsMax)")
    }

    @ViewBuilder
    private var mascotView: some View {
        switch store.pose {
        case .idle:
            SpriteMascotView.idle(size: 140)
        case .knitting:
            SpriteMascotView.knitting(size: 140)
        case .jumping:
            // Jump frames read visually smaller; oversize so the mascot keeps perceived size.
            SpriteMascotView.jumping(size: 170)
        case .pouty:
            SpriteMascotView.pouty(size: 140)
        case .petting:
            SpriteMascotView.petting(size: 156)
        }
    }

    private var treatRow: some View {
        HStack(spacing: Theme.Spacing.sm) {
            ForEach(store.availableTreats) { item in
                let qty = store.treatInventory[item.id] ?? 0
                Button {
                    if qty > 0 {
                        store.feed(treatId: item.id)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(item.iconAssetName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 18, height: 18)
                        Text("\(qty)")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.deepPlum.opacity(0.7))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.7))
                    )
                    .overlay(
                        Capsule()
                            .stroke(Theme.deepPlum.opacity(0.08), lineWidth: 1)
                    )
                    .opacity(qty > 0 ? 1 : 0.45)
                }
                .buttonStyle(.plain)
                .onDrag {
                    NSItemProvider(object: NSString(string: item.id))
                }
                .accessibilityLabel("\(item.title) treat, \(qty) available")
                .accessibilityHint(qty > 0 ? "Tap to feed \(store.mascotName)" : "Empty")
            }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { object, _ in
            var treatId: String?
            if let data = object as? Data {
                treatId = String(data: data, encoding: .utf8)
            } else if let str = object as? String {
                treatId = str
            } else if let ns = object as? NSString {
                treatId = ns as String
            }
            guard let treatId else { return }
            Task { @MainActor in
                store.feed(treatId: treatId.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        return true
    }
}

