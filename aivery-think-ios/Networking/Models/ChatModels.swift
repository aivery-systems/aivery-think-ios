import Foundation

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

    init(message: String, agentId: String, think: Bool = false,
         conversationId: String? = nil,
         history: [HistoryMessage] = [],
         systemPrompt: String? = nil, chatStyle: String? = nil,
         provider: ProviderSettings? = nil) {
        self.message = message
        self.agent_id = agentId
        self.think = think
        self.conversation_id = conversationId
        self.history = history.isEmpty ? nil : history
        self.user_system_prompt = (systemPrompt?.isEmpty == false) ? systemPrompt : nil
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
    case done
    case error
}
