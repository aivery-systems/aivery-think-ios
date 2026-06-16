import Foundation

struct Conversation: Codable, Identifiable {
    let id: String
    let agent_id: String
    let title: String?
    let created_at: String
    let parent_message_id: String?

    var displayTitle: String { title?.isEmpty == false ? title! : "New Chat" }
    var isBranch: Bool { parent_message_id != nil }
}

struct MessageRecord: Codable, Identifiable {
    let id: String
    let role: String
    let content: String
    let created_at: String

    var isUser: Bool { role == "user" }

    // Fabric /api/messages returns camelCase `createdAt`; locally we create with `created_at`.
    enum CodingKeys: String, CodingKey {
        case id, role, content
        case created_at = "createdAt"
    }
}

struct CreateConversationResponse: Decodable {
    let id: String
}

struct ConversationListResponse: Decodable {
    let conversations: [Conversation]
}

struct MessagesResponse: Decodable {
    let messages: [MessageRecord]
}
