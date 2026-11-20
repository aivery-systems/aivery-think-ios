import SwiftUI

// AiVery interactive accent (amber) — see ChatComposerView for the rationale.
private let aiveryAccent = Color.aiveryAccent

struct ChatView: View {
    @ObservedObject var vm: ChatViewModel
    // Backs the chip-tap memory detail sheet; list stays empty — update/restore
    // guards in the VM no-op on ids outside it, the HTTP calls still fire.
    @StateObject private var chatMemoryVM = MemoryBrowserViewModel()
    @StateObject private var conn = ConnectionMonitor.shared
    @StateObject private var capabilities = ModelCapabilitiesStore.shared
    @ObservedObject private var settings = UserSettings.shared

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                // Layer 1: surface-recessed background + slow-orbit gradient orbs
                ChatBackgroundView()
                    .onTapGesture {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }

                // Layer 2: plexus particle mesh
                if settings.showPlexus {
                    PlexusView(
                        retrievedCount: vm.plexusRetrievedCount,
                        writtenCount: vm.plexusWrittenCount
                    )
                }

                // Message list — its own view, so composer keystrokes never touch it
                MessageListView(vm: vm)

                // Floating input bar — owns the draft text
                ChatComposerView(vm: vm)
            }
            .overlay(alignment: .top) {
                if conn.status == .offline { offlineBanner }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: conn.status)
            .navigationTitle("Think")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text("Think").font(.headline)
                        if vm.conversationRecallOnly || navConversationTitle != nil {
                            HStack(spacing: 3) {
                                if vm.conversationRecallOnly {
                                    Image(systemName: "eye.slash")
                                        .font(.caption2)
                                    Text("Recall Only")
                                        .font(.caption2)
                                    if navConversationTitle != nil {
                                        Text("·").font(.caption2)
                                    }
                                }
                                if let title = navConversationTitle {
                                    Text(title)
                                        .font(.caption2)
                                        .lineLimit(1)
                                }
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        vm.startNewChat()   // fires its own crisp haptic
                    } label: {
                        Label("New Chat", systemImage: "square.and.pencil")
                            .labelStyle(.iconOnly)
                            .foregroundStyle(settings.isAivery ? AnyShapeStyle(aiveryAccent) : AnyShapeStyle(.primary))
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        vm.showRetrievalSheet = true
                    } label: {
                        Label("Memories Retrieved", systemImage: "sparkles")
                            .labelStyle(.iconOnly)
                            .foregroundStyle(vm.retrievedMemories.isEmpty
                                             ? AnyShapeStyle(.tertiary)
                                             : (settings.isAivery ? AnyShapeStyle(aiveryAccent) : AnyShapeStyle(.primary)))
                    }
                    .disabled(vm.retrievedMemories.isEmpty)
                }
            }
            .toolbarBackground(.thinMaterial, for: .navigationBar)
            .task { await vm.loadHistory() }
            .task { await capabilities.refresh() }
            .task { vm.requestPermissionsIfNeeded() }
            .sheet(isPresented: $vm.showRetrievalSheet) {
                MemoryRetrievalSheetView(
                    stages: vm.retrievalStages,
                    memories: vm.retrievedMemories
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.regularMaterial)
            }
            .sheet(item: $vm.selectedMemory) { memory in
                NavigationStack {
                    MemoryDetailView(memory: memory, vm: chatMemoryVM)
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .alert("Error", isPresented: .constant(vm.errorMessage != nil), actions: {
                Button("OK") { vm.errorMessage = nil }
            }, message: {
                Text(vm.errorMessage ?? "")
            })
        }
    }

    // Active conversation's name for the nav subtitle: server title if known, else the
    // first user message, capped so it never crowds the bar.
    private var navConversationTitle: String? {
        let raw = vm.conversationTitle ?? vm.messages.first(where: { $0.isUser })?.content
        guard let raw else { return nil }
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        let cap = 28
        return t.count > cap ? String(t.prefix(cap)).trimmingCharacters(in: .whitespaces) + "…" : t
    }

    private var offlineBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash").font(.footnote.weight(.semibold))
            Text("Can't reach \(conn.host)")
                .font(.footnote).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 8)
            Button("Retry") { Task { await conn.check() } }
                .font(.footnote.weight(.semibold))
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.red.opacity(0.4), lineWidth: 1))
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
