import SwiftUI

struct MessageBubbleView: View {
    let message: MessageRecord
    var isFirstInGroup: Bool = true
    var isLastInGroup: Bool = true
    var onRetry: (() -> Void)?
    var onBranch: (() -> Void)?
    var onDelete: (() -> Void)?
    var onMemoryTap: ((String) -> Void)?
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var settings = UserSettings.shared

    // --bubble-user: teal dark / violet light (matches web globals.css).
    // AiVery theme: brand blue to match the icon gradient.
    private var bubbleUserColor: Color {
        if settings.isAivery { return .aiveryBlue }
        return colorScheme == .dark ? .aiveryTeal : .aiveryViolet
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

                // Agent action notes ("Stored a memory about …") + saved-memory chips
                if !message.isUser {
                    let notes = AgentNotes.extract(from: message.content).notes
                    let refs = MemoryRefs.extract(from: message.content).refs
                    if !notes.isEmpty || !refs.isEmpty {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(notes, id: \.self) { AgentNoteChip(text: $0) }
                            ForEach(refs) { ref in
                                MemorySavedChip(memory: ref) { onMemoryTap?(ref.id) }
                            }
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
                VStack(alignment: .trailing, spacing: 5) {
                    if let img = message.localImage {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: 240, maxHeight: 260)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(.white.opacity(0.18), lineWidth: 0.5)
                            )
                            .shadow(color: .black.opacity(0.2), radius: 5, x: 0, y: 2)
                    }
                    if !message.content.isEmpty {
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
                    }
                }
            } else {
                AgentProseView(text: prose)
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
        let clean = MemoryRefs.extract(from: AgentNotes.extract(from: content).content).content
        let thinking = ThinkText.split(clean).thinking
        return thinking.isEmpty ? nil : thinking
    }

    private func strippedContent(_ content: String) -> String {
        ThinkText.split(MemoryRefs.extract(from: AgentNotes.extract(from: content).content).content).response
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

/// Tappable "Memory saved" chip with a type-colored dot — opens the memory detail
/// sheet. Mirrors the web client's MemorySavedChip (aivery-think/.../chat/chat-history.tsx).
struct MemorySavedChip: View {
    let memory: WrittenMemoryRef
    var onTap: (() -> Void)?

    // Same palette as TypeBadge (MemoryRetrievalSheetView).
    private var dotColor: Color {
        switch memory.type.lowercased() {
        case "semantic":   return .blue
        case "preference": return .purple
        case "episodic":   return .orange
        case "identity":   return .green
        case "system":     return .gray
        default:           return .secondary
        }
    }
    private var snippet: String {
        memory.content.count > 60
            ? String(memory.content.prefix(60)).trimmingCharacters(in: .whitespaces) + "…"
            : memory.content
    }

    var body: some View {
        Button { onTap?() } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(dotColor.opacity(0.75))
                    .frame(width: 7, height: 7)
                (Text("Memory saved").foregroundStyle(.secondary)
                    + Text(snippet.isEmpty ? "" : " · \(snippet)").foregroundStyle(.tertiary))
                    .font(.caption2)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Streaming assistant bubble — same glass treatment as completed assistant bubbles
struct StreamingBubbleView: View {
    let text: String
    let thinking: String
    var notes: [String] = []
    var memories: [WrittenMemoryRef] = []
    // Text is done; server is finishing memory writes. Caret off, hint row on.
    var memoryPhase: Bool = false
    var onMemoryTap: ((String) -> Void)?

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
                    AgentProseView(text: prose, streaming: !memoryPhase)
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

                // Saved-memory chips, appearing live as writes land
                if !memories.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(memories) { ref in
                            MemorySavedChip(memory: ref) { onMemoryTap?(ref.id) }
                        }
                    }
                    .padding(.top, 1)
                    .transition(.opacity)
                }

                // Text is complete; memory writes still draining server-side
                if memoryPhase {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text("saving memories…")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 2)
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
