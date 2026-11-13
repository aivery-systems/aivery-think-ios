import Foundation
import Combine
import UIKit
import CoreLocation

@MainActor
final class ChatViewModel: ObservableObject {
    private let api = APIClient.shared
    @Published var messages: [MessageRecord] = []
    @Published var streamingText = ""
    @Published var streamingThinking = ""
    @Published var streamingNotes: [String] = []
    @Published var isStreaming = false
    // True between response_complete (all visible text emitted) and done (memory writes
    // drained server-side) — the caret stops and a "saving memories…" hint shows.
    @Published var memoryPhase = false
    // Memories written during the in-flight turn — rendered as tappable chips.
    @Published var streamingMemories: [WrittenMemoryRef] = []
    // Memories queued for background writing (this conversation). Chips render under the
    // message they belong to — placeholder until the job reaches each item, then saved.
    @Published var memoryJobs: [QueuedMemoryJob] = []
    private var memoryJobsPoll: Task<Void, Never>?
    // The open conversation ends in a recent prompt whose reply is still generating server-side
    // (the user left mid-turn; Cortex finishes it detached). Shows the thinking indicator while
    // the history is polled for the reply.
    @Published var awaitingReply = false
    private var awaitReplyTask: Task<Void, Never>?
    // Background grace for an in-flight turn: iOS suspends the stream shortly after the app
    // leaves the foreground, freezing the Live Activity mid-phase. This buys ~30s to finish.
    private var turnBackgroundTask: UIBackgroundTaskIdentifier = .invalid
    // Cortex has answered this turn at least once — so it has the prompt and will finish
    // the turn even if the connection drops from here on.
    private var turnAccepted = false
    // Stored message id of the in-flight turn, from memory_queued — the local assistant
    // message adopts it so queued chips attach before the server sync swaps ids.
    private var streamingMessageId: String?
    // A chip was tapped; non-nil presents the memory detail sheet.
    @Published var selectedMemory: MemoryRecord?
    @Published var retrievalStages: [RetrievalStageEvent] = []
    @Published var retrievedMemories: [RetrievedMemory] = []
    @Published var showRetrievalSheet = false
    @Published var errorMessage: String?
    // Reasoning only goes out when the model can do it (capabilities from Cortex).
    private var thinkMode: Bool { UserSettings.shared.enableReasoning && ModelCapabilitiesStore.shared.supportsThinking }
    // Plexus triggers — each increment fires an effect in PlexusView
    @Published var plexusRetrievedCount: Int = 0
    @Published var plexusWrittenCount: Int = 0

    // Active conversation (persisted across launches)
    @Published var conversationId: String? = UserDefaults.standard.string(forKey: "activeConversationId") {
        didSet { UserDefaults.standard.set(conversationId, forKey: "activeConversationId") }
    }
    // Display name for the active conversation (nil = fresh/untitled chat).
    @Published var conversationTitle: String?
    // Recall Only: the active conversation never creates/updates memories, but still
    // recalls existing ones and its own message history. Set at creation, immutable after.
    // Persisted alongside conversationId — without this, an app relaunch (iOS backgrounding
    // the process, force-quit, etc.) restores conversationId correctly but silently resets
    // this to false, and the user resumes chatting with memory-write suppression disabled
    // in what still looks like the same recall-only conversation.
    @Published var conversationRecallOnly: Bool = UserDefaults.standard.bool(forKey: "activeConversationRecallOnly") {
        didSet { UserDefaults.standard.set(conversationRecallOnly, forKey: "activeConversationRecallOnly") }
    }

    private let sseClient = SSEClient()
    private let location = LocationManager.shared

    // MARK: – Send

    func sendMessage(_ text: String, image: UIImage? = nil) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || image != nil, !isStreaming else { return }

        // Ensure a conversation exists (titled from the first message)
        await ensureConversation(firstMessage: trimmed.isEmpty ? "📷 Image" : trimmed)

        // Append user message — stays visible even on error. Keep the sent image on it
        // (transient, user's eyes only) so it shows in their bubble.
        messages.append(MessageRecord(
            id: UUID().uuidString,
            role: "user",
            content: trimmed,
            created_at: ISO8601DateFormatter().string(from: Date()),
            localImage: image
        ))
        Haptics.tapMedium()
        // Image with no caption: send a default prompt so the model has text to act on
        // (an empty text part errors); the bubble still shows just the image.
        let prompt = (trimmed.isEmpty && image != nil) ? "What's in this image?" : trimmed
        streamAssistant(userText: prompt, image: image, coordinate: location.coordinate)
    }

    // Re-send a user message (drops everything after it, then re-streams).
    func retryUser(_ userMessage: MessageRecord) async {
        guard !isStreaming, userMessage.isUser,
              let idx = messages.firstIndex(where: { $0.id == userMessage.id }) else { return }
        if idx + 1 < messages.count { messages.removeSubrange((idx + 1)..<messages.count) }
        Haptics.tapLight()
        streamAssistant(userText: stripThink(userMessage.content), image: nil)
    }

    // Regenerate the response to the user message preceding this assistant message.
    func regenerate(_ assistantMessage: MessageRecord) async {
        guard !isStreaming,
              let idx = messages.firstIndex(where: { $0.id == assistantMessage.id }),
              idx > 0, messages[idx - 1].isUser else { return }
        let userText = messages[idx - 1].content
        // Best-effort: delete the stale assistant turn server-side
        if let cid = conversationId { await deleteServerMessage(cid: cid, mid: assistantMessage.id) }
        messages.removeSubrange(idx..<messages.count)
        Haptics.tapLight()
        streamAssistant(userText: stripThink(userText), image: nil)
    }

    // Builds the Cortex request from current state and starts streaming.
    // The current user message must already be the last item in `messages`.
    private func streamAssistant(userText: String, image: UIImage? = nil, coordinate: (lat: Double, lon: Double)? = nil) {
        retrievalStages = []
        retrievedMemories = []

        let url = api.cortexURL.appendingPathComponent("/api/agent/chat")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        for (k, v) in api.commonHeaders() { req.setValue(v, forHTTPHeaderField: k) }
        let history = messages.dropLast().suffix(20).map {
            HistoryMessage(role: $0.role, content: stripThink($0.content))
        }

        do {
            let body = CortexChatRequest(
                message: userText,
                agentId: api.agentId,
                think: thinkMode,
                conversationId: conversationId,
                history: Array(history),
                systemPrompt: ChatPrefsLocal.systemPrompt,
                chatStyle: ChatPrefsLocal.chatStyle,
                provider: ProviderSettingsLocal.load(),
                // Never send an image the model would reject (Ollama 400s on non-vision models).
                image: ModelCapabilitiesStore.shared.supportsVision ? image : nil,
                latitude: coordinate?.lat,
                longitude: coordinate?.lon,
                skipMemoryWrite: conversationRecallOnly
            )
            req.httpBody = try JSONEncoder().encode(body)
        } catch {
            errorMessage = "Failed to encode request."
            return
        }

        stopAwaitingReply()
        isStreaming = true
        streamingText = ""
        streamingThinking = ""
        streamingNotes = []
        streamingMemories = []
        streamingMessageId = nil
        memoryPhase = false
        LiveActivityManager.shared.start(agentId: api.agentId)
        turnAccepted = false
        beginTurnBackgroundTask()
        startSSE(request: req)
    }

    private func beginTurnBackgroundTask() {
        endTurnBackgroundTask()
        turnBackgroundTask = UIApplication.shared.beginBackgroundTask(withName: "chat-turn") { [weak self] in
            // Out of background time: the stream is about to be suspended. The turn keeps
            // running on the server (Cortex finishes it detached), so don't leave the Live
            // Activity frozen on "Recalling" — end it; the reply loads on return.
            Task { @MainActor [weak self] in
                LiveActivityManager.shared.end()
                self?.endTurnBackgroundTask()
            }
        }
    }

    private func endTurnBackgroundTask() {
        guard turnBackgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(turnBackgroundTask)
        turnBackgroundTask = .invalid
    }

    // The user left a chat mid-turn (opened another, or started a new one). The turn keeps
    // running server-side; this client just stops following it.
    private func detachFromTurn() {
        sseClient.cancel()
        isStreaming = false
        LiveActivityManager.shared.end()
        endTurnBackgroundTask()
    }

    func cancelStream() {
        sseClient.cancel()
        finalizeStream()
    }

    // MARK: – SSE

    private func startSSE(request: URLRequest) {
        sseClient.onEvent = { [weak self] event in
            Task { @MainActor [weak self] in self?.handle(event: event) }
        }
        sseClient.onComplete = { [weak self] in
            Task { @MainActor [weak self] in self?.finalizeStream() }
        }
        sseClient.onHTTPError = { [weak self] code, message in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let wasMidTurn = self.isStreaming && self.turnAccepted
                self.isStreaming = false
                LiveActivityManager.shared.end()
                self.endTurnBackgroundTask()
                // Connection dropped after the turn was under way (typically the app was
                // suspended in the background): Cortex finishes and stores it regardless, so
                // wait for the stored reply instead of reporting a network error.
                if code < 0, wasMidTurn, let cid = self.conversationId {
                    self.streamingText = ""
                    self.streamingThinking = ""
                    self.streamingNotes = []
                    self.memoryPhase = false
                    self.awaitReplyIfPending(conversationId: cid)
                    return
                }
                switch code {
                case 401: self.errorMessage = "Invalid API key (401). Check Settings."
                case 403: self.errorMessage = "Forbidden (403). Your API key may lack required scopes."
                case let c where c < 0:   // NSURLError transport failure
                    ConnectionMonitor.shared.noteOffline()
                    self.errorMessage = Self.friendlyTransportError(code: c, host: self.api.cortexURL.host ?? "the server")
                default:  self.errorMessage = "Server error (HTTP \(code)).\n\(message)"
                }
            }
        }
        sseClient.connect(with: request)
    }

    private func handle(event: SSEEvent) {
        turnAccepted = true
        switch event {
        case .chunk(let text):
            if streamingText.isEmpty { LiveActivityManager.shared.update(phase: "Responding") }
            streamingText += text
        case .thinkChunk(let text):
            streamingThinking += text
        case .retrievalStage(let stage):
            retrievalStages.append(stage)
            showRetrievalSheet = true
        case .memoryResult(let mems):
            retrievedMemories = mems
            plexusRetrievedCount += mems.count
            LiveActivityManager.shared.update(phase: "Recalling", detail: "\(mems.count) " + (mems.count == 1 ? "memory" : "memories"))
        case .memoryWritten(let ref):
            plexusWrittenCount += 1
            Haptics.success()
            NotificationManager.shared.scheduleMemoryStored(agentId: api.agentId)
            if let ref, !streamingMemories.contains(where: { $0.id == ref.id }) {
                streamingMemories.append(ref)
            }
        case .memoryQueued(let job):
            if job.messageId != nil { streamingMessageId = job.messageId }
            if !memoryJobs.contains(where: { $0.jobId == job.jobId }) {
                memoryJobs.append(job)
            }
            pollMemoryJobs()
        case .responseComplete:
            memoryPhase = true
            LiveActivityManager.shared.update(phase: "Saving memories")
        case .agentNote(let note):
            let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, !streamingNotes.contains(trimmed) {
                streamingNotes.append(trimmed)
            }
        case .done:
            finalizeStream()
        case .error:
            errorMessage = "An error occurred during response generation."
            finalizeStream()
        }
    }

    private func finalizeStream() {
        guard isStreaming else { return }
        isStreaming = false
        LiveActivityManager.shared.end()
        endTurnBackgroundTask()

        if !streamingText.isEmpty {
            // Embed notes + written-memory refs so the chips survive reload.
            let content = MemoryRefs.embed(streamingMemories,
                                           into: AgentNotes.embed(streamingNotes, into: streamingText))
            messages.append(MessageRecord(
                id: streamingMessageId ?? UUID().uuidString,
                role: "assistant",
                content: content,
                created_at: ISO8601DateFormatter().string(from: Date())
            ))
            Haptics.success()
            ConnectionMonitor.shared.noteOnline()   // a successful turn proves reachability
            // Quietly swap local-id messages for server-id ones so Retry/Branch/Delete work.
            let turnNotes = streamingNotes
            let turnRefs = streamingMemories
            Task { await syncMessagesFromServer(expecting: messages.count, notes: turnNotes, refs: turnRefs) }
        } else if streamingThinking.isEmpty && errorMessage == nil {
            errorMessage = "No response received. Check Cortex is running and your provider/model in Settings.\nCortex: \(api.cortexURL)"
        }

        streamingText = ""
        streamingThinking = ""
        streamingNotes = []
        streamingMemories = []
        memoryPhase = false
    }

    // After a turn, Cortex logs both messages to Fabric asynchronously. Poll briefly
    // until the server has caught up, then replace local copies so every message
    // carries its real server id (needed for delete/branch/retry).
    private func syncMessagesFromServer(expecting localCount: Int, notes: [String] = [], refs: [WrittenMemoryRef] = []) async {
        guard let cid = conversationId else { return }
        for attempt in 0..<4 {
            try? await Task.sleep(nanoseconds: attempt == 0 ? 700_000_000 : 1_000_000_000)
            guard !isStreaming, conversationId == cid else { return }  // a new turn started
            guard var server: [MessageRecord] = try? await api.request("/api/conversations/\(cid)/messages") else { return }
            if server.count >= localCount {
                // Cortex now embeds notes + memory refs when logging the turn to Fabric,
                // but guard-and-re-attach anyway (older Cortex, or a race) so chips
                // never vanish on sync — without ever duplicating a block.
                if let lastAssistantIdx = server.lastIndex(where: { !$0.isUser }) {
                    let m = server[lastAssistantIdx]
                    var content = m.content
                    if !notes.isEmpty, AgentNotes.extract(from: content).notes.isEmpty {
                        content = AgentNotes.embed(notes, into: content)
                    }
                    if !refs.isEmpty, MemoryRefs.extract(from: content).refs.isEmpty {
                        content = MemoryRefs.embed(refs, into: content)
                    }
                    if content != m.content {
                        server[lastAssistantIdx] = MessageRecord(
                            id: m.id, role: m.role,
                            content: content,
                            created_at: m.created_at)
                    }
                }

                // Preserve user-sent images (eyes only) across the swap, in order.
                let localImages = messages.filter(\.isUser).map(\.localImage)
                var imgIdx = 0
                for i in server.indices where server[i].isUser {
                    if imgIdx < localImages.count {
                        server[i].localImage = localImages[imgIdx]
                        imgIdx += 1
                    }
                }

                messages = server
                return
            }
        }
    }

    // Load the active conversation's messages so past turns appear on launch.
    func loadHistory() async {
        guard messages.isEmpty, let cid = conversationId else { return }
        await loadMessages(conversationId: cid)
    }

    func loadMessages(conversationId cid: String) async {
        do {
            let msgs: [MessageRecord] = try await api.request("/api/conversations/\(cid)/messages")
            messages = msgs
        } catch {
            messages = []
        }
        await restoreMemoryJobs(conversationId: cid)
        awaitReplyIfPending(conversationId: cid)
    }

    private func awaitReplyIfPending(conversationId cid: String) {
        stopAwaitingReply()
        guard let last = messages.last, last.isUser,
              let sent = last.date, Date().timeIntervalSince(sent) < 300 else { return }
        awaitingReply = true
        awaitReplyTask = Task { [weak self] in
            // Up to ~3 minutes: long enough for a slow model, short enough that a failed
            // turn doesn't leave the indicator spinning.
            for _ in 0..<90 {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard let self, !Task.isCancelled, !self.isStreaming, self.conversationId == cid else { return }
                guard let server: [MessageRecord] = try? await self.api.request("/api/conversations/\(cid)/messages") else { continue }
                if let last = server.last, !last.isUser {
                    self.messages = server
                    await self.restoreMemoryJobs(conversationId: cid)
                    break
                }
            }
            self?.awaitingReply = false
        }
    }

    private func stopAwaitingReply() {
        awaitReplyTask?.cancel()
        awaitReplyTask = nil
        awaitingReply = false
    }

    // MARK: - Queued memory writes

    // A reload mid-write would otherwise lose the placeholders: fetch the conversation's
    // unfinished jobs and resume polling them.
    private func restoreMemoryJobs(conversationId cid: String) async {
        memoryJobs = []
        guard let list: QueuedMemoryJobList = try? await api.request("/memory/write-queue/conversation/\(cid)"),
              conversationId == cid else { return }
        memoryJobs = list.jobs ?? []
        pollMemoryJobs()
    }

    private func pollMemoryJobs() {
        guard memoryJobsPoll == nil, memoryJobs.contains(where: { !$0.isSettled }) else { return }
        memoryJobsPoll = Task { [weak self] in
            var failures: [String: Int] = [:]
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard let self else { return }
                let pending = self.memoryJobs.filter { !$0.isSettled }
                if pending.isEmpty { break }
                for job in pending {
                    do {
                        let updated: QueuedMemoryJob = try await self.api.request("/memory/write-queue/\(job.jobId)")
                        failures[job.jobId] = nil
                        self.applyMemoryJobUpdate(updated)
                    } catch {
                        // Transient errors retry; a job that keeps failing (e.g. deleted) is given up on.
                        let count = (failures[job.jobId] ?? 0) + 1
                        failures[job.jobId] = count
                        if count >= 5 { self.markMemoryJobFailed(job.jobId) }
                    }
                }
            }
            self?.memoryJobsPoll = nil
        }
    }

    private func applyMemoryJobUpdate(_ updated: QueuedMemoryJob) {
        guard let idx = memoryJobs.firstIndex(where: { $0.jobId == updated.jobId }) else { return }
        let previous = memoryJobs[idx]
        let newlyWritten = updated.items.filter { item in
            item.status == .written && previous.items.first(where: { $0.index == item.index })?.status != .written
        }.count
        var merged = updated
        if merged.items.isEmpty { merged.items = previous.items }
        memoryJobs[idx] = merged
        if newlyWritten > 0 {
            plexusWrittenCount += newlyWritten
            Haptics.success()
        }
    }

    private func markMemoryJobFailed(_ jobId: String) {
        guard let idx = memoryJobs.firstIndex(where: { $0.jobId == jobId }) else { return }
        for i in memoryJobs[idx].items.indices where memoryJobs[idx].items[i].status == .pending {
            memoryJobs[idx].items[i].status = .failed
        }
    }

    // Open an existing conversation from the list.
    func open(conversation: Conversation) async {
        detachFromTurn()
        conversationId = conversation.id
        conversationTitle = conversation.title
        conversationRecallOnly = conversation.recall_only
        retrievalStages = []
        retrievedMemories = []
        await loadMessages(conversationId: conversation.id)
    }

    // Create a conversation lazily on the first message of a fresh chat. recallOnly comes
    // from conversationRecallOnly, already primed by startNewChat(recallOnly:).
    private func ensureConversation(firstMessage: String) async {
        guard conversationId == nil else { return }
        let title = String(firstMessage.prefix(48))
        struct Body: Encodable { let title: String; let recallOnly: Bool }
        do {
            let resp: CreateConversationResponse = try await api.request(
                "/api/conversations", method: "POST", body: Body(title: title, recallOnly: conversationRecallOnly))
            conversationId = resp.id
            conversationTitle = title
        } catch {
            // Leave nil — message still streams; just won't persist to a conversation.
        }
    }

    private func stripThink(_ content: String) -> String {
        // Strip reasoning, agent-action tags (note/remember), and the persisted
        // <agent_notes>/<memory_refs> blocks so prior turns fed back to the model
        // never contain its own control tags.
        let noNotes = AgentNotes.extract(from: content).content
        let noRefs = MemoryRefs.extract(from: noNotes).content
        return AgentActions.plainText(from: ThinkText.split(noRefs).response)
    }

    // Chip tap: fetch the memory and present the detail sheet.
    func openMemory(id: String) async {
        do {
            let record: MemoryRecord = try await api.request("/api/memories/\(id)")
            selectedMemory = record
        } catch {
            errorMessage = "Couldn't load that memory — it may have been deleted or replaced by an edit."
        }
    }

    // Turn raw NSURLError codes into something a human can act on.
    static func friendlyTransportError(code: Int, host: String) -> String {
        switch code {
        case NSURLErrorNotConnectedToInternet:
            return "You're offline. Check your internet connection."
        case NSURLErrorTimedOut:
            return "\(host) took too long to respond. It may be waking up or under load — try again."
        case NSURLErrorCannotConnectToHost:
            return "Can't reach \(host). Make sure the API is running — and if you're on Tailscale, that both devices are on the tailnet."
        case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed:
            return "Can't find \(host). Check the API Host in Settings."
        case NSURLErrorNetworkConnectionLost:
            return "The connection dropped mid-response. Tap send to retry."
        case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateUntrusted:
            return "Secure connection to \(host) failed."
        default:
            return "Network error (\(code)) reaching \(host)."
        }
    }

    // Delete a single message (optimistic; best-effort server delete).
    func delete(_ message: MessageRecord) async {
        messages.removeAll { $0.id == message.id }
        Haptics.tapMedium()
        if let cid = conversationId { await deleteServerMessage(cid: cid, mid: message.id) }
    }

    // Fork a new conversation containing everything up to this message, then switch to it.
    func branch(from message: MessageRecord) async {
        guard let cid = conversationId else { return }
        struct Body: Encodable { let messageId: String; let title: String? }
        struct Resp: Decodable { let id: String }
        do {
            let title = messages.first(where: { $0.isUser }).map { String($0.content.prefix(48)) }
            let resp: Resp = try await api.request(
                "/api/conversations/\(cid)/branch", method: "POST",
                body: Body(messageId: message.id, title: title))
            Haptics.success()
            conversationId = resp.id
            await loadMessages(conversationId: resp.id)
        } catch {
            errorMessage = "Couldn't branch this conversation."
        }
    }

    private func deleteServerMessage(cid: String, mid: String) async {
        try? await api.requestEmpty(
            "/api/conversations/\(cid)/messages/\(mid)", method: "DELETE")
    }

    func startNewChat(recallOnly: Bool = false) {
        detachFromTurn()
        messages = []
        conversationId = nil   // a fresh conversation is created on the next message
        conversationTitle = nil
        conversationRecallOnly = recallOnly
        streamingText = ""
        streamingThinking = ""
        streamingNotes = []
        streamingMemories = []
        memoryPhase = false
        isStreaming = false
        retrievalStages = []
        retrievedMemories = []
        memoryJobsPoll?.cancel()
        memoryJobsPoll = nil
        memoryJobs = []
        stopAwaitingReply()
        Haptics.tapRigid()
    }

    func requestPermissionsIfNeeded() {
        location.requestWhenInUse()
        location.startUpdating()
        NotificationManager.shared.requestAuthorization()
    }
}
