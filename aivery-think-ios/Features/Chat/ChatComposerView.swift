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

// AiVery interactive accent — amber lifts the input controls off the dark vibrant
// gradient. Not the brand teal: teal is indistinguishable from the gradient's blues
// for blue–green color-deficient vision; amber contrasts in hue and luminance both.
private let aiveryAccent = Color.aiveryAccent

/// The floating input bar. It owns the draft text: keeping that @State out of ChatView
/// means a keystroke re-renders only this bar, not the whole message list (the cause of
/// typing lag in long conversations).
struct ChatComposerView: View {
    @ObservedObject var vm: ChatViewModel
    @ObservedObject private var capabilities = ModelCapabilitiesStore.shared
    @ObservedObject private var settings = UserSettings.shared
    @State private var inputText = ""
    @FocusState private var inputFocused: Bool
    @State private var placeholderIndex = Int.random(in: 0..<chatPlaceholders.count)
    @State private var placeholderVisible = true
    @State private var photoItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    // "@" attachments: conversations whose transcripts go along with the next message.
    @State private var contextRefs: [ConversationRef] = []
    @State private var showConversationPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !contextRefs.isEmpty { attachmentChips }
            inputRow
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .animation(.snappy(duration: 0.2), value: canSend)
        .animation(.snappy(duration: 0.2), value: contextRefs)
        .onChange(of: inputText) { old, new in
            // A freshly typed "@" at the start or after whitespace opens the picker.
            guard new.count == old.count + 1, new.hasSuffix("@") else { return }
            let before = new.dropLast()
            if before.isEmpty || before.last?.isWhitespace == true {
                Haptics.tapLight()
                showConversationPicker = true
            }
        }
        .onChange(of: vm.conversationId) { contextRefs = [] }   // attachments belong to their chat
        .sheet(isPresented: $showConversationPicker) {
            ConversationPickerSheet(
                excludeId: vm.conversationId,
                attachedIds: contextRefs.map(\.id),
                onSelect: attach
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
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
    }

    private var attachmentChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(contextRefs) { ref in
                    HStack(spacing: 4) {
                        Image(systemName: ref.recallOnly ? "eye.slash" : "bubble.left.and.bubble.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(ref.title)
                            .font(.caption)
                            .lineLimit(1)
                        Button {
                            contextRefs.removeAll { $0.id == ref.id }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityLabel("Remove \(ref.title)")
                    }
                    .padding(.leading, 10)
                    .padding(.trailing, 6)
                    .padding(.vertical, 6)
                    .glassEffectCompat(in: Capsule())
                }
                if contextRefs.contains(where: \.recallOnly) {
                    Text("Memories won't be saved this turn")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 4)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func attach(_ ref: ConversationRef) {
        // Replace the trailing "@" that opened the picker with the conversation's name.
        if inputText.hasSuffix("@") { inputText.removeLast() }
        inputText += "@\(ref.title) "
        if !contextRefs.contains(where: { $0.id == ref.id }), contextRefs.count < 5 {
            contextRefs.append(ref)
        }
        inputFocused = true
    }

    private var inputRow: some View {
        GlassEffectContainerCompat(spacing: 8) {
            HStack(alignment: .bottom, spacing: 8) {
                // Photo picker button — only for models that take image input
                if capabilities.supportsVision {
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
                                    .foregroundStyle(settings.isAivery ? AnyShapeStyle(aiveryAccent) : AnyShapeStyle(.secondary))
                                    .frame(width: 40, height: 40)
                            }
                        }
                    }
                    .glassEffectCompat(interactive: true, in: .circle)
                    .onChange(of: photoItem) {
                        Task {
                            if let data = try? await photoItem?.loadTransferable(type: Data.self),
                               let img = UIImage(data: data) {
                                selectedImage = img
                                Haptics.tapLight()
                            }
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
                                             : AnyShapeStyle(canSend ? (settings.isAivery ? aiveryAccent : Color.accentColor) : Color(.tertiaryLabel)))
                    }
                    .disabled(!canSend && !vm.isStreaming)
                    .padding(4)
                }
                // Fixed-radius rounded rect (not a capsule): looks pill-like on one line,
                // but keeps a consistent radius as the field grows — like iMessage.
                .glassEffectCompat(in: RoundedRectangle(cornerRadius: 21, style: .continuous))
            }
        }
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || (selectedImage != nil && capabilities.supportsVision)
    }

    private func send() async {
        let text = inputText
        let image = capabilities.supportsVision ? selectedImage : nil
        let refs = contextRefs
        inputText = ""
        selectedImage = nil
        photoItem = nil
        contextRefs = []
        await vm.sendMessage(text, image: image, contextConversationIds: refs.map(\.id))
    }
}
