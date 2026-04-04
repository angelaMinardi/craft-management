//
//  RowTrackerWidget.swift
//  PatternVaultWidget
//
//  Lock-screen row counter: shows active pattern name and Row X / Y with +/-.
//  Data is written by the main app (WidgetDataService) and by the widget’s +/- intents.
//

import AppIntents
import SwiftUI
import WidgetKit

private let suiteName = "group.com.patternvault.app"
private let keyActivePatternId = "widgetActivePatternId"
private let keyActivePatternTitle = "widgetActivePatternTitle"
private let keyWidgetRowCurrent = "widgetRowCurrent"
private let keyWidgetRowTotal = "widgetRowTotal"
private let keyWidgetSecondaryTitle = "widgetSecondaryTitle"
private let keyWidgetSecondaryCurrent = "widgetSecondaryCurrent"
private let keyWidgetSecondaryResetAfter = "widgetSecondaryResetAfter"

// Brand colors for widget (match Theme.swift; widget has no access to main app assets)
// Use dark background for lock-screen visibility on light and dark wallpapers.
private let widgetBackground = Color(red: 0.22, green: 0.10, blue: 0.18) // deep plum, opaque
private let widgetWarmCream = Color(red: 1.0, green: 0.973, blue: 0.941)
private let widgetDeepPlum = Color(red: 0.29, green: 0.125, blue: 0.251)
private let widgetSoftCoral = Color(red: 0.91, green: 0.514, blue: 0.42)
private let widgetTextOnDark = Color.white
private let widgetSecondaryOnDark = Color.white.opacity(0.85)

private let keyIsPremium = "entitlement_is_premium"

struct RowTrackerEntry: TimelineEntry {
    let date: Date
    let patternId: UUID?
    let patternTitle: String?
    let currentRow: Int
    let totalRows: Int?
    let secondaryTitle: String?
    let secondaryCurrent: Int?
    let secondaryResetAfter: Int?
    let isPremium: Bool
}

struct RowTrackerProvider: TimelineProvider {
    func placeholder(in context: Context) -> RowTrackerEntry {
        RowTrackerEntry(
            date: Date(),
            patternId: nil,
            patternTitle: "My project",
            currentRow: 12,
            totalRows: 120,
            secondaryTitle: "Cable",
            secondaryCurrent: 3,
            secondaryResetAfter: 8,
            isPremium: true
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (RowTrackerEntry) -> Void) {
        completion(readEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RowTrackerEntry>) -> Void) {
        let entry = readEntry()
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func readEntry() -> RowTrackerEntry {
        let defaults = UserDefaults(suiteName: suiteName)
        let isPremium = defaults?.bool(forKey: keyIsPremium) ?? false
        let idString = defaults?.string(forKey: keyActivePatternId)
        let patternId = idString.flatMap { UUID(uuidString: $0) }
        let title = defaults?.string(forKey: keyActivePatternTitle)
        let current = defaults?.object(forKey: keyWidgetRowCurrent) as? Int ?? 0
        let total = defaults?.object(forKey: keyWidgetRowTotal) as? Int
        let secondaryTitle = defaults?.string(forKey: keyWidgetSecondaryTitle)
        let secondaryCurrent = defaults?.object(forKey: keyWidgetSecondaryCurrent) as? Int
        let secondaryResetAfter = defaults?.object(forKey: keyWidgetSecondaryResetAfter) as? Int
        return RowTrackerEntry(
            date: Date(),
            patternId: patternId,
            patternTitle: title,
            currentRow: max(0, current),
            totalRows: total.map { max(0, $0) },
            secondaryTitle: secondaryTitle,
            secondaryCurrent: secondaryCurrent.map { max(0, $0) },
            secondaryResetAfter: secondaryResetAfter.map { max(0, $0) },
            isPremium: isPremium
        )
    }
}

struct RowTrackerWidgetView: View {
    var entry: RowTrackerEntry
    @Environment(\.widgetFamily) var family

    /// No active pattern: app wrote nil/empty title and 0 rows.
    private var isEmpty: Bool {
        let hasTitle = entry.patternTitle.map { !$0.isEmpty } ?? false
        return !hasTitle && entry.currentRow == 0
    }

    var body: some View {
        switch family {
        case .accessoryRectangular:
            if entry.isPremium {
                accessoryRectangularView
            } else {
                premiumUpgradeRectangularView
            }
        case .accessoryInline:
            if entry.isPremium {
                accessoryInlineView
            } else {
                Text("Row Tracker · Premium")
                    .accessibilityLabel("Row Tracker is a premium feature")
            }
        default:
            if entry.isPremium {
                accessoryRectangularView
            } else {
                premiumUpgradeRectangularView
            }
        }
    }

    private var premiumUpgradeRectangularView: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Row Tracker")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(widgetTextOnDark)
            Text("Upgrade to Premium to track rows from your lock screen.")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(widgetSecondaryOnDark)
                .lineLimit(3)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Row Tracker is a premium feature. Open the app to upgrade.")
    }

    private var accessoryInlineView: some View {
        Group {
            if isEmpty {
                Text("No active project")
                    .accessibilityLabel("No active project")
            } else if let title = entry.patternTitle, !title.isEmpty {
                Text("\(title) · Row \(entry.currentRow)\(entry.totalRows.map { " / \($0)" } ?? "")")
                    .accessibilityLabel("\(title), row \(entry.currentRow)\(entry.totalRows.map { " of \($0)" } ?? "")")
            } else {
                Text("Row \(entry.currentRow)\(entry.totalRows.map { " / \($0)" } ?? "")")
                    .accessibilityLabel(rowLabelAccessibility)
            }
        }
    }

    private var accessoryRectangularView: some View {
        Group {
            if isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("No active project")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(widgetTextOnDark)
                    Text("Open app to set one")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(widgetSecondaryOnDark)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("No active project. Open app to set one.")
            } else {
                // Compact two-line layout; keep content inset to avoid clipping and clock overlap
                VStack(alignment: .leading, spacing: 3) {
                    // Line 1: current row (prominent) + label + project name so key info survives overlap
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(entry.currentRow)")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(widgetTextOnDark)
                            .accessibilityLabel(rowLabelAccessibility)
                            .accessibilityHint("Current row count for this pattern")
                        Text(rowLabel)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(widgetSecondaryOnDark)
                        if let title = entry.patternTitle, !title.isEmpty {
                            Text("·")
                                .font(.system(size: 10))
                                .foregroundStyle(widgetSecondaryOnDark)
                            Text(title)
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(widgetSecondaryOnDark)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        Spacer(minLength: 0)
                    }

                    // Line 2: short label + buttons + progress ring
                    HStack(alignment: .center, spacing: 6) {
                        Text("Row Tracker")
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundStyle(widgetSecondaryOnDark)
                        if #available(iOS 17.0, *) {
                            Button(intent: DecrementRowIntent()) {
                                Text("-1")
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundStyle(widgetTextOnDark)
                                    .frame(width: 26, height: 20)
                                    .background(widgetTextOnDark.opacity(0.25))
                                    .clipShape(RoundedRectangle(cornerRadius: 5))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Subtract row")
                            Button(intent: IncrementRowIntent()) {
                                Text("+1")
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundStyle(widgetTextOnDark)
                                    .frame(width: 26, height: 20)
                                    .background(widgetSoftCoral)
                                    .clipShape(RoundedRectangle(cornerRadius: 5))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Add row")
                        }
                        if let total = entry.totalRows, total > 0 {
                            Gauge(value: Double(entry.currentRow), in: 0...Double(total)) {}
                                .gaugeStyle(.accessoryCircularCapacity)
                                .tint(widgetSoftCoral)
                                .scaleEffect(0.78)
                        }
                    }

                    if let secondaryTitle = entry.secondaryTitle,
                       let secondaryCurrent = entry.secondaryCurrent,
                       let secondaryResetAfter = entry.secondaryResetAfter,
                       secondaryResetAfter > 0 {
                        Text("\(secondaryTitle): \(secondaryCurrent)/\(secondaryResetAfter)")
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundStyle(widgetSecondaryOnDark)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(entry.patternId.flatMap { URL(string: "patternvault://pattern/\($0.uuidString)") })
    }

    private var rowLabel: String {
        if let total = entry.totalRows, total > 0 {
            return "Row \(entry.currentRow) / \(total)"
        }
        return "Row \(entry.currentRow)"
    }

    private var rowLabelAccessibility: String {
        if let total = entry.totalRows, total > 0 {
            return "Row \(entry.currentRow) of \(total)"
        }
        return "Row \(entry.currentRow)"
    }
}

@available(iOS 17.0, *)
struct IncrementRowIntent: AppIntent {
    static var title: LocalizedStringResource { "Add row" }
    static var description: IntentDescription { "Increment the row counter by one." }

    func perform() async throws -> some IntentResult {
        let suite = UserDefaults(suiteName: suiteName)
        let current = (suite?.object(forKey: keyWidgetRowCurrent) as? Int) ?? 0
        let total = suite?.object(forKey: keyWidgetRowTotal) as? Int
        var next = current + 1
        if let t = total, t > 0 { next = min(next, t) }
        suite?.set(next, forKey: keyWidgetRowCurrent)
        suite?.synchronize()
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

@available(iOS 17.0, *)
struct DecrementRowIntent: AppIntent {
    static var title: LocalizedStringResource { "Subtract row" }
    static var description: IntentDescription { "Decrement the row counter by one." }

    func perform() async throws -> some IntentResult {
        let suite = UserDefaults(suiteName: suiteName)
        let current = (suite?.object(forKey: keyWidgetRowCurrent) as? Int) ?? 0
        let next = max(0, current - 1)
        suite?.set(next, forKey: keyWidgetRowCurrent)
        suite?.synchronize()
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

struct RowTrackerWidget: Widget {
    let kind = "RowTrackerWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RowTrackerProvider()) { entry in
            RowTrackerWidgetView(entry: entry)
                .containerBackground(widgetBackground, for: .widget)
        }
        .configurationDisplayName("Row Tracker")
        .description("Track your current row without unlocking. Set row progress in a pattern to show it here.")
        .supportedFamilies([.accessoryRectangular, .accessoryInline])
    }
}

#Preview("Row Tracker", as: .accessoryRectangular) {
    RowTrackerWidget()
} timeline: {
    RowTrackerEntry(
        date: .now,
        patternId: nil,
        patternTitle: "Fluffy Sweater",
        currentRow: 38,
        totalRows: 120,
        secondaryTitle: "Lace",
        secondaryCurrent: 5,
        secondaryResetAfter: 12,
        isPremium: true
    )
}
