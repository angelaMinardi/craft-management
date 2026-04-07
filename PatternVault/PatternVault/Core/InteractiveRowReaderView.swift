//
//  InteractiveRowReaderView.swift
//  PatternVault
//

import SwiftUI

struct InteractiveRowReaderView: View {
    let rows: [ParsedRow]
    let patternId: UUID
    let makeId: UUID?
    let patternTitle: String

    @ObservedObject private var rowCounterStore = RowCounterStore.shared
    @State private var showCounterSheet = false
    @State private var editingCounterId: UUID?

    private var currentState: RowCounterState {
        rowCounterStore.state(for: patternId, makeId: makeId)
    }

    private var currentRow: Int {
        currentState.globalRow
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        ForEach(rows) { row in
                            rowLine(row)
                                .id(row.id)
                                .onTapGesture {
                                    rowCounterStore.jumpToRow(patternId: patternId, makeId: makeId, row: row.id, patternTitle: patternTitle)
                                }
                        }
                    }
                }
                .frame(maxHeight: 260)
                .onAppear {
                    rowCounterStore.setTotalRows(patternId: patternId, makeId: makeId, totalRows: rows.count)
                    let startRow = max(1, currentRow)
                    proxy.scrollTo(startRow, anchor: .center)
                }
                .onChange(of: currentRow) { _, newRow in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(newRow, anchor: .center)
                    }
                }
            }

            RowCounterBarView(
                currentRow: currentRow,
                totalRows: rows.count,
                secondaryCounters: currentState.secondaryCounters,
                onDecrement: {
                    rowCounterStore.decrementGlobal(patternId: patternId, makeId: makeId, patternTitle: patternTitle)
                },
                onIncrement: {
                    rowCounterStore.incrementGlobal(patternId: patternId, makeId: makeId, patternTitle: patternTitle)
                },
                onAddSecondary: {
                    editingCounterId = nil
                    showCounterSheet = true
                },
                onTapSecondary: { counterId in
                    rowCounterStore.incrementSecondary(patternId: patternId, makeId: makeId, counterId: counterId, patternTitle: patternTitle)
                },
                onLongPressSecondary: { counterId in
                    editingCounterId = counterId
                    showCounterSheet = true
                }
            )
        }
        .sheet(isPresented: $showCounterSheet) {
            SecondaryCounterConfigSheet(
                existing: editingCounter,
                onSave: { counter in
                    if editingCounter != nil {
                        rowCounterStore.updateSecondaryCounter(patternId: patternId, makeId: makeId, counter: counter)
                    } else {
                        rowCounterStore.addSecondaryCounter(
                            patternId: patternId,
                            makeId: makeId,
                            title: counter.title,
                            resetAfter: counter.resetAfter,
                            maxResets: counter.maxResets,
                            linkMode: counter.linkMode,
                            color: counter.color
                        )
                    }
                },
                onDelete: editingCounter == nil ? nil : {
                    guard let id = editingCounterId else { return }
                    rowCounterStore.removeSecondaryCounter(patternId: patternId, makeId: makeId, counterId: id)
                }
            )
        }
    }

    @ViewBuilder
    private func rowLine(_ row: ParsedRow) -> some View {
        let isCurrent = row.id == currentRow
        let isPast = row.id < currentRow
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
            Text(isCurrent ? ">" : " ")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.honey)
            Text("Row \(row.id): \(row.instruction)")
                .font(.system(size: 14, weight: isCurrent ? .semibold : .regular, design: .rounded))
                .foregroundStyle(Theme.deepPlum)
                .opacity(isPast ? 0.55 : 1)
            Spacer(minLength: 0)
            if let stitchCount = row.stitchCount {
                Text("\(stitchCount) sts")
                    .font(Theme.Typography.caption2)
                    .foregroundStyle(Theme.deepPlum.opacity(0.45))
            }
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xs)
        .background(isCurrent ? Theme.honey.opacity(0.18) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.small))
    }

    private var editingCounter: SecondaryCounter? {
        guard let id = editingCounterId else { return nil }
        return currentState.secondaryCounters.first(where: { $0.id == id })
    }
}
