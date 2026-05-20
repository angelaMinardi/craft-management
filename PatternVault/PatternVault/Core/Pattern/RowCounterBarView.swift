//
//  RowCounterBarView.swift
//  PatternVault
//

import SwiftUI

struct RowCounterBarView: View {
    let currentRow: Int
    let totalRows: Int
    let secondaryCounters: [SecondaryCounter]
    let alertRows: [Int]
    let onDecrement: () -> Void
    let onIncrement: () -> Void
    let onAddSecondary: () -> Void
    let onTapSecondary: (UUID) -> Void
    let onLongPressSecondary: (UUID) -> Void
    let onAddAlertRow: (Int) -> Void
    let onRemoveAlertRow: (Int) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var counterScale: CGFloat = 1.0
    @State private var showReminderSheet = false
    @State private var reminderRowText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.md) {
                Button {
                    onDecrement()
                    pulseCounter()
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Image(systemName: "chevron.down.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(Theme.deepPlum)
                }
                .buttonStyle(.plain)

                Text("Row \(currentRow) / \(totalRows)")
                    .font(Theme.Typography.cardTitle)
                    .foregroundStyle(Theme.deepPlum)
                    .contentTransition(.numericText())
                    .scaleEffect(counterScale)
                    .frame(maxWidth: .infinity)
                    .animation(reduceMotion ? .none : Theme.Motion.spring, value: currentRow)
                    .contextMenu {
                        Button {
                            reminderRowText = ""
                            showReminderSheet = true
                        } label: {
                            Label("Add row reminder…", systemImage: "bell.badge")
                        }
                        if !alertRows.isEmpty {
                            Divider()
                            ForEach(alertRows, id: \.self) { row in
                                Button(role: .destructive) {
                                    onRemoveAlertRow(row)
                                } label: {
                                    Label("Remove reminder at row \(row)", systemImage: "bell.slash")
                                }
                            }
                        }
                    }

                // Bell badge if reminders are set
                if !alertRows.isEmpty {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.honey)
                        .onTapGesture {
                            reminderRowText = ""
                            showReminderSheet = true
                        }
                }

                Button {
                    onIncrement()
                    pulseCounter()
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Image(systemName: "chevron.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(Theme.sageGreen)
                }
                .buttonStyle(.plain)
            }
            .sheet(isPresented: $showReminderSheet) {
                rowReminderSheet
            }

            HStack(spacing: Theme.Spacing.xs) {
                ForEach(secondaryCounters.filter { $0.isActive }.prefix(3)) { counter in
                    secondaryChip(counter)
                }

                Button(action: onAddSecondary) {
                    Label("Add", systemImage: "plus.circle")
                        .font(Theme.Typography.captionSemibold)
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

    private var rowReminderSheet: some View {
        NavigationStack {
            Form {
                Section("Remind me when I reach row:") {
                    TextField("Row number", text: $reminderRowText)
                        .keyboardType(.numberPad)
                }
                if !alertRows.isEmpty {
                    Section("Current reminders") {
                        ForEach(alertRows, id: \.self) { row in
                            HStack {
                                Image(systemName: "bell.fill")
                                    .foregroundStyle(Theme.honey)
                                Text("Row \(row)")
                                    .foregroundStyle(Theme.deepPlum)
                                Spacer()
                                Button(role: .destructive) {
                                    onRemoveAlertRow(row)
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundStyle(Theme.softCoral)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Row Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showReminderSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        if let row = Int(reminderRowText), row > 0 {
                            onAddAlertRow(row)
                        }
                        showReminderSheet = false
                    }
                    .disabled(Int(reminderRowText) == nil || (Int(reminderRowText) ?? 0) <= 0)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func pulseCounter() {
        guard !reduceMotion else { return }
        withAnimation(.spring(response: 0.15, dampingFraction: 0.5)) {
            counterScale = 1.15
        }
        withAnimation(.spring(response: 0.2, dampingFraction: 0.7).delay(0.12)) {
            counterScale = 1.0
        }
    }

    @ViewBuilder
    private func secondaryChip(_ counter: SecondaryCounter) -> some View {
        if counter.linkMode == .unlinked && counter.color == "dustyBlue" {
            repeatCycleChip(counter)
        } else {
            let title = counter.title.isEmpty ? "Counter" : counter.title
            Text("\(title): \(counter.currentCount)/\(counter.resetAfter)")
                .font(Theme.Typography.caption2.weight(.semibold))
                .foregroundStyle(Theme.deepPlum)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Theme.cardBackground)
                .clipShape(Capsule())
                .onTapGesture { onTapSecondary(counter.id) }
                .onLongPressGesture { onLongPressSecondary(counter.id) }
        }
    }

    @ViewBuilder
    private func repeatCycleChip(_ counter: SecondaryCounter) -> some View {
        let cycleNum = counter.totalResets + 1
        let label: String = {
            if let max = counter.maxResets {
                return "Cycle \(cycleNum) of ~\(max)"
            }
            return "Cycle \(cycleNum)"
        }()
        HStack(spacing: 4) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 10, weight: .semibold))
            Text(label)
                .font(Theme.Typography.caption2.weight(.semibold))
        }
        .foregroundStyle(Theme.dustyBlue)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Theme.dustyBlue.opacity(0.12))
        .clipShape(Capsule())
        .onTapGesture { onTapSecondary(counter.id) }
        .onLongPressGesture { onLongPressSecondary(counter.id) }
    }
}
