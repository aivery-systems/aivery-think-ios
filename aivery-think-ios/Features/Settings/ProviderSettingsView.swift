import SwiftUI

private enum VerifyState: Equatable { case idle, loading, ok, error(String) }
private enum SaveState: Equatable { case idle, saving, saved }

struct ProviderSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var enabled = false
    @State private var type    = "ollama"
    @State private var url     = ""
    @State private var apiKey  = ""
    @State private var model   = ""
    @State private var models: [String] = []
    @State private var verify: VerifyState = .idle
    @State private var save:   SaveState   = .idle

    var body: some View {
        Form {
            Section {
                Toggle("Use custom provider", isOn: $enabled.animation())
                    .onChange(of: enabled) { verify = .idle; models = [] }
            } footer: {
                Text("Route chat through your own Ollama or OpenAI-compatible endpoint instead of the default.")
            }

            if enabled {
                Section("Connection") {
                    Picker("Provider", selection: $type) {
                        Text("Ollama").tag("ollama")
                        Text("OpenAI-compatible").tag("openai")
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: type) { verify = .idle; models = [] }

                    HStack {
                        Text("Base URL").foregroundStyle(.secondary)
                        TextField(type == "ollama" ? "http://…:11434" : "https://api.openai.com", text: $url)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .multilineTextAlignment(.trailing)
                            .onChange(of: url) { verify = .idle; models = [] }
                    }

                    HStack {
                        Text(type == "ollama" ? "API Key" : "API Key")
                            .foregroundStyle(.secondary)
                        SecureField(type == "ollama" ? "optional" : "sk-••••", text: $apiKey)
                            .multilineTextAlignment(.trailing)
                    }

                    HStack {
                        Button { Task { await runVerify() } } label: {
                            if verify == .loading { ProgressView().scaleEffect(0.8) }
                            else { Text("Verify connection") }
                        }
                        .disabled(url.isEmpty || verify == .loading)
                        Spacer()
                        switch verify {
                        case .ok: Label("Connected", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green).font(.caption)
                        case .error(let m): Text(m).foregroundStyle(.red).font(.caption).lineLimit(2)
                        default: EmptyView()
                        }
                    }
                }

                if !models.isEmpty {
                    Section("Model") {
                        Picker("Model", selection: $model) {
                            Text("Select…").tag("")
                            ForEach(models, id: \.self) { Text($0).tag($0) }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    }
                }
            }
        }
        .navigationTitle("Model Provider")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    persist(); UINotificationFeedbackGenerator().notificationOccurred(.success); dismiss()
                } label: {
                    if save == .saving { ProgressView() } else { Text("Save").fontWeight(.semibold) }
                }
                .disabled(enabled && (url.isEmpty || model.isEmpty))
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard let ps = ProviderSettingsLocal.load() else { return }
        enabled = ps.enabled; type = ps.type; url = ps.baseUrl
        apiKey = ps.apiKey ?? ""; model = ps.model
    }

    private func persist() {
        ProviderSettingsLocal.save(ProviderSettings(
            enabled: enabled, type: type, baseUrl: url,
            apiKey: apiKey.isEmpty ? nil : apiKey, model: model))
    }

    private func runVerify() async {
        verify = .loading; models = []
        let body = ProviderSettings(enabled: true, type: type, baseUrl: url,
                                    apiKey: apiKey.isEmpty ? nil : apiKey, model: "")
        do {
            let resp: VerifyResponse = try await APIClient.shared.request(
                "/api/provider-settings/verify", method: "POST", body: body)
            models = resp.models
            if model.isEmpty, let first = resp.models.first { model = first }
            verify = .ok
        } catch APIError.serverError(let code) {
            verify = .error("Server \(code)")
        } catch {
            verify = .error(error.localizedDescription)
        }
    }
}
