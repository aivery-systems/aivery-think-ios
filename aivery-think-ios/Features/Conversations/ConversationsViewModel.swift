import Foundation
import Combine

@MainActor
final class ConversationsViewModel: ObservableObject {
    @Published var conversations: [Conversation] = []
    @Published var loading = false
    // Shown as an alert — a failed action must not look like a dead button.
    @Published var errorMessage: String?

    func load() async {
        loading = true
        defer { loading = false }
        do {
            // /api/conversations returns a bare array, newest first.
            conversations = try await APIClient.shared.request("/api/conversations")
        } catch { conversations = [] }
    }

    func rename(_ id: String, title: String) async {
        struct Body: Encodable { let title: String }
        do {
            try await APIClient.shared.requestEmpty(
                "/api/conversations/\(id)/title", method: "PATCH", body: Body(title: title))
            if let idx = conversations.firstIndex(where: { $0.id == id }) {
                let old = conversations[idx]
                conversations[idx] = Conversation(
                    id: old.id, agent_id: old.agent_id, title: title,
                    created_at: old.created_at, parent_message_id: old.parent_message_id,
                    recall_only: old.recall_only, pinned_at: old.pinned_at,
                    last_activity_at: old.last_activity_at, unread: old.unread)
            }
        } catch { /* surface if needed */ }
    }

    var pinned: [Conversation] { conversations.filter(\.isPinned) }
    var recent: [Conversation] { conversations.filter { !$0.isPinned } }

    func togglePin(_ conv: Conversation) async {
        struct Body: Encodable { let pinned: Bool }
        struct Result: Decodable { let pinned_at: String? }
        do {
            let result: Result = try await APIClient.shared.request(
                "/api/conversations/\(conv.id)/pin", method: "PATCH", body: Body(pinned: !conv.isPinned))
            if let idx = conversations.firstIndex(where: { $0.id == conv.id }) {
                conversations[idx].pinned_at = result.pinned_at
            }
            sortLikeServer()
            Haptics.tapLight()
        } catch APIError.notFound {
            // An API older than pinning has no /pin route.
            errorMessage = "Couldn't \(conv.isPinned ? "unpin" : "pin") this chat — the server doesn't support pinning yet. Restart or update the Aivery API."
        } catch {
            errorMessage = "Couldn't \(conv.isPinned ? "unpin" : "pin") this chat: \(error.localizedDescription)"
        }
    }

    // Opening a chat marks it read server-side (ChatViewModel); reflect that here right away.
    func markReadLocally(_ id: String) {
        if let idx = conversations.firstIndex(where: { $0.id == id }) { conversations[idx].unread = false }
    }

    // Same order as the API: pinned first (most recently pinned on top), then by last activity.
    private func sortLikeServer() {
        conversations.sort { a, b in
            if a.isPinned != b.isPinned { return a.isPinned }
            if let pa = a.pinned_at, let pb = b.pinned_at, pa != pb { return pa > pb }
            return (a.last_activity_at ?? a.created_at) > (b.last_activity_at ?? b.created_at)
        }
    }

    func delete(_ id: String) async {
        do {
            try await APIClient.shared.requestEmpty("/api/conversations/\(id)", method: "DELETE")
            conversations.removeAll { $0.id == id }
        } catch { /* surface if needed */ }
    }
}
