//
//  PatternVaultWidgetLiveActivity.swift
//  PatternVaultWidget
//
//  Created by Angela M on 3/9/26.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct PatternVaultWidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var patternId: String
        var patternTitle: String
        var rowCurrent: Int
        var rowTotal: Int?
        var secondaryTitle: String?
        var secondaryCurrent: Int?
        var secondaryResetAfter: Int?
    }

    var name: String
}

struct PatternVaultWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PatternVaultWidgetAttributes.self) { context in
            VStack(alignment: .leading, spacing: 8) {
                Text(context.state.patternTitle)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .lineLimit(1)

                HStack(spacing: 10) {
                    Text("Row \(context.state.rowCurrent)\(context.state.rowTotal.map { "/\($0)" } ?? "")")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))

                    if let secondaryTitle = context.state.secondaryTitle,
                       let secondaryCurrent = context.state.secondaryCurrent,
                       let secondaryResetAfter = context.state.secondaryResetAfter,
                       secondaryResetAfter > 0 {
                        Text("\(secondaryTitle) \(secondaryCurrent)/\(secondaryResetAfter)")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.vertical, 6)
            .activityBackgroundTint(Color(red: 0.22, green: 0.10, blue: 0.18))
            .activitySystemActionForegroundColor(.white)

        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text("Row")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.state.rowCurrent)\(context.state.rowTotal.map { "/\($0)" } ?? "")")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(context.state.patternTitle)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                        if let secondaryTitle = context.state.secondaryTitle,
                           let secondaryCurrent = context.state.secondaryCurrent,
                           let secondaryResetAfter = context.state.secondaryResetAfter,
                           secondaryResetAfter > 0 {
                            Text("\(secondaryTitle): \(secondaryCurrent)/\(secondaryResetAfter)")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } compactLeading: {
                Text("R")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            } compactTrailing: {
                Text("\(context.state.rowCurrent)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
            } minimal: {
                Text("\(context.state.rowCurrent)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
            }
            .widgetURL(URL(string: "patternvault://row-tracker"))
            .keylineTint(Color(red: 0.91, green: 0.514, blue: 0.42))
        }
    }
}

extension PatternVaultWidgetAttributes {
    fileprivate static var preview: PatternVaultWidgetAttributes {
        PatternVaultWidgetAttributes(name: "Pattern Vault")
    }
}

extension PatternVaultWidgetAttributes.ContentState {
    fileprivate static var smiley: PatternVaultWidgetAttributes.ContentState {
        PatternVaultWidgetAttributes.ContentState(
            patternId: UUID().uuidString,
            patternTitle: "Skull Sampler Socks",
            rowCurrent: 24,
            rowTotal: 36,
            secondaryTitle: "Lace",
            secondaryCurrent: 5,
            secondaryResetAfter: 12
        )
     }
     
     fileprivate static var starEyes: PatternVaultWidgetAttributes.ContentState {
         PatternVaultWidgetAttributes.ContentState(
            patternId: UUID().uuidString,
            patternTitle: "Skull Sampler Socks",
            rowCurrent: 25,
            rowTotal: 36,
            secondaryTitle: "Lace",
            secondaryCurrent: 6,
            secondaryResetAfter: 12
        )
     }
}

#Preview("Notification", as: .content, using: PatternVaultWidgetAttributes.preview) {
   PatternVaultWidgetLiveActivity()
} contentStates: {
    PatternVaultWidgetAttributes.ContentState.smiley
    PatternVaultWidgetAttributes.ContentState.starEyes
}
