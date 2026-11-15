import SwiftUI

struct ConversationsView: View {
    @ObservedObject var chatVM: ChatViewModel
    @Binding var selectedTab: Int
    @StateObject private var vm = ConversationsViewModel()
    @State private var renameTarget: Conversation?
    @State private var renameText = ""

    var body: some View {
        NavigationStack {
            List {
                Menu {
                    Button {
                        chatVM.startNewChat()
                        Haptics.tapLight()
                        selectedTab = 0
                    } label: {
                        Label("New Chat", systemImage: "plus.bubble")
                    }
                    Button {
                        chatVM.startNewChat(recallOnly: true)
                        Haptics.tapLight()
                        selectedTab = 0
                    } label: {
                        Label("New Recall Only Chat", systemImage: "eye.slash")
                    }
                } label: {
                    Label("New Chat", systemImage: "plus.bubble")
                        .foregroundStyle(Color.accentColor)
                }

                if vm.loading {
                    ProgressView().frame(maxWidth: .infinity)
                } else if vm.pinned.isEmpty {
                    rows(vm.recent)
                } else {
                    Section("Pinned") { rows(vm.pinned) }
                    Section("Recent") { rows(vm.recent) }
                }
            }
            .navigationTitle("History")
            .task { await vm.load() }
            .onAppear { Task { await vm.load() } }
            .alert("Rename", isPresented: .constant(renameTarget != nil)) {
                TextField("Title", text: $renameText)
                Button("Save") {
                    if let target = renameTarget {
                        Task { await vm.rename(target.id, title: renameText) }
                    }
                    renameTarget = nil
                }
                Button("Cancel", role: .cancel) { renameTarget = nil }
            }
        }
    }

    @ViewBuilder
    private func rows(_ list: [Conversation]) -> some View {
        ForEach(list) { conv in
            Button {
                Task {
                    await chatVM.open(conversation: conv)
                    Haptics.tapLight()
                    selectedTab = 0
                }
            } label: {
                conversationRow(conv)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .swipeActions(edge: .trailing) {
                Button("Delete", systemImage: "trash", role: .destructive) {
                    Task { await vm.delete(conv.id) }
                }
                Button("Rename", systemImage: "pencil") {
                    renameTarget = conv
                    renameText = conv.displayTitle
                }
                .tint(.indigo)
            }
            .swipeActions(edge: .leading) {
                Button(conv.isPinned ? "Unpin" : "Pin",
                       systemImage: conv.isPinned ? "pin.slash" : "pin") {
                    Task { await vm.togglePin(conv) }
                }
                .tint(.orange)
            }
            .contextMenu {
                Button(conv.isPinned ? "Unpin" : "Pin",
                       systemImage: conv.isPinned ? "pin.slash" : "pin") {
                    Task { await vm.togglePin(conv) }
                }
            }
        }
    }

    private func conversationRow(_ conv: Conversation) -> some View {
        HStack(spacing: 8) {
            if conv.isBranch {
                Image(systemName: "arrow.turn.down.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if conv.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .accessibilityLabel("Pinned")
                    }
                    Text(conv.displayTitle)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                }
                HStack(spacing: 4) {
                    if conv.recall_only {
                        Label("Recall Only", systemImage: "eye.slash")
                            .font(.caption2)
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(.secondary)
                    }
                    Text(relativeDate(conv.created_at))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            if conv.id == chatVM.conversationId {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.vertical, 2)
    }

    private func relativeDate(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: iso) else { return iso }
        let rel = RelativeDateTimeFormatter()
        rel.unitsStyle = .short
        return rel.localizedString(for: date, relativeTo: Date())
    }
}
