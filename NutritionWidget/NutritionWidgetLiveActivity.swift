//
//  NutritionWidgetLiveActivity.swift
//  NutritionWidget
//
//  Created by Ishwar Partap Singh on 18/12/25.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct NutritionWidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct NutritionWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NutritionWidgetAttributes.self) { context in
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

extension NutritionWidgetAttributes {
    fileprivate static var preview: NutritionWidgetAttributes {
        NutritionWidgetAttributes(name: "World")
    }
}

extension NutritionWidgetAttributes.ContentState {
    fileprivate static var smiley: NutritionWidgetAttributes.ContentState {
        NutritionWidgetAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: NutritionWidgetAttributes.ContentState {
         NutritionWidgetAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: NutritionWidgetAttributes.preview) {
   NutritionWidgetLiveActivity()
} contentStates: {
    NutritionWidgetAttributes.ContentState.smiley
    NutritionWidgetAttributes.ContentState.starEyes
}
