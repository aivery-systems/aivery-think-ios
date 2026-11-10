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

// A memory written during a turn — carried by the memory_written SSE event and
// persisted inside the assistant message as a <memory_refs> JSON block (same keys
// as the web client's WrittenMemoryRef in aivery-think/.../chat/types.ts).
struct WrittenMemoryRef: Codable, Identifiable, Equatable {
    let id: String
    let type: String
    let content: String
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

// A turn's memories queued as one Fabric memory_write job. Arrives in the memory_queued SSE
// event (items all pending) and from GET /memory/write-queue/{jobId} as items land
// (mirrors QueuedMemoryJob in aivery-think/.../chat/types.ts).
struct QueuedMemoryJob: Codable, Identifiable, Equatable {
    let jobId: String
    let messageId: String?
    var items: [QueuedMemoryItem]

    var id: String { jobId }
    // Paused items still wait (resumed from the queue manager), so keep polling them.
    var isSettled: Bool { items.allSatisfy { $0.status != .pending && $0.status != .paused } }

    enum CodingKeys: String, CodingKey {
        case jobId = "job_id"
        case messageId = "message_id"
        case items
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        jobId = try c.decode(String.self, forKey: .jobId)
        messageId = try c.decodeIfPresent(String.self, forKey: .messageId)
        // The event's items carry no index/status; position is the index, status is pending.
        let raw = try c.decodeIfPresent([QueuedMemoryItem].self, forKey: .items) ?? []
        items = raw.enumerated().map { offset, item in
            var item = item
            if item.index == nil { item.index = offset }
            return item
        }
    }
}

struct QueuedMemoryItem: Codable, Equatable {
    enum Status: String, Codable {
        case pending, paused, written, rejected, invalid, quota, failed, deleted
    }

    var index: Int?
    let content: String
    let type: String
    var status: Status
    var id: String?

    enum CodingKeys: String, CodingKey { case index, content, type, status, id }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        index = try c.decodeIfPresent(Int.self, forKey: .index)
        content = try c.decodeIfPresent(String.self, forKey: .content) ?? ""
        type = try c.decodeIfPresent(String.self, forKey: .type) ?? ""
        status = (try? c.decodeIfPresent(Status.self, forKey: .status)) ?? .pending
        id = try c.decodeIfPresent(String.self, forKey: .id)
    }
}

struct QueuedMemoryJobList: Codable {
    let jobs: [QueuedMemoryJob]?
}

// Queue manager (GET /memory/write-queue/agent/{agentId}): memories still waiting to be
// validated and written. Mirrors MemoryQueue in aivery-think/.../sidebar/memory-queue.tsx.
struct MemoryQueueState: Codable {
    let paused: Bool
    let items: [MemoryQueueEntry]?
}

struct MemoryQueueEntry: Codable, Identifiable, Equatable {
    let jobId: String
    let content: String?
    let type: String?
    let status: String   // queued | running | retrying | paused

    var id: String { jobId }

    enum CodingKeys: String, CodingKey {
        case jobId = "job_id"
        case content, type, status
    }
}
