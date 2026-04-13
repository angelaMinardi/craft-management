//
//  ProjectGoal.swift
//  PatternVault
//

import Foundation

struct ProjectGoal: Codable, Equatable {
    var targetDate: Date?
    var stepMilestones: [StepMilestone]

    struct StepMilestone: Codable, Equatable, Identifiable {
        let id: UUID
        var stepIndex: Int
        var stepName: String
        var targetDate: Date
        var isCompleted: Bool

        init(id: UUID = UUID(), stepIndex: Int, stepName: String, targetDate: Date, isCompleted: Bool = false) {
            self.id = id
            self.stepIndex = stepIndex
            self.stepName = stepName
            self.targetDate = targetDate
            self.isCompleted = isCompleted
        }
    }

    init(targetDate: Date? = nil, stepMilestones: [StepMilestone] = []) {
        self.targetDate = targetDate
        self.stepMilestones = stepMilestones
    }

    var daysRemaining: Int? {
        guard let targetDate else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: targetDate).day
    }

    var nextMilestone: StepMilestone? {
        stepMilestones
            .filter { !$0.isCompleted }
            .sorted { $0.targetDate < $1.targetDate }
            .first
    }
}
