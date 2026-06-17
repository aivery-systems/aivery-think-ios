import SwiftUI
import PhotosUI

private let chatPlaceholders = [
    "What do you want to remember?",
    "Tell me something worth keeping.",
    "Context is intelligence. What's yours?",
    "What happened today?",
    "Where are you? What are you thinking?",
    "Your past is searchable. Add to it.",
    "What would you like your AI to never forget?",
    "Give your AI a past.",
    "Thought, note, memory — drop it here.",
    "Your second brain is listening.",
]

struct ChatView: View {
    @ObservedObject var vm: ChatViewModel
    @Binding var isSignedIn: Bool
    @StateObject private var conn = ConnectionMonitor.shared
    @State private var inputText = ""
    @State private var showScrollToBottom = false
    @FocusState private var inputFocused: Bool
    @State private var placeholderIndex = Int.random(in: 0..<chatPlaceholders.count)
    @State private var placeholderVisible = true
    @State private var photoItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                // Layer 1: surface-recessed background + slow-orbit gradient orbs
                ChatBackgroundView()
                    .onTapGesture {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }

                // Layer 2: plexus particle mesh
                PlexusView(
                    retrievedCount: vm.plexusRetrievedCount,
                    writtenCount: vm.plexusWrittenCount
                )

                // Message list
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(vm.messages.enumerated()), id: \.element.id) { index, msg in
                                if showTimestamp(at: index), let d = msg.date {
                                    Text(ChatDate.separatorLabel(d))
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.top, 14)
                                        .padding(.bottom, 2)
                                }
                                MessageBubbleView(
                                    message: msg,
                                    isFirstInGroup: index == 0 || vm.messages[index - 1].role != msg.role,
                                    isLastInGroup: index == vm.messages.count - 1 || vm.messages[index + 1].role != msg.role,
                                    onRetry: { Task { if msg.isUser { await vm.retryUser(msg) } else { await vm.regenerate(msg) } } },
                                    onBranch: msg.isUser ? nil : { Task { await vm.branch(from: msg) } },
                                    onDelete: { Task { await vm.delete(msg) } }
                                )
                                .id(msg.id)
                                .transition(.scale(scale: 0.96, anchor: msg.isUser ? .bottomTrailing : .bottomLeading).combined(with: .opacity))
                            }

                            // Live streaming bubble
                            if vm.isStreaming {
                                if vm.streamingText.isEmpty && vm.streamingThinking.isEmpty {
                                    ThinkingIndicatorView()
                                        .id("thinking-indicator")
                                } else {
                                    StreamingBubbleView(
                                        text: vm.streamingText,
                                        thinking: vm.streamingThinking
                                    )
                                    .id("streaming-bubble")
                                }
                            }

                            // Bottom spacer so content clears the input bar
                            Color.clear.frame(height: 80).id("bottom-anchor")
                        }
                        .padding(.top, 8)
                        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: vm.messages.count)
                    }
                    .onChange(of: vm.streamingText) {
                        withAnimation(.linear(duration: 0.1)) {
                            proxy.scrollTo("bottom-anchor", anchor: .bottom)
                        }
                    }
                    .onChange(of: vm.messages.count) {
                        withAnimation {
                            proxy.scrollTo("bottom-anchor", anchor: .bottom)
                        }
                    }
                    // Show the jump-to-bottom chevron when scrolled up from the latest message
                    .onScrollGeometryChange(for: Bool.self) { geo in
                        let maxOffset = max(0, geo.contentSize.height - geo.containerSize.height)
                        return (maxOffset - geo.contentOffset.y) > 140
                    } action: { _, away in
                        withAnimation(.easeInOut(duration: 0.2)) { showScrollToBottom = away }
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .overlay(alignment: .bottomTrailing) {
                        if showScrollToBottom {
                            Button {
                                withAnimation { proxy.scrollTo("bottom-anchor", anchor: .bottom) }
                            } label: {
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.primary)
                                    .frame(width: 38, height: 38)
                                    .glassEffect(.regular.interactive(), in: .circle)
                            }
                            .padding(.trailing, 16)
                            .padding(.bottom, 88)   // float above the input bar
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                }

                // Floating input bar
                inputBar
            }
            .overlay(alignment: .top) {
                if conn.status == .offline { offlineBanner }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: conn.status)
            .navigationTitle("Think")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        vm.startNewChat()   // fires its own crisp haptic
                    } label: {
                        Label("New Chat", systemImage: "square.and.pencil")
                            .labelStyle(.iconOnly)
                            .foregroundStyle(.primary)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        vm.showRetrievalSheet = true
                    } label: {
                        Label("Memories Retrieved", systemImage: "sparkles")
                            .labelStyle(.iconOnly)
                            .foregroundStyle(vm.retrievedMemories.isEmpty ? .tertiary : .primary)
                    }
                    .disabled(vm.retrievedMemories.isEmpty)
                }
            }
            .toolbarBackground(.thinMaterial, for: .navigationBar)
            .task { await vm.loadHistory() }
            .task { vm.requestPermissionsIfNeeded() }
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(3.5))
                    guard inputText.isEmpty && !inputFocused else { continue }
                    placeholderVisible = false
                    try? await Task.sleep(for: .seconds(0.4))
                    placeholderIndex = (placeholderIndex + 1) % chatPlaceholders.count
                    placeholderVisible = true
                }
            }
            .sheet(isPresented: $vm.showRetrievalSheet) {
                MemoryRetrievalSheetView(
                    stages: vm.retrievalStages,
                    memories: vm.retrievedMemories
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.regularMaterial)
            }
            .alert("Error", isPresented: .constant(vm.errorMessage != nil), actions: {
                Button("OK") { vm.errorMessage = nil }
            }, message: {
                Text(vm.errorMessage ?? "")
            })
        }
    }

    private var inputBar: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(alignment: .bottom, spacing: 8) {
                // Photo picker button
                PhotosPicker(selection: $photoItem, matching: .images) {
                    ZStack {
                        if let img = selectedImage {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 40, height: 40)
                                .clipShape(Circle())
                        } else {
                            Image(systemName: "photo")
                                .font(.system(size: 19))
                                .foregroundStyle(.secondary)
                                .frame(width: 40, height: 40)
                        }
                    }
                }
                .glassEffect(.regular.interactive(), in: .circle)
                .onChange(of: photoItem) {
                    Task {
                        if let data = try? await photoItem?.loadTransferable(type: Data.self),
                           let img = UIImage(data: data) {
                            selectedImage = img
                            Haptics.tapLight()
                        }
                    }
                }

                // Text field — single glass capsule with the send button tucked inside
                HStack(alignment: .bottom, spacing: 4) {
                    ZStack(alignment: .leading) {
                        if inputText.isEmpty && !inputFocused {
                            Text(chatPlaceholders[placeholderIndex])
                                .foregroundStyle(.tertiary)
                                .opacity(placeholderVisible ? 1 : 0)
                                .animation(.easeInOut(duration: 0.4), value: placeholderVisible)
                                .allowsHitTesting(false)
                        }
                        TextField("", text: $inputText, axis: .vertical)
                            .lineLimit(1...6)
                            .focused($inputFocused)
                            .onSubmit { Task { await send() } }
                            .onChange(of: inputFocused) { if inputFocused { Haptics.prepare() } }
                    }
                    .padding(.leading, 16)
                    .padding(.vertical, 10)

                    Button {
                        if vm.isStreaming { Haptics.tapLight(); vm.cancelStream() } else { Task { await send() } }
                    } label: {
                        Image(systemName: vm.isStreaming ? "stop.circle.fill" : "arrow.up.circle.fill")
                            .font(.system(size: 30))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(vm.isStreaming ? AnyShapeStyle(.secondary)
                                             : AnyShapeStyle(canSend ? Color.accentColor : Color(.tertiaryLabel)))
                    }
                    .disabled(!canSend && !vm.isStreaming)
                    .padding(4)
                }
                // Fixed-radius rounded rect (not a capsule): looks pill-like on one line,
                // but keeps a consistent radius as the field grows — like iMessage.
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 21, style: .continuous))
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .animation(.snappy(duration: 0.2), value: canSend)
    }

    private var offlineBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash").font(.footnote.weight(.semibold))
            Text("Can't reach \(conn.host)")
                .font(.footnote).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 8)
            Button("Retry") { Task { await conn.check() } }
                .font(.footnote.weight(.semibold))
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.red.opacity(0.4), lineWidth: 1))
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedImage != nil
    }

    // Show a timestamp above the first message and whenever there's a >15-min gap.
    private func showTimestamp(at index: Int) -> Bool {
        guard index >= 0, index < vm.messages.count, let d = vm.messages[index].date else { return false }
        if index == 0 { return true }
        guard let prev = vm.messages[index - 1].date else { return true }
        return d.timeIntervalSince(prev) > 15 * 60
    }

    private func send() async {
        let text = inputText
        let image = selectedImage
        inputText = ""
        selectedImage = nil
        photoItem = nil
        await vm.sendMessage(text, image: image)
    }
}
