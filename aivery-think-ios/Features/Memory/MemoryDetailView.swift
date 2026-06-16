import SwiftUI

struct MemoryDetailView: View {
    let memory: MemoryRecord
    @ObservedObject var vm: MemoryBrowserViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var editedContent: String
    @State private var editedType: String
    @State private var editedRelevance: Double
    @State private var saving = false

    private let types = ["semantic", "preference", "episodic", "identity", "system"]

    init(memory: MemoryRecord, vm: MemoryBrowserViewModel) {
        self.memory = memory
        self.vm = vm
        _editedContent = State(initialValue: memory.content)
        _editedType = State(initialValue: memory.memoryType)
        _editedRelevance = State(initialValue: memory.relevance ?? 0.5)
    }

    var body: some View {
        Form {
            Section("Content") {
                ZStack(alignment: .topLeading) {
                    if editedContent.isEmpty {
                        Text("Memory content…")
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8)
                            .padding(.leading, 4)
                    }
                    TextEditor(text: $editedContent)
                        .frame(minHeight: 100)
                }
                .background(.ultraThinMaterial)
            }

            Section("Type") {
                Picker("Type", selection: $editedType) {
                    ForEach(types, id: \.self) { t in
                        Text(t.capitalized).tag(t)
                    }
                }
                .pickerStyle(.menu)
            }

            Section {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Relevance")
                        Spacer()
                        Text(String(format: "%.2f", editedRelevance))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $editedRelevance, in: 0...1)
                        .tint(Color.accentColor)
                }
            }

            Section("Metadata") {
                metaRow("Created", memory.createdAt)
                metaRow("Last Accessed", memory.lastAccessedAt ?? "—")
                metaRow("Status", memory.isStale ? "Stale" : "Active")
                if let clusterId = memory.clusterId {
                    metaRow("Cluster", clusterId)
                }
            }

            if memory.isStale {
                Section {
                    Button("Restore Memory") {
                        Task {
                            await vm.restore(memory.id)
                            dismiss()
                        }
                    }
                    .foregroundStyle(Color.accentColor)
                }
            }
        }
        .navigationTitle(memory.memoryType.capitalized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") {
                    Task {
                        saving = true
                        await vm.update(memory.id, content: editedContent, type: editedType, relevance: editedRelevance)
                        saving = false
                        dismiss()
                    }
                }
                .disabled(saving)
            }
        }
    }

    private func metaRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.footnote).foregroundStyle(.secondary)
        }
    }
}
