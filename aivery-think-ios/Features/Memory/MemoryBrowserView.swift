import SwiftUI

struct MemoryBrowserView: View {
    @StateObject private var vm = MemoryBrowserViewModel()
    private enum Tab { case saved, queue }
    @State private var tab: Tab = .saved
    // Checklist mode for bulk mark-stale / restore.
    @State private var editMode: EditMode = .inactive
    @State private var selection = Set<String>()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("View", selection: $tab) {
                    Text("Saved").tag(Tab.saved)
                    Text("Queue").tag(Tab.queue)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                if tab == .saved {
                    savedList
                } else {
                    MemoryQueueView()
                }
            }
            .navigationTitle("Memories")
            .toolbar {
                if tab == .saved {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(editMode.isEditing ? "Done" : "Select") {
                            withAnimation {
                                editMode = editMode.isEditing ? .inactive : .active
                                selection = []
                            }
                        }
                    }
                    if editMode.isEditing {
                        ToolbarItemGroup(placement: .bottomBar) {
                            let chosen = vm.displayed.filter { selection.contains($0.id) }
                            Button(selection.count == vm.displayed.count && !vm.displayed.isEmpty ? "Clear" : "Select all") {
                                selection = selection.count == vm.displayed.count ? [] : Set(vm.displayed.map(\.id))
                            }
                            Spacer()
                            Button("Mark stale") { bulk(stale: true) }
                                .tint(.orange)
                                .disabled(!chosen.contains { !$0.isStale })
                            Button("Restore") { bulk(stale: false) }
                                .tint(.green)
                                .disabled(!chosen.contains { $0.isStale })
                        }
                    }
                }
            }
        }
    }

    private func bulk(stale: Bool) {
        let ids = selection
        Task {
            await vm.setStale(ids, stale: stale)
            withAnimation {
                selection = []
                editMode = .inactive
            }
        }
    }

    private var savedList: some View {
            List(selection: $selection) {
                // Type filter
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(vm.filterTypes, id: \.self) { type in
                                filterChip(type)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12))
                    .listRowBackground(Color.clear)

                    Toggle("Show stale", isOn: $vm.showStale)
                        .font(.subheadline)
                }

                if vm.loading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                } else if let err = vm.loadError {
                    Text(err)
                        .foregroundStyle(.red)
                        .font(.caption)
                } else if vm.displayed.isEmpty {
                    Text("No memories")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                } else {
                    ForEach(vm.displayed) { mem in
                        NavigationLink {
                            MemoryDetailView(memory: mem, vm: vm)
                        } label: {
                            memoryRow(mem)
                        }
                    }
                    .onDelete { offsets in
                        for i in offsets {
                            let id = vm.displayed[i].id
                            Task { await vm.delete(id) }
                            Haptics.tapMedium()
                        }
                    }
                }
            }
            .environment(\.editMode, $editMode)
            .searchable(text: $vm.searchText, prompt: "Search memories")
            .task { await vm.load() }
            // Stale memories are only fetched when asked for.
            .onChange(of: vm.showStale) { Task { await vm.load() } }
    }

    private func filterChip(_ label: String) -> some View {
        let isSelected = vm.typeFilter == label
        return Button {
            vm.typeFilter = label
        } label: {
            Text(label)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .white : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    isSelected ? Color.accentColor : Color(.secondarySystemFill),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }

    private func memoryRow(_ mem: MemoryRecord) -> some View {
        HStack(spacing: 10) {
            TypeBadge(type: mem.memoryType)
            VStack(alignment: .leading, spacing: 2) {
                Text(mem.content)
                    .lineLimit(2)
                    .font(.subheadline)
                if mem.isStale {
                    Text("Stale")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
