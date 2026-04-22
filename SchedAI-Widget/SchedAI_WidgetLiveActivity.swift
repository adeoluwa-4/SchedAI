//
//  SchedAI_WidgetLiveActivity.swift
//  SchedAI-Widget
//
//  Created by Adeoluwa Adekoya on 4/17/26.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct SchedAI_WidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct SchedAI_WidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SchedAI_WidgetAttributes.self) { context in
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

extension SchedAI_WidgetAttributes {
    fileprivate static var preview: SchedAI_WidgetAttributes {
        SchedAI_WidgetAttributes(name: "World")
    }
}

extension SchedAI_WidgetAttributes.ContentState {
    fileprivate static var smiley: SchedAI_WidgetAttributes.ContentState {
        SchedAI_WidgetAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: SchedAI_WidgetAttributes.ContentState {
         SchedAI_WidgetAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: SchedAI_WidgetAttributes.preview) {
   SchedAI_WidgetLiveActivity()
} contentStates: {
    SchedAI_WidgetAttributes.ContentState.smiley
    SchedAI_WidgetAttributes.ContentState.starEyes
}
