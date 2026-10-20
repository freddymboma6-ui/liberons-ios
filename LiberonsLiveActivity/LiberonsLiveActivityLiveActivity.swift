//
//  LiberonsLiveActivityLiveActivity.swift
//  LiberonsLiveActivity
//
//  Created by macbook on 2026-10-20.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct LiberonsLiveActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct LiberonsLiveActivityLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiberonsLiveActivityAttributes.self) { context in
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

extension LiberonsLiveActivityAttributes {
    fileprivate static var preview: LiberonsLiveActivityAttributes {
        LiberonsLiveActivityAttributes(name: "World")
    }
}

extension LiberonsLiveActivityAttributes.ContentState {
    fileprivate static var smiley: LiberonsLiveActivityAttributes.ContentState {
        LiberonsLiveActivityAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: LiberonsLiveActivityAttributes.ContentState {
         LiberonsLiveActivityAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: LiberonsLiveActivityAttributes.preview) {
   LiberonsLiveActivityLiveActivity()
} contentStates: {
    LiberonsLiveActivityAttributes.ContentState.smiley
    LiberonsLiveActivityAttributes.ContentState.starEyes
}
