import SwiftUI

/// A message plus everything the list needs to lay it out, precomputed by
/// ChatViewModel whenever `messages` changes (never during a render).
struct MessageRow: Identifiable {
    let message: MessageRecord
    /// Non-nil → draw a timestamp separator above this message.
    let separatorDate: Date?
    let isFirstInGroup: Bool
    let isLastInGroup: Bool
    var id: String { message.id }
}

// UIScrollView KVO scroll tracking (iOS 13+ compatible) — replaces
// onScrollGeometryChange, which requires iOS 18. SwiftUI's GeometryReader +
// PreferenceKey combo (the usual pre-iOS-18 recipe) only fires once here and never
// updates on subsequent layout passes, so it silently never shows the chevron —
// observing the underlying UIScrollView's contentOffset/contentSize directly via
// KVO is the reliable, long-established fallback for this exact problem.
private final class ScrollOffsetCoordinator: NSObject {
    var onChange: ((_ offset: CGFloat, _ contentHeight: CGFloat, _ viewportHeight: CGFloat) -> Void)?
    private weak var scrollView: UIScrollView?
    private var observations: [NSKeyValueObservation] = []

    func attach(to scrollView: UIScrollView) {
        guard self.scrollView !== scrollView else { return }
        self.scrollView = scrollView
        observations = [
            scrollView.observe(\.contentOffset, options: [.initial, .new]) { [weak self] sv, _ in self?.report(sv) },
            scrollView.observe(\.contentSize, options: [.new]) { [weak self] sv, _ in self?.report(sv) },
            scrollView.observe(\.bounds, options: [.new]) { [weak self] sv, _ in self?.report(sv) },
        ]
    }

    var isAttached: Bool { scrollView != nil }

    private func report(_ sv: UIScrollView) {
        onChange?(sv.contentOffset.y, sv.contentSize.height, sv.bounds.height)
    }
}

private struct ScrollOffsetReader: UIViewRepresentable {
    let onChange: (CGFloat, CGFloat, CGFloat) -> Void

    func makeCoordinator() -> ScrollOffsetCoordinator {
        let coordinator = ScrollOffsetCoordinator()
        coordinator.onChange = onChange
        return coordinator
    }

    func makeUIView(context: Context) -> UIView {
        UIView(frame: .zero)
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onChange = onChange
        // Walk the responder chain once; after attaching, updates are free.
        guard !context.coordinator.isAttached else { return }
        DispatchQueue.main.async {
            var responder: UIResponder? = uiView
            while let r = responder, !(r is UIScrollView) {
                responder = r.next
            }
            if let scrollView = responder as? UIScrollView {
                context.coordinator.attach(to: scrollView)
            }
        }
    }
}

/// One list element per message (timestamp folded in), so LazyVStack can stay lazy —
/// a ForEach closure that yields a variable number of views forces SwiftUI to evaluate
/// every element to resolve identities.
private struct MessageRowView: View, Equatable {
    let row: MessageRow
    let bubble: MessageBubbleView

    static func == (lhs: MessageRowView, rhs: MessageRowView) -> Bool {
        lhs.row.separatorDate == rhs.row.separatorDate && lhs.bubble == rhs.bubble
    }

    var body: some View {
        VStack(spacing: 0) {
            if let d = row.separatorDate {
                Text(ChatDate.separatorLabel(d))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 14)
                    .padding(.bottom, 2)
            }
            bubble
        }
    }
}

struct MessageListView: View {
    @ObservedObject var vm: ChatViewModel
    @ObservedObject private var settings = UserSettings.shared
    @State private var showScrollToBottom = false
    @State private var lastStreamScroll = Date.distantPast

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(vm.rows) { row in
                        let msg = row.message
                        MessageRowView(
                            row: row,
                            bubble: MessageBubbleView(
                                message: msg,
                                isFirstInGroup: row.isFirstInGroup,
                                isLastInGroup: row.isLastInGroup,
                                onRetry: { Task { if msg.isUser { await vm.retryUser(msg) } else { await vm.regenerate(msg) } } },
                                onBranch: msg.isUser ? nil : { Task { await vm.branch(from: msg) } },
                                onDelete: { Task { await vm.delete(msg) } },
                                onMemoryTap: { id in Task { await vm.openMemory(id: id) } },
                                queuedJobs: msg.isUser ? [] : (vm.jobsByMessageId[msg.id] ?? [])
                            )
                        )
                        .equatable()
                        .id(msg.id)
                        .transition(.scale(scale: 0.96, anchor: msg.isUser ? .bottomTrailing : .bottomLeading).combined(with: .opacity))
                    }

                    // Reply to a turn the user left mid-generation, still finishing server-side
                    if vm.awaitingReply && !vm.isStreaming {
                        ThinkingIndicatorView()
                            .id("awaiting-reply")
                    }

                    // Live streaming bubble
                    if vm.isStreaming {
                        if vm.streamingText.isEmpty && vm.streamingThinking.isEmpty && vm.streamingNotes.isEmpty && vm.streamingMemories.isEmpty {
                            ThinkingIndicatorView()
                                .id("thinking-indicator")
                        } else {
                            StreamingBubbleView(
                                text: vm.streamingText,
                                thinking: vm.streamingThinking,
                                notes: vm.streamingNotes,
                                memories: vm.streamingMemories,
                                memoryPhase: vm.memoryPhase,
                                onMemoryTap: { id in Task { await vm.openMemory(id: id) } }
                            )
                            .id("streaming-bubble")
                        }
                    }

                    // Bottom spacer so content clears the input bar
                    Color.clear.frame(height: 80).id("bottom-anchor")
                }
                .padding(.top, 8)
                .animation(.spring(response: 0.34, dampingFraction: 0.82), value: vm.messages.count)
                .background(
                    // Show the jump-to-bottom chevron when scrolled up from the latest message
                    ScrollOffsetReader { offset, contentHeight, viewportHeight in
                        let maxOffset = max(0, contentHeight - viewportHeight)
                        let away = (maxOffset - offset) > 140
                        if away != showScrollToBottom {
                            withAnimation(.easeInOut(duration: 0.2)) { showScrollToBottom = away }
                        }
                    }
                )
            }
            .onChange(of: vm.streamingText) {
                // Chunks already arrive coalesced (~20/s); cap follow-scrolling further and
                // skip the animation — animating every update fought the layout pass.
                let now = Date()
                guard now.timeIntervalSince(lastStreamScroll) > 0.15 else { return }
                lastStreamScroll = now
                proxy.scrollTo("bottom-anchor", anchor: .bottom)
            }
            .onChange(of: vm.messages.count) {
                withAnimation {
                    proxy.scrollTo("bottom-anchor", anchor: .bottom)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .overlay(alignment: .bottomTrailing) {
                if showScrollToBottom {
                    Button {
                        withAnimation { proxy.scrollTo("bottom-anchor", anchor: .bottom) }
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(settings.isAivery ? AnyShapeStyle(Color.aiveryAccent) : AnyShapeStyle(.primary))
                            .frame(width: 38, height: 38)
                            .glassEffectCompat(interactive: true, in: .circle)
                    }
                    .padding(.trailing, 16)
                    .padding(.bottom, 88)   // float above the input bar
                    .transition(.scale.combined(with: .opacity))
                }
            }
        }
    }
}
