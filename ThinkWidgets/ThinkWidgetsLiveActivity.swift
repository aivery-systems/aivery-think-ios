import ActivityKit
import WidgetKit
import SwiftUI

// Aivery brand
private let aiveryTeal = Color(red: 76/255, green: 201/255, blue: 167/255)    // #4CC9A7
private let aiveryViolet = Color(red: 185/255, green: 167/255, blue: 255/255) // #B9A7FF

private func phaseIcon(_ phase: String) -> String {
    switch phase {
    case "Recalling":  return "sparkles"
    case "Responding": return "ellipsis.bubble.fill"
    default:           return "brain"
    }
}

private func statusLine(_ phase: String, detail: String) -> String {
    if !detail.isEmpty { return detail }
    switch phase {
    case "Recalling":  return "Searching memories…"
    case "Responding": return "Writing a reply…"
    default:           return "Thinking…"
    }
}

struct ThinkWidgetsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ThinkingAttributes.self) { context in
            // Lock screen / banner
            LockScreenThinkingView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.35))
                .activitySystemActionForegroundColor(aiveryTeal)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text("Aivery").font(.caption2).foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: phaseIcon(context.state.phase))
                            .foregroundStyle(aiveryTeal)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.phase)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(aiveryTeal)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small).tint(aiveryViolet)
                        Text(statusLine(context.state.phase, detail: context.state.detail))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(context.attributes.startedAt, style: .timer)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: 42)
                    }
                }
            } compactLeading: {
                Image(systemName: phaseIcon(context.state.phase))
                    .foregroundStyle(aiveryTeal)
            } compactTrailing: {
                ProgressView().controlSize(.mini).tint(aiveryViolet)
            } minimal: {
                Image(systemName: "brain").foregroundStyle(aiveryTeal)
            }
            .keylineTint(aiveryTeal)
        }
    }
}

private struct LockScreenThinkingView: View {
    let context: ActivityViewContext<ThinkingAttributes>

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(aiveryTeal.opacity(0.18)).frame(width: 40, height: 40)
                Image(systemName: phaseIcon(context.state.phase))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(aiveryTeal)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Aivery is \(context.state.phase.lowercased())")
                    .font(.subheadline.weight(.semibold))
                Text(statusLine(context.state.phase, detail: context.state.detail))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(context.attributes.startedAt, style: .timer)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(maxWidth: 48)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

#Preview("Lock Screen", as: .content, using: ThinkingAttributes.preview) {
    ThinkWidgetsLiveActivity()
} contentStates: {
    ThinkingAttributes.ContentState(phase: "Thinking", detail: "")
    ThinkingAttributes.ContentState(phase: "Recalling", detail: "3 memories")
    ThinkingAttributes.ContentState(phase: "Responding", detail: "")
}

extension ThinkingAttributes {
    fileprivate static var preview: ThinkingAttributes {
        ThinkingAttributes(agentId: "default", startedAt: Date())
    }
}
