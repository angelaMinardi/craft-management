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
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct PatternVaultWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PatternVaultWidgetAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension PatternVaultWidgetAttributes {
    fileprivate static var preview: PatternVaultWidgetAttributes {
        PatternVaultWidgetAttributes(name: "World")
    }
}

extension PatternVaultWidgetAttributes.ContentState {
    fileprivate static var smiley: PatternVaultWidgetAttributes.ContentState {
        PatternVaultWidgetAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: PatternVaultWidgetAttributes.ContentState {
         PatternVaultWidgetAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: PatternVaultWidgetAttributes.preview) {
   PatternVaultWidgetLiveActivity()
} contentStates: {
    PatternVaultWidgetAttributes.ContentState.smiley
    PatternVaultWidgetAttributes.ContentState.starEyes
}
