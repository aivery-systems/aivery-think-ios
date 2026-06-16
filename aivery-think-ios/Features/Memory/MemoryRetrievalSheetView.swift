import SwiftUI

struct MemoryRetrievalSheetView: View {
    let stages: [RetrievalStageEvent]
    let memories: [RetrievedMemory]

    @State private var selected: RetrievedMemory?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    RetrievalPipelineView(stages: stages)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                }

                Section {
                    if memories.isEmpty {
                        Text("No memories retrieved")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    } else {
                        ForEach(memories) { mem in
                            Button {
                                selected = mem
                            } label: {
                                MemoryRowView(memory: mem)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    Text("Retrieved Memories")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Memory Retrieval")
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(item: $selected) { mem in
            ScoreBreakdownView(memory: mem)
                .presentationDetents([.medium])
                .presentationBackground(.regularMaterial)
        }
    }
}

struct MemoryRowView: View {
    let memory: RetrievedMemory

    var body: some View {
        HStack(spacing: 10) {
            TypeBadge(type: memory.type)

            VStack(alignment: .leading, spacing: 3) {
                Text(memory.content)
                    .lineLimit(2)
                    .font(.subheadline)
                    .foregroundStyle(.primary)

                HStack(spacing: 10) {
                    if let c = memory.cosine { scoreChip("cos", c) }
                    if let r = memory.relevance { scoreChip("rel", r) }
                    if let rec = memory.recency { scoreChip("rec", rec) }
                }
            }

            Spacer()

            Text("\(memory.scorePercent)%")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.accentColor)
        }
        .padding(.vertical, 4)
    }

    private func scoreChip(_ label: String, _ value: Double) -> some View {
        Text("\(label) \(String(format: "%.2f", value))")
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
    }
}

struct ScoreBreakdownView: View {
    let memory: RetrievedMemory
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Content") {
                    Text(memory.content)
                        .font(.subheadline)
                }

                Section("Scores") {
                    scoreRow("Cosine Similarity", memory.cosine)
                    scoreRow("Relevance", memory.relevance)
                    scoreRow("Recency Decay", memory.recency)
                    HStack {
                        Text("Final Score")
                            .fontWeight(.semibold)
                        Spacer()
                        Text("\(memory.scorePercent)%")
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.accentColor)
                    }
                }

                if let explanation = memory.explanation {
                    Section("Explanation") {
                        Text(explanation)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(memory.type.capitalized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func scoreRow(_ label: String, _ value: Double?) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value.map { String(format: "%.3f", $0) } ?? "—")
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}

struct TypeBadge: View {
    let type: String

    private var color: Color {
        switch type.lowercased() {
        case "semantic":   return .blue
        case "preference": return .purple
        case "episodic":   return .orange
        case "identity":   return .green
        case "system":     return .gray
        default:           return .secondary
        }
    }

    var body: some View {
        Text(type.prefix(3).uppercased())
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
    }
}
