//
//  PatternVaultWidget.swift
//  PatternVaultWidget
//
//  Home Screen widget: shows "Continue" pattern and progress, or summary counts.
//  Data is written by the main app (WidgetDataService) to App Group.
//

import WidgetKit
import SwiftUI

private let suiteName = "group.com.patternvault.app"
private let keyContinueTitle = "widgetContinueTitle"
private let keyContinueProgress = "widgetContinueProgress"
private let keyInProgressCount = "widgetInProgressCount"
private let keyCompletedCount = "widgetCompletedCount"
private let keyTotalCount = "widgetTotalCount"

struct WidgetEntry: TimelineEntry {
    let date: Date
    let continueTitle: String?
    let continueProgress: Double
    let inProgressCount: Int
    let completedCount: Int
    let totalCount: Int
}

struct PatternVaultDataProvider: TimelineProvider {
    func placeholder(in context: Context) -> WidgetEntry {
        WidgetEntry(date: Date(), continueTitle: nil, continueProgress: 0, inProgressCount: 0, completedCount: 0, totalCount: 0)
    }

    func getSnapshot(in context: Context, completion: @escaping (WidgetEntry) -> Void) {
        completion(readEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetEntry>) -> Void) {
        let entry = readEntry()
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func readEntry() -> WidgetEntry {
        let defaults = UserDefaults(suiteName: suiteName)
        let title = defaults?.string(forKey: keyContinueTitle)
        let progress = defaults?.double(forKey: keyContinueProgress) ?? 0
        let inProgress = defaults?.integer(forKey: keyInProgressCount) ?? 0
        let completed = defaults?.integer(forKey: keyCompletedCount) ?? 0
        let total = defaults?.integer(forKey: keyTotalCount) ?? 0
        return WidgetEntry(
            date: Date(),
            continueTitle: title,
            continueProgress: progress,
            inProgressCount: inProgress,
            completedCount: completed,
            totalCount: total
        )
    }
}

struct PatternVaultWidgetEntryView: View {
    var entry: WidgetEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        if let title = entry.continueTitle, !title.isEmpty, entry.inProgressCount > 0 {
            VStack(alignment: .leading, spacing: 6) {
                Text("Continue")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                ProgressView(value: entry.continueProgress, total: 1)
                    .tint(.orange)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else if entry.totalCount > 0 {
            VStack(alignment: .leading, spacing: 4) {
                Text("Pattern Vault")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    label("In progress", value: entry.inProgressCount)
                    label("Done", value: entry.completedCount)
                    label("Saved", value: entry.totalCount)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("Pattern Vault")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Open the app to see your patterns.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private func label(_ name: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(value)")
                .font(.title2.weight(.bold))
            Text(name)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

struct PatternVaultWidget: Widget {
    let kind: String = "PatternVaultWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PatternVaultDataProvider()) { entry in
            PatternVaultWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Pattern Vault")
        .description("See your continue pattern or pattern counts.")
        .supportedFamilies([.systemSmall])
    }
}

#Preview(as: .systemSmall) {
    PatternVaultWidget()
} timeline: {
    WidgetEntry(date: .now, continueTitle: "Chunky Poncho", continueProgress: 0.4, inProgressCount: 2, completedCount: 5, totalCount: 10)
}
