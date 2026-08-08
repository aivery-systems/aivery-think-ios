import Foundation
import Combine

@MainActor
final class ConversationsViewModel: ObservableObject {
    @Published var conversations: [Conversation] = []
    @Published var loading = false

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
                    recall_only: old.recall_only)
            }
        } catch { /* surface if needed */ }
    }

    func delete(_ id: String) async {
        do {
            try await APIClient.shared.requestEmpty("/api/conversations/\(id)", method: "DELETE")
            conversations.removeAll { $0.id == id }
        } catch { /* surface if needed */ }
    }
}
