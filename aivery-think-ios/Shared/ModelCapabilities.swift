import Foundation
import Combine

// What the active chat model supports, from Cortex POST /api/models/capabilities.
// A nil flag means unknown (not loaded, or Cortex couldn't tell) — treated as allowed,
// so only an explicit false hides a control.
struct ModelCapabilities: Decodable {
    let model: String
    let vision: Bool?
    let thinking: Bool?
    let tools: Bool?
}

// Same provider override fields as CortexChatRequest; all nil = server default model.
private struct ModelCapabilitiesRequest: Encodable {
    let provider_type: String?
    let provider_url: String?
    let api_key: String?
    let model: String?

    init(provider: ProviderSettings?) {
        if let p = provider, p.enabled, !p.baseUrl.isEmpty {
            provider_type = p.type
            provider_url = p.baseUrl
            api_key = p.apiKey
            model = p.model
        } else {
            provider_type = nil
            provider_url = nil
            api_key = nil
            model = nil
        }
    }
}

@MainActor
final class ModelCapabilitiesStore: ObservableObject {
    static let shared = ModelCapabilitiesStore()

    @Published private(set) var capabilities: ModelCapabilities?

    var supportsVision: Bool { capabilities?.vision != false }
    var supportsThinking: Bool { capabilities?.thinking != false }

    // Call on launch and whenever the provider override is saved.
    func refresh() async {
        let api = APIClient.shared
        var req = URLRequest(url: api.cortexURL.appendingPathComponent("/api/models/capabilities"))
        req.httpMethod = "POST"
        req.timeoutInterval = 15
        for (k, v) in api.commonHeaders() { req.setValue(v, forHTTPHeaderField: k) }
        do {
            req.httpBody = try JSONEncoder().encode(ModelCapabilitiesRequest(provider: ProviderSettingsLocal.load()))
            let (data, response) = try await URLSession.shared.data(for: req)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { capabilities = nil; return }
            capabilities = try JSONDecoder().decode(ModelCapabilities.self, from: data)
        } catch {
            capabilities = nil
        }
    }
}
