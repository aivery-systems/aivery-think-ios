import Foundation
import UIKit

struct HistoryMessage: Codable {
    let role: String
    let content: String
}

// Matches Cortex AgentChatRequest (POST /api/agent/chat) — snake_case JSON keys.
// Provider override fields let the user point chat at their own Ollama/OpenAI.
struct CortexChatRequest: Encodable {
    let message: String
    let agent_id: String
    let stream: Bool = true
    let think: Bool
    let conversation_id: String?
    let history: [HistoryMessage]?
    let user_system_prompt: String?
    let chat_style: String?
    let provider_type: String?
    let provider_url: String?
    let api_key: String?
    let model: String?
    let image: String?      // base64-encoded JPEG
    let latitude: Double?
    let longitude: Double?

    init(message: String, agentId: String, think: Bool = false,
         conversationId: String? = nil,
         history: [HistoryMessage] = [],
         systemPrompt: String? = nil, chatStyle: String? = nil,
         provider: ProviderSettings? = nil,
         image: UIImage? = nil,
         latitude: Double? = nil,
         longitude: Double? = nil) {
        self.message = message
        self.agent_id = agentId
        self.think = think
        self.conversation_id = conversationId
        self.history = history.isEmpty ? nil : history
        self.user_system_prompt = (systemPrompt?.isEmpty == false) ? systemPrompt : nil
        self.image = image.flatMap { Self.encodeImage($0) }
        self.latitude = latitude
        self.longitude = longitude
        self.chat_style = (chatStyle?.isEmpty == false) ? chatStyle : nil
        if let p = provider, p.enabled, !p.baseUrl.isEmpty {
            self.provider_type = p.type
            self.provider_url = p.baseUrl
            self.api_key = p.apiKey
            self.model = p.model
        } else {
            self.provider_type = nil
            self.provider_url = nil
            self.api_key = nil
            self.model = nil
        }
    }

    // Scale large images down before base64-encoding to cap request body size.
    // A 12MP photo is ~48MB raw; scaled to 1024px it's ~150KB JPEG ≈ 200KB base64.
    private static func encodeImage(_ image: UIImage) -> String? {
        let maxDim: CGFloat = 1024
        let size = image.size
        let scale = size.width > size.height
            ? min(maxDim / size.width, 1)
            : min(maxDim / size.height, 1)
        let target = scale < 1
            ? CGSize(width: size.width * scale, height: size.height * scale)
            : size
        let renderer = UIGraphicsImageRenderer(size: target)
        let scaled = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
        return scaled.jpegData(compressionQuality: 0.8)?.base64EncodedString()
    }
}

struct RetrievalStageEvent: Codable {
    // "embedding" | "clusterFilter" | "vectorSearch" | "dbFetch" | "ranked"
    let stage: String
    let count: Int
}

enum SSEEvent {
    case chunk(String)
    case thinkChunk(String)
    case retrievalStage(RetrievalStageEvent)
    case memoryResult([RetrievedMemory])
    case memoryWritten
    case agentNote(String)
    case done
    case error
}
