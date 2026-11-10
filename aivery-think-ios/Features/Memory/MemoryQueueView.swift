import SwiftUI
import Combine

/// Queue manager: the agent's memories still waiting to be validated and written. Pause holds
/// them all (new ones queue paused too); Run all resumes in order; swipe an item to run it now
/// (even while paused) or delete it so it's never written. Mirrors the web Queue tab.
@MainActor
final class MemoryQueueViewModel: ObservableObject {
    private let api = APIClient.shared
    @Published var paused = false
    @Published var items: [MemoryQueueEntry] = []
    @Published var loaded = false
    @Published var busy = false

    private var agentPath: String {
        "/memory/write-queue/agent/\(api.agentId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? api.agentId)"
    }

    func load() async {
        if let state: MemoryQueueState = try? await api.request(agentPath) {
            paused = state.paused
            items = state.items ?? []
        }
        loaded = true
    }

    func togglePause() async {
        busy = true
        try? await api.requestEmpty("\(agentPath)/\(paused ? "resume" : "pause")", method: "POST")
        Haptics.tapMedium()
        busy = false
        await load()
    }

    func run(_ item: MemoryQueueEntry) async {
        try? await api.requestEmpty("/memory/write-queue/item/\(item.jobId)/run", method: "POST")
        Haptics.tapLight()
        await load()
    }

    func delete(_ item: MemoryQueueEntry) async {
        items.removeAll { $0.id == item.id }
        try? await api.requestEmpty("/memory/write-queue/item/\(item.jobId)", method: "DELETE")
        Haptics.tapMedium()
        await load()
    }
}

struct MemoryQueueView: View {
    @StateObject private var vm = MemoryQueueViewModel()

    var body: some View {
        List {
            Section {
                HStack {
                    Text(vm.paused
                         ? "Paused — new memories wait here"
                         : vm.items.isEmpty ? "Nothing waiting" : "\(vm.items.count) waiting")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(vm.paused ? "Run all" : "Pause") { Task { await vm.togglePause() } }
                        .buttonStyle(.bordered)
                        .tint(vm.paused ? .green : .secondary)
                        .disabled(vm.busy)
                }
            }

            if vm.loaded && vm.items.isEmpty {
                Text("Memories from your chats appear here while they wait to be validated and saved.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }

            ForEach(vm.items) { item in
                HStack(alignment: .top, spacing: 10) {
                    TypeBadge(type: item.type ?? "")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.content ?? "")
                            .font(.subheadline)
                            .lineLimit(3)
                        Text(statusLabel(item.status))
                            .font(.caption2)
                            .foregroundStyle(item.status == "running" ? .green : .secondary)
                    }
                }
                .padding(.vertical, 2)
                .swipeActions(edge: .trailing) {
                    if item.status != "running" {
                        Button(role: .destructive) { Task { await vm.delete(item) } } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                .swipeActions(edge: .leading) {
                    if item.status != "running" {
                        Button { Task { await vm.run(item) } } label: {
                            Label("Run now", systemImage: "play.fill")
                        }
                        .tint(.green)
                    }
                }
            }
        }
        .refreshable { await vm.load() }
        .task {
            // Poll while visible; .task cancels when the view goes away.
            while !Task.isCancelled {
                await vm.load()
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    private func statusLabel(_ status: String) -> String {
        switch status {
        case "running":  return "Validating…"
        case "retrying": return "Retrying"
        case "paused":   return "Paused"
        default:         return "Waiting"
        }
    }
}
