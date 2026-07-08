import SwiftUI

struct MemoryBrowserView: View {
    @StateObject private var vm = MemoryBrowserViewModel()
    var body: some View {
        NavigationStack {
            List {
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
            .searchable(text: $vm.searchText, prompt: "Search memories")
            .navigationTitle("Memories")
            .task { await vm.load() }
        }
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
