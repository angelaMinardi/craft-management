//
//  RowCounterBarView.swift
//  PatternVault
//

import SwiftUI

struct RowCounterBarView: View {
    let currentRow: Int
    let totalRows: Int
    let secondaryCounters: [SecondaryCounter]
    let onDecrement: () -> Void
    let onIncrement: () -> Void
    let onAddSecondary: () -> Void
    let onTapSecondary: (UUID) -> Void
    let onLongPressSecondary: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.md) {
                Button(action: onDecrement) {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(Theme.deepPlum)
                }
                .buttonStyle(.plain)

                Text("Row \(currentRow) / \(totalRows)")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.deepPlum)
                    .frame(maxWidth: .infinity)

                Button(action: onIncrement) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(Theme.sageGreen)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: Theme.Spacing.xs) {
                ForEach(secondaryCounters.filter { $0.isActive }.prefix(3)) { counter in
                    secondaryChip(counter)
                }

                Button(action: onAddSecondary) {
                    Label("Add", systemImage: "plus.circle")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.dustyBlue)
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Theme.Spacing.sm)
        .background(Theme.warmCream.opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
    }

    @ViewBuilder
    private func secondaryChip(_ counter: SecondaryCounter) -> some View {
        let title = counter.title.isEmpty ? "Counter" : counter.title
        Text("\(title): \(counter.currentCount)/\(counter.resetAfter)")
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(Theme.deepPlum)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Theme.cardBackground)
            .clipShape(Capsule())
            .onTapGesture { onTapSecondary(counter.id) }
            .onLongPressGesture { onLongPressSecondary(counter.id) }
    }
}
