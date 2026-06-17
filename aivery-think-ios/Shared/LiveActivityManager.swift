import ActivityKit
import Foundation

/// Drives the "Thinking" Live Activity (Dynamic Island + lock screen) over a single
/// agent turn. No-ops gracefully if Live Activities are disabled or unsupported, and
/// if no widget extension is installed yet (Activity.request simply throws → ignored).
@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    private var activity: Activity<ThinkingAttributes>?
    private let stale: TimeInterval = 120   // auto-stale if a turn hangs

    func start(agentId: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        end()   // clear any leftover from a previous turn
        let attributes = ThinkingAttributes(agentId: agentId, startedAt: Date())
        let state = ThinkingAttributes.ContentState(phase: "Thinking", detail: "")
        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(stale))
        activity = try? Activity.request(attributes: attributes, content: content)
    }

    func update(phase: String, detail: String = "") {
        guard let activity else { return }
        let content = ActivityContent(
            state: ThinkingAttributes.ContentState(phase: phase, detail: detail),
            staleDate: Date().addingTimeInterval(stale)
        )
        Task { await activity.update(content) }
    }

    func end() {
        guard let activity else { return }
        self.activity = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }
}
