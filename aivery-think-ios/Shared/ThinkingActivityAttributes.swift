import ActivityKit
import Foundation

/// Shared between the app (which starts/updates/ends the activity) and the widget
/// extension (which renders it in the Dynamic Island + lock screen). This exact type
/// must be a member of BOTH targets — add it to the widget target's membership.
struct ThinkingAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// "Thinking" | "Recalling" | "Responding"
        var phase: String
        /// Short detail, e.g. "3 memories" — may be empty.
        var detail: String
    }

    var agentId: String
    var startedAt: Date
}
