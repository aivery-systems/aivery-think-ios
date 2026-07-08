import Foundation

struct MemoryRecord: Codable, Identifiable {
    let id: String
    let memoryType: String
    let content: String
    let createdAt: String
    let lastAccessedAt: String?
    let isStale: Bool
    let clusterId: String?
    let relevance: Double?

    // API field names differ from our Swift property names
    enum CodingKeys: String, CodingKey {
        case id, content, isStale, clusterId, relevance
        case memoryType = "type"
        case createdAt = "createdAt"
        case lastAccessedAt = "lastAccessed"
    }
}

// Cortex emits these flat (snake_case) in the session_memory_context SSE event.
struct RetrievedMemory: Codable, Identifiable {
    let id: String
    let content: String
    let type: String
    let relevance: Double?
    let cosine: Double?
    let recency: Double?
    let finalScore: Double?
    let explanation: String?

    enum CodingKeys: String, CodingKey {
        case id, content, type, relevance, cosine, recency, explanation
        case finalScore = "final_score"
    }

    var scorePercent: Int { Int((finalScore ?? relevance ?? 0) * 100) }
}
