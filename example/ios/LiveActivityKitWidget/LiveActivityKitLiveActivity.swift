import ActivityKit
import SwiftUI
import WidgetKit

/// The single `ActivityConfiguration` behind every activity this package
/// starts. It never hard-codes a use case: each region simply renders whichever
/// component tree Dart put in the content state.
@available(iOS 16.1, *)
struct LiveActivityKitLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiveActivityKitAttributes.self) { context in
            // Lock Screen / banner / StandBy.
            LockScreenView(layout: LALayout.decode(context.state.payload))
        } dynamicIsland: { context in
            let layout = LALayout.decode(context.state.payload)

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    LARegionView(layout: layout, region: .expandedLeading)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    LARegionView(layout: layout, region: .expandedTrailing)
                }
                DynamicIslandExpandedRegion(.center) {
                    LARegionView(layout: layout, region: .expandedCenter)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    LARegionView(layout: layout, region: .expandedBottom)
                }
            } compactLeading: {
                LARegionView(layout: layout, region: .compactLeading)
            } compactTrailing: {
                LARegionView(layout: layout, region: .compactTrailing)
            } minimal: {
                LARegionView(layout: layout, region: .minimal)
            }
            .widgetURL(layout.deepLink)
            .keylineTint(layout.theme.tint)
        }
    }
}

/// Lock-screen presentation: the region tree plus the layout's background
/// treatment.
@available(iOS 16.1, *)
private struct LockScreenView: View {
    let layout: LALayout

    var body: some View {
        LARegionView(layout: layout, region: .lockScreen)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(BackgroundModifier(theme: layout.theme))
            .widgetURL(layout.deepLink)
    }
}

/// `activityBackgroundTint` only exists on iOS 16.2+, and passing `nil` there
/// is what preserves the default system material — so the modifier is applied
/// conditionally rather than with a fallback colour.
@available(iOS 16.1, *)
private struct BackgroundModifier: ViewModifier {
    let theme: LALayout.Theme

    func body(content: Content) -> some View {
        if #available(iOS 16.2, *) {
            if let gradient = theme.gradient {
                content
                    .background(
                        LinearGradient(colors: gradient,
                                       startPoint: .topLeading,
                                       endPoint: .bottomTrailing)
                    )
                    .activityBackgroundTint(nil)
                    .activitySystemActionForegroundColor(theme.foreground)
            } else {
                content
                    .activityBackgroundTint(theme.background)
                    .activitySystemActionForegroundColor(theme.foreground)
            }
        } else {
            content
        }
    }
}

// MARK: - Previews

#if DEBUG
@available(iOS 17.0, *)
private extension LiveActivityKitAttributes {
    static var preview: LiveActivityKitAttributes {
        LiveActivityKitAttributes(id: "preview")
    }
}

@available(iOS 17.0, *)
private extension LiveActivityKitAttributes.ContentState {
    /// Mirrors what `LA.column([...])` produces on the Dart side, so the Xcode
    /// canvas exercises the same decoder the device does.
    static var sample: LiveActivityKitAttributes.ContentState {
        let payload = """
        {"regions":{
          "lockScreen":{"type":"column","spacing":6,"children":[
            {"type":"row","children":[
              {"type":"text","value":"Next meal","weight":"bold"},
              {"type":"spacer"},
              {"type":"text","value":"LIVE","size":11,"color":"#ff3b30"}]},
            {"type":"text","value":"Lunch — 1:00 PM","size":20},
            {"type":"progress","value":0.65,"tint":"#34c759"}]},
          "compactTrailing":{"type":"text","value":"🍱 1:00"},
          "minimal":{"type":"text","value":"🍱"}
        }}
        """
        return LiveActivityKitAttributes.ContentState(payload: payload, revision: 1)
    }
}

@available(iOS 17.0, *)
#Preview("Lock Screen", as: .content, using: LiveActivityKitAttributes.preview) {
    LiveActivityKitLiveActivity()
} contentStates: {
    LiveActivityKitAttributes.ContentState.sample
}

@available(iOS 17.0, *)
#Preview("Island — expanded", as: .dynamicIsland(.expanded), using: LiveActivityKitAttributes.preview) {
    LiveActivityKitLiveActivity()
} contentStates: {
    LiveActivityKitAttributes.ContentState.sample
}
#endif
