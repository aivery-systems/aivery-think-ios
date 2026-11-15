import Foundation
import UIKit

struct Conversation: Codable, Identifiable {
    let id: String
    let agent_id: String
    let title: String?
    let created_at: String
    let parent_message_id: String?
    let recall_only: Bool
    // ISO time it was pinned (text, like created_at); nil = not pinned. Absent from older APIs.
    var pinned_at: String? = nil

    var displayTitle: String { title?.isEmpty == false ? title! : "New Chat" }
    var isPinned: Bool { pinned_at != nil }
    var isBranch: Bool { parent_message_id != nil }
}

struct MessageRecord: Codable, Identifiable {
    let id: String
    let role: String
    let content: String
    let created_at: String
    // Transient: the image the user sent, shown in their bubble for their eyes only.
    // Excluded from CodingKeys, so it's never encoded/decoded or sent to the server.
    var localImage: UIImage? = nil

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
