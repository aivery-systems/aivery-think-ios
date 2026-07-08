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
                Button {
                    chatVM.startNewChat()
                    Haptics.tapLight()
                    selectedTab = 0
                } label: {
                    Label("New Chat", systemImage: "plus.bubble")
                        .foregroundStyle(Color.accentColor)
                }

                if vm.loading {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    ForEach(vm.conversations) { conv in
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
                    }
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

    private func conversationRow(_ conv: Conversation) -> some View {
        HStack(spacing: 8) {
            if conv.isBranch {
                Image(systemName: "arrow.turn.down.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(conv.displayTitle)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Text(relativeDate(conv.created_at))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
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
