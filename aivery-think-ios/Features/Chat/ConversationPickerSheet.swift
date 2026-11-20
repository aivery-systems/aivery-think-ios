import SwiftUI

/// A row from GET /api/conversations/search (aivery-api) — full-text over messages plus
/// title match, scoped to the current agent. Empty query → most recent conversations.
struct ConversationSearchHit: Decodable, Identifiable, Equatable {
    let id: String
    let title: String?
    let created_at: String
    let recall_only: Bool
    let snippet: String?
    let last_activity_at: String?

    var displayTitle: String {
        let t = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return t.isEmpty ? "Untitled" : t
    }
}

/// A conversation attached to the next message with "@" — its transcript is sent as context.
struct ConversationRef: Identifiable, Equatable {
    let id: String
    let title: String
    let recallOnly: Bool
}

/// The "@" picker: search past conversations and attach one as context for the next message.
struct ConversationPickerSheet: View {
    /// The open conversation — never offered.
    let excludeId: String?
    let attachedIds: [String]
    let onSelect: (ConversationRef) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var hits: [ConversationSearchHit] = []
    @State private var loading = true
    @State private var failed = false

    private var visible: [ConversationSearchHit] { hits.filter { !attachedIds.contains($0.id) } }

    var body: some View {
        NavigationStack {
            List {
                if !loading && visible.isEmpty {
                    Text(failed ? "Couldn't search conversations." : "No conversations found.")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }
                ForEach(visible) { hit in
                    Button {
                        Haptics.tapLight()
                        onSelect(ConversationRef(id: hit.id, title: hit.displayTitle, recallOnly: hit.recall_only))
                        dismiss()
                    } label: {
                        row(hit)
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.plain)
            .overlay { if loading && visible.isEmpty { ProgressView() } }
            .navigationTitle("Attach a Conversation")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search past chats")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            // Re-runs on every query change; the sleep debounces typing (cancelled by the next run).
            .task(id: query) {
                if !query.isEmpty { try? await Task.sleep(for: .milliseconds(200)) }
                guard !Task.isCancelled else { return }
                await search(query)
            }
        }
    }

    private func row(_ hit: ConversationSearchHit) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                if hit.recall_only {
                    Image(systemName: "eye.slash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(hit.displayTitle)
                    .font(.body)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let d = ChatDate.parse(hit.last_activity_at ?? hit.created_at) {
                    Text(d.formatted(.relative(presentation: .named)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let snippet = hit.snippet, !snippet.isEmpty {
                Text(snippet)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func search(_ q: String) async {
        loading = true
        var items = [URLQueryItem(name: "q", value: q), URLQueryItem(name: "limit", value: "20")]
        if let excludeId { items.append(URLQueryItem(name: "exclude", value: excludeId)) }
        do {
            let rows: [ConversationSearchHit] = try await APIClient.shared.request("/api/conversations/search", query: items)
            guard !Task.isCancelled else { return }
            hits = rows
            failed = false
        } catch {
            guard !Task.isCancelled else { return }
            failed = true
        }
        loading = false
    }
}
