import SwiftUI

struct MessageBubbleView: View {
    let message: MessageRecord
    var isStreaming: Bool = false
    var isFirstInGroup: Bool = true
    var isLastInGroup: Bool = true
    var onRetry: (() -> Void)?
    var onBranch: (() -> Void)?
    var onDelete: (() -> Void)?
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var settings = UserSettings.shared

    // --bubble-user: #4CC9A7 dark / #B9A7FF light  (matches web globals.css)
    // AiVery theme: blue (#3B82F2) to match the icon gradient.
    private var bubbleUserColor: Color {
        if settings.isAivery { return Color(red: 59/255, green: 130/255, blue: 242/255) }   // #3B82F2
        return colorScheme == .dark
            ? Color(red: 76/255,  green: 201/255, blue: 167/255)   // #4CC9A7
            : Color(red: 185/255, green: 167/255, blue: 255/255)    // #B9A7FF
    }
    // --bubble-user-fg: #0A0A0C near-black; white on the AiVery blue bubble.
    private var bubbleUserFg: Color {
        settings.isAivery ? .white : Color(red: 10/255, green: 10/255, blue: 12/255)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            if message.isUser { Spacer(minLength: 56) }

            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                // Thinking disclosure (assistant only, first bubble of a run)
                if !message.isUser, isFirstInGroup, settings.showThinking, let thinking = extractThinking(from: message.content), !thinking.isEmpty {
                    DisclosureGroup {
                        Text(thinking)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 4)
                    } label: {
                        HStack(spacing: 6) {
                            ThinkingBrainIcon(isActive: false)
                            Text("Thought")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                }

                // Agent actions (note / remember) — between the thoughts and the reply bubble.
                if !message.isUser, !agentActions.isEmpty {
                    AgentActionsBlock(actions: agentActions)
                }

                bubble

                // Agent action notes ("Stored a memory about …")
                if !message.isUser {
                    let notes = AgentNotes.extract(from: message.content).notes
                    if !notes.isEmpty {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(notes, id: \.self) { AgentNoteChip(text: $0) }
                        }
                        .padding(.top, 1)
                    }
                }
            }

            if !message.isUser { Spacer(minLength: 56) }
        }
        .padding(.horizontal, 12)
        // Tight gap within a sender run, larger gap when the sender changes.
        .padding(.top, isFirstInGroup ? 8 : 2)
        .padding(.bottom, isLastInGroup ? 2 : 0)
    }

    @ViewBuilder
    private var bubble: some View {
        Group {
            if message.isUser {
                Text(message.content)
                    .foregroundStyle(bubbleUserFg)
                    .font(.body)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 9)
                    .background(bubbleUserColor, in: ChatBubbleShape(isUser: true, hasTail: isLastInGroup))
                    .overlay {
                        if settings.isAivery {
                            ChatBubbleShape(isUser: true, hasTail: isLastInGroup)
                                .stroke(Color.white.opacity(0.4), lineWidth: 1)
                        }
                    }
                    .shadow(color: settings.isAivery ? .black.opacity(0.28) : bubbleUserColor.opacity(0.28),
                            radius: settings.isAivery ? 6 : 8, x: 0, y: settings.isAivery ? 2 : 3)
            } else {
                AgentProseView(text: prose, streaming: isStreaming)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.thinMaterial, in: ChatBubbleShape(isUser: false, hasTail: isLastInGroup))
            }
        }
        .contextMenu { messageActions }
    }

    // Native long-press actions
    @ViewBuilder
    private var messageActions: some View {
        Button {
            UIPasteboard.general.string = message.isUser ? message.content : strippedContent(message.content)
        } label: { Label("Copy", systemImage: "doc.on.doc") }

        if let onRetry {
            Button { onRetry() } label: {
                Label(message.isUser ? "Retry" : "Regenerate", systemImage: "arrow.clockwise")
            }
        }
        if let onBranch {
            Button { onBranch() } label: { Label("Branch from here", systemImage: "arrow.triangle.branch") }
        }
        if let onDelete {
            Button(role: .destructive) { onDelete() } label: { Label("Delete", systemImage: "trash") }
        }
    }

    private func extractThinking(from content: String) -> String? {
        let clean = AgentNotes.extract(from: content).content
        let thinking = ThinkText.split(clean).thinking
        return thinking.isEmpty ? nil : thinking
    }

    private func strippedContent(_ content: String) -> String {
        ThinkText.split(AgentNotes.extract(from: content).content).response
    }

    // Agent actions (note/remember) shown above the bubble; prose goes inside it.
    private var agentActions: [AgentAction] {
        message.isUser ? [] : AgentActions.actions(from: strippedContent(message.content))
    }
    private var prose: String {
        AgentActions.plainText(from: strippedContent(message.content))
    }
}

/// Small lightbulb chip surfacing an agent action ("Stored a memory about …").
/// Mirrors the web client's AgentNoteChip (aivery-think/.../chat/chat-history.tsx).
struct AgentNoteChip: View {
    let text: String
    private var display: String { text.count > 120 ? String(text.prefix(120)).trimmingCharacters(in: .whitespaces) + "…" : text }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 9))
                .foregroundStyle(Color.accentColor.opacity(0.6))
            Text(display)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Streaming assistant bubble — same glass treatment as completed assistant bubbles
struct StreamingBubbleView: View {
    let text: String
    let thinking: String
    var notes: [String] = []

    var body: some View {
        // Some models stream reasoning inline as <think>…</think> within the chunk
        // text, others emit it on a separate channel. Split live so the reply bubble
        // never shows raw tags, and the disclosure holds whichever reasoning we have.
        let parts = ThinkText.split(text)
        let displayThinking = thinking.isEmpty ? parts.thinking : thinking
        let actions = AgentActions.actions(from: parts.response)
        let prose = AgentActions.plainText(from: parts.response)

        // Mirror MessageBubbleView's layout: a leading content column with a trailing
        // spacer so the thinking block is bubble-width (not full width) and sits the
        // same distance below the user bubble.
        HStack(alignment: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                if !displayThinking.isEmpty {
                    DisclosureGroup {
                        Text(displayThinking)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 4)
                    } label: {
                        HStack(spacing: 6) {
                            ThinkingBrainIcon(isActive: true)
                            Text("Thinking")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                }

                // Agent actions between the thoughts and the reply bubble.
                if !actions.isEmpty {
                    AgentActionsBlock(actions: actions)
                }

                if !prose.isEmpty {
                    AgentProseView(text: prose, streaming: true)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.thinMaterial, in: ChatBubbleShape(isUser: false, hasTail: true))
                }

                // Live agent action notes ("Stored a memory about …")
                if !notes.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(notes, id: \.self) { AgentNoteChip(text: $0) }
                    }
                    .padding(.top, 1)
                    .transition(.opacity)
                }
            }
            Spacer(minLength: 56)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 2)
    }
}

// One bubble shape for both sides. The "tail" pinches the bottom corner on the
// sender's side — but only on the last bubble of a run (iMessage grouping).
struct ChatBubbleShape: Shape {
    let isUser: Bool
    let hasTail: Bool
    private let r: CGFloat = 20
    private let pinch: CGFloat = 6

    func path(in rect: CGRect) -> Path {
        UnevenRoundedRectangle(
            topLeadingRadius:     r,
            bottomLeadingRadius:  (!isUser && hasTail) ? pinch : r,
            bottomTrailingRadius: (isUser && hasTail) ? pinch : r,
            topTrailingRadius:    r
        ).path(in: rect)
    }
}
