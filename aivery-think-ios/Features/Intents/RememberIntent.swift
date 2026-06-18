import AppIntents

/// "Hey Siri, remember … in Aivery" — and a Shortcuts action. Stores a memory directly
/// via the Fabric write endpoint. Runs without launching the app (restores the API key
/// from the Keychain first).
struct RememberIntent: AppIntent {
    static var title: LocalizedStringResource = "Remember in Aivery"
    static var description = IntentDescription("Save a quick memory to your Aivery agent.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Memory", requestValueDialog: "What should Aivery remember?")
    var text: String

    static var parameterSummary: some ParameterSummary {
        Summary("Remember \(\.$text) in Aivery")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard await APIClient.shared.restoreApiKey() else {
            return .result(dialog: "Open Aivery and add your API key first.")
        }
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else {
            return .result(dialog: "There was nothing to remember.")
        }
        do {
            try await APIClient.shared.writeMemory(content: content, source: "siri")
            return .result(dialog: "Saved to Aivery.")
        } catch APIError.unauthorized {
            return .result(dialog: "Your API key was rejected — check it in Aivery's Settings.")
        } catch {
            return .result(dialog: "Couldn't reach Aivery to save that. Try again.")
        }
    }
}

struct AiveryShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RememberIntent(),
            phrases: [
                "Remember this in \(.applicationName)",
                "Add a memory to \(.applicationName)",
                "Save a memory in \(.applicationName)",
            ],
            shortTitle: "Remember",
            systemImageName: "brain.head.profile"
        )
    }
}
