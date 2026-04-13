//
//  GoalSettingView.swift
//  PatternVault
//

import SwiftUI

struct GoalSettingView: View {
    let patternId: UUID
    let makeId: UUID?
    let stepNames: [String]
    @ObservedObject var progressStore: PatternProgressStore
    @Environment(\.dismiss) private var dismiss

    @State private var hasTargetDate = false
    @State private var targetDate = Calendar.current.date(byAdding: .day, value: 14, to: Date()) ?? Date()
    @State private var milestones: [ProjectGoal.StepMilestone] = []

    private var existingGoal: ProjectGoal? {
        progressStore.progress(for: patternId, makeId: makeId)?.goal
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Set a target finish date", isOn: $hasTargetDate)
                    if hasTargetDate {
                        DatePicker("Finish by", selection: $targetDate, in: Date()..., displayedComponents: .date)
                    }
                } header: {
                    Text("Overall Goal")
                } footer: {
                    if hasTargetDate, let days = Calendar.current.dateComponents([.day], from: Date(), to: targetDate).day {
                        Text("\(days) days from now")
                    }
                }

                if !stepNames.isEmpty {
                    Section("Step Milestones") {
                        ForEach(stepNames.indices, id: \.self) { index in
                            let existing = milestones.first(where: { $0.stepIndex == index })
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(stepNames[index])
                                        .font(Theme.Typography.body)
                                        .foregroundStyle(Theme.deepPlum)
                                    if let m = existing {
                                        Text(m.targetDate, format: .dateTime.month(.abbreviated).day())
                                            .font(Theme.Typography.caption2)
                                            .foregroundStyle(m.isCompleted ? Theme.sageGreen : Theme.deepPlum.opacity(0.5))
                                    }
                                }
                                Spacer()
                                if existing != nil {
                                    Button {
                                        milestones.removeAll { $0.stepIndex == index }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(Theme.deepPlum.opacity(0.3))
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    Button("Set date") {
                                        let date = Calendar.current.date(byAdding: .day, value: (index + 1) * 3, to: Date()) ?? Date()
                                        milestones.append(.init(stepIndex: index, stepName: stepNames[index], targetDate: date))
                                    }
                                    .font(Theme.Typography.caption)
                                    .foregroundStyle(Theme.sageGreen)
                                }
                            }
                        }
                    }

                    if !milestones.isEmpty {
                        Section("Adjust Dates") {
                            ForEach($milestones) { $milestone in
                                DatePicker(
                                    milestone.stepName,
                                    selection: $milestone.targetDate,
                                    in: Date()...,
                                    displayedComponents: .date
                                )
                                .font(Theme.Typography.caption)
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.screenGradient.ignoresSafeArea())
            .navigationTitle("Set Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveGoal() }
                }
            }
            .onAppear {
                if let existing = existingGoal {
                    hasTargetDate = existing.targetDate != nil
                    if let d = existing.targetDate { targetDate = d }
                    milestones = existing.stepMilestones
                }
            }
        }
    }

    private func saveGoal() {
        let goal = ProjectGoal(
            targetDate: hasTargetDate ? targetDate : nil,
            stepMilestones: milestones
        )
        var progress = progressStore.progress(for: patternId, makeId: makeId) ??
            PatternProgressData(currentStepIndex: 0, stepCount: nil, rowsCompleted: nil, totalRows: nil, yarnColorName: nil, customStepLayout: nil)
        progress.goal = goal
        progressStore.write(patternId: patternId, makeId: makeId, progress)
        progressStore.saveToDefaults()
        dismiss()
    }
}
