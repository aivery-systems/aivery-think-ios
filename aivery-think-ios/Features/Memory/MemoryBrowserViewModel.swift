import Foundation
import Combine

@MainActor
final class MemoryBrowserViewModel: ObservableObject {
    @Published var memories: [MemoryRecord] = []
    @Published var loading = false
    @Published var typeFilter = "All"
    @Published var searchText = ""
    @Published var showStale = false

    private let types = ["All", "Semantic", "Preference", "Episodic", "Identity", "System"]
    var filterTypes: [String] { types }

    var displayed: [MemoryRecord] {
        memories.filter { mem in
            let matchesType = typeFilter == "All" || mem.memoryType.lowercased() == typeFilter.lowercased()
            let matchesSearch = searchText.isEmpty || mem.content.localizedCaseInsensitiveContains(searchText)
            let matchesStale = showStale ? true : !mem.isStale
            return matchesType && matchesSearch && matchesStale
        }
    }

    @Published var loadError: String?

    func load() async {
        loading = true
        loadError = nil
        defer { loading = false }
        do {
            // /api/memories returns a bare JSON array, not a wrapper object
            let result: [MemoryRecord] = try await APIClient.shared.request("/api/memories")
            memories = result
        } catch APIError.unauthorized {
            loadError = "401 — check your API key in Settings"
        } catch APIError.serverError(let code) {
            loadError = "Server error \(code)"
        } catch {
            loadError = error.localizedDescription
        }
    }

    func delete(_ id: String) async {
        do {
            try await APIClient.shared.requestEmpty("/api/memories/\(id)", method: "DELETE")
            memories.removeAll { $0.id == id }
        } catch { /* surface error if needed */ }
    }

    func restore(_ id: String) async {
        struct Empty: Decodable {}
        do {
            let _: Empty = try await APIClient.shared.request(
                "/api/memories/\(id)/restore",
                method: "PATCH"
            )
            if let idx = memories.firstIndex(where: { $0.id == id }) {
                let old = memories[idx]
                memories[idx] = MemoryRecord(
                    id: old.id,
                    memoryType: old.memoryType,
                    content: old.content,
                    createdAt: old.createdAt,
                    lastAccessedAt: old.lastAccessedAt,
                    isStale: false,
                    clusterId: old.clusterId,
                    relevance: old.relevance
                )
            }
        } catch { /* surface error */ }
    }

    // Matches Fabric API: record UpdateMemoryRequest(string Content, double Relevance, string Type)
    struct UpdateBody: Encodable {
        let content: String
        let relevance: Double
        let type: String
    }

    func update(_ id: String, content: String, type: String, relevance: Double) async {
        struct Empty: Decodable {}
        do {
            let _: Empty = try await APIClient.shared.request(
                "/api/memories/\(id)",
                method: "PUT",
                body: UpdateBody(content: content, relevance: relevance, type: type)
            )
            if let idx = memories.firstIndex(where: { $0.id == id }) {
                let old = memories[idx]
                memories[idx] = MemoryRecord(
                    id: old.id,
                    memoryType: type,
                    content: content,
                    createdAt: old.createdAt,
                    lastAccessedAt: old.lastAccessedAt,
                    isStale: old.isStale,
                    clusterId: old.clusterId,
                    relevance: relevance
                )
            }
        } catch { /* surface error */ }
    }
}
