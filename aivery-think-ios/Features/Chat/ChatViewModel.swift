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
    @Published var retrievalStages: [RetrievalStageEvent] = []
    @Published var retrievedMemories: [RetrievedMemory] = []
    @Published var showRetrievalSheet = false
    @Published var errorMessage: String?
    private var thinkMode: Bool { UserSettings.shared.enableReasoning }
    // Plexus triggers — each increment fires an effect in PlexusView
    @Published var plexusRetrievedCount: Int = 0
    @Published var plexusWrittenCount: Int = 0

    // Active conversation (persisted across launches)
    @Published var conversationId: String? = UserDefaults.standard.string(forKey: "activeConversationId") {
        didSet { UserDefaults.standard.set(conversationId, forKey: "activeConversationId") }
    }
    // Display name for the active conversation (nil = fresh/untitled chat).
    @Published var conversationTitle: String?

    private let sseClient = SSEClient()
    private let location = LocationManager.shared

    // MARK: – Send

    func sendMessage(_ text: String, image: UIImage? = nil) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || image != nil, !isStreaming else { return }

        // Ensure a conversation exists (titled from the first message)
        await ensureConversation(firstMessage: trimmed.isEmpty ? "📷 Image" : trimmed)

        // Append user message — stays visible even on error
        messages.append(MessageRecord(
            id: UUID().uuidString,
            role: "user",
            content: trimmed,
            created_at: ISO8601DateFormatter().string(from: Date())
        ))
        Haptics.tapMedium()
        streamAssistant(userText: trimmed, image: image, coordinate: location.coordinate)
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
                image: image,
                latitude: coordinate?.lat,
                longitude: coordinate?.lon
            )
            req.httpBody = try JSONEncoder().encode(body)
        } catch {
            errorMessage = "Failed to encode request."
            return
        }

        isStreaming = true
        streamingText = ""
        streamingThinking = ""
        streamingNotes = []
        LiveActivityManager.shared.start(agentId: api.agentId)
        startSSE(request: req)
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
                self.isStreaming = false
                LiveActivityManager.shared.end()
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
        case .memoryWritten:
            plexusWrittenCount += 1
            Haptics.success()
            NotificationManager.shared.scheduleMemoryStored(agentId: api.agentId)
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

        if !streamingText.isEmpty {
            // Embed the agent's action notes so the "memory saved" chip survives reload.
            let content = AgentNotes.embed(streamingNotes, into: streamingText)
            messages.append(MessageRecord(
                id: UUID().uuidString,
                role: "assistant",
                content: content,
                created_at: ISO8601DateFormatter().string(from: Date())
            ))
            Haptics.success()
            ConnectionMonitor.shared.noteOnline()   // a successful turn proves reachability
            // Quietly swap local-id messages for server-id ones so Retry/Branch/Delete work.
            let turnNotes = streamingNotes
            Task { await syncMessagesFromServer(expecting: messages.count, notes: turnNotes) }
        } else if streamingThinking.isEmpty && errorMessage == nil {
            errorMessage = "No response received. Check Cortex is running and your provider/model in Settings.\nCortex: \(api.cortexURL)"
        }

        streamingText = ""
        streamingThinking = ""
        streamingNotes = []
    }

    // After a turn, Cortex logs both messages to Fabric asynchronously. Poll briefly
    // until the server has caught up, then replace local copies so every message
    // carries its real server id (needed for delete/branch/retry).
    private func syncMessagesFromServer(expecting localCount: Int, notes: [String] = []) async {
        guard let cid = conversationId else { return }
        for attempt in 0..<4 {
            try? await Task.sleep(nanoseconds: attempt == 0 ? 700_000_000 : 1_000_000_000)
            guard !isStreaming, conversationId == cid else { return }  // a new turn started
            guard var server: [MessageRecord] = try? await api.request("/api/conversations/\(cid)/messages") else { return }
            if server.count >= localCount {
                // Server doesn't persist agent notes — re-attach them to the latest
                // assistant message so the "memory saved" chip doesn't vanish on sync.
                if !notes.isEmpty,
                   let lastAssistantIdx = server.lastIndex(where: { !$0.isUser }) {
                    let m = server[lastAssistantIdx]
                    server[lastAssistantIdx] = MessageRecord(
                        id: m.id, role: m.role,
                        content: AgentNotes.embed(notes, into: m.content),
                        created_at: m.created_at)
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
    }

    // Open an existing conversation from the list.
    func open(conversation: Conversation) async {
        sseClient.cancel()
        isStreaming = false
        conversationId = conversation.id
        conversationTitle = conversation.title
        retrievalStages = []
        retrievedMemories = []
        await loadMessages(conversationId: conversation.id)
    }

    // Create a conversation lazily on the first message of a fresh chat.
    private func ensureConversation(firstMessage: String) async {
        guard conversationId == nil else { return }
        let title = String(firstMessage.prefix(48))
        struct Body: Encodable { let title: String }
        do {
            let resp: CreateConversationResponse = try await api.request(
                "/api/conversations", method: "POST", body: Body(title: title))
            conversationId = resp.id
            conversationTitle = title
        } catch {
            // Leave nil — message still streams; just won't persist to a conversation.
        }
    }

    private func stripThink(_ content: String) -> String {
        // Strip reasoning AND agent-action tags (note/remember) so prior turns fed back
        // to the model never contain its own control tags.
        AgentActions.plainText(from: ThinkText.split(content).response)
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

    func startNewChat() {
        sseClient.cancel()
        messages = []
        conversationId = nil   // a fresh conversation is created on the next message
        conversationTitle = nil
        streamingText = ""
        streamingThinking = ""
        streamingNotes = []
        isStreaming = false
        retrievalStages = []
        retrievedMemories = []
        Haptics.tapRigid()
    }

    func requestPermissionsIfNeeded() {
        location.requestWhenInUse()
        location.startUpdating()
        NotificationManager.shared.requestAuthorization()
    }
}
